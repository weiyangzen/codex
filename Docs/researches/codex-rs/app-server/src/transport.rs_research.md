# transport.rs 深度研究文档

## 文件位置
`codex-rs/app-server/src/transport.rs`

---

## 1. 场景与职责

### 1.1 核心定位
`transport.rs` 是 Codex App-Server 的**传输层核心模块**，负责处理客户端与服务器之间的所有通信通道。它抽象了两种不同的传输机制：

1. **Stdio 传输** (`stdio://`)：标准输入输出，用于本地进程间通信（如 CLI 工具链）
2. **WebSocket 传输** (`ws://IP:PORT`)：基于 TCP 的全双工通信，用于远程客户端连接

### 1.2 主要职责

| 职责 | 说明 |
|------|------|
| **连接管理** | 建立、维护和关闭客户端连接，分配唯一 ConnectionId |
| **消息路由** | 将入站消息路由到 MessageProcessor，将出站消息路由到目标连接 |
| **协议处理** | JSON-RPC 消息的序列化/反序列化 |
| **背压控制** | 通过有界通道（bounded channel）防止内存无限增长 |
| **过载保护** | 当消息队列满时返回 `OVERLOADED_ERROR_CODE` (-32001) |
| **优雅关闭** | 支持 graceful shutdown，等待运行中的任务完成 |
| **安全防护** | WebSocket 模式下拒绝带 Origin 头的请求（CSRF 防护） |

### 1.3 使用场景

- **VSCode 扩展**：通过 WebSocket 连接本地或远程 App-Server
- **CLI 工具**：通过 stdio 与 App-Server 通信
- **TUI 界面**：通过 in-process 或 WebSocket 方式嵌入
- **自动化测试**：WebSocket 传输支持多连接并发测试

---

## 2. 功能点目的

### 2.1 传输类型枚举 (`AppServerTransport`)

```rust
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AppServerTransport {
    Stdio,
    WebSocket { bind_address: SocketAddr },
}
```

**设计意图**：
- 统一两种截然不同的传输机制，使上层代码无需关心底层实现
- 支持从 URL 字符串解析（`stdio://` 或 `ws://IP:PORT`）
- 默认使用 stdio，符合 MCP (Model Context Protocol) 规范

### 2.2 传输事件枚举 (`TransportEvent`)

```rust
pub(crate) enum TransportEvent {
    ConnectionOpened { ... },
    ConnectionClosed { connection_id: ConnectionId },
    IncomingMessage { connection_id: ConnectionId, message: JSONRPCMessage },
}
```

**设计意图**：
- 解耦传输层与处理层，通过 channel 进行异步通信
- 支持多连接并发，每个连接有独立的 writer channel
- 统一事件模型，无论是 stdio 还是 WebSocket 都产生相同事件

### 2.3 连接状态管理

#### `ConnectionState`（入站连接状态）
- 跟踪连接的初始化状态 (`initialized`)
- 实验性 API 启用标志 (`experimental_api_enabled`)
- 用户选择退出的通知方法 (`opted_out_notification_methods`)
- 会话状态 (`session: ConnectionSessionState`)

#### `OutboundConnectionState`（出站连接状态）
- 包含 writer channel 用于发送消息
- 支持断开连接的信号机制 (`disconnect_sender: Option<CancellationToken>`)
- 区分内部进程客户端和外部客户端（`allow_legacy_notifications`）

### 2.4 消息队列与背压

**常量定义**：
```rust
pub(crate) const CHANNEL_CAPACITY: usize = 128;
```

**背压策略**：
1. **入站消息**：使用 `try_send`，队列满时对请求返回过载错误，对响应/通知则等待
2. **出站消息**：WebSocket 连接队列满时断开慢连接；stdio 连接则阻塞等待

### 2.5 实验性 API 过滤

```rust
fn filter_outgoing_message_for_connection(...)
```

**功能**：在消息发送前根据连接能力过滤实验性字段，例如：
- `CommandExecutionRequestApprovalParams` 中的 `additional_permissions`
- `skill_metadata` 等实验性功能字段

**目的**：确保未启用实验性 API 的客户端不会收到不理解的字段，保持向后兼容。

---

## 3. 具体技术实现

### 3.1 关键数据结构

```rust
// 连接标识符（包装 u64）
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub(crate) struct ConnectionId(pub(crate) u64);

// 连接级请求标识符
#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub(crate) struct ConnectionRequestId {
    pub(crate) connection_id: ConnectionId,
    pub(crate) request_id: RequestId,
}

// 出站消息信封（支持单发和广播）
pub(crate) enum OutgoingEnvelope {
    ToConnection { connection_id: ConnectionId, message: OutgoingMessage },
    Broadcast { message: OutgoingMessage },
}

// 出站消息类型
pub(crate) enum OutgoingMessage {
    Request(ServerRequest),
    Notification(OutgoingNotification),
    AppServerNotification(ServerNotification),
    Response(OutgoingResponse),
    Error(OutgoingError),
}
```

### 3.2 关键流程

#### 3.2.1 WebSocket 连接建立流程

```
1. start_websocket_acceptor(bind_address)
   ├── 绑定 TCP listener
   ├── 打印启动 banner（显示 ws:// 地址、readyz/healthz 端点）
   ├── 创建 axum Router
   │   ├── /readyz → health_check_handler (200 OK)
   │   ├── /healthz → health_check_handler (200 OK)
   │   └── fallback → websocket_upgrade_handler
   └── 启动 axum server

2. websocket_upgrade_handler
   ├── 生成 connection_id（原子自增）
   ├── 发送 ConnectionOpened 事件到 transport_event_tx
   └── on_upgrade → run_websocket_connection

3. run_websocket_connection
   ├── 分割 WebSocket stream（reader/writer）
   ├── 启动 outbound_task（run_websocket_outbound_loop）
   ├── 启动 inbound_task（run_websocket_inbound_loop）
   └── tokio::select! 等待任一任务结束，然后清理
```

#### 3.2.2 消息入站流程

```
run_websocket_inbound_loop / start_stdio_connection
├── 读取消息（WebSocket frame 或 stdin line）
├── forward_incoming_message
│   ├── 解析 JSON → JSONRPCMessage
│   └── 调用 enqueue_incoming_message
└── enqueue_incoming_message
    ├── try_send 到 transport_event_tx
    ├── 如果队列满且是 Request：返回 OVERLOADED_ERROR_CODE
    ├── 如果队列满且是 Response/Notification：await send（阻塞等待）
    └── 如果 channel 关闭：返回 false，触发连接关闭
```

#### 3.2.3 消息出站流程

```
route_outgoing_envelope
├── OutgoingEnvelope::ToConnection
│   └── send_message_to_connection
│       ├── 获取连接状态
│       ├── filter_outgoing_message_for_connection（过滤实验性字段）
│       ├── should_skip_notification_for_connection（检查通知过滤）
│       └── 发送消息
│           ├── WebSocket：try_send，满则断开连接
│           └── Stdio：await send（阻塞）
└── OutgoingEnvelope::Broadcast
    ├── 筛选已初始化且不跳过通知的连接
    └── 逐个调用 send_message_to_connection
```

### 3.3 协议细节

#### JSON-RPC 消息格式

基于 `codex-app-server-protocol` crate，支持四种消息类型：

```rust
pub enum JSONRPCMessage {
    Request(JSONRPCRequest),      // { id, method, params?, trace? }
    Notification(JSONRPCNotification), // { method, params? }
    Response(JSONRPCResponse),    // { id, result }
    Error(JSONRPCError),          // { id, error: { code, message, data? } }
}
```

**注意**：协议不发送/期望 `"jsonrpc": "2.0"` 字段（见 `jsonrpc_lite.rs` 注释）。

#### WebSocket 帧处理

| 帧类型 | 处理 |
|--------|------|
| Text | 解析为 JSON-RPC 消息 |
| Ping | 回复 Pong（通过 control channel） |
| Pong | 忽略 |
| Close | 断开连接 |
| Binary | 丢弃并警告 |

### 3.4 并发模型

```
┌─────────────────────────────────────────────────────────────┐
│                        App-Server                            │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────┐  │
│  │ WebSocket   │    │   Stdio     │    │   In-Process    │  │
│  │ Acceptor    │    │  Reader     │    │   (optional)    │  │
│  └──────┬──────┘    └──────┬──────┘    └─────────────────┘  │
│         │                  │                                 │
│         └──────────────────┬─────────────────┐                │
│                            ▼                 │                │
│              ┌─────────────────────┐         │                │
│              │  transport_event_tx │         │                │
│              └──────────┬──────────┘         │                │
│                         ▼                    │                │
│              ┌─────────────────────┐         │                │
│              │   MessageProcessor  │         │                │
│              │   (request handling)│         │                │
│              └──────────┬──────────┘         │                │
│                         │                    │                │
│              ┌──────────▼──────────┐         │                │
│              │   outgoing_tx       │         │                │
│              └──────────┬──────────┘         │                │
│                         ▼                    │                │
│              ┌─────────────────────┐         │                │
│              │   Outbound Router   │◄────────┘                │
│              │   (per-connection   │                          │
│              │    writers)         │                          │
│              └─────────────────────┘                          │
└─────────────────────────────────────────────────────────────┘
```

---

## 4. 关键代码路径与文件引用

### 4.1 内部依赖

| 文件 | 依赖关系 | 说明 |
|------|----------|------|
| `lib.rs` | 调用 transport | 主入口，协调 transport、processor、outbound router |
| `message_processor.rs` | 被 transport 调用 | 处理 JSON-RPC 请求，生成响应 |
| `outgoing_message.rs` | 被 transport 使用 | 定义出站消息类型和发送器 |
| `error_code.rs` | 被 transport 使用 | 定义错误码常量 |
| `app_server_tracing.rs` | 与 transport 协作 | 为请求创建 tracing span |
| `in_process.rs` | 复用 transport 逻辑 | 进程内运行时，复用 OutboundConnectionState 和 route_outgoing_envelope |

### 4.2 外部依赖

| Crate | 用途 |
|-------|------|
| `axum` | WebSocket HTTP 服务器框架 |
| `tokio` | 异步运行时、TCP listener、channel |
| `futures` | Stream/Sink trait 用于 WebSocket |
| `serde_json` | JSON 序列化/反序列化 |
| `codex-app-server-protocol` | JSON-RPC 消息类型定义 |
| `owo_colors` | 终端彩色输出（启动 banner） |

### 4.3 关键代码路径

#### 启动 WebSocket 服务器
```
main.rs → run_main_with_transport → start_websocket_acceptor
```

#### 处理入站消息
```
run_websocket_inbound_loop → forward_incoming_message → enqueue_incoming_message
→ transport_event_tx → lib.rs (processor loop) → MessageProcessor::process_request
```

#### 发送出站消息
```
MessageProcessor → OutgoingMessageSender → outgoing_tx → route_outgoing_envelope
→ send_message_to_connection → writer_tx → run_websocket_outbound_loop
```

---

## 5. 依赖与外部交互

### 5.1 与 lib.rs 的交互

`lib.rs` 中的主循环处理 `TransportEvent`：

```rust
// lib.rs: processor_handle 异步块
loop {
    tokio::select! {
        event = transport_event_rx.recv() => {
            match event {
                TransportEvent::ConnectionOpened { ... } => {
                    // 创建 ConnectionState
                    // 发送 OutboundControlEvent::Opened
                }
                TransportEvent::ConnectionClosed { connection_id } => {
                    // 清理连接状态
                    // 发送 OutboundControlEvent::Closed
                }
                TransportEvent::IncomingMessage { connection_id, message } => {
                    // 路由到 MessageProcessor
                }
            }
        }
    }
}
```

### 5.2 与 MessageProcessor 的交互

`MessageProcessor` 通过 `OutgoingMessageSender` 发送响应：

```rust
// message_processor.rs
self.outgoing.send_response(request_id, response).await;
self.outgoing.send_error(request_id, error).await;
self.outgoing.send_server_notification(notification).await;
```

### 5.3 与 in_process.rs 的交互

`in_process.rs` 复用 transport 层的出站路由逻辑：

```rust
// in_process.rs
use crate::transport::OutboundConnectionState;
use crate::transport::route_outgoing_envelope;

// 创建单连接状态
outbound_connections.insert(
    IN_PROCESS_CONNECTION_ID,
    OutboundConnectionState::new(...),
);

// 复用广播/单发逻辑
route_outgoing_envelope(&mut outbound_connections, envelope).await;
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 严重程度 | 说明 |
|------|----------|------|
| **消息丢失** | 中 | 当 outbound queue 满时，WebSocket 连接会被断开，可能导致消息丢失 |
| **背压不均** | 中 | 广播时一个慢连接会阻塞整个广播（顺序发送） |
| **Origin 检查绕过** | 低 | 当前仅检查 HTTP Origin 头，不检查 WebSocket 子协议 |
| **内存泄漏** | 低 | 连接断开后 request_contexts 可能未完全清理（已处理） |
| **实验性 API 竞争** | 中 | 多连接共享线程时，实验性 API 标志可能不一致 |

### 6.2 边界情况

1. **零容量通道**：`in_process.rs` 中 `channel_capacity` 被 clamp 到至少 1
2. **重复请求 ID**：`in_process.rs` 会检查并返回 `INVALID_REQUEST_ERROR_CODE`
3. **快速重连**：连接计数器使用 `AtomicU64`，理论上不会溢出
4. **SIGTERM 处理**：WebSocket 模式支持 graceful shutdown，stdio 模式不支持

### 6.3 改进建议

#### 6.3.1 性能优化

1. **并行广播**：当前广播是顺序的，可以考虑使用 `tokio::spawn` 并行发送
   ```rust
   // 当前实现
   for connection_id in target_connections {
       send_message_to_connection(...).await;
   }
   
   // 建议改进
   let futures: Vec<_> = target_connections
       .into_iter()
       .map(|id| send_message_to_connection(...))
       .collect();
   futures::future::join_all(futures).await;
   ```

2. **零拷贝序列化**：当前消息被序列化两次（`to_value` 然后 `to_string`），可以考虑使用 `serde_json::to_writer`

#### 6.3.2 可观测性

1. **Metrics**：添加 Prometheus 指标：
   - 连接数（gauge）
   - 消息吞吐量（counter）
   - 队列深度（histogram）
   - 断开原因（counter with labels）

2. **Tracing**：在关键路径添加 span：
   - 消息序列化/反序列化
   - 队列等待时间
   - 网络 I/O 延迟

#### 6.3.3 安全加固

1. **TLS 支持**：当前 WebSocket 是明文传输，建议添加 `wss://` 支持
2. **认证**：在 WebSocket 握手时验证 token
3. **速率限制**：基于 connection_id 的请求速率限制

#### 6.3.4 代码重构

1. **拆分模块**：文件已接近 1400 行，建议拆分为：
   - `transport/mod.rs`
   - `transport/stdio.rs`
   - `transport/websocket.rs`
   - `transport/state.rs`

2. **抽象 trait**：定义 `Transport` trait，便于测试和扩展
   ```rust
   #[async_trait]
   trait Transport {
       async fn accept(&self) -> Result<Box<dyn Connection>>;
   }
   ```

### 6.4 测试覆盖

当前测试覆盖良好，包括：
- URL 解析测试
- 过载错误测试
- 通知过滤测试
- 实验性字段过滤测试
- 广播行为测试

**建议添加**：
- 大规模并发连接测试
- 网络分区/延迟测试
- 内存使用测试

---

## 7. 总结

`transport.rs` 是 Codex App-Server 的核心基础设施，设计简洁且功能完整。它成功抽象了 stdio 和 WebSocket 两种传输机制，通过 channel 实现了高效的异步消息路由。背压控制、过载保护和优雅关闭等生产级特性均已实现。

主要优点：
- 清晰的职责分离（传输 vs 处理）
- 良好的背压和过载保护
- 完善的测试覆盖
- 与 in-process 模式的良好复用

主要改进空间：
- 并行广播优化
- TLS 和认证支持
- 更细粒度的可观测性
- 模块拆分以提高可维护性
