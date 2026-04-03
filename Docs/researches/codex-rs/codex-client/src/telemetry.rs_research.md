# telemetry.rs 研究文档

## 场景与职责

`telemetry.rs` 是 Codex HTTP 客户端的遥测接口模块，定义了请求级别的遥测数据收集 trait。该模块为上层应用提供钩子，用于监控 HTTP 请求的尝试次数、状态码、错误和持续时间。

核心职责：
- 定义 `RequestTelemetry` trait，规范遥测数据接口
- 支持每次请求尝试的细粒度监控
- 与重试机制集成，记录每次重试的详细信息

## 功能点目的

### 1. RequestTelemetry Trait
```rust
pub trait RequestTelemetry: Send + Sync {
    fn on_request(
        &self,
        attempt: u64,                    // 尝试次数（从0开始）
        status: Option<StatusCode>,      // HTTP 状态码（成功时）
        error: Option<&TransportError>,  // 错误信息（失败时）
        duration: Duration,              // 请求持续时间
    );
}
```

- **目的**：为 HTTP 请求提供统一的遥测数据收集接口
- **设计特点**：
  - `Send + Sync`：支持多线程共享
  - `&self`：允许多次调用（记录多次重试）
  - `Option<StatusCode>` 和 `Option<&TransportError>`：互斥存在，表示成功或失败

## 具体技术实现

### Trait 设计分析

| 参数 | 类型 | 含义 |
|------|------|------|
| `attempt` | `u64` | 尝试次数，0 表示首次请求，>0 表示重试 |
| `status` | `Option<StatusCode>` | HTTP 状态码，成功时存在 |
| `error` | `Option<&TransportError>` | 错误引用，失败时存在 |
| `duration` | `Duration` | 请求耗时 |

### 使用模式

该 trait 通常与 `Arc<dyn RequestTelemetry>` 一起使用：
```rust
// 来自 codex-api/src/telemetry.rs
pub(crate) async fn run_with_request_telemetry<T, F, Fut>(
    policy: RetryPolicy,
    telemetry: Option<Arc<dyn RequestTelemetry>>,  // 动态分发
    make_request: impl FnMut() -> Request,
    send: F,
) -> Result<T, TransportError>
```

## 关键代码路径与文件引用

### 当前文件关键代码
- **行 5-14**：`RequestTelemetry` trait 定义

### 被调用方（使用者）

| 文件 | 使用方式 |
|------|----------|
| `codex-api/src/telemetry.rs` | 实现 `run_with_request_telemetry` 包装器 |
| `codex-api/src/endpoint/session.rs` | 存储 `Option<Arc<dyn RequestTelemetry>>` |
| `codex-api/src/endpoint/models.rs` | 客户端配置遥测 |
| `codex-api/src/endpoint/memories.rs` | 客户端配置遥测 |
| `codex-api/src/endpoint/compact.rs` | 客户端配置遥测 |
| `codex-api/src/endpoint/responses.rs` | 客户端配置遥测 |

### 依赖的外部 crate
| crate | 用途 |
|-------|------|
| `http` | `StatusCode` 类型 |

### 模块依赖图
```
telemetry.rs
    ↑
    ├── error.rs (TransportError)
    └── codex-api/src/telemetry.rs (主要实现者)
        └── 各端点客户端
```

## 依赖与外部交互

### 与 codex-api 的集成

`codex-api/src/telemetry.rs` 提供了具体的集成实现：

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

**关键点**：
- 包装 `run_with_retry` 添加遥测
- 每次尝试（包括重试）都调用 `on_request`
- 使用 `Instant::now()` 和 `elapsed()` 精确计时

### 端点客户端集成

各端点客户端（如 `ResponsesClient`、`ModelsClient`）支持通过 `with_telemetry` 方法配置遥测：

```rust
// 来自 codex-api/src/endpoint/responses.rs
pub fn with_telemetry(
    self,
    request: Option<Arc<dyn RequestTelemetry>>,
    sse: Option<Arc<dyn SseTelemetry>>,
) -> Self {
    Self {
        session: self.session.with_request_telemetry(request),
        sse_telemetry: sse,
    }
}
```

## 风险、边界与改进建议

### 潜在风险

1. **Trait 方法无返回值**
   - `on_request` 返回 `()`，无法感知遥测处理失败
   - 遥测实现 panic 可能影响主流程
   - 建议：文档要求实现者内部处理错误，不 panic

2. **错误类型借用**
   ```rust
   error: Option<&TransportError>
   ```
   - 仅借用错误引用，实现者需要立即克隆或处理
   - 不能存储引用供后续使用

3. **无上下文信息**
   - 缺少请求 URL、方法等信息
   - 仅知道 attempt 次数，无法区分不同请求

### 边界情况

1. **telemetry = None**
   - 调用方可以选择不配置遥测
   - 逻辑正确，无性能开销

2. **attempt = 0 但立即失败**
   - 首次请求失败，status = None, error = Some(...)
   - 逻辑正确

3. **多次重试后成功**
   - attempt = 0, 1, 2, ... 直到成功
   - 每次都有独立的 duration

### 改进建议

1. **添加请求标识信息**
   ```rust
   fn on_request(
       &self,
       request_id: &str,  // 新增：请求唯一标识
       method: &Method,   // 新增：HTTP 方法
       url: &str,         // 新增：请求 URL
       attempt: u64,
       status: Option<StatusCode>,
       error: Option<&TransportError>,
       duration: Duration,
   );
   ```

2. **添加返回值处理遥测错误**
   ```rust
   fn on_request(...) -> Result<(), TelemetryError>;
   ```
   或添加 `on_request_result` 回调

3. **考虑使用事件结构体**
   ```rust
   pub struct RequestEvent {
       pub attempt: u64,
       pub status: Option<StatusCode>,
       pub error: Option<TransportError>,  // 拥有所有权
       pub duration: Duration,
   }
   
   fn on_request(&self, event: RequestEvent);
   ```

4. **添加 span/context 支持**
   ```rust
   fn on_request(
       &self,
       attempt: u64,
       status: Option<StatusCode>,
       error: Option<&TransportError>,
       duration: Duration,
       context: &tracing::Span,  // 新增：追踪上下文
   );
   ```

### 扩展性分析

当前 trait 设计简洁，但可能不足以支持高级遥测需求：

| 需求 | 当前支持 | 建议 |
|------|----------|------|
| 请求/响应体大小 | ❌ | 添加参数或扩展 trait |
| 重试原因 | ❌ | 添加 `retry_reason: Option<&str>` |
| 自定义标签 | ❌ | 添加 `labels: HashMap<String, String>` |
| 批量上报 | ❌ | 添加 `flush()` 方法 |

### 测试建议

当前模块无测试（仅 trait 定义），建议在使用方添加：
- 模拟 `RequestTelemetry` 实现验证调用次数
- 验证重试场景下的多次调用
- 验证成功/失败状态的正确传递
