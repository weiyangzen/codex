# transport.rs 研究文档

## 场景与职责

`transport.rs` 是 Codex HTTP 客户端的核心传输层模块，负责将抽象的 `Request` 转换为实际的 HTTP 请求并执行。该模块提供了同步和流式两种请求执行模式，支持请求压缩、超时配置和错误处理。

核心职责：
- 定义 `HttpTransport` trait，抽象 HTTP 传输能力
- 实现基于 `reqwest` 的具体传输层 `ReqwestTransport`
- 支持请求体 Zstd 压缩
- 提供普通请求和流式响应两种执行模式
- 统一的错误映射（将 `reqwest::Error` 转换为 `TransportError`）

## 功能点目的

### 1. HttpTransport Trait
```rust
#[async_trait]
pub trait HttpTransport: Send + Sync {
    async fn execute(&self, req: Request) -> Result<Response, TransportError>;
    async fn stream(&self, req: Request) -> Result<StreamResponse, TransportError>;
}
```
- **目的**：抽象 HTTP 传输能力，支持不同实现（如 mock、测试用）
- **方法**：
  - `execute`：普通请求，返回完整响应体
  - `stream`：流式请求，返回字节流

### 2. ReqwestTransport 结构体
```rust
#[derive(Clone, Debug)]
pub struct ReqwestTransport {
    client: CodexHttpClient,  // 包装后的 reqwest 客户端
}
```
- **目的**：基于 `reqwest` 的具体 HTTP 传输实现
- **特点**：支持 Clone，可在多任务间共享

### 3. StreamResponse 结构体
```rust
pub struct StreamResponse {
    pub status: StatusCode,
    pub headers: HeaderMap,
    pub bytes: ByteStream,  // 字节流
}
```
- **目的**：封装流式 HTTP 响应
- **ByteStream 类型**：`BoxStream<'static, Result<Bytes, TransportError>>`

### 4. 请求压缩支持
- **支持算法**：Zstd
- **压缩级别**：3（平衡速度和压缩率）
- **触发条件**：`RequestCompression::Zstd` 且请求体存在
- **头部设置**：自动添加 `Content-Encoding: zstd`

## 具体技术实现

### 请求构建流程

```rust
fn build(&self, req: Request) -> Result<CodexRequestBuilder, TransportError> {
    // 1. 解构请求
    let Request { method, url, headers, body, compression, timeout } = req;
    
    // 2. 创建 builder
    let mut builder = self.client.request(Method::from_bytes(...), &url);
    
    // 3. 设置超时
    if let Some(timeout) = timeout { ... }
    
    // 4. 处理请求体
    if let Some(body) = body {
        if compression != RequestCompression::None {
            // 4a. 压缩流程
            // - 检查 Content-Encoding 是否已存在
            // - JSON 序列化
            // - Zstd 压缩（level=3）
            // - 添加 Content-Encoding 头部
            // - 记录压缩前后大小和耗时
        } else {
            // 4b. 无压缩，直接 JSON
            builder = builder.headers(headers).json(&body);
        }
    }
    
    Ok(builder)
}
```

### 压缩实现细节

```rust
let json = serde_json::to_vec(&body)?;  // JSON 序列化
let pre_compression_bytes = json.len();
let compression_start = std::time::Instant::now();

// Zstd 压缩，级别 3
let compressed = zstd::stream::encode_all(std::io::Cursor::new(json), 3)?;
let content_encoding = http::HeaderValue::from_static("zstd");

let post_compression_bytes = compressed.len();
let compression_duration = compression_start.elapsed();

// 日志记录
tracing::info!(
    pre_compression_bytes,
    post_compression_bytes,
    compression_duration_ms = compression_duration.as_millis(),
    "Compressed request body with zstd"
);
```

### 错误映射

```rust
fn map_error(err: reqwest::Error) -> TransportError {
    if err.is_timeout() {
        TransportError::Timeout
    } else {
        TransportError::Network(err.to_string())
    }
}
```

### 执行流程对比

| 方面 | execute | stream |
|------|---------|--------|
| 响应体处理 | 一次性读取 `resp.bytes()` | 转换为 `bytes_stream()` |
| 错误响应 | 读取 body 作为错误信息 | 读取 text 作为错误信息 |
| 返回类型 | `Response` | `StreamResponse` |
| 内存占用 | 一次性加载 | 流式处理，低内存 |

## 关键代码路径与文件引用

### 当前文件关键代码

| 行号 | 内容 |
|------|------|
| 18 | `ByteStream` 类型定义 |
| 20-24 | `StreamResponse` 结构体 |
| 26-30 | `HttpTransport` trait 定义 |
| 32-35 | `ReqwestTransport` 结构体 |
| 37-42 | `ReqwestTransport::new()` |
| 44-111 | `build()` 请求构建方法 |
| 113-119 | `map_error()` 错误映射 |
| 122-154 | `execute()` 实现 |
| 156-189 | `stream()` 实现 |

### 依赖模块

| 文件 | 依赖内容 |
|------|----------|
| `default_client.rs` | `CodexHttpClient`, `CodexRequestBuilder` |
| `error.rs` | `TransportError` |
| `request.rs` | `Request`, `RequestCompression`, `Response` |

### 被调用方（使用者）

| 文件 | 使用场景 |
|------|----------|
| `codex-api/src/endpoint/session.rs` | `EndpointSession` 使用 `HttpTransport` 执行请求 |
| `codex-api/src/telemetry.rs` | 包装 transport 调用添加遥测 |
| `codex-api/tests/*.rs` | 测试中使用 mock transport |

### 依赖的外部 crate

| crate | 用途 |
|-------|------|
| `async-trait` | `#[async_trait]` 宏 |
| `bytes` | `Bytes` 类型 |
| `futures` | `StreamExt`, `BoxStream` |
| `http` | `HeaderMap`, `Method`, `StatusCode` |
| `tracing` | 日志记录（trace, info） |
| `zstd` | 请求体压缩 |

## 依赖与外部交互

### 模块依赖图
```
transport.rs
    ↑
    ├── default_client.rs (CodexHttpClient)
    ├── error.rs (TransportError)
    ├── request.rs (Request, Response)
    └── codex-api/... (使用方)
```

### 与 default_client.rs 的交互

`default_client.rs` 提供了：
- `CodexHttpClient`：包装 `reqwest::Client`，添加 OpenTelemetry 追踪头注入
- `CodexRequestBuilder`：包装 `reqwest::RequestBuilder`

关键交互点：
```rust
// transport.rs 行 54-56
let mut builder = self.client.request(
    Method::from_bytes(method.as_str().as_bytes()).unwrap_or(Method::GET),
    &url,
);
```

### 与 codex-api 的集成

`codex-api/src/endpoint/session.rs` 中的使用：
```rust
pub(crate) async fn execute_with(...)
    -> Result<Response, TransportError> 
{
    let req = self.build_request(method, path, headers, body, customize)?;
    run_with_request_telemetry(..., |req| self.transport.execute(req)).await
}

pub(crate) async fn stream_with(...)
    -> Result<StreamResponse, TransportError> 
{
    let req = self.build_request(...)?;
    self.transport.stream(req).await
}
```

## 风险、边界与改进建议

### 潜在风险

1. **unwrap_or 回退到 GET**
   ```rust
   Method::from_bytes(method.as_str().as_bytes()).unwrap_or(Method::GET)
   ```
   - 问题：非法方法字符串静默回退到 GET
   - 风险：可能导致非预期的 GET 请求
   - 建议：返回错误而非静默回退

2. **压缩冲突检测**
   ```rust
   if headers.contains_key(http::header::CONTENT_ENCODING) {
       return Err(TransportError::Build(...));
   }
   ```
   - 问题：仅检测 `Content-Encoding`，不检测 `Content-Type`
   - 建议：统一处理头部冲突

3. **大响应体内存问题**
   ```rust
   let bytes = resp.bytes().await.map_err(Self::map_error)?;  // execute 方法
   ```
   - 问题：`execute` 一次性加载整个响应体
   - 风险：大响应可能导致 OOM
   - 建议：文档明确说明使用 `stream` 处理大响应

4. **Zstd 压缩级别硬编码**
   ```rust
   zstd::stream::encode_all(..., 3)  // 行 79
   ```
   - 建议：可配置压缩级别

5. **流式响应错误处理差异**
   ```rust
   // execute: 使用 resp.bytes()
   // stream: 使用 resp.text()
   ```
   - 问题：错误响应体处理方式不一致
   - 建议：统一处理逻辑

### 边界情况

1. **空请求体 + 压缩**
   - `body: None` 时压缩配置被忽略
   - 逻辑正确

2. **timeout = None**
   - 使用 reqwest 默认超时
   - 可能无限等待

3. **超大请求体压缩**
   - Zstd 压缩在内存中完成
   - 可能占用大量内存

4. **流式响应中断**
   - 消费者 drop `ByteStream` 时连接可能被中断
   - 依赖 HTTP/1.1 或 HTTP/2 的连接管理

### 改进建议

1. **方法解析错误处理**
   ```rust
   Method::from_bytes(method.as_str().as_bytes())
       .map_err(|e| TransportError::Build(format!("invalid method: {e}")))?
   ```

2. **可配置压缩级别**
   ```rust
   pub struct Request {
       // ...
       pub compression_level: Option<i32>,  // 新增
   }
   ```

3. **添加请求/响应大小限制**
   ```rust
   pub struct ReqwestTransport {
       client: CodexHttpClient,
       max_request_size: Option<usize>,
       max_response_size: Option<usize>,
   }
   ```

4. **流式请求支持**
   - 当前仅支持流式响应
   - 考虑支持流式请求体（上传大文件）

5. **连接池配置暴露**
   ```rust
   impl ReqwestTransport {
       pub fn with_pool_config(...) -> Self
   }
   ```

6. **更详细的错误分类**
   ```rust
   pub enum TransportError {
       // ...
       DnsError(String),
       ConnectionRefused,
       TlsError(String),
       // ...
   }
   ```

### 性能考虑

1. **压缩性能**
   - 当前压缩在阻塞线程中执行（`zstd::stream::encode_all`）
   - 大请求体可能阻塞异步运行时
   - 建议：使用 `tokio::task::spawn_blocking`

2. **内存拷贝**
   - `serde_json::to_vec` 产生中间 buffer
   - Zstd 压缩再产生一个 buffer
   - 考虑使用 `bytes::BytesMut` 减少拷贝

### 测试建议

当前模块无单元测试，建议添加：
- 请求构建测试（各种头部组合）
- 压缩/解压正确性测试
- 错误映射测试
- 流式响应测试
- 超时测试
- 大请求体处理测试
