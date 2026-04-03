# session.rs 研究文档

## 场景与职责

`session.rs` 是 `codex-api` 端点模块的**内部核心基础设施**，为所有端点客户端提供统一的 HTTP 请求执行能力。它是连接高层业务逻辑（各种端点客户端）和底层 HTTP 传输层的桥梁。

该模块提供了 `EndpointSession` 结构体，封装了：
- 请求构建和认证头添加
- 重试策略执行
- 请求遥测收集
- 流式和非流式请求的统一处理

## 功能点目的

1. **请求统一处理**：为所有端点提供一致的请求执行接口
2. **认证集成**：自动添加认证头到请求
3. **重试机制**：集成 `codex_client` 的重试策略
4. **遥测支持**：收集请求性能和错误遥测
5. **配置管理**：管理 provider 配置和传输层

## 具体技术实现

### 核心数据结构

```rust
pub(crate) struct EndpointSession<T: HttpTransport, A: AuthProvider> {
    transport: T,
    provider: Provider,
    auth: A,
    request_telemetry: Option<Arc<dyn RequestTelemetry>>,
}
```

- **泛型设计**: `T: HttpTransport` 支持不同传输实现，`A: AuthProvider` 支持不同认证方式
- **内部可见性**: `pub(crate)` 限制仅在 crate 内使用
- **可选遥测**: 通过 `Option<Arc<dyn RequestTelemetry>>` 支持可选的遥测收集

### 关键流程

#### 1. 会话创建与配置
```rust
pub(crate) fn new(transport: T, provider: Provider, auth: A) -> Self

pub(crate) fn with_request_telemetry(
    mut self,
    request: Option<Arc<dyn RequestTelemetry>>,
) -> Self

pub(crate) fn provider(&self) -> &Provider
```

#### 2. 请求构建
```rust
fn make_request(
    &self,
    method: &Method,
    path: &str,
    extra_headers: &HeaderMap,
    body: Option<&Value>,
) -> Request
```

构建流程：
1. 使用 `provider.build_request` 创建基础请求
2. 添加额外头部
3. 设置请求体
4. 添加认证头

#### 3. 执行请求（非流式）
```rust
pub(crate) async fn execute(
    &self,
    method: Method,
    path: &str,
    extra_headers: HeaderMap,
    body: Option<Value>,
) -> Result<Response, ApiError>
```

#### 4. 执行请求（带配置）
```rust
pub(crate) async fn execute_with<C>(
    &self,
    method: Method,
    path: &str,
    extra_headers: HeaderMap,
    body: Option<Value>,
    configure: C,
) -> Result<Response, ApiError>
where
    C: Fn(&mut Request),
```

- 支持通过闭包自定义请求配置
- 使用 `run_with_request_telemetry` 执行带遥测的重试逻辑

#### 5. 执行流式请求
```rust
pub(crate) async fn stream_with<C>(
    &self,
    method: Method,
    path: &str,
    extra_headers: HeaderMap,
    body: Option<Value>,
    configure: C,
) -> Result<StreamResponse, ApiError>
where
    C: Fn(&mut Request),
```

- 与 `execute_with` 类似，但返回 `StreamResponse` 用于 SSE

### 遥测集成

```rust
let response = run_with_request_telemetry(
    self.provider.retry.to_policy(),
    self.request_telemetry.clone(),
    make_request,
    |req| self.transport.execute(req),
)
.await?;
```

`run_with_request_telemetry` 函数（定义在 `crate::telemetry`）：
1. 包装 `run_with_retry` 添加遥测
2. 每次请求尝试记录：状态码、错误、耗时
3. 通过 `RequestTelemetry` trait 回调

### 重试策略

```rust
// 在 Provider 中定义
pub struct RetryConfig {
    pub max_attempts: u64,
    pub base_delay: Duration,
    pub retry_429: bool,
    pub retry_5xx: bool,
    pub retry_transport: bool,
}

impl RetryConfig {
    pub fn to_policy(&self) -> RetryPolicy { ... }
}
```

转换为 `codex_client::RetryPolicy` 后由 `run_with_retry` 执行。

### 追踪注解

```rust
#[instrument(
    name = "endpoint_session.execute_with",
    level = "info",
    skip_all,
    fields(http.method = %method, api.path = path)
)]
```

- 使用 `tracing` 提供结构化日志
- 记录 HTTP 方法和 API 路径

## 关键代码路径与文件引用

### 内部依赖

| 文件 | 用途 |
|------|------|
| `crate::auth::{AuthProvider, add_auth_headers}` | 认证 |
| `crate::error::ApiError` | 错误类型 |
| `crate::provider::Provider` | 端点配置 |
| `crate::telemetry::run_with_request_telemetry` | 遥测执行 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `codex_client::{HttpTransport, Request, Response, StreamResponse, RequestTelemetry}` | HTTP 传输和遥测 |
| `http::{HeaderMap, Method}` | HTTP 类型 |
| `serde_json::Value` | JSON 请求体 |
| `tracing::instrument` | 追踪注解 |

### 调用关系

```
EndpointSession::execute
  └─> EndpointSession::execute_with (configure = |_| {})

EndpointSession::execute_with
  ├─> make_request
  │   ├─> provider.build_request
  │   ├─> add extra_headers
  │   ├─> set body
  │   └─> add_auth_headers
  ├─> configure(req)  // 自定义配置
  └─> run_with_request_telemetry
      ├─> provider.retry.to_policy()
      ├─> make_request
      └─> transport.execute / transport.stream
```

### 使用者

所有端点客户端都通过 `EndpointSession` 执行请求：

| 端点 | 使用方法 |
|------|----------|
| `compact.rs` | `session.execute(Method::POST, Self::path(), ...)` |
| `memories.rs` | `session.execute(Method::POST, Self::path(), ...)` |
| `models.rs` | `session.execute_with(Method::GET, Self::path(), ..., append_client_version_query)` |
| `responses.rs` | `session.stream_with(Method::POST, Self::path(), ...)` |

## 依赖与外部交互

### 认证流程

```rust
// auth.rs
pub(crate) fn add_auth_headers<A: AuthProvider>(auth: &A, mut req: Request) -> Request {
    add_auth_headers_to_header_map(auth, &mut req.headers);
    req
}

pub(crate) fn add_auth_headers_to_header_map<A: AuthProvider>(auth: &A, headers: &mut HeaderMap) {
    if let Some(token) = auth.bearer_token() {
        headers.insert(http::header::AUTHORIZATION, format!("Bearer {token}").parse().unwrap());
    }
    if let Some(account_id) = auth.account_id() {
        headers.insert("ChatGPT-Account-ID", account_id.parse().unwrap());
    }
}
```

### Provider 请求构建

```rust
// provider.rs
impl Provider {
    pub fn build_request(&self, method: Method, path: &str) -> Request {
        Request {
            method,
            url: self.url_for_path(path),
            headers: self.headers.clone(),
            body: None,
            compression: RequestCompression::None,
            timeout: None,
        }
    }
}
```

### 遥测回调

```rust
// telemetry.rs
pub(crate) async fn run_with_request_telemetry<T, F, Fut>(
    policy: RetryPolicy,
    telemetry: Option<Arc<dyn RequestTelemetry>>,
    make_request: impl FnMut() -> Request,
    send: F,
) -> Result<T, TransportError>
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
            if let Some(t) = telemetry.as_ref() {
                let (status, err) = match &result {
                    Ok(resp) => (Some(resp.status()), None),
                    Err(err) => (http_status(err), Some(err)),
                };
                t.on_request(attempt, status, err, start.elapsed());
            }
            result
        }
    })
    .await
}
```

## 风险、边界与改进建议

### 风险点

1. **认证头泄露**: 如果日志记录请求详情，可能泄露敏感头信息
2. **重试风暴**: 配置不当的重试策略可能导致重试风暴
3. **资源泄漏**: 流式请求的资源清理依赖调用者正确消费
4. **遥测阻塞**: 遥测回调如果阻塞会影响请求性能

### 边界条件

1. **空请求体**: 正确处理 `body: None` 的情况
2. **超大请求体**: 没有请求体大小限制
3. **并发限制**: 没有内置的并发请求限制
4. **超时控制**: 超时配置依赖 `Provider`，但执行时可能不生效

### 测试覆盖

当前模块**缺少单元测试**，建议添加：

1. **请求构建测试**: 验证 `make_request` 正确组合各部分
2. **认证头测试**: 验证认证头正确添加
3. **重试测试**: 验证重试策略正确应用
4. **遥测测试**: 验证遥测回调正确触发

### 改进建议

1. **添加单元测试**: 当前模块无测试，需要补充

2. **请求大小限制**: 添加请求体大小检查

   ```rust
   const MAX_BODY_SIZE: usize = 50 * 1024 * 1024; // 50MB
   ```

3. **请求验证**: 在发送前验证请求有效性

4. **连接池管理**: 考虑在会话层管理连接池

5. **断路器模式**: 添加断路器防止级联故障

6. **请求 ID**: 自动生成请求 ID 用于追踪

   ```rust
   req.headers.insert("x-request-id", generate_request_id());
   ```

7. **超时细化**: 支持连接超时、读取超时、总超时分离

8. **指标暴露**: 暴露请求计数、延迟、错误率等指标

9. **日志脱敏**: 确保日志中不输出敏感头信息

   ```rust
   fn sanitize_headers(headers: &HeaderMap) -> HeaderMap { ... }
   ```

### 代码质量评估

- **优点**:
  - 职责清晰，作为底层基础设施
  - 泛型设计灵活，支持多种传输和认证
  - 使用 `tracing` 提供结构化日志
  - 错误处理使用 `?` 操作符，简洁明了
  - 内部可见性控制得当

- **可改进**:
  - 缺少单元测试
  - 缺少请求验证和大小限制
  - 可考虑添加 Builder 模式简化复杂请求构建
  - 可考虑添加请求拦截器/中间件机制

### 设计模式

1. **门面模式**: `EndpointSession` 为复杂的 HTTP 执行流程提供简化接口
2. **策略模式**: 通过泛型参数支持不同的传输和认证策略
3. **装饰器模式**: `with_request_telemetry` 方法添加遥测功能而不改变接口

### 关键常量

```rust
// 来自 http crate
const AUTHORIZATION: HeaderName = HeaderName::from_static("authorization");

// 来自 auth.rs
const CHATGPT_ACCOUNT_ID: &str = "ChatGPT-Account-ID";
```
