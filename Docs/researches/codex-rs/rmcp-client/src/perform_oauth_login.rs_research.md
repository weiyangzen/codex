# perform_oauth_login.rs 研究文档

## 场景与职责

`perform_oauth_login.rs` 实现了 MCP 服务器的 OAuth 2.0 登录流程，支持本地回调服务器接收授权码、自动浏览器启动、以及可嵌入外部 UI 的登录模式。该模块是用户与 MCP 服务器进行 OAuth 认证的核心交互组件。

核心职责：
1. **OAuth 登录流程编排**: 完整的授权码流程（Authorization Code Flow）实现
2. **本地回调服务器**: 启动临时 HTTP 服务器接收 OAuth 回调
3. **浏览器集成**: 自动启动系统浏览器进行用户授权
4. **外部 UI 支持**: 提供 `return_url` 模式供外部应用嵌入
5. **错误处理**: 处理 OAuth 提供商返回的错误响应

## 功能点目的

### 1. 两种登录模式

| 模式 | 函数 | 适用场景 |
|------|------|----------|
| 自动浏览器 | `perform_oauth_login()` | CLI 工具，直接完成登录 |
| 返回 URL | `perform_oauth_login_return_url()` | GUI 应用，嵌入外部浏览器 |

### 2. OAuth 流程概览

```
┌─────────┐                                    ┌──────────────┐
│  Client │ ──1. 启动回调服务器────────────────→│ Local Server │
│         │                                    │   (tiny_http)│
│         │ ──2. 获取授权 URL─────────────────→│              │
│         │                                    │              │
│         │ ──3. 打开浏览器/返回 URL───────────→│   User       │
│         │                                    │              │
│         │ ←─4. 用户授权后回调─────────────────│              │
│         │    (code + state)                  │              │
│         │                                    │              │
│         │ ──5. 交换 token───────────────────→│ MCP Server   │
│         │                                    │              │
│         │ ←─6. 存储凭证──────────────────────│              │
└─────────┘                                    └──────────────┘
```

### 3. 回调服务器架构

- 使用 `tiny_http` 创建临时 HTTP 服务器
- 支持自定义端口（`callback_port`）或随机端口（`:0`）
- 支持自定义回调路径（`callback_url`）
- 自动绑定到 `127.0.0.1` 或 `0.0.0.0`（根据配置）

## 具体技术实现

### 核心数据结构

```rust
/// OAuth 登录句柄（return_url 模式）
pub struct OauthLoginHandle {
    authorization_url: String,
    completion: oneshot::Receiver<Result<()>>,
}

/// 回调结果
enum CallbackResult {
    Success(OauthCallbackResult),
    Error(OAuthProviderError),
}

/// 回调解析结果
struct OauthCallbackResult {
    code: String,   // 授权码
    state: String,  // CSRF 状态
}

/// OAuth 提供商错误
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OAuthProviderError {
    error: Option<String>,
    error_description: Option<String>,
}
```

### 主要函数实现

#### `perform_oauth_login()` - 完整自动登录

```rust
pub async fn perform_oauth_login(
    server_name: &str,
    server_url: &str,
    store_mode: OAuthCredentialsStoreMode,
    http_headers: Option<HashMap<String, String>>,
    env_http_headers: Option<HashMap<String, String>>,
    scopes: &[String],
    oauth_resource: Option<&str>,
    callback_port: Option<u16>,
    callback_url: Option<&str>,
) -> Result<()>
```

**流程**：
1. 创建 `OauthLoginFlow`
2. 调用 `finish()` 完成登录（包含浏览器启动）

#### `perform_oauth_login_return_url()` - 返回 URL 模式

```rust
pub async fn perform_oauth_login_return_url(
    server_name: &str,
    server_url: &str,
    store_mode: OAuthCredentialsStoreMode,
    http_headers: Option<HashMap<String, String>>,
    env_http_headers: Option<HashMap<String, String>>,
    scopes: &[String],
    oauth_resource: Option<&str>,
    timeout_secs: Option<i64>,
    callback_port: Option<u16>,
    callback_url: Option<&str>,
) -> Result<OauthLoginHandle>
```

**返回**: `OauthLoginHandle` 包含授权 URL 和完成接收器

#### `OauthLoginFlow::new()` - 流程初始化

```rust
async fn new(
    server_name: &str,
    server_url: &str,
    store_mode: OAuthCredentialsStoreMode,
    headers: OauthHeaders,
    scopes: &[String],
    oauth_resource: Option<&str>,
    launch_browser: bool,
    callback_port: Option<u16>,
    callback_url: Option<&str>,
    timeout_secs: Option<i64>,
) -> Result<Self>
```

**实现细节**：
1. 解析回调绑定地址（默认 `127.0.0.1`）
2. 创建 `tiny_http::Server`
3. 计算重定向 URI 和回调路径
4. 启动回调服务器（`spawn_callback_server`）
5. 初始化 `OAuthState`（来自 `rmcp` SDK）
6. 启动授权流程，获取授权 URL
7. 追加可选的 `resource` 参数

#### `OauthLoginFlow::finish()` - 完成登录

```rust
async fn finish(mut self) -> Result<()>
```

**流程**：
1. 如果 `launch_browser=true`，启动浏览器
2. 等待回调（带超时，默认 300 秒）
3. 解析回调结果（成功/错误）
4. 调用 `oauth_state.handle_callback()` 交换 token
5. 获取凭证并保存

#### `spawn_callback_server()` - 回调服务器

```rust
fn spawn_callback_server(
    server: Arc<Server>,
    tx: oneshot::Sender<CallbackResult>,
    expected_callback_path: String,
)
```

**实现**：
- 使用 `tokio::task::spawn_blocking` 在阻塞线程运行
- 循环接收 HTTP 请求
- 解析路径和查询参数
- 匹配 `expected_callback_path`
- 发送结果到 oneshot channel

#### `parse_oauth_callback()` - 回调解析

```rust
fn parse_oauth_callback(path: &str, expected_callback_path: &str) -> CallbackOutcome
```

**解析逻辑**：
1. 分割路径和查询字符串
2. 验证路径匹配
3. 解析查询参数（`code`, `state`, `error`, `error_description`）
4. URL 解码参数值
5. 返回 `Success`、`Error` 或 `Invalid`

### 回调服务器守卫

```rust
struct CallbackServerGuard {
    server: Arc<Server>,
}

impl Drop for CallbackServerGuard {
    fn drop(&mut self) {
        self.server.unblock();  // 强制解除阻塞，关闭服务器
    }
}
```

**作用**: 确保即使流程提前退出，回调服务器也能被正确关闭

### 辅助函数

#### `callback_bind_host()` - 绑定地址解析

```rust
fn callback_bind_host(callback_url: Option<&str>) -> &'static str {
    // 无配置 → "127.0.0.1"
    // localhost/127.0.0.1/::1 → "127.0.0.1"
    // 其他 → "0.0.0.0" (允许外部访问)
}
```

#### `append_query_param()` - URL 参数追加

```rust
fn append_query_param(url: &str, key: &str, value: Option<&str>) -> String
```

**特性**：
- 使用 `url::Url` 解析时正确编码
- 解析失败时回退到字符串拼接 + `urlencoding::encode`

## 关键代码路径与文件引用

### 内部依赖

| 依赖项 | 路径 | 用途 |
|--------|------|------|
| `OAuthCredentialsStoreMode` | `crate` | 存储模式配置 |
| `StoredOAuthTokens` | `crate` | 凭证结构 |
| `WrappedOAuthTokenResponse` | `crate` | Token 包装 |
| `save_oauth_tokens` | `crate` | 保存凭证 |
| `compute_expires_at_millis` | `crate::oauth` | 计算过期时间 |
| `build_default_headers` | `crate::utils` | 构建 HTTP 头 |
| `apply_default_headers` | `crate::utils` | 应用 HTTP 头 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `rmcp` | `OAuthState` - OAuth 状态机 |
| `tiny_http` | 临时 HTTP 服务器 |
| `tokio::sync::oneshot` | 异步结果传递 |
| `webbrowser` | 系统浏览器启动 |
| `urlencoding` | URL 编码/解码 |

### 调用关系

```
perform_oauth_login.rs
├── 被 lib.rs 导出
│   ├── perform_oauth_login
│   ├── perform_oauth_login_return_url
│   ├── OauthLoginHandle
│   └── OAuthProviderError
├── 调用 oauth.rs
│   ├── save_oauth_tokens()
│   └── compute_expires_at_millis()
└── 调用 utils.rs
    ├── build_default_headers()
    └── apply_default_headers()
```

## 依赖与外部交互

### 与 rmcp SDK 的 OAuth 状态机交互

```rust
// 初始化
let mut oauth_state = OAuthState::new(server_url.to_string(), Some(http_client)).await?;

// 开始授权
let scope_refs: Vec<&str> = scopes.iter().map(String::as_str).collect();
oauth_state.start_authorization(&scope_refs, &redirect_uri, Some("Codex")).await?;

// 获取授权 URL
let auth_url = oauth_state.get_authorization_url().await?;

// 处理回调
oauth_state.handle_callback(&code, &csrf_state).await?;

// 获取凭证
let (client_id, credentials_opt) = oauth_state.get_credentials().await?;
```

### HTTP 交互

**回调请求期望格式**：
```http
GET /callback?code=AUTH_CODE&state=CSRF_STATE HTTP/1.1
```

**错误回调格式**：
```http
GET /callback?error=invalid_scope&error_description=scope%20rejected HTTP/1.1
```

**响应**：
```http
HTTP/1.1 200 OK

Authentication complete. You may close this window.
```

## 风险、边界与改进建议

### 安全风险

1. **CSRF 保护**: 依赖 `rmcp::OAuthState` 的 state 参数验证，需确保其实现正确
2. **本地服务器绑定**: 默认绑定 `127.0.0.1`，但自定义 `callback_url` 可能暴露到网络
3. **HTTP 明文传输**: 本地回调使用 HTTP 而非 HTTPS

### 边界情况

1. **端口冲突**: 使用 `:0` 让系统分配端口可避免冲突
2. **超时处理**: 默认 300 秒超时，可通过 `timeout_secs` 配置
3. **浏览器启动失败**: 失败时打印 URL 提示用户手动打开
4. **回调路径匹配**: 严格匹配路径，查询参数顺序不影响

### 测试覆盖

| 测试用例 | 描述 |
|----------|------|
| `parse_oauth_callback_accepts_default_path` | 默认路径解析 |
| `parse_oauth_callback_accepts_custom_path` | 自定义路径解析 |
| `parse_oauth_callback_rejects_wrong_path` | 错误路径拒绝 |
| `parse_oauth_callback_returns_provider_error` | 错误响应解析 |
| `callback_path_comes_from_redirect_uri` | 回调路径提取 |
| `append_query_param_adds_resource_to_absolute_url` | URL 参数追加 |
| `append_query_param_ignores_empty_values` | 空值处理 |
| `append_query_param_handles_unparseable_url` | 无效 URL 处理 |

### 改进建议

1. **PKCE 支持**: 当前实现依赖 `rmcp::OAuthState`，需确认是否支持 PKCE
2. **并发登录**: 当前不支持多个并发登录流程，可考虑添加流程 ID
3. **状态持久化**: 登录过程中断后无法恢复，可考虑保存 state 到临时存储
4. **自定义响应页面**: 当前使用纯文本响应，可支持 HTML 成功/错误页面
5. **日志增强**: 添加更多诊断日志，便于排查登录问题

### 代码质量

1. **参数数量**: `perform_oauth_login` 有 9 个参数，建议构建器模式
2. **错误处理**: `OAuthProviderError` 已实现 `std::error::Error`，便于错误链
3. **文档完善**: 缺少模块级文档，建议添加 `//!` 文档

### 平台兼容性

| 平台 | 支持状态 | 注意事项 |
|------|----------|----------|
| macOS | ✅ | 浏览器启动正常 |
| Windows | ✅ | 浏览器启动正常 |
| Linux | ✅ | 需确保浏览器可执行 |
| WSL | ⚠️ | 浏览器启动可能失败，依赖 Windows 浏览器 |
