# codex-rs/login/Cargo.toml 研究文档

## 场景与职责

`Cargo.toml` 是 Rust 包管理工具 Cargo 的配置文件，定义了 `codex-login` crate 的元数据、依赖关系和构建配置。该 crate 是 Codex CLI 的**登录认证模块**，实现了两种主要的 OpenAI/Codex 认证方式：

1. **本地 OAuth 回调服务器流程**（浏览器登录）
2. **设备码授权流程**（无浏览器环境登录）

## 功能点目的

### 1. 包元数据

```toml
[package]
name = "codex-login"
version.workspace = true
edition.workspace = true
license.workspace = true
```

- 使用 Workspace 继承机制，版本号、Rust Edition、许可证信息从根 `Cargo.toml` 继承
- 保持多 crate 项目的版本一致性

### 2. 代码质量配置

```toml
[lints]
workspace = true
```

继承 Workspace 级别的 lint 配置（如 `rustfmt`、`clippy` 规则），确保代码风格统一。

### 3. 运行时依赖

| 依赖 | 用途 |
|------|------|
| `base64` | JWT/Base64URL 编解码（PKCE、Token 解析） |
| `chrono` | 时间处理（Token 过期时间） |
| `codex-client` | HTTP 客户端构建（支持自定义 CA） |
| `codex-core` | 核心认证逻辑、Token 数据类型 |
| `codex-app-server-protocol` | 认证模式枚举（AuthMode） |
| `rand` | 随机数生成（PKCE code_verifier、state） |
| `reqwest` | HTTP 客户端（OAuth Token 交换、API 调用） |
| `serde`/`serde_json` | JSON 序列化/反序列化 |
| `sha2` | SHA256 哈希（PKCE code_challenge） |
| `tiny_http` | 本地回调 HTTP 服务器 |
| `tokio` | 异步运行时 |
| `tracing` | 结构化日志 |
| `url`/`urlencoding` | URL 解析和编码 |
| `webbrowser` | 自动打开浏览器 |

### 4. 开发依赖

| 依赖 | 用途 |
|------|------|
| `anyhow` | 测试中的错误处理 |
| `core_test_support` | 项目内部测试工具（网络跳过宏等） |
| `pretty_assertions` | 测试断言美化 |
| `tempfile` | 临时目录（测试中的 codex_home） |
| `wiremock` | HTTP Mock 服务器（测试 OAuth 流程） |

## 具体技术实现

### 关键流程

#### 1. OAuth2 Authorization Code Flow + PKCE

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Codex CLI │────▶│  Local Server    │────▶│  OpenAI OAuth   │
│  (login crate)│   │ (localhost:1455) │     │   (/authorize)  │
└─────────────┘     └──────────────────┘     └─────────────────┘
                           │                           │
                           │                           ▼
                           │                    ┌─────────────────┐
                           │                    │  User Browser   │
                           │                    │  (Login/Consent)│
                           │                    └─────────────────┘
                           │                           │
                           ▼                           │
                    ┌──────────────────┐              │
                    │  /auth/callback  │◀─────────────┘
                    │  (exchange code) │
                    └──────────────────┘
                           │
                           ▼
                    ┌──────────────────┐
                    │  Token Exchange  │
                    │  (/oauth/token)  │
                    └──────────────────┘
```

**PKCE 实现**（`src/pkce.rs`）:
```rust
pub fn generate_pkce() -> PkceCodes {
    let mut bytes = [0u8; 64];
    rand::rng().fill_bytes(&mut bytes);
    
    // code_verifier: URL-safe base64, 43-128 chars
    let code_verifier = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes);
    
    // code_challenge: BASE64URL(SHA256(verifier))
    let digest = Sha256::digest(code_verifier.as_bytes());
    let code_challenge = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(digest);
    
    PkceCodes { code_verifier, code_challenge }
}
```

#### 2. 设备码授权流程（Device Code Flow）

```
┌─────────────┐                                    ┌─────────────────┐
│   Codex CLI │───POST /deviceauth/usercode───────▶│  OpenAI Device  │
│             │◀──{device_auth_id, user_code}──────│   Auth Server   │
│             │                                    └─────────────────┘
│             │  (Display: "Go to URL, enter CODE")
│             │
│             │───POST /deviceauth/token──────────▶│  (Poll every    │
│             │◀──403/404 (pending)  or  200───────│   interval secs)│
│             │    {authorization_code, ...}       │                 │
└─────────────┘                                    └─────────────────┘
```

**关键实现**（`src/device_code_auth.rs`）:
- `request_user_code()`: 请求用户码和设备授权 ID
- `poll_for_token()`: 轮询 Token 端点（最大等待 15 分钟）
- 使用 `interval` 字段控制轮询频率

#### 3. 本地回调服务器

**路由处理**（`src/server.rs`）:

| 路径 | 功能 |
|------|------|
| `/auth/callback` | OAuth 回调处理：验证 state、交换 code、保存 Token |
| `/success` | 登录成功页面（内嵌 success.html） |
| `/cancel` | 取消登录（用于端口占用时的优雅关闭） |

**安全机制**:
- **State 验证**: 防止 CSRF 攻击
- **PKCE**: 防止授权码拦截攻击
- **URL 敏感信息脱敏**: 日志中自动脱敏 `code`、`token` 等参数

### 数据结构

#### ServerOptions（服务器配置）
```rust
pub struct ServerOptions {
    pub codex_home: PathBuf,                    // 认证文件存储目录
    pub client_id: String,                      // OAuth client ID
    pub issuer: String,                         // OpenAI Auth URL
    pub port: u16,                              // 本地服务器端口（0=随机）
    pub open_browser: bool,                     // 是否自动打开浏览器
    pub force_state: Option<String>,            // 测试用：强制 state 值
    pub forced_chatgpt_workspace_id: Option<String>, // 强制工作空间限制
    pub cli_auth_credentials_store_mode: AuthCredentialsStoreMode, // 存储模式
}
```

#### DeviceCode（设备码信息）
```rust
pub struct DeviceCode {
    pub verification_url: String,  // 用户访问的验证 URL
    pub user_code: String,         // 用户输入的一次性代码
    device_auth_id: String,        // 设备授权 ID（内部使用）
    interval: u64,                 // 轮询间隔（秒）
}
```

#### ExchangedTokens（交换后的 Token）
```rust
pub(crate) struct ExchangedTokens {
    pub id_token: String,      // JWT ID Token（包含用户/组织信息）
    pub access_token: String,  // Access Token
    pub refresh_token: String, // Refresh Token
}
```

### 协议细节

#### OAuth 授权 URL 参数
```
https://auth.openai.com/oauth/authorize?
  response_type=code
  &client_id=app_EMoamEEZ73f0CkXaXp7hrann
  &redirect_uri=http://localhost:1455/auth/callback
  &scope=openid profile email offline_access api.connectors.read api.connectors.invoke
  &code_challenge=<PKCE_challenge>
  &code_challenge_method=S256
  &state=<random_state>
  &originator=codex-cli
  &allowed_workspace_id=<optional>
```

#### Token 交换请求
```
POST /oauth/token
Content-Type: application/x-www-form-urlencoded

grant_type=authorization_code
&code=<authorization_code>
&redirect_uri=http://localhost:1455/auth/callback
&client_id=app_EMoamEEZ73f0CkXaXp7hrann
&code_verifier=<PKCE_verifier>
```

## 关键代码路径与文件引用

### 源文件结构

```
codex-rs/login/src/
├── lib.rs                    # 模块导出、公共 API
├── server.rs                 # 本地 OAuth 回调服务器（~1200 行）
├── device_code_auth.rs       # 设备码流程实现（~230 行）
├── pkce.rs                   # PKCE 代码生成（~30 行）
└── assets/
    ├── error.html            # 错误页面模板
    └── success.html          # 成功页面模板（含自动跳转 JS）
```

### 公共 API（`lib.rs` 导出）

```rust
// 设备码流程
pub use device_code_auth::DeviceCode;
pub use device_code_auth::request_device_code;
pub use device_code_auth::complete_device_code_login;
pub use device_code_auth::run_device_code_login;

// 本地服务器流程
pub use server::LoginServer;
pub use server::ServerOptions;
pub use server::ShutdownHandle;
pub use server::run_login_server;

// 核心认证类型（从 codex-core re-export）
pub use codex_core::AuthManager;
pub use codex_core::CodexAuth;
pub use codex_core::auth::AuthDotJson;
pub use codex_core::auth::CLIENT_ID;
pub use codex_core::auth::login_with_api_key;
pub use codex_core::auth::logout;
pub use codex_core::auth::save_auth;
pub use codex_core::token_data::TokenData;
```

### 测试文件

```
codex-rs/login/tests/
├── all.rs                    # 测试入口
└── suite/
    ├── mod.rs                # 测试模块聚合
    ├── device_code_login.rs  # 设备码流程测试（~320 行）
    └── login_server_e2e.rs   # 本地服务器 E2E 测试（~460 行）
```

## 依赖与外部交互

### 上游依赖（Workspace crates）

| Crate | 用途 |
|-------|------|
| `codex-client` | `build_reqwest_client_with_custom_ca()` - 构建支持自定义 CA 的 HTTP 客户端 |
| `codex-core` | `AuthDotJson`、`TokenData`、`save_auth()`、`CLIENT_ID` 等核心类型和函数 |
| `codex-app-server-protocol` | `AuthMode` 枚举（ApiKey/Chatgpt/ChatgptAuthTokens） |

### 外部服务交互

| 服务 | 端点 | 用途 |
|------|------|------|
| OpenAI Auth | `https://auth.openai.com/oauth/authorize` | OAuth 授权页面 |
| OpenAI Auth | `https://auth.openai.com/oauth/token` | Token 交换/刷新 |
| OpenAI API | `https://api.openai.com/api/accounts/deviceauth/usercode` | 请求设备码 |
| OpenAI API | `https://api.openai.com/api/accounts/deviceauth/token` | 轮询设备授权结果 |

### 下游调用方

| Crate | 使用方式 |
|-------|----------|
| `codex-rs/cli` | `run_login_server()` / `run_device_code_login()` |
| `codex-rs/tui` | 调用登录功能处理用户登录命令 |
| `codex-rs/tui_app_server` | 复用登录逻辑（根据 AGENTS.md 要求保持行为一致） |

## 风险、边界与改进建议

### 风险点

1. **端口占用冲突**:
   - 默认端口 1455 可能被其他应用占用
   - 已实现缓解：`bind_server()` 会尝试发送 `/cancel` 请求关闭旧实例（最多 10 次重试）
   - 仍可能因权限问题或僵尸进程导致绑定失败

2. **Token 安全**:
   - Token 存储在本地文件系统（`~/.codex/auth.json`）
   - 依赖 `AuthCredentialsStoreMode` 控制存储方式（File/Keyring/None）
   - 日志中已脱敏敏感信息，但调试时仍需小心

3. **网络超时**:
   - 设备码流程最大等待 15 分钟，无中间状态保存
   - 网络中断后需要重新开始整个流程

4. **OAuth State 验证**:
   - 使用随机生成的 state 防止 CSRF
   - 测试时可通过 `force_state` 覆盖，生产环境必须随机

### 边界情况

| 场景 | 处理逻辑 |
|------|----------|
| 用户拒绝授权 | 检测 `error=access_denied`，显示友好错误页面 |
| 缺少 Codex 权限 | 检测 `error_description=missing_codex_entitlement`，提示联系管理员 |
| 工作空间不匹配 | `forced_chatgpt_workspace_id` 与 Token 中的 `chatgpt_account_id` 不一致时拒绝 |
| 端口绑定失败 | 尝试关闭旧实例后重试，最终返回 `AddrInUse` 错误 |
| API Key 交换失败 | 登录仍视为成功，但 `openai_api_key` 为 `None` |

### 改进建议

1. **端口选择优化**:
   ```rust
   // 当前：默认 1455，冲突时尝试关闭旧实例
   // 建议：优先尝试 1455，冲突时自动选择随机端口
   port: u16, // 0 = 随机端口
   ```

2. **设备码流程持久化**:
   - 将 `device_auth_id` 和 `user_code` 临时保存，支持断点续传
   - 避免 15 分钟等待期间进程崩溃导致需要重新开始

3. **Token 刷新集成**:
   - 当前登录模块只负责获取 Token
   - 建议将刷新逻辑也从 `codex-core` 迁移到 `codex-login`，统一认证生命周期管理

4. **测试覆盖率**:
   - 当前测试使用 `wiremock` 和 `tiny_http` 模拟外部服务
   - 建议添加更多边界测试：网络超时、无效 JSON、恶意回调参数等

5. **错误页面本地化**:
   - 当前 error.html 为英文，可考虑根据系统语言显示本地化内容

6. **安全加固**:
   - 考虑在本地服务器使用 HTTPS（自签名证书），防止本地网络中的中间人攻击
   - 添加更严格的 state 验证（如签名）

---

**文件大小**: 1036 bytes  
**最后更新**: 基于当前仓库状态分析
