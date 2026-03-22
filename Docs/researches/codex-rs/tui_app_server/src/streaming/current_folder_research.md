# TUI App Server Streaming 模块研究文档

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 模块定位

`codex-rs/tui_app_server/src/streaming` 是 TUI App Server 中负责**流式输出渲染与动画控制**的核心模块。它处理从 AI 模型接收到的增量文本流（streaming deltas），将其转换为可视化的终端输出，并通过自适应的动画策略平衡用户体验与性能。

### 核心职责

1. **流式文本收集与渲染**
   - 接收来自 AI 的增量文本片段（deltas）
   - 将 Markdown 格式的流式文本实时渲染为终端可显示的 `ratatui::text::Line`
   - 处理本地文件链接的相对路径解析（基于 session CWD）

2. **队列管理与行提交**
   - 维护一个 FIFO 队列存储待显示的行
   - 实现基于换行符的"门控"机制：只有完整的逻辑行才会被提交到队列
   - 记录每行入队时间戳，支持基于年龄的流控决策

3. **自适应分块动画策略**
   - **Smooth 模式**：基线行为，每 tick 显示一行，提供传统打字机效果
   - **CatchUp 模式**：当队列积压时，批量 drain 所有队列内容以快速收敛显示延迟
   - 通过滞回（hysteresis）机制防止模式频繁切换

4. **双控制器架构**
   - `StreamController`：处理普通 AI 消息流
   - `PlanStreamController`：处理"Proposed Plan"特殊格式的计划流

### 使用场景

| 场景 | 行为 |
|------|------|
| 正常对话 | Smooth 模式，逐行显示，提供自然阅读体验 |
| 代码块/长文本突发 | 检测到队列深度≥8 或最老行年龄≥120ms 时进入 CatchUp 模式 |
| 网络恢复后大量积压 | Severe backlog（≥64 行或≥300ms）绕过重入限制，立即进入 CatchUp |
| Plan 工具输出 | 使用 PlanStreamController，添加特殊标题样式和缩进 |

---

## 功能点目的

### 1. 流式渲染的核心问题

在 TUI 中直接显示原始流式文本会导致：
- **视觉抖动**：部分行频繁更新
- **Markdown 解析不一致**：增量解析可能产生与完整文本不同的渲染结果
- **性能问题**：每帧重新渲染整个缓冲区

### 2. 解决方案：Newline-Gated Commit

```
输入流: "Hello" -> " world" -> "!\n" -> "Next line\n"
         ↓           ↓          ↓            ↓
      缓冲区     缓冲区     检测到\n     检测到\n
      不提交     不提交    提交完整行   提交完整行
```

**关键设计**：只有遇到换行符时才将已完成的逻辑行提交到渲染队列。这保证了：
- 每行都是完整的 Markdown 解析单元
- 渲染结果与一次性渲染完整文本一致
- 队列中的行是稳定的，不会被后续 deltas 修改

### 3. 自适应动画的目的

| 问题 | 自适应策略的解决 |
|------|----------------|
| 固定速率跟不上突发流量 | CatchUp 模式批量 drain |
| 批量 drain 导致视觉跳跃 | 只在积压严重时进入 CatchUp |
| 频繁模式切换造成闪烁 | 滞回窗口（250ms hold）稳定状态 |
| 积压清除后过早回到 Smooth | 退出阈值低于进入阈值，防止振荡 |

### 4. 双控制器设计的目的

- **普通消息**（`StreamController`）：简洁的子弹头样式（"• "前缀）
- **计划消息**（`PlanStreamController`）：特殊格式化（"• Proposed Plan"标题，2空格缩进，dim 样式），使计划内容在视觉上与其他消息区分

---

## 具体技术实现

### 3.1 核心数据结构

#### `StreamState`（`mod.rs`）

```rust
pub(crate) struct StreamState {
    pub(crate) collector: MarkdownStreamCollector,  // Markdown 收集器
    queued_lines: VecDeque<QueuedLine>,             // 待显示行队列
    pub(crate) has_seen_delta: bool,                // 是否收到过内容
}

struct QueuedLine {
    line: Line<'static>,        // 渲染后的行
    enqueued_at: Instant,       // 入队时间戳（用于年龄计算）
}
```

**关键方法**：
- `enqueue(lines)`：批量入队，共享同一时间戳
- `step()`：弹出队列头部一行（Smooth 模式）
- `drain_n(max_lines)`：批量弹出最多 N 行（CatchUp 模式）
- `drain_all()`：清空队列（finalize 时使用）
- `oldest_queued_age(now)`：计算最老行的年龄

#### `MarkdownStreamCollector`（`markdown_stream.rs`）

```rust
pub(crate) struct MarkdownStreamCollector {
    buffer: String,                 // 原始文本缓冲区
    committed_line_count: usize,    // 已提交行数（用于增量渲染）
    width: Option<usize>,           // 终端宽度（用于换行）
    cwd: PathBuf,                   // 当前工作目录（用于文件链接）
}
```

**关键方法**：
- `push_delta(delta)`：追加增量文本到缓冲区
- `commit_complete_lines()`：检测缓冲区中已完成的行，渲染并返回新行
  - 找到最后一个 `\n` 的位置
  - 截取到该位置的文本进行 Markdown 渲染
  - 排除末尾的纯空白行
  - 只返回自上次提交以来的新行
- `finalize_and_drain()`：流结束时强制渲染剩余内容（即使无换行符）

#### `AdaptiveChunkingPolicy`（`chunking.rs`）

```rust
#[derive(Debug, Default)]
pub(crate) struct AdaptiveChunkingPolicy {
    mode: ChunkingMode,                          // 当前模式
    below_exit_threshold_since: Option<Instant>, // 低于退出阈值的开始时间
    last_catch_up_exit_at: Option<Instant>,      // 上次退出 CatchUp 的时间
}

pub(crate) enum ChunkingMode {
    Smooth,   // 基线模式
    CatchUp,  // 追赶模式
}

pub(crate) struct QueueSnapshot {
    pub(crate) queued_lines: usize,
    pub(crate) oldest_age: Option<Duration>,
}

pub(crate) enum DrainPlan {
    Single,       //  drain 一行
    Batch(usize), //  drain 多行
}
```

**决策流程**（`decide()` 方法）：

```
if queue empty:
    → Smooth, Single

if mode == Smooth:
    if should_enter_catch_up(snapshot):
        if reentry_hold_active(now) && !is_severe_backlog(snapshot):
            → 保持 Smooth（重入冷却中）
        else:
            → CatchUp, Batch(queued_lines)
    else:
        → Smooth, Single

if mode == CatchUp:
    if should_exit_catch_up(snapshot):
        if below_exit_threshold_since 已满 EXIT_HOLD:
            → Smooth, Single
        else:
            → 保持 CatchUp
    else:
        → 保持 CatchUp
```

**阈值常量**：

| 常量 | 值 | 说明 |
|------|-----|------|
| `ENTER_QUEUE_DEPTH_LINES` | 8 | 进入 CatchUp 的队列深度阈值 |
| `ENTER_OLDEST_AGE` | 120ms | 进入 CatchUp 的年龄阈值 |
| `EXIT_QUEUE_DEPTH_LINES` | 2 | 退出 CatchUp 的深度阈值 |
| `EXIT_OLDEST_AGE` | 40ms | 退出 CatchUp 的年龄阈值 |
| `EXIT_HOLD` | 250ms | 退出前需持续低于阈值的保持时间 |
| `REENTER_CATCH_UP_HOLD` | 250ms | 退出后防止立即重入的冷却时间 |
| `SEVERE_QUEUE_DEPTH_LINES` | 64 | 严重积压深度阈值（绕过冷却） |
| `SEVERE_OLDEST_AGE` | 300ms | 严重积压年龄阈值（绕过冷却） |

### 3.2 控制器实现

#### `StreamController`（`controller.rs`）

```rust
pub(crate) struct StreamController {
    state: StreamState,
    finishing_after_drain: bool,
    header_emitted: bool,  // 跟踪是否已发射消息头（用于缩进控制）
}
```

**关键方法**：
- `push(delta) -> bool`：推送增量，如果产生新队列行返回 true
- `finalize() -> Option<Box<dyn HistoryCell>>`：结束流，返回剩余内容
- `on_commit_tick() -> (Option<Cell>, bool)`：执行一次 tick，返回 (可能的单元格, 是否空闲)
- `on_commit_tick_batch(max_lines)`：批量 drain

**emit 逻辑**：
```rust
fn emit(&mut self, lines: Vec<Line>) -> Option<Box<dyn HistoryCell>> {
    if lines.is_empty() { return None; }
    Some(Box::new(AgentMessageCell::new(lines, !self.header_emitted)))
    // 第一行使用 "• " 前缀，后续行使用 "  " 缩进
}
```

#### `PlanStreamController`

与普通控制器类似，但 emit 时：
- 添加 "• Proposed Plan" 标题
- 添加顶部和底部 padding
- 应用 `proposed_plan_style()`（dim 样式）
- 所有行添加 2 空格前缀缩进

### 3.3 Commit Tick 编排（`commit_tick.rs`）

```rust
pub(crate) fn run_commit_tick(
    policy: &mut AdaptiveChunkingPolicy,
    stream_controller: Option<&mut StreamController>,
    plan_stream_controller: Option<&mut PlanStreamController>,
    scope: CommitTickScope,  // AnyMode 或 CatchUpOnly
    now: Instant,
) -> CommitTickOutput {
    // 1. 收集队列快照
    let snapshot = stream_queue_snapshot(stream, plan_stream, now);
    
    // 2. 请求策略决策
    let decision = resolve_chunking_plan(policy, snapshot, now);
    
    // 3. 如果 scope 限制为 CatchUpOnly 且当前不是 CatchUp，跳过
    if scope == CatchUpOnly && decision.mode != CatchUp {
        return CommitTickOutput::default();
    }
    
    // 4. 应用 drain plan
    apply_commit_tick_plan(decision.drain_plan, stream, plan_stream)
}
```

**队列快照计算**：
```rust
fn stream_queue_snapshot(stream, plan_stream, now) -> QueueSnapshot {
    let mut queued_lines = 0;
    let mut oldest_age: Option<Duration> = None;
    
    if let Some(c) = stream {
        queued_lines += c.queued_lines();
        oldest_age = max_duration(oldest_age, c.oldest_queued_age(now));
    }
    if let Some(c) = plan_stream {
        queued_lines += c.queued_lines();
        oldest_age = max_duration(oldest_age, c.oldest_queued_age(now));
    }
    
    QueueSnapshot { queued_lines, oldest_age }
}
```

### 3.4 与 ChatWidget 的集成

在 `chatwidget.rs` 中：

```rust
pub(crate) struct ChatWidget {
    adaptive_chunking: AdaptiveChunkingPolicy,
    stream_controller: Option<StreamController>,
    plan_stream_controller: Option<PlanStreamController>,
    // ...
}
```

**流生命周期**：

1. **流开始**（`handle_streaming_delta`）：
   ```rust
   if self.stream_controller.is_none() {
       self.stream_controller = Some(StreamController::new(width, &self.config.cwd));
   }
   if controller.push(&delta) {
       // 有新行产生，启动动画
       self.app_event_tx.send(AppEvent::StartCommitAnimation);
       self.run_catch_up_commit_tick();  // 立即尝试一次 catch-up
   }
   ```

2. **定期 tick**（`on_commit_tick`，由动画线程触发）：
   ```rust
   pub(crate) fn on_commit_tick(&mut self) {
       self.run_commit_tick();
   }
   ```

3. **Tick 处理**：
   ```rust
   fn run_commit_tick_with_scope(&mut self, scope: CommitTickScope) {
       let outcome = run_commit_tick(
           &mut self.adaptive_chunking,
           self.stream_controller.as_mut(),
           self.plan_stream_controller.as_mut(),
           scope,
           Instant::now(),
       );
       
       // 将 drain 出的 cells 添加到历史
       for cell in outcome.cells {
           self.add_boxed_history(cell);
       }
       
       // 如果所有控制器都空闲，停止动画
       if outcome.has_controller && outcome.all_idle {
           self.app_event_tx.send(AppEvent::StopCommitAnimation);
       }
   }
   ```

4. **流结束**（`handle_stream_finished`）：
   ```rust
   if let Some(controller) = self.stream_controller.take() {
       if let Some(cell) = controller.finalize() {
           self.add_boxed_history(cell);
       }
   }
   ```

---

## 关键代码路径与文件引用

### 4.1 模块文件结构

```
codex-rs/tui_app_server/src/streaming/
├── mod.rs           # StreamState 定义，队列管理基础
├── chunking.rs      # AdaptiveChunkingPolicy，模式决策
├── commit_tick.rs   # run_commit_tick 编排函数
└── controller.rs    # StreamController, PlanStreamController
```

### 4.2 关键代码路径

| 功能 | 文件 | 行号范围 | 函数/结构 |
|------|------|----------|-----------|
| 队列状态管理 | `mod.rs` | 30-103 | `StreamState` |
| Markdown 收集 | `markdown_stream.rs` | 9-107 | `MarkdownStreamCollector` |
| 策略决策 | `chunking.rs` | 155-262 | `AdaptiveChunkingPolicy::decide` |
| 进入 CatchUp 判断 | `chunking.rs` | 216-227 | `maybe_enter_catch_up` |
| 退出 CatchUp 判断 | `chunking.rs` | 233-250 | `maybe_exit_catch_up` |
| Tick 编排 | `commit_tick.rs` | 69-91 | `run_commit_tick` |
| 快照计算 | `commit_tick.rs` | 97-118 | `stream_queue_snapshot` |
| 普通流控制 | `controller.rs` | 15-113 | `StreamController` |
| Plan 流控制 | `controller.rs` | 116-246 | `PlanStreamController` |
| 历史单元格 | `history_cell.rs` | 445-477 | `AgentMessageCell` |
| Plan 单元格 | `history_cell.rs` | 241-245 | `new_proposed_plan_stream` |

### 4.3 调用链

```
动画线程触发
    ↓
ChatWidget::on_commit_tick
    ↓
ChatWidget::run_commit_tick
    ↓
commit_tick::run_commit_tick
    ├── stream_queue_snapshot  (收集两个控制器的队列状态)
    ├── resolve_chunking_plan  (请求策略决策)
    │   └── AdaptiveChunkingPolicy::decide
    │       ├── maybe_enter_catch_up
    │       └── maybe_exit_catch_up
    └── apply_commit_tick_plan
        ├── drain_stream_controller
        │   ├── StreamController::on_commit_tick
        │   └── StreamController::on_commit_tick_batch
        └── drain_plan_stream_controller
            ├── PlanStreamController::on_commit_tick
            └── PlanStreamController::on_commit_tick_batch
```

### 4.4 测试覆盖

| 测试文件 | 测试内容 |
|----------|----------|
| `streaming/mod.rs` | `drain_n_clamps_to_available_lines` |
| `streaming/chunking.rs` | 模式转换、滞回行为、严重积压绕过等 10+ 测试 |
| `streaming/controller.rs` | `controller_loose_vs_tight_with_commit_ticks_matches_full` |
| `markdown_stream.rs` | 块引用、列表、嵌套、换行、围栏代码块等 15+ 测试 |

---

## 依赖与外部交互

### 5.1 上游依赖（输入）

| 来源 | 数据 | 用途 |
|------|------|------|
| `ChatWidget::handle_streaming_delta` | `String` delta | 流式文本输入 |
| `ChatWidget::handle_plan_streaming_delta` | `String` delta | Plan 流式文本输入 |
| 动画线程（`app.rs`） | `CommitTick` 事件 | 定期触发 drain |
| `config.cwd` | `PathBuf` | 文件链接相对化 |
| `last_rendered_width` | `Option<usize>` | Markdown 换行宽度 |

### 5.2 下游依赖（输出）

| 目标 | 数据 | 触发条件 |
|------|------|----------|
| `ChatWidget::add_boxed_history` | `Box<dyn HistoryCell>` | 每次 drain 产生新行 |
| `AppEvent::StartCommitAnimation` | - | 首次产生队列行 |
| `AppEvent::StopCommitAnimation` | - | 所有队列为空 |
| `tracing` | 模式转换日志 | 模式变化时 |

### 5.3 外部模块依赖

| 模块 | 用途 |
|------|------|
| `markdown.rs` / `markdown_render.rs` | Markdown 到 `Line` 的渲染 |
| `render/line_utils.rs` | `prefix_lines`, `is_blank_line_spaces_only` |
| `history_cell.rs` | `AgentMessageCell`, `new_proposed_plan_stream` |
| `style.rs` | `proposed_plan_style()` |
| `ratatui::text::Line` | 终端行表示 |

### 5.4 crate 依赖

```toml
# Cargo.toml 关键依赖
ratatui = { features = ["scrolling-regions", "unstable-backend-writer", ...] }
tokio = { features = ["rt-multi-thread", "time", ...] }
tracing = { features = ["log"] }
```

---

## 风险、边界与改进建议

### 6.1 已知风险

#### 风险 1：Markdown 渲染一致性

**问题**：`MarkdownStreamCollector` 在每次 `commit_complete_lines()` 时重新渲染整个缓冲区。如果 `markdown::append_markdown` 的行为在多次调用间不一致（例如由于解析器状态），可能导致渲染错误。

**缓解**：
- 测试覆盖 `simulate_stream_markdown_for_tests` 验证流式渲染与完整渲染一致性
- 使用 `committed_line_count` 只返回新增行

**改进建议**：
- 考虑使用增量 Markdown 解析器避免重复渲染
- 添加更多模糊测试（fuzzing）覆盖边界情况

#### 风险 2：队列年龄计算准确性

**问题**：`oldest_queued_age` 基于 `Instant::now()` 计算，如果在两次 tick 之间有大量行入队，年龄计算可能不够精确。

**当前行为**：所有同时入队的行共享相同的时间戳。

**改进建议**：
- 对于极高精度需求，可以为每行记录独立时间戳
- 但当前设计已足够满足动画需求

#### 风险 3：宽度变化处理

**问题**：`StreamState` 在构造时固定 `width`，如果终端在流进行中调整大小，渲染宽度不会更新。

**代码位置**：`StreamController::new(width, cwd)` 只调用一次

**改进建议**：
- 添加 `set_width()` 方法支持动态调整
- 或在 finalize 时使用最新宽度重新渲染

#### 风险 4：双控制器竞争

**问题**：`stream_queue_snapshot` 将两个控制器的队列深度相加，但分别 drain。如果两个控制器同时有积压，CatchUp 模式会同时 drain 两者，可能导致视觉上的内容交错。

**当前行为**：`apply_commit_tick_plan` 顺序处理两个控制器。

**改进建议**：
- 考虑为不同流类型设置优先级
- 或添加交错控制逻辑

### 6.2 边界情况

| 场景 | 当前行为 | 注意事项 |
|------|----------|----------|
| 空 delta | `has_seen_delta` 保持 false | 不会触发提交 |
| 无换行符的长文本 | 缓冲到流结束或遇到 `\n` | finalize 时强制提交 |
| 大量空行 | `is_blank_line_spaces_only` 检测 | 末尾空白行被排除 |
| 极快速连续 deltas | CatchUp 模式批量处理 | 严重积压阈值 64 行/300ms |
| 流中断后恢复 | 新 `StreamController` 重新开始 | 历史状态通过 `header_emitted` 跟踪 |

### 6.3 性能考虑

1. **克隆开销**：`commit_complete_lines()` 克隆整个缓冲区进行渲染
   - 建议：对于大缓冲区，考虑使用 `rope` 数据结构

2. **渲染频率**：基线 tick 间隔约 8.3ms（120fps）
   - 在 Smooth 模式下，即使无新内容也会定期调用
   - 建议：可添加空闲时跳过逻辑

3. **内存使用**：`VecDeque<QueuedLine>` 在 CatchUp 模式下可能临时增长
   - 64 行严重积压阈值提供天然上限

### 6.4 改进建议

#### 建议 1：配置化阈值

当前所有阈值都是硬编码常量。建议添加配置支持：

```rust
// 在 Config 中添加
pub struct StreamingConfig {
    pub enter_queue_depth: usize,
    pub enter_oldest_age_ms: u64,
    pub exit_hold_ms: u64,
    // ...
}
```

#### 建议 2：更智能的批量 drain

当前 CatchUp 模式一次性 drain 所有队列行。对于极大积压（>1000 行），可考虑：

```rust
// 分帧 drain，避免单帧卡顿
const MAX_CATCHUP_LINES_PER_TICK: usize = 100;
```

#### 建议 3：流式 Markdown 解析器

当前使用 `pulldown-cmark` 完整重新渲染。考虑：
- 使用 `pulldown-cmark-to-cmark` 保持解析器状态
- 或切换到支持增量的 Markdown 解析器

#### 建议 4：观测性增强

当前只有模式转换日志。建议添加：
- 队列深度直方图指标
- 模式持续时间统计
- 每行平均等待时间

#### 建议 5：测试覆盖

- 添加终端宽度变化的集成测试
- 添加长时间运行的压力测试（模拟 10k+ 行流）
- 添加模糊测试验证 Markdown 渲染一致性

### 6.5 相关文档

| 文档 | 路径 | 内容 |
|------|------|------|
| Chunking Review | `docs/tui-stream-chunking-review.md` | 设计原理和运行时流程 |
| Chunking Tuning | `docs/tui-stream-chunking-tuning.md` | 阈值调优指南 |
| Chunking Validation | `docs/tui-stream-chunking-validation.md` | 验证流程和实验历史 |

---

## 总结

`streaming` 模块是 TUI App Server 中处理 AI 流式输出的核心组件。它通过以下设计实现了流畅的用户体验：

1. **Newline-gated commit**：确保渲染一致性和稳定性
2. **双模式动画**：Smooth 提供自然阅读体验，CatchUp 快速收敛延迟
3. **滞回控制**：防止模式频繁切换造成的视觉闪烁
4. **双控制器架构**：支持普通消息和 Plan 消息的差异化渲染

模块设计良好，测试覆盖充分，文档完整。主要改进空间在于配置化阈值、动态宽度支持和更高效的 Markdown 渲染。
