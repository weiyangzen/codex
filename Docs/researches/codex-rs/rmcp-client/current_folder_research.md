# DIR codex-rs/rmcp-client 深度研究文档

## 1. 场景与职责

### 1.1 定位
`codex-rmcp-client` 是 Codex CLI 的 **MCP (Model Context Protocol) 客户端实现层**，基于官方 `rmcp` Rust SDK 构建。它是连接 Codex 与各种 MCP 服务器（本地 STDIO 或远程 HTTP）的桥梁。

### 1.2 核心职责
1. **MCP 服务器连接管理**：支持 STDIO（子进程）和 Streamable HTTP 两种传输方式
2. **OAuth 2.0 认证流程**：完整的 OAuth 登录、令牌存储、刷新和持久化
3. **MCP 协议操作**：工具调用、资源读取、elicitation（交互式表单）处理
4. **会话恢复**：Streamable HTTP 会话过期后的自动重连机制
5. **进程生命周期管理**：Unix 进程组清理，防止 MCP 服务器进程泄漏

### 1.3 使用场景
| 场景 | 说明 |
|------|------|
| 本地 MCP 工具 | 通过 STDIO 连接本地安装的 MCP 服务器（如 `npx @modelcontextprotocol/server-filesystem`） |
| 远程 MCP 服务 | 通过 Streamable HTTP 连接云端 MCP 服务（如 GitHub Copilot MCP、Codex Apps） |
| OAuth 认证 | 为需要 OAuth 的 MCP 服务器提供登录流程和令牌管理 |
| 工具调用 | 代理 LLM 调用 MCP 工具，处理参数和返回结果 |

---

## 2. 功能点目的

### 2.1 双模式传输支持

#### STDIO 传输 (`new_stdio_client`)
- **目的**：连接本地安装的 MCP 服务器程序
- **实现**：通过 `TokioChildProcess` 启动子进程，使用 stdin/stdout 进行 JSON-RPC 通信
- **进程管理**：Unix 系统使用进程组（process group）确保子进程及其后代能被完整清理

#### Streamable HTTP 传输 (`new_streamable_http_client`)
- **目的**：连接远程 MCP 服务端点
- **实现**：基于 SSE (Server-Sent Events) 和 HTTP POST 的流式通信
- **认证支持**：Bearer Token 或 OAuth 2.0

### 2.2 OAuth 2.0 认证系统

#### 认证状态检测 (`auth_status.rs`)
- 检测服务器是否支持 OAuth
- 通过 RFC 8414 定义的 well-known 端点发现 OAuth 元数据
- 返回认证状态：`BearerToken`、`OAuth`、`NotLoggedIn`、`Unsupported`

#### OAuth 登录流程 (`perform_oauth_login.rs`)
- 启动本地回调服务器（tiny_http）
- 打开浏览器进行用户授权
- 处理授权码回调并交换访问令牌
- 支持自定义回调端口和 URL（用于桌面应用集成）

#### 令牌管理 (`oauth.rs`)
- **存储模式**：
  - `Auto`：优先使用系统 keyring，失败则回退到文件
  - `Keyring`：强制使用系统 keyring（macOS Keychain、Windows Credential Manager、Linux Secret Service）
  - `File`：存储在 `CODEX_HOME/.credentials.json`
- **自动刷新**：令牌过期前自动刷新（30秒缓冲）
- **持久化**：令牌变更后自动保存

### 2.3 会话恢复机制

Streamable HTTP 会话可能因服务器重启或超时而过期（返回 404）。`RmcpClient` 实现了自动恢复：

1. 检测 `SessionExpired404` 错误
2. 使用保存的初始化上下文重新连接
3. 重试原始请求（仅重试一次，防止无限循环）

### 2.4 Elicitation 支持

Elicitation 是 MCP 协议中的交互式表单功能，允许服务器向用户请求额外信息：

- **Form Elicitation**：基于 JSON Schema 的表单输入
- **URL Elicitation**：引导用户访问特定 URL
- **回调处理**：通过 `SendElicitation` 回调将请求转发到 UI 层

---

## 3. 具体技术实现

### 3.1 关键数据结构

```rust
// 客户端状态机
enum ClientState {
    Connecting { transport: Option<PendingTransport> },
    Ready {
        _process_group_guard: Option<ProcessGroupGuard>,
        service: Arc<RunningService<RoleClient, LoggingClientHandler>>,
        oauth: Option<OAuthPersistor>,
    },
}

// 传输配置
enum TransportRecipe {
    Stdio { program, args, env, env_vars, cwd },
    StreamableHttp { server_name, url, bearer_token, http_headers, env_http_headers, store_mode },
}

// OAuth 令牌存储
pub struct StoredOAuthTokens {
    pub server_name: String,
    pub url: String,
    pub client_id: String,
    pub token_response: WrappedOAuthTokenResponse,
    pub expires_at: Option<u64>,
}

// Elicitation 回调类型
pub type SendElicitation = Box<
    dyn Fn(RequestId, Elicitation) -> BoxFuture<'static, Result<ElicitationResponse>> + Send + Sync,
>;
```

### 3.2 关键流程

#### 初始化流程 (`initialize`)
```
1. 从 Connecting 状态提取 PendingTransport
2. 根据传输类型创建 RunningService
   - STDIO: serve_client(handler, TokioChildProcess)
   - HTTP: serve_client(handler, StreamableHttpClientTransport)
3. 执行 MCP 初始化握手 (initialize request)
4. 状态转换为 Ready
5. 持久化 OAuth 令牌（如有）
```

#### 工具调用流程 (`call_tool`)
```
1. 检查 OAuth 令牌是否需要刷新
2. 获取 RunningService 引用
3. 调用 rmcp::service::call_tool
4. 如遇到 SessionExpired404：
   a. 获取 session_recovery_lock
   b. 重新创建 PendingTransport
   c. 重新初始化
   d. 重试工具调用
5. 持久化 OAuth 令牌（如有刷新）
```

#### OAuth 登录流程 (`perform_oauth_login`)
```
1. 解析回调端口和绑定地址
2. 启动 tiny_http 回调服务器
3. 创建 OAuthState 并启动授权流程
4. 打开浏览器（如 launch_browser=true）
5. 等待回调或超时
6. 交换授权码获取令牌
7. 保存令牌到 keyring 或文件
```

### 3.3 协议实现细节

#### Streamable HTTP 客户端 (`StreamableHttpResponseClient`)
实现了 `rmcp::transport::streamable_http_client::StreamableHttpClient` trait：

- `post_message`: 发送 JSON-RPC 请求，支持 SSE 和 JSON 响应
- `get_stream`: 建立 SSE 连接接收服务器推送
- `delete_session`: 删除会话（优雅关闭）

**特殊处理**：
- 401 Unauthorized：解析 `WWW-Authenticate` 头，返回 `AuthRequired` 错误
- 404 Not Found：标记为 `SessionExpired404`，触发恢复流程
- 内容类型协商：优先 `text/event-stream`，其次 `application/json`

#### 请求头作用域 (`request_headers`)
某些请求（如 `tools/call`）需要动态添加请求头（如 `ChatGPT-Account-ID`）：

```rust
fn message_uses_request_scoped_headers(message: &ClientJsonRpcMessage) -> bool {
    matches!(message, ClientJsonRpcMessage::Request(request)
        if request.request.method() == "tools/call")
}
```

通过 `Arc<StdMutex<Option<HeaderMap>>>` 实现运行时动态注入。

### 3.4 平台适配

#### Windows 程序解析 (`program_resolver.rs`)
Windows 无法直接执行 `.cmd`、`.bat` 脚本（需要扩展名），使用 `which` crate 解析完整路径：

```rust
#[cfg(windows)]
pub fn resolve(program: OsString, env: &HashMap<String, String>) -> std::io::Result<OsString> {
    let search_path = env.get("PATH");
    match which::which_in(&program, search_path, &cwd) {
        Ok(resolved) => Ok(resolved.into_os_string()),
        Err(_) => Ok(program), // 回退到原始路径
    }
}
```

#### Unix 进程组清理
```rust
#[cfg(unix)]
impl ProcessGroupGuard {
    fn maybe_terminate_process_group(&self) {
        // 1. 发送 SIGTERM
        // 2. 等待 2 秒
        // 3. 如进程仍存在，发送 SIGKILL
    }
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件

| 文件 | 职责 | 关键类型/函数 |
|------|------|--------------|
| `src/lib.rs` | 模块导出 | 公共 API 聚合 |
| `src/rmcp_client.rs` | 主客户端实现 | `RmcpClient`, `ClientState`, `TransportRecipe` |
| `src/oauth.rs` | OAuth 令牌管理 | `StoredOAuthTokens`, `OAuthPersistor`, `load/save_oauth_tokens` |
| `src/perform_oauth_login.rs` | OAuth 登录流程 | `perform_oauth_login`, `OauthLoginFlow`, `OauthLoginHandle` |
| `src/auth_status.rs` | 认证状态检测 | `determine_streamable_http_auth_status`, `discover_streamable_http_oauth` |
| `src/logging_client_handler.rs` | MCP 事件处理 | `LoggingClientHandler` (impl `ClientHandler`) |
| `src/program_resolver.rs` | 跨平台程序解析 | `resolve` |
| `src/utils.rs` | 工具函数 | `create_env_for_mcp_server`, `build_default_headers` |

### 4.2 测试文件

| 文件 | 测试内容 |
|------|----------|
| `tests/process_group_cleanup.rs` | Unix 进程组清理验证 |
| `tests/resources.rs` | MCP 资源列表和读取测试 |
| `tests/streamable_http_recovery.rs` | Streamable HTTP 会话恢复测试 |

### 4.3 测试服务器

| 文件 | 用途 |
|------|------|
| `src/bin/test_stdio_server.rs` | STDIO 传输测试服务器（支持 tools、resources） |
| `src/bin/test_streamable_http_server.rs` | HTTP 传输测试服务器（支持会话故障注入） |
| `src/bin/rmcp_test_server.rs` | 简化版 STDIO 测试服务器 |

### 4.4 关键代码路径

#### 创建 STDIO 客户端
```
RmcpClient::new_stdio_client
  → create_env_for_mcp_server (构建环境变量)
  → program_resolver::resolve (解析程序路径)
  → TokioChildProcess::spawn (启动子进程)
  → PendingTransport::ChildProcess
```

#### 创建 HTTP 客户端
```
RmcpClient::new_streamable_http_client
  → build_default_headers (构建默认请求头)
  → load_oauth_tokens (加载已有令牌)
  → create_oauth_transport_and_runtime (OAuth 模式)
     → OAuthState::new → AuthClient::new
  → StreamableHttpClientTransport::with_client
```

#### 工具调用（含恢复）
```
RmcpClient::call_tool
  → run_service_operation
     → run_service_operation_once
        → service.call_tool (rmcp SDK)
     → 如 SessionExpired404:
        → reinitialize_after_session_expiry
           → create_pending_transport (重建连接)
           → initialize (重新握手)
        → run_service_operation_once (重试)
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

```
codex-rmcp-client
├── codex-client (build_reqwest_client_with_custom_ca)
├── codex-keyring-store (DefaultKeyringStore trait)
├── codex-protocol (McpAuthStatus, McpListToolsResponseEvent)
├── codex-utils-pty (process_group::terminate/kill_process_group)
└── codex-utils-home-dir (find_codex_home)
```

### 5.2 外部依赖

| Crate | 用途 |
|-------|------|
| `rmcp` | 官方 MCP Rust SDK，提供协议实现和传输抽象 |
| `oauth2` | OAuth 2.0 客户端实现 |
| `reqwest` | HTTP 客户端（用于 Streamable HTTP 和 OAuth） |
| `keyring` | 跨平台系统密钥环访问 |
| `tiny_http` | 本地 OAuth 回调服务器 |
| `sse-stream` | SSE (Server-Sent Events) 解析 |
| `axum` | 测试服务器框架（dev dependency） |

### 5.3 调用方

| Crate | 使用方式 |
|-------|----------|
| `codex-core` | `McpConnectionManager` 封装 `RmcpClient`，管理多服务器连接 |
| `codex-cli` | CLI 命令 `codex mcp login` 调用 `perform_oauth_login` |
| `codex-app-server` | 服务端 MCP 功能（如 connectors） |

### 5.4 配置集成

通过 `codex-core::config::types::McpServerConfig` 配置：

```toml
[mcp_servers.github]
transport = { type = "streamable_http", url = "https://api.githubcopilot.com/mcp/" }
bearer_token_env_var = "GITHUB_TOKEN"

[mcp_servers.filesystem]
transport = { type = "stdio", command = "npx", args = ["-y", "@modelcontextprotocol/server-filesystem", "/home/user"] }
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 风险 1：OAuth 令牌存储安全性
- **问题**：`File` 模式将令牌以明文 JSON 存储在 `CODEX_HOME/.credentials.json`
- **缓解**：默认使用 `Auto` 模式优先选择系统 keyring
- **建议**：考虑对文件存储添加加密（如使用系统密钥派生密钥）

#### 风险 2：会话恢复竞争条件
- **问题**：并发请求同时触发会话恢复可能导致多次重连
- **缓解**：使用 `session_recovery_lock: Mutex<()>` 序列化恢复流程
- **边界**：仅重试一次，连续失败则抛出错误

#### 风险 3：进程组清理延迟
- **问题**：Unix 进程组清理使用 `std::thread::sleep` 阻塞线程
- **代码位置**：`ProcessGroupGuard::maybe_terminate_process_group`
- **建议**：考虑使用异步定时器或 tokio 的 spawn_blocking

#### 风险 4：回调服务器端口占用
- **问题**：OAuth 回调服务器绑定 `127.0.0.1:0`（随机端口），可能被防火墙拦截
- **建议**：支持配置固定端口范围，或提供手动复制 URL 的降级方案

### 6.2 边界条件

| 边界 | 行为 |
|------|------|
| OAuth 令牌过期 | 自动刷新（提前 30 秒），刷新失败则报错 |
| 服务器无响应 | 受 `startup_timeout_sec` 控制，默认 10 秒 |
| 工具调用超时 | 受 `tool_timeout_sec` 控制，默认 120 秒 |
| 工具名冲突 | 使用 SHA1 哈希后缀去重，限制 64 字符 |
| 环境变量继承 | 白名单机制，仅传递必要变量（PATH, HOME 等） |

### 6.3 改进建议

#### 建议 1：连接池化
- 当前：每个 MCP 服务器一个独立连接
- 改进：对 Streamable HTTP 支持连接复用和 HTTP/2 多路复用

#### 建议 2：健康检查
- 当前：仅在工具调用时检测会话失效
- 改进：添加后台心跳任务，提前发现连接问题

#### 建议 3：令牌加密
- 当前：文件存储为明文 JSON
- 改进：使用 `keyring` 派生密钥或 `age` 加密令牌文件

#### 建议 4：指标增强
- 当前：仅通过 `tracing` 输出日志
- 改进：集成 `codex-otel` 输出 MCP 调用指标（延迟、成功率等）

#### 建议 5：Windows 服务支持
- 当前：OAuth 回调服务器绑定 IP 地址
- 改进：支持 Windows 命名管道或本地回环地址，提升安全性

### 6.4 测试覆盖

| 测试类型 | 覆盖情况 |
|----------|----------|
| 单元测试 | OAuth 令牌序列化、回调 URL 解析、存储 key 计算 |
| 集成测试 | STDIO 资源操作、HTTP 会话恢复、进程组清理 |
| 手动测试 | `test_stdio_server` 支持 image_scenario 工具用于 TUI 渲染测试 |

**测试缺口**：
- OAuth 完整流程（需要真实 OAuth 提供商）
- 大规模并发工具调用
- 网络分区恢复场景

---

## 7. 附录

### 7.1 MCP 协议版本
- 实现版本：`2025-06-18`
- SDK：`rmcp` (Model Context Protocol Rust SDK)

### 7.2 环境变量

| 变量 | 用途 |
|------|------|
| `CODEX_HOME` | 配置文件和令牌存储根目录 |
| `CODEX_CONNECTORS_TOKEN` | Codex Apps MCP 的 Bearer Token |
| `MCP_STREAMABLE_HTTP_BIND_ADDR` | 测试服务器绑定地址 |
| `MCP_TEST_VALUE` | 测试服务器环境变量快照 |

### 7.3 相关文档
- [MCP 协议规范](https://modelcontextprotocol.io/specification/2025-06-18)
- [rmcp Rust SDK](https://github.com/modelcontextprotocol/rust-sdk)
- [RFC 8414 - OAuth 2.0 授权服务器元数据](https://datatracker.ietf.org/doc/html/rfc8414)
