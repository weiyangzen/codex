# controller.rs 深入研究文档

## 场景与职责

`controller.rs` 实现了两种流控制器，负责管理流式 Markdown 内容的**接收、缓冲、渲染和显示**。它是流式输出系统的核心执行层，直接与 `MarkdownStreamCollector` 和 `StreamState` 交互。

### 控制器类型

| 控制器 | 用途 | 输出样式 |
|--------|------|----------|
| `StreamController` | 普通消息流（LLM 回复） | 标准消息格式，带 "• " 前缀 |
| `PlanStreamController` | 计划流（Proposed Plan） | 带样式的计划块，带 "• Proposed Plan" 标题 |

### 核心场景

1. **增量接收**：接收来自 LLM 的 delta 文本片段
2. **行完成检测**：检测换行符，将完成的行提交到队列
3. **动画显示**：通过 commit tick 逐步显示队列中的行
4. **最终确定**：流结束时刷新剩余内容

### 职责边界

| 职责 | 说明 |
|------|------|
| ✅ 管理流生命周期 | 创建、增量推送、最终确定 |
| ✅ 换行门控的 Markdown 收集 | 使用 `MarkdownStreamCollector` |
| ✅ 队列管理和 drain 操作 | 通过 `StreamState` |
| ✅ 生成 `HistoryCell` | 将渲染后的行包装为单元格 |
| ✅ 头部控制 | 跟踪头部是否已发出，控制格式 |
| ❌ 策略决策 | 委托给 `AdaptiveChunkingPolicy` |
| ❌ Tick 调度 | 由 `chatwidget.rs` 控制 |
| ❌ UI 直接操作 | 仅返回单元格，不直接修改 UI |

---

## 功能点目的

### 1. 换行门控（Newline-Gated Streaming）

核心机制：仅在检测到换行符时才将内容提交到显示队列。

```rust
pub(crate) fn push(&mut self, delta: &str) -> bool {
    state.collector.push_delta(delta);
    if delta.contains('\n') {
        let newly_completed = state.collector.commit_complete_lines();
        if !newly_completed.is_empty() {
            state.enqueue(newly_completed);
            return true; // 有新行可显示
        }
    }
    false
}
```

目的：
- 避免部分行提前显示导致的视觉闪烁
- 保持 Markdown 渲染的完整性（块级元素需要完整行）

### 2. 双模式 Drain 接口

支持两种 drain 模式以适应不同的分块策略：

```rust
// 单步模式：每 tick 一行
pub(crate) fn on_commit_tick(&mut self) -> (Option<Box<dyn HistoryCell>>, bool);

// 批量模式：catch-up 时使用
pub(crate) fn on_commit_tick_batch(&mut self, max_lines: usize) -> (Option<Box<dyn HistoryCell>>, bool);
```

返回元组：
- `Option<Box<dyn HistoryCell>>`：本次 drain 产生的单元格（可能为 None）
- `bool`：控制器是否空闲（队列已空）

### 3. 头部管理

两种控制器都跟踪头部发出状态：

- **`StreamController`**：使用 `header_emitted` 布尔值
  - 第一行显示 "• " 前缀
  - 后续行显示 "  " 前缀（缩进）

- **`PlanStreamController`**：使用 `header_emitted` 和 `top_padding_emitted`
  - 显示 "• Proposed Plan" 标题
  - 顶部和底部添加空行 padding
  - 应用 `proposed_plan_style()` 样式

### 4. 队列状态查询

为策略层提供队列状态信息：

```rust
pub(crate) fn queued_lines(&self) -> usize;
pub(crate) fn oldest_queued_age(&self, now: Instant) -> Option<Duration>;
```

---

## 具体技术实现

### 结构体定义

```rust
/// 普通消息流控制器
pub(crate) struct StreamController {
    state: StreamState,
    finishing_after_drain: bool,  // 标记是否在 drain 后完成
    header_emitted: bool,         // 头部是否已发出
}

/// 计划流控制器
pub(crate) struct PlanStreamController {
    state: StreamState,
    header_emitted: bool,
    top_padding_emitted: bool,    // 顶部 padding 是否已发出
}
```

### 核心方法流程

#### 1. 创建控制器

```rust
// StreamController::new
pub(crate) fn new(width: Option<usize>, cwd: &Path) -> Self {
    Self {
        state: StreamState::new(width, cwd),
        finishing_after_drain: false,
        header_emitted: false,
    }
}

// PlanStreamController::new
pub(crate) fn new(width: Option<usize>, cwd: &Path) -> Self {
    Self {
        state: StreamState::new(width, cwd),
        header_emitted: false,
        top_padding_emitted: false,
    }
}
```

#### 2. 推送 Delta

```rust
// StreamController::push (PlanStreamController 类似)
pub(crate) fn push(&mut self, delta: &str) -> bool {
    let state = &mut self.state;
    if !delta.is_empty() {
        state.has_seen_delta = true;
    }
    state.collector.push_delta(delta);
    if delta.contains('\n') {
        let newly_completed = state.collector.commit_complete_lines();
        if !newly_completed.is_empty() {
            state.enqueue(newly_completed);
            return true;
        }
    }
    false
}
```

#### 3. 最终确定（Finalize）

```rust
// StreamController::finalize
pub(crate) fn finalize(&mut self) -> Option<Box<dyn HistoryCell>> {
    // 1. 最终化收集器，获取剩余内容
    let remaining = {
        let state = &mut self.state;
        state.collector.finalize_and_drain()
    };
    
    // 2. 收集所有输出行
    let mut out_lines = Vec::new();
    {
        let state = &mut self.state;
        if !remaining.is_empty() {
            state.enqueue(remaining);
        }
        let step = state.drain_all();
        out_lines.extend(step);
    }
    
    // 3. 清理状态
    self.state.clear();
    self.finishing_after_drain = false;
    self.header_emitted = false;
    
    // 4. 发出单元格
    self.emit(out_lines)
}
```

#### 4. Commit Tick 处理

```rust
// StreamController::on_commit_tick
pub(crate) fn on_commit_tick(&mut self) -> (Option<Box<dyn HistoryCell>>, bool) {
    let step = self.state.step();        // drain 一行
    (self.emit(step), self.state.is_idle())
}

// StreamController::on_commit_tick_batch
pub(crate) fn on_commit_tick_batch(&mut self, max_lines: usize) -> (Option<Box<dyn HistoryCell>>, bool) {
    let step = self.state.drain_n(max_lines.max(1));  // drain N 行
    (self.emit(step), self.state.is_idle())
}
```

#### 5. 单元格发出（Emit）

```rust
// StreamController::emit
fn emit(&mut self, lines: Vec<Line<'static>>) -> Option<Box<dyn HistoryCell>> {
    if lines.is_empty() {
        return None;
    }
    Some(Box::new(history_cell::AgentMessageCell::new(lines, {
        let header_emitted = self.header_emitted;
        self.header_emitted = true;
        !header_emitted  // is_first_line
    })))
}

// PlanStreamController::emit (更复杂)
fn emit(&mut self, lines: Vec<Line<'static>>, include_bottom_padding: bool) -> Option<Box<dyn HistoryCell>> {
    if lines.is_empty() && !include_bottom_padding {
        return None;
    }

    let mut out_lines: Vec<Line<'static>> = Vec::new();
    let is_stream_continuation = self.header_emitted;
    
    // 添加标题
    if !self.header_emitted {
        out_lines.push(vec!["• ".dim(), "Proposed Plan".bold()].into());
        out_lines.push(Line::from(" "));
        self.header_emitted = true;
    }

    // 构建计划内容
    let mut plan_lines: Vec<Line<'static>> = Vec::new();
    if !self.top_padding_emitted {
        plan_lines.push(Line::from(" "));
        self.top_padding_emitted = true;
    }
    plan_lines.extend(lines);
    if include_bottom_padding {
        plan_lines.push(Line::from(" "));
    }

    // 应用样式和前缀
    let plan_style = proposed_plan_style();
    let plan_lines = prefix_lines(plan_lines, "  ".into(), "  ".into())
        .into_iter()
        .map(|line| line.style(plan_style))
        .collect::<Vec<_>>();
    out_lines.extend(plan_lines);

    Some(Box::new(history_cell::new_proposed_plan_stream(
        out_lines,
        is_stream_continuation,
    )))
}
```

---

## 关键代码路径与文件引用

### 模块内引用

| 文件 | 引用关系 | 说明 |
|------|----------|------|
| `mod.rs` | 被 `pub(crate) mod controller;` 导出 | 模块入口 |
| `commit_tick.rs` | `use super::controller::*` | 调用控制器方法 |

### 跨模块引用

| 文件 | 引用内容 | 用途 |
|------|----------|------|
| `chatwidget.rs:292-293` | `use crate::streaming::controller::{PlanStreamController, StreamController};` | 主窗口使用 |
| `chatwidget.rs:667, 669, 671` | 作为 `Chat` 结构体字段 | 持有控制器实例 |
| `chatwidget.rs:1599` | `PlanStreamController::new(...)` | 创建计划控制器 |
| `chatwidget.rs:3133` | `StreamController::new(...)` | 创建消息控制器 |
| `history_cell.rs` | `use crate::history_cell::{HistoryCell, AgentMessageCell, new_proposed_plan_stream};` | 输出类型 |
| `markdown_stream.rs` | `use super::StreamState;` | StreamState 定义在 mod.rs |
| `style.rs` | `use crate::style::proposed_plan_style;` | 计划块样式 |
| `line_utils.rs` | `use crate::render::line_utils::prefix_lines;` | 行前缀工具 |

### 依赖关系图

```
controller.rs
    ├── StreamState (mod.rs)
    │   └── MarkdownStreamCollector (markdown_stream.rs)
    ├── HistoryCell (history_cell.rs)
    │   ├── AgentMessageCell
    │   └── new_proposed_plan_stream
    ├── proposed_plan_style (style.rs)
    └── prefix_lines (line_utils.rs)
```

---

## 依赖与外部交互

### 标准库依赖

```rust
use std::path::Path;
use std::time::Duration;
use std::time::Instant;
```

### 外部 crate 依赖

```rust
use ratatui::prelude::Stylize;
use ratatui::text::Line;
```

### 内部模块依赖

| 模块 | 用途 |
|------|------|
| `StreamState` | 队列管理和状态维护 |
| `MarkdownStreamCollector` | Markdown 增量收集和渲染 |
| `AgentMessageCell` | 消息单元格类型 |
| `new_proposed_plan_stream` | 计划单元格构造器 |
| `proposed_plan_style` | 计划块背景样式 |
| `prefix_lines` | 为每行添加前缀 |

### 数据流

```
LLM Delta
    ↓
[push] → MarkdownStreamCollector
    ↓ (检测到换行)
commit_complete_lines()
    ↓
StreamState::enqueue(lines)
    ↓ (commit tick)
StreamState::step() / drain_n()
    ↓
emit(lines) → AgentMessageCell / ProposedPlanCell
    ↓
返回给 chatwidget 添加到历史记录
```

---

## 风险、边界与改进建议

### 已知风险

#### 1. 宽度计算偏差
- **风险**：`PlanStreamController` 在创建时计算宽度：`width.saturating_sub(4)`
- **问题**：如果终端宽度在流期间变化，渲染宽度可能不匹配
- **现状**：`chatwidget.rs` 的 `last_rendered_width` 提供当前宽度，但控制器创建后固定

#### 2. 部分行最终化
- **风险**：`finalize_and_drain()` 会在末尾添加临时换行符以强制渲染
- **影响**：如果原始内容没有以换行符结尾，最终化后会多出一个空行

#### 3. 头部状态不一致
- **风险**：`StreamController` 有 `finishing_after_drain` 字段但在代码中未被使用
- **代码**：
  ```rust
  finishing_after_drain: bool,  // 定义但从未读取
  ```

### 边界条件

| 场景 | 行为 |
|------|------|
| 空 delta 推送 | `has_seen_delta` 不变，不检测换行 |
| 无换行符的 delta | 缓冲但不提交，返回 false |
| 多个换行符的 delta | 提交所有完成的行 |
| finalize 时队列为空 | 返回 None（无单元格） |
| `max_lines=0` | `max_lines.max(1)` 确保至少 drain 一行 |
| 计划流空内容 | 如果 `include_bottom_padding=false` 返回 None |

### 测试覆盖

包含一个集成测试：

```rust
#[tokio::test]
async fn controller_loose_vs_tight_with_commit_ticks_matches_full() {
    // 验证流式渲染与完整渲染结果一致
    // 使用复杂的 Markdown 列表测试
}
```

测试内容：
- 模拟真实的 delta 序列（从会话日志提取）
- 比较流式渲染结果与完整渲染结果
- 验证松散列表（loose list）和紧凑列表（tight list）的正确处理

### 改进建议

#### 1. 移除未使用字段
`StreamController::finishing_after_drain` 从未被读取，建议移除：

```rust
// 当前
pub(crate) struct StreamController {
    state: StreamState,
    finishing_after_drain: bool,  // 未使用
    header_emitted: bool,
}

// 建议
pub(crate) struct StreamController {
    state: StreamState,
    header_emitted: bool,
}
```

#### 2. 动态宽度调整
当前宽度在创建时固定，可考虑：

```rust
impl StreamController {
    pub(crate) fn update_width(&mut self, width: Option<usize>) {
        self.state.collector.update_width(width);
    }
}
```

#### 3. 增加更多单元测试
建议添加：

```rust
#[test]
fn push_without_newline_does_not_enqueue() {
    // 验证无换行时不提交
}

#[test]
fn push_with_newline_enqueues_completed_lines() {
    // 验证换行时提交
}

#[test]
fn finalize_drains_remaining_content() {
    // 验证最终化刷新剩余内容
}

#[test]
fn header_emitted_tracks_correctly() {
    // 验证头部状态跟踪
}

#[test]
fn batch_drain_respects_max_lines() {
    // 验证批量 drain 限制
}
```

#### 4. 统一控制器接口
两个控制器有大量重复代码，可考虑提取 trait：

```rust
pub(crate) trait StreamController {
    fn push(&mut self, delta: &str) -> bool;
    fn finalize(&mut self) -> Option<Box<dyn HistoryCell>>;
    fn on_commit_tick(&mut self) -> (Option<Box<dyn HistoryCell>>, bool);
    fn on_commit_tick_batch(&mut self, max_lines: usize) -> (Option<Box<dyn HistoryCell>>, bool);
    fn queued_lines(&self) -> usize;
    fn oldest_queued_age(&self, now: Instant) -> Option<Duration>;
}
```

#### 5. 优化计划流样式
当前 `proposed_plan_style()` 使用与 `user_message_style()` 相同的背景色，可考虑差异化：

```rust
// style.rs
pub fn proposed_plan_style_for(terminal_bg: Option<(u8, u8, u8)>) -> Style {
    // 使用不同的背景色或边框样式
}
```

### 代码质量观察

- **优点**：
  - 清晰的职责分离（收集、队列、发出）
  - 对称的 `StreamController` 和 `PlanStreamController` API
  - 详尽的文档注释
  - 使用 `Line<'static>` 避免生命周期问题

- **潜在改进**：
  - `PlanStreamController::emit` 方法较长（~35 行），可分解为子函数
  - 两个控制器的 `push` 方法几乎相同，可提取共享逻辑
  - 缺少对 `has_seen_delta` 的读取使用（虽然被设置）
