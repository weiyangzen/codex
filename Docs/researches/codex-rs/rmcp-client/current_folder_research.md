# codex-rs/rmcp-client 研究文档

## 概述

`codex-rmcp-client` 是 Codex 项目的核心 MCP (Model Context Protocol) 客户端库，基于官方的 `rmcp` Rust SDK 构建。该库提供了与 MCP 服务器通信的能力，支持多种传输协议（STDIO、Streamable HTTP），并实现了完整的 OAuth 认证流程。

---

## 场景与职责

### 核心场景

1. **MCP 服务器连接管理**：作为 Codex 与外部 MCP 服务器之间的桥梁，管理连接生命周期
2. **工具调用**：执行 MCP 服务器提供的工具（tools）并处理结果
3. **资源访问**：读取 MCP 服务器暴露的资源（resources）
4. **认证管理**：处理 OAuth 2.0 认证流程，安全存储和刷新访问令牌
5. **会话恢复**：在 Streamable HTTP 会话过期时自动重新初始化

### 主要职责

| 职责 | 说明 |
|------|------|
| 协议实现 | 实现 MCP 2025-06-18 协议规范 |
| 传输抽象 | 支持 STDIO 和 Streamable HTTP 两种传输方式 |
| 认证处理 | OAuth 2.0 登录、令牌存储、自动刷新 |
| 错误恢复 | 会话过期检测与自动重连 |
| 进程管理 | Unix 进程组管理，确保子进程正确清理 |

---

## 功能点目的

### 1. RmcpClient - 核心客户端

**文件**: `src/rmcp_client.rs` (1245 行)

主要功能：
- `new_stdio_client()`: 创建基于 STDIO 的 MCP 客户端（用于本地子进程）
- `new_streamable_http_client()`: 创建基于 HTTP 的 MCP 客户端（用于远程服务器）
- `initialize()`: 执行 MCP 初始化握手协议
- `list_tools()`: 获取服务器提供的工具列表
- `call_tool()`: 调用指定工具
- `list_resources()`: 获取资源列表
- `read_resource()`: 读取资源内容

### 2. OAuth 认证系统

**文件**: `src/oauth.rs` (922 行), `src/perform_oauth_login.rs` (594 行), `src/auth_status.rs` (365 行)

功能：
- **令牌存储**: 支持 Keyring（系统密钥库）和文件两种存储模式
- **自动刷新**: 在令牌过期前自动刷新
- **登录流程**: 完整的 OAuth 2.0 PKCE 流程，包括本地回调服务器
- **认证状态检测**: 检测服务器是否支持 OAuth、是否已登录

存储模式 (`OAuthCredentialsStoreMode`):
```rust
pub enum OAuthCredentialsStoreMode {
    Auto,     // 优先 Keyring，失败时回退到文件
    File,     // 仅使用文件存储
    Keyring,  // 仅使用系统密钥库
}
```

### 3. 程序解析器

**文件**: `src/program_resolver.rs` (222 行)

解决跨平台程序执行差异：
- **Unix**: 直接返回程序名，依赖 OS 的 shebang 机制
- **Windows**: 使用 `which` crate 解析完整路径（处理 `.cmd`, `.bat` 等扩展名）

### 4. 日志客户端处理器

**文件**: `src/logging_client_handler.rs` (136 行)

实现 `ClientHandler` trait，处理服务器端通知：
- elicitation 请求（表单/URL 交互）
- 进度通知
- 资源更新通知
- 日志消息（分级处理：error/warning/info/debug）

### 5. 工具函数

**文件**: `src/utils.rs` (194 行)

- `create_env_for_mcp_server()`: 创建 MCP 服务器环境变量
- `build_default_headers()`: 构建 HTTP 请求头
- 平台特定的默认环境变量列表

---

## 具体技术实现

### 关键流程

#### 1. STDIO 客户端创建流程

```
new_stdio_client(program, args, env, env_vars, cwd)
    ↓
TransportRecipe::Stdio { ... }
    ↓
create_pending_transport()
    ↓
program_resolver::resolve()  // 解析程序路径
    ↓
Command::new() + TokioChildProcess::spawn()
    ↓
PendingTransport::ChildProcess { transport, process_group_guard }
```

#### 2. Streamable HTTP 客户端创建流程

```
new_streamable_http_client(server_name, url, bearer_token, ...)
    ↓
TransportRecipe::StreamableHttp { ... }
    ↓
create_pending_transport()
    ↓
load_oauth_tokens()  // 尝试加载已有令牌
    ↓
if 有令牌:
    create_oauth_transport_and_runtime()  // OAuth 模式
else:
    StreamableHttpClientTransport::with_client()  // 普通模式
```

#### 3. 会话恢复流程

当检测到 `SessionExpired404` 错误时：

```
run_service_operation()
    ↓
is_session_expired_404()  // 检测特定错误
    ↓
reinitialize_after_session_expiry()
    ↓
session_recovery_lock.lock()  // 防止并发恢复
    ↓
create_pending_transport()  // 重新创建传输层
    ↓
connect_pending_transport()  // 重新连接
    ↓
重新执行操作
```

#### 4. OAuth 登录流程

```
perform_oauth_login()
    ↓
OauthLoginFlow::new()
    ↓
启动本地回调服务器 (tiny_http)
    ↓
OAuthState::new()  // 初始化 OAuth 状态
    ↓
OAuthState::start_authorization()  // 开始授权
    ↓
webbrowser::open()  // 打开浏览器
    ↓
等待回调 (code + state)
    ↓
OAuthState::handle_callback()  // 处理回调
    ↓
save_oauth_tokens()  // 保存令牌
```

### 关键数据结构

#### ClientState - 客户端状态机

```rust
enum ClientState {
    Connecting {
        transport: Option<PendingTransport>,
    },
    Ready {
        _process_group_guard: Option<ProcessGroupGuard>,
        service: Arc<RunningService<RoleClient, LoggingClientHandler>>,
        oauth: Option<OAuthPersistor>,
    },
}
```

#### PendingTransport - 待连接传输层

```rust
enum PendingTransport {
    ChildProcess {
        transport: TokioChildProcess,
        process_group_guard: Option<ProcessGroupGuard>,
    },
    StreamableHttp {
        transport: StreamableHttpClientTransport<StreamableHttpResponseClient>,
    },
    StreamableHttpWithOAuth {
        transport: StreamableHttpClientTransport<AuthClient<StreamableHttpResponseClient>>,
        oauth_persistor: OAuthPersistor,
    },
}
```

#### StoredOAuthTokens - 存储的 OAuth 令牌

```rust
pub struct StoredOAuthTokens {
    pub server_name: String,
    pub url: String,
    pub client_id: String,
    pub token_response: WrappedOAuthTokenResponse,
    pub expires_at: Option<u64>,  // 毫秒级时间戳
}
```

### 协议实现

#### MCP 协议版本
- 支持协议版本: `2025-06-18`
- 客户端能力: `roots`, `sampling`, `elicitation`

#### HTTP 头处理
关键头定义：
```rust
const EVENT_STREAM_MIME_TYPE: &str = "text/event-stream";
const JSON_MIME_TYPE: &str = "application/json";
const HEADER_LAST_EVENT_ID: &str = "Last-Event-Id";
const HEADER_SESSION_ID: &str = "Mcp-Session-Id";
```

#### OAuth 发现
实现 RFC 8414 第 3.1 节的 OAuth 服务端点发现：
- 尝试路径：`/.well-known/oauth-authorization-server/{path}`
- 回退路径：`/{path}/.well-known/oauth-authorization-server`

---

## 关键代码路径与文件引用

### 核心文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `src/rmcp_client.rs` | 1245 | 核心客户端实现，连接管理，操作执行 |
| `src/oauth.rs` | 922 | OAuth 令牌存储、加载、刷新 |
| `src/perform_oauth_login.rs` | 594 | OAuth 登录流程，本地回调服务器 |
| `src/auth_status.rs` | 365 | 认证状态检测，OAuth 发现 |
| `src/logging_client_handler.rs` | 136 | 客户端处理器，通知处理 |
| `src/utils.rs` | 194 | 工具函数，环境变量处理 |
| `src/program_resolver.rs` | 222 | 跨平台程序路径解析 |
| `src/lib.rs` | 30 | 模块导出 |

### 测试文件

| 文件 | 职责 |
|------|------|
| `tests/process_group_cleanup.rs` | Unix 进程组清理测试 |
| `tests/resources.rs` | 资源列表/读取功能测试 |
| `tests/streamable_http_recovery.rs` | HTTP 会话恢复测试 |

### 测试服务器二进制

| 文件 | 职责 |
|------|------|
| `src/bin/test_stdio_server.rs` | STDIO 测试服务器（工具+资源） |
| `src/bin/test_streamable_http_server.rs` | HTTP 测试服务器（支持会话失败模拟） |
| `src/bin/rmcp_test_server.rs` | 简单 STDIO 测试服务器 |

---

## 依赖与外部交互

### 主要依赖

```toml
# MCP SDK
rmcp = { features = ["auth", "client", "server", "transport-child-process", "transport-streamable-http-client-reqwest"] }

# OAuth
oauth2 = "5"

# HTTP 客户端
reqwest = { version = "0.12", features = ["json", "stream", "rustls-tls"] }

# 本地回调服务器
tiny_http = { workspace = true }

# 密钥存储
keyring = { workspace = true, features = [...] }

# SSE 流处理
sse-stream = "0.2.1"

# 异步运行时
tokio = { workspace = true, features = ["io-util", "macros", "process", "rt-multi-thread", ...] }
```

### 内部依赖

| Crate | 用途 |
|-------|------|
| `codex-client` | HTTP 客户端构建（自定义 CA 证书支持） |
| `codex-keyring-store` | 密钥存储抽象 |
| `codex-protocol` | 协议类型（McpAuthStatus） |
| `codex-utils-pty` | Unix 进程组管理 |
| `codex-utils-home-dir` | CODEX_HOME 路径解析 |

### 调用方

| Crate | 用途 |
|-------|------|
| `codex-core` | `McpConnectionManager` 使用 `RmcpClient` 管理 MCP 连接 |
| `codex-cli` | `mcp_cmd.rs` 使用 OAuth 功能进行登录/登出 |
| `codex-app-server` | 消息处理器使用 MCP 功能 |

---

## 风险、边界与改进建议

### 已知风险

1. **OAuth 令牌安全**
   - 风险：文件存储模式 (`OAuthCredentialsStoreMode::File`) 将令牌存储在明文 JSON 文件中
   - 缓解：默认使用 `Auto` 模式优先尝试系统密钥库

2. **会话恢复竞争条件**
   - 风险：多个并发请求同时触发会话恢复可能导致重复初始化
   - 缓解：使用 `session_recovery_lock` 互斥锁保护恢复流程

3. **进程组清理**
   - 风险：Unix 系统上子进程可能残留
   - 缓解：`ProcessGroupGuard` 在 Drop 时发送 SIGTERM/SIGKILL

4. **回调服务器端口占用**
   - 风险：OAuth 登录时本地回调端口可能被占用
   - 缓解：使用端口 0 让系统自动分配可用端口

### 边界条件

1. **超时处理**
   - 默认启动超时：10 秒
   - 默认工具调用超时：120 秒
   - 可针对每个服务器配置

2. **令牌刷新**
   - 提前 30 秒刷新（`REFRESH_SKEW_MILLIS: u64 = 30_000`）
   - 依赖服务器返回的 `expires_in` 字段

3. **工具名称限制**
   - 最大长度：64 字符
   - 仅允许 ASCII 字母数字、下划线和连字符

### 改进建议

1. **连接池优化**
   - 当前：每个服务器一个独立连接
   - 建议：对高并发场景考虑连接池化

2. **重试策略**
   - 当前：会话过期仅重试一次
   - 建议：实现指数退避重试机制

3. **监控指标**
   - 当前：基础持续时间指标
   - 建议：添加错误率、重连次数等监控

4. **配置热更新**
   - 当前：配置变更需要重启
   - 建议：支持运行时动态添加/移除服务器

5. **OAuth 设备流**
   - 当前：仅支持授权码流程（需要浏览器）
   - 建议：添加设备授权流程支持无浏览器环境

---

## 测试覆盖

### 单元测试
- `auth_status.rs`: OAuth 发现、范围规范化
- `oauth.rs`: 令牌存储/加载/删除（使用 MockKeyringStore）
- `perform_oauth_login.rs`: 回调解析、URL 参数追加
- `program_resolver.rs`: 跨平台程序解析
- `utils.rs`: 环境变量处理

### 集成测试
- `process_group_cleanup.rs`: Unix 进程组终止验证
- `resources.rs`: 资源列表/读取端到端测试
- `streamable_http_recovery.rs`: 会话恢复机制测试（404/401/500 场景）

---

## 相关文档

- [MCP 协议规范](https://modelcontextprotocol.io/specification/2025-06-18/)
- [rmcp Rust SDK](https://github.com/modelcontextprotocol/rust-sdk)
- [RFC 8414 - OAuth 2.0 授权服务器元数据](https://datatracker.ietf.org/doc/html/rfc8414)
