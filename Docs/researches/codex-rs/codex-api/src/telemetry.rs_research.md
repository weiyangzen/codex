# telemetry.rs 研究文档

## 场景与职责

`telemetry.rs` 是 `codex-api` crate 的遥测接口模块，负责定义 API 层的遥测回调接口，并提供带遥测的重试执行包装器。该模块是 Codex 可观测性架构的关键组件：

1. **遥测接口定义**: 定义 SSE 和 WebSocket 的遥测回调 trait
2. **请求遥测集成**: 将 `codex-client` 的 `RequestTelemetry` 集成到重试流程
3. **性能指标收集**: 收集请求延迟、重试次数、错误率等指标

在架构中，该模块向上层（`codex-core`, `otel` crate）提供遥测扩展点，向下层（`codex-client`）消费基础遥测能力。

## 功能点目的

### 1. SseTelemetry Trait
SSE（Server-Sent Events）流的遥测接口：

```rust
pub trait SseTelemetry: Send + Sync {
    fn on_sse_poll(
        &self,
        result: &Result<Option<Result<Event, EventStreamError<TransportError>>>, Elapsed>,
        duration: Duration,
    );
}
```

- **调用时机**: 每次 SSE 轮询完成后
- **参数**: 轮询结果（事件、错误或超时）、耗时
- **用途**: 监控 SSE 流健康状态、检测空闲超时

### 2. WebsocketTelemetry Trait
WebSocket 连接的遥测接口：

```rust
pub trait WebsocketTelemetry: Send + Sync {
    fn on_ws_request(&self, duration: Duration, error: Option<&ApiError>, connection_reused: bool);
    fn on_ws_event(&self, result: &Result<Option<Result<Message, Error>>, ApiError>, duration: Duration);
}
```

- `on_ws_request`: WebSocket 请求发送后，记录延迟和错误
- `on_ws_event`: WebSocket 事件接收后，记录延迟
- **用途**: 监控 WebSocket 连接质量、检测重连需求

### 3. run_with_request_telemetry 函数
带请求遥测的重试执行包装器：

```rust
pub(crate) async fn run_with_request_telemetry<T, F, Fut>(
    policy: RetryPolicy,
    telemetry: Option<Arc<dyn RequestTelemetry>>,
    make_request: impl FnMut() -> Request,
    send: F,
) -> Result<T, TransportError>
```

- 包装 `codex_client::run_with_retry`，添加每轮尝试的遥测
- 记录：尝试次数、HTTP 状态码、错误、耗时
- 支持一元和流式 HTTP 调用

## 具体技术实现

### 关键数据结构

```rust
/// SSE 遥测接口
pub trait SseTelemetry: Send + Sync {
    fn on_sse_poll(
        &self,
        result: &Result<
            Option<
                Result<
                    eventsource_stream::Event,
                    eventsource_stream::EventStreamError<TransportError>,
                >,
            >,
            tokio::time::error::Elapsed,
        >,
        duration: Duration,
    );
}

/// WebSocket 遥测接口
pub trait WebsocketTelemetry: Send + Sync {
    fn on_ws_request(&self, duration: Duration, error: Option<&ApiError>, connection_reused: bool);
    fn on_ws_event(
        &self,
        result: &Result<Option<Result<Message, Error>>, ApiError>,
        duration: Duration,
    );
}

/// 内部 trait：提取 HTTP 状态码
trait WithStatus {
    fn status(&self) -> StatusCode;
}
```

### 核心实现逻辑

#### 状态码提取
```rust
impl WithStatus for Response {
    fn status(&self) -> StatusCode {
        self.status
    }
}

impl WithStatus for StreamResponse {
    fn status(&self) -> StatusCode {
        self.status
    }
}

fn http_status(err: &TransportError) -> Option<StatusCode> {
    match err {
        TransportError::Http { status, .. } => Some(*status),
        _ => None,
    }
}
```

#### 带遥测的重试执行
```rust
pub(crate) async fn run_with_request_telemetry<T, F, Fut>(...)
where
    T: WithStatus,
    F: Clone + Fn(Request) -> Fut,
    Fut: Future<Output = Result<T, TransportError>>,
{
    run_with_retry(policy, make_request, move |req, attempt| {
        let telemetry = telemetry.clone();
        let send = send.clone();
        async move {
            let start = Instant::now();
            let result = send(req).await;
            
            // 记录遥测
            if let Some(t) = telemetry.as_ref() {
                let (status, err) = match &result {
                    Ok(resp) => (Some(resp.status()), None),
                    Err(err) => (http_status(err), Some(err)),
                };
                t.on_request(attempt, status, err, start.elapsed());
            }
            
            result
        }
    }).await
}
```

### 调用流程

```
endpoint/session.rs: EndpointSession::execute_with()
    -> run_with_request_telemetry()
        -> run_with_retry() [from codex_client]
            -> make_request() [闭包]
            -> send(req, attempt) [闭包]
                -> 记录遥测
                -> transport.execute(req) 或 transport.stream(req)
```

## 关键代码路径与文件引用

### 内部调用关系
```
telemetry.rs
├── SseTelemetry (被 endpoint/responses.rs 使用)
├── WebsocketTelemetry (被 responses_websocket.rs 使用)
└── run_with_request_telemetry (被 endpoint/session.rs 使用)
    ├── WithStatus trait (内部实现)
    ├── http_status (内部函数)
    └── codex_client::run_with_retry
```

### 被调用方
- `codex-rs/codex-api/src/endpoint/session.rs`: `EndpointSession::execute_with()`, `stream_with()`
- `codex-rs/codex-api/src/endpoint/responses.rs`: `ResponsesClient::with_telemetry()`
- `codex-rs/codex-api/src/endpoint/responses_websocket.rs`: `run_websocket_response_stream()`
- `codex-rs/codex-api/src/sse/responses.rs`: `process_sse()`

### 依赖类型
- `codex_client::RequestTelemetry`: 基础遥测接口
- `codex_client::run_with_retry`: 重试执行器
- `codex_client::Response`, `StreamResponse`: 响应类型
- `eventsource_stream::Event`, `EventStreamError`: SSE 类型
- `tokio_tungstenite::tungstenite::Message`, `Error`: WebSocket 类型

## 依赖与外部交互

### 外部依赖
| Crate | 用途 |
|-------|------|
| `codex_client` | `RequestTelemetry`, `run_with_retry`, `Response`, `StreamResponse`, `TransportError` |
| `http` | `StatusCode` |
| `tokio::time` | `Instant`, `Duration` |
| `eventsource_stream` | SSE 事件类型 |
| `tokio_tungstenite::tungstenite` | WebSocket 消息和错误类型 |

### 遥测数据流

```
API 调用
    -> run_with_request_telemetry
        -> on_request(attempt, status, error, duration)
            -> otel crate (OpenTelemetry 导出)
            -> core crate (内部指标)
            -> tui (UI 状态更新)
```

## 风险、边界与改进建议

### 已知风险

1. **遥测闭包捕获**
   - `telemetry` 使用 `Arc` 克隆，每次重试都增加引用计数
   - 在极端重试场景下可能有轻微性能开销
   - 缓解：使用 `Option<Arc<...>>`，仅在需要时克隆

2. **错误类型转换**
   - `http_status()` 仅提取 `TransportError::Http` 的状态码
   - `Timeout` 和 `Network` 错误无状态码，遥测中显示为 `None`
   - 建议：考虑为所有错误类型分配分类代码

3. **SSE 轮询结果复杂性**
   - `on_sse_poll` 的参数类型非常复杂（嵌套 Result/Option）
   - 调用方容易混淆各层含义
   - 建议：定义类型别名或简化结构

4. **WebSocket 错误类型不匹配**
   - `on_ws_request` 使用 `ApiError`，但 `on_ws_event` 内部使用 `Error`
   - 类型不一致可能导致混淆
   - 建议：统一错误类型或明确文档说明

### 边界条件

1. **遥测为 None**: 跳过所有遥测逻辑，零开销
2. **重试次数为 0**: 仍记录第一次尝试
3. **超时错误**: `Elapsed` 错误在 SSE 轮询中表示空闲超时
4. **状态码提取失败**: 非 HTTP 错误的状态码为 `None`

### 改进建议

1. **类型别名简化**
   ```rust
   pub type SsePollResult = Result<
       Option<Result<Event, EventStreamError<TransportError>>>,
       Elapsed,
   >;
   
   pub trait SseTelemetry: Send + Sync {
       fn on_sse_poll(&self, result: &SsePollResult, duration: Duration);
   }
   ```

2. **遥测事件枚举**
   ```rust
   pub enum TelemetryEvent {
       Request { attempt: u64, status: Option<StatusCode>, duration: Duration },
       Error { attempt: u64, kind: ErrorKind, duration: Duration },
   }
   
   pub trait Telemetry: Send + Sync {
       fn on_event(&self, event: TelemetryEvent);
   }
   ```

3. **指标聚合**
   ```rust
   // 添加批量/聚合遥测接口，减少回调频率
   pub trait BatchedTelemetry: Send + Sync {
       fn flush(&self, events: &[TelemetryEvent]);
   }
   ```

4. **文档完善**
   ```rust
   /// Called after each SSE poll attempt.
   /// 
   /// # Arguments
   /// 
   /// * `result` - `Ok(Some(Ok(event)))` if an event was received,
   ///              `Ok(Some(Err(e)))` if stream error occurred,
   ///              `Ok(None)` if stream ended,
   ///              `Err(elapsed)` if idle timeout reached
   /// * `duration` - Time spent waiting for this poll
   fn on_sse_poll(&self, result: &SsePollResult, duration: Duration);
   ```

5. **测试覆盖**
   - 当前无单元测试
   - 建议添加：
     - 遥测回调调用次数验证
     - 重试场景下的遥测数据验证
     - 错误类型正确传递验证

6. **性能优化**
   ```rust
   // 使用 weak pointer 避免循环引用（如果遥测实现持有 Provider 引用）
   // 或考虑使用 channel 批量发送遥测事件
   ```

7. **扩展性**
   ```rust
   // 添加上下文支持，允许传递自定义元数据
   pub trait SseTelemetry: Send + Sync {
       fn on_sse_poll(&self, ctx: &TelemetryContext, result: &SsePollResult, duration: Duration);
   }
   ```
