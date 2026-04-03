# server.rs 研究文档

## 场景与职责

`server.rs` 实现了 **OAuth 2.0 Authorization Code Flow** 的本地回调服务器，用于浏览器-based 的交互式登录。这是 Codex CLI 的主要登录方式，用户通过浏览器完成身份验证后，授权服务器将用户重定向回本地运行的 HTTP 服务器。

### 核心使用场景

1. **交互式桌面登录**：用户在图形化环境中运行 Codex CLI
2. **浏览器自动打开**：自动启动系统默认浏览器
3. **单点登录（SSO）体验**：复用浏览器中已有的 OpenAI 会话

### 模块职责

- 启动临时的本地 HTTP 服务器（默认端口 1455）
- 处理 OAuth 回调（`/auth/callback`）
- 交换授权码获取令牌
- 验证工作区限制
- 获取 API Key（通过 token exchange）
- 持久化认证凭据
- 提供用户友好的成功/错误页面

---

## 功能点目的

### 1. 本地回调服务器 (`run_login_server`)

**目的**：启动临时的 HTTP 服务器接收 OAuth 回调

**关键特性**：
- 默认绑定 `127.0.0.1:1455`
- 支持动态端口分配（`port: 0`）
- 自动打开浏览器（`webbrowser::open`）
- 端口占用时自动取消旧服务器

**并发模型**：
- 使用 `tiny_http` 作为同步 HTTP 服务器
- 通过 `std::thread` 将请求转发到 `tokio::sync::mpsc` 通道
- 主循环使用 `tokio::select!` 处理请求和关闭信号

### 2. 请求处理 (`process_request`)

**目的**：路由和处理 HTTP 请求

**路由表**：

| 路径 | 处理 |
|------|------|
| `/auth/callback` | OAuth 回调处理：验证 state、交换令牌、持久化 |
| `/success` | 登录成功页面（内嵌 HTML） |
| `/cancel` | 取消登录，关闭服务器 |
| 其他 | 404 响应 |

### 3. 令牌交换 (`exchange_code_for_tokens`)

**目的**：使用授权码交换访问令牌

**OAuth 参数**：
- `grant_type=authorization_code`
- `code`：回调接收的授权码
- `redirect_uri`：必须与请求时一致
- `client_id`：应用标识
- `code_verifier`：PKCE verifier

**返回令牌**：
- `id_token`：JWT 格式的身份信息
- `access_token`：API 访问令牌
- `refresh_token`：用于刷新访问令牌

### 4. 敏感信息处理

**目的**：在安全日志记录的同时保留调试信息

**脱敏策略**：

```rust
const SENSITIVE_URL_QUERY_KEYS: &[&str] = &[
    "access_token", "api_key", "client_secret", "code",
    "code_verifier", "id_token", "key", "refresh_token",
    "requested_token", "state", "subject_token", "token",
];
```

**处理函数**：
- `redact_sensitive_query_value`：将敏感值替换为 `<redacted>`
- `redact_sensitive_url_parts`：清理 URL 的用户名、密码、片段、敏感查询参数
- `redact_sensitive_error_url`：处理 reqwest 错误中的 URL
- `sanitize_url_for_logging`：用于日志记录的 URL 清理

### 5. 工作区验证 (`ensure_workspace_allowed`)

**目的**：验证用户是否登录到指定的工作区

**验证逻辑**：
- 解析 ID Token 中的 `chatgpt_account_id` 声明
- 与 `forced_chatgpt_workspace_id` 配置比较
- 不匹配时拒绝登录

### 6. API Key 获取 (`obtain_api_key`)

**目的**：通过 Token Exchange 获取 API Key 格式的访问令牌

**流程**：
- 使用 `urn:ietf:params:oauth:grant-type:token-exchange` grant type
- 请求 `openai-api-key` 类型的令牌
- 使用 ID Token 作为 subject token

### 7. 令牌持久化 (`persist_tokens_async`)

**目的**：将获取的令牌保存到本地存储

**执行步骤**：
1. 解析 ID Token JWT 获取声明
2. 提取 `chatgpt_account_id` 作为 `account_id`
3. 创建 `AuthDotJson` 结构
4. 调用 `save_auth` 保存到文件/密钥环

### 8. 成功页面 (`compose_success_url`)

**目的**：构建重定向 URL，传递用户信息到前端页面

**参数**：
- `id_token`：JWT（用于 org-setup 页面）
- `needs_setup`：是否需要完成组织设置
- `org_id`、`project_id`：组织/项目标识
- `plan_type`：订阅计划类型
- `platform_url`：平台 URL

---

## 具体技术实现

### 核心数据结构

```rust
/// 服务器配置选项
pub struct ServerOptions {
    pub codex_home: PathBuf,                    // 配置目录
    pub client_id: String,                      // OAuth Client ID
    pub issuer: String,                         // 授权服务器地址
    pub port: u16,                              // 监听端口（0=随机）
    pub open_browser: bool,                     // 是否自动打开浏览器
    pub force_state: Option<String>,            // 强制 state（测试用）
    pub forced_chatgpt_workspace_id: Option<String>, // 强制工作区
    pub cli_auth_credentials_store_mode: AuthCredentialsStoreMode, // 存储模式
}

/// 运行中的服务器句柄
pub struct LoginServer {
    pub auth_url: String,                       // 浏览器应访问的授权 URL
    pub actual_port: u16,                       // 实际监听端口
    server_handle: tokio::task::JoinHandle<io::Result<()>>,
    shutdown_handle: ShutdownHandle,
}

/// 关闭信号句柄
#[derive(Clone, Debug)]
pub struct ShutdownHandle {
    shutdown_notify: Arc<tokio::sync::Notify>,
}

/// 令牌交换结果
pub(crate) struct ExchangedTokens {
    pub id_token: String,
    pub access_token: String,
    pub refresh_token: String,
}

/// 令牌端点错误详情
#[derive(Debug, Clone, PartialEq, Eq)]
struct TokenEndpointErrorDetail {
    error_code: Option<String>,
    error_message: Option<String>,
    display_message: String,
}
```

### 请求处理枚举

```rust
enum HandledRequest {
    // 普通响应，继续监听
    Response(Response<Cursor<Vec<u8>>>),
    // 重定向响应
    RedirectWithHeader(Header),
    // 响应后退出服务器
    ResponseAndExit {
        headers: Vec<Header>,
        body: Vec<u8>,
        result: io::Result<()>,
    },
}
```

### 授权 URL 构建

```rust
fn build_authorize_url(
    issuer: &str,
    client_id: &str,
    redirect_uri: &str,
    pkce: &PkceCodes,
    state: &str,
    forced_chatgpt_workspace_id: Option<&str>,
) -> String {
    let query = vec![
        ("response_type", "code"),
        ("client_id", client_id),
        ("redirect_uri", redirect_uri),
        ("scope", "openid profile email offline_access api.connectors.read api.connectors.invoke"),
        ("code_challenge", &pkce.code_challenge),
        ("code_challenge_method", "S256"),
        ("id_token_add_organizations", "true"),
        ("codex_cli_simplified_flow", "true"),
        ("state", state),
        ("originator", originator().value.as_str()),
    ];
    // 可选：添加 allowed_workspace_id
    format!("{issuer}/oauth/authorize?{qs}")
}
```

### 端口占用处理 (`bind_server`)

```rust
fn bind_server(port: u16) -> io::Result<Server> {
    loop {
        match Server::http(&bind_address) {
            Ok(server) => return Ok(server),
            Err(err) => {
                // 如果是端口占用，尝试取消旧服务器
                if is_addr_in_use && !cancel_attempted {
                    send_cancel_request(port)?;  // 发送 /cancel 请求
                    cancel_attempted = true;
                }
                // 最多重试 10 次
                if attempts >= MAX_ATTEMPTS {
                    return Err(...);
                }
            }
        }
    }
}
```

### JWT 声明解析

```rust
fn jwt_auth_claims(jwt: &str) -> serde_json::Map<String, serde_json::Value> {
    // JWT 格式: header.payload.signature
    let parts: Vec<&str> = jwt.split('.').collect();
    let payload_b64 = parts[1];
    
    // Base64url 解码 payload
    let payload_bytes = base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(payload_b64)?;
    
    // 解析 JSON 并提取 "https://api.openai.com/auth" 命名空间
    let claims: serde_json::Value = serde_json::from_slice(&payload_bytes)?;
    claims.get("https://api.openai.com/auth").as_object()
}
```

---

## 关键代码路径与文件引用

### 内部调用关系

```
run_login_server
├── bind_server
│   └── send_cancel_request (处理端口占用)
├── generate_pkce (pkce.rs)
├── generate_state
├── build_authorize_url
├── webbrowser::open (可选)
└── 启动异步处理循环
    └── process_request
        ├── /auth/callback
        │   ├── exchange_code_for_tokens
        │   │   └── build_reqwest_client_with_custom_ca (codex_client)
        │   ├── ensure_workspace_allowed
        │   ├── obtain_api_key
        │   └── persist_tokens_async
        │       └── save_auth (codex_core)
        ├── /success (返回 HTML)
        └── /cancel (关闭服务器)
```

### 外部依赖

| 依赖 | 来源 | 用途 |
|------|------|------|
| `PkceCodes`, `generate_pkce` | `crate::pkce` | PKCE 参数生成 |
| `build_reqwest_client_with_custom_ca` | `codex_client` | 带自定义 CA 的 HTTP 客户端 |
| `AuthCredentialsStoreMode`, `AuthDotJson`, `save_auth` | `codex_core::auth` | 认证存储 |
| `TokenData`, `parse_chatgpt_jwt_claims` | `codex_core::token_data` | 令牌数据结构 |
| `originator` | `codex_core::default_client` | 客户端标识 |
| `AuthMode` | `codex_app_server_protocol` | 认证模式枚举 |

### 资源文件

| 文件 | 用途 |
|------|------|
| `src/assets/success.html` | 登录成功页面（内嵌） |
| `src/assets/error.html` | 登录错误页面模板（内嵌） |

### 公开 API

```rust
// 启动登录服务器
pub fn run_login_server(opts: ServerOptions) -> io::Result<LoginServer>

// 服务器句柄方法
impl LoginServer {
    pub async fn block_until_done(self) -> io::Result<()>>
    pub fn cancel(&self)
    pub fn cancel_handle(&self) -> ShutdownHandle
}

// 内部使用（crate 可见）
pub(crate) async fn exchange_code_for_tokens(...) -> io::Result<ExchangedTokens>
pub(crate) async fn persist_tokens_async(...) -> io::Result<()>
pub(crate) fn ensure_workspace_allowed(...) -> Result<(), String>
```

---

## 依赖与外部交互

### HTTP 服务器架构

```
┌─────────────────┐
│   tiny_http     │  同步 HTTP 服务器（独立线程）
│  (blocking)     │
└────────┬────────┘
         │ 请求
         ↓
┌─────────────────┐
│  std::thread    │  转发线程
│  (blocking_send)│
└────────┬────────┘
         │ mpsc::channel
         ↓
┌─────────────────┐
│  tokio::spawn   │  异步处理循环
│  (select!)      │
└─────────────────┘
```

### OAuth 流程交互

```
┌─────────┐     1. 打开浏览器      ┌──────────┐
│  Codex  │ ────────────────────> │  浏览器   │
│  CLI    │                       │          │
│         │ <──────────────────── │          │
│         │     2. 用户登录        │          │
│         │                       │          │
│         │ <──────────────────── │          │
│         │     3. 重定向到        │          │
│         │        localhost      │          │
│         │                       │          │
│         │ ────────────────────> │  Auth    │
│         │     4. 交换令牌        │  Server  │
│         │ <──────────────────── │          │
│         │     5. 返回令牌        │          │
└─────────┘                       └──────────┘
```

### 外部服务端点

| 端点 | 用途 |
|------|------|
| `{issuer}/oauth/authorize` | 授权端点（浏览器打开） |
| `{issuer}/oauth/token` | 令牌交换端点 |
| `{issuer}/oauth/token` (token exchange) | API Key 交换 |

---

## 风险、边界与改进建议

### 安全风险与缓解

| 风险 | 缓解措施 |
|------|----------|
| 授权码拦截 | PKCE (S256) 验证 |
| CSRF 攻击 | State 参数验证 |
| 端口扫描攻击 | 仅绑定 127.0.0.1 |
| 敏感信息泄露 | URL 脱敏处理 |
| 旧服务器挂起 | `/cancel` 机制 |

### 已知边界情况

1. **端口占用处理**
   - 最多重试 10 次
   - 每次等待 200ms
   - 发送 `/cancel` 请求终止旧服务器

2. **浏览器打开失败**
   - `webbrowser::open` 失败被忽略（`let _ =`）
   - 用户可手动复制 `auth_url`

3. **Token Exchange 失败**
   - API Key 获取失败不阻止登录（`.ok()`）
   - 仅记录日志，继续保存其他令牌

4. **并发登录**
   - 新实例会自动取消旧实例
   - 通过 `/cancel` 端点实现

### 代码质量风险

1. **复杂度过高**
   - 文件长度：1196 行
   - 职责过多：HTTP 服务器、OAuth 流程、HTML 渲染、JWT 解析
   - 建议：拆分为子模块（`server/`, `oauth/`, `html/`）

2. **错误处理不一致**
   - 部分错误使用 `eprintln!`
   - 部分错误使用 `tracing::error!`
   - 部分错误直接返回

3. **测试依赖网络**
   - 集成测试需要实际网络或 mock 服务器
   - 使用 `skip_if_no_network!` 宏

### 改进建议

1. **模块化重构**
   ```
   server/
   ├── mod.rs          # 公共 API
   ├── http_server.rs  # HTTP 服务器逻辑
   ├── oauth.rs        # OAuth 流程
   ├── html.rs         # HTML 页面渲染
   └── jwt.rs          # JWT 解析
   ```

2. **配置提取**
   ```rust
   pub struct LoginConfig {
       pub max_bind_attempts: u32,
       pub bind_retry_delay: Duration,
       pub token_exchange_timeout: Duration,
       pub success_redirect_delay: Duration,
   }
   ```

3. **增强可观测性**
   - 添加更多 `tracing` span
   - 记录关键路径耗时
   - 添加结构化日志字段

4. **错误类型优化**
   ```rust
   pub enum LoginError {
       BindFailed { port: u16, attempts: u32 },
       StateMismatch { expected: String, actual: String },
       TokenExchangeFailed { status: u16, detail: TokenEndpointErrorDetail },
       WorkspaceMismatch { expected: String, actual: Option<String> },
   }
   ```

5. **测试改进**
   - 添加单元测试覆盖 `parse_token_endpoint_error`
   - 添加单元测试覆盖 `jwt_auth_claims`
   - 使用 `mockall` 模拟 HTTP 客户端

### 性能考虑

1. **内存使用**
   - HTML 模板使用 `include_str!` 编译时嵌入
   - JWT 解析创建临时字符串

2. **启动时间**
   - 端口绑定可能需要等待旧服务器关闭（最多 2 秒）

3. **并发处理**
   - 单线程处理请求（`tiny_http` 默认）
   - 登录流程是顺序的，无并发需求

### 维护建议

1. **文档同步**：更新 `docs/` 目录下的登录流程文档
2. **安全配置**：`SENSITIVE_URL_QUERY_KEYS` 需要随新 API 更新
3. **HTML 模板**：修改 `success.html`/`error.html` 时需测试多浏览器
4. **OAuth 规范**：跟踪 OAuth 2.1 规范变化
