# rmcp_client.rs 研究文档

## 场景与职责

`rmcp_client.rs` 是 Codex 项目中 MCP (Model Context Protocol) 客户端的核心实现文件。它基于官方的 `rmcp` Rust SDK 构建，提供了与 MCP 服务器通信的完整客户端功能。该模块负责：

1. **MCP 服务器连接管理**：支持两种传输方式 - 子进程 STDIO 和 Streamable HTTP
2. **OAuth 认证集成**：完整的 OAuth 2.0 流程支持，包括令牌存储、刷新和持久化
3. **会话恢复机制**：当 HTTP 会话过期（404）时自动重新初始化
4. **工具调用与资源管理**：提供工具列表、资源读写等 MCP 标准操作
5. **请求头动态注入**：支持工具调用时的请求级自定义头部

## 功能点目的

### 1. 双模式传输支持

**STDIO 模式**：用于本地 MCP 服务器（如通过 npm 安装的 CLI 工具）
- 启动子进程并通过 stdin/stdout 进行 JSON-RPC 通信
- 支持进程组管理，确保清理时终止所有子进程
- 环境变量过滤，只传递必要的系统变量

**Streamable HTTP 模式**：用于远程 MCP 服务器
- 支持 SSE (Server-Sent Events) 流式响应
- 支持会话 ID 管理（`Mcp-Session-Id` 头部）
- 支持 Last-Event-ID 用于断线重连

### 2. OAuth 认证体系

- **令牌存储**：支持 Keyring（系统密钥库）和文件两种存储模式
- **自动刷新**：在令牌过期前自动刷新
- **持久化**：每次操作后自动保存更新后的令牌
- **发现机制**：通过 `.well-known/oauth-authorization-server` 端点自动发现 OAuth 配置

### 3. 会话恢复机制

当 Streamable HTTP 会话返回 404 时，客户端会：
1. 检测 `SessionExpired404` 错误
2. 获取会话恢复锁（防止并发恢复）
3. 使用保存的初始化上下文重新建立连接
4. 重试原始请求

### 4. 工具调用增强

- **Connector ID 提取**：从工具元数据中提取 connector 相关信息
- **请求级头部**：支持为特定工具调用注入自定义 HTTP 头部
- **参数验证**：确保工具参数是 JSON 对象类型

## 具体技术实现

### 关键数据结构

```rust
// 传输层抽象
enum PendingTransport {
    ChildProcess { transport: TokioChildProcess, process_group_guard: Option<ProcessGroupGuard> },
    StreamableHttp { transport: StreamableHttpClientTransport<StreamableHttpResponseClient> },
    StreamableHttpWithOAuth { transport: ..., oauth_persistor: OAuthPersistor },
}

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
```

### 核心流程

#### 初始化流程 (`initialize`)
1. 从 `Connecting` 状态提取 `PendingTransport`
2. 调用 `connect_pending_transport` 建立连接
3. 使用 `service::serve_client` 启动服务
4. 获取服务器信息并保存初始化上下文
5. 转换到 `Ready` 状态

#### 工具调用流程 (`call_tool`)
1. 调用 `refresh_oauth_if_needed` 检查令牌刷新
2. 调用 `run_service_operation` 执行服务操作
3. 内部使用 `run_service_operation_once` 带超时控制
4. 如果检测到会话过期，触发 `reinitialize_after_session_expiry`
5. 成功后调用 `persist_oauth_tokens` 保存令牌

#### HTTP 响应处理 (`post_message`)
1. 构建请求，添加认证头部和会话 ID
2. 检查是否为 `tools/call` 请求，注入请求级头部
3. 发送请求并处理响应状态码
4. 根据 Content-Type 解析响应（SSE 或 JSON）
5. 处理 401 未授权（触发 OAuth 重新认证）

### 会话恢复实现

```rust
async fn reinitialize_after_session_expiry(&self, failed_service: &Arc<...>) -> Result<()> {
    let _recovery_guard = self.session_recovery_lock.lock().await;  // 1. 获取锁
    
    // 2. 检查是否已被其他任务恢复
    if Arc::ptr_eq(service, failed_service) { return Ok(()); }
    
    // 3. 获取初始化上下文
    let initialize_context = self.initialize_context.lock().await.clone()
        .ok_or_else(|| anyhow!("..."))?;
    
    // 4. 重新创建传输层
    let pending_transport = Self::create_pending_transport(...).await?;
    
    // 5. 重新连接
    let (service, oauth_persistor, process_group_guard) = 
        Self::connect_pending_transport(...).await?;
    
    // 6. 更新状态
    *guard = ClientState::Ready { ... };
}
```

### 进程组管理 (Unix)

```rust
#[cfg(unix)]
struct ProcessGroupGuard {
    process_group_id: u32,
}

impl Drop for ProcessGroupGuard {
    fn drop(&mut self) {
        // 1. 发送 SIGTERM
        // 2. 等待 2 秒
        // 3. 如果进程仍在运行，发送 SIGKILL
    }
}
```

## 关键代码路径与文件引用

### 内部依赖

| 文件 | 用途 |
|------|------|
| `utils.rs` | HTTP 头部构建、环境变量过滤 |
| `oauth.rs` | OAuth 令牌存储、刷新、持久化 |
| `logging_client_handler.rs` | MCP 客户端处理器，处理服务器通知 |
| `program_resolver.rs` | 跨平台程序路径解析 |
| `auth_status.rs` | OAuth 发现、认证状态检测 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `rmcp` | 官方 MCP Rust SDK，提供协议实现 |
| `reqwest` | HTTP 客户端 |
| `oauth2` | OAuth 2.0 流程实现 |
| `tokio` | 异步运行时 |
| `sse-stream` | SSE 流解析 |

### 关键常量

```rust
const EVENT_STREAM_MIME_TYPE: &str = "text/event-stream";
const JSON_MIME_TYPE: &str = "application/json";
const HEADER_LAST_EVENT_ID: &str = "Last-Event-Id";
const HEADER_SESSION_ID: &str = "Mcp-Session-Id";
const NON_JSON_RESPONSE_BODY_PREVIEW_BYTES: usize = 8_192;
```

## 依赖与外部交互

### 与 rmcp SDK 的交互

1. **服务启动**：使用 `rmcp::service::serve_client` 启动客户端服务
2. **模型类型**：使用 `rmcp::model::*` 中的请求/响应类型
3. **传输层**：使用 `rmcp::transport::*` 提供的传输实现
4. **认证**：使用 `rmcp::transport::auth::OAuthState` 管理 OAuth 状态

### 与 OAuth 子系统的交互

1. **令牌加载**：`load_oauth_tokens` - 从 keyring 或文件加载
2. **令牌保存**：`save_oauth_tokens` - 持久化到存储
3. **令牌刷新**：`OAuthPersistor::refresh_if_needed` - 自动刷新
4. **令牌持久化**：`OAuthPersistor::persist_if_needed` - 保存更新

### 与配置系统的交互

- `OAuthCredentialsStoreMode` 控制令牌存储位置（Auto/File/Keyring）
- `http_headers` 和 `env_http_headers` 支持静态和动态头部配置

## 风险、边界与改进建议

### 已知风险

1. **会话恢复竞争条件**
   - 使用 `session_recovery_lock` 防止并发恢复
   - 通过 `Arc::ptr_eq` 检查避免重复恢复
   - 风险：如果多个请求同时失败，可能触发多次恢复

2. **OAuth 令牌过期**
   - `refresh_oauth_if_needed` 在每次操作前检查
   - 使用 `REFRESH_SKEW_MILLIS`（30秒）提前刷新
   - 风险：如果刷新失败，操作可能使用过期令牌

3. **进程组清理**
   - Unix 平台使用 `ProcessGroupGuard` 确保清理
   - Windows 平台无进程组支持
   - 风险：Windows 上可能残留孤儿进程

4. **请求头注入**
   - 只有 `tools/call` 请求支持请求级头部
   - 使用 `Arc<StdMutex<Option<HeaderMap>>>` 共享状态
   - 风险：如果设置后未清理，可能影响后续请求

### 边界情况

1. **HTTP 响应处理**
   - 非 JSON 响应截断到 8KB 预览
   - 空内容类型返回 `UnexpectedContentType`
   - 405 Method Not Allowed 在 DELETE 会话时视为成功

2. **超时处理**
   - 初始化、工具调用等操作支持自定义超时
   - 默认无超时（`None`）
   - OAuth 发现超时 5 秒

3. **存储回退**
   - Keyring 失败时自动回退到文件存储
   - 文件存储位置：`CODEX_HOME/.credentials.json`
   - Unix 文件权限设置为 0o600

### 改进建议

1. **连接池管理**
   - 当前每次创建新的 HTTP 客户端
   - 建议：复用 reqwest Client 以支持连接池

2. **重试机制**
   - 仅会话过期有自动重试
   - 建议：添加可配置的重试策略（指数退避）

3. **指标与监控**
   - 缺少操作指标收集
   - 建议：添加 Prometheus/OpenTelemetry 指标

4. **错误分类**
   - 当前错误类型较为通用
   - 建议：细化错误类型，便于调用方处理

5. **请求头清理**
   - 当前依赖调用方清理 `request_headers`
   - 建议：在工具调用后自动清理

6. **会话恢复增强**
   - 当前仅支持 404 恢复
   - 建议：考虑网络错误、超时等情况的恢复

### 测试覆盖

- `tests/streamable_http_recovery.rs`：会话恢复测试
- `tests/process_group_cleanup.rs`：进程清理测试（Unix）
- `tests/resources.rs`：资源读写测试
- `src/bin/test_streamable_http_server.rs`：测试服务器

### 相关配置

```toml
# Cargo.toml 关键依赖
rmcp = { features = [
    "auth",
    "client",
    "transport-child-process",
    "transport-streamable-http-client-reqwest",
] }
reqwest = { features = ["json", "stream", "rustls-tls"] }
oauth2 = "5"
```
