# chunking.rs 深入研究文档

## 场景与职责

`chunking.rs` 实现了 TUI 流式输出的自适应分块策略（Adaptive Stream Chunking Policy），核心职责是解决**流式输出到达速度**与**动画显示速度**之间的不匹配问题。

### 核心场景

当 Codex TUI 接收 LLM 的流式响应时，文本以 delta 形式持续到达。如果输出到达速度超过动画逐行显示的速度，队列会积压，导致用户感知的显示滞后。`chunking.rs` 通过动态调整每帧提交的行数来解决这一问题：

- **正常负载**：保持基线用户体验，每 tick 显示一行（Smooth 模式）
- **突发负载**：检测到队列压力时，切换到批量 drain 模式（CatchUp 模式）

### 职责边界

| 职责 | 说明 |
|------|------|
| ✅ 模式跟踪与滞后状态管理 | 维护 Smooth/CatchUp 两种模式及转换历史 |
| ✅ 从队列快照生成确定性决策 | 基于 `QueueSnapshot` 生成 `ChunkingDecision` |
| ✅ 保持队列顺序 | 仅从队列头部 drain，不重新排序 |
| ❌ 调度 commit tick | 由调用方（`chatwidget.rs`）控制 |
| ❌ 重新排序流式行 | 由 `StreamState` 保证 FIFO |
| ❌ 传输/源特定语义 | 策略与数据源无关 |

---

## 功能点目的

### 1. 双模式系统（Two-Gear System）

```rust
pub(crate) enum ChunkingMode {
    Smooth,   // 基线显示节奏，每 tick 一行
    CatchUp,  // 全队列 drain，积压存在时立即处理
}
```

设计哲学：
- **Smooth**：提供熟悉、稳定的动画体验
- **CatchUp**：在积压时快速收敛显示滞后

### 2. 滞后转换（Hysteresis Transitions）

避免在阈值边界附近快速模式切换（flapping）：

- **进入 CatchUp**：需要跨越较高的压力阈值
- **退出 CatchUp**：需要在较低阈值以下保持 `EXIT_HOLD` 时间
- **重新进入抑制**：退出后 `REENTER_CATCH_UP_HOLD` 时间内阻止重新进入（严重积压除外）

### 3. 压力感知阈值

| 阈值类型 | 常量 | 值 | 用途 |
|----------|------|-----|------|
| 进入深度 | `ENTER_QUEUE_DEPTH_LINES` | 8 行 | 队列深度触发 catch-up |
| 进入年龄 | `ENTER_OLDEST_AGE` | 120ms | 最旧行年龄触发 catch-up |
| 退出深度 | `EXIT_QUEUE_DEPTH_LINES` | 2 行 | 退出 catch-up 的深度条件 |
| 退出年龄 | `EXIT_OLDEST_AGE` | 40ms | 退出 catch-up 的年龄条件 |
| 严重深度 | `SEVERE_QUEUE_DEPTH_LINES` | 64 行 | 绕过重新进入抑制 |
| 严重年龄 | `SEVERE_OLDEST_AGE` | 300ms | 绕过重新进入抑制 |
| 退出保持 | `EXIT_HOLD` | 250ms | 退出前的持续低压力时间 |
| 重新进入抑制 | `REENTER_CATCH_UP_HOLD` | 250ms | 退出后的冷却窗口 |

---

## 具体技术实现

### 核心数据结构

```rust
/// 队列压力输入快照
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) struct QueueSnapshot {
    pub(crate) queued_lines: usize,      // 等待显示的行数
    pub(crate) oldest_age: Option<Duration>, // 最旧行的年龄
}

/// Drain 计划
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum DrainPlan {
    Single,         // 发出一行
    Batch(usize),   // 发出最多 N 行
}

/// 策略决策结果
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct ChunkingDecision {
    pub(crate) mode: ChunkingMode,           // 应用后的模式
    pub(crate) entered_catch_up: bool,       // 是否刚进入 catch-up
    pub(crate) drain_plan: DrainPlan,        // 要执行的 drain 计划
}

/// 自适应分块策略状态机
#[derive(Debug, Default)]
pub(crate) struct AdaptiveChunkingPolicy {
    mode: ChunkingMode,
    below_exit_threshold_since: Option<Instant>, // 低于退出阈值的开始时间
    last_catch_up_exit_at: Option<Instant>,      // 上次退出 catch-up 的时间
}
```

### 关键决策流程

```
decide(snapshot, now)
├── 如果队列为空
│   └── 重置为 Smooth，返回 Single
│
├── 如果当前是 Smooth
│   └── maybe_enter_catch_up()
│       ├── 检查是否应该进入（深度≥8 或 年龄≥120ms）
│       ├── 检查重新进入抑制是否激活
│       │   └── 如果是，检查是否为严重积压
│       └── 切换模式，清除状态
│
├── 如果当前是 CatchUp
│   └── maybe_exit_catch_up()
│       ├── 检查是否应该退出（深度≤2 且 年龄≤40ms）
│       ├── 如果首次低于阈值，记录时间
│       └── 如果持续低于阈值超过 EXIT_HOLD，切换回 Smooth
│
└── 根据模式生成 DrainPlan
    ├── Smooth → Single
    └── CatchUp → Batch(queued_lines)
```

### 关键代码路径

#### 1. 决策入口
```rust
// chunking.rs:180-210
pub(crate) fn decide(&mut self, snapshot: QueueSnapshot, now: Instant) -> ChunkingDecision {
    if snapshot.queued_lines == 0 {
        // 队列为空时重置
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
    // ...
}
```

#### 2. 进入 CatchUp 逻辑
```rust
// chunking.rs:216-227
fn maybe_enter_catch_up(&mut self, snapshot: QueueSnapshot, now: Instant) -> bool {
    if !should_enter_catch_up(snapshot) { return false; }
    
    // 重新进入抑制检查
    if self.reentry_hold_active(now) && !is_severe_backlog(snapshot) {
        return false;
    }
    
    self.mode = ChunkingMode::CatchUp;
    self.below_exit_threshold_since = None;
    self.last_catch_up_exit_at = None;
    true
}
```

#### 3. 退出 CatchUp 逻辑
```rust
// chunking.rs:233-250
fn maybe_exit_catch_up(&mut self, snapshot: QueueSnapshot, now: Instant) {
    if !should_exit_catch_up(snapshot) {
        self.below_exit_threshold_since = None;
        return;
    }

    match self.below_exit_threshold_since {
        Some(since) if now.saturating_duration_since(since) >= EXIT_HOLD => {
            // 持续低压力超过 EXIT_HOLD，正式退出
            self.mode = ChunkingMode::Smooth;
            self.below_exit_threshold_since = None;
            self.last_catch_up_exit_at = Some(now);
        }
        Some(_) => {} // 等待中
        None => { self.below_exit_threshold_since = Some(now); }
    }
}
```

#### 4. 压力评估函数
```rust
// chunking.rs:267-294
fn should_enter_catch_up(snapshot: QueueSnapshot) -> bool {
    snapshot.queued_lines >= ENTER_QUEUE_DEPTH_LINES
        || snapshot.oldest_age.is_some_and(|oldest| oldest >= ENTER_OLDEST_AGE)
}

fn should_exit_catch_up(snapshot: QueueSnapshot) -> bool {
    snapshot.queued_lines <= EXIT_QUEUE_DEPTH_LINES
        && snapshot.oldest_age.is_some_and(|oldest| oldest <= EXIT_OLDEST_AGE)
}

fn is_severe_backlog(snapshot: QueueSnapshot) -> bool {
    snapshot.queued_lines >= SEVERE_QUEUE_DEPTH_LINES
        || snapshot.oldest_age.is_some_and(|oldest| oldest >= SEVERE_OLDEST_AGE)
}
```

---

## 关键代码路径与文件引用

### 模块内引用

| 文件 | 引用关系 | 说明 |
|------|----------|------|
| `mod.rs` | 被 `pub(crate) mod chunking;` 导出 | 模块入口 |
| `commit_tick.rs` | `use super::chunking::*` | 使用策略进行 tick 编排 |
| `controller.rs` | 被 `commit_tick.rs` 调用 | 执行实际的 drain 操作 |

### 跨模块引用

| 文件 | 引用内容 | 用途 |
|------|----------|------|
| `chatwidget.rs:289` | `use crate::streaming::chunking::AdaptiveChunkingPolicy;` | 主窗口持有策略状态 |
| `chatwidget.rs:667` | `adaptive_chunking: AdaptiveChunkingPolicy` | 作为 `Chat` 结构体字段 |
| `chatwidget.rs:3055` | 传递给 `run_commit_tick()` | 每个 commit tick 使用 |
| `chatwidget.rs:3596` | `AdaptiveChunkingPolicy::default()` | 初始化新会话 |

### 外部文档引用

- `docs/tui-stream-chunking-review.md` - 设计概述
- `docs/tui-stream-chunking-tuning.md` - 调优指南
- `docs/tui-stream-chunking-validation.md` - 验证流程

---

## 依赖与外部交互

### 标准库依赖

```rust
use std::time::Duration;
use std::time::Instant;
```

- **`Duration`**：所有时间阈值（年龄、保持窗口）
- **`Instant`**：时间点记录（进入/退出时间戳）

### 内部模块依赖

```
chunking.rs
    ↑ 被使用
commit_tick.rs ──→ controller.rs
    ↓
chatwidget.rs
```

### 调用时序

```
Chat::on_commit_tick() [chatwidget.rs:3033]
    └── Chat::run_commit_tick()
        └── Chat::run_commit_tick_with_scope(CommitTickScope::AnyMode)
            └── run_commit_tick(...) [commit_tick.rs:69]
                ├── stream_queue_snapshot() [commit_tick.rs:97]
                │   └── controller.queued_lines() / oldest_queued_age()
                ├── resolve_chunking_plan() [commit_tick.rs:124]
                │   └── policy.decide(snapshot, now) [chunking.rs:180]
                └── apply_commit_tick_plan() [commit_tick.rs:148]
                    └── controller.on_commit_tick() / on_commit_tick_batch()
```

---

## 风险、边界与改进建议

### 已知风险

#### 1. 阈值敏感性问题
- **风险**：阈值设置不当可能导致过早进入 catch-up（动画感丢失）或过晚进入（滞后感明显）
- **缓解**：当前值基于实验验证，文档中提供了调优指南

#### 2. 时间测量精度
- **风险**：`Instant::now()` 在极端高频率调用时可能有微小开销
- **现状**：commit tick 约每 8.3ms（120fps），`Instant` 调用频率可接受

#### 3. 严重积压绕过机制
- **风险**：`SEVERE_QUEUE_DEPTH_LINES=64` 可能在高分辨率/小字体屏幕上显得过于保守
- **边界**：严重积压检测仅在重新进入抑制期间有效

### 边界条件

| 场景 | 行为 |
|------|------|
| 队列为空 | 强制重置为 Smooth 模式 |
| 快照年龄为 None | `should_exit_catch_up` 返回 false（需要 AND 条件） |
| 同时满足进入和退出条件 | 由当前模式决定，避免同时触发 |
| 退出后立即有积压 | 受 `REENTER_CATCH_UP_HOLD` 抑制，除非严重积压 |

### 测试覆盖

模块内包含 10 个单元测试：

```rust
#[test]
fn smooth_mode_is_default() { ... }
#[test]
fn enters_catch_up_on_depth_threshold() { ... }
#[test]
fn enters_catch_up_on_age_threshold() { ... }
#[test]
fn severe_backlog_uses_faster_paced_batches() { ... }
#[test]
fn catch_up_batch_drains_current_backlog() { ... }
#[test]
fn exits_catch_up_after_hysteresis_hold() { ... }
#[test]
fn drops_back_to_smooth_when_idle() { ... }
#[test]
fn holds_reentry_after_catch_up_exit() { ... }
#[test]
fn severe_backlog_can_reenter_during_hold() { ... }
```

### 改进建议

#### 1. 动态阈值调整（低优先级）
考虑基于终端尺寸或历史模式动态调整阈值：
```rust
// 潜在扩展
impl AdaptiveChunkingPolicy {
    pub(crate) fn with_terminal_size(mut self, size: TerminalSize) -> Self {
        // 小屏幕可能需要更激进的 catch-up
        self
    }
}
```

#### 2. 指标导出（可观测性增强）
当前仅通过 trace log 输出，可考虑：
- 暴露累计统计（总 Smooth tick 数、总 CatchUp tick 数、模式切换次数）
- 用于性能回归测试的断言钩子

#### 3. 配置化阈值（用户定制）
当前阈值为编译时常量，未来可考虑：
```toml
# 潜在的 config.toml 扩展
[stream_chunking]
enter_queue_depth = 8
enter_oldest_age_ms = 120
exit_queue_depth = 2
exit_oldest_age_ms = 40
```

#### 4. 预测性进入（实验性）
基于到达速率预测而非仅当前队列状态：
```rust
// 伪代码
fn should_enter_catch_up_predictive(&self, snapshot: QueueSnapshot, arrival_rate: f64) -> bool {
    let predicted_lag = snapshot.oldest_age.map(|age| {
        age + Duration::from_secs_f64(snapshot.queued_lines as f64 / arrival_rate)
    });
    // ...
}
```

### 代码质量观察

- **优点**：
  - 详尽的文档注释（模块级、函数级、行内）
  - 清晰的职责分离
  - 完备的单元测试
  - 使用 `saturating_duration_since` 避免时间溢出

- **潜在改进**：
  - `should_exit_catch_up` 使用 AND 条件（深度 AND 年龄），而 `should_enter_catch_up` 使用 OR 条件，这种不对称性需要文档明确说明原因
  - 常量值分散在文件顶部，可考虑集中配置结构体
