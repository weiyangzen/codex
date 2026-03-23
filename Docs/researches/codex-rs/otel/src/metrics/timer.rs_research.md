# timer.rs 深度研究文档

## 场景与职责

`timer.rs` 实现了 Codex 指标系统的自动计时器功能。它是指标系统的辅助工具，负责：

1. **自动计时**：使用 RAII 模式，在创建时开始计时，在销毁时自动记录耗时
2. **标签支持**：支持基础标签和额外标签的合并
3. **错误处理**：记录失败时记录错误日志但不 panic
4. **与 MetricsClient 集成**：作为 `MetricsClient` 的配套工具

该模块被 `SessionTelemetry` 和直接使用 `MetricsClient` 的代码使用，简化耗时指标的记录。

## 功能点目的

### 1. Timer 结构体

```rust
#[derive(Debug)]
pub struct Timer {
    name: String,                    // 指标名称
    tags: Vec<(String, String)>,     // 基础标签（拥有所有权）
    client: MetricsClient,           // 指标客户端克隆
    start_time: Instant,             // 开始时间
}
```

### 2. Drop  trait 实现

```rust
impl Drop for Timer {
    fn drop(&mut self) {
        if let Err(e) = self.record(&[]) {
            tracing::error!("metrics client error: {}", e);
        }
    }
}
```

- 利用 Rust 的 RAII 机制，确保计时器被销毁时自动记录
- 即使发生 panic，Drop 仍会被调用
- 错误仅记录日志，不中断程序流程

### 3. 额外标签支持

```rust
pub fn record(&self, additional_tags: &[(&str, &str)]) -> Result<()> {
    // 合并额外标签和基础标签
    let mut tags = Vec::with_capacity(self.tags.len() + additional_tags.len());
    tags.extend(additional_tags);
    tags.extend(self.tags.iter().map(|(k, v)| (k.as_str(), v.as_str())));
    // 记录持续时间
    self.client.record_duration(&self.name, self.start_time.elapsed(), &tags)
}
```

允许在记录时动态添加额外标签，而无需重新创建 Timer。

## 具体技术实现

### 创建流程

```rust
impl Timer {
    pub(crate) fn new(name: &str, tags: &[(&str, &str)], client: &MetricsClient) -> Self {
        Self {
            name: name.to_string(),
            // 克隆标签（需要所有权用于 Drop）
            tags: tags.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect(),
            // 克隆 MetricsClient（内部是 Arc，成本低）
            client: client.clone(),
            start_time: Instant::now(),  // 记录开始时间
        }
    }
}
```

### 使用模式

#### 模式 1：自动记录（RAII）

```rust
{
    let timer = metrics.start_timer("codex.operation.duration_ms", &[("op", "parse")])?;
    // ... 执行操作
} // 自动调用 drop，记录耗时
```

#### 模式 2：手动记录

```rust
let timer = metrics.start_timer("codex.operation.duration_ms", &[("op", "parse")])?;
// ... 执行操作
timer.record(&[("status", "success")])?;  // 手动记录，可添加额外标签
// 注意：之后 drop 还会再记录一次！
```

#### 模式 3：条件记录

```rust
let timer = metrics.start_timer("codex.operation.duration_ms", &[])?;
let result = perform_operation();
// 根据结果添加不同标签
timer.record(&[("success", if result.is_ok() { "true" } else { "false" })])?;
mem::forget(timer);  // 防止 Drop 再次记录
```

### 标签合并策略

```rust
pub fn record(&self, additional_tags: &[(&str, &str)]) -> Result<()> {
    // 额外标签在前，基础标签在后
    let mut tags = Vec::with_capacity(self.tags.len() + additional_tags.len());
    tags.extend(additional_tags);  // 额外标签优先
    tags.extend(self.tags.iter().map(|(k, v)| (k.as_str(), v.as_str())));
    self.client.record_duration(&self.name, self.start_time.elapsed(), &tags)
}
```

- 额外标签在前，基础标签在后
- 如果有重复 key，后出现的值生效（基础标签覆盖额外标签）
- 实际使用时通常不会有重复 key

## 关键代码路径与文件引用

### 内部依赖

| 文件 | 用途 |
|------|------|
| `client.rs` | `MetricsClient`, `record_duration()` |
| `error.rs` | `Result` 类型 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `std::time::Instant` | 计时 |
| `tracing::error` | 错误日志 |

### 调用方

| 文件 | 使用场景 |
|------|----------|
| `client.rs` | `start_timer()` 方法创建 Timer |
| `events/session_telemetry.rs` | `start_timer()` 包装 |
| `lib.rs` | `start_global_timer()` 函数 |

### 公共接口

```rust
// client.rs
pub fn start_timer(&self, name: &str, tags: &[(&str, &str)]) -> Result<Timer> {
    Ok(Timer::new(name, tags, self))
}

// lib.rs
pub fn start_global_timer(name: &str, tags: &[(&str, &str)]) -> MetricsResult<Timer> {
    let Some(metrics) = crate::metrics::global() else {
        return Err(MetricsError::ExporterDisabled);
    };
    metrics.start_timer(name, tags)
}
```

## 依赖与外部交互

### 生命周期

```
1. start_timer() 调用
   ↓
2. Timer::new() 创建
   ├─ 克隆 name（String）
   ├─ 克隆 tags（Vec<(String, String)>）
   ├─ 克隆 client（Arc）
   └─ Instant::now()
   ↓
3. 执行被计时的操作
   ↓
4. Timer 离开作用域 / 手动 drop
   ↓
5. Drop::drop() 调用
   ├─ self.record(&[])
   │   ├─ 合并标签
   │   ├─ 计算耗时（Instant::elapsed()）
   │   └─ client.record_duration()
   └─ 错误时记录 tracing::error
```

### 与 MetricsClient 关系

```
MetricsClient
    ├─ start_timer() → Timer
    │                   ├─ name: String
    │                   ├─ tags: Vec<(String, String)>
    │                   ├─ client: MetricsClient (克隆)
    │                   └─ start_time: Instant
    └─ record_duration() ← Timer::record() / Drop
```

## 风险、边界与改进建议

### 当前风险

1. **双重记录**: 如果手动调用 `record()` 后又让 Timer drop，会记录两次
2. **标签克隆**: 创建时克隆所有标签字符串，有一定内存开销
3. **错误静默**: Drop 中的错误仅记录日志，调用方无法感知
4. **Panic 安全**: 如果 `record()` panic，可能导致双重 panic

### 边界情况

1. **零耗时**: 极短操作可能记录 0ms
2. **长时间运行**: 长时间操作可能溢出毫秒转换（实际不会，Duration 内部是秒 + 纳秒）
3. **空标签**: 支持空标签列表
4. **提前 drop**: 可以手动 `drop(timer)` 提前记录

### 改进建议

1. **防止双重记录**:
   ```rust
   pub struct Timer {
       // ...
       recorded: AtomicBool,  // 标记是否已记录
   }
   
   impl Drop for Timer {
       fn drop(&mut self) {
           if !self.recorded.swap(true, Ordering::SeqCst) {
               // 记录
           }
       }
   }
   ```

2. **取消记录**:
   ```rust
   impl Timer {
       pub fn cancel(mut self) {
           self.recorded = true;  // 标记为已记录（实际不记录）
           mem::forget(self);      // 防止 Drop
       }
   }
   ```

3. **作用域回调**:
   ```rust
   impl MetricsClient {
       pub fn time<F, R>(&self, name: &str, tags: &[(&str, &str)], f: F) -> Result<R>
       where F: FnOnce() -> R {
           let timer = self.start_timer(name, tags)?;
           let result = f();
           timer.record(&[])?;
           Ok(result)
       }
   }
   ```

4. **异步支持**:
   ```rust
   pub struct AsyncTimer {
       // 使用 tokio::time::Instant 支持异步上下文
   }
   ```

5. **标签引用优化**:
   ```rust
   // 使用 Cow 避免克隆
   tags: Vec<(Cow<'static, str>, Cow<'static, str>)>,
   ```

6. **精度选项**:
   ```rust
   pub enum TimeUnit {
       Milliseconds,
       Microseconds,
       Nanoseconds,
   }
   ```
