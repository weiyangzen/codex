# error.rs 研究文档

## 场景与职责

`error.rs` 是 `codex-api` crate 的错误定义模块，负责定义 API 层可能遇到的所有错误类型，并提供错误转换实现。该模块是错误处理链的关键环节：

1. **统一错误类型**: 将底层传输错误（`TransportError`）、速率限制错误（`RateLimitError`）转换为统一的 `ApiError`
2. **业务错误分类**: 定义 API 特定的错误变体（上下文窗口超限、配额耗尽等）
3. **错误传播**: 通过 `thiserror` 实现自动错误转换和显示

在架构中，该模块向上层（`codex-core` 等）提供统一的错误接口，向下层（`codex-client`）消费原始错误。

## 功能点目的

### 1. ApiError 枚举
定义 API 层所有可能的错误：

| 错误变体 | 用途 | 来源 |
|----------|------|------|
| `Transport` | 底层传输错误（网络、HTTP） | `codex_client::TransportError` |
| `Api` | API 返回的业务错误 | HTTP 响应解析 |
| `Stream` | 流处理错误 | SSE/WebSocket 解析 |
| `ContextWindowExceeded` | 上下文窗口超限 | `response.failed` 事件 |
| `QuotaExceeded` | 账户配额耗尽 | `response.failed` 事件 |
| `UsageNotIncluded` | 使用量未包含 | `response.failed` 事件 |
| `Retryable` | 可重试错误 | 速率限制、服务器过载 |
| `RateLimit` | 速率限制错误 | `RateLimitError` 转换 |
| `InvalidRequest` | 无效请求 | `response.failed` 事件 |
| `ServerOverloaded` | 服务器过载 | `response.failed` 事件 |

### 2. 错误转换实现
- `From<TransportError>`: 底层传输错误自动转换
- `From<RateLimitError>`: 速率限制错误转换

## 具体技术实现

### 关键数据结构

```rust
#[derive(Debug, Error)]
pub enum ApiError {
    #[error(transparent)]
    Transport(#[from] TransportError),
    
    #[error("api error {status}: {message}")]
    Api { status: StatusCode, message: String },
    
    #[error("stream error: {0}")]
    Stream(String),
    
    #[error("context window exceeded")]
    ContextWindowExceeded,
    
    #[error("quota exceeded")]
    QuotaExceeded,
    
    #[error("usage not included")]
    UsageNotIncluded,
    
    #[error("retryable error: {message}")]
    Retryable { message: String, delay: Option<Duration> },
    
    #[error("rate limit: {0}")]
    RateLimit(String),
    
    #[error("invalid request: {message}")]
    InvalidRequest { message: String },
    
    #[error("server overloaded")]
    ServerOverloaded,
}
```

### 错误转换流程

```
TransportError (codex-client)
    -> #[from] 自动转换
    -> ApiError::Transport

RateLimitError (rate_limits.rs)
    -> From<RateLimitError> 实现
    -> ApiError::RateLimit(err.to_string())
```

### 使用模式

```rust
// 自动转换示例
fn make_request() -> Result<Response, ApiError> {
    let response = transport.execute(req).await?; // TransportError -> ApiError
    Ok(response)
}

// 业务错误构造
if is_context_window_error(&error) {
    return Err(ApiError::ContextWindowExceeded);
}

// 可重试错误
Err(ApiError::Retryable { 
    message: error.message.unwrap_or_default(), 
    delay: try_parse_retry_after(&error) 
})
```

## 关键代码路径与文件引用

### 内部调用关系
```
error.rs
├── ApiError (被以下模块使用)
│   ├── sse/responses.rs: process_responses_event()
│   ├── endpoint/responses.rs: ResponsesClient::stream_request()
│   ├── endpoint/responses_websocket.rs: run_websocket_response_stream()
│   ├── endpoint/compact.rs: CompactClient
│   ├── endpoint/memories.rs: MemoriesClient
│   └── endpoint/models.rs: ModelsClient
└── From<RateLimitError> (被 rate_limits.rs 使用)
```

### 外部依赖
- `codex_client::TransportError`: 底层传输错误类型
- `http::StatusCode`: HTTP 状态码
- `rate_limits::RateLimitError`: 速率限制解析错误

### 错误来源分析

| 源文件 | 错误产生场景 |
|--------|-------------|
| `sse/responses.rs` | SSE 事件解析失败、流中断、API 错误事件 |
| `responses_websocket.rs` | WebSocket 连接失败、消息解析失败 |
| `endpoint/session.rs` | HTTP 请求执行失败 |
| `rate_limits.rs` | 速率限制头解析失败 |

## 依赖与外部交互

### 外部依赖
| Crate | 用途 |
|-------|------|
| `thiserror` | 派生宏，自动生成 Error trait 和 Display |
| `http` | `StatusCode` 类型 |
| `std::time::Duration` | 重试延迟 |
| `codex_client` | `TransportError` |
| `crate::rate_limits` | `RateLimitError` |

### 错误分类策略

1. **致命错误**: `ContextWindowExceeded`, `QuotaExceeded`, `InvalidRequest`
   - 不应重试，需用户干预
   
2. **可重试错误**: `Retryable`, `ServerOverloaded`
   - 可指数退避重试
   
3. **传输错误**: `Transport`, `Stream`
   - 可能由网络问题导致，可重试

## 风险、边界与改进建议

### 已知风险

1. **错误信息丢失**
   - `RateLimitError` 转换为 `ApiError::RateLimit(String)` 仅保留字符串表示
   - 可能丢失结构化信息（如重置时间）
   - 建议：考虑保留原始错误类型

2. **Stream 错误过于通用**
   - `Stream(String)` 使用裸字符串，缺乏结构化信息
   - 难以程序化判断错误类型
   - 建议：细分为 `ParseError`, `ConnectionError`, `TimeoutError` 等

3. **Retryable 延迟精度**
   - `delay: Option<Duration>` 由调用方解析，格式不统一
   - 不同 API 的错误消息格式可能导致解析失败
   - 建议：标准化延迟解析逻辑

### 边界条件

1. **空消息处理**: `Stream("")` 是合法但无意义的错误
2. **超大消息**: `Stream(String)` 无长度限制，可能消耗大量内存
3. **状态码范围**: `Api { status, message }` 的 status 可以是任意 u16

### 改进建议

1. **结构化错误信息**
   ```rust
   pub struct StreamError {
       pub kind: StreamErrorKind,
       pub message: String,
       pub source: Option<Box<dyn Error>>,
   }
   
   pub enum StreamErrorKind {
       Parse,
       Connection,
       Timeout,
       UnexpectedEof,
   }
   ```

2. **保留原始错误**
   ```rust
   pub enum ApiError {
       // ...
       #[error("rate limit: {0}")]
       RateLimit(#[source] RateLimitError), // 保留原始类型
   }
   ```

3. **错误代码标准化**
   ```rust
   impl ApiError {
       pub fn error_code(&self) -> &'static str {
           match self {
               Self::ContextWindowExceeded => "context_window_exceeded",
               Self::QuotaExceeded => "quota_exceeded",
               // ...
           }
       }
   }
   ```

4. **测试覆盖**
   - 当前无单元测试
   - 建议添加：错误转换测试、Display 格式测试

5. **文档完善**
   - 为每个错误变体添加何时产生的文档
   - 说明哪些错误应该重试、哪些应该终止
