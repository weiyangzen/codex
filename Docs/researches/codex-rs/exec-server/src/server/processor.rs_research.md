# 连接处理器研究文档

## 场景与职责

`processor.rs` 是 codex-exec-server 的核心请求处理模块，负责管理单个 JSON-RPC 连接的生命周期和消息处理。它实现了完整的请求分发、通知处理和错误恢复机制，是连接层（transport）与业务逻辑层（handler）之间的桥梁。

该模块位于 `codex-rs/exec-server/src/server/processor.rs`，是 exec-server 中最关键的协调组件。

## 功能点目的

### 1. 连接生命周期管理
- **目的**: 管理单个客户端连接的完整生命周期，从建立到关闭
- **实现**: `run_connection` 函数作为主循环，处理所有连接事件直到断开

### 2. 消息分类处理
- **目的**: 区分并正确处理不同类型的 JSON-RPC 消息
- **实现**: 
  - `Request` → 分发到对应处理方法，返回响应
  - `Notification` → 异步处理，无响应
  - `Response`/`Error` → 协议错误（服务器不应收到）

### 3. 请求路由分发
- **目的**: 将请求路由到正确的处理方法
- **实现**: `dispatch_request` 函数根据 `method` 字段匹配处理逻辑

### 4. 错误恢复与优雅降级
- **目的**: 在出现协议错误时优雅地关闭连接
- **实现**: 
  - 格式错误的消息返回错误响应并继续
  - 协议错误（如收到响应）关闭连接

## 具体技术实现

### 核心流程

#### 连接主循环 (`run_connection`)
```rust
pub(crate) async fn run_connection(connection: JsonRpcConnection) {
    let (json_outgoing_tx, mut incoming_rx, _connection_tasks) = connection.into_parts();
    let handler = ExecServerHandler::new();

    while let Some(event) = incoming_rx.recv().await {
        match event {
            JsonRpcConnectionEvent::Message(message) => { /* 处理消息 */ }
            JsonRpcConnectionEvent::MalformedMessage { reason } => { /* 返回错误 */ }
            JsonRpcConnectionEvent::Disconnected { reason } => { /* 退出循环 */ }
        }
    }

    handler.shutdown().await;
}
```

#### 消息处理流程
```
┌─────────────────┐
│  JsonRpcConnection  │
│  (WebSocket/stdio)  │
└────────┬────────┘
         │ JSON-RPC Message
         v
┌─────────────────┐
│ run_connection  │
│   主事件循环     │
└────────┬────────┘
         │ JsonRpcConnectionEvent
         v
┌─────────────────┐
│ handle_connection_message │
│    消息分类处理   │
└────────┬────────┘
         │
    ┌────┴────┐
    v         v
┌───────┐  ┌────────┐
│Request│  │Notification│
└───┬───┘  └────┬───┘
    v           v
┌──────────┐  ┌─────────────┐
│dispatch_ │  │handle_      │
│request   │  │notification │
└──────────┘  └─────────────┘
```

### 关键函数详解

#### 1. `run_connection` - 连接主循环
```rust
pub(crate) async fn run_connection(connection: JsonRpcConnection) {
    let (json_outgoing_tx, mut incoming_rx, _connection_tasks) = connection.into_parts();
    let handler = ExecServerHandler::new();

    while let Some(event) = incoming_rx.recv().await {
        match event {
            JsonRpcConnectionEvent::Message(message) => {
                let response = match handle_connection_message(&handler, message).await {
                    Ok(response) => response,
                    Err(err) => {
                        tracing::warn!("closing exec-server connection after protocol error: {err}");
                        break;
                    }
                };
                // 发送响应...
            }
            JsonRpcConnectionEvent::MalformedMessage { reason } => {
                // 返回 invalid_request 错误...
            }
            JsonRpcConnectionEvent::Disconnected { reason } => {
                break;
            }
        }
    }

    handler.shutdown().await;
}
```

**关键点**:
- 每个连接创建独立的 `ExecServerHandler` 实例
- 协议错误导致连接关闭，格式错误仅返回错误响应
- 使用 `tokio::mpsc` 通道进行异步消息传递

#### 2. `handle_connection_message` - 消息分类
```rust
pub(crate) async fn handle_connection_message(
    handler: &ExecServerHandler,
    message: JSONRPCMessage,
) -> Result<Option<JSONRPCMessage>, String> {
    match message {
        JSONRPCMessage::Request(request) => 
            Ok(Some(dispatch_request(handler, request))),
        JSONRPCMessage::Notification(notification) => {
            handle_notification(handler, notification)?;
            Ok(None)  // 通知无响应
        }
        JSONRPCMessage::Response(response) => 
            Err(format!("unexpected client response...")),
        JSONRPCMessage::Error(error) => 
            Err(format!("unexpected client error...")),
    }
}
```

**设计决策**:
- 返回 `Option<JSONRPCMessage>` 区分需要响应和不需要响应的场景
- 使用 `Result` 表示协议错误（需要关闭连接）

#### 3. `dispatch_request` - 请求分发
```rust
fn dispatch_request(handler: &ExecServerHandler, request: JSONRPCRequest) -> JSONRPCMessage {
    let JSONRPCRequest { id, method, params, trace: _ } = request;

    match method.as_str() {
        INITIALIZE_METHOD => {
            let result = serde_json::from_value::<InitializeParams>(...)
                .map_err(|err| invalid_params(err.to_string()))
                .and_then(|_params| handler.initialize())
                .and_then(|response| {
                    serde_json::to_value(response).map_err(|err| invalid_params(err.to_string()))
                });
            response_message(id, result)
        }
        other => response_message(
            id,
            Err(method_not_found(format!(
                "exec-server stub does not implement `{other}` yet"
            ))),
        ),
    }
}
```

**处理流程**:
1. 解析参数 JSON → `InitializeParams`
2. 调用 `handler.initialize()` 执行业务逻辑
3. 序列化响应 → JSON Value
4. 任何步骤失败都转换为 JSON-RPC 错误

#### 4. `handle_notification` - 通知处理
```rust
fn handle_notification(
    handler: &ExecServerHandler,
    notification: JSONRPCNotification,
) -> Result<(), String> {
    match notification.method.as_str() {
        INITIALIZED_METHOD => handler.initialized(),
        other => Err(format!("unexpected notification method: {other}")),
    }
}
```

**注意**: 通知处理返回 `String` 错误（协议错误），而非 JSON-RPC 错误

### 错误处理策略

| 错误类型 | 处理方式 | 是否关闭连接 |
|----------|----------|--------------|
| 消息格式错误 | 返回 `invalid_request` 错误响应 | 否 |
| 参数解析错误 | 返回 `invalid_params` 错误响应 | 否 |
| 方法未找到 | 返回 `method_not_found` 错误响应 | 否 |
| 收到响应消息 | 记录警告，关闭连接 | 是 |
| 收到错误消息 | 记录警告，关闭连接 | 是 |
| 未知通知方法 | 记录警告，关闭连接 | 是 |
| 初始化顺序错误 | 返回错误/错误通知 | 否 |

## 依赖与外部交互

### 内部模块依赖

```
processor.rs
    ├── handler.rs      (ExecServerHandler, 状态管理)
    ├── jsonrpc.rs      (错误构造, 响应封装)
    ├── protocol.rs     (INITIALIZE_METHOD, InitializeParams)
    └── connection.rs   (JsonRpcConnection, JsonRpcConnectionEvent)
```

### 外部 crate 依赖

| crate | 用途 |
|-------|------|
| `codex_app_server_protocol` | JSON-RPC 协议类型定义 |
| `serde_json` | JSON 序列化/反序列化 |
| `tracing` | 日志记录（debug, warn） |

### 调用关系

#### 被调用方
- `transport.rs:68` - `run_connection` 在 WebSocket 连接建立后调用

#### 调用方
- `handler.initialize()` - 处理 initialize 请求
- `handler.initialized()` - 处理 initialized 通知
- `handler.shutdown()` - 连接关闭时清理
- `jsonrpc::*` - 构造错误和响应

## 风险、边界与改进建议

### 当前风险

1. **单线程处理瓶颈**
   - 现状：每个连接的消息按顺序串行处理
   - 风险：长时间运行的请求会阻塞后续请求
   - 建议：考虑为无状态请求添加并发处理

2. **未实现方法返回 stub 错误**
   - 现状：所有未实现方法返回 "stub does not implement"
   - 风险：错误信息暴露实现细节
   - 建议：生产环境返回更通用的 "method not found"

3. **通知处理错误导致连接关闭**
   - 现状：`initialized` 顺序错误会关闭连接
   - 风险：客户端 bug 导致服务不可用
   - 建议：某些通知错误可仅记录日志而不关闭

4. **无请求超时机制**
   - 现状：请求可能无限期挂起
   - 风险：资源泄漏
   - 建议：添加请求超时处理

### 边界情况

1. **空 params 处理**
   ```rust
   params.unwrap_or(serde_json::Value::Null)
   ```
   - 允许省略 params 字段，使用 Null 作为默认值

2. **并发消息处理**
   - 当前实现保证消息按顺序处理
   - 响应顺序与请求顺序一致（JSON-RPC 要求）

3. **连接断开时的未完成请求**
   - 连接层负责通知断开事件
   - 当前不追踪未完成请求，依赖客户端处理

### 改进建议

1. **添加请求上下文追踪**
```rust
struct RequestContext {
    id: RequestId,
    method: String,
    start_time: Instant,
}
```

2. **支持批量请求 (batch requests)**
```rust
JSONRPCMessage::Batch(requests) => {
    let responses = futures::future::join_all(
        requests.into_iter().map(|req| dispatch_request(...))
    ).await;
}
```

3. **添加中间件支持**
```rust
trait Middleware {
    async fn handle(&self, request: JSONRPCRequest, next: Next) -> JSONRPCMessage;
}
```

4. **改进错误上下文**
```rust
// 当前
Err(format!("unexpected notification method: {other}"))

// 建议
Err(format!(
    "unexpected notification method '{}' (expected: initialized)",
    other
))
```

5. **metrics 集成**
```rust
metrics::counter!("exec_server_requests_total", "method" => method).increment(1);
metrics::histogram!("exec_server_request_duration_seconds").record(duration);
```

### 相关文件引用

- 本文件：`codex-rs/exec-server/src/server/processor.rs`
- 状态管理：`codex-rs/exec-server/src/server/handler.rs`
- JSON-RPC 工具：`codex-rs/exec-server/src/server/jsonrpc.rs`
- 传输层：`codex-rs/exec-server/src/server/transport.rs`
- 连接管理：`codex-rs/exec-server/src/connection.rs`
- 协议定义：`codex-rs/exec-server/src/protocol.rs`
- 入口文件：`codex-rs/exec-server/src/bin/codex-exec-server.rs`
