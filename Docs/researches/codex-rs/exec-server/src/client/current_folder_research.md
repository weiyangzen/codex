# codex-rs/exec-server/src/client 研究文档

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

`codex-rs/exec-server/src/client` 目录是 `codex-exec-server` crate 的客户端实现核心，负责提供与执行服务器（exec-server）通信的 Rust 客户端库。该模块设计用于支持两种运行模式：

1. **远程 WebSocket 模式**：通过 WebSocket 连接到独立运行的 exec-server 进程
2. **进程内模式（In-Process）**：直接在本地内存中调用服务器处理程序，无需网络通信

### 核心职责

- **连接管理**：建立和维护与 exec-server 的连接（WebSocket 或进程内）
- **协议握手**：实现 JSON-RPC 初始化握手流程（initialize → initialized）
- **请求/响应处理**：发送 RPC 请求并处理响应，支持异步并发请求
- **后端抽象**：统一远程和本地两种后端的行为接口
- **生命周期管理**：确保连接正确关闭和资源清理

### 在架构中的位置

```
┌─────────────────────────────────────────────────────────────┐
│                    调用方 (如 codex-core)                     │
├─────────────────────────────────────────────────────────────┤
│  ExecServerClient (本模块)                                   │
│  ├── ClientBackend::Remote (WebSocket)                      │
│  └── ClientBackend::InProcess (LocalBackend)                │
├─────────────────────────────────────────────────────────────┤
│  JsonRpcConnection → RpcClient                              │
├─────────────────────────────────────────────────────────────┤
│  WebSocket Transport / In-Process Direct Call               │
├─────────────────────────────────────────────────────────────┤
│  ExecServerHandler (server side)                            │
└─────────────────────────────────────────────────────────────┘
```

---

## 功能点目的

### 1. ExecServerClient - 主客户端结构

`ExecServerClient` 是面向使用者的主要接口，提供以下能力：

| 方法 | 用途 |
|------|------|
| `connect_websocket()` | 通过 WebSocket URL 连接到远程 exec-server |
| `connect_in_process()` | 创建进程内本地后端实例 |
| `initialize()` | 执行初始化握手（可重复调用） |

### 2. 双后端架构

通过 `ClientBackend` 枚举实现双模式支持：

```rust
enum ClientBackend {
    Remote(RpcClient),      // WebSocket 远程连接
    InProcess(LocalBackend), // 本地直接调用
}
```

**设计目的**：
- 允许同一套客户端代码在"独立服务器"和"嵌入式"两种场景下工作
- 便于测试（无需启动真实服务器进程）
- 支持未来可能的混合部署模式

### 3. 初始化握手协议

实现 LSP 风格的初始化序列：

```
Client                          Server
  |                               |
  |---- initialize request ----->|
  |<--- initialize response -----|
  |---- initialized notify ----->|
  |                               |
  [Ready for exec/filesystem ops]
```

**目的**：确保双方就协议版本和能力达成一致，防止不兼容的请求。

### 4. 超时控制

| 超时类型 | 默认值 | 用途 |
|---------|--------|------|
| `CONNECT_TIMEOUT` | 10s | WebSocket 连接建立超时 |
| `INITIALIZE_TIMEOUT` | 10s | 初始化握手完成超时 |

---

## 具体技术实现

### 3.1 关键数据结构

#### ExecServerClient

```rust
#[derive(Clone)]
pub struct ExecServerClient {
    inner: Arc<Inner>,
}

struct Inner {
    backend: ClientBackend,
    reader_task: tokio::task::JoinHandle<()>,
}
```

- 使用 `Arc<Inner>` 实现客户端的克隆共享
- `reader_task` 负责在后台处理服务器事件（通知、断开连接等）

#### ExecServerError

```rust
pub enum ExecServerError {
    Spawn(std::io::Error),           // 启动服务器失败
    WebSocketConnectTimeout { url, timeout },
    WebSocketConnect { url, source },
    InitializeTimedOut { timeout },
    Closed,                          // 连接已关闭
    Json(serde_json::Error),         // 序列化错误
    Protocol(String),                // 协议错误
    Server { code: i64, message },   // 服务器返回错误
}
```

### 3.2 连接流程

#### WebSocket 连接流程

```rust
pub async fn connect_websocket(args: RemoteExecServerConnectArgs) -> Result<Self, ExecServerError> {
    // 1. 建立 WebSocket 连接（带超时）
    let (stream, _) = timeout(connect_timeout, connect_async(websocket_url)).await?;
    
    // 2. 包装为 JsonRpcConnection
    let conn = JsonRpcConnection::from_websocket(stream, label);
    
    // 3. 创建 RpcClient 并启动 reader_task
    let (rpc_client, events_rx) = RpcClient::new(conn);
    let reader_task = tokio::spawn(async move {
        while let Some(event) = events_rx.recv().await {
            match event {
                RpcClientEvent::Notification(n) => warn!("unexpected notification"),
                RpcClientEvent::Disconnected { reason } => { /* 处理断开 */ }
            }
        }
    });
    
    // 4. 执行初始化握手
    client.initialize(options).await?;
    Ok(client)
}
```

#### 进程内连接流程

```rust
pub async fn connect_in_process(options: ExecServerClientConnectOptions) -> Result<Self, ExecServerError> {
    // 1. 直接创建 LocalBackend，包装 ExecServerHandler
    let backend = LocalBackend::new(ExecServerHandler::new());
    
    // 2. 创建空 reader_task（无实际 I/O）
    let reader_task = tokio::spawn(async {});
    
    // 3. 执行相同的初始化流程
    client.initialize(options).await?;
    Ok(client)
}
```

### 3.3 LocalBackend 实现

```rust
#[derive(Clone)]
pub(super) struct LocalBackend {
    handler: Arc<ExecServerHandler>,
}

impl LocalBackend {
    pub(super) async fn initialize(&self) -> Result<InitializeResponse, ExecServerError> {
        self.handler.initialize().map_err(|e| ExecServerError::Server { ... })
    }
    
    pub(super) async fn initialized(&self) -> Result<(), ExecServerError> {
        self.handler.initialized().map_err(ExecServerError::Protocol)
    }
    
    pub(super) async fn shutdown(&self) {
        self.handler.shutdown().await;
    }
}
```

**关键设计**：
- `LocalBackend` 直接调用 `ExecServerHandler` 的方法，绕过 JSON-RPC 序列化
- 使用 `Arc<ExecServerHandler>` 实现克隆共享
- 错误转换：将 handler 的错误转换为 `ExecServerError`

### 3.4 生命周期管理

#### Drop 实现

```rust
impl Drop for Inner {
    fn drop(&mut self) {
        // 1. 如果是本地后端，异步调用 shutdown
        if let Some(backend) = self.backend.as_local() {
            if let Ok(handle) = tokio::runtime::Handle::try_current() {
                handle.spawn(async move { backend.shutdown().await });
            }
        }
        // 2. 中止 reader_task
        self.reader_task.abort();
    }
}
```

**注意点**：
- 本地后端的 shutdown 在 Drop 时异步执行，不阻塞当前线程
- reader_task 被强制中止，可能导致未处理的消息丢失

### 3.5 协议常量

```rust
// protocol.rs
pub const INITIALIZE_METHOD: &str = "initialize";
pub const INITIALIZED_METHOD: &str = "initialized";

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InitializeParams {
    pub client_name: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InitializeResponse {}
```

---

## 关键代码路径与文件引用

### 4.1 文件结构

```
codex-rs/exec-server/src/
├── client.rs              # 主客户端实现，ExecServerClient
├── client/
│   └── local_backend.rs   # 本地后端实现
├── client_api.rs          # 公共 API 类型定义
├── connection.rs          # JSON-RPC 连接抽象（WebSocket/stdio）
├── rpc.rs                 # RpcClient 实现
├── protocol.rs            # 协议消息类型
├── server.rs              # 服务器入口
├── server/
│   ├── handler.rs         # ExecServerHandler
│   ├── processor.rs       # 连接消息处理
│   ├── jsonrpc.rs         # JSON-RPC 工具函数
│   └── transport.rs       # WebSocket 传输层
└── bin/
    └── codex-exec-server.rs # 独立二进制入口
```

### 4.2 关键代码路径

#### 初始化流程

```
ExecServerClient::connect_websocket()
  └─> connect_async()                    [tokio-tungstenite]
      └─> JsonRpcConnection::from_websocket()
          └─> RpcClient::new()
              └─> spawn reader_task
          └─> ExecServerClient::initialize()
              └─> RpcClient::call(INITIALIZE_METHOD)
                  └─> RpcClient::notify(INITIALIZED_METHOD)
```

#### 进程内流程

```
ExecServerClient::connect_in_process()
  └─> LocalBackend::new(ExecServerHandler::new())
      └─> ExecServerClient::initialize()
          └─> LocalBackend::initialize()
              └─> ExecServerHandler::initialize()
          └─> LocalBackend::initialized()
              └─> ExecServerHandler::initialized()
```

### 4.3 测试相关

| 测试文件 | 测试内容 |
|---------|---------|
| `tests/initialize.rs` | 初始化握手测试 |
| `tests/websocket.rs` | WebSocket 连接和错误处理测试 |
| `tests/process.rs` | 进程启动 stub 测试 |
| `tests/common/exec_server.rs` | 测试工具：启动 exec-server 进程 |
| `rpc.rs` (mod tests) | RpcClient 单元测试（请求 ID 匹配） |

---

## 依赖与外部交互

### 5.1 外部依赖

| Crate | 用途 |
|-------|------|
| `tokio` | 异步运行时、任务管理、超时 |
| `tokio-tungstenite` | WebSocket 客户端连接 |
| `serde`/`serde_json` | JSON 序列化/反序列化 |
| `futures` | Stream/Sink trait |
| `thiserror` | 错误定义宏 |
| `tracing` | 日志记录 |
| `clap` | 命令行参数（二进制） |

### 5.2 内部依赖

| Crate | 交互内容 |
|-------|---------|
| `codex-app-server-protocol` | JSON-RPC 消息类型定义（`JSONRPCMessage`, `JSONRPCRequest`, `JSONRPCResponse`, `JSONRPCError` 等） |
| `codex-utils-cargo-bin` | 测试时定位编译后的二进制文件 |

### 5.3 协议依赖

客户端与服务端通过 `codex-app-server-protocol` 定义的 JSON-RPC 2.0 子集通信：

- **请求**：`{ id, method, params, trace? }`
- **响应**：`{ id, result }`
- **错误**：`{ id, error: { code, message, data? } }`
- **通知**：`{ method, params }`

---

## 风险、边界与改进建议

### 6.1 当前风险

#### 1. 请求 ID 溢出风险

```rust
// rpc.rs
let request_id = RequestId::Integer(self.next_request_id.fetch_add(1, Ordering::SeqCst));
```

- `next_request_id` 是 `AtomicI64`，长时间运行可能溢出
- **建议**：使用循环 ID 或 UUID

#### 2. Drop 时的异步 shutdown 不可靠

```rust
impl Drop for Inner {
    fn drop(&mut self) {
        if let Some(backend) = self.backend.as_local() {
            if let Ok(handle) = tokio::runtime::Handle::try_current() {
                handle.spawn(async move { backend.shutdown().await }); // 不等待完成
            }
        }
        self.reader_task.abort(); // 强制中止
    }
}
```

- `shutdown()` 被 spawn 后不等待完成，可能资源泄漏
- `reader_task.abort()` 可能丢失未处理的消息
- **建议**：提供显式的 `async shutdown()` 方法供调用者使用

#### 3. 远程后端的通知处理 stub

```rust
// client.rs reader_task
RpcClientEvent::Notification(notification) => {
    warn!("ignoring unexpected exec-server notification during stub phase: {}", notification.method);
}
```

- 当前忽略所有服务器通知，仅记录警告
- 未来需要实现通知处理（如 `command/exec/outputDelta`, `command/exec/exited`）

#### 4. 初始化状态检查不足

```rust
// server/handler.rs
pub(crate) fn initialize(&self) -> Result<InitializeResponse, JSONRPCErrorError> {
    if self.initialize_requested.swap(true, Ordering::SeqCst) {
        return Err(invalid_request("initialize may only be sent once per connection".to_string()));
    }
    Ok(InitializeResponse {})
}
```

- 服务端检查重复初始化，但客户端没有相应的状态跟踪
- **建议**：客户端也维护初始化状态，避免重复调用

### 6.2 边界情况

| 场景 | 当前行为 | 建议 |
|------|---------|------|
| WebSocket 连接超时 | 返回 `WebSocketConnectTimeout` | ✅ 合理 |
| 初始化超时 | 返回 `InitializeTimedOut` | ✅ 合理 |
| 服务器返回错误 | 转换为 `ExecServerError::Server` | ✅ 合理 |
| 连接断开 | reader_task 收到 `Disconnected` 事件 | 需要暴露给调用者 |
| 并发请求 | RpcClient 使用 HashMap 跟踪 pending | ✅ 支持乱序响应 |
| 进程内模式错误 | 直接返回，无序列化开销 | ✅ 高效 |

### 6.3 改进建议

#### 1. 添加显式关闭方法

```rust
impl ExecServerClient {
    pub async fn shutdown(self) -> Result<(), ExecServerError> {
        // 1. 发送关闭通知（如有需要）
        // 2. 等待 reader_task 完成
        // 3. 调用 backend shutdown
        // 4. 清理资源
    }
}
```

#### 2. 实现通知处理机制

```rust
pub enum ExecServerEvent {
    OutputDelta { process_id: String, stream: String, chunk: Vec<u8> },
    ProcessExited { process_id: String, exit_code: i32 },
    Disconnected { reason: Option<String> },
}

// 在 connect 时传入事件处理器
pub async fn connect_websocket(
    args: RemoteExecServerConnectArgs,
    event_handler: mpsc::Sender<ExecServerEvent>,
) -> Result<Self, ExecServerError>
```

#### 3. 添加连接健康检查

```rust
impl ExecServerClient {
    pub fn is_connected(&self) -> bool {
        // 检查 reader_task 是否仍在运行
        !self.inner.reader_task.is_finished()
    }
}
```

#### 4. 支持重连机制

```rust
pub struct ExecServerClientConfig {
    pub max_reconnect_attempts: u32,
    pub reconnect_backoff: Duration,
    // ...
}
```

#### 5. 完善文档和示例

- 添加更多使用示例（特别是进程内模式）
- 文档化错误处理最佳实践
- 说明何时使用 WebSocket 模式 vs 进程内模式

### 6.4 测试覆盖建议

| 测试场景 | 优先级 |
|---------|--------|
| 进程内模式完整流程 | 高 |
| 连接断开后的错误处理 | 高 |
| 并发请求性能测试 | 中 |
| 超时边界测试（刚好超时） | 中 |
| 通知处理（未来实现） | 高 |
| 资源泄漏检查（长时运行） | 中 |

---

## 总结

`codex-rs/exec-server/src/client` 模块实现了一个设计良好的双模式客户端，能够同时支持远程 WebSocket 连接和本地进程内调用。其核心设计亮点包括：

1. **统一抽象**：通过 `ClientBackend` 枚举隐藏远程/本地差异
2. **类型安全**：完整的错误类型和协议类型定义
3. **异步友好**：基于 tokio 的完全异步实现
4. **资源管理**：Drop 实现确保基本清理

当前主要限制在于通知处理尚未实现，且资源清理在 Drop 中不够可靠。随着 exec-server 功能的扩展（实现 `command/exec` 等方法），客户端需要相应扩展以支持服务器推送通知的处理。
