# Login Server E2E 测试研究文档

## 场景与职责

`login_server_e2e.rs` 是 Codex CLI 登录模块的端到端（E2E）集成测试文件，专注于测试**基于浏览器回调的 OAuth 登录流程**。该测试文件验证本地 HTTP 回调服务器处理 OAuth 授权码流程的完整功能。

### 核心职责
1. **验证端到端登录流程**：从启动本地服务器到处理浏览器回调的完整流程
2. **测试凭证持久化**：验证登录成功后 `auth.json` 的正确写入和更新
3. **验证工作区限制**：测试强制工作区 ID 的匹配和拒绝逻辑
4. **测试错误处理**：验证 OAuth 错误回调（access_denied 等）的处理
5. **测试服务器生命周期**：验证登录服务器的启动、取消和端口占用处理

---

## 功能点目的

### 1. 浏览器回调登录流程
标准的 OAuth 2.0 授权码流程：
1. 启动本地 HTTP 服务器监听回调
2. 构建授权 URL 并打开浏览器
3. 用户在浏览器中完成授权
4. 浏览器重定向到本地回调端点
5. 服务器交换授权码获取令牌
6. 持久化凭证并返回成功页面

### 2. 测试覆盖场景

| 测试函数 | 目的 |
|---------|------|
| `end_to_end_login_flow_persists_auth_json` | 验证完整登录流程和凭证持久化 |
| `creates_missing_codex_home_dir` | 验证自动创建缺失的 `codex_home` 目录 |
| `forced_chatgpt_workspace_id_mismatch_blocks_login` | 验证工作区 ID 不匹配时阻止登录 |
| `oauth_access_denied_missing_entitlement_blocks_login_with_clear_error` | 验证缺少 Codex 权限的错误处理 |
| `oauth_access_denied_unknown_reason_uses_generic_error_page` | 验证通用 OAuth 拒绝错误处理 |
| `cancels_previous_login_server_when_port_is_in_use` | 验证端口占用时的服务器取消机制 |

---

## 具体技术实现

### 关键流程

#### 1. Mock OAuth 发行方服务器
```rust
fn start_mock_issuer(chatgpt_account_id: &str) -> (SocketAddr, thread::JoinHandle<()>)
```
使用 `tiny_http` 启动轻量级 Mock 服务器：
- 监听随机可用端口
- 处理 `POST /oauth/token` 请求
- 返回包含自定义 JWT 的令牌响应
- JWT payload 包含 `chatgpt_plan_type` 和 `chatgpt_account_id`

**Mock 响应示例**：
```json
{
    "id_token": "<JWT with plan=pro>",
    "access_token": "access-123",
    "refresh_token": "refresh-123"
}
```

#### 2. 测试服务器配置
```rust
ServerOptions {
    codex_home: PathBuf,           // 临时目录
    cli_auth_credentials_store_mode: AuthCredentialsStoreMode::File,
    client_id: String,             // OAuth 客户端 ID
    issuer: String,                // Mock 服务器地址
    port: u16,                     // 0 = 随机端口
    open_browser: false,           // 测试时禁用
    force_state: Option<String>,   // 固定 state 便于测试
    forced_chatgpt_workspace_id: Option<String>, // 强制工作区
}
```

#### 3. 模拟浏览器回调
```rust
let client = reqwest::Client::builder()
    .redirect(reqwest::redirect::Policy::limited(5))
    .build()?;
let url = format!("http://127.0.0.1:{login_port}/auth/callback?code=abc&state=test_state_123");
let resp = client.get(&url).send().await?;
```

### 数据结构

#### 预置的 stale_auth（用于测试凭证覆盖）
```rust
{
    "OPENAI_API_KEY": "sk-stale",
    "tokens": {
        "id_token": "stale.header.payload",
        "access_token": "stale-access",
        "refresh_token": "stale-refresh",
        "account_id": "stale-acc"
    }
}
```

#### JWT Claims 结构
```rust
{
    "email": "user@example.com",
    "https://api.openai.com/auth": {
        "chatgpt_plan_type": "pro",
        "chatgpt_account_id": "12345678-0000-0000-0000-000000000000"
    }
}
```

---

## 关键代码路径与文件引用

### 被测代码路径

| 文件 | 职责 |
|------|------|
| `codex-rs/login/src/server.rs` | 登录服务器核心实现 |
| `codex-rs/login/src/pkce.rs` | PKCE 代码生成 |
| `codex-rs/core/src/auth/storage.rs` | 凭证存储实现 |
| `codex-rs/core/src/token_data.rs` | 令牌数据结构和 JWT 解析 |

### 关键函数调用链

```
run_login_server(opts) -> io::Result<LoginServer>
  ├── bind_server(port) -> 绑定本地端口
  ├── build_authorize_url() -> 构建授权 URL
  ├── 启动后台线程处理 HTTP 请求
  └── 返回 LoginServer { auth_url, actual_port, ... }

LoginServer::block_until_done() -> 等待登录完成
  └── 处理回调请求 process_request()
        ├── /auth/callback -> 处理授权码
        │     ├── 验证 state 参数
        │     ├── exchange_code_for_tokens()
        │     ├── ensure_workspace_allowed()
        │     ├── obtain_api_key() (可选)
        │     ├── persist_tokens_async()
        │     └── 重定向到 /success
        ├── /success -> 返回成功页面
        └── /cancel -> 取消登录
```

### 服务器端点处理

| 端点 | 方法 | 用途 |
|------|------|------|
| `/auth/callback` | GET | 处理 OAuth 回调，交换授权码 |
| `/success` | GET | 返回登录成功页面 |
| `/cancel` | GET | 取消当前登录流程 |

### 测试断言要点

1. **成功登录断言**:
   - `auth.json` 存在且内容正确
   - 旧凭证被新凭证覆盖
   - `account_id` 正确提取
   - 授权 URL 包含工作区参数（如适用）

2. **错误场景断言**:
   - 错误页面包含用户友好的消息
   - 终端错误包含操作指导
   - `auth.json` 未被创建或修改
   - 错误类型为 `PermissionDenied`

3. **服务器取消断言**:
   - 第一个服务器返回 `Interrupted` 错误
   - 第二个服务器成功接管端口
   - `/cancel` 端点可正常访问

---

## 依赖与外部交互

### 测试依赖

| 依赖 | 用途 |
|------|------|
| `tiny_http` | Mock OAuth 发行方服务器 |
| `reqwest` | 模拟浏览器 HTTP 请求 |
| `tempfile` | 创建临时 `codex_home` 目录 |
| `core_test_support` | 提供 `skip_if_no_network!` 宏 |
| `anyhow` | 错误处理 |
| `base64` | JWT 编码 |

### 网络依赖

测试使用 `skip_if_no_network!` 宏：
```rust
skip_if_no_network!(Ok(()));
```
- 检测 `CODEX_SANDBOX_NETWORK_DISABLED` 环境变量
- 在沙箱环境中跳过测试

### 外部交互

1. **Mock 发行方服务器** (`tiny_http`):
   - 监听 `127.0.0.1:随机端口`
   - 处理 `POST /oauth/token`
   - 返回 JWT 令牌

2. **登录服务器** (被测代码):
   - 监听 `127.0.0.1:随机端口` (默认 1455)
   - 处理浏览器回调
   - 向 Mock 发行方请求令牌

3. **文件系统**:
   - 读取/写入 `auth.json`
   - 自动创建缺失的目录

---

## 风险、边界与改进建议

### 已知风险

1. **端口竞争**
   - 测试使用随机端口，但仍有极小概率冲突
   - `cancels_previous_login_server_when_port_is_in_use` 测试依赖特定时序

2. **线程安全**
   - Mock 服务器在单独线程运行
   - 需要确保测试结束时正确清理

3. **状态管理**
   - `force_state` 选项仅用于测试
   - 生产环境使用随机生成的 state

### 边界情况

1. **目录创建**
   - 测试验证 `codex_home` 父目录不存在时自动创建
   - 使用 `std::fs::create_dir_all`

2. **凭证覆盖**
   - 新登录应完全覆盖旧凭证
   - 测试预置 stale auth 数据验证此行为

3. **错误消息映射**
   - `missing_codex_entitlement` 映射为用户友好消息
   - 其他错误保留原始描述

4. **并发登录**
   - 同一端口只能有一个登录服务器
   - 新服务器启动时会取消旧服务器

### 改进建议

1. **增强测试覆盖率**
   - 添加 `state` 参数不匹配测试
   - 测试授权码过期场景
   - 测试令牌端点返回非 JSON 响应
   - 添加 `Keyring` 存储模式测试

2. **性能优化**
   - 使用共享的 Mock 服务器减少启动开销
   - 考虑使用 `lazy_static` 缓存编译后的正则

3. **代码重构**
   - 提取 Mock 服务器构建器减少重复代码
   - 添加辅助函数构建回调 URL
   - 使用快照测试验证 HTML 响应内容

4. **可靠性改进**
   - 添加重试机制处理端口绑定失败
   - 增加超时处理防止测试挂起
   - 使用 `Drop` trait 确保资源清理

5. **文档改进**
   - 添加 OAuth 流程的序列图
   - 说明各端点的请求/响应格式
   - 记录测试与生产环境的差异

### 相关配置

测试涉及的关键配置项：
- `DEFAULT_PORT = 1455` - 默认登录服务器端口
- `DEFAULT_ISSUER = "https://auth.openai.com"` - 默认 OAuth 发行方
- `AuthCredentialsStoreMode` - 凭证存储模式
- `forced_chatgpt_workspace_id` - 强制工作区 ID 验证
- `force_state` - 固定 state（仅测试使用）

### 安全考虑

1. **敏感信息脱敏**
   - 生产代码使用 `redact_sensitive_url_parts` 脱敏日志
   - 测试使用假令牌避免泄露真实凭证

2. **CSRF 防护**
   - 使用 `state` 参数防止 CSRF 攻击
   - 测试验证 state 匹配逻辑

3. **PKCE 验证**
   - 使用 S256 挑战方法
   - 测试间接验证 PKCE 代码生成
