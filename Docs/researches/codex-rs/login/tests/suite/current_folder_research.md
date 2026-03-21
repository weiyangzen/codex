# DIR codex-rs/login/tests/suite 研究文档

## 概述

`codex-rs/login/tests/suite` 是 `codex-login` crate 的集成测试套件目录，包含对登录功能（包括设备码登录和 OAuth 回调服务器）的全面测试。测试使用 `wiremock` 和 `tiny_http` 模拟外部 OAuth 服务，验证登录流程的各个环节。

---

## 场景与职责

### 测试目标

该测试套件负责验证以下核心场景：

1. **设备码登录流程** (`device_code_login.rs`)
   - 完整的设备码授权流程（Device Code Flow）
   - 用户码获取、轮询令牌端点、OAuth 令牌交换
   - 工作区（Workspace）限制验证
   - 错误处理（HTTP 失败、授权拒绝、错误载荷）

2. **OAuth 回调服务器端到端测试** (`login_server_e2e.rs`)
   - 浏览器回调流程的完整验证
   - 本地 HTTP 服务器的启动、请求处理和关闭
   - 授权码交换令牌
   - 工作区 ID 不匹配时的拒绝逻辑
   - OAuth 访问拒绝错误处理（缺少 Codex 权限）
   - 多服务器实例端口冲突处理

### 目录结构

```
codex-rs/login/tests/
├── all.rs                 # 测试入口，聚合 suite 模块
└── suite/
    ├── mod.rs             # 模块聚合（device_code_login + login_server_e2e）
    ├── device_code_login.rs    # 设备码登录测试
    └── login_server_e2e.rs     # OAuth 服务器 E2E 测试
```

---

## 功能点目的

### 1. 设备码登录测试 (`device_code_login.rs`)

| 测试函数 | 目的 |
|---------|------|
| `device_code_login_integration_succeeds` | 验证完整的成功登录流程，确认 auth.json 正确持久化 |
| `device_code_login_rejects_workspace_mismatch` | 验证当 JWT 中的 workspace ID 与强制要求的 ID 不匹配时拒绝登录 |
| `device_code_login_integration_handles_usercode_http_failure` | 验证用户码端点 HTTP 失败时的错误处理 |
| `device_code_login_integration_persists_without_api_key_on_exchange_failure` | 验证 API Key 交换失败时仍持久化其他令牌 |
| `device_code_login_integration_handles_error_payload` | 验证设备授权错误载荷（如 authorization_declined）的处理 |

### 2. 登录服务器 E2E 测试 (`login_server_e2e.rs`)

| 测试函数 | 目的 |
|---------|------|
| `end_to_end_login_flow_persists_auth_json` | 验证完整的浏览器登录流程，包括回调处理、令牌持久化 |
| `creates_missing_codex_home_dir` | 验证当 codex_home 目录不存在时自动创建 |
| `forced_chatgpt_workspace_id_mismatch_blocks_login` | 验证强制工作区 ID 不匹配时阻止登录 |
| `oauth_access_denied_missing_entitlement_blocks_login_with_clear_error` | 验证 OAuth access_denied + missing_codex_entitlement 的错误提示 |
| `oauth_access_denied_unknown_reason_uses_generic_error_page` | 验证未知拒绝原因时使用通用错误页面 |
| `cancels_previous_login_server_when_port_is_in_use` | 验证端口被占用时取消前一个服务器实例 |

---

## 具体技术实现

### 关键流程

#### 1. 设备码登录流程 (Device Code Flow)

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Client    │────▶│ /deviceauth/usercode │────▶│  Get user_code  │
│  (Test)     │     │   (获取用户码)      │     │  device_auth_id │
└─────────────┘     └──────────────────┘     └─────────────────┘
        │                                              │
        │                                              ▼
        │     ┌──────────────────┐     ┌─────────────────┐
        │◀────│ /deviceauth/token │◀────│   Poll tokens   │
        │     │   (轮询令牌)       │     │  (循环直到成功)  │
        │     └──────────────────┘     └─────────────────┘
        │                                              │
        ▼                                              ▼
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Success   │◀────│   /oauth/token   │◀────│  Exchange code  │
│ persist auth│     │  (交换 OAuth 令牌) │     │  for tokens     │
└─────────────┘     └──────────────────┘     └─────────────────┘
```

#### 2. OAuth 回调服务器流程

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Browser   │────▶│ /auth/callback   │────▶│  Validate state │
│             │     │   (授权回调)       │     │  Check error    │
└─────────────┘     └──────────────────┘     └─────────────────┘
        │                                              │
        │                                              ▼
        │     ┌──────────────────┐     ┌─────────────────┐
        │◀────│   /oauth/token   │◀────│  Exchange code  │
        │     │  (交换令牌)        │     │  for tokens     │
        │     └──────────────────┘     └─────────────────┘
        │                                              │
        ▼                                              ▼
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  /success   │◀────│  persist_tokens  │◀────│  Validate       │
│  redirect   │     │  (持久化认证)       │     │  workspace      │
└─────────────┘     └──────────────────┘     └─────────────────┘
```

### 数据结构

#### DeviceCode (设备码)
```rust
pub struct DeviceCode {
    pub verification_url: String,  // 用户访问的验证 URL
    pub user_code: String,         // 用户输入的一次性码
    device_auth_id: String,        // 设备授权 ID（内部使用）
    interval: u64,                 // 轮询间隔（秒）
}
```

#### ServerOptions (服务器配置)
```rust
pub struct ServerOptions {
    pub codex_home: PathBuf,
    pub client_id: String,
    pub issuer: String,                    // OAuth 发行者 URL
    pub port: u16,
    pub open_browser: bool,
    pub force_state: Option<String>,       // 测试用：强制 state 值
    pub forced_chatgpt_workspace_id: Option<String>, // 强制工作区限制
    pub cli_auth_credentials_store_mode: AuthCredentialsStoreMode,
}
```

#### ExchangedTokens (交换的令牌)
```rust
pub(crate) struct ExchangedTokens {
    pub id_token: String,      // JWT ID 令牌
    pub access_token: String,  // 访问令牌
    pub refresh_token: String, // 刷新令牌
}
```

### 协议与端点

#### 设备码端点

| 端点 | 方法 | 描述 |
|-----|------|------|
| `/api/accounts/deviceauth/usercode` | POST | 获取用户码和设备授权 ID |
| `/api/accounts/deviceauth/token` | POST | 轮询获取授权码 |
| `/oauth/token` | POST | 交换授权码获取 OAuth 令牌 |

#### OAuth 回调端点

| 端点 | 方法 | 描述 |
|-----|------|------|
| `/auth/callback` | GET | 浏览器回调，处理授权码或错误 |
| `/success` | GET | 登录成功页面 |
| `/cancel` | GET | 取消登录 |

### Mock 辅助函数

测试使用 `wiremock` 创建模拟服务器：

```rust
// 模拟用户码成功响应
async fn mock_usercode_success(server: &MockServer) {
    Mock::given(method("POST"))
        .and(path("/api/accounts/deviceauth/usercode"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({
            "device_auth_id": "device-auth-123",
            "user_code": "CODE-12345",
            "interval": "0"
        })))
        .mount(server)
        .await;
}

// 模拟两步轮询（第一次失败，第二次成功）
async fn mock_poll_token_two_step(
    server: &MockServer,
    counter: Arc<AtomicUsize>,
    first_response_status: u16,
) { ... }
```

---

## 关键代码路径与文件引用

### 被测试的源代码

| 文件 | 职责 | 测试覆盖 |
|-----|------|---------|
| `codex-rs/login/src/device_code_auth.rs` | 设备码登录实现 | `device_code_login.rs` |
| `codex-rs/login/src/server.rs` | OAuth 回调服务器 | `login_server_e2e.rs` |
| `codex-rs/login/src/pkce.rs` | PKCE 码生成 | 间接测试 |
| `codex-rs/login/src/lib.rs` | 公共 API 导出 | 集成测试 |

### 测试文件详解

#### `device_code_login.rs` (318 行)

**核心测试逻辑：**
- 使用 `wiremock::MockServer` 模拟 OAuth 服务
- 使用 `tempfile::tempdir()` 创建隔离的测试环境
- 使用 `make_jwt()` 辅助函数生成测试用 JWT
- 验证 `auth.json` 的持久化内容

**关键断言模式：**
```rust
// 验证令牌持久化
let auth = load_auth_dot_json(codex_home.path(), AuthCredentialsStoreMode::File)?;
let tokens = auth.tokens.expect("tokens persisted");
assert_eq!(tokens.access_token, "access-token-123");
assert_eq!(tokens.account_id.as_deref(), Some("acct_321"));
```

#### `login_server_e2e.rs` (464 行)

**核心测试逻辑：**
- 使用 `tiny_http::Server` 创建模拟 OAuth 发行者
- 使用 `reqwest::Client` 模拟浏览器请求
- 测试完整的端到端流程

**Mock OAuth 发行者实现：**
```rust
fn start_mock_issuer(chatgpt_account_id: &str) -> (SocketAddr, thread::JoinHandle<()>) {
    let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
    let server = tiny_http::Server::from_listener(listener, None).unwrap();
    // ... 处理 /oauth/token 请求，返回模拟 JWT
}
```

### 测试基础设施

#### 网络跳过宏

测试使用 `core_test_support::skip_if_no_network!` 宏处理沙箱环境：

```rust
#[tokio::test]
async fn device_code_login_integration_succeeds() -> anyhow::Result<()> {
    skip_if_no_network!(Ok(()));  // 如果网络被禁用则跳过
    // ... 测试逻辑
}
```

#### JWT 生成辅助函数

```rust
fn make_jwt(payload: serde_json::Value) -> String {
    let header = json!({ "alg": "none", "typ": "JWT" });
    let header_b64 = URL_SAFE_NO_PAD.encode(serde_json::to_vec(&header).unwrap());
    let payload_b64 = URL_SAFE_NO_PAD.encode(serde_json::to_vec(&payload).unwrap());
    let signature_b64 = URL_SAFE_NO_PAD.encode(b"sig");
    format!("{header_b64}.{payload_b64}.{signature_b64}")
}
```

---

## 依赖与外部交互

### 直接依赖 (Cargo.toml)

```toml
[dev-dependencies]
anyhow = { workspace = true }
core_test_support = { workspace = true }
pretty_assertions = { workspace = true }
tempfile = { workspace = true }
wiremock = { workspace = true }
```

### 内部依赖

| Crate | 用途 |
|-------|------|
| `codex-core` | `AuthCredentialsStoreMode`, `load_auth_dot_json` |
| `codex-client` | HTTP 客户端构建 |
| `codex-app-server-protocol` | `AuthMode` 类型 |

### 外部服务模拟

1. **WireMock 服务器**: 模拟 OAuth 端点
   - `/api/accounts/deviceauth/usercode`
   - `/api/accounts/deviceauth/token`
   - `/oauth/token`

2. **tiny_http 服务器**: 模拟 OAuth 发行者
   - 处理令牌交换请求
   - 返回模拟 JWT 令牌

### 文件系统交互

测试在临时目录中操作：
- 创建临时 `codex_home` 目录
- 验证 `auth.json` 的创建和内容
- 测试目录自动创建逻辑

---

## 风险、边界与改进建议

### 当前风险

1. **网络依赖**
   - 测试需要网络访问（使用 `skip_if_no_network!` 跳过）
   - 在 CI 沙箱环境中可能无法完全执行

2. **时间敏感测试**
   - `cancels_previous_login_server_when_port_is_in_use` 使用 `tokio::time::sleep`
   - 在慢速环境中可能不稳定

3. **端口冲突**
   - 测试使用随机端口（`port: 0`），但仍存在冲突风险
   - 端口释放可能有延迟

### 边界情况

| 边界情况 | 处理方式 |
|---------|---------|
| State 不匹配 | 返回 400 错误 |
| 缺少授权码 | 返回错误页面 |
| OAuth 拒绝 (access_denied) | 显示用户友好的错误信息 |
| 缺少 Codex 权限 | 特殊错误提示，引导联系管理员 |
| 工作区 ID 不匹配 | 返回 PermissionDenied 错误 |
| 端口被占用 | 尝试取消前一个服务器，最多重试 10 次 |

### 改进建议

1. **测试稳定性**
   - 将 `tokio::time::sleep` 替换为更可靠的同步机制
   - 使用端口池避免冲突

2. **覆盖率提升**
   - 添加 PKCE 码生成验证测试
   - 添加令牌刷新流程测试
   - 添加更多错误边界测试（如无效 JWT）

3. **性能优化**
   - 考虑并行执行独立测试
   - 共享 Mock 服务器实例减少启动开销

4. **文档完善**
   - 添加测试架构图
   - 记录每个测试的具体前置条件

5. **安全加固**
   - 验证敏感信息（令牌、密码）不会泄露到日志
   - 测试 URL 脱敏逻辑

---

## 附录：测试执行命令

```bash
# 运行所有登录测试
cargo test -p codex-login

# 运行特定测试
cargo test -p codex-login device_code_login_integration_succeeds

# 运行测试（带输出）
cargo test -p codex-login -- --nocapture
```

---

*文档生成时间: 2026-03-21*
*研究对象: codex-rs/login/tests/suite*
