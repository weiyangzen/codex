# chunking.rs 深度研究文档

## 场景与职责

`chunking.rs` 实现了 TUI 流式输出的自适应分块策略（Adaptive Stream Chunking Policy），用于解决流式内容到达速度超过动画显示速度时的队列积压问题。

### 核心场景
- **正常负载**：保持基线用户体验，每帧提交一行内容（Smooth 模式）
- **突发流量**：当队列压力上升时，切换到 CatchUp 模式立即排空积压内容
- **模式切换稳定性**：通过滞后机制（hysteresis）避免模式频繁翻转

### 职责边界
**负责**：
- 跟踪分块模式和滞后状态
- 基于队列快照产生确定性的分块决策
- 保持队列顺序（仅从队列头部排空）

**不负责**：
- 调度提交 tick（由调用方控制）
- 重新排序流式行
- 传输/源特定的语义

## 功能点目的

### 1. 双模式系统设计
系统采用"双齿轮"设计：

- **Smooth 模式**：基线显示节奏，每 tick 排空一行
- **CatchUp 模式**：全队列排空，积压存在时立即处理

### 2. 滞后机制（Hysteresis）
避免在阈值边界附近快速模式翻转：

- **进入 CatchUp**：使用较高的压力阈值
- **退出 CatchUp**：使用较低的压力阈值，并保持 `EXIT_HOLD` 时间
- **重新进入抑制**：退出后 `REENTER_CATCH_UP_HOLD` 时间内禁止重新进入（严重积压除外）

### 3. 决策流程
每次决策 tick 时，`AdaptiveChunkingPolicy::decide` 执行：
1. 如果队列为空，重置为 Smooth 模式
2. 如果当前是 Smooth，调用 `maybe_enter_catch_up`
3. 如果当前是 CatchUp，调用 `maybe_exit_catch_up`
4. 构建 `DrainPlan`（Smooth 为 `Single`，CatchUp 为 `Batch`）

## 具体技术实现

### 关键数据结构

```rust
/// 分块模式
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) enum ChunkingMode {
    #[default]
    Smooth,   // 每 tick 排空一行
    CatchUp,  // 根据队列压力批量排空
}

/// 队列压力快照
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) struct QueueSnapshot {
    pub(crate) queued_lines: usize,      // 等待显示的行数
    pub(crate) oldest_age: Option<Duration>, // 最老行的年龄
}

/// 排空计划
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum DrainPlan {
    Single,       // 发出一行
    Batch(usize), // 发出最多 usize 行
}

/// 分块决策
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct ChunkingDecision {
    pub(crate) mode: ChunkingMode,
    pub(crate) entered_catch_up: bool,  // 是否从 Smooth 转入 CatchUp
    pub(crate) drain_plan: DrainPlan,
}

/// 自适应分块策略状态机
#[derive(Debug, Default)]
pub(crate) struct AdaptiveChunkingPolicy {
    mode: ChunkingMode,
    below_exit_threshold_since: Option<Instant>, // 低于退出阈值的时间点
    last_catch_up_exit_at: Option<Instant>,      // 上次退出 CatchUp 的时间
}
```

### 关键阈值常量

| 常量 | 值 | 用途 |
|------|-----|------|
| `ENTER_QUEUE_DEPTH_LINES` | 8 | 进入 CatchUp 的队列深度阈值 |
| `ENTER_OLDEST_AGE` | 120ms | 进入 CatchUp 的最老行年龄阈值 |
| `EXIT_QUEUE_DEPTH_LINES` | 2 | 退出 CatchUp 的队列深度阈值 |
| `EXIT_OLDEST_AGE` | 40ms | 退出 CatchUp 的最老行年龄阈值 |
| `EXIT_HOLD` | 250ms | 退出前必须保持低压力的持续时间 |
| `REENTER_CATCH_UP_HOLD` | 250ms | 退出后禁止重新进入的冷却时间 |
| `SEVERE_QUEUE_DEPTH_LINES` | 64 | 严重积压的队列深度阈值 |
| `SEVERE_OLDEST_AGE` | 300ms | 严重积压的最老行年龄阈值 |

### 核心算法逻辑

#### 进入 CatchUp 判断
```rust
fn should_enter_catch_up(snapshot: QueueSnapshot) -> bool {
    snapshot.queued_lines >= ENTER_QUEUE_DEPTH_LINES
        || snapshot.oldest_age.is_some_and(|oldest| oldest >= ENTER_OLDEST_AGE)
}
```
任一条件满足即可进入 CatchUp。

#### 退出 CatchUp 判断
```rust
fn should_exit_catch_up(snapshot: QueueSnapshot) -> bool {
    snapshot.queued_lines <= EXIT_QUEUE_DEPTH_LINES
        && snapshot.oldest_age.is_some_and(|oldest| oldest <= EXIT_OLDEST_AGE)
}
```
必须两个条件同时满足才开始考虑退出。

#### 严重积压判断
```rust
fn is_severe_backlog(snapshot: QueueSnapshot) -> bool {
    snapshot.queued_lines >= SEVERE_QUEUE_DEPTH_LINES
        || snapshot.oldest_age.is_some_and(|oldest| oldest >= SEVERE_OLDEST_AGE)
}
```
严重积压会绕过重新进入抑制机制。

#### 决策实现
```rust
pub(crate) fn decide(&mut self, snapshot: QueueSnapshot, now: Instant) -> ChunkingDecision {
    // 队列为空时重置
    if snapshot.queued_lines == 0 {
        self.note_catch_up_exit(now);
        self.mode = ChunkingMode::Smooth;
        self.below_exit_threshold_since = None;
        return ChunkingDecision { /* ... */ };
    }

    let entered_catch_up = match self.mode {
        ChunkingMode::Smooth => self.maybe_enter_catch_up(snapshot, now),
        ChunkingMode::CatchUp => { self.maybe_exit_catch_up(snapshot, now); false }
    };

    let drain_plan = match self.mode {
        ChunkingMode::Smooth => DrainPlan::Single,
        ChunkingMode::CatchUp => DrainPlan::Batch(snapshot.queued_lines.max(1)),
    };

    ChunkingDecision { mode: self.mode, entered_catch_up, drain_plan }
}
```

#### 进入 CatchUp 逻辑
```rust
fn maybe_enter_catch_up(&mut self, snapshot: QueueSnapshot, now: Instant) -> bool {
    if !should_enter_catch_up(snapshot) {
        return false;
    }
    // 检查重新进入抑制（非严重积压时）
    if self.reentry_hold_active(now) && !is_severe_backlog(snapshot) {
        return false;
    }
    self.mode = ChunkingMode::CatchUp;
    self.below_exit_threshold_since = None;
    self.last_catch_up_exit_at = None;
    true
}
```

#### 退出 CatchUp 逻辑
```rust
fn maybe_exit_catch_up(&mut self, snapshot: QueueSnapshot, now: Instant) {
    if !should_exit_catch_up(snapshot) {
        self.below_exit_threshold_since = None;
        return;
    }

    match self.below_exit_threshold_since {
        Some(since) if now.saturating_duration_since(since) >= EXIT_HOLD => {
            // 满足退出条件并持续足够时间
            self.mode = ChunkingMode::Smooth;
            self.below_exit_threshold_since = None;
            self.last_catch_up_exit_at = Some(now);
        }
        Some(_) => {} // 等待中
        None => { self.below_exit_threshold_since = Some(now); }
    }
}
```

## 关键代码路径与文件引用

### 本文件内关键函数
- `AdaptiveChunkingPolicy::decide` (line 180-210): 主决策入口
- `AdaptiveChunkingPolicy::maybe_enter_catch_up` (line 216-227): 进入 CatchUp 逻辑
- `AdaptiveChunkingPolicy::maybe_exit_catch_up` (line 233-250): 退出 CatchUp 逻辑
- `should_enter_catch_up` (line 267-272): 进入条件判断
- `should_exit_catch_up` (line 278-283): 退出条件判断
- `is_severe_backlog` (line 289-294): 严重积压判断

### 调用方
- `commit_tick.rs::run_commit_tick` (line 69-91): 调用 `decide` 并应用排空计划
- `chatwidget.rs` (line 722, 3640-3645): 持有 `AdaptiveChunkingPolicy` 实例并调用 commit tick

### 被调用方
无直接下游调用，纯策略模块

### 相关测试
本文件包含 10 个单元测试（line 296-439）：
- `smooth_mode_is_default`: 验证默认模式
- `enters_catch_up_on_depth_threshold`: 验证深度阈值触发
- `enters_catch_up_on_age_threshold`: 验证年龄阈值触发
- `severe_backlog_uses_faster_paced_batches`: 验证严重积压处理
- `catch_up_batch_drains_current_backlog`: 验证批量排空
- `exits_catch_up_after_hysteresis_hold`: 验证滞后退出
- `drops_back_to_smooth_when_idle`: 验证空闲重置
- `holds_reentry_after_catch_up_exit`: 验证重新进入抑制
- `severe_backlog_can_reenter_during_hold`: 验证严重积压绕过抑制

## 依赖与外部交互

### 依赖模块
- `std::time::{Duration, Instant}`: 时间计算

### 被依赖模块
- `commit_tick.rs`: 使用 `AdaptiveChunkingPolicy`、`ChunkingDecision`、`DrainPlan`、`QueueSnapshot`
- `chatwidget.rs`: 持有 `AdaptiveChunkingPolicy` 实例

### 配置与文档
- `docs/tui-stream-chunking-review.md`: 设计文档
- `docs/tui-stream-chunking-tuning.md`: 调优指南
- `docs/tui-stream-chunking-validation.md`: 验证流程

## 风险、边界与改进建议

### 风险点

1. **阈值敏感性问题**
   - 当前阈值是硬编码的实验值，可能不适合所有场景
   - 不同终端性能、网络延迟下表现可能不一致

2. **滞后时间窗口**
   - `EXIT_HOLD` 和 `REENTER_CATCH_UP_HOLD` 固定为 250ms
   - 在极端高帧率或低帧率环境下可能需要调整

3. **严重积压判断**
   - 严重积压阈值（64行/300ms）可能过于激进或保守
   - 没有动态调整机制

### 边界条件

1. **队列为空**
   - 当 `queued_lines == 0` 时强制重置为 Smooth 模式
   - 这会清除所有滞后状态

2. **时间回退**
   - 使用 `saturating_duration_since` 处理时间回退情况

3. **单行长内容**
   - 策略基于行数而非字节数，单行极长内容可能影响体验

### 改进建议

1. **可配置化**
   ```rust
   // 建议：从配置文件读取阈值
   pub struct ChunkingConfig {
       enter_queue_depth: usize,
       enter_oldest_age_ms: u64,
       // ...
   }
   ```

2. **动态调整**
   - 基于历史数据动态调整阈值
   - 根据终端帧率自适应调整 `EXIT_HOLD`

3. **更多可观测性**
   - 添加指标收集（模式切换次数、平均队列深度等）
   - 支持导出到外部监控系统

4. **测试覆盖**
   - 添加压力测试（模拟高频率输入）
   - 添加边界条件测试（时间回退、空队列等）

5. **性能优化**
   - `decide` 函数每次调用都会创建新的 `ChunkingDecision`
   - 考虑使用对象池减少分配（如果性能成为问题）
