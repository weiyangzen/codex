# Research: codex-rs/login/tests/all.rs

## 1. 场景与职责

### 1.1 文件定位

`codex-rs/login/tests/all.rs` 是 **codex-login** crate 的集成测试入口文件，采用 Rust 的 "单一集成测试二进制文件" 模式（single integration test binary pattern）。该文件本身仅包含 3 行代码，作为模块聚合器（module aggregator），将实际测试代码分散在 `tests/suite/` 目录下的子模块中。

### 1.2 所属模块架构

```
codex-rs/login/
├── src/
│   ├── lib.rs              # 库入口，导出公开 API
│   ├── device_code_auth.rs # 设备码登录流程实现
│   ├── server.rs           # OAuth 回调服务器实现
│   └── pkce.rs             # PKCE 代码生成
├── tests/
│   ├── all.rs              # 本文件：测试聚合入口
│   └── suite/
│       ├── mod.rs          # 子模块聚合
│       ├── device_code_login.rs    # 设备码登录测试
│       └── login_server_e2e.rs     # OAuth 回调服务器 E2E 测试
```

### 1.3 核心职责

1. **模块聚合**：将分散的测试模块统一编译为单一测试二进制文件
2. **测试组织**：遵循 Rust 集成测试最佳实践，保持 `tests/` 目录整洁
3. **测试执行**：通过 `cargo test -p codex-login` 执行所有登录相关集成测试

---

## 2. 功能点目的

### 2.1 被测功能概述

本测试文件聚合的测试覆盖两大登录机制：

| 登录机制 | 实现文件 | 测试文件 | 用途 |
|---------|---------|---------|------|
| **设备码登录** (Device Code Flow) | `src/device_code_auth.rs` | `suite/device_code_login.rs` | 无浏览器环境下的 CLI 登录 |
| **OAuth 回调服务器** (Authorization Code Flow) | `src/server.rs` | `suite/login_server_e2e.rs` | 浏览器辅助的本地登录 |

### 2.2 设备码登录测试目的

测试 `run_device_code_login()` 函数的完整流程：

1. **成功路径**：验证从获取 user_code 到最终持久化 auth.json 的完整流程
2. **工作区限制**：验证 `forced_chatgpt_workspace_id` 不匹配时拒绝登录
3. **错误处理**：验证 HTTP 失败、授权拒绝等异常场景
4. **无 API Key 场景**：验证交换失败时仍持久化 token 但不存储 API key

### 2.3 OAuth 回调服务器测试目的

测试 `run_login_server()` 函数的端到端行为：

1. **完整回调流程**：模拟浏览器回调，验证 auth.json 持久化
2. **目录创建**：验证自动创建缺失的 codex_home 目录
3. **工作区验证**：验证强制工作区 ID 不匹配时阻止登录
4. **OAuth 错误处理**：验证 `access_denied` 及 `missing_codex_entitlement` 错误
5. **服务器取消**：验证端口占用时取消先前服务器实例

---

## 3. 具体技术实现

### 3.1 测试架构模式

#### 3.1.1 单一二进制模式

```rust
// tests/all.rs
mod suite;  // 聚合所有子模块
```

```rust
// tests/suite/mod.rs
mod device_code_login;   // 设备码登录测试
mod login_server_e2e;    // OAuth 服务器 E2E 测试
```

**优势**：
- 减少编译产物数量
- 共享测试辅助代码
- 更快的增量编译

#### 3.1.2 网络跳过宏

所有测试使用 `skip_if_no_network!` 宏检测沙箱环境：

```rust
#[tokio::test]
async fn device_code_login_integration_succeeds() -> anyhow::Result<()> {
    skip_if_no_network!(Ok(()));  // 沙箱环境中跳过
    // 测试逻辑...
}
```

该宏定义在 `core_test_support` crate 中，检查 `CODEX_SANDBOX_NETWORK_DISABLED` 环境变量。

### 3.2 设备码登录测试详解

#### 3.2.1 核心测试用例

| 测试函数 | 目的 | 关键验证点 |
|---------|------|-----------|
| `device_code_login_integration_succeeds` | 验证完整成功流程 | auth.json 持久化、token 字段正确性 |
| `device_code_login_rejects_workspace_mismatch` | 验证工作区限制 | `PermissionDenied` 错误、auth.json 未创建 |
| `device_code_login_integration_handles_usercode_http_failure` | 验证 HTTP 失败处理 | 503 错误正确传播 |
| `device_code_login_integration_persists_without_api_key_on_exchange_failure` | 验证无 API Key 场景 | token 持久化但 `openai_api_key` 为 null |
| `device_code_login_integration_handles_error_payload` | 验证授权拒绝 | `authorization_declined` 错误处理 |

#### 3.2.2 Mock 服务器辅助函数

```rust
// 模拟 usercode 端点成功响应
async fn mock_usercode_success(server: &MockServer) {
    Mock::given(method("POST"))
        .and(path("/api/accounts/deviceauth/usercode"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({
            "device_auth_id": "device-auth-123",
            "user_code": "CODE-12345",
            "interval": "0"  // 测试时设为0避免等待
        })))
        .mount(server)
        .await;
}

// 模拟两步轮询（第一次失败，第二次成功）
async fn mock_poll_token_two_step(
    server: &MockServer,
    counter: Arc<AtomicUsize>,
    first_response_status: u16,
) { /* ... */ }
```

使用 **WireMock** crate 进行 HTTP 交互的模拟。

#### 3.2.3 JWT 生成辅助

```rust
fn make_jwt(payload: serde_json::Value) -> String {
    let header = json!({ "alg": "none", "typ": "JWT" });
    let header_b64 = URL_SAFE_NO_PAD.encode(serde_json::to_vec(&header).unwrap());
    let payload_b64 = URL_SAFE_NO_PAD.encode(serde_json::to_vec(&payload).unwrap());
    let signature_b64 = URL_SAFE_NO_PAD.encode(b"sig");
    format!("{header_b64}.{payload_b64}.{signature_b64}")
}
```

生成无签名（`alg: none`）的测试 JWT，用于模拟 ID token。

### 3.3 OAuth 回调服务器测试详解

#### 3.3.1 核心测试用例

| 测试函数 | 目的 | 关键验证点 |
|---------|------|-----------|
| `end_to_end_login_flow_persists_auth_json` | 验证完整 E2E 流程 | auth.json 更新、URL 参数正确性 |
| `creates_missing_codex_home_dir` | 验证目录自动创建 | 缺失子目录时成功创建 auth.json |
| `forced_chatgpt_workspace_id_mismatch_blocks_login` | 验证工作区限制 | 错误页面包含限制信息、无 auth.json |
| `oauth_access_denied_missing_entitlement_blocks_login_with_clear_error` | 验证权限错误 | 用户友好的错误提示、管理员联系信息 |
| `oauth_access_denied_unknown_reason_uses_generic_error_page` | 验证通用错误 | 通用错误页面、保留原始错误信息 |
| `cancels_previous_login_server_when_port_is_in_use` | 验证服务器取消 | 先前列表服务器收到 `Interrupted` 错误 |

#### 3.3.2 Mock OAuth 服务器

使用 **tiny_http** 创建轻量级 Mock OAuth 服务器：

```rust
fn start_mock_issuer(chatgpt_account_id: &str) -> (SocketAddr, thread::JoinHandle<()>) {
    let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
    let addr = listener.local_addr().unwrap();
    let server = tiny_http::Server::from_listener(listener, None).unwrap();
    
    let handle = thread::spawn(move || {
        while let Ok(mut req) = server.recv() {
            let url = req.url().to_string();
            if url.starts_with("/oauth/token") {
                // 构造 JWT 响应
                let id_token = format!("{header}.{payload}.{sig}");
                let tokens = json!({
                    "id_token": id_token,
                    "access_token": "access-123",
                    "refresh_token": "refresh-123",
                });
                // 发送响应...
            }
        }
    });
    (addr, handle)
}
```

#### 3.3.3 浏览器回调模拟

```rust
// 构建带重定向跟随的 HTTP 客户端
let client = reqwest::Client::builder()
    .redirect(reqwest::redirect::Policy::limited(5))
    .build()?;

// 模拟浏览器回调
let url = format!("http://127.0.0.1:{login_port}/auth/callback?code=abc&state=test_state_123");
let resp = client.get(&url).send().await?;
assert!(resp.status().is_success());

// 等待服务器完成
server.block_until_done().await?;
```

### 3.4 数据结构

#### 3.4.1 ServerOptions 配置

```rust
pub struct ServerOptions {
    pub codex_home: PathBuf,
    pub client_id: String,
    pub issuer: String,
    pub port: u16,
    pub open_browser: bool,
    pub force_state: Option<String>,       // 测试用：强制 state 值
    pub forced_chatgpt_workspace_id: Option<String>,  // 工作区限制
    pub cli_auth_credentials_store_mode: AuthCredentialsStoreMode,
}
```

#### 3.4.2 AuthDotJson 持久化结构

```rust
pub struct AuthDotJson {
    pub auth_mode: Option<AuthMode>,
    pub openai_api_key: Option<String>,    // 传统 API Key
    pub tokens: Option<TokenData>,         // OAuth token
    pub last_refresh: Option<DateTime<Utc>>,
}

pub struct TokenData {
    pub id_token: IdTokenInfo,             // 解析后的 JWT 声明
    pub access_token: String,
    pub refresh_token: String,
    pub account_id: Option<String>,
}
```

### 3.5 关键流程

#### 3.5.1 设备码登录流程

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────┐
│   Client    │────▶│  /deviceauth/    │────▶│   Server    │
│             │     │    usercode      │     │             │
└─────────────┘     └──────────────────┘     └─────────────┘
       │                                           │
       │    {device_auth_id, user_code, interval}  │
       │◀──────────────────────────────────────────┘
       │
       │     ┌─────────────────────────────────────────┐
       │     │  轮询 POST /deviceauth/token            │
       └────▶│  (带 device_auth_id + user_code)        │
             │  直到返回 authorization_code            │
             └─────────────────────────────────────────┘
                                    │
                                    ▼
             ┌─────────────────────────────────────────┐
             │  POST /oauth/token                      │
             │  (authorization_code + PKCE)            │
             │  获取 id_token, access_token,           │
             │       refresh_token                     │
             └─────────────────────────────────────────┘
                                    │
                                    ▼
                          ┌─────────────────┐
                          │  持久化 auth.json │
                          └─────────────────┘
```

#### 3.5.2 OAuth 回调流程

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────┐
│   Browser   │────▶│  /oauth/authorize │────▶│  Auth Server │
└─────────────┘     └──────────────────┘     └─────────────┘
                                                          │
┌─────────────┐     ┌──────────────────┐                  │
│  Callback   │◀────│  /auth/callback   │◀─────────────────┘
│   Server    │     │  (带 code + state)│
│  :1455      │     └──────────────────┘
└─────────────┘              │
       │                     │
       │    ┌────────────────┘
       │    │ 验证 state
       │    │ 交换 code → tokens
       │    │ 验证工作区限制
       │    │ 持久化 auth.json
       │    ▼
       │  ┌─────────────┐
       └──┤ /success    │
          │ (重定向)    │
          └─────────────┘
```

---

## 4. 关键代码路径与文件引用

### 4.1 被测代码路径

| 被测功能 | 实现文件 | 关键函数/结构 |
|---------|---------|--------------|
| 设备码登录 | `codex-rs/login/src/device_code_auth.rs` | `run_device_code_login()`, `request_device_code()`, `complete_device_code_login()` |
| OAuth 服务器 | `codex-rs/login/src/server.rs` | `run_login_server()`, `LoginServer`, `process_request()` |
| PKCE 生成 | `codex-rs/login/src/pkce.rs` | `generate_pkce()`, `PkceCodes` |
| Token 持久化 | `codex-rs/login/src/server.rs` | `persist_tokens_async()` |
| 工作区验证 | `codex-rs/login/src/server.rs` | `ensure_workspace_allowed()` |

### 4.2 依赖代码路径

| 功能 | 依赖文件 | 用途 |
|-----|---------|------|
| Auth 存储 | `codex-rs/core/src/auth/storage.rs` | `AuthDotJson`, `AuthCredentialsStoreMode`, `save_auth()` |
| Token 解析 | `codex-rs/core/src/token_data.rs` | `TokenData`, `IdTokenInfo`, `parse_chatgpt_jwt_claims()` |
| Auth 管理 | `codex-rs/core/src/auth.rs` | `load_auth_dot_json()`, `AuthManager` |
| HTTP 客户端 | `codex-rs/client/src/lib.rs` | `build_reqwest_client_with_custom_ca()` |
| 测试支持 | `codex-rs/core/tests/common/lib.rs` | `skip_if_no_network!` 宏 |

### 4.3 测试辅助文件

| 文件 | 用途 |
|-----|------|
| `codex-rs/login/tests/suite/mod.rs` | 子模块聚合 |
| `codex-rs/login/tests/suite/device_code_login.rs` | 设备码登录测试实现 |
| `codex-rs/login/tests/suite/login_server_e2e.rs` | OAuth 服务器 E2E 测试实现 |
| `codex-rs/login/src/assets/success.html` | 登录成功页面模板 |
| `codex-rs/login/src/assets/error.html` | 登录错误页面模板 |

### 4.4 关键调用链

#### 设备码登录调用链

```
device_code_login_integration_succeeds (test)
  └── run_device_code_login(opts)
        ├── request_device_code(opts)
        │     └── request_user_code(client, api_base_url, client_id)
        │           └── POST /api/accounts/deviceauth/usercode
        └── complete_device_code_login(opts, device_code)
              ├── poll_for_token(client, api_base_url, ...)
              │     └── POST /api/accounts/deviceauth/token
              ├── exchange_code_for_tokens(issuer, client_id, ...)
              │     └── POST /oauth/token
              ├── ensure_workspace_allowed(forced_workspace_id, id_token)
              └── persist_tokens_async(codex_home, api_key, tokens, ...)
                    └── save_auth(codex_home, auth, store_mode)
```

#### OAuth 服务器调用链

```
end_to_end_login_flow_persists_auth_json (test)
  └── run_login_server(opts)
        ├── bind_server(port) -> Server
        ├── build_authorize_url(issuer, client_id, ...)
        └── LoginServer { auth_url, actual_port, server_handle, shutdown_handle }
              └── server_handle: tokio::spawn(async { loop { ... } })
                    └── process_request(url_raw, opts, ...)
                          ├── /auth/callback -> handle_callback()
                          │     ├── verify state
                          │     ├── exchange_code_for_tokens()
                          │     ├── ensure_workspace_allowed()
                          │     ├── obtain_api_key() (optional)
                          │     ├── persist_tokens_async()
                          │     └── redirect to /success
                          ├── /success -> success.html
                          └── /cancel -> shutdown
```

---

## 5. 依赖与外部交互

### 5.1 测试依赖（dev-dependencies）

| Crate | 用途 |
|-------|------|
| `anyhow` | 错误处理 |
| `core_test_support` | 测试工具宏（`skip_if_no_network!`） |
| `pretty_assertions` | 美观的断言输出 |
| `tempfile` | 临时目录创建 |
| `wiremock` | HTTP Mock 服务器 |

### 5.2 生产依赖

| Crate | 用途 |
|-------|------|
| `codex-core` | Auth 存储、Token 解析 |
| `codex-client` | HTTP 客户端构建 |
| `codex-app-server-protocol` | `AuthMode` 类型 |
| `reqwest` | HTTP 请求 |
| `tokio` | 异步运行时 |
| `tiny_http` | 本地回调服务器 |
| `serde`/`serde_json` | JSON 序列化 |
| `base64` | JWT 编码/解码 |
| `sha2` | PKCE 挑战生成 |
| `rand` | 随机数生成 |
| `url`/`urlencoding` | URL 编码 |
| `webbrowser` | 自动打开浏览器 |

### 5.3 外部系统交互

| 系统 | 交互方式 | 测试处理 |
|-----|---------|---------|
| OpenAI Auth Server | HTTPS: `/oauth/authorize`, `/oauth/token` | WireMock/tiny_http Mock |
| Device Auth API | HTTPS: `/api/accounts/deviceauth/*` | WireMock Mock |
| 文件系统 | 读写 `auth.json` | tempfile 创建隔离目录 |
| 浏览器 | 自动打开授权 URL | `open_browser: false` 禁用 |
| 本地端口 | 绑定 `127.0.0.1:1455` (默认) | 绑定随机端口 (`port: 0`) |

---

## 6. 风险、边界与改进建议

### 6.1 当前风险

#### 6.1.1 网络依赖风险

```rust
skip_if_no_network!(Ok(()));
```

- **风险**：所有测试在沙箱环境（如 Seatbelt sandbox）中被跳过，导致登录代码覆盖率下降
- **影响**：CI 中可能无法发现登录相关的回归问题
- **缓解**：测试使用 Mock 服务器，理论上可在沙箱运行，但宏强制跳过

#### 6.1.2 时序敏感测试

```rust
tokio::time::sleep(Duration::from_millis(100)).await;
```

- **风险**：`cancels_previous_login_server_when_port_is_in_use` 使用固定延迟
- **影响**：在慢速 CI 环境中可能不稳定
- **缓解**：使用同步原语（如 `Notify`）替代固定延迟

#### 6.1.3 端口冲突风险

```rust
let server = run_login_server(opts)?;  // port: 0 表示随机端口
```

- **风险**：虽然使用随机端口，但在高并发测试下仍有极小概率冲突
- **影响**：测试失败（`AddrInUse`）
- **缓解**：已实现端口冲突时的取消机制，但测试未覆盖此场景

### 6.2 边界条件

| 边界条件 | 当前处理 | 测试覆盖 |
|---------|---------|---------|
| 15 分钟超时 | `poll_for_token()` 中 `max_wait = Duration::from_secs(15 * 60)` | ❌ 未测试（测试设 `interval: 0`） |
| State 不匹配 | 返回 400 "State mismatch" | ✅ `state_valid` 检查 |
| 缺失 code | 返回错误页面 "Missing authorization code" | ✅ 测试覆盖 |
| 无效 JWT | `jwt_auth_claims()` 返回空对象 | ⚠️ 部分覆盖 |
| 目录权限 | `create_dir_all()` 可能失败 | ❌ 未测试 |
| Keyring 不可用 | 回退到文件存储 | ❌ 未测试（测试使用 `File` 模式） |

### 6.3 改进建议

#### 6.3.1 测试覆盖率提升

```rust
// 建议添加：测试刷新 token 流程
#[tokio::test]
async fn device_code_login_triggers_token_refresh_on_401() {
    // 验证 401 后自动刷新 token
}

// 建议添加：测试并发登录请求
#[tokio::test]
async fn concurrent_login_requests_are_serialized() {
    // 验证同时发起多个登录请求的行为
}
```

#### 6.3.2 沙箱环境支持

```rust
// 当前：完全跳过
skip_if_no_network!(Ok(()));

// 建议：允许 Mock 测试在沙箱运行
#[cfg(feature = "mock-tests")]
#[tokio::test]
async fn device_code_login_with_mock_works_in_sandbox() {
    // 使用 WireMock，无需真实网络
}
```

#### 6.3.3 错误场景细化

| 建议添加的测试 | 目的 |
|--------------|------|
| `malformed_jwt_handling` | 验证无效 JWT 格式处理 |
| `expired_device_code` | 验证设备码过期处理 |
| `keyring_fallback_to_file` | 验证 keyring 失败时回退 |
| `concurrent_auth_file_write` | 验证并发 auth.json 写入安全 |

#### 6.3.4 性能测试

```rust
// 建议添加：登录延迟基准测试
#[tokio::test]
async fn login_completes_within_reasonable_time() {
    let start = Instant::now();
    // ... 执行登录
    assert!(start.elapsed() < Duration::from_secs(5));
}
```

#### 6.3.5 代码重构建议

1. **提取测试辅助库**：
   - `make_jwt()`, `mock_usercode_success()` 等可在多个 crate 复用
   - 建议移至 `core_test_support`

2. **统一 Mock 服务器**：
   - 设备码测试使用 WireMock
   - OAuth 测试使用 tiny_http
   - 建议统一为单一 Mock 框架

3. **快照测试**：
   - 错误页面 HTML 输出可使用 `insta` 进行快照测试
   - 便于检测 UI 回归

### 6.4 安全考虑

| 方面 | 当前状态 | 建议 |
|-----|---------|------|
| JWT 签名验证 | 测试使用 `alg: none` | ✅ 测试场景合理 |
| 敏感信息日志 | 生产代码有脱敏处理 | ✅ 测试验证 `redact_sensitive_url_parts` |
| State 参数 | 随机生成 32 字节 | ✅ 足够安全 |
| PKCE | 使用 S256 方法 | ✅ 符合 OAuth 2.1 要求 |

---

## 7. 总结

`codex-rs/login/tests/all.rs` 作为测试聚合入口，组织了对 Codex CLI 登录系统的全面集成测试。测试覆盖两大登录机制（设备码和 OAuth 回调），验证成功路径、错误处理、工作区限制等关键场景。

测试架构清晰，使用 WireMock 和 tiny_http 进行外部依赖隔离，tempfile 保证测试隔离性。主要改进空间在于：
1. 提升沙箱环境测试覆盖率
2. 消除时序敏感测试
3. 添加更多边界条件测试
4. 统一 Mock 框架

该测试套件为登录系统的稳定性和安全性提供了重要保障。
