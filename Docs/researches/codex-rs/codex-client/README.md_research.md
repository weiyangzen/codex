# codex-rs/codex-client/README.md 研究文档

## 场景与职责

`codex-client` 是 Codex 项目的**通用 HTTP 传输层** crate。它封装了 HTTP 请求、重试、流式传输等底层网络能力，同时保持与 Codex/OpenAI 特定 API 的无关性。这种设计允许上层 crate（如 `codex-api`）专注于业务逻辑，而无需关心网络传输细节。

## 功能点目的

README 中明确阐述了四个核心功能模块：

### 1. HTTP 传输抽象 (`HttpTransport` / `ReqwestTransport`)
```rust
// 定义在 src/transport.rs
#[async_trait]
pub trait HttpTransport: Send + Sync {
    async fn execute(&self, req: Request) -> Result<Response, TransportError>;
    async fn stream(&self, req: Request) -> Result<StreamResponse, TransportError>;
}
```
- **目的**：解耦具体 HTTP 客户端实现（reqwest）与业务代码
- **价值**：便于测试 mock、未来更换底层客户端、统一错误处理

### 2. 请求/响应类型 (`Request` / `Response`)
```rust
// 定义在 src/request.rs
pub struct Request {
    pub method: Method,
    pub url: String,
    pub headers: HeaderMap,
    pub body: Option<Value>,
    pub compression: RequestCompression,  // None | Zstd
    pub timeout: Option<Duration>,
}
```
- **目的**：提供中立的请求构建 API
- **特色**：内置 zstd 压缩支持、JSON 序列化助手

### 3. 重试机制 (`RetryPolicy`, `RetryOn`, `run_with_retry`, `backoff`)
```rust
// 定义在 src/retry.rs
pub struct RetryPolicy {
    pub max_attempts: u64,
    pub base_delay: Duration,
    pub retry_on: RetryOn,  // 配置 429/5xx/transport 错误重试
}

pub fn backoff(base: Duration, attempt: u64) -> Duration {
    // 指数退避 + 随机抖动 (0.9~1.1)
}
```
- **目的**：为 unary 和 streaming 调用提供弹性重试能力
- **算法**：指数退避 + jitter，避免 thundering herd

### 4. SSE 流处理 (`sse_stream`)
```rust
// 定义在 src/sse.rs
pub fn sse_stream(
    stream: ByteStream,
    idle_timeout: Duration,
    tx: mpsc::Sender<Result<String, StreamError>>,
)
```
- **目的**：将原始字节流转换为 SSE `data:` 帧
- **特性**：空闲超时检测、流错误透传、异步通道输出

## 具体技术实现

### 架构分层

```
┌─────────────────────────────────────────────────────────────┐
│  上层 crate (codex-api / codex-core / tui / ...)           │
│  - OpenAI API 特定逻辑                                      │
│  - 业务错误处理                                             │
└───────────────────────┬─────────────────────────────────────┘
                        │ 使用 HttpTransport trait
┌───────────────────────▼─────────────────────────────────────┐
│  codex-client (本 crate)                                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │  transport  │  │   retry     │  │        sse          │ │
│  │ ReqwestTransport │ run_with_retry │ sse_stream       │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │   request   │  │   error     │  │     custom_ca       │ │
│  │ Request/Resp│  │TransportErr │  │ 自定义 CA 证书处理   │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
└───────────────────────┬─────────────────────────────────────┘
                        │ 依赖
┌───────────────────────▼─────────────────────────────────────┐
│  外部 crate                                                 │
│  reqwest / tokio / rustls / zstd / eventsource-stream      │
└─────────────────────────────────────────────────────────────┘
```

### 关键实现细节

#### 1. 压缩实现 (src/transport.rs:64-103)
```rust
if compression != RequestCompression::None {
    // 1. JSON 序列化
    let json = serde_json::to_vec(&body)?;
    let pre_compression_bytes = json.len();
    
    // 2. zstd 压缩（级别 3）
    let (compressed, content_encoding) = zstd::stream::encode_all(..., 3)?;
    
    // 3. 记录压缩指标
    tracing::info!(
        pre_compression_bytes,
        post_compression_bytes,
        compression_duration_ms = ...,
        "Compressed request body with zstd"
    );
    
    // 4. 设置 Content-Encoding 头
    headers.insert(http::header::CONTENT_ENCODING, content_encoding);
}
```

#### 2. 追踪头自动注入 (src/default_client.rs:157-166)
```rust
fn trace_headers() -> HeaderMap {
    let mut headers = HeaderMap::new();
    global::get_text_map_propagator(|prop| {
        prop.inject_context(
            &Span::current().context(),
            &mut HeaderMapInjector(&mut headers),
        );
    });
    headers
}
```
每个请求自动注入 OpenTelemetry 追踪上下文，实现分布式追踪。

#### 3. 自定义 CA 证书处理 (src/custom_ca.rs)
这是一个 788 行的核心模块，处理企业代理场景：
- 环境变量优先级：`CODEX_CA_CERTIFICATE` > `SSL_CERT_FILE`
- PEM 格式兼容：标准 CERTIFICATE + OpenSSL TRUSTED CERTIFICATE
- CRL 忽略：自动跳过证书吊销列表
- DER 解析：处理 X509_AUX 尾随数据

#### 4. 指数退避算法 (src/retry.rs:38-47)
```rust
pub fn backoff(base: Duration, attempt: u64) -> Duration {
    if attempt == 0 {
        return base;
    }
    let exp = 2u64.saturating_pow(attempt as u32 - 1);
    let millis = base.as_millis() as u64;
    let raw = millis.saturating_mul(exp);
    let jitter: f64 = rand::rng().random_range(0.9..1.1);
    Duration::from_millis((raw as f64 * jitter) as u64)
}
```

## 关键代码路径与文件引用

### 公共 API 导出 (src/lib.rs)
```rust
pub use crate::transport::{ByteStream, HttpTransport, ReqwestTransport, StreamResponse};
pub use crate::request::{Request, RequestCompression, Response};
pub use crate::retry::{RetryOn, RetryPolicy, backoff, run_with_retry};
pub use crate::sse::sse_stream;
pub use crate::error::{StreamError, TransportError};
pub use crate::custom_ca::{build_reqwest_client_with_custom_ca, ...};
pub use crate::default_client::{CodexHttpClient, CodexRequestBuilder};
pub use crate::telemetry::RequestTelemetry;
```

### 文件清单与职责

| 文件 | 行数 | 职责 |
|------|------|------|
| `src/lib.rs` | 36 | 模块聚合与公共 API 导出 |
| `src/transport.rs` | 189 | HttpTransport trait + ReqwestTransport 实现 |
| `src/custom_ca.rs` | 788 | 自定义 CA 证书处理（最复杂模块） |
| `src/default_client.rs` | 218 | CodexHttpClient + 追踪头注入 + 单元测试 |
| `src/retry.rs` | 73 | 重试策略与退避算法 |
| `src/request.rs` | 53 | Request/Response 类型定义 |
| `src/sse.rs` | 48 | SSE 流处理助手 |
| `src/error.rs` | 30 | 错误类型定义 |
| `src/telemetry.rs` | 14 | RequestTelemetry trait |
| `src/bin/custom_ca_probe.rs` | 29 | CA 测试辅助二进制 |
| `tests/ca_env.rs` | 145 | 子进程 CA 集成测试 |

## 依赖与外部交互

### 被调用方（上层 crate 使用方式）

#### codex-api 中的使用示例
```rust
// 构建带重试的请求
let policy = RetryPolicy {
    max_attempts: 3,
    base_delay: Duration::from_millis(100),
    retry_on: RetryOn {
        retry_429: true,
        retry_5xx: true,
        retry_transport: true,
    },
};

run_with_retry(policy, || request.clone(), |req, _| async {
    transport.execute(req).await
}).await
```

#### TUI 中的 SSE 使用
```rust
let (tx, mut rx) = mpsc::channel(100);
sse_stream(byte_stream, idle_timeout, tx);

while let Some(event) = rx.recv().await {
    match event {
        Ok(data) => println!("SSE data: {}", data),
        Err(StreamError::Timeout) => break,
        Err(e) => return Err(e.into()),
    }
}
```

### 外部系统交互

```
┌─────────────────────────────────────────────────────────────┐
│                     codex-client                            │
├─────────────────────────────────────────────────────────────┤
│  环境变量                                                    │
│  - CODEX_CA_CERTIFICATE: 自定义 CA 证书路径                  │
│  - SSL_CERT_FILE: 备用 CA 证书路径                           │
├─────────────────────────────────────────────────────────────┤
│  系统资源                                                    │
│  - 系统根证书存储（via rustls-native-certs）                 │
│  - 文件系统（读取 CA PEM 文件）                              │
├─────────────────────────────────────────────────────────────┤
│  网络交互                                                    │
│  - HTTPS 服务器（OpenAI API / Backend API）                  │
│  - 企业代理（通过自定义 CA 支持）                            │
└─────────────────────────────────────────────────────────────┘
```

## 风险、边界与改进建议

### 风险点

1. **设计约束：API 无关性**
   - README 强调 "without any Codex/OpenAI awareness"
   - 风险：如果设计边界模糊，可能导致业务逻辑泄漏到传输层
   - 缓解：当前实现严格遵守，错误类型也是通用的 `TransportError`

2. **SSE 空闲超时**
   - `sse_stream` 的空闲超时是硬终止，不会尝试重连
   - 风险：长连接场景下可能过于激进
   - 现状：由调用方配置 `idle_timeout`，给予上层控制权

3. **压缩与 content-encoding 冲突**
   ```rust
   if headers.contains_key(http::header::CONTENT_ENCODING) {
       return Err(TransportError::Build(
           "request compression was requested but content-encoding is already set"
               .to_string(),
       ));
   }
   ```
   - 这种保守策略防止了重复编码，但可能让调用者困惑

4. **子进程测试复杂度**
   - `custom_ca_probe` 二进制专门用于测试 CA 处理
   - 原因：macOS seatbelt 环境下 reqwest 代理发现会 panic
   - 风险：测试架构复杂，需要维护额外的二进制目标

### 边界情况

| 场景 | 当前行为 |
|------|----------|
| 空 CA 文件 | `InvalidCaFile` 错误，提示 "no certificates found" |
| 损坏的 PEM | 带行号的详细解析错误 |
| TRUSTED CERTIFICATE 格式 | 自动标准化为普通 CERTIFICATE |
| 包含 CRL 的 bundle | 自动忽略 CRL 条目，记录 info 日志 |
| 多个 CA 证书 | 全部加载到根证书存储 |
| 重试次数耗尽 | `TransportError::RetryLimit` |

### 改进建议

1. **SSE 重连支持**
   当前 `sse_stream` 在超时或错误时直接结束。考虑添加可选的重连机制：
   ```rust
   pub fn sse_stream_with_retry(
       stream_factory: impl Fn() -> ByteStream,
       idle_timeout: Duration,
       max_reconnects: u32,
       tx: mpsc::Sender<Result<String, StreamError>>,
   )
   ```

2. **压缩算法扩展**
   当前仅支持 zstd。考虑添加 brotli/gzip 支持：
   ```rust
   pub enum RequestCompression {
       None,
       Zstd(u32),  // 压缩级别
       Brotli(u32),
       Gzip,
   }
   ```

3. **请求拦截器/中间件**
   当前 `HttpTransport` 是 trait，但缺乏中间件机制。考虑：
   ```rust
   pub trait RequestInterceptor {
       async fn intercept(&self, req: &mut Request) -> Result<(), TransportError>;
   }
   ```

4. **指标暴露**
   当前压缩指标通过 tracing 记录。考虑通过 `RequestTelemetry` trait 暴露：
   ```rust
   fn on_compression(&self, pre_bytes: usize, post_bytes: usize, duration: Duration);
   ```

5. **文档改进**
   - README 可以添加使用示例代码
   - 添加架构图说明模块关系
   - 说明何时使用 `execute` vs `stream`

6. **测试覆盖**
   - `custom_ca.rs` 有 105 行测试代码（约 13%），但主要是单元测试
   - 建议添加与真实代理服务器的集成测试（可能需要在 CI 中配置）
