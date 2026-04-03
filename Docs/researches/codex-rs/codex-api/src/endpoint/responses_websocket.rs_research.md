# responses_websocket.rs 研究文档

## 场景与职责

`responses_websocket.rs` 是 Codex API 客户端中负责**WebSocket 响应流**功能的核心模块。与 HTTP SSE 相比，WebSocket 提供了双向实时通信能力，支持：
- 更低的延迟
- 连接复用（60 分钟限制后需要新建连接）
- 服务器主动推送
- 更高效的二进制数据传输

该模块提供了 `ResponsesWebsocketClient` 和 `ResponsesWebsocketConnection` 结构体，用于建立和管理与后端 `responses` WebSocket 端点的长连接。

## 功能点目的

1. **WebSocket 连接管理**：建立和维护与后端的 WebSocket 连接
2. **双向流式通信**：支持发送请求和接收流式响应
3. **自动心跳处理**：处理 Ping/Pong 保持连接活跃
4. **错误恢复**：处理连接限制、超时等错误场景
5. **元数据提取**：从连接响应头提取模型信息、ETag 等
6. **TLS 配置**：支持自定义 CA 证书的 TLS 配置

## 具体技术实现

### 核心数据结构

#### WebSocket 流包装器
```rust
struct WsStream {
    tx_command: mpsc::Sender<WsCommand>,
    rx_message: mpsc::UnboundedReceiver<Result<Message, WsError>>,
    pump_task: tokio::task::JoinHandle<(),
}

enum WsCommand {
    Send {
        message: Message,
        tx_result: oneshot::Sender<Result<(), WsError>>,
    },
}
```

- 使用命令模式封装 WebSocket 操作
- 独立的 pump 任务处理消息收发
- 自动处理 Ping/Pong

#### WebSocket 连接
```rust
pub struct ResponsesWebsocketConnection {
    stream: Arc<Mutex<Option<WsStream>>>,
    idle_timeout: Duration,
    server_reasoning_included: bool,
    models_etag: Option<String>,
    server_model: Option<String>,
    telemetry: Option<Arc<dyn WebsocketTelemetry>>,
}
```

#### WebSocket 客户端
```rust
pub struct ResponsesWebsocketClient<A: AuthProvider> {
    provider: Provider,
    auth: A,
}
```

### 关键流程

#### 1. 建立连接
```rust
pub async fn connect(
    &self,
    extra_headers: HeaderMap,
    default_headers: HeaderMap,
    turn_state: Option<Arc<OnceLock<String>>>,
    telemetry: Option<Arc<dyn WebsocketTelemetry>>,
) -> Result<ResponsesWebsocketConnection, ApiError>
```

流程：
1. 构建 WebSocket URL（`wss://` 或 `ws://`）
2. 合并请求头（provider + extra + default）
3. 添加认证头
4. 建立 TLS 连接（支持自定义 CA）
5. 提取响应头元数据
6. 创建 `ResponsesWebsocketConnection`

#### 2. 发送流式请求
```rust
pub async fn stream_request(
    &self,
    request: ResponsesWsRequest,
    connection_reused: bool,
) -> Result<ResponseStream, ApiError>
```

流程：
1. 序列化请求为 JSON
2. 发送服务器元数据事件（model, etag, reasoning）
3. 在独立任务中运行 WebSocket 响应流
4. 返回 `ResponseStream` 供调用者消费

#### 3. WebSocket 消息泵
```rust
async fn run_websocket_response_stream(
    ws_stream: &mut WsStream,
    tx_event: mpsc::Sender<std::result::Result<ResponseEvent, ApiError>>,
    request_body: Value,
    idle_timeout: Duration,
    telemetry: Option<Arc<dyn WebsocketTelemetry>>,
    connection_reused: bool,
) -> Result<(), ApiError>
```

处理：
- 发送请求消息
- 循环接收响应消息
- 处理空闲超时
- 解析和转换事件
- 错误映射和恢复

### 错误处理

#### WebSocket 错误映射
```rust
fn map_ws_error(err: WsError, url: &Url) -> ApiError {
    match err {
        WsError::Http(response) => ApiError::Transport(TransportError::Http { ... }),
        WsError::ConnectionClosed | WsError::AlreadyClosed => {
            ApiError::Stream("websocket closed".to_string())
        }
        WsError::Io(err) => ApiError::Transport(TransportError::Network(...)),
        other => ApiError::Transport(TransportError::Network(...)),
    }
}
```

#### 包装错误事件处理
```rust
fn map_wrapped_websocket_error_event(
    event: WrappedWebsocketErrorEvent,
    original_payload: String,
) -> Option<ApiError>
```

特殊处理 `websocket_connection_limit_reached` 错误：
- 转换为 `ApiError::Retryable`
- 提示创建新连接

### TLS 配置

```rust
let connector = maybe_build_rustls_client_config_with_custom_ca()
    .map_err(|err| ApiError::Stream(format!("failed to configure websocket TLS: {err}")))?
    .map(tokio_tungstenite::Connector::Rustls);
```

支持通过环境变量配置的自定义 CA 证书。

### WebSocket 配置

```rust
fn websocket_config() -> WebSocketConfig {
    let mut extensions = ExtensionsConfig::default();
    extensions.permessage_deflate = Some(DeflateConfig::default());
    
    let mut config = WebSocketConfig::default();
    config.extensions = extensions;
    config
}
```

启用 `permessage-deflate` 扩展进行消息压缩。

### 关键常量

```rust
const X_CODEX_TURN_STATE_HEADER: &str = "x-codex-turn-state";
const X_MODELS_ETAG_HEADER: &str = "x-models-etag";
const X_REASONING_INCLUDED_HEADER: &str = "x-reasoning-included";
const OPENAI_MODEL_HEADER: &str = "openai-model";
const WEBSOCKET_CONNECTION_LIMIT_REACHED_CODE: &str = "websocket_connection_limit_reached";
const WEBSOCKET_CONNECTION_LIMIT_REACHED_MESSAGE: &str = 
    "Responses websocket connection limit reached (60 minutes). Create a new websocket connection to continue.";
```

## 关键代码路径与文件引用

### 内部依赖

| 文件 | 用途 |
|------|------|
| `crate::auth::{AuthProvider, add_auth_headers_to_header_map}` | 认证 |
| `crate::common::{ResponseEvent, ResponseStream, ResponsesWsRequest}` | 响应类型 |
| `crate::error::ApiError` | 错误类型 |
| `crate::provider::Provider` | 端点配置 |
| `crate::rate_limits::parse_rate_limit_event` | 速率限制解析 |
| `crate::sse::responses::{ResponsesStreamEvent, process_responses_event}` | 事件处理 |
| `crate::telemetry::WebsocketTelemetry` | 遥测 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `tokio_tungstenite` | WebSocket 客户端 |
| `tokio::net::TcpStream` | TCP 连接 |
| `futures::{SinkExt, StreamExt}` | 异步流处理 |
| `codex_client::maybe_build_rustls_client_config_with_custom_ca` | TLS 配置 |
| `codex_utils_rustls_provider::ensure_rustls_crypto_provider` | rustls 初始化 |

### API 端点

- **WebSocket URL**: `wss://{base_url}/responses` 或 `ws://{base_url}/responses`
- **协议**: WebSocket with permessage-deflate
- **TLS**: 支持自定义 CA 证书

### 请求/响应消息格式

#### 请求（WebSocket Text）
```json
{
  "type": "response.create",
  "model": "gpt-4",
  "instructions": "...",
  "input": [...],
  ...
}
```

#### 响应事件（WebSocket Text）
```json
{"type": "response.created", "response": {"id": "resp-1"}}
{"type": "response.output_item.done", "item": {...}}
{"type": "response.completed", "response": {"id": "resp-1", "usage": {...}}}
```

## 依赖与外部交互

### 调用关系

```
ResponsesWebsocketClient::connect
  ├─> provider.websocket_url_for_path("responses")
  ├─> merge_request_headers
  ├─> add_auth_headers_to_header_map
  └─> connect_websocket
      ├─> ensure_rustls_crypto_provider
      ├─> maybe_build_rustls_client_config_with_custom_ca
      ├─> connect_async_tls_with_config
      └─> WsStream::new

ResponsesWebsocketConnection::stream_request
  └─> run_websocket_response_stream (spawn)
      ├─> ws_stream.send(request)
      └─> loop { ws_stream.next() }
          ├─> parse_wrapped_websocket_error_event
          ├─> process_responses_event
          └─> tx_event.send(event)
```

### 连接生命周期

1. **创建**: `ResponsesWebsocketClient::new` -> `connect`
2. **请求**: `stream_request` -> 发送请求 -> 接收流式响应
3. **关闭**: 连接错误或 `Drop` 时 `pump_task.abort()`

### 并发模型

- 每个连接有一个独立的 pump 任务（`tokio::spawn`）
- 使用 `mpsc` 通道进行命令发送
- 使用 `mpsc` 无界通道接收消息
- `Mutex` 保护共享的流状态

## 风险、边界与改进建议

### 风险点

1. **连接限制**: 60 分钟连接限制需要客户端处理重连
2. **内存泄漏**: `UnboundedReceiver` 可能无限增长，如果消费者跟不上
3. **TLS 配置**: 自定义 CA 配置失败会导致连接失败
4. **消息丢失**: 连接中断时未确认的消息可能丢失
5. **并发安全**: `Arc<Mutex<Option<WsStream>>>` 的复杂性

### 边界条件

1. **连接超时**: 初始连接可能超时
2. **空闲超时**: `idle_timeout` 后无消息会触发错误
3. **消息大小**: 超大消息可能导致内存问题
4. **并发请求**: 同一连接上的并发请求处理

### 测试覆盖

模块包含完善的单元测试：

1. **`websocket_config_enables_permessage_deflate`**
   - 验证 WebSocket 压缩扩展启用

2. **`parse_wrapped_websocket_error_event_maps_to_transport_http`**
   - 验证错误事件解析为 HTTP 错误
   - 测试状态码、头、响应体提取

3. **`parse_wrapped_websocket_error_event_ignores_non_error_payloads`**
   - 验证非错误事件被正确忽略

4. **`parse_wrapped_websocket_error_event_with_status_maps_invalid_request`**
   - 验证 400 错误映射

5. **`parse_wrapped_websocket_error_event_with_connection_limit_maps_retryable`**
   - 验证连接限制错误映射为可重试错误

6. **`parse_wrapped_websocket_error_event_without_status_is_not_mapped`**
   - 验证无状态码错误不被映射

7. **`merge_request_headers_matches_http_precedence`**
   - 验证头合并优先级：provider > extra > default

### 改进建议

1. **连接池**: 实现 WebSocket 连接池，支持连接复用和自动重连

2. **背压处理**: 将 `UnboundedReceiver` 改为有界通道，防止内存无限增长

   ```rust
   let (tx_message, rx_message) = mpsc::channel::<Result<Message, WsError>>(1024);
   ```

3. **优雅关闭**: 实现 WebSocket 的优雅关闭握手

4. **心跳检测**: 添加客户端主动心跳，检测死连接

5. **重连策略**: 内置指数退避重连机制

6. **消息确认**: 实现消息确认机制，确保不丢失

7. **并发控制**: 限制同一连接的并发请求数

8. **指标收集**: 添加连接时长、消息数、错误率等指标

9. **流控**: 实现基于接收速度的流控机制

### 代码质量评估

- **优点**:
  - 完善的错误处理和映射
  - 良好的测试覆盖（特别是错误场景）
  - 使用 `tracing` 提供详细的日志
  - 支持 TLS 自定义配置
  - 清晰的并发模型

- **可改进**:
  - `WsStream` 使用 `UnboundedReceiver` 有内存风险
  - 缺少连接池和自动重连
  - `stream_request` 较长，可进一步拆分
  - 缺少背压和流控机制

### 关键设计决策

1. **命令模式**: 使用 `WsCommand` 封装 WebSocket 操作，简化并发控制
2. **Pump 任务**: 独立的 pump 任务处理底层 I/O，上层只处理业务逻辑
3. **错误包装**: 通过 `WrappedWebsocketErrorEvent` 统一处理服务端错误
4. **连接限制处理**: 将连接限制错误映射为 `Retryable`，提示客户端重连
