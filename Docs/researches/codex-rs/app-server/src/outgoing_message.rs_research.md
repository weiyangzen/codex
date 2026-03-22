# outgoing_message.rs 研究文档

## 场景与职责

`outgoing_message.rs` 是 Codex App Server 的核心消息路由模块，负责管理服务器到客户端的消息发送、请求-响应回调管理、连接状态跟踪和分布式追踪上下文传播。该模块实现了复杂的双向通信机制，支持广播、定向发送和线程级消息隔离。

## 功能点目的

### 1. 消息发送管理
- **广播**: 向所有连接发送消息
- **定向**: 向特定连接发送消息
- **线程隔离**: 支持线程级别的消息作用域

### 2. 请求-响应管理
- 生成唯一请求 ID
- 维护待处理请求的回调通道
- 处理客户端响应和错误
- 支持请求取消

### 3. 连接生命周期管理
- 跟踪活跃连接
- 连接断开时清理相关请求
- 请求上下文跟踪（用于追踪）

### 4. 追踪支持
- W3C Trace Context 传播
- OpenTelemetry Span 集成

## 具体技术实现

### 核心结构

#### ConnectionId
```rust
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub(crate) struct ConnectionId(pub(crate) u64);
```
- 连接的稳定标识符
- 实现 `Display` trait 便于日志记录

#### ConnectionRequestId
```rust
#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub(crate) struct ConnectionRequestId {
    pub(crate) connection_id: ConnectionId,
    pub(crate) request_id: RequestId,
}
```
- 连接内请求的唯一标识
- 组合连接 ID 和请求 ID

#### RequestContext
```rust
pub(crate) struct RequestContext {
    request_id: ConnectionRequestId,
    span: Span,
    parent_trace: Option<W3cTraceContext>,
}
```
- 维护请求的追踪上下文
- 支持 W3C Trace Context 提取

#### OutgoingMessageSender
```rust
pub(crate) struct OutgoingMessageSender {
    next_server_request_id: AtomicI64,
    sender: mpsc::Sender<OutgoingEnvelope>,
    request_id_to_callback: Mutex<HashMap<RequestId, PendingCallbackEntry>>,
    request_contexts: Mutex<HashMap<ConnectionRequestId, RequestContext>>,
}
```

#### ThreadScopedOutgoingMessageSender
```rust
pub(crate) struct ThreadScopedOutgoingMessageSender {
    outgoing: Arc<OutgoingMessageSender>,
    connection_ids: Arc<Vec<ConnectionId>>,
    thread_id: ThreadId,
}
```
- 线程级消息发送器
- 自动关联线程 ID 到请求

### 消息类型

#### OutgoingEnvelope
```rust
pub(crate) enum OutgoingEnvelope {
    ToConnection { connection_id: ConnectionId, message: OutgoingMessage },
    Broadcast { message: OutgoingMessage },
}
```

#### OutgoingMessage
```rust
#[serde(untagged)]
pub(crate) enum OutgoingMessage {
    Request(ServerRequest),
    Notification(OutgoingNotification),
    AppServerNotification(ServerNotification),
    Response(OutgoingResponse),
    Error(OutgoingError),
}
```

### 关键方法

#### 请求发送
```rust
pub(crate) async fn send_request(
    &self,
    request: ServerRequestPayload,
) -> (RequestId, oneshot::Receiver<ClientRequestResult>)
```
- 生成递增的请求 ID
- 创建回调通道
- 发送消息到指定连接或广播

#### 响应处理
```rust
pub(crate) async fn send_response<T: Serialize>(
    &self,
    request_id: ConnectionRequestId,
    response: T,
)
```
- 序列化响应
- 清理请求上下文
- 定向发送到原始连接

#### 客户端响应通知
```rust
pub(crate) async fn notify_client_response(&self, id: RequestId, result: Result)
pub(crate) async fn notify_client_error(&self, id: RequestId, error: JSONRPCErrorError)
```
- 查找并触发对应的回调
- 清理请求状态

#### 线程级请求管理
```rust
pub(crate) async fn pending_requests_for_thread(&self, thread_id: ThreadId) -> Vec<ServerRequest>
pub(crate) async fn cancel_requests_for_thread(&self, thread_id: ThreadId, error: Option<JSONRPCErrorError>)
```
- 获取线程关联的所有待处理请求
- 批量取消线程请求（用于 turn 切换时）

#### 连接管理
```rust
pub(crate) async fn connection_closed(&self, connection_id: ConnectionId)
pub(crate) async fn register_request_context(&self, request_context: RequestContext)
```
- 连接关闭时清理相关请求上下文
- 注册新请求的追踪上下文

### 线程安全设计
- 使用 `tokio::sync::Mutex` 保护共享状态
- `AtomicI64` 用于请求 ID 生成
- `Arc` 用于跨任务共享发送器

## 关键代码路径与文件引用

### 定义位置
- `codex-rs/app-server/src/outgoing_message.rs`

### 协议层类型
- `codex-rs/app-server-protocol/src/protocol/common.rs`:
  - `ServerRequest`, `ServerRequestPayload`
  - `ServerNotification`
  - `RequestId`, `Result`, `JSONRPCErrorError`

### 使用位置
| 文件 | 用途 |
|------|------|
| `lib.rs` | 创建发送器，传递给处理器 |
| `message_processor.rs` | 处理客户端请求，发送响应 |
| `codex_message_processor.rs` | 发送服务器请求到客户端 |
| `thread_status.rs` | 发送状态变更通知 |
| `fuzzy_file_search.rs` | 发送搜索结果通知 |
| `bespoke_event_handling.rs` | 发送定制事件 |
| `dynamic_tools.rs` | 发送工具调用请求 |
| `transport.rs` | 路由出站消息到连接 |
| `in_process.rs` | 进程内通信 |
| `command_exec.rs` | 命令执行管理 |

### 测试覆盖
模块包含全面的单元测试：
- 服务器通知序列化验证
- 响应路由到目标连接
- 请求上下文清理
- 错误路由
- 连接关闭清理
- 客户端错误转发
- 线程请求排序和取消

## 依赖与外部交互

### 外部依赖
```rust
use codex_app_server_protocol::{JSONRPCErrorError, RequestId, Result, ServerNotification, ServerRequest, ServerRequestPayload};
use codex_otel::span_w3c_trace_context;
use codex_protocol::ThreadId;
use codex_protocol::protocol::W3cTraceContext;
use tokio::sync::{Mutex, mpsc, oneshot};
use tracing::{Instrument, Span};
```

### 调用流程示例

#### 服务器请求客户端
1. `CodexMessageProcessor` 调用 `send_request`
2. 生成请求 ID，创建回调通道
3. 发送 `OutgoingEnvelope` 到传输层
4. 等待客户端响应或超时
5. `notify_client_response`/`notify_client_error` 触发回调

#### 响应客户端请求
1. `MessageProcessor` 处理客户端请求
2. 注册 `RequestContext` 用于追踪
3. 业务处理完成后调用 `send_response`
4. 序列化响应，定向发送
5. 清理请求上下文

## 风险、边界与改进建议

### 当前风险
1. **内存泄漏风险**: 如果客户端不响应，`request_id_to_callback` 可能无限增长
2. **回调丢失**: 通道发送失败仅记录警告，调用方可能永远等待
3. **序列化失败**: 响应序列化失败时发送错误响应，但原始请求上下文已丢失
4. **竞态条件**: `take_request_callback` 和 `notify_client_response` 之间可能存在竞态

### 边界情况
1. **重复请求 ID**: 理论上 `AtomicI64` 溢出后可能产生重复 ID（实际极不可能）
2. **连接断开**: 连接断开后，待处理请求的回调将被丢弃
3. **广播失败**: 部分连接发送失败时，继续尝试其他连接
4. **空连接列表**: `ThreadScopedOutgoingMessageSender` 连接列表为空时静默返回

### 改进建议
1. **请求超时**: 添加内置超时机制，自动清理过期请求
2. **背压处理**: 当 `mpsc` 通道满时，考虑阻塞或丢弃策略
3. **指标收集**: 记录请求延迟、队列深度、失败率等指标
4. **优雅关闭**: 支持优雅关闭，等待待处理请求完成
5. **批量通知**: 考虑批量处理通知，减少锁竞争
6. **请求去重**: 对相同请求的重复发送进行去重或合并
