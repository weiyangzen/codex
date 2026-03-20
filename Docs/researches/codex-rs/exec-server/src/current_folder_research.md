# codex-rs/exec-server/src 研究文档

> **目标路径**: `codex-rs/exec-server/src`  
> **研究日期**: 2026-03-21  
> ** crate 名称**: `codex-exec-server`  

---

## 1. 场景与职责

### 1.1 定位

`codex-exec-server` 是一个**独立的 JSON-RPC 服务器**，专门用于：
- 生成和控制子进程（通过 `codex-utils-pty`）
- 提供远程执行能力，支持 Codex CLI 与执行环境的解耦
- 作为 Codex 应用服务器的执行层扩展

### 1.2 核心职责

| 职责 | 说明 |
|------|------|
| **进程管理** | 启动、终止、写入 PTY 支持的进程 |
| **WebSocket 传输** | 提供基于 WebSocket 的 JSON-RPC 通信 |
| **协议实现** | 实现 `codex-app-server-protocol` 定义的消息格式 |
| **客户端 SDK** | 提供 Rust 客户端 `ExecServerClient` 用于连接服务器 |
| **本地/远程双模式** | 支持进程内本地后端和远程 WebSocket 后端 |

### 1.3 架构位置

```
┌─────────────────────────────────────────────────────────────┐
│                    Codex CLI / TUI                          │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│              ExecServerClient (client.rs)                   │
│         ┌─────────────────┬─────────────────┐               │
│         │   Remote Mode   │  In-Process     │               │
│         │  (WebSocket)    │   (Local)       │               │
│         └────────┬────────┴────────┬────────┘               │
└──────────────────┼─────────────────┼────────────────────────┘
                   │                 │
                   ▼                 ▼
┌─────────────────────────────────────────────────────────────┐
│         codex-exec-server (WebSocket Server)                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │  Transport  │  │  Processor  │  │   ExecServerHandler │  │
│  │ (WebSocket) │  │ (JSON-RPC)  │  │   (Request Handler) │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. 功能点目的

### 2.1 初始化握手 (Initialize Handshake)

**目的**: 建立客户端与服务器之间的会话，验证协议兼容性。

**流程**:
1. 客户端发送 `initialize` 请求（携带 `clientName`）
2. 服务器返回 `InitializeResponse`（当前为空对象 `{}`）
3. 客户端发送 `initialized` 通知确认
4. 之后可调用执行相关 RPC

**代码位置**:
- 协议定义: `protocol.rs`
- 请求处理: `server/processor.rs:dispatch_request()`
- 状态管理: `server/handler.rs:ExecServerHandler::initialize()`

### 2.2 进程执行 (Process Execution)

**目的**: 启动和管理子进程（当前为 stub 实现）。

**设计 API**（来自 README.md）:
- `command/exec`: 启动新进程
- `command/exec/write`: 向 PTY 进程写入数据
- `command/exec/terminate`: 终止进程
- `command/exec/outputDelta`: 输出流通知
- `command/exec/exited`: 进程退出通知

**当前状态**: 仅实现 `initialize`/`initialized`，其他方法返回 `-32601` (Method Not Found)。

### 2.3 双模式客户端

**目的**: 支持灵活部署（本地集成或远程服务）。

| 模式 | 适用场景 | 实现 |
|------|----------|------|
| **In-Process** | 单机集成、测试 | `LocalBackend` 直接调用 `ExecServerHandler` |
| **Remote** | 分布式、沙箱隔离 | `RpcClient` 通过 WebSocket 通信 |

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 初始化协议 (`protocol.rs`)

```rust
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

#### 3.1.2 连接选项 (`client_api.rs`)

```rust
pub struct ExecServerClientConnectOptions {
    pub client_name: String,
    pub initialize_timeout: Duration,
}

pub struct RemoteExecServerConnectArgs {
    pub websocket_url: String,
    pub client_name: String,
    pub connect_timeout: Duration,
    pub initialize_timeout: Duration,
}
```

#### 3.1.3 客户端后端枚举 (`client.rs`)

```rust
enum ClientBackend {
    Remote(RpcClient),
    InProcess(LocalBackend),
}

struct Inner {
    backend: ClientBackend,
    reader_task: tokio::task::JoinHandle<()>,
}

pub struct ExecServerClient {
    inner: Arc<Inner>,
}
```

### 3.2 关键流程

#### 3.2.1 WebSocket 服务器启动流程

```
run_main_with_listen_url(listen_url)
    └── run_transport(listen_url)
            └── parse_listen_url("ws://IP:PORT") 
                    └── run_websocket_listener(bind_address)
                            ├── TcpListener::bind(bind_address)
                            └── loop { accept_async(stream) }
                                    └── run_connection(JsonRpcConnection::from_websocket(...))
```

**文件**: `server/transport.rs`

#### 3.2.2 连接处理流程

```
run_connection(connection)
    ├── connection.into_parts() → (outgoing_tx, incoming_rx, tasks)
    ├── ExecServerHandler::new()
    └── loop { incoming_rx.recv().await }
            ├── Message → handle_connection_message()
            │                   ├── Request → dispatch_request()
            │                   │                   ├── "initialize" → handler.initialize()
            │                   │                   └── other → method_not_found()
            │                   └── Notification → handle_notification()
            │                                       └── "initialized" → handler.initialized()
            ├── MalformedMessage → invalid_request_message()
            └── Disconnected → break
```

**文件**: `server/processor.rs`

#### 3.2.3 客户端连接流程

```
ExecServerClient::connect_websocket(args)
    ├── connect_async(websocket_url) with timeout
    ├── JsonRpcConnection::from_websocket(stream, label)
    ├── RpcClient::new(connection) → (rpc_client, events_rx)
    ├── spawn reader_task for events_rx
    └── client.initialize(options)
            └── timeout(initialize_timeout)
                    └── remote.call(INITIALIZE_METHOD, params)
                            └── notify_initialized()
```

**文件**: `client.rs`

### 3.3 协议与命令

#### 3.3.1 JSON-RPC 错误码 (`server/jsonrpc.rs`)

| 错误码 | 常量 | 含义 |
|--------|------|------|
| -32600 | `invalid_request` | 无效请求 |
| -32601 | `method_not_found` | 方法未找到 |
| -32602 | `invalid_params` | 无效参数 |

#### 3.3.2 WebSocket 消息格式

- **请求**: `{"id": 1, "method": "initialize", "params": {"clientName": "test"}}`
- **响应**: `{"id": 1, "result": {}}`
- **通知**: `{"method": "initialized", "params": {}}`
- **错误**: `{"id": -1, "error": {"code": -32600, "message": "..."}}`

### 3.4 传输层实现

#### 3.4.1 JsonRpcConnection (`connection.rs`)

支持两种传输方式：

1. **WebSocket** (`from_websocket`):
   - 使用 `tokio_tungstenite::WebSocketStream`
   - 每帧一个 JSON-RPC 消息（Text 或 Binary）
   - 处理 Ping/Pong/Close 帧

2. **Stdio** (`from_stdio`, test-only):
   - 每行一个 JSON-RPC 消息
   - 用于单元测试

#### 3.4.2 RpcClient (`rpc.rs`)

- 维护待处理请求的 `HashMap<RequestId, oneshot::Sender>`
- 使用原子计数器生成递增的 `request_id`
- 支持乱序响应（通过 request_id 匹配）
- 连接断开时清理所有待处理请求

---

## 4. 关键代码路径与文件引用

### 4.1 模块结构

```
codex-rs/exec-server/src/
├── lib.rs                    # 库入口，导出公共 API
├── protocol.rs               # 初始化协议定义
├── client_api.rs             # 客户端连接选项
├── client.rs                 # ExecServerClient 实现
├── client/
│   └── local_backend.rs      # 本地进程内后端
├── connection.rs             # JsonRpcConnection 传输层
├── rpc.rs                    # RpcClient JSON-RPC 客户端
└── server.rs                 # 服务器模块入口
    ├── handler.rs            # ExecServerHandler 请求处理
    ├── jsonrpc.rs            # JSON-RPC 工具函数
    ├── processor.rs          # 连接消息处理循环
    ├── transport.rs          # WebSocket 传输监听
    └── transport_tests.rs    # 传输层单元测试

bin/
└── codex-exec-server.rs      # 独立二进制入口
```

### 4.2 关键文件详解

| 文件 | 行数 | 核心功能 |
|------|------|----------|
| `lib.rs` | 17 | 模块声明和公共导出 |
| `protocol.rs` | 15 | `InitializeParams`, `InitializeResponse` |
| `client_api.rs` | 17 | 连接配置结构体 |
| `client.rs` | 249 | `ExecServerClient`, 双模式连接 |
| `connection.rs` | 282 | `JsonRpcConnection`, WebSocket/Stdio 传输 |
| `rpc.rs` | 347 | `RpcClient`, 请求/响应匹配 |
| `server.rs` | 18 | 服务器模块聚合 |
| `server/handler.rs` | 40 | `ExecServerHandler`, 初始化状态机 |
| `server/jsonrpc.rs` | 53 | JSON-RPC 错误构造和响应包装 |
| `server/processor.rs` | 121 | `run_connection`, 消息分发 |
| `server/transport.rs` | 86 | WebSocket 监听和连接接受 |
| `server/transport_tests.rs` | 44 | URL 解析测试 |
| `client/local_backend.rs` | 38 | `LocalBackend`, 进程内调用 |
| `bin/codex-exec-server.rs` | 18 | CLI 入口，clap 参数解析 |

### 4.3 测试文件

| 文件 | 说明 |
|------|------|
| `tests/initialize.rs` | 初始化握手测试 |
| `tests/websocket.rs` | 畸形消息处理测试 |
| `tests/process.rs` | 进程启动 stub 测试 |
| `tests/common/exec_server.rs` | 测试工具：启动服务器、WebSocket 连接 |

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| Crate | 用途 |
|-------|------|
| `codex-app-server-protocol` | JSON-RPC 消息类型定义 (`JSONRPCMessage`, `JSONRPCRequest`, etc.) |
| `codex-utils-cargo-bin` | 测试时定位编译后的二进制文件 |
| `codex-utils-pty` | （未来）PTY 进程管理 |

### 5.2 外部依赖

| Crate | 版本 | 用途 |
|-------|------|------|
| `tokio` | workspace | 异步运行时、TCP 监听、任务管理 |
| `tokio-tungstenite` | workspace | WebSocket 服务器和客户端 |
| `serde` | workspace | 序列化/反序列化 |
| `serde_json` | workspace | JSON 处理 |
| `futures` | workspace | Stream/Sink trait |
| `clap` | workspace | CLI 参数解析 |
| `thiserror` | workspace | 错误类型定义 |
| `tracing` | workspace | 日志记录 |

### 5.3 协议依赖

- **传输协议**: WebSocket (`ws://`)
- **消息协议**: JSON-RPC 2.0（通过 `codex-app-server-protocol`）
- **序列化**: JSON，camelCase 命名

---

## 6. 风险、边界与改进建议

### 6.1 当前限制

| 限制 | 说明 | 影响 |
|------|------|------|
| **Stub 实现** | 仅实现 `initialize`/`initialized` | 无法实际执行命令 |
| **无认证** | WebSocket 连接无身份验证 | 安全风险（本地回绑缓解） |
| **单连接** | 每个服务器实例处理多连接，但无会话隔离 | 进程 ID 可能冲突 |
| **无 TLS** | 仅支持 `ws://`，不支持 `wss://` | 明文传输 |
| **硬编码超时** | CONNECT_TIMEOUT = 10s, INITIALIZE_TIMEOUT = 10s | 网络差时可能失败 |

### 6.2 边界情况

1. **重复初始化**: `initialize` 只能调用一次，重复调用返回 `-32600` 错误
2. **乱序通知**: 收到 `initialized` 前必须先收到 `initialize`，否则报错
3. **畸形消息**: 收到非 JSON 数据时返回错误但保持连接
4. **连接断开**: 自动清理待处理请求，通知所有等待中的调用方

### 6.3 改进建议

#### 6.3.1 短期（当前 PR 后续）

1. **实现进程管理 API**
   - 实现 `command/exec`, `command/exec/write`, `command/exec/terminate`
   - 集成 `codex-utils-pty` 进行 PTY 管理
   - 实现输出流通知 (`outputDelta`) 和退出通知 (`exited`)

2. **增强错误处理**
   - 为进程相关错误定义专门的错误码
   - 添加更详细的错误上下文

#### 6.3.2 中期

1. **安全性增强**
   - 添加连接认证（Token 或 mTLS）
   - 支持 `wss://` 加密传输
   - 添加连接白名单/黑名单

2. **可观测性**
   - 添加 metrics 端点（Prometheus 格式）
   - 结构化日志（JSON 格式）
   - 分布式 tracing 支持

3. **配置化**
   - 支持配置文件（TOML/YAML）
   - 可配置超时、缓冲区大小、日志级别

#### 6.3.3 长期

1. **多路复用优化**
   - 支持 HTTP/2 或 QUIC 传输
   - 连接池和负载均衡

2. **资源管理**
   - 进程 cgroup 限制
   - 内存和 CPU 配额
   - 自动清理僵尸进程

### 6.4 代码质量建议

1. **测试覆盖**
   - 当前测试仅覆盖初始化流程，需补充：
     - 连接断开场景
     - 并发请求处理
     - 错误恢复路径

2. **文档完善**
   - 添加架构图
   - 补充更多示例代码
   - 记录性能基准

3. **API 演进**
   - 考虑使用 gRPC 替代 JSON-RPC（性能考虑）
   - 支持流式响应（Server-Sent Events 或 gRPC streaming）

---

## 7. 参考文档

- [README.md](/home/sansha/Github/codex/codex-rs/exec-server/README.md) - 详细 API 文档
- [AGENTS.md](/home/sansha/Github/codex/AGENTS.md) - 项目级编码规范
- `codex-app-server-protocol` - 共享协议定义
