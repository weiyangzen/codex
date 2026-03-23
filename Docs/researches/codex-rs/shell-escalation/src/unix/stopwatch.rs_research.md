# stopwatch.rs 研究文档

## 场景与职责

`stopwatch.rs` 是 Unix 平台 shell 权限提升机制的**时间管理组件**，提供一个可暂停/恢复的计时器，用于管理命令执行的超时。与普通计时器不同，它支持在特定操作期间暂停计时（如等待用户审批），确保超时只计算实际执行时间。

核心职责：
1. 提供可暂停/恢复的计时功能
2. 支持嵌套/重叠的暂停（引用计数）
3. 生成 `CancellationToken` 在超时后自动触发
4. 支持无限制模式（永不超时）

## 功能点目的

### 1. Stopwatch 结构

```rust
#[derive(Clone, Debug)]
pub struct Stopwatch {
    limit: Option<Duration>,
    inner: Arc<Mutex<StopwatchState>>,
    notify: Arc<Notify>,
}

#[derive(Debug)]
struct StopwatchState {
    elapsed: Duration,
    running_since: Option<Instant>,
    active_pauses: u32,
}
```

**字段说明**：
- `limit`：超时限制，`None` 表示无限制
- `inner`：共享状态（已用时间、运行起始时间、活跃暂停数）
- `notify`：用于唤醒超时等待任务的通知器

**状态说明**：
- `elapsed`：累计已用时间（不包括暂停期间）
- `running_since`：当前运行段的起始时间，`None` 表示正在暂停
- `active_pauses`：活跃暂停的引用计数

### 2. 构造方法

```rust
impl Stopwatch {
    pub fn new(limit: Duration) -> Self { ... }
    pub fn unlimited() -> Self { ... }
}
```

- `new()`：创建有限时长的计时器，立即开始计时
- `unlimited()`：创建无限制的计时器，用于不需要超时的场景

### 3. CancellationToken 生成

```rust
pub fn cancellation_token(&self) -> CancellationToken
```

创建一个与计时器关联的取消令牌：
- 当计时器达到限制时，自动触发 `cancel()`
- 支持暂停期间的正确等待
- 使用 `tokio::spawn` 在后台监控时间

### 4. 暂停/恢复

```rust
pub async fn pause_for<F, T>(&self, fut: F) -> T
where
    F: Future<Output = T>,
{
    self.pause().await;
    let result = fut.await;
    self.resume().await;
    result
}
```

在异步操作期间暂停计时：
- 支持嵌套调用（引用计数）
- 只有最外层的 `resume` 才真正恢复计时
- 自动处理，无需手动配对 pause/resume

## 具体技术实现

### 计时逻辑

**当前已用时间计算**：
```rust
let elapsed = guard.elapsed
    + guard
        .running_since
        .map(|since| since.elapsed())
        .unwrap_or_default();
```

- 基础：`elapsed`（累计已用时间）
- 加上：当前运行段的持续时间（如果正在运行）

**暂停逻辑**：
```rust
async fn pause(&self) {
    let mut guard = self.inner.lock().await;
    guard.active_pauses += 1;
    if guard.active_pauses == 1
        && let Some(since) = guard.running_since.take()
    {
        guard.elapsed += since.elapsed();
        self.notify.notify_waiters();
    }
}
```

1. 增加暂停计数
2. 如果是第一个暂停：
   - 将当前运行段的时间加到 `elapsed`
   - 清除 `running_since`（标记为暂停状态）
   - 通知等待的任务（超时监控任务会重新计算剩余时间）

**恢复逻辑**：
```rust
async fn resume(&self) {
    let mut guard = self.inner.lock().await;
    if guard.active_pauses == 0 { return; }
    guard.active_pauses -= 1;
    if guard.active_pauses == 0 && guard.running_since.is_none() {
        guard.running_since = Some(Instant::now());
        self.notify.notify_waiters();
    }
}
```

1. 减少暂停计数
2. 如果暂停计数归零且当前处于暂停状态：
   - 设置 `running_since` 为当前时间（恢复计时）
   - 通知等待的任务

### 超时监控任务

```rust
pub fn cancellation_token(&self) -> CancellationToken {
    let token = CancellationToken::new();
    let Some(limit) = self.limit else { return token; };
    
    let cancel = token.clone();
    let inner = Arc::clone(&self.inner);
    let notify = Arc::clone(&self.notify);
    
    tokio::spawn(async move {
        loop {
            // 计算剩余时间和运行状态
            let (remaining, running) = {
                let guard = inner.lock().await;
                let elapsed = ...;
                if elapsed >= limit { break; }
                (limit - elapsed, guard.running_since.is_some())
            };
            
            if !running {
                // 暂停中，等待恢复通知
                notify.notified().await;
                continue;
            }
            
            // 运行中，等待剩余时间或暂停通知
            let sleep = tokio::time::sleep(remaining);
            tokio::pin!(sleep);
            tokio::select! {
                _ = &mut sleep => break,
                _ = notify.notified() => continue,
            }
        }
        cancel.cancel();
    });
    
    token
}
```

关键点：
1. 无限制模式直接返回未触发的 token
2. 每次循环重新计算剩余时间（考虑暂停）
3. 暂停时等待 `notify.notified()`
4. 运行时使用 `tokio::select!` 同时等待超时和暂停通知

## 关键代码路径与文件引用

### 本文件内关键行

| 行号 | 内容 | 说明 |
|------|------|------|
| 10-15 | `Stopwatch` 结构 | 主结构定义 |
| 17-22 | `StopwatchState` 结构 | 内部状态 |
| 24-47 | `new()` / `unlimited()` | 构造方法 |
| 49-91 | `cancellation_token()` | 取消令牌生成 |
| 93-105 | `pause_for()` | 暂停包装器 |
| 107-116 | `pause()` | 暂停实现 |
| 118-128 | `resume()` | 恢复实现 |
| 131-237 | 测试模块 | comprehensive tests |

### 依赖文件

- `codex-rs/core/src/tools/runtimes/shell/unix_escalation.rs`：使用 `Stopwatch` 管理命令超时

### 被依赖文件

| 文件 | 用途 |
|------|------|
| `mod.rs` | 重新导出 `Stopwatch` |
| `codex-rs/core/src/tools/runtimes/shell/unix_escalation.rs` | 创建计时器，传递给 `EscalateServer::exec()` |

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `std::future::Future` | `pause_for` 的异步操作 |
| `std::sync::Arc` | 共享状态 |
| `std::time::Duration`, `std::time::Instant` | 时间计算 |
| `tokio::sync::Mutex` | 异步互斥锁 |
| `tokio::sync::Notify` | 暂停/恢复通知 |
| `tokio_util::sync::CancellationToken` | 超时取消信号 |

### 使用模式

```rust
// 创建计时器
let stopwatch = Stopwatch::new(Duration::from_secs(60));
let cancel_token = stopwatch.cancellation_token();

// 执行可能暂停的操作
let result = stopwatch.pause_for(async {
    // 例如：等待用户审批
    request_user_approval().await
}).await;

// 继续执行
let output = execute_command(cancel_token).await;
```

### 在核心代码中的使用

`unix_escalation.rs` 中的使用：
```rust
let stopwatch = Stopwatch::new(effective_timeout);
let cancel_token = stopwatch.cancellation_token();

// 在策略中使用
let escalation_policy = CoreShellActionProvider {
    // ...
    stopwatch: stopwatch.clone(),
};

// 策略中的审批流程
async fn prompt(...) -> anyhow::Result<ReviewDecision> {
    Ok(stopwatch
        .pause_for(async move {
            // 用户审批期间暂停计时
            request_command_approval(...).await
        })
        .await)
}
```

## 风险、边界与改进建议

### 已知风险

1. **时间精度**：使用 `Instant::elapsed()` 计算时间，受系统时钟精度影响。在极端情况下（如系统休眠），计时可能不准确。

2. **任务泄漏**：`cancellation_token()` spawn 的后台任务在 `Stopwatch` 被 drop 后仍可能运行，直到超时或取消。虽然影响小，但会造成资源浪费。

3. **锁竞争**：使用 `tokio::sync::Mutex`，在高并发暂停/恢复场景可能有锁竞争。

### 边界情况

1. **嵌套暂停**：测试验证最多 2 层嵌套暂停（`overlapping_pauses_only_resume_once`），理论上支持任意深度，但过深的嵌套可能导致栈溢出。

2. **零时长限制**：`Duration::from_secs(0)` 会立即触发取消。

3. **无限暂停**：如果暂停后永不恢复，计时器永远不会触发取消。

4. **快速暂停恢复**：如果暂停和恢复间隔极短，可能 `running_since` 和当前时间相同，导致 `elapsed` 不增加。

### 测试覆盖

文件包含 comprehensive 的测试套件（约 105 行测试代码）：

| 测试 | 目的 |
|------|------|
| `cancellation_receiver_fires_after_limit` | 验证基本超时功能 |
| `pause_prevents_timeout_until_resumed` | 验证暂停阻止超时 |
| `overlapping_pauses_only_resume_once` | 验证嵌套暂停的正确性 |
| `unlimited_stopwatch_never_cancels` | 验证无限制模式 |

### 改进建议

1. **后台任务清理**：在 `Stopwatch` 实现 `Drop` 时通知后台任务退出：
   ```rust
   impl Drop for Stopwatch {
       fn drop(&mut self) {
           // 通知后台任务退出
           self.notify.notify_waiters();
       }
   }
   ```

2. **精度配置**：允许配置时间精度，例如：
   ```rust
   pub fn with_precision(limit: Duration, precision: Duration) -> Self
   ```

3. **回调支持**：添加超时回调：
   ```rust
   pub fn on_timeout<F: FnOnce() + Send + 'static>(&self, callback: F)
   ```

4. **统计信息**：添加计时统计：
   ```rust
   pub async fn stats(&self) -> StopwatchStats {
       let guard = self.inner.lock().await;
       StopwatchStats {
           elapsed: guard.elapsed,
           paused: guard.running_since.is_none(),
           pause_count: guard.active_pauses,
       }
   }
   ```

5. **同步接口**：对于非异步场景，提供同步接口：
   ```rust
   pub fn pause_for_sync<F, T>(&self, f: F) -> T
   where
       F: FnOnce() -> T,
   {
       // 使用 block_on 或内部线程
   }
   ```

6. **文档示例**：添加更多使用示例：
   ```rust
   /// # Example: Nested pauses
   /// ```
   /// let stopwatch = Stopwatch::new(Duration::from_secs(10));
   /// 
   /// stopwatch.pause_for(async {
   ///     // Outer pause
   ///     stopwatch.pause_for(async {
   ///         // Inner pause
   ///         sleep(Duration::from_secs(5)).await;
   ///     }).await;
   ///     
   ///     // Still paused here
   ///     sleep(Duration::from_secs(3)).await;
   /// }).await;
   /// 
   /// // Now resumed
   /// ```
   ```

7. **性能优化**：对于高频暂停/恢复场景，考虑使用无锁数据结构（如 `parking_lot::Mutex` 或原子操作）。

### 设计亮点

1. **引用计数暂停**：使用 `active_pauses: u32` 实现嵌套暂停，简洁而有效。

2. **通知机制**：使用 `tokio::sync::Notify` 而非轮询，提高效率。

3. **Clone 支持**：`Stopwatch` 实现 `Clone`，允许多个组件共享同一个计时器。

4. **与 tokio 集成**：使用 `tokio_util::sync::CancellationToken`，与 tokio 生态无缝集成。

5. **无限制模式**：`unlimited()` 方法提供与有限计时器相同的接口，简化调用代码。
