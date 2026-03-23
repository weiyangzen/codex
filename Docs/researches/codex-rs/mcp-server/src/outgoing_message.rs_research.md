# outgoing_message.rs 研究文档

## 场景与职责

`outgoing_message.rs` 负责管理 Codex MCP 服务器的所有出站消息，包括响应、通知和请求。它提供了一个统一的接口，将内部消息类型转换为符合 MCP 协议的 JSON-RPC 格式。

**核心职责：**
1. 管理出站消息队列（通过 Tokio 通道）
2. 生成唯一的请求 ID
3. 处理请求-响应回调映射
4. 将内部事件转换为 MCP 通知格式
5. 序列化消息为 JSON-RPC 格式

## 功能点目的

### 1. OutgoingMessageSender 结构

```rust
pub(crate) struct OutgoingMessageSender {
    next_request_id: AtomicI64,
    sender: mpsc::UnboundedSender<OutgoingMessage>,
    request_id_to_callback: Mutex<HashMap<RequestId, oneshot::Sender<Value>>>,
}
```

**字段说明：**
- `next_request_id`：原子计数器，生成递增的请求 ID
- `sender`：无界通道发送器，将消息发送到 stdout 写入任务
- `request_id_to_callback`：请求 ID 到 oneshot 回调的映射，用于等待响应

### 2. 消息类型枚举

```rust
pub(crate) enum OutgoingMessage {
    Request(OutgoingRequest),
    Notification(OutgoingNotification),
    Response(OutgoingResponse),
    Error(OutgoingError),
}
```

**转换到 JSON-RPC：**
```rust
impl From<OutgoingMessage> for OutgoingJsonRpcMessage {
    fn from(val: OutgoingMessage) -> Self {
        match val {
            Request(OutgoingRequest { id, method, params }) => {
                JsonRpcMessage::Request(JsonRpcRequest { ... })
            }
            Notification(OutgoingNotification { method, params }) => {
                JsonRpcMessage::Notification(JsonRpcNotification { ... })
            }
            Response(OutgoingResponse { id, result }) => {
                JsonRpcMessage::Response(JsonRpcResponse { ... })
            }
            Error(OutgoingError { id, error }) => {
                JsonRpcMessage::Error(JsonRpcError { ... })
            }
        }
    }
}
```

### 3. 核心方法

**发送请求（Elicitation）：**
```rust
pub(crate) async fn send_request(
    &self,
    method: &str,
    params: Option<serde_json::Value>,
) -> oneshot::Receiver<Value>
```

返回 oneshot receiver，调用者可等待响应。

**发送响应：**
```rust
pub(crate) async fn send_response<T: Serialize>(&self, id: RequestId, response: T)
```

**发送错误：**
```rust
pub(crate) async fn send_error(&self, id: RequestId, error: ErrorData)
```

**发送事件通知：**
```rust
pub(crate) async fn send_event_as_notification(
    &self,
    event: &Event,
    meta: Option<OutgoingNotificationMeta>,
)
```

### 4. 通知元数据

```rust
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct OutgoingNotificationMeta {
    pub request_id: Option<RequestId>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub thread_id: Option<ThreadId>,
}
```

用于在通知中携带额外的 MCP 特定元数据，遵循 MCP 协议的 `_meta` 字段约定。

## 具体技术实现

### 请求发送流程

```rust
pub(crate) async fn send_request(
    &self,
    method: &str,
    params: Option<serde_json::Value>,
) -> oneshot::Receiver<Value> {
    // 1. 生成请求 ID
    let id = RequestId::Number(self.next_request_id.fetch_add(1, Ordering::Relaxed));
    let outgoing_message_id = id.clone();
    
    // 2. 创建 oneshot 通道
    let (tx_approve, rx_approve) = oneshot::channel();
    
    // 3. 注册回调
    {
        let mut request_id_to_callback = self.request_id_to_callback.lock().await;
        request_id_to_callback.insert(id, tx_approve);
    }
    
    // 4. 构建并发送消息
    let outgoing_message = OutgoingMessage::Request(OutgoingRequest {
        id: outgoing_message_id,
        method: method.to_string(),
        params,
    });
    let _ = self.sender.send(outgoing_message);
    
    // 5. 返回 receiver
    rx_approve
}
```

### 响应通知处理

```rust
pub(crate) async fn notify_client_response(&self, id: RequestId, result: Value) {
    // 1. 查找并移除回调
    let entry = {
        let mut request_id_to_callback = self.request_id_to_callback.lock().await;
        request_id_to_callback.remove_entry(&id)
    };
    
    // 2. 发送结果
    match entry {
        Some((id, sender)) => {
            if let Err(err) = sender.send(result) {
                warn!("could not notify callback for {id:?} due to: {err:?}");
            }
        }
        None => {
            warn!("could not find callback for {id:?}");
        }
    }
}
```

### 事件通知发送

```rust
pub(crate) async fn send_event_as_notification(
    &self,
    event: &Event,
    meta: Option<OutgoingNotificationMeta>,
) {
    // 1. 序列化事件
    let event_json = serde_json::to_value(event).expect("Event must serialize");
    
    // 2. 包装为通知参数
    let params = if let Ok(params) = serde_json::to_value(OutgoingNotificationParams {
        meta,
        event: event_json.clone(),
    }) {
        params
    } else {
        warn!("Failed to serialize event as OutgoingNotificationParams");
        event_json
    };
    
    // 3. 发送通知
    self.send_notification(OutgoingNotification {
        method: "codex/event".to_string(),
        params: Some(params.clone()),
    }).await;
}
```

### 序列化格式

**通知参数结构：**
```rust
#[derive(Debug, Clone, PartialEq, Serialize)]
pub(crate) struct OutgoingNotificationParams {
    #[serde(rename = "_meta", default, skip_serializing_if = "Option::is_none")]
    pub meta: Option<OutgoingNotificationMeta>,
    
    #[serde(flatten)]
    pub event: serde_json::Value,
}
```

生成的 JSON：
```json
{
    "_meta": {
        "requestId": "123",
        "threadId": "..."
    },
    "id": "event-1",
    "msg": {
        "type": "session_configured",
        ...
    }
}
```

## 关键代码路径与文件引用

### 内部依赖

| 依赖 | 路径 | 用途 |
|------|------|------|
| `Event` | `codex_protocol::protocol` | Codex 事件类型 |
| `ThreadId` | `codex_protocol` | 线程标识 |

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `rmcp::model::*` | MCP 协议类型 |
| `tokio::sync::{Mutex, mpsc, oneshot}` | 异步同步原语 |
| `serde::Serialize` | 序列化 |
| `tracing::warn` | 警告日志 |

### 调用关系

```
MessageProcessor / CodexToolRunner
    └─> OutgoingMessageSender::send_request()
        ├─> 生成 ID
        ├─> 注册 oneshot 回调
        └─> 发送到 stdout 任务
    
    └─> OutgoingMessageSender::send_response()
        └─> 序列化并发送
    
    └─> OutgoingMessageSender::send_event_as_notification()
        ├─> 序列化 Event
        ├─> 包装为 OutgoingNotificationParams
        └─> 发送 codex/event 通知

lib.rs::stdout_writer task
    └─> 接收 OutgoingMessage
        └─> Into<OutgoingJsonRpcMessage>
            └─> serde_json::to_string()
                └─> stdout.write_all()

lib.rs::processor task (处理客户端响应)
    └─> MessageProcessor::process_response()
        └─> OutgoingMessageSender::notify_client_response()
            └─> oneshot::Sender::send()
                └─> 唤醒等待的 elicitation 处理
```

## 依赖与外部交互

### MCP 协议消息格式

**请求（Elicitation）：**
```json
{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "elicitation/create",
    "params": { ... }
}
```

**响应：**
```json
{
    "jsonrpc": "2.0",
    "id": 1,
    "result": { ... }
}
```

**通知（Event）：**
```json
{
    "jsonrpc": "2.0",
    "method": "codex/event",
    "params": {
        "_meta": {
            "requestId": "...",
            "threadId": "..."
        },
        "id": "event-id",
        "msg": { ... }
    }
}
```

### 回调机制

用于 Elicitation 请求-响应模式：

```rust
// 发送请求，获取 receiver
let on_response = outgoing.send_request("elicitation/create", Some(params_json)).await;

// 在独立任务中等待响应
tokio::spawn(async move {
    let response = on_response.await;  // 等待客户端响应
    // 处理响应...
});
```

### 线程安全

- `next_request_id`：`AtomicI64`，线程安全
- `request_id_to_callback`：`Mutex<HashMap<...>>`，异步安全
- `sender`：`mpsc::UnboundedSender`，克隆后可在多任务使用

## 风险、边界与改进建议

### 已知风险

1. **无界通道**：使用 `mpsc::unbounded_channel`，极端情况下可能耗尽内存
   ```rust
   let (outgoing_tx, mut outgoing_rx) = mpsc::unbounded_channel::<OutgoingMessage>();
   ```

2. **回调泄漏**：如果客户端不响应 elicitation 请求，回调映射中的条目永远不会被清理

3. **序列化 panic**：`send_event_as_notification` 使用 `expect` 假设事件总是可序列化
   ```rust
   let event_json = serde_json::to_value(event).expect("Event must serialize");
   ```

4. **ID 溢出**：`AtomicI64` 在极端长时间运行后可能溢出（但实际不太可能发生）

### 边界情况

| 场景 | 行为 |
|------|------|
| 发送失败 | 静默忽略（`let _ = self.sender.send(...)`） |
| 回调未找到 | 记录警告日志 |
| 回调发送失败 | 记录警告日志 |
| 序列化失败（响应） | 发送内部错误响应 |
| 通知参数序列化失败 | 回退到原始事件 JSON |

### 改进建议

1. **有界通道**：考虑使用有界通道，应用背压
   ```rust
   let (tx, rx) = mpsc::channel::<OutgoingMessage>(1024);
   ```

2. **回调超时**：添加 elicitation 超时，清理过期回调
   ```rust
   tokio::time::timeout(Duration::from_secs(300), on_response).await
   ```

3. **回调清理**：定期清理长时间未响应的回调条目

4. **错误传播**：将发送失败返回给调用者，而不是静默忽略
   ```rust
   self.sender.send(outgoing_message).map_err(|_| SendError)?;
   ```

5. **ID 生成器**：考虑使用 UUID 或更复杂的 ID 生成策略

6. **批处理**：对于高频事件，考虑批处理通知以减少 I/O

### 测试覆盖

包含四个单元测试：

1. **`outgoing_request_serializes_as_jsonrpc_request`**
   - 验证请求序列化为正确的 JSON-RPC 格式
   - 检查 `jsonrpc`, `id`, `method`, `params` 字段

2. **`outgoing_notification_serializes_as_jsonrpc_notification`**
   - 验证通知序列化为正确的 JSON-RPC 格式
   - 检查 `jsonrpc`, `method`, `params` 字段

3. **`test_send_event_as_notification`**
   - 验证事件作为通知发送
   - 检查 `codex/event` 方法名

4. **`test_send_event_as_notification_with_meta`** / **`test_send_event_as_notification_with_meta_and_thread_id`**
   - 验证元数据正确包含在 `_meta` 字段中
   - 检查 `requestId` 和 `threadId` 序列化

测试使用 `tokio::sync::mpsc::unbounded_channel` 模拟消息通道。
