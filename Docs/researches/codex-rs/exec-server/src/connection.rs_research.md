# connection.rs 深入研究文档

## 场景与职责

`connection.rs` 是 `codex-exec-server` crate 的传输层抽象模块，负责将底层 I/O 流（WebSocket 或标准输入/输出）包装为统一的 JSON-RPC 消息通道。它是客户端与服务器之间通信的桥梁，处理消息的序列化、反序列化、帧解析和连接生命周期。

## 功能点目的

### 1. 传输层抽象
- **目的**：统一 WebSocket 和 stdio 两种传输方式，为上层提供一致的 JSON-RPC 消息接口
- **设计**：通过 `JsonRpcConnection` 结构体封装底层差异

### 2. 异步消息处理
- **目的**：支持高并发、非阻塞的消息收发
- **实现**：使用 `tokio::sync::mpsc` 通道分离读写任务

### 3. 错误隔离与恢复
- **目的**：单个消息解析失败不导致连接中断
- **实现**：通过 `MalformedMessage` 事件通知上层，继续处理后续消息

### 4. WebSocket 帧处理
- **目的**：正确处理 WebSocket 的不同帧类型（Text、Binary、Close、Ping/Pong）
- **实现**：区分处理各类帧，忽略控制帧

## 具体技术实现

### 核心数据结构

```rust
// 连接事件枚举，表示从连接接收到的各种事件
#[derive(Debug)]
pub(crate) enum JsonRpcConnectionEvent {
    Message(JSONRPCMessage),           // 成功解析的 JSON-RPC 消息
    MalformedMessage { reason: String }, // 格式错误的消息
    Disconnected { reason: Option<String> }, // 连接断开
}

// 连接结构体，封装发送通道、接收通道和任务句柄
pub(crate) struct JsonRpcConnection {
    outgoing_tx: mpsc::Sender<JSONRPCMessage>,    // 发送消息到对端
    incoming_rx: mpsc::Receiver<JsonRpcConnectionEvent>, // 接收来自对端的事件
    task_handles: Vec<tokio::task::JoinHandle<()>>, // 读写任务句柄
}
```

### 通道容量

```rust
pub(crate) const CHANNEL_CAPACITY: usize = 128;
```

使用有界通道防止内存无限增长，128 是经验值平衡吞吐量和内存占用。

### WebSocket 连接创建

```rust
pub(crate) fn from_websocket<S>(stream: WebSocketStream<S>, connection_label: String) -> Self
where
    S: AsyncRead + AsyncWrite + Unpin + Send + 'static,
{
    // 1. 创建 mpsc 通道
    let (outgoing_tx, mut outgoing_rx) = mpsc::channel(CHANNEL_CAPACITY);
    let (incoming_tx, incoming_rx) = mpsc::channel(CHANNEL_CAPACITY);
    
    // 2. 分割 WebSocket 流为读写两半
    let (mut websocket_writer, mut websocket_reader) = stream.split();
    
    // 3. 启动读取任务：将 WebSocket 帧解析为 JSON-RPC 消息
    let reader_task = tokio::spawn(async move {
        loop {
            match websocket_reader.next().await {
                Some(Ok(Message::Text(text))) => { /* 解析 JSON */ }
                Some(Ok(Message::Binary(bytes))) => { /* 解析 JSON */ }
                Some(Ok(Message::Close(_))) => { /* 断开 */ }
                Some(Ok(Message::Ping(_))) | Some(Ok(Message::Pong(_))) => { /* 忽略 */ }
                Some(Ok(_)) => { /* 其他类型忽略 */ }
                Some(Err(err)) => { /* 错误断开 */ }
                None => { /* 流结束断开 */ }
            }
        }
    });
    
    // 4. 启动写入任务：将 JSON-RPC 消息序列化为 WebSocket 帧
    let writer_task = tokio::spawn(async move {
        while let Some(message) = outgoing_rx.recv().await {
            // 序列化并发送 Text 帧
        }
    });
    
    // 5. 返回连接实例
    Self { outgoing_tx, incoming_rx, task_handles: vec![reader_task, writer_task] }
}
```

### stdio 连接创建（测试专用）

```rust
#[cfg(test)]
pub(crate) fn from_stdio<R, W>(reader: R, writer: W, connection_label: String) -> Self
where
    R: AsyncRead + Unpin + Send + 'static,
    W: AsyncWrite + Unpin + Send + 'static,
{
    // 类似 WebSocket，但使用行缓冲 I/O
    // 每行一个 JSON-RPC 消息
}
```

### 消息序列化

```rust
fn serialize_jsonrpc_message(message: &JSONRPCMessage) -> Result<String, serde_json::Error> {
    serde_json::to_string(message)
}

#[cfg(test)]
async fn write_jsonrpc_line_message<W>(
    writer: &mut BufWriter<W>,
    message: &JSONRPCMessage,
) -> std::io::Result<()>
where
    W: AsyncWrite + Unpin,
{
    let encoded = serialize_jsonrpc_message(message)
        .map_err(|err| std::io::Error::other(err.to_string()))?;
    writer.write_all(encoded.as_bytes()).await?;
    writer.write_all(b"\n").await?;  // 行分隔符
    writer.flush().await
}
```

### 辅助函数

```rust
// 发送断开事件
async fn send_disconnected(
    incoming_tx: &mpsc::Sender<JsonRpcConnectionEvent>,
    reason: Option<String>,
) {
    let _ = incoming_tx
        .send(JsonRpcConnectionEvent::Disconnected { reason })
        .await;
}

// 发送格式错误事件
async fn send_malformed_message(
    incoming_tx: &mpsc::Sender<JsonRpcConnectionEvent>,
    reason: Option<String>,
) {
    let _ = incoming_tx
        .send(JsonRpcConnectionEvent::MalformedMessage {
            reason: reason.unwrap_or_else(|| "malformed JSON-RPC message".to_string()),
        })
        .await;
}
```

## 关键代码路径与文件引用

### 内部依赖

| 模块 | 路径 | 用途 |
|------|------|------|
| `codex_app_server_protocol` | 外部 crate | `JSONRPCMessage` 类型定义 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `tokio::sync::mpsc` | 有界异步通道 |
| `tokio::io` | 异步 I/O trait |
| `tokio_tungstenite` | WebSocket 支持 |
| `futures::SinkExt/StreamExt` | Stream/Sink 扩展方法 |
| `serde_json` | JSON 解析 |

### 使用位置

| 文件 | 使用方式 |
|------|----------|
| `client.rs` | `JsonRpcConnection::from_websocket` 包装 WebSocket 流 |
| `rpc.rs` | 调用 `into_parts()` 获取通道和任务句柄 |
| `server/processor.rs` | `JsonRpcConnection::from_websocket` 处理服务器端连接 |
| `server/transport.rs` | 创建连接并传递给 `run_connection` |

### 关键代码路径

1. **WebSocket 消息接收**：
   ```
   websocket_reader.next() -> Message::Text/Binary 
   -> serde_json::from_str/slice 
   -> JsonRpcConnectionEvent::Message 
   -> incoming_tx.send()
   ```

2. **WebSocket 消息发送**：
   ```
   outgoing_rx.recv() 
   -> serialize_jsonrpc_message 
   -> websocket_writer.send(Message::Text(...))
   ```

3. **连接解构**：
   ```
   into_parts() -> (outgoing_tx, incoming_rx, task_handles)
   ```

## 依赖与外部交互

### 与 protocol 的交互
- 使用 `codex_app_server_protocol::JSONRPCMessage` 作为消息类型

### 与 rpc 的交互
- `RpcClient::new` 消费 `JsonRpcConnection` 并调用 `into_parts()`
- 获得发送通道、接收通道和任务句柄

### 与 server 的交互
- `transport.rs` 创建 `JsonRpcConnection` 并传递给 `processor::run_connection`
- `processor.rs` 调用 `into_parts()` 处理消息循环

## 风险、边界与改进建议

### 当前风险

1. **任务泄漏风险**：
   ```rust
   pub(crate) fn into_parts(self) -> (...task_handles) {
       (self.outgoing_tx, self.incoming_rx, self.task_handles)
   }
   ```
   调用方必须妥善管理 `task_handles`，否则任务可能在后台无限运行。

2. **消息大小限制**：
   - WebSocket 帧大小无显式限制
   - 超大消息可能导致内存问题

3. **背压处理**：
   - 使用有界通道 (128) 提供基本背压
   - 但发送方阻塞时无超时机制

4. **序列化错误处理**：
   ```rust
   Err(err) => {
       send_disconnected(&incoming_tx, Some(format!("failed to serialize..."))).await;
       break;
   }
   ```
   序列化失败导致整个连接关闭，可能过于激进。

### 边界情况

1. **空行处理**（stdio 模式）：
   ```rust
   if line.trim().is_empty() {
       continue;
   }
   ```

2. **Ping/Pong 处理**：
   ```rust
   Some(Ok(Message::Ping(_))) | Some(Ok(Message::Pong(_))) => {}
   ```
   自动由 `tokio_tungstenite` 处理，应用层忽略。

3. **半开连接**：
   - 读取任务检测到断开时发送 `Disconnected` 事件
   - 写入任务独立运行，可能稍后才发现断开

### 改进建议

1. **添加消息大小限制**：
   ```rust
   const MAX_MESSAGE_SIZE: usize = 10 * 1024 * 1024; // 10MB
   ```

2. **优雅关闭**：
   ```rust
   impl JsonRpcConnection {
       pub async fn shutdown(mut self) {
           // 1. 关闭 outgoing_tx
           // 2. 等待 writer_task 完成
           // 3. 发送 Close 帧
           // 4. 等待 reader_task 完成
       }
   }
   ```

3. **批量发送优化**：
   ```rust
   // 使用 futures::stream::StreamExt::ready_chunks
   while let Some(messages) = outgoing_rx.ready_chunks(10).await {
       // 批量序列化和发送
   }
   ```

4. **指标监控**：
   - 消息吞吐量
   - 序列化/反序列化耗时
   - 通道积压深度

5. **压缩支持**：
   ```rust
   // 检测大消息并启用压缩
   if encoded.len() > COMPRESS_THRESHOLD {
       // 使用 permessage-deflate
   }
   ```

6. **连接标签改进**：
   当前仅用于日志，可考虑：
   - 添加到 span 用于分布式追踪
   - 作为指标标签
