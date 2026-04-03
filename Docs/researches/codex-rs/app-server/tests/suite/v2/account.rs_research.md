# account.rs 研究文档

## 场景与职责

`account.rs` 是 Codex App Server V2 API 的账户管理模块集成测试套件。该文件位于 `codex-rs/app-server/tests/suite/v2/account.rs`，包含 1277 行代码，负责验证账户相关的核心功能，包括：

- 用户登录/登出流程（API Key 和 ChatGPT OAuth 两种模式）
- 外部认证令牌管理（ChatGPT Auth Tokens）
- 账户信息查询与状态通知
- 认证刷新机制（401 自动重试）
- 强制登录方式配置验证

该测试套件使用 MCP（Model Context Protocol）进程与 App Server 进行通信，通过 JSON-RPC 2.0 协议发送请求和接收通知。

## 功能点目的

### 1. 登出功能测试 (`logout_account_removes_auth_and_notifies`)
验证登出操作会：
- 删除本地 `auth.json` 凭证文件
- 发送 `account/updated` 通知，将 `auth_mode` 和 `plan_type` 置空
- 后续 `account/read` 请求返回空账户

### 2. 外部认证令牌设置 (`set_auth_token_updates_account_and_notifies`)
验证通过 `account/login/start` 设置 ChatGPT Auth Tokens 时：
- 解析 JWT token 提取用户邮箱和 plan 类型
- 发送 `account/updated` 通知更新认证状态
- `account/read` 返回正确的账户信息

### 3. 外部模式令牌刷新 (`account_read_refresh_token_is_noop_in_external_mode`)
验证在外部认证模式下，`refresh_token=true` 不会触发 token 刷新请求（与托管模式不同）。

### 4. 401 自动刷新机制 (`external_auth_refreshes_on_unauthorized`)
验证当后端返回 401 时：
- 服务器向客户端发送 `account/chatgptAuthTokens/refresh` 请求
- 客户端提供新 token 后，请求自动重试
- 两次请求分别使用新旧 token 的 Authorization header

### 5. 刷新失败处理 (`external_auth_refresh_error_fails_turn`)
验证当 token 刷新返回错误时，turn 状态标记为 Failed。

### 6. 工作空间不匹配检测 (`external_auth_refresh_mismatched_workspace_fails_turn`)
验证刷新返回的 `chatgpt_account_id` 与预期不符时，turn 失败。

### 7. 无效令牌检测 (`external_auth_refresh_invalid_access_token_fails_turn`)
验证刷新返回的 access token 格式无效（非 JWT）时，turn 失败。

### 8. API Key 登录 (`login_account_api_key_succeeds_and_notifies`)
验证 API Key 登录流程：
- 发送 `account/login/completed` 通知
- 发送 `account/updated` 通知
- 创建 `auth.json` 文件

### 9. 强制登录方式限制
- `login_account_api_key_rejected_when_forced_chatgpt`: 配置强制 ChatGPT 登录时拒绝 API Key
- `login_account_chatgpt_rejected_when_forced_api`: 配置强制 API Key 登录时拒绝 ChatGPT

### 10. ChatGPT OAuth 登录控制 (`login_account_chatgpt_start_can_be_cancelled`)
验证 OAuth 登录流程可被取消：
- 启动登录返回 `login_id` 和 `auth_url`
- 取消登录发送 `account/login/completed`（success=false）
- 不发送 `account/updated`（因未实际登录）

### 11. 令牌设置取消活跃登录 (`set_auth_token_cancels_active_chatgpt_login`)
验证在 OAuth 登录过程中设置外部令牌会取消活跃登录。

### 12. 强制工作空间参数 (`login_account_chatgpt_includes_forced_workspace_query_param`)
验证配置 `forced_chatgpt_workspace_id` 时，auth_url 包含 `allowed_workspace_id` 参数。

### 13. 账户查询场景
- `get_account_no_auth`: 无认证时返回空账户和 `requires_openai_auth=true`
- `get_account_with_api_key`: API Key 认证返回 `Account::ApiKey`
- `get_account_when_auth_not_required`: 不需要认证时返回空账户和 `requires_openai_auth=false`
- `get_account_with_chatgpt`: ChatGPT 认证返回邮箱和 plan 类型
- `get_account_with_chatgpt_missing_plan_claim_returns_unknown`: JWT 缺少 plan claim 时返回 `PlanType::Unknown`

## 具体技术实现

### 关键数据结构

```rust
// 协议定义 (codex-app-server-protocol/src/protocol/v2.rs)

pub enum Account {
    ApiKey {},
    Chatgpt { email: String, plan_type: PlanType },
}

pub enum LoginAccountResponse {
    ApiKey {},
    Chatgpt { login_id: String, auth_url: String },
    ChatgptAuthTokens {},
}

pub struct GetAccountResponse {
    pub account: Option<Account>,
    pub requires_openai_auth: bool,
}

pub struct CancelLoginAccountParams {
    pub login_id: String,
}

pub enum CancelLoginAccountStatus {
    Canceled,
    NotFound,
}

pub struct ChatgptAuthTokensRefreshResponse {
    pub access_token: String,
    pub chatgpt_account_id: String,
    pub chatgpt_plan_type: Option<String>,
}
```

### 测试辅助结构

```rust
// 配置生成参数
struct CreateConfigTomlParams {
    forced_method: Option<String>,           // forced_login_method
    forced_workspace_id: Option<String>,     // forced_chatgpt_workspace_id
    requires_openai_auth: Option<bool>,      // requires_openai_auth
    base_url: Option<String>,                // model_providers.mock_provider.base_url
}

// JWT Claims 结构（测试辅助）
struct ChatGptIdTokenClaims {
    email: Option<String>,
    plan_type: Option<String>,
    chatgpt_account_id: Option<String>,
}
```

### 关键流程

#### 1. 外部认证刷新流程
```
1. 客户端设置初始 token (account/login/start with chatgptAuthTokens)
2. 客户端发起 turn/start 请求
3. 后端返回 401 Unauthorized
4. 服务器发送 ServerRequest::ChatgptAuthTokensRefresh 给客户端
5. 客户端响应新 token (ChatgptAuthTokensRefreshResponse)
6. 服务器使用新 token 重试原请求
7. 发送 turn/completed 通知
```

#### 2. 测试断言模式
```rust
// 标准响应验证流程
let resp: JSONRPCResponse = timeout(
    DEFAULT_READ_TIMEOUT,
    mcp.read_stream_until_response_message(RequestId::Integer(req_id)),
).await??;
let result: ExpectedType = to_response(resp)?;

// 通知验证流程
let note = timeout(
    DEFAULT_READ_TIMEOUT,
    mcp.read_stream_until_notification_message("account/updated"),
).await??;
let parsed: ServerNotification = note.try_into()?;
```

#### 3. 刷新请求响应辅助函数
```rust
async fn respond_to_refresh_request(
    mcp: &mut McpProcess,
    access_token: &str,
    chatgpt_account_id: &str,
    chatgpt_plan_type: Option<&str>,
) -> Result<()> {
    let refresh_req: ServerRequest = timeout(...).await??;
    let ServerRequest::ChatgptAuthTokensRefresh { request_id, params } = refresh_req else { ... };
    assert_eq!(params.reason, ChatgptAuthTokensRefreshReason::Unauthorized);
    let response = ChatgptAuthTokensRefreshResponse { ... };
    mcp.send_response(request_id, serde_json::to_value(response)?).await?;
    Ok(())
}
```

## 关键代码路径与文件引用

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 1554-1715)
  - `Account` enum (行 1558)
  - `LoginAccountResponse` enum (行 1607)
  - `GetAccountParams` / `GetAccountResponse` (行 1699-1715)
  - `CancelLoginAccountParams` / `CancelLoginAccountResponse` (行 1628-1646)
  - `ChatgptAuthTokensRefreshResponse` (行 1680)
  - `AccountUpdatedNotification` (行 3517)
  - `AccountLoginCompletedNotification` (行 5791)

### 测试支持库
- `codex-rs/app-server/tests/suite/v2/mod.rs` - 测试模块入口
- `codex-rs/core/src/auth.rs` - 认证管理
- `codex-rs/core/src/test_support.rs` - 测试辅助函数

### 外部依赖
- `wiremock` - HTTP mock 服务器（模拟后端 API）
- `tokio::time::timeout` - 异步测试超时控制
- `tempfile::TempDir` - 临时测试目录
- `serial_test::serial` - 串行化测试（避免端口冲突）

## 依赖与外部交互

### 1. 测试框架依赖
```toml
[dev-dependencies]
tokio = { version = "1", features = ["full"] }
wiremock = "0.6"
tempfile = "3"
serial_test = "3"
pretty_assertions = "1"
anyhow = "1"
```

### 2. 内部 crate 依赖
- `codex_app_server_protocol` - JSON-RPC 协议类型
- `codex_core` - 核心认证和配置
- `codex_login` - 登录流程
- `app_test_support` - 测试辅助（McpProcess, ChatGptAuthFixture 等）
- `core_test_support` - 核心测试支持（responses mock）

### 3. 环境变量
- `OPENAI_API_KEY` - 用于测试 API Key 登录场景（测试中设为 None 以模拟无环境变量）

### 4. 配置文件
测试生成 `config.toml` 包含：
```toml
model = "mock-model"
approval_policy = "never"
sandbox_mode = "danger-full-access"
forced_login_method = "..."  # 可选
forced_chatgpt_workspace_id = "..."  # 可选
requires_openai_auth = true/false  # 可选

[features]
shell_snapshot = false

[model_providers.mock_provider]
name = "Mock provider for test"
base_url = "http://127.0.0.1:0/v1"
wire_api = "responses"
request_max_retries = 0
stream_max_retries = 0
```

## 风险、边界与改进建议

### 已知风险

1. **串行化测试限制**
   - 使用 `#[serial(login_port)]` 的测试必须串行执行，因为登录服务器绑定固定端口
   - 这增加了测试执行时间，且容易因端口占用导致 flaky 测试

2. **JWT 硬编码依赖**
   - 测试使用 `encode_id_token` 生成测试 JWT，依赖特定 claims 结构
   - 如果协议改变，所有相关测试需要更新

3. **超时硬编码**
   - `DEFAULT_READ_TIMEOUT = 10s` 可能在慢速 CI 环境下不稳定
   - 建议通过环境变量允许覆盖

4. **Mock 服务器竞争**
   - 多个测试同时启动 mock 服务器时可能遇到端口分配问题

### 边界条件

1. **空 JWT claims 处理**
   - 测试 `get_account_with_chatgpt_missing_plan_claim_returns_unknown` 验证缺少 plan claim 时返回 `Unknown`

2. **并发登录取消**
   - `set_auth_token_cancels_active_chatgpt_login` 验证在 OAuth 流程中设置外部令牌的行为

3. **401 重试次数**
   - 测试假设单次 401 后刷新成功，未测试多次 401 或刷新后仍 401 的场景

### 改进建议

1. **端口动态分配**
   - 使用 `TcpListener::bind("127.0.0.1:0")` 模式实现登录服务器动态端口分配
   - 移除 `#[serial(login_port)]` 限制，提高测试并行度

2. **超时配置外部化**
   ```rust
   const DEFAULT_READ_TIMEOUT: Duration = Duration::from_secs(
       env::var("TEST_TIMEOUT_SECS")
           .ok()
           .and_then(|s| s.parse().ok())
           .unwrap_or(10)
   );
   ```

3. **增加边界测试**
   - 多次 401 后的回退行为
   - 刷新 token 后再次 401 的处理
   - 网络超时场景

4. **测试数据工厂化**
   - 使用 `fake` crate 或工厂模式生成测试数据，减少硬编码

5. **文档化测试矩阵**
   - 创建认证状态 × 登录方式 × 配置约束的完整测试矩阵文档
