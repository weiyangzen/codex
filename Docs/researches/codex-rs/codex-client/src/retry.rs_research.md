# retry.rs 研究文档

## 场景与职责

`retry.rs` 是 Codex HTTP 客户端的重试机制模块，提供可配置的重试策略和指数退避算法。该模块处理网络不稳定、服务端暂时不可用等场景下的自动重试逻辑。

核心职责：
- 定义重试策略配置（最大重试次数、基础延迟、重试条件）
- 实现指数退避算法（带抖动）
- 提供通用的重试执行框架
- 支持基于错误类型的条件重试

## 功能点目的

### 1. RetryPolicy 结构体
```rust
pub struct RetryPolicy {
    pub max_attempts: u64,      // 最大尝试次数（含首次）
    pub base_delay: Duration,   // 基础延迟时间
    pub retry_on: RetryOn,      // 重试条件配置
}
```
- **目的**：封装完整的重试策略配置
- **设计**：所有字段公开，便于灵活配置

### 2. RetryOn 结构体
```rust
pub struct RetryOn {
    pub retry_429: bool,        // 是否重试 429 Too Many Requests
    pub retry_5xx: bool,        // 是否重试 5xx 服务端错误
    pub retry_transport: bool,  // 是否重试网络/超时错误
}
```
- **目的**：细粒度控制哪些错误类型触发重试
- **决策逻辑**：`should_retry()` 方法根据错误类型和尝试次数决定是否重试

### 3. 指数退避算法
```rust
pub fn backoff(base: Duration, attempt: u64) -> Duration
```
- **公式**：`base * 2^(attempt-1) * jitter(0.9~1.1)`
- **抖动**：±10% 随机抖动避免 thundering herd
- **饱和处理**：使用 `saturating_pow` 和 `saturating_mul` 防止溢出

### 4. run_with_retry 函数
```rust
pub async fn run_with_retry<T, F, Fut>(
    policy: RetryPolicy,
    mut make_req: impl FnMut() -> Request,
    op: F,
) -> Result<T, TransportError>
```
- **目的**：通用重试执行框架
- **特点**：
  - 每次重试重新构造请求（支持请求刷新）
  - 异步执行，支持取消
  - 最后一次失败后返回原始错误

## 具体技术实现

### 指数退避计算流程
```
attempt=0: 返回 base（首次重试）
attempt>0: 
    exp = 2^(attempt-1)
    raw_delay = base.as_millis() * exp
    jitter = random(0.9..1.1)
    final_delay = raw_delay * jitter
```

### 重试决策流程
```
should_retry(error, attempt, max):
    if attempt >= max: return false
    match error:
        Http{status: 429} → retry_429
        Http{status: 5xx} → retry_5xx
        Timeout | Network → retry_transport
        _ → false
```

### 执行流程
```
for attempt in 0..=max_attempts:
    req = make_req()
    match op(req, attempt).await:
        Ok(resp) → return Ok(resp)
        Err(err) if should_retry(err) → sleep(backoff)
        Err(err) → return Err(err)
return Err(RetryLimit)
```

## 关键代码路径与文件引用

### 当前文件关键代码
- **行 8-13**：`RetryPolicy` 结构体定义
- **行 15-20**：`RetryOn` 结构体定义
- **行 22-36**：`RetryOn::should_retry()` 决策逻辑
- **行 38-47**：`backoff()` 指数退避实现
- **行 49-73**：`run_with_retry()` 核心重试逻辑

### 依赖模块
| 文件 | 依赖内容 |
|------|----------|
| `error.rs` | `TransportError` 错误类型 |
| `request.rs` | `Request` 请求类型 |

### 被调用方（使用者）
| 文件 | 使用场景 |
|------|----------|
| `codex-api/src/telemetry.rs` | `run_with_request_telemetry` 包装器 |
| `codex-api/src/endpoint/session.rs` | 端点请求重试 |

### 依赖的外部 crate
| crate | 用途 |
|-------|------|
| `rand` | 随机数生成（抖动计算） |
| `tokio` | `sleep` 异步延迟 |

## 依赖与外部交互

### 模块依赖图
```
retry.rs
    ↑
    ├── error.rs (TransportError)
    ├── request.rs (Request)
    └── codex-api/src/telemetry.rs (包装使用)
```

### 与 telemetry.rs 的交互
`codex-api/src/telemetry.rs` 提供了 `run_with_request_telemetry` 包装器：
```rust
pub(crate) async fn run_with_request_telemetry<T, F, Fut>(...)
```
- 包装 `run_with_retry` 添加每次尝试的遥测数据收集
- 记录尝试次数、状态码、错误、持续时间

### 与 endpoint session 的交互
各端点客户端通过 `EndpointSession` 使用重试功能：
- 配置 `RetryPolicy` 传递给 `run_with_retry`
- 在请求失败时自动触发重试逻辑

## 风险、边界与改进建议

### 潜在风险

1. **重试次数边界问题**
   ```rust
   for attempt in 0..=policy.max_attempts  // 行 58
   ```
   - 实际尝试次数 = max_attempts + 1（含首次）
   - 命名可能引起误解，建议文档明确说明

2. **退避时间溢出**
   ```rust
   let exp = 2u64.saturating_pow(attempt as u32 - 1);  // 行 42
   ```
   - `attempt` 为 `u64`，转换为 `u32` 可能在极端情况下截断
   - 实际场景中 `max_attempts` 通常很小（< 10），风险较低

3. **抖动范围固定**
   - 当前硬编码 0.9~1.1 的抖动范围
   - 某些场景可能需要更大或更小的抖动

4. **没有最大退避限制**
   - 退避时间可能无限增长
   - 建议添加 `max_delay` 上限

### 边界情况

1. **max_attempts = 0**
   - 仅执行一次，不重试
   - 逻辑正确

2. **base_delay = 0**
   - 退避时间为 0，立即重试
   - 可能导致密集重试，建议设置最小延迟

3. **所有重试条件为 false**
   - 任何错误都不触发重试
   - 逻辑正确，但配置可能不合理

4. **请求构造失败**
   - `make_req` 闭包 panic 会传播
   - 建议在调用方处理

### 改进建议

1. **添加最大退避限制**
   ```rust
   pub struct RetryPolicy {
       pub max_attempts: u64,
       pub base_delay: Duration,
       pub max_delay: Option<Duration>,  // 新增
       pub retry_on: RetryOn,
   }
   ```

2. **可配置的抖动范围**
   ```rust
   pub struct RetryPolicy {
       // ...
       pub jitter_factor: f64,  // 0.0 ~ 1.0，表示抖动幅度
   }
   ```

3. **添加重试钩子**
   ```rust
   pub async fn run_with_retry<T, F, Fut, OnRetry>(
       policy: RetryPolicy,
       make_req: impl FnMut() -> Request,
       op: F,
       on_retry: Option<OnRetry>,  // 重试回调
   ) -> Result<T, TransportError>
   ```

4. **更清晰的命名**
   - `max_attempts` → `max_retries`（明确是重试次数而非总次数）
   - 或添加文档说明：`max_attempts` 包含首次请求

5. **添加重试计数指标**
   - 返回实际重试次数，便于监控和调试

### 测试建议

当前模块无单元测试，建议添加：
- 各种错误类型的重试决策测试
- 退避时间计算测试（验证指数增长和抖动）
- 边界条件测试（max_attempts=0, base_delay=0）
- 并发安全性测试
