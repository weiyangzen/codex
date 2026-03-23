# commit_tick.rs 深入研究文档

## 场景与职责

`commit_tick.rs` 是流式分块策略（`chunking`）与具体流控制器（`controller`）之间的**编排桥梁**。它负责将高层的自适应分块决策转化为具体的控制器操作，并管理每个 commit tick 的完整生命周期。

### 核心场景

在 Codex TUI 的流式输出系统中，每个 commit tick 是一个周期性的动画帧，负责将队列中的行显示到屏幕上。`commit_tick.rs` 处理以下场景：

1. **常规 tick**：在正常动画节奏下，决定显示多少行
2. **追赶 tick**：在积压情况下，批量显示队列内容
3. **条件 tick**：仅在 catch-up 模式下执行（`CatchUpOnly` 作用域）

### 职责边界

| 职责 | 说明 |
|------|------|
| ✅ 编排完整的 commit tick 流程 | 快照 → 决策 → 应用 → 输出 |
| ✅ 聚合多控制器的队列状态 | 合并 `StreamController` 和 `PlanStreamController` 的队列信息 |
| ✅ 模式转换的可观测性 | 通过 trace log 记录模式切换 |
| ✅ 作用域控制 | 支持 `AnyMode` 和 `CatchUpOnly` 两种执行作用域 |
| ❌ 调度 tick 时机 | 由 `chatwidget.rs` 的动画系统控制 |
| ❌ 直接操作 UI | 仅返回 `HistoryCell`，由调用方插入 |
| ❌ 策略决策逻辑 | 委托给 `AdaptiveChunkingPolicy` |

---

## 功能点目的

### 1. 队列快照聚合

将多个控制器的队列状态合并为单一快照供策略使用：

```rust
fn stream_queue_snapshot(
    stream_controller: Option<&StreamController>,
    plan_stream_controller: Option<&PlanStreamController>,
    now: Instant,
) -> QueueSnapshot
```

聚合逻辑：
- **队列深度**：两个控制器队列深度之和
- **最旧年龄**：两个控制器最旧年龄的最大值

### 2. 作用域控制（CommitTickScope）

```rust
pub(crate) enum CommitTickScope {
    AnyMode,      // 始终执行 tick，无论当前模式
    CatchUpOnly,  // 仅在 CatchUp 模式下执行 drain
}
```

使用场景：
- **`AnyMode`**：常规动画 tick，由定时器触发
- **`CatchUpOnly`**：在接收到新 delta 时的机会性 tick，仅在积压时处理

### 3. 可观测性集成

通过 `tracing` 记录关键事件：
- **模式转换**：`stream chunking mode transition`
  - 记录 prior_mode, new_mode, queued_lines, oldest_queued_age_ms, entered_catch_up

---

## 具体技术实现

### 核心数据结构

```rust
/// 描述 commit tick 的执行作用域
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum CommitTickScope {
    AnyMode,      // 始终运行 tick
    CatchUpOnly,  // 仅在 CatchUp 模式下提交行
}

/// 描述单个 commit tick 的输出
pub(crate) struct CommitTickOutput {
    pub(crate) cells: Vec<Box<dyn HistoryCell>>, // 本次 tick 产生的单元格
    pub(crate) has_controller: bool,             // 是否有控制器参与
    pub(crate) all_idle: bool,                   // 所有控制器是否空闲
}
```

### 主流程：`run_commit_tick`

```rust
pub(crate) fn run_commit_tick(
    policy: &mut AdaptiveChunkingPolicy,
    stream_controller: Option<&mut StreamController>,
    plan_stream_controller: Option<&mut PlanStreamController>,
    scope: CommitTickScope,
    now: Instant,
) -> CommitTickOutput
```

执行流程：

```
run_commit_tick
├── stream_queue_snapshot(...)     // 收集队列状态
│   ├── controller.queued_lines()
│   └── controller.oldest_queued_age(now)
│
├── resolve_chunking_plan(...)     // 获取策略决策
│   ├── policy.decide(snapshot, now)
│   └── tracing::trace!(...)       // 记录模式转换
│
├── 作用域检查
│   └── 如果 scope == CatchUpOnly 且 mode != CatchUp
│       └── 返回默认输出（空）
│
└── apply_commit_tick_plan(...)    // 应用 drain 计划
    ├── drain_stream_controller(...)
    │   ├── controller.on_commit_tick()       // Single
    │   └── controller.on_commit_tick_batch() // Batch
    └── drain_plan_stream_controller(...)    // 同上
```

### 关键代码路径

#### 1. 队列快照构建
```rust
// commit_tick.rs:97-118
fn stream_queue_snapshot(
    stream_controller: Option<&StreamController>,
    plan_stream_controller: Option<&PlanStreamController>,
    now: Instant,
) -> QueueSnapshot {
    let mut queued_lines = 0usize;
    let mut oldest_age: Option<Duration> = None;

    if let Some(controller) = stream_controller {
        queued_lines += controller.queued_lines();
        oldest_age = max_duration(oldest_age, controller.oldest_queued_age(now));
    }
    if let Some(controller) = plan_stream_controller {
        queued_lines += controller.queued_lines();
        oldest_age = max_duration(oldest_age, controller.oldest_queued_age(now));
    }

    QueueSnapshot { queued_lines, oldest_age }
}
```

#### 2. 策略决策与追踪
```rust
// commit_tick.rs:124-142
fn resolve_chunking_plan(
    policy: &mut AdaptiveChunkingPolicy,
    snapshot: QueueSnapshot,
    now: Instant,
) -> ChunkingDecision {
    let prior_mode = policy.mode();
    let decision = policy.decide(snapshot, now);
    
    if decision.mode != prior_mode {
        tracing::trace!(
            prior_mode = ?prior_mode,
            new_mode = ?decision.mode,
            queued_lines = snapshot.queued_lines,
            oldest_queued_age_ms = snapshot.oldest_age.map(|age| age.as_millis() as u64),
            entered_catch_up = decision.entered_catch_up,
            "stream chunking mode transition"
        );
    }
    decision
}
```

#### 3. Drain 计划应用
```rust
// commit_tick.rs:148-173
fn apply_commit_tick_plan(
    drain_plan: DrainPlan,
    stream_controller: Option<&mut StreamController>,
    plan_stream_controller: Option<&mut PlanStreamController>,
) -> CommitTickOutput {
    let mut output = CommitTickOutput::default();

    if let Some(controller) = stream_controller {
        output.has_controller = true;
        let (cell, is_idle) = drain_stream_controller(controller, drain_plan);
        if let Some(cell) = cell {
            output.cells.push(cell);
        }
        output.all_idle &= is_idle;
    }
    // 同样处理 plan_stream_controller...
    output
}
```

#### 4. 控制器 Drain 分发
```rust
// commit_tick.rs:180-202
fn drain_stream_controller(
    controller: &mut StreamController,
    drain_plan: DrainPlan,
) -> (Option<Box<dyn HistoryCell>>, bool) {
    match drain_plan {
        DrainPlan::Single => controller.on_commit_tick(),
        DrainPlan::Batch(max_lines) => controller.on_commit_tick_batch(max_lines),
    }
}

fn drain_plan_stream_controller(
    controller: &mut PlanStreamController,
    drain_plan: DrainPlan,
) -> (Option<Box<dyn HistoryCell>>, bool) {
    match drain_plan {
        DrainPlan::Single => controller.on_commit_tick(),
        DrainPlan::Batch(max_lines) => controller.on_commit_tick_batch(max_lines),
    }
}
```

#### 5. 辅助函数：最大持续时间
```rust
// commit_tick.rs:207-214
fn max_duration(lhs: Option<Duration>, rhs: Option<Duration>) -> Option<Duration> {
    match (lhs, rhs) {
        (Some(left), Some(right)) => Some(left.max(right)),
        (Some(left), None) => Some(left),
        (None, Some(right)) => Some(right),
        (None, None) => None,
    }
}
```

---

## 关键代码路径与文件引用

### 模块内引用

| 文件 | 引用关系 | 说明 |
|------|----------|------|
| `mod.rs` | 被 `pub(crate) mod commit_tick;` 导出 | 模块入口 |
| `chunking.rs` | `use super::chunking::*` | 策略决策 |
| `controller.rs` | `use super::controller::*` | 执行 drain 操作 |

### 跨模块引用

| 文件 | 引用内容 | 用途 |
|------|----------|------|
| `chatwidget.rs:290-291` | `use crate::streaming::commit_tick::{CommitTickScope, run_commit_tick};` | 导入类型和函数 |
| `chatwidget.rs:3038-3044` | `run_commit_tick()` / `run_catch_up_commit_tick()` | 常规和追赶 tick |
| `chatwidget.rs:3053` | `run_commit_tick_with_scope(scope)` | 带作用域的执行 |
| `history_cell.rs` | `use crate::history_cell::HistoryCell;` | 输出类型 |

### 调用时序详解

```
用户输入 → LLM 流式响应
    ↓
chatwidget::handle_streaming_delta(delta)
    ├── stream_controller.push(delta)     // 推入新内容
    └── 如果有新行完成
        └── app_event_tx.send(AppEvent::StartCommitAnimation)
            ↓
动画系统（~120fps）
    ↓
chatwidget::on_commit_tick() [每 8.3ms]
    └── chatwidget::run_commit_tick()
        └── chatwidget::run_commit_tick_with_scope(CommitTickScope::AnyMode)
            ↓
commit_tick::run_commit_tick(...)
    ├── 构建队列快照
    ├── 获取策略决策
    ├── 应用 drain 计划
    └── 返回 CommitTickOutput
        ↓
chatwidget::run_commit_tick_with_scope 继续
    ├── 将 cells 添加到历史记录
    ├── 如果全部空闲，停止动画
    └── 刷新运行时指标
```

---

## 依赖与外部交互

### 标准库依赖

```rust
use std::time::Duration;
use std::time::Instant;
```

### 内部模块依赖

```
commit_tick.rs
    ├── chunking.rs (策略)
    ├── controller.rs (执行)
    └── history_cell.rs (输出类型)
```

### 依赖图

```
┌─────────────────┐
│   chatwidget.rs │ ◄── 调用方，持有控制器和策略状态
└────────┬────────┘
         │ 调用 run_commit_tick()
         ▼
┌─────────────────┐
│  commit_tick.rs │ ◄── 编排层，无状态，纯函数
└────────┬────────┘
         │
    ┌────┴────┐
    ▼         ▼
┌────────┐ ┌──────────┐
│chunking│ │controller│
└────────┘ └──────────┘
```

### 追踪目标

运行时可通过以下方式启用追踪：

```bash
RUST_LOG='codex_tui::streaming::commit_tick=trace' just codex
```

追踪事件：
- `stream chunking mode transition`：模式转换时记录

---

## 风险、边界与改进建议

### 已知风险

#### 1. 控制器引用有效性
- **风险**：文档警告 "If callers pass stale controller references... queue age can be misread"
- **场景**：如果调用方传递了与当前 turn 不关联的控制器引用，策略可能错误地保持 catch-up 模式
- **缓解**：`chatwidget.rs` 确保在正确的生命周期阶段调用

#### 2. 空控制器处理
- **风险**：`has_controller` 和 `all_idle` 的语义在边界情况下可能令人困惑
- **分析**：
  - 无控制器时：`has_controller=false`, `all_idle=true`
  - 有控制器且空闲时：`has_controller=true`, `all_idle=true`
  - 有控制器且忙碌时：`has_controller=true`, `all_idle=false`

#### 3. 时间快照一致性
- **风险**：`now` 参数在多个调用间传递，如果调用方使用不同的时间源可能导致不一致
- **现状**：`chatwidget.rs` 使用 `Instant::now()` 统一获取时间

### 边界条件

| 场景 | 行为 |
|------|------|
| 两个控制器都为 None | 返回默认输出（空 cells, has_controller=false, all_idle=true） |
| 只有一个控制器 | 正常处理，聚合逻辑正确处理 Option |
| scope=CatchUpOnly 且 mode=Smooth | 提前返回，不执行 drain，但策略状态仍更新 |
| drain_plan=Batch(0) | `max_lines.max(1)` 确保至少 drain 一行 |

### 测试覆盖

`commit_tick.rs` 本身没有独立的单元测试，其功能通过以下方式验证：

1. **集成测试**：`chatwidget/tests.rs` 中的端到端测试
2. **策略测试**：`chunking.rs` 中的单元测试验证决策逻辑
3. **控制器测试**：`controller.rs` 中的测试验证 drain 行为

### 改进建议

#### 1. 增加独立单元测试
当前模块缺乏直接测试，建议添加：

```rust
#[cfg(test)]
mod tests {
    #[test]
    fn catch_up_only_scope_skips_in_smooth_mode() {
        // 验证 CatchUpOnly 在 Smooth 模式下返回空
    }
    
    #[test]
    fn aggregates_queue_depth_across_controllers() {
        // 验证两个控制器的队列深度正确聚合
    }
    
    #[test]
    fn max_duration_selects_oldest() {
        // 验证 oldest_age 取最大值逻辑
    }
}
```

#### 2. 扩展追踪事件
当前仅记录模式转换，可考虑添加：

```rust
// 在 apply_commit_tick_plan 后
tracing::trace!(
    cells_emitted = output.cells.len(),
    has_controller = output.has_controller,
    all_idle = output.all_idle,
    "commit tick completed"
);
```

#### 3. 性能优化考虑
- **批量 drain 的效率**：当前 `Batch(n)` 会 drain 所有队列行，对于非常大的积压（如 1000+ 行）可能导致单帧处理时间过长
- **潜在改进**：添加每帧最大 drain 行数上限，即使 catch-up 也分多帧处理

#### 4. 错误处理增强
当前使用 `Option` 处理控制器，如果控制器状态不一致（如 `has_seen_delta` 为 true 但队列为空），可能导致意外行为。建议：

```rust
// 潜在改进：添加调试断言
debug_assert!(
    !controller.has_seen_delta || controller.queued_lines() > 0,
    "Controller has seen delta but queue is empty"
);
```

### 代码质量观察

- **优点**：
  - 清晰的函数分解，每个函数职责单一
  - 详尽的文档注释，包括警告和约束
  - 使用 `#[inline]` 友好的小函数
  - 对称的 `drain_stream_controller` 和 `drain_plan_stream_controller` 设计

- **潜在改进**：
  - `max_duration` 函数可考虑作为通用工具移至 `utils` 模块
  - `CommitTickOutput::default()` 的语义（特别是 `has_controller=false`）需要文档明确说明
