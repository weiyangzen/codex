# client.rs 研究文档

## 场景与职责

`client.rs` 是 `codex-backend-client` crate 的核心实现文件，提供了一个 HTTP 客户端用于与 Codex 后端服务（包括 Codex API 和 ChatGPT WHAM API）进行通信。该客户端封装了所有与云端任务管理相关的 REST API 调用，为上层应用（如 TUI、app-server 和 cloud-tasks-client）提供统一的网络访问接口。

### 核心职责
1. **双后端支持**：同时支持 Codex API (`/api/codex/*`) 和 ChatGPT WHAM API (`/wham/*`) 两种路径风格
2. **认证管理**：支持 Bearer Token 认证和 ChatGPT Account ID 头部
3. **速率限制查询**：获取用户当前的 API 使用配额和限制状态
4. **任务管理**：创建、查询、列出云端任务（Cloud Tasks）
5. **配置获取**：拉取云端托管的配置要求（requirements.toml）

---

## 功能点目的

### 1. RequestError 错误类型
定义了详细的 HTTP 请求错误类型，区分：
- `UnexpectedStatus`：服务器返回非成功状态码，包含完整的请求上下文（method, url, status, content-type, body）
- `Other`：其他 anyhow 错误

提供 `is_unauthorized()` 方法用于快速判断 401 未授权错误，支持上游进行认证恢复流程。

### 2. PathStyle 路径风格枚举
区分两种后端 API 路径风格：
- `CodexApi`：标准 Codex 后端 API，路径前缀 `/api/codex`
- `ChatGptApi`：ChatGPT WHAM API，路径前缀 `/wham`

自动检测逻辑：当 base_url 包含 `/backend-api` 时，判定为 ChatGptApi 风格。

### 3. Client 结构体
核心 HTTP 客户端，包含：
- `base_url`：后端服务基础 URL
- `http`：reqwest HTTP 客户端实例
- `bearer_token`：可选的认证令牌
- `user_agent`：可选的 User-Agent 头部
- `chatgpt_account_id`：可选的 ChatGPT 账户 ID
- `path_style`：路径风格（自动检测或手动指定）

### 4. 主要 API 方法

| 方法 | 功能 | 路径（CodexApi / ChatGptApi）|
|------|------|------------------------------|
| `get_rate_limits` | 获取首选速率限制快照 | `/api/codex/usage` / `/wham/usage` |
| `get_rate_limits_many` | 获取所有速率限制 | 同上 |
| `list_tasks` | 分页列出任务 | `/api/codex/tasks/list` / `/wham/tasks/list` |
| `get_task_details` | 获取任务详情 | `/api/codex/tasks/{id}` / `/wham/tasks/{id}` |
| `list_sibling_turns` | 获取同层 turn 列表 | `/api/codex/tasks/{id}/turns/{turn_id}/sibling_turns` |
| `get_config_requirements_file` | 获取云端配置 | `/api/codex/config/requirements` / `/wham/config/requirements` |
| `create_task` | 创建新任务 | `/api/codex/tasks` / `/wham/tasks` |

---

## 具体技术实现

### 关键流程

#### 1. 客户端构建流程
```rust
// 1. 创建基础客户端
let mut client = Client::new(base_url)?;

// 2. 自动路径风格检测
let path_style = PathStyle::from_base_url(&base_url);

// 3. 从认证信息构建（推荐方式）
let client = Client::from_auth(base_url, &auth)?;
```

#### 2. 请求执行流程
```rust
async fn exec_request(&self, req: RequestBuilder, method: &str, url: &str) 
    -> Result<(String, String)> 
{
    // 1. 发送请求
    // 2. 提取状态码和 content-type
    // 3. 读取响应体
    // 4. 非成功状态码返回 anyhow 错误
    // 5. 返回 (body, content_type)
}
```

#### 3. 速率限制数据处理流程
```rust
fn rate_limit_snapshots_from_payload(payload: RateLimitStatusPayload) 
    -> Vec<RateLimitSnapshot> 
{
    // 1. 提取主速率限制（codex）
    // 2. 提取附加速率限制列表
    // 3. 将内部类型映射为 protocol 类型
    // 4. 计算窗口分钟数（从秒数向上取整）
}
```

### 数据结构

#### Client 结构体
```rust
pub struct Client {
    base_url: String,
    http: reqwest::Client,
    bearer_token: Option<String>,
    user_agent: Option<HeaderValue>,
    chatgpt_account_id: Option<String>,
    path_style: PathStyle,
}
```

#### RequestError 枚举
```rust
pub enum RequestError {
    UnexpectedStatus {
        method: String,
        url: String,
        status: StatusCode,
        content_type: String,
        body: String,
    },
    Other(anyhow::Error),
}
```

### 协议与命令

#### HTTP 头部构造
```rust
fn headers(&self) -> HeaderMap {
    // 1. User-Agent：优先使用自定义，默认 "codex-cli"
    // 2. Authorization：Bearer {token}（如果设置了 token）
    // 3. ChatGPT-Account-Id：ChatGPT 账户标识（如果设置了 account_id）
}
```

#### URL 构建规则
根据 `path_style` 选择不同路径前缀：
- CodexApi: `{base_url}/api/codex/{endpoint}`
- ChatGptApi: `{base_url}/wham/{endpoint}`

---

## 关键代码路径与文件引用

### 内部依赖
| 模块 | 路径 | 用途 |
|------|------|------|
| types | `crate::types` | 请求/响应数据结构定义 |
| codex_client | `codex_client::build_reqwest_client_with_custom_ca` | 带自定义 CA 的 HTTP 客户端构建 |
| codex_core::auth | `codex_core::auth::CodexAuth` | 认证信息获取 |
| codex_core::default_client | `codex_core::default_client::get_codex_user_agent` | 默认 User-Agent |
| codex_protocol | `codex_protocol::account::PlanType` | 账户计划类型 |
| codex_protocol | `codex_protocol::protocol::{CreditsSnapshot, RateLimitSnapshot, RateLimitWindow}` | 速率限制协议类型 |

### 外部依赖
- `reqwest`：HTTP 客户端库
- `serde`/`serde_json`：JSON 序列化/反序列化
- `anyhow`：错误处理

### 调用方（上游使用者）
| Crate | 文件 | 用途 |
|-------|------|------|
| cloud-tasks-client | `src/http.rs` | 云端任务管理 HTTP 客户端封装 |
| cloud-requirements | `src/lib.rs` | 云端配置获取 |
| app-server | `src/codex_message_processor.rs` | 消息处理 |
| tui | `src/chatwidget.rs` | TUI 聊天组件 |

---

## 依赖与外部交互

### 构建时依赖
```toml
[dependencies]
anyhow = "1"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
reqwest = { version = "0.12", default-features = false, features = ["json", "rustls-tls"] }
codex-backend-openapi-models = { path = "../codex-backend-openapi-models" }
codex-client = { workspace = true }
codex-protocol = { workspace = true }
codex-core = { workspace = true }
```

### 运行时交互
1. **认证服务**：通过 `CodexAuth` 获取 access token 和 account ID
2. **后端 API**：与 Codex 后端或 ChatGPT WHAM 后端通信
3. **TLS/CA**：通过 `codex_client` 支持自定义 CA 证书

### 测试依赖
- `pretty_assertions`：测试断言增强

---

## 风险、边界与改进建议

### 已知风险

1. **硬编码 URL 路径**：路径前缀 `/api/codex` 和 `/wham` 硬编码在代码中，后端 API 版本变更需要修改源码
2. **JSON 解析容错性**：`create_task` 方法中手动解析 JSON 响应提取 task ID，如果后端返回格式变更会导致失败
3. **速率限制计算**：`window_minutes_from_seconds` 使用向上取整 `(seconds + 59) / 60`，可能产生非预期的大窗口值

### 边界情况

1. **空响应处理**：`exec_request` 使用 `res.text().await.unwrap_or_default()`，空响应体会返回空字符串而非错误
2. **Account ID 头部**：`ChatGPT-Account-Id` 头部名称使用字节数组 `b"ChatGPT-Account-Id"` 构造，非标准常量
3. **PlanType 映射**：`map_plan_type` 将多个内部类型（Guest, FreeWorkspace, Quorum, K12）映射为 `Unknown`，信息丢失

### 改进建议

1. **API 版本管理**：
   - 建议引入 API 版本常量或配置，避免硬编码路径
   - 考虑使用 OpenAPI 生成客户端代码

2. **错误处理增强**：
   - 为 `RequestError` 实现更多辅助方法（如 `is_rate_limited()`）
   - 添加请求重试机制（目前由调用方处理）

3. **测试覆盖**：
   - 当前测试仅覆盖速率限制数据处理，建议增加：
     - HTTP 请求/响应集成测试
     - 路径风格自动检测测试
     - 错误场景测试（超时、网络错误等）

4. **代码组织**：
   - `create_task` 中的 JSON 解析逻辑可以提取到 `types.rs` 中
   - `rate_limit_snapshots_from_payload` 等辅助方法可以考虑移到独立模块

5. **文档完善**：
   - 为公共 API 方法添加更详细的 rustdoc 注释
   - 添加使用示例到模块级文档

### 性能考虑
- 每个请求都重新构造 `HeaderMap`，可以考虑缓存（但需要注意 token 刷新）
- `reqwest::Client` 内部已使用连接池，无需额外优化
