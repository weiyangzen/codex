# chatgpt_client.rs 研究文档

## 场景与职责

`chatgpt_client.rs` 是 `codex-chatgpt` crate 的 HTTP 客户端模块，提供与 **ChatGPT 后端 API** 通信的基础能力。该模块封装了认证令牌的获取、请求构造和响应处理，为其他模块（如 `get_task`、`connectors`）提供统一的 API 调用接口。

### 核心使用场景

1. **任务数据获取**：`get_task.rs` 调用 `/wham/tasks/{task_id}` 获取任务详情
2. **连接器目录查询**：`connectors.rs` 调用 `/connectors/directory/list` 获取应用连接器列表
3. **工作区连接器查询**：为企业/团队账户获取工作区级别的连接器

## 功能点目的

### 1. chatgpt_get_request 标准 GET 请求
提供无超时限制的 GET 请求封装：
- 自动初始化认证令牌
- 构造完整 URL（base_url + path）
- 添加认证头（Bearer token + account-id）
- 自动 JSON 反序列化响应

### 2. chatgpt_get_request_with_timeout 超时控制版本
支持自定义超时时间的 GET 请求：
- 用于目录列表等可能较慢的查询
- 默认超时 60 秒（在 `connectors.rs` 中定义）

### 3. 认证头管理
自动处理两个关键 HTTP 头：
- `Authorization: Bearer {access_token}`
- `chatgpt-account-id: {account_id}`

## 具体技术实现

### 关键流程

```
chatgpt_get_request_with_timeout
├── init_chatgpt_token_from_auth     // 确保令牌已加载
├── create_client                    // 创建 reqwest 客户端
├── 构造完整 URL
├── get_chatgpt_token_data           // 获取令牌数据
├── 验证 account_id 存在
├── 构造请求（认证头 + Content-Type + 可选超时）
├── 发送请求
└── 处理响应
    ├── 成功：解析 JSON
    └── 失败：返回状态码和响应体错误
```

### 数据结构

```rust
// 来自 codex_core::token_data::TokenData
pub struct TokenData {
    pub id_token: IdTokenInfo,       // 包含 chatgpt_user_id, is_workspace_account 等
    pub access_token: String,        // JWT 访问令牌
    pub refresh_token: String,
    pub account_id: Option<String>,  // ChatGPT 账户 ID
}

pub struct IdTokenInfo {
    pub email: Option<String>,
    pub chatgpt_plan_type: Option<PlanType>,  // free/plus/pro/business/enterprise/edu
    pub chatgpt_user_id: Option<String>,
    pub chatgpt_account_id: Option<String>,
    pub raw_jwt: String,
}
```

### 请求构造

```rust
let mut request = client
    .get(&url)
    .bearer_auth(&token.access_token)
    .header("chatgpt-account-id", account_id?)
    .header("Content-Type", "application/json");

if let Some(timeout) = timeout {
    request = request.timeout(timeout);
}
```

### 错误处理

```rust
if response.status().is_success() {
    let result: T = response.json().await?;
    Ok(result)
} else {
    let status = response.status();
    let body = response.text().await.unwrap_or_default();
    anyhow::bail!("Request failed with status {status}: {body}")
}
```

## 关键代码路径与文件引用

### 内部依赖

| 模块 | 路径 | 用途 |
|------|------|------|
| `chatgpt_token` | `chatgpt_token.rs` | 令牌初始化和获取 |

### 外部依赖

| Crate | 模块 | 用途 |
|-------|------|------|
| `codex_core` | `config::Config` | 配置访问 |
| `codex_core` | `default_client::create_client` | HTTP 客户端创建 |
| `anyhow` | `Context` | 错误上下文增强 |

### 调用链

```
chatgpt_client::chatgpt_get_request
├── chatgpt_token::init_chatgpt_token_from_auth
│   ├── AuthManager::new
│   └── auth_manager.auth().await
│       └── 读取 ~/.codex/auth.json
├── chatgpt_token::get_chatgpt_token_data
│   └── CHATGPT_TOKEN.read()
└── codex_core::default_client::create_client
    └── reqwest::Client::new()
```

### 被调用方

```
get_task::get_task
└── chatgpt_get_request::<GetTaskResponse>

connectors::list_all_connectors_with_options
└── chatgpt_get_request_with_timeout::<DirectoryListResponse>
```

## 依赖与外部交互

### 1. ChatGPT 后端 API

基础 URL 来自 `config.chatgpt_base_url`，默认通常是 `https://chatgpt.com`。

### 2. 认证系统

依赖 `codex_core::AuthManager`：
- 从 `~/.codex/auth.json` 读取认证信息
- 支持 `AuthCredentialsStoreMode` 控制凭证存储行为
- 令牌缓存在全局静态变量 `CHATGPT_TOKEN` 中

### 3. HTTP 客户端

使用 `codex_core::default_client::create_client` 创建，通常配置：
- 连接超时
- 重试策略
- TLS 配置

## 风险、边界与改进建议

### 风险点

1. **account_id 缺失**
   - 错误信息提示重新运行 `codex login`
   - 但某些 API 调用可能不需要 account_id
   - 建议：根据 API 端点决定是否为必需

2. **令牌过期**
   - 当前实现不处理 401 响应
   - 令牌过期后需要手动重新登录
   - 建议：自动刷新令牌或提示重新认证

3. **全局状态依赖**
   - 依赖 `CHATGPT_TOKEN` 全局静态变量
   - 多线程环境下可能有问题
   - 建议：考虑使用 `tokio::task_local` 或显式传递

### 边界条件

1. **空 account_id**
   ```rust
   let account_id = token.account_id.ok_or_else(|| {
       anyhow::anyhow!("ChatGPT account ID not available...")
   });
   ```
   某些旧版认证可能没有 account_id

2. **超时为 None**
   - 默认使用 reqwest 的全局超时
   - 可能阻塞 indefinitely

3. **JSON 解析失败**
   - 使用 `context("Failed to parse JSON response")` 增强错误
   - 但原始错误信息可能丢失

### 改进建议

1. **令牌刷新机制**
   ```rust
   // 建议添加
   async fn ensure_token_valid(config: &Config) -> anyhow::Result<()> {
       if token_expired() {
           refresh_token(config).await?;
       }
       Ok(())
   }
   ```

2. **请求重试**
   ```rust
   // 建议添加指数退避重试
   pub(crate) async fn chatgpt_get_request_with_retry<T>(...)
   ```

3. **更好的错误分类**
   ```rust
   pub enum ChatgptError {
       Unauthorized,      // 401
       NotFound,          // 404
       RateLimited,       // 429
       ServerError(u16),  // 5xx
       Network(reqwest::Error),
       Parse(serde_json::Error),
   }
   ```

4. **请求日志**
   - 添加调试日志记录请求 URL 和响应状态
   - 便于问题排查

5. **并发安全**
   - 考虑令牌初始化的竞态条件
   - 当前使用 `RwLock`，但初始化可能重复执行

### 测试建议

当前模块缺乏直接测试，建议添加：
- Mock HTTP 服务器的集成测试
- 令牌过期场景测试
- 错误响应处理测试
