# default_client.rs 深度研究文档

## 场景与职责

`default_client.rs` 是 Codex HTTP 客户端的轻量级封装层，基于 `reqwest` 构建，添加了 OpenTelemetry 分布式追踪支持。该模块解决的核心问题是在微服务架构中跟踪请求链路：当 Codex 作为客户端调用后端服务时，需要将当前请求的追踪上下文（trace context）传播到下游服务，以便实现端到端的可观测性。

该模块的主要职责：
1. **HTTP 客户端封装**：提供 `CodexHttpClient` 包装 `reqwest::Client`，统一请求构建接口
2. **追踪上下文传播**：自动注入 OpenTelemetry traceparent 和 tracestate 头
3. **请求构建器模式**：提供流式 API 构建 HTTP 请求（`CodexRequestBuilder`）
4. **结构化日志记录**：记录请求方法、URL、状态码、响应头等信息

## 功能点目的

### 1. 追踪上下文自动传播
- 使用 OpenTelemetry 的 `TextMapPropagator` 将当前 span 的上下文注入请求头
- 支持 W3C Trace Context 标准（traceparent、tracestate）
- 无需调用方手动处理追踪头

### 2. 流式请求构建 API
- 提供 `get()`、`post()`、`request()` 等便捷方法开始构建请求
- 支持链式调用设置头、认证、超时、JSON 体等
- 保持底层 `reqwest::RequestBuilder` 的灵活性

### 3. 请求/响应日志记录
- 成功时记录方法、URL、状态码、响应头、HTTP 版本
- 失败时记录错误详情和状态码（如有）
- 使用 `tracing` crate 实现结构化日志

## 具体技术实现

### 关键数据结构

```rust
/// Codex HTTP 客户端包装器
#[derive(Clone, Debug)]
pub struct CodexHttpClient {
    inner: reqwest::Client,
}

/// 请求构建器（must_use 防止忘记发送）
#[must_use = "requests are not sent unless `send` is awaited"]
#[derive(Debug)]
pub struct CodexRequestBuilder {
    builder: reqwest::RequestBuilder,
    method: Method,
    url: String,
}

/// 请求头注入器（OpenTelemetry Injector trait 实现）
struct HeaderMapInjector<'a>(&'a mut HeaderMap);
```

### 核心流程

#### 1. 客户端创建与请求发起
```rust
impl CodexHttpClient {
    pub fn new(inner: reqwest::Client) -> Self;
    
    pub fn get<U: IntoUrl>(&self, url: U) -> CodexRequestBuilder;
    pub fn post<U: IntoUrl>(&self, url: U) -> CodexRequestBuilder;
    pub fn request<U: IntoUrl>(&self, method: Method, url: U) -> CodexRequestBuilder;
}
```

#### 2. 请求构建流程
```rust
impl CodexRequestBuilder {
    fn new(builder: reqwest::RequestBuilder, method: Method, url: String) -> Self;
    
    // 链式配置方法
    pub fn headers(self, headers: HeaderMap) -> Self;
    pub fn header<K, V>(self, key: K, value: V) -> Self;
    pub fn bearer_auth<T: Display>(self, token: T) -> Self;
    pub fn timeout(self, timeout: Duration) -> Self;
    pub fn json<T: Serialize>(self, value: &T) -> Self;
    pub fn body<B: Into<reqwest::Body>>(self, body: B) -> Self;
    
    // 内部辅助方法，用于链式调用
    fn map(self, f: impl FnOnce(reqwest::RequestBuilder) -> reqwest::RequestBuilder) -> Self;
}
```

#### 3. 追踪头注入流程 (`send` 方法)
```rust
pub async fn send(self) -> Result<Response, reqwest::Error> {
    // 1. 获取当前 span 的追踪上下文并注入头
    let headers = trace_headers();
    
    // 2. 发送请求（携带追踪头）
    match self.builder.headers(headers).send().await {
        Ok(response) => {
            tracing::debug!(...);  // 记录成功
            Ok(response)
        }
        Err(error) => {
            tracing::debug!(...);  // 记录失败
            Err(error)
        }
    }
}
```

#### 4. OpenTelemetry 上下文注入
```rust
fn trace_headers() -> HeaderMap {
    let mut headers = HeaderMap::new();
    global::get_text_map_propagator(|prop| {
        prop.inject_context(
            &Span::current().context(),  // 获取当前 span 的上下文
            &mut HeaderMapInjector(&mut headers),
        );
    });
    headers
}

// Injector trait 实现：将追踪数据写入 HeaderMap
impl<'a> Injector for HeaderMapInjector<'a> {
    fn set(&mut self, key: &str, value: String) {
        if let (Ok(name), Ok(val)) = (
            HeaderName::from_bytes(key.as_bytes()),
            HeaderValue::from_str(&value),
        ) {
            self.0.insert(name, val);
        }
    }
}
```

### 测试策略

模块包含单元测试验证追踪上下文传播：

```rust
#[test]
fn inject_trace_headers_uses_current_span_context() {
    // 1. 设置全局 propagator 为 W3C Trace Context
    global::set_text_map_propagator(TraceContextPropagator::new());
    
    // 2. 创建 tracer 和 subscriber
    let provider = SdkTracerProvider::builder().build();
    let tracer = provider.tracer("test-tracer");
    let subscriber = tracing_subscriber::registry()
        .with(tracing_opentelemetry::layer().with_tracer(tracer));
    
    // 3. 在 span 上下文中生成追踪头
    let span = trace_span!("client_request");
    let _entered = span.enter();
    let headers = trace_headers();
    
    // 4. 验证注入的头可被正确提取
    let extractor = HeaderMapExtractor(&headers);
    let extracted = TraceContextPropagator::new().extract(&extractor);
    // 断言：提取的 trace_id/span_id 与原始一致
}
```

## 关键代码路径与文件引用

### 本模块关键函数
| 函数/结构 | 行号 | 用途 |
|-----------|------|------|
| `CodexHttpClient::new` | 22-24 | 客户端包装器构造函数 |
| `CodexHttpClient::request` | 40-46 | 通用请求构建入口 |
| `CodexRequestBuilder::send` | 113-141 | 发送请求并注入追踪头 |
| `trace_headers` | 157-166 | 生成包含追踪上下文的头集合 |
| `HeaderMapInjector` | 144-155 | OpenTelemetry Injector 实现 |

### 相关文件
| 文件 | 关系 |
|------|------|
| `src/transport.rs` | 调用方：使用 `CodexHttpClient` 执行实际请求 |
| `../core/src/default_client.rs` | 调用方：构建带默认头的 reqwest 客户端 |
| `../codex-api/src/` | 调用方：各端点客户端使用此模块发起 API 调用 |

## 依赖与外部交互

### 外部 crate 依赖
| Crate | 用途 |
|-------|------|
| `reqwest` | 底层 HTTP 客户端 |
| `http` | HTTP 类型（HeaderMap、HeaderName、HeaderValue、Method） |
| `opentelemetry` | 分布式追踪 API（global propagator、Injector trait） |
| `tracing` | 结构化日志 |
| `tracing-opentelemetry` | 桥接 tracing 和 OpenTelemetry |
| `serde` | JSON 序列化 |

### OpenTelemetry 集成
- 使用全局 `TextMapPropagator`（通常为 `TraceContextPropagator`）
- 通过 `Span::current().context()` 获取当前追踪上下文
- 注入的头遵循 W3C Trace Context 标准：
  - `traceparent`: `00-<trace-id>-<span-id>-<flags>`
  - `tracestate`: 厂商特定的追踪状态

### 与 transport.rs 的交互
```rust
// transport.rs 使用示例
impl ReqwestTransport {
    fn build(&self, req: Request) -> Result<CodexRequestBuilder, TransportError> {
        let mut builder = self.client.request(Method::GET, &url);
        // ... 配置 builder ...
        Ok(builder)
    }
    
    async fn execute(&self, req: Request) -> Result<Response, TransportError> {
        let builder = self.build(req)?;
        let resp = builder.send().await.map_err(...)?;  // 自动携带追踪头
        // ...
    }
}
```

## 风险、边界与改进建议

### 已知风险

1. **Header 值解析失败静默忽略**
   - 现象：`HeaderMapInjector::set` 中解析失败时直接忽略
   - 影响：极端情况下追踪上下文可能丢失
   - 缓解：使用标准 W3C 格式，失败概率极低

2. **Must_use 属性依赖**
   - 现象：`CodexRequestBuilder` 标记 `#[must_use]` 但编译器警告可被禁用
   - 影响：开发者可能忘记调用 `.send()`

### 边界条件

| 场景 | 行为 |
|------|------|
| 无活跃 span | `Span::current()` 返回空 span，不注入追踪头 |
| 无效 header 值 | 解析失败时跳过该头，其他头正常注入 |
| 请求超时 | 返回 `reqwest::Error`，状态码为 None |
| 网络错误 | 返回 `reqwest::Error`，包含错误详情 |

### 改进建议

1. **重试机制集成**
   - 当前：无内置重试，依赖调用方处理
   - 建议：与 `crate::retry` 模块集成，在失败时自动重试
   - 注意：需考虑幂等性和追踪上下文保持

2. **指标收集**
   - 当前：仅有日志
   - 建议：添加请求延迟、成功率等指标导出

3. **请求/响应体日志**
   - 当前：仅记录方法和 URL
   - 建议：可选的详细日志模式（用于调试）
   - 风险：可能记录敏感信息，需谨慎设计

4. **连接池监控**
   - 建议：暴露连接池统计信息（空闲连接数、等待时间等）

5. **请求取消支持**
   - 当前：依赖 `reqwest` 的取消机制
   - 建议：显式支持 `CancellationToken` 集成

### 架构考虑

该模块设计为轻量级包装，职责单一：
- **优点**：简单、可预测、易于测试
- **限制**：高级功能（如重试、限流）需要调用方或上层模块实现

在 Codex 架构中，这些高级功能由 `transport.rs` 和 `retry.rs` 处理，形成清晰的分层：
```
application code
      ↓
codex-api (端点抽象)
      ↓
transport.rs (重试、压缩、错误处理)
      ↓
default_client.rs (追踪、日志)
      ↓
reqwest (底层 HTTP)
```
