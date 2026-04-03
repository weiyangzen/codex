# auth.rs 研究文档

## 场景与职责

`auth.rs` 是 Codex App Server 的集成测试模块，专注于验证**认证系统**的端到端行为。该测试文件位于 `codex-rs/app-server/tests/suite/auth.rs`，通过 MCP (Model Context Protocol) 进程与 App Server 交互，测试认证状态查询、API Key 登录、强制登录方法等核心认证流程。

### 核心职责
1. **认证状态查询测试**: 验证 `getAuthStatus` RPC 方法在各种场景下的行为
2. **API Key 登录流程测试**: 测试通过 API Key 进行账户登录的完整流程
3. **强制登录方法测试**: 验证当配置强制使用特定登录方法时的拒绝逻辑
4. **多 Provider 场景测试**: 测试自定义 Provider 下认证行为的差异

---

## 功能点目的

### 1. 测试配置生成辅助函数

| 函数 | 目的 |
|------|------|
| `create_config_toml_custom_provider` | 创建带有自定义 mock provider 的配置，支持设置 `requires_openai_auth` |
| `create_config_toml` | 创建基础配置，使用默认 OpenAI provider |
| `create_config_toml_forced_login` | 创建强制使用特定登录方法的配置（如强制 ChatGPT 登录） |

### 2. 认证测试用例

| 测试函数 | 测试目的 |
|----------|----------|
| `get_auth_status_no_auth` | 验证无认证时的状态返回（`auth_method: None`, `auth_token: None`） |
| `get_auth_status_with_api_key` | 验证 API Key 登录后的状态返回（`auth_method: ApiKey`, 包含 token） |
| `get_auth_status_with_api_key_when_auth_not_required` | 验证当 provider 不需要 OpenAI 认证时的行为差异 |
| `get_auth_status_with_api_key_no_include_token` | 验证 `include_token: None` 时 token 被正确省略 |
| `login_api_key_rejected_when_forced_chatgpt` | 验证强制 ChatGPT 登录时 API Key 登录被拒绝 |

---

## 具体技术实现

### 关键流程

#### 1. API Key 登录流程 (`login_with_api_key_via_request`)

```rust
async fn login_with_api_key_via_request(mcp: &mut McpProcess, api_key: &str) -> Result<()> {
    // 1. 发送登录请求
    let request_id = mcp.send_login_account_api_key_request(api_key).await?;
    
    // 2. 等待响应（带超时）
    let resp: JSONRPCResponse = timeout(
        DEFAULT_READ_TIMEOUT,
        mcp.read_stream_until_response_message(RequestId::Integer(request_id)),
    ).await??;
    
    // 3. 验证响应类型
    let response: LoginAccountResponse = to_response(resp)?;
    assert_eq!(response, LoginAccountResponse::ApiKey {});
    Ok(())
}
```

#### 2. 认证状态查询流程

```rust
let request_id = mcp
    .send_get_auth_status_request(GetAuthStatusParams {
        include_token: Some(true),   // 是否包含 token
        refresh_token: Some(false),  // 是否刷新 token
    })
    .await?;

let resp: JSONRPCResponse = timeout(
    DEFAULT_READ_TIMEOUT,
    mcp.read_stream_until_response_message(RequestId::Integer(request_id)),
).await??;

let status: GetAuthStatusResponse = to_response(resp)?;
// 验证: status.auth_method, status.auth_token, status.requires_openai_auth
```

### 数据结构

#### GetAuthStatusParams (请求参数)
```rust
pub struct GetAuthStatusParams {
    pub include_token: Option<bool>,  // 是否在响应中包含认证 token
    pub refresh_token: Option<bool>,  // 是否先刷新 token 再返回
}
```

#### GetAuthStatusResponse (响应结构)
```rust
pub struct GetAuthStatusResponse {
    pub auth_method: Option<AuthMode>,        // 认证方式: ApiKey/Chatgpt/ChatgptAuthTokens
    pub auth_token: Option<String>,           // 认证 token（可选）
    pub requires_openai_auth: Option<bool>,   // 是否需要 OpenAI 认证
}
```

#### AuthMode 枚举
```rust
pub enum AuthMode {
    ApiKey,           // OpenAI API Key
    Chatgpt,          // ChatGPT OAuth
    ChatgptAuthTokens, // 外部托管的 ChatGPT 令牌（内部使用）
}
```

### 配置模板示例

```toml
# 基础配置
model = "mock-model"
approval_policy = "never"
sandbox_mode = "danger-full-access"

[features]
shell_snapshot = false

# 自定义 Provider 配置
[model_providers.mock_provider]
name = "Mock provider for test"
base_url = "http://127.0.0.1:0/v1"
wire_api = "responses"
request_max_retries = 0
stream_max_retries = 0
requires_openai_auth = true  # 控制是否需要 OpenAI 认证
```

---

## 关键代码路径与文件引用

### 测试文件
| 文件 | 路径 | 说明 |
|------|------|------|
| auth.rs | `codex-rs/app-server/tests/suite/auth.rs` | 本测试文件 |
| mod.rs | `codex-rs/app-server/tests/suite/mod.rs` | 测试套件模块声明 |
| all.rs | `codex-rs/app-server/tests/all.rs` | 集成测试入口 |

### 测试支持库
| 文件 | 路径 | 说明 |
|------|------|------|
| mcp_process.rs | `codex-rs/app-server/tests/common/mcp_process.rs` | MCP 进程管理 |
| lib.rs | `codex-rs/app-server/tests/common/lib.rs` | 测试公共库 |

### 协议定义
| 文件 | 路径 | 说明 |
|------|------|------|
| v1.rs | `codex-rs/app-server-protocol/src/protocol/v1.rs` | v1 协议定义（GetAuthStatusParams/Response） |
| common.rs | `codex-rs/app-server-protocol/src/protocol/common.rs` | AuthMode 枚举定义 |
| lib.rs | `codex-rs/app-server-protocol/src/lib.rs` | 协议库导出 |

### 被测试的目标代码
| 文件 | 路径 | 说明 |
|------|------|------|
| app-server 主代码 | `codex-rs/app-server/src/` | 实现认证逻辑的 App Server |

---

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `anyhow` | 错误处理 |
| `app_test_support` | 测试支持库（McpProcess, to_response） |
| `codex_app_server_protocol` | 协议类型定义 |
| `codex_protocol::ThreadId` | Thread ID 类型 |
| `pretty_assertions` | 测试断言美化 |
| `tempfile::TempDir` | 临时目录创建 |
| `tokio::time::timeout` | 异步超时处理 |

### 进程间交互

```
测试进程 (auth.rs)
    │
    ├─► 启动 codex-app-server 子进程 (McpProcess)
    │       CODEX_HOME={临时目录}
    │       config.toml (测试生成)
    │
    ├─► 发送 JSON-RPC 请求 (stdin)
    │       method: "account/login/start"
    │       method: "getAuthStatus"
    │
    └─◄ 读取 JSON-RPC 响应 (stdout)
            JSONRPCResponse / JSONRPCError
```

### 环境变量

| 变量 | 说明 |
|------|------|
| `CODEX_HOME` | 指向临时测试目录，包含 config.toml |
| `OPENAI_API_KEY` | 在特定测试中被移除以模拟无认证场景 |

---

## 风险、边界与改进建议

### 已知风险

1. **超时风险**: 所有测试使用 10 秒超时 (`DEFAULT_READ_TIMEOUT`)，在慢速 CI 环境可能 flaky
2. **并发风险**: 测试使用 `multi_thread` flavor，共享全局状态可能导致干扰
3. **进程泄漏**: 尽管 `McpProcess` 实现了 `Drop` 清理，但 Tokio 的 `kill_on_drop` 是 best-effort

### 边界条件

| 边界场景 | 测试覆盖 |
|----------|----------|
| 无认证状态 | `get_auth_status_no_auth` |
| 有 API Key 认证 | `get_auth_status_with_api_key` |
| Provider 不需要认证 | `get_auth_status_with_api_key_when_auth_not_required` |
| 不请求 token | `get_auth_status_with_api_key_no_include_token` |
| 强制登录方法冲突 | `login_api_key_rejected_when_forced_chatgpt` |

### 改进建议

1. **增加重试机制**: 对于可能 flaky 的测试，增加有限的重试逻辑
2. **更细粒度的超时**: 区分连接超时和响应超时
3. **并发隔离**: 考虑使用独立的端口/标识符避免测试间干扰
4. **错误码验证**: 当前仅验证错误消息文本，建议同时验证错误码
5. **覆盖更多场景**:
   - ChatGPT OAuth 登录流程（需要模拟 OAuth 服务器）
   - Token 刷新逻辑
   - 多并发登录请求的竞争条件

### 相关协议方法

| 方法 | 方向 | 说明 |
|------|------|------|
| `account/login/start` | Client → Server | 启动登录流程 |
| `getAuthStatus` | Client → Server | 查询认证状态 |
| `account/login/cancel` | Client → Server | 取消登录（未测试） |
| `account/logout` | Client → Server | 登出（未测试） |
