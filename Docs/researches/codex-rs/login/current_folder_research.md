# codex-rs/login 目录研究文档

## 概述

`codex-rs/login` 是 Codex CLI/TUI 的认证登录模块，负责处理用户与 OpenAI/ChatGPT 的 OAuth 认证流程。该模块实现了两种主要的登录方式：浏览器回调登录（Browser-based OAuth）和设备码登录（Device Code Flow），并提供了完整的本地服务器来处理 OAuth 回调。

---

## 场景与职责

### 核心场景

1. **浏览器登录流程** - 用户在本地浏览器中完成 OpenAI 账号授权，通过 localhost 回调接收 token
2. **设备码登录** - 在无浏览器环境（SSH/headless）下，用户在其他设备上输入一次性验证码完成授权
3. **API Key 登录** - 直接使用 OpenAI API Key 进行认证（由 `codex-core` 实现，本模块提供封装）
4. **Token 持久化** - 将获取的认证信息保存到本地存储（文件系统或系统密钥环）

### 职责边界

| 职责 | 说明 |
|------|------|
| OAuth 流程实现 | 完整的 PKCE + Authorization Code 流程 |
| 本地回调服务器 | 启动临时 HTTP 服务器接收浏览器回调 |
| 设备码流程 | 请求设备码、轮询 token 端点 |
| Token 交换 | 使用 authorization code 交换 id/access/refresh tokens |
| Workspace 验证 | 验证用户所属 workspace 是否符合强制配置 |
| 错误页面渲染 | 提供用户友好的 HTML 错误/成功页面 |

---

## 功能点目的

### 1. 浏览器登录 (`server.rs`)

**目的**：在本地机器上启动临时 HTTP 服务器，接收浏览器 OAuth 回调并提取授权码。

**关键功能**：
- 绑定 localhost 端口（默认 1455），支持自动端口冲突解决
- 生成 PKCE code verifier/challenge 防止授权码拦截攻击
- 构建授权 URL 并自动打开浏览器
- 处理 `/auth/callback` 路由，验证 state 参数防止 CSRF
- 交换 authorization code 获取 tokens
- 支持强制 workspace ID 验证

### 2. 设备码登录 (`device_code_auth.rs`)

**目的**：支持无浏览器环境下的登录，用户在其他设备上输入验证码。

**关键功能**：
- 请求设备码（`POST /deviceauth/usercode`）
- 轮询 token 端点（`POST /deviceauth/token`）
- 15 分钟超时，支持可配置的轮询间隔
- 自动回退到浏览器登录（当设备码端点返回 404）

### 3. PKCE 实现 (`pkce.rs`)

**目的**：为 OAuth 授权码流程提供额外的安全层。

**实现细节**：
- 生成 64 字节随机数作为 code verifier
- 使用 SHA-256 哈希生成 code challenge
- URL-safe base64 编码（无填充）

### 4. Token 持久化与 Workspace 验证

**目的**：安全存储认证信息并实施 workspace 级别的访问控制。

**功能**：
- 解析 JWT 获取用户账户信息
- 验证 `chatgpt_account_id` 是否符合强制配置
- 支持通过 token exchange 获取 API key
- 异步保存到配置指定的存储后端

---

## 具体技术实现

### 关键数据结构

```rust
// server.rs - 服务器配置选项
pub struct ServerOptions {
    pub codex_home: PathBuf,
    pub client_id: String,
    pub issuer: String,           // 默认: https://auth.openai.com
    pub port: u16,                // 默认: 1455
    pub open_browser: bool,
    pub force_state: Option<String>,  // 测试用
    pub forced_chatgpt_workspace_id: Option<String>,
    pub cli_auth_credentials_store_mode: AuthCredentialsStoreMode,
}

// device_code_auth.rs - 设备码信息
pub struct DeviceCode {
    pub verification_url: String,  // 用户访问的验证页面
    pub user_code: String,         // 一次性验证码
    device_auth_id: String,        // 内部设备标识
    interval: u64,                 // 轮询间隔（秒）
}

// pkce.rs - PKCE 参数
pub struct PkceCodes {
    pub code_verifier: String,
    pub code_challenge: String,
}

// server.rs - 运行中的服务器句柄
pub struct LoginServer {
    pub auth_url: String,          // 授权 URL（供浏览器打开）
    pub actual_port: u16,
    server_handle: tokio::task::JoinHandle<io::Result<()>>,
    shutdown_handle: ShutdownHandle,
}
```

### 关键流程

#### 浏览器登录流程

```
1. run_login_server(opts)
   ├─ generate_pkce()                    # 生成 PKCE 参数
   ├─ bind_server(port)                  # 绑定 localhost 端口
   ├─ build_authorize_url()              # 构建授权 URL
   ├─ webbrowser::open(&auth_url)        # 自动打开浏览器
   └─ 启动 tokio 任务处理请求循环
      
2. 请求处理 (process_request)
   ├─ /auth/callback
   │  ├─ 验证 state 参数
   │  ├─ 检查 error 参数（用户拒绝/无权限）
   │  ├─ exchange_code_for_tokens()      # 交换 tokens
   │  ├─ ensure_workspace_allowed()      # 验证 workspace
   │  ├─ obtain_api_key()                # 获取 API key（可选）
   │  ├─ persist_tokens_async()          # 持久化 tokens
   │  └─ 重定向到 /success 页面
   ├─ /success → 返回成功 HTML 页面
   └─ /cancel → 取消登录流程
```

#### 设备码登录流程

```
1. request_device_code(opts)
   └─ POST /api/accounts/deviceauth/usercode
      └─ 返回: device_auth_id, user_code, interval

2. complete_device_code_login(opts, device_code)
   ├─ poll_for_token()                   # 轮询 token 端点
   │  └─ POST /api/accounts/deviceauth/token
   │     ├─ 403/404 → 继续轮询（最多 15 分钟）
   │     └─ 200 → 获取 authorization_code
   ├─ exchange_code_for_tokens()         # 标准 OAuth 交换
   ├─ ensure_workspace_allowed()
   └─ persist_tokens_async()
```

### 协议与端点

| 端点 | 方法 | 用途 |
|------|------|------|
| `https://auth.openai.com/oauth/authorize` | GET | OAuth 授权页面 |
| `https://auth.openai.com/oauth/token` | POST | 交换 code/refresh token |
| `/api/accounts/deviceauth/usercode` | POST | 请求设备码 |
| `/api/accounts/deviceauth/token` | POST | 轮询设备授权结果 |

### 安全机制

1. **PKCE (RFC 7636)**
   - 防止 authorization code 拦截攻击
   - 实现：`pkce.rs` 中的 `generate_pkce()`

2. **State 参数验证**
   - 防止 CSRF 攻击
   - 32 字节随机数，URL-safe base64 编码

3. **敏感信息脱敏**
   - URL 参数中的 token/code 在日志中显示为 `<redacted>`
   - 实现：`redact_sensitive_url_parts()`, `SENSITIVE_URL_QUERY_KEYS`

4. **Workspace 强制验证**
   - 配置 `forced_chatgpt_workspace_id` 时，验证用户所属 workspace
   - 不匹配时拒绝登录并显示明确错误

---

## 关键代码路径与文件引用

### 核心文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `src/server.rs` | ~1195 | 本地回调服务器、OAuth 流程、Token 交换 |
| `src/device_code_auth.rs` | ~228 | 设备码登录流程 |
| `src/pkce.rs` | ~27 | PKCE 参数生成 |
| `src/lib.rs` | ~26 | 模块导出、公共 API |
| `src/assets/success.html` | ~198 | 登录成功页面模板 |
| `src/assets/error.html` | ~122 | 登录错误页面模板 |

### 关键函数

```rust
// 公共 API（lib.rs 导出）
pub use device_code_auth::run_device_code_login;      // 设备码登录入口
pub use server::run_login_server;                      // 浏览器登录入口
pub use server::LoginServer;                           // 服务器句柄
pub use server::ServerOptions;                         // 配置选项
pub use server::ShutdownHandle;                        // 关闭控制

// 内部关键函数（server.rs）
pub(crate) async fn exchange_code_for_tokens(...) -> io::Result<ExchangedTokens>;
pub(crate) async fn persist_tokens_async(...) -> io::Result<()>;
pub(crate) fn ensure_workspace_allowed(...) -> Result<(), String>;
pub(crate) async fn obtain_api_key(...) -> io::Result<String>;

// 设备码（device_code_auth.rs）
pub async fn request_device_code(...) -> io::Result<DeviceCode>;
pub async fn complete_device_code_login(...) -> io::Result<()>;
```

### 测试文件

| 文件 | 说明 |
|------|------|
| `tests/suite/login_server_e2e.rs` | 浏览器登录端到端测试（端口绑定、OAuth 回调、token 持久化） |
| `tests/suite/device_code_login.rs` | 设备码登录测试（WireMock 模拟后端） |

---

## 依赖与外部交互

### 内部依赖

```toml
[dependencies]
codex-client = { workspace = true }        # HTTP 客户端（支持自定义 CA）
codex-core = { workspace = true }          # AuthManager, TokenData, 存储
codex-app-server-protocol = { workspace = true }  # AuthMode 枚举
```

### 外部依赖

| Crate | 用途 |
|-------|------|
| `tiny_http` | 本地 HTTP 服务器 |
| `webbrowser` | 自动打开系统浏览器 |
| `reqwest` | HTTP 客户端（设备码轮询、token 交换） |
| `base64`, `sha2`, `rand` | PKCE 实现 |
| `urlencoding` | URL 参数编码 |

### 调用方

| 模块 | 用途 |
|------|------|
| `codex-rs/cli/src/login.rs` | CLI `codex login` 命令实现 |
| `codex-rs/tui/src/onboarding/auth.rs` | TUI 登录界面 |
| `codex-rs/tui/src/onboarding/auth/headless_chatgpt_login.rs` | TUI 设备码登录 |
| `codex-rs/tui_app_server/src/onboarding/auth.rs` | App Server 登录流程 |

---

## 风险、边界与改进建议

### 已知风险

1. **端口冲突**
   - 默认端口 1455 可能被占用
   - 缓解：自动尝试取消占用进程（`send_cancel_request`），最多重试 10 次

2. **浏览器未打开**
   - `webbrowser::open` 可能失败（无浏览器/headless 环境）
   - 缓解：打印授权 URL 供用户手动访问；设备码登录作为备选

3. **Token 泄露风险**
   - 回调 URL 包含敏感参数
   - 缓解：URL 脱敏日志；`Connection: close` 确保连接关闭

4. **设备码钓鱼**
   - 用户可能在恶意页面输入验证码
   - 缓解：UI 明确提示 "Never share this code"

### 边界情况

| 场景 | 行为 |
|------|------|
| 设备码端点 404 | 自动回退到浏览器登录 |
| 15 分钟超时 | 返回 `io::ErrorKind::TimedOut` |
| Workspace 不匹配 | `io::ErrorKind::PermissionDenied` + 明确错误信息 |
| OAuth 拒绝（access_denied） | 特殊处理 `missing_codex_entitlement` 错误，显示友好提示 |
| 端口被占用且无法取消 | 返回 `io::ErrorKind::AddrInUse` |

### 改进建议

1. **端口选择**
   - 当前：固定 1455，冲突时尝试取消占用
   - 建议：支持端口 0（自动分配），减少冲突概率

2. **错误恢复**
   - 当前：token 交换失败直接返回错误
   - 建议：增加重试机制（网络抖动场景）

3. **设备码 UX**
   - 当前：轮询间隔固定（后端返回）
   - 建议：支持指数退避，减少服务器压力

4. **测试覆盖**
   - 当前：依赖 WireMock 模拟后端
   - 建议：增加与真实 auth 服务的集成测试（标记为 `#[ignored]`）

5. **代码组织**
   - `server.rs` 超过 1100 行，职责较重
   - 建议：将 token 交换、workspace 验证、页面渲染拆分为独立模块

---

## 附录：HTML 模板

### 成功页面 (`success.html`)

- 显示 "Signed in to Codex" 成功信息
- 根据 `needs_setup` 参数显示不同的后续引导
- 如需设置，3 秒后自动跳转到 platform.openai.com/org-setup

### 错误页面 (`error.html`)

- 模板变量：`__ERROR_TITLE__`, `__ERROR_MESSAGE__`, `__ERROR_CODE__`, `__ERROR_DESCRIPTION__`, `__ERROR_HELP__`
- 特殊处理 `missing_codex_entitlement`：显示 "You do not have access to Codex" 并引导联系管理员

---

*文档生成时间：2026-03-21*
*研究范围：codex-rs/login 目录及其上下游依赖*
