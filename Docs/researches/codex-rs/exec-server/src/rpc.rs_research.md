# rpc.rs 深入研究文档

## 场景与职责

`rpc.rs` 是 `codex-exec-server` crate 的 JSON-RPC 客户端实现模块，负责在客户端侧管理 JSON-RPC 请求-响应生命周期。它实现了异步 RPC 调用的核心机制：请求 ID 生成、pending 请求跟踪、响应匹配和通知处理。

## 功能点目的

### 1. 请求-响应匹配
- **目的**：支持异步并发请求，正确处理乱序到达的响应
- **实现**：使用 `HashMap<RequestId, oneshot::Sender>` 跟踪 pending 请求

### 2. 通知处理
- **目的**：接收服务器主动推送的通知消息
- **实现**：通过 `mpsc::Receiver<RpcClientEvent>` 暴露通知流

### 3. 连接生命周期管理
- **目的**：在连接断开时优雅清理资源
- **实现**：Drop 实现中止所有任务，drain_pending 通知所有等待者

### 4. 类型安全的 RPC 调用
- **目的**：提供编译期类型检查的 RPC 调用接口
- **实现**：泛型方法 `call<P, T>` 自动处理序列化/反序列化

## 具体技术实现

### 核心数据结构

```rust
// RPC 客户端主结构
pub(crate) struct RpcClient {
    write_tx: mpsc::Sender<JSONRPCMessage>,           // 发送请求/通知
    pending: Arc<Mutex<HashMap<RequestId, PendingRequest>>>, // 等待中的请求
    next_request_id: AtomicI64,                        // 自增请求 ID
    transport_tasks: Vec<JoinHandle<()>>,             // 传输层任务
    reader_task: JoinHandle<()>,                      // 消息读取任务
}

// Pending 请求类型：用于将响应传回调用者
type PendingRequest = oneshot::Sender<Result<Value, JSONRPCErrorError>>;

// 客户端事件（通知或断开）
#[derive(Debug)]
pub(crate) enum RpcClientEvent {
    Notification(JSONRPCNotification),
    Disconnected { reason: Option<String> },
}
```

### 请求 ID 生成

```rust
let request_id = RequestId::Integer(self.next_request_id.fetch_add(1, Ordering::SeqCst));
```

使用 `AtomicI64` + `SeqCst` 保证：
- 线程安全的 ID 分配
- 严格递增的顺序（便于调试和日志追踪）

### 异步调用流程

```rust
pub(crate) async fn call<P, T>(&self, method: &str, params: &P) -> Result<T, RpcCallError>
where
    P: Serialize,
    T: DeserializeOwned,
{
    // 1. 生成请求 ID
    let request_id = RequestId::Integer(self.next_request_id.fetch_add(1, Ordering::SeqCst));
    
    // 2. 创建 oneshot 通道接收响应
    let (response_tx, response_rx) = oneshot::channel();
    
    // 3. 注册到 pending map
    self.pending.lock().await.insert(request_id.clone(), response_tx);
    
    // 4. 序列化参数
    let params = match serde_json::to_value(params) {
        Ok(params) => params,
        Err(err) => {
            self.pending.lock().await.remove(&request_id);
            return Err(RpcCallError::Json(err));
        }
    };
    
    // 5. 发送请求
    if self.write_tx.send(JSONRPCMessage::Request(...)).await.is_err() {
        self.pending.lock().await.remove(&request_id);
        return Err(RpcCallError::Closed);
    }
    
    // 6. 等待响应
    let result = response_rx.await.map_err(|_| RpcCallError::Closed)?;
    let response = match result {
        Ok(response) => response,
        Err(error) => return Err(RpcCallError::Server(error)),
    };
    
    // 7. 反序列化响应
    serde_json::from_value(response).map_err(RpcCallError::Json)
}
```

### 通知发送

```rust
pub(crate) async fn notify<P: Serialize>(
    &self,
    method: &str,
    params: &P,
) -> Result<(), serde_json::Error> {
    let params = serde_json::to_value(params)?;
    self.write_tx
        .send(JSONRPCMessage::Notification(JSONRPCNotification {
            method: method.to_string(),
            params: Some(params),
        }))
        .await
        .map_err(|_| {
            serde_json::Error::io(std::io::Error::new(
                std::io::ErrorKind::BrokenPipe,
                "JSON-RPC transport closed",
            ))
        })
}
```

### 消息处理循环

```rust
let reader_task = tokio::spawn(async move {
    while let Some(event) = incoming_rx.recv().await {
        match event {
            JsonRpcConnectionEvent::Message(message) => {
                if let Err(err) = handle_server_message(&pending_for_reader, &event_tx, message).await {
                    warn!("JSON-RPC client closing after protocol error: {err}");
                    break;
                }
            }
            JsonRpcConnectionEvent::MalformedMessage { reason } => {
                warn!("JSON-RPC client closing after malformed server message: {reason}");
                // 发送断开事件，清理 pending
                let _ = event_tx.send(RpcClientEvent::Disconnected { reason: Some(reason) }).await;
                drain_pending(&pending_for_reader).await;
                return;
            }
            JsonRpcConnectionEvent::Disconnected { reason } => {
                let _ = event_tx.send(RpcClientEvent::Disconnected { reason }).await;
                drain_pending(&pending_for_reader).await;
                return;
            }
        }
    }
    // 通道关闭，发送断开事件
    let _ = event_tx.send(RpcClientEvent::Disconnected { reason: None }).await;
    drain_pending(&pending_for_reader).await;
});
```

### 服务器消息处理

```rust
async fn handle_server_message(
    pending: &Mutex<HashMap<RequestId, PendingRequest>>,
    event_tx: &mpsc::Sender<RpcClientEvent>,
    message: JSONRPCMessage,
) -> Result<(), String> {
    match message {
        JSONRPCMessage::Response(JSONRPCResponse { id, result }) => {
            // 找到对应的 pending 请求，发送响应
            if let Some(pending) = pending.lock().await.remove(&id) {
                let _ = pending.send(Ok(result));
            }
        }
        JSONRPCMessage::Error(JSONRPCError { id, error }) => {
            // 找到对应的 pending 请求，发送错误
            if let Some(pending) = pending.lock().await.remove(&id) {
                let _ = pending.send(Err(error));
            }
        }
        JSONRPCMessage::Notification(notification) => {
            // 通过事件通道转发通知
            let _ = event_tx.send(RpcClientEvent::Notification(notification)).await;
        }
        JSONRPCMessage::Request(request) => {
            // 服务器不应发送请求，视为协议错误
            return Err(format!("unexpected JSON-RPC request from remote server: {}", request.method));
        }
    }
    Ok(())
}
```

### Pending 请求清理

```rust
async fn drain_pending(pending: &Mutex<HashMap<RequestId, PendingRequest>>) {
    // 一次性取出所有 pending 请求
    let pending = {
        let mut pending = pending.lock().await;
        pending.drain().map(|(_, pending)| pending).collect::<Vec<_>>()
    };
    
    // 向所有等待者发送断开错误
    for pending in pending {
        let _ = pending.send(Err(JSONRPCErrorError {
            code: -32000,
            data: None,
            message: "JSON-RPC transport closed".to_string(),
        }));
    }
}
```

### 错误类型

```rust
#[derive(Debug)]
pub(crate) enum RpcCallError {
    Closed,                     // 连接已关闭
    Json(serde_json::Error),    // 序列化/反序列化错误
    Server(JSONRPCErrorError),  // 服务器返回的错误
}
```

## 关键代码路径与文件引用

### 内部依赖

| 模块 | 路径 | 用途 |
|------|------|------|
| `connection` | `connection.rs` | `JsonRpcConnection`, `JsonRpcConnectionEvent` |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `codex_app_server_protocol` | JSON-RPC 消息类型定义 |
| `tokio::sync` | `mpsc`, `oneshot`, `Mutex` |
| `serde` | 序列化/反序列化 |
| `serde_json` | JSON 处理 |
| `std::sync::atomic` | 原子 ID 生成 |

### 使用位置

| 文件 | 使用方式 |
|------|----------|
| `client.rs` | `RpcClient::new`, `RpcClient::call`, `RpcClient::notify`, `RpcClientEvent` |

### 关键代码路径

1. **创建客户端**：
   ```
   RpcClient::new(connection) -> (Self, mpsc::Receiver<RpcClientEvent>)
   ```

2. **发送请求**：
   ```
   RpcClient::call(method, params) -> generate ID -> register pending -> send -> wait oneshot
   ```

3. **接收响应**：
   ```
   reader_task -> handle_server_message -> find pending by ID -> send via oneshot
   ```

4. **连接断开**：
   ```
   Disconnected event -> drain_pending -> notify all with error
   ```

## 依赖与外部交互

### 与 connection 的交互
- 消费 `JsonRpcConnection` 并调用 `into_parts()`
- 使用 `incoming_rx` 接收消息事件
- 使用 `write_tx` 发送消息

### 与 client 的交互
- `ExecServerClient` 包装 `RpcClient`（远程模式）
- 将 `RpcCallError` 转换为 `ExecServerError`
- 处理 `RpcClientEvent`（当前仅记录警告）

### 与 app-server-protocol 的交互
- 使用 `JSONRPCMessage`, `JSONRPCRequest`, `JSONRPCResponse`, `JSONRPCError`
- 使用 `JSONRPCNotification`, `JSONRPCErrorError`, `RequestId`

## 风险、边界与改进建议

### 当前风险

1. **内存增长风险**：
   - 如果服务器不响应某些请求，pending map 会无限增长
   - 建议添加请求超时机制

2. **响应 ID 不匹配**：
   - 如果服务器返回未知 ID 的响应，静默丢弃
   - 建议记录警告或错误

3. **通知丢失**：
   - 如果 `event_tx` 通道满，通知被丢弃（`let _ = ...`）
   - 建议添加背压或缓冲策略

4. **锁竞争**：
   - 每个请求/响应都需要获取 `pending` 锁
   - 高并发场景可能成为瓶颈

### 边界情况

1. **重复响应**：
   - 如果服务器发送重复响应，第二次找不到 pending 项，静默忽略

2. **快速断开**：
   - 请求发送后、注册到 pending 前断开，调用者收到 `Closed` 错误
   - 请求注册后、发送前断开，从 pending 移除并返回 `Closed`

3. **序列化失败**：
   - 参数序列化失败时，已从 pending 移除，不会泄漏

### 改进建议

1. **添加请求超时**：
   ```rust
   pub(crate) async fn call_with_timeout<P, T>(
       &self,
       method: &str,
       params: &P,
       timeout: Duration,
   ) -> Result<T, RpcCallError> {
       tokio::time::timeout(timeout, self.call(method, params)).await
           .map_err(|_| RpcCallError::Timeout)?
   }
   ```

2. **响应 ID 不匹配警告**：
   ```rust
   JSONRPCMessage::Response(JSONRPCResponse { id, result }) => {
       let mut pending = pending.lock().await;
       if let Some(sender) = pending.remove(&id) {
           let _ = sender.send(Ok(result));
       } else {
           warn!("received response for unknown request ID: {id}");
       }
   }
   ```

3. **无锁 pending 跟踪**：
   ```rust
   // 使用 dashmap 或分片锁减少竞争
   use dashmap::DashMap;
   pending: Arc<DashMap<RequestId, PendingRequest>>,
   ```

4. **通知缓冲**：
   ```rust
   // 使用广播通道或持久化队列
   let (event_tx, _) = broadcast::channel(128);
   ```

5. **指标暴露**：
   ```rust
   pub(crate) async fn pending_request_count(&self) -> usize {
       self.pending.lock().await.len()
   }
   
   // 添加更多指标：请求延迟、吞吐量、错误率
   ```

6. **请求取消支持**：
   ```rust
   pub(crate) async fn call_cancellable<P, T>(
       &self,
       method: &str,
       params: &P,
   ) -> (RequestId, impl Future<Output = Result<T, RpcCallError>>) {
       // 返回请求 ID，允许调用者取消
   }
   
   pub(crate) async fn cancel(&self, request_id: RequestId) {
       // 发送取消通知，从 pending 移除
   }
   ```

### 测试覆盖

当前包含一个关键测试：

```rust
#[tokio::test]
async fn rpc_client_matches_out_of_order_responses_by_request_id() {
    // 验证乱序响应能正确匹配到对应请求
    // 发送 slow 和 fast 两个请求
    // 服务器先返回 fast，再返回 slow
    // 验证两个调用都能收到正确响应
}
```

建议添加：
- 连接断开时的 pending 清理测试
- 通知接收测试
- 高并发请求测试
- 序列化/反序列化错误测试
