# codex-rs/exec-server 深度研究文档

## 1. 场景与职责

### 1.1 定位与目标

`codex-exec-server` 是一个独立的 JSON-RPC 服务器，专门用于：

1. **进程生命周期管理**：创建、控制、终止子进程
2. **交互式执行支持**：通过 PTY（伪终端）支持交互式命令（如 bash、vim 等）
3. **输出流管理**：异步收集 stdout/stderr 输出并通过 WebSocket 流式传输
4. **统一执行抽象**：为 Codex 核心提供与底层执行机制解耦的接口

### 1.2 架构位置

```
┌─────────────────────────────────────────────────────────────────┐
│                        Codex 应用层                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │   codex-cli │  │ codex-tui   │  │  codex-app-server       │  │
│  └──────┬──────┘  └──────┬──────┘  └───────────┬─────────────┘  │
└─────────┼────────────────┼─────────────────────┼────────────────┘
          │                │                     │
          └────────────────┴──────────┬──────────┘
                                      ▼
                    ┌─────────────────────────────────┐
                    │    codex-exec-server (本组件)    │
                    │  ┌───────────────────────────┐  │
                    │  │  WebSocket JSON-RPC 服务   │  │
                    │  │  - 进程创建/终止           │  │
                    │  │  - 输入写入 (PTY)          │  │
                    │  │  - 输出流订阅              │  │
                    │  └───────────────────────────┘  │
                    └───────────────┬─────────────────┘
                                    │
                    ┌───────────────┴─────────────────┐
                    │      codex-utils-pty            │
                    │  - PTY 进程创建 (portable-pty)  │
                    │  - Pipe 进程创建                │
                    │  - 进程组管理                    │
                    └─────────────────────────────────┘
```

### 1.3 使用场景

| 场景 | 说明 |
|------|------|
| **本地开发** | 独立二进制运行，通过 WebSocket 接受命令执行请求 |
| **集成测试** | 提供 `ExecServerClient` 用于自动化测试进程执行 |
| **远程执行** | 未来可扩展为远程执行服务器（当前仅本地） |
| **进程隔离** | 每个连接拥有独立的进程命名空间，连接断开自动清理 |

---

## 2. 功能点目的

### 2.1 核心功能模块

| 功能模块 | 目的 | 当前状态 |
|---------|------|---------|
| **传输层** | WebSocket 上的 JSON-RPC 通信 | ✅ 完整实现 |
| **握手协议** | `initialize` → `initialized` 生命周期 | ✅ 完整实现 |
| **进程执行** | `command/exec` 创建管理进程 | ⚠️ Stub（待实现） |
| **输入写入** | `command/exec/write` 向 PTY 写入 | ⚠️ Stub（待实现） |
| **进程终止** | `command/exec/terminate` 终止进程 | ⚠️ Stub（待实现） |
| **输出通知** | `command/exec/outputDelta` 流式输出 | ⚠️ Stub（待实现） |
| **退出通知** | `command/exec/exited` 进程退出事件 | ⚠️ Stub（待实现） |

### 2.2 设计决策

1. **独立进程 vs 库集成**：
   - 当前 PR 仅提供独立二进制，未集成到主 Codex CLI
   - 提供 `connect_in_process` 模式用于同进程内测试

2. **WebSocket 作为默认传输**：
   - 支持 `ws://IP:PORT` 格式
   - 每个消息一个 JSON-RPC 帧

3. **双向通信模型**：
   - 客户端 → 服务器：Request（期望响应）
   - 服务器 → 客户端：Notification（单向事件，如输出、退出）

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 协议类型（`protocol.rs`）

```rust
// 握手参数
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InitializeParams {
    pub client_name: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InitializeResponse {}
```

#### 3.1.2 连接抽象（`connection.rs`）

```rust
pub(crate) const CHANNEL_CAPACITY: usize = 128;

pub(crate) enum JsonRpcConnectionEvent {
    Message(JSONRPCMessage),
    MalformedMessage { reason: String },
    Disconnected { reason: Option<String> },
}

pub(crate) struct JsonRpcConnection {
    outgoing_tx: mpsc::Sender<JSONRPCMessage>,
    incoming_rx: mpsc::Receiver<JsonRpcConnectionEvent>,
    task_handles: Vec<tokio::task::JoinHandle<()>>,
}
```

#### 3.1.3 客户端后端枚举（`client.rs`）

```rust
enum ClientBackend {
    Remote(RpcClient),      // WebSocket 连接
    InProcess(LocalBackend), // 同进程内直接调用
}
```

### 3.2 关键流程

#### 3.2.1 服务器启动流程

```
main() (codex-exec-server.rs)
    │
    ▼
run_main_with_listen_url(url) (server.rs)
    │
    ▼
parse_listen_url(url) → SocketAddr
    │
    ▼
run_websocket_listener(bind_address)
    │
    ├── TcpListener::bind(bind_address)
    │
    └── loop {
            TcpListener::accept()
            accept_async(stream)  // tokio-tungstenite
            run_connection(JsonRpcConnection::from_websocket(...))
        }
```

#### 3.2.2 连接处理流程（`processor.rs`）

```
run_connection(connection)
    │
    ├── connection.into_parts() → (outgoing_tx, incoming_rx, tasks)
    │
    ├── ExecServerHandler::new()  // 每个连接一个 handler
    │
    └── while let Some(event) = incoming_rx.recv().await {
            match event {
                Message(msg) => {
                    handle_connection_message(&handler, msg)
                        ├── dispatch_request() → JSONRPCMessage
                        └── handle_notification() → Result<(), String>
                }
                MalformedMessage { reason } → send_error_response
                Disconnected { reason } → break
            }
        }
    │
    └── handler.shutdown().await  // 清理资源
```

#### 3.2.3 客户端连接流程（`client.rs`）

```
ExecServerClient::connect_websocket(args)
    │
    ├── connect_async(websocket_url)  // 带超时
    │
    ├── JsonRpcConnection::from_websocket(stream, label)
    │
    ├── RpcClient::new(connection) → (rpc_client, events_rx)
    │
    ├── spawn(reader_task)  // 处理服务器通知
    │
    └── client.initialize(options)
            ├── RpcClient::call("initialize", params)
            └── notify_initialized() → RpcClient::notify("initialized", {})
```

#### 3.2.4 同进程内连接（测试模式）

```
ExecServerClient::connect_in_process(options)
    │
    ├── LocalBackend::new(ExecServerHandler::new())
    │
    ├── Arc::new(Inner { backend: InProcess(backend), ... })
    │
    └── client.initialize(options)
            └── LocalBackend::initialize() → handler.initialize()
```

### 3.3 JSON-RPC 协议实现

#### 3.3.1 消息类型（来自 `codex-app-server-protocol`）

```rust
pub enum JSONRPCMessage {
    Request(JSONRPCRequest),
    Notification(JSONRPCNotification),
    Response(JSONRPCResponse),
    Error(JSONRPCError),
}

pub struct JSONRPCRequest {
    pub id: RequestId,           // Integer | String
    pub method: String,
    pub params: Option<Value>,
    pub trace: Option<W3cTraceContext>,
}

pub struct JSONRPCNotification {
    pub method: String,
    pub params: Option<Value>,
}
```

#### 3.3.2 错误码定义（`server/jsonrpc.rs`）

| 错误码 | 含义 | 使用场景 |
|-------|------|---------|
| -32600 | Invalid Request | 格式错误、非 initialized 通知 |
| -32601 | Method Not Found | 未实现的方法（当前所有 exec 方法） |
| -32602 | Invalid Params | 参数解析失败、重复 processId |
| -32603 | Internal Error | 内部错误 |

### 3.4 WebSocket 传输实现

#### 3.4.1 读取端（`connection.rs:126-195`）

```rust
let reader_task = tokio::spawn(async move {
    loop {
        match websocket_reader.next().await {
            Some(Ok(Message::Text(text))) => {
                match serde_json::from_str::<JSONRPCMessage>(&text) {
                    Ok(msg) => incoming_tx.send(Message(msg)).await,
                    Err(err) => send_malformed_message(...),
                }
            }
            Some(Ok(Message::Binary(bytes))) => { /* 类似处理 */ }
            Some(Ok(Message::Close(_))) => { /* 断开连接 */ }
            Some(Ok(Message::Ping(_) | Message::Pong(_))) => { /* 忽略 */ }
            Some(Err(err)) => { /* 错误断开 */ }
            None => { /* 正常断开 */ }
        }
    }
});
```

#### 3.4.2 写入端（`connection.rs:197-225`）

```rust
let writer_task = tokio::spawn(async move {
    while let Some(message) = outgoing_rx.recv().await {
        match serialize_jsonrpc_message(&message) {
            Ok(encoded) => {
                websocket_writer.send(Message::Text(encoded.into())).await
            }
            Err(err) => { /* 序列化错误 */ }
        }
    }
});
```

### 3.5 客户端 RPC 实现（`rpc.rs`）

#### 3.5.1 请求-响应匹配

```rust
pub(crate) async fn call<P, T>(&self, method: &str, params: &P) -> Result<T, RpcCallError>
where
    P: Serialize,
    T: DeserializeOwned,
{
    let request_id = RequestId::Integer(
        self.next_request_id.fetch_add(1, Ordering::SeqCst)
    );
    
    // 注册 pending 请求
    let (response_tx, response_rx) = oneshot::channel();
    self.pending.lock().await.insert(request_id.clone(), response_tx);
    
    // 发送请求
    self.write_tx.send(JSONRPCMessage::Request(...)).await?;
    
    // 等待响应
    let result = response_rx.await?;
    serde_json::from_value(result)?
}
```

#### 3.5.2 消息分发（`handle_server_message`）

```rust
async fn handle_server_message(...) -> Result<(), String> {
    match message {
        Response(JSONRPCResponse { id, result }) => {
            if let Some(pending) = pending.lock().await.remove(&id) {
                pending.send(Ok(result));
            }
        }
        Error(JSONRPCError { id, error }) => {
            if let Some(pending) = pending.lock().await.remove(&id) {
                pending.send(Err(error));
            }
        }
        Notification(notification) => {
            event_tx.send(RpcClientEvent::Notification(notification)).await;
        }
        Request(request) => Err("unexpected request from server"),
    }
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 源文件结构

```
codex-rs/exec-server/src/
├── bin/
│   └── codex-exec-server.rs      # 独立二进制入口
├── lib.rs                        # 库入口，模块声明
├── protocol.rs                   # 协议类型定义（InitializeParams/Response）
├── client.rs                     # 客户端实现（ExecServerClient）
├── client_api.rs                 # 客户端 API 类型定义
├── client/
│   └── local_backend.rs          # 同进程内后端实现
├── rpc.rs                        # RPC 客户端实现（RpcClient）
├── connection.rs                 # 传输连接抽象（WebSocket/stdio）
└── server/
    ├── mod.rs                    # 服务器模块入口
    ├── handler.rs                # ExecServerHandler（业务逻辑）
    ├── processor.rs              # 连接处理循环
    ├── jsonrpc.rs                # JSON-RPC 辅助函数
    ├── transport.rs              # WebSocket 传输层
    └── transport_tests.rs        # 传输层单元测试
```

### 4.2 关键代码路径

| 功能 | 文件 | 行号范围 |
|-----|------|---------|
| 服务器启动 | `server/transport.rs` | 49-82 |
| URL 解析 | `server/transport.rs` | 35-47 |
| 连接处理主循环 | `server/processor.rs` | 18-61 |
| 请求分发 | `server/processor.rs` | 84-111 |
| 通知处理 | `server/processor.rs` | 113-121 |
| 握手状态机 | `server/handler.rs` | 24-39 |
| WebSocket 读取 | `connection.rs` | 126-195 |
| WebSocket 写入 | `connection.rs` | 197-225 |
| RPC 请求发送 | `rpc.rs` | 115-156 |
| RPC 响应处理 | `rpc.rs` | 180-210 |
| 客户端连接 | `client.rs` | 137-161 |
| 同进程连接 | `client.rs` | 124-135 |

### 4.3 测试文件

```
codex-rs/exec-server/tests/
├── common/
│   ├── mod.rs                    # 测试公共模块
│   └── exec_server.rs            # ExecServerHarness（测试工具）
├── initialize.rs                 # 初始化流程测试
├── process.rs                    # 进程执行 stub 测试
└── websocket.rs                  # WebSocket 传输测试
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| Crate | 用途 | 路径 |
|-------|------|------|
| `codex-app-server-protocol` | JSON-RPC 消息类型定义 | `codex-rs/app-server-protocol` |
| `codex-utils-pty` | PTY/进程创建（未来使用） | `codex-rs/utils/pty` |
| `codex-utils-cargo-bin` | 测试时定位二进制 | `codex-rs/utils/cargo-bin` |

### 5.2 外部依赖

| Crate | 版本 | 用途 |
|-------|------|------|
| `tokio` | 1.x | 异步运行时 |
| `tokio-tungstenite` | 0.28.0 | WebSocket 实现 |
| `serde` / `serde_json` | 1.x | 序列化 |
| `futures` | 0.3 | 流处理 |
| `clap` | 4.x | CLI 参数解析 |
| `thiserror` | 2.x | 错误定义 |
| `tracing` | 0.1 | 日志/追踪 |

### 5.3 依赖关系图

```
codex-exec-server
├── codex-app-server-protocol
│   ├── codex-protocol (W3cTraceContext)
│   ├── serde
│   ├── schemars
│   └── ts-rs
├── codex-utils-pty (未来使用)
│   ├── portable-pty
│   ├── tokio
│   └── anyhow
├── tokio (io-std, io-util, net, process, rt-multi-thread, sync, time)
├── tokio-tungstenite
│   ├── tokio
│   ├── futures
│   └── tungstenite
├── serde
├── serde_json
├── futures
├── clap
├── thiserror
└── tracing
```

### 5.4 协议依赖

`codex-app-server-protocol` 提供：

```rust
// jsonrpc_lite.rs
pub enum JSONRPCMessage { ... }
pub struct JSONRPCRequest { ... }
pub struct JSONRPCResponse { ... }
pub struct JSONRPCError { ... }
pub struct JSONRPCErrorError { ... }
pub enum RequestId { String(String), Integer(i64) }
```

---

## 6. 风险、边界与改进建议

### 6.1 当前限制

#### 6.1.1 功能限制

| 限制 | 说明 | 影响 |
|-----|------|------|
| **仅实现握手** | 所有 exec 方法返回 -32601 | 无法实际执行命令 |
| **仅 WebSocket 传输** | 不支持 stdio、unix socket | 灵活性受限 |
| **无认证** | 任何可连接客户端都可使用 | 安全风险 |
| **单节点** | 无集群/分布式支持 | 扩展性受限 |

#### 6.1.2 代码边界

```rust
// handler.rs - 当前仅实现握手
pub(crate) fn initialize(&self) -> Result<InitializeResponse, JSONRPCErrorError> {
    if self.initialize_requested.swap(true, Ordering::SeqCst) {
        return Err(invalid_request(
            "initialize may only be sent once per connection".to_string()
        ));
    }
    Ok(InitializeResponse {})  // 空响应
}

// processor.rs - 所有其他方法返回未实现
_ => response_message(
    id,
    Err(method_not_found(format!(
        "exec-server stub does not implement `{other}` yet"
    ))),
),
```

### 6.2 潜在风险

#### 6.2.1 资源泄漏风险

```rust
// processor.rs:60
handler.shutdown().await;

// 当前 shutdown 为空实现
pub(crate) async fn shutdown(&self) {}
```

**风险**：连接断开时，已启动的进程可能继续运行（僵尸进程）。

#### 6.2.2 并发竞争

```rust
// handler.rs - 使用 AtomicBool 进行状态检查
if self.initialize_requested.swap(true, Ordering::SeqCst) { ... }
```

虽然使用 `SeqCst` 顺序，但多字段状态（initialize_requested + initialized）之间无原子性保证。

#### 6.2.3 错误处理

```rust
// processor.rs:27-31
let response = match handle_connection_message(&handler, message).await {
    Ok(response) => response,
    Err(err) => {
        tracing::warn!("closing exec-server connection after protocol error: {err}");
        break;  // 直接断开，无优雅关闭
    }
};
```

### 6.3 改进建议

#### 6.3.1 功能实现优先级

| 优先级 | 功能 | 说明 |
|-------|------|------|
| P0 | `command/exec` | 基础进程执行能力 |
| P0 | `command/exec/outputDelta` | 输出流通知 |
| P0 | `command/exec/exited` | 退出状态通知 |
| P1 | `command/exec/write` | PTY 输入写入 |
| P1 | `command/exec/terminate` | 进程终止 |
| P2 | 进程管理 | 连接断开自动清理进程组 |
| P2 | 资源限制 | 内存、CPU、超时限制 |

#### 6.3.2 架构改进

1. **进程存储**：

```rust
// 建议添加
use std::collections::HashMap;
use tokio::sync::RwLock;

pub(crate) struct ExecServerHandler {
    processes: Arc<RwLock<HashMap<String, ProcessHandle>>>,
    // ...
}
```

2. **优雅关闭**：

```rust
pub(crate) async fn shutdown(&self) {
    let processes = self.processes.write().await.drain().collect::<Vec<_>>();
    for (id, handle) in processes {
        if let Err(e) = handle.terminate().await {
            tracing::warn!("failed to terminate process {}: {}", id, e);
        }
    }
}
```

3. **传输扩展**：

```rust
// 支持 stdio 传输（用于本地集成）
pub enum Transport {
    WebSocket(WebSocketStream),
    Stdio(tokio::io::Stdin, tokio::io::Stdout),
    UnixSocket(tokio::net::UnixStream),
}
```

#### 6.3.3 监控与可观测性

```rust
// 建议添加 tracing instrument
#[tracing::instrument(skip(self, params))]
pub(crate) async fn exec(&self, params: ExecParams) -> Result<ExecResponse, Error> {
    // ...
}
```

#### 6.3.4 安全增强

1. **命令白名单**：限制可执行命令范围
2. **工作目录限制**：限制可访问的文件系统路径
3. **认证机制**：Token 或 mTLS 认证

### 6.4 测试建议

当前测试覆盖：

| 测试文件 | 覆盖范围 |
|---------|---------|
| `transport_tests.rs` | URL 解析 |
| `initialize.rs` | 握手流程 |
| `process.rs` | Stub 错误响应 |
| `websocket.rs` | 畸形消息处理 |

建议添加：

1. **并发测试**：多客户端同时连接
2. **压力测试**：大量进程创建/销毁
3. **故障注入**：网络中断、超时场景
4. **集成测试**：与 `codex-utils-pty` 集成

---

## 7. 附录

### 7.1 API 参考

#### 请求方法

| 方法 | 方向 | 参数 | 响应 |
|-----|------|------|------|
| `initialize` | C→S | `{clientName: string}` | `{}` |
| `initialized` | C→S | `{}` | (notification) |
| `command/exec` | C→S | `{processId, argv, cwd, env, tty, ...}` | `{processId, running, exitCode, stdout, stderr}` |
| `command/exec/write` | C→S | `{processId, chunk: base64}` | `{accepted: bool}` |
| `command/exec/terminate` | C→S | `{processId}` | `{running: bool}` |

#### 通知（Server → Client）

| 方法 | 参数 |
|-----|------|
| `command/exec/outputDelta` | `{processId, stream: "stdout"|"stderr", chunk: base64}` |
| `command/exec/exited` | `{processId, exitCode: number}` |

### 7.2 启动示例

```bash
# 启动服务器（默认 ws://127.0.0.1:0，随机端口）
cargo run -p codex-exec-server

# 指定端口
cargo run -p codex-exec-server -- --listen ws://127.0.0.1:8080
```

### 7.3 客户端使用示例

```rust
use codex_exec_server::{
    ExecServerClient, RemoteExecServerConnectArgs
};

let client = ExecServerClient::connect_websocket(
    RemoteExecServerConnectArgs::new(
        "ws://127.0.0.1:8080".to_string(),
        "my-client".to_string(),
    )
).await?;

// 后续：使用 exec 方法（待实现）
```

### 7.4 相关文档

- `codex-rs/exec-server/README.md` - 官方 API 文档
- `codex-rs/utils/pty/README.md` - PTY 工具文档
- `codex-rs/app-server-protocol/src/jsonrpc_lite.rs` - JSON-RPC 协议定义
