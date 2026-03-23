# commit_tick.rs 深度研究文档

## 场景与职责

`commit_tick.rs` 是流式分块策略与具体控制器之间的桥梁，负责编排提交 tick 的完整流程：收集队列快照、计算分块决策、应用排空计划、返回生成的历史单元格。

### 核心场景
- **定期提交 tick**：由动画定时器触发，定期执行内容提交
- **追赶模式提交**：仅在 CatchUp 模式下执行的 opportunistic 提交
- **多控制器协调**：同时处理主流控制器和计划流控制器

### 职责边界
**负责**：
- 收集跨控制器的队列压力快照
- 调用分块策略获取决策
- 应用排空计划到具体控制器
- 记录追踪日志用于可观测性

**不负责**：
- 调度 tick（由 `chatwidget.rs` 控制）
- 直接修改 UI 状态
- 处理动画事件

## 功能点目的

### 1. 提交 Tick 范围控制
通过 `CommitTickScope` 枚举控制 tick 的执行范围：

```rust
pub(crate) enum CommitTickScope {
    AnyMode,      // 任何模式下都执行
    CatchUpOnly,  // 仅在 CatchUp 模式下执行排空
}
```

用于区分常规提交 tick 和 opportunistic 追赶 tick。

### 2. 队列快照聚合
聚合多个控制器的队列状态：
- 累加队列深度
- 取最老行的最大年龄

### 3. 追踪日志
在模式切换时输出结构化日志：
```rust
tracing::trace!(
    prior_mode = ?prior_mode,
    new_mode = ?decision.mode,
    queued_lines = snapshot.queued_lines,
    oldest_queued_age_ms = snapshot.oldest_age.map(|age| age.as_millis() as u64),
    entered_catch_up = decision.entered_catch_up,
    "stream chunking mode transition"
);
```

## 具体技术实现

### 关键数据结构

```rust
/// 提交 Tick 范围
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum CommitTickScope {
    AnyMode,      // 总是执行 tick
    CatchUpOnly,  // 仅在 CatchUp 模式下执行排空
}

/// 单次提交 tick 的输出
pub(crate) struct CommitTickOutput {
    pub(crate) cells: Vec<Box<dyn HistoryCell>>, // 本次 tick 产生的单元格
    pub(crate) has_controller: bool,             // 是否有控制器参与
    pub(crate) all_idle: bool,                   // 所有控制器是否空闲
}
```

### 核心流程

#### 主入口函数
```rust
pub(crate) fn run_commit_tick(
    policy: &mut AdaptiveChunkingPolicy,
    stream_controller: Option<&mut StreamController>,
    plan_stream_controller: Option<&mut PlanStreamController>,
    scope: CommitTickScope,
    now: Instant,
) -> CommitTickOutput {
    // 1. 收集队列快照
    let snapshot = stream_queue_snapshot(
        stream_controller.as_deref(),
        plan_stream_controller.as_deref(),
        now,
    );
    
    // 2. 获取分块决策
    let decision = resolve_chunking_plan(policy, snapshot, now);
    
    // 3. 根据 scope 决定是否跳过
    if scope == CommitTickScope::CatchUpOnly && decision.mode != ChunkingMode::CatchUp {
        return CommitTickOutput::default();
    }
    
    // 4. 应用排空计划
    apply_commit_tick_plan(
        decision.drain_plan,
        stream_controller,
        plan_stream_controller,
    )
}
```

#### 队列快照收集
```rust
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

#### 决策解析与日志
```rust
fn resolve_chunking_plan(
    policy: &mut AdaptiveChunkingPolicy,
    snapshot: QueueSnapshot,
    now: Instant,
) -> ChunkingDecision {
    let prior_mode = policy.mode();
    let decision = policy.decide(snapshot, now);
    
    // 模式切换时输出追踪日志
    if decision.mode != prior_mode {
        tracing::trace!(...);
    }
    decision
}
```

#### 排空计划应用
```rust
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
    
    if let Some(controller) = plan_stream_controller {
        output.has_controller = true;
        let (cell, is_idle) = drain_plan_stream_controller(controller, drain_plan);
        if let Some(cell) = cell {
            output.cells.push(cell);
        }
        output.all_idle &= is_idle;
    }

    output
}
```

#### 控制器排空
```rust
fn drain_stream_controller(
    controller: &mut StreamController,
    drain_plan: DrainPlan,
) -> (Option<Box<dyn HistoryCell>>, bool) {
    match drain_plan {
        DrainPlan::Single => controller.on_commit_tick(),
        DrainPlan::Batch(max_lines) => controller.on_commit_tick_batch(max_lines),
    }
}
```

### 辅助函数

```rust
/// 返回两个可选 Duration 中的较大者
fn max_duration(lhs: Option<Duration>, rhs: Option<Duration>) -> Option<Duration> {
    match (lhs, rhs) {
        (Some(left), Some(right)) => Some(left.max(right)),
        (Some(left), None) => Some(left),
        (None, Some(right)) => Some(right),
        (None, None) => None,
    }
}
```

## 关键代码路径与文件引用

### 本文件内关键函数
- `run_commit_tick` (line 69-91): 主入口函数
- `stream_queue_snapshot` (line 97-118): 队列快照收集
- `resolve_chunking_plan` (line 124-142): 决策解析与日志
- `apply_commit_tick_plan` (line 148-173): 排空计划应用
- `drain_stream_controller` (line 180-188): 主流控制器排空
- `drain_plan_stream_controller` (line 194-202): 计划流控制器排空

### 调用方
- `chatwidget.rs`:
  - `on_commit_tick` (line 3618-3620): 调用 `run_commit_tick`
  - `run_commit_tick` (line 3623-3625): 常规提交
  - `run_catch_up_commit_tick` (line 3628-3630): 追赶提交
  - `run_commit_tick_with_scope` (line 3638-3650): 带范围的提交

### 被调用方
- `chunking.rs`:
  - `AdaptiveChunkingPolicy::decide`: 获取分块决策
  - `AdaptiveChunkingPolicy::mode`: 获取当前模式
- `controller.rs`:
  - `StreamController::queued_lines`: 获取队列深度
  - `StreamController::oldest_queued_age`: 获取最老行年龄
  - `StreamController::on_commit_tick`: 单步排空
  - `StreamController::on_commit_tick_batch`: 批量排空
  - `PlanStreamController` 的相同方法

### 依赖模块
- `history_cell.rs`: `HistoryCell` trait
- `chunking.rs`: 分块策略相关类型
- `controller.rs`: 控制器类型

## 依赖与外部交互

### 依赖模块
- `std::time::{Duration, Instant}`: 时间类型
- `tracing`: 日志追踪

### 被依赖模块
- `chatwidget.rs`: 调用 `run_commit_tick`

### 追踪日志目标
- `codex_tui::streaming::commit_tick`
- 日志内容：
  - `stream chunking mode transition`: 模式切换事件
  - 包含字段：`prior_mode`, `new_mode`, `queued_lines`, `oldest_queued_age_ms`, `entered_catch_up`

## 风险、边界与改进建议

### 风险点

1. **控制器生命周期**
   - 文档警告：如果传入过时的控制器引用，队列年龄可能被误读
   - 策略可能保持 CatchUp 模式比预期更长

2. **空控制器处理**
   - 当两个控制器都为 `None` 时，`has_controller` 为 `false`，`all_idle` 为 `true`
   - 调用方需要正确处理这种情况

3. **时间参数依赖**
   - `now` 参数由调用方提供，如果提供过时的时间戳会导致错误决策

### 边界条件

1. **CatchUpOnly 范围**
   - 当 scope 为 `CatchUpOnly` 且模式为 `Smooth` 时，返回默认输出（空 cells）
   - 这是预期的 opportunistic 行为

2. **部分控制器存在**
   - 支持只有一个控制器存在的情况
   - `all_idle` 初始为 `true`，使用 `&=` 累加

3. **Duration 比较**
   - `max_duration` 正确处理 `None` 情况，保留存在的值

### 改进建议

1. **错误处理增强**
   ```rust
   // 建议：添加控制器状态验证
   if stream_controller.is_none() && plan_stream_controller.is_none() {
       tracing::warn!("run_commit_tick called with no controllers");
   }
   ```

2. **性能指标收集**
   ```rust
   // 建议：添加性能指标
   pub(crate) struct CommitTickMetrics {
       pub tick_count: u64,
       pub mode_transitions: u64,
       pub total_cells_emitted: u64,
   }
   ```

3. **更细粒度的日志**
   ```rust
   // 建议：添加 tick 级别日志
   tracing::trace!(
       tick_scope = ?scope,
       drain_plan = ?decision.drain_plan,
       "stream chunking commit tick"
   );
   ```

4. **测试覆盖**
   - 当前没有单元测试
   - 建议添加：
     - 空控制器场景测试
     - 单控制器场景测试
     - 双控制器协调测试
     - CatchUpOnly 范围测试

5. **文档改进**
   - 添加更多关于 `now` 参数要求的文档
   - 说明控制器引用的生命周期要求
