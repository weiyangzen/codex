# controller.rs 深度研究文档

## 场景与职责

`controller.rs` 实现了两个流控制器：`StreamController`（主流控制器）和 `PlanStreamController`（计划流控制器），负责管理基于换行符门控的流式内容、头部发射和提交动画。

### 核心场景
- **内容流式接收**：接收增量内容（delta），按换行符分割
- **行队列管理**：将完成的行加入队列，等待动画提交
- **动画提交**：按节奏逐行或批量提交内容到 UI
- **流结束处理**：最终化流，排空剩余内容

### 职责边界
**负责**：
- 接收增量内容并检测换行符
- 管理待显示行的 FIFO 队列
- 按节奏提交行到历史单元格
- 处理流的最终化

**不负责**：
- 决定提交节奏（由 `chunking.rs` 策略决定）
- 直接渲染到 UI（返回 `HistoryCell` 由调用方处理）
- Markdown 解析（委托给 `MarkdownStreamCollector`）

## 功能点目的

### 1. StreamController（主流控制器）
用于管理常规 AI 消息流：
- 接收 Markdown 增量内容
- 换行时提交完整行到队列
- 支持单步和批量提交
- 生成 `AgentMessageCell` 历史单元格

### 2. PlanStreamController（计划流控制器）
专门用于管理"提议计划"（Proposed Plan）流：
- 与 `StreamController` 类似的核心逻辑
- 生成带有特定样式的计划块
- 添加 "Proposed Plan" 头部和装饰性 padding
- 生成 `ProposedPlanStreamCell` 历史单元格

### 3. 头部发射管理
两个控制器都跟踪头部发射状态：
- 首次发射时添加头部（如 "• " 前缀）
- 后续发射标记为流延续
- 避免重复头部

## 具体技术实现

### 关键数据结构

```rust
/// 主流控制器
pub(crate) struct StreamController {
    state: StreamState,              // 流状态（收集器 + 队列）
    finishing_after_drain: bool,     // 排空后是否结束
    header_emitted: bool,            // 头部是否已发射
}

/// 计划流控制器
pub(crate) struct PlanStreamController {
    state: StreamState,
    header_emitted: bool,
    top_padding_emitted: bool,       // 顶部 padding 是否已发射
}
```

### StreamController 实现

#### 构造
```rust
pub(crate) fn new(width: Option<usize>, cwd: &Path) -> Self {
    Self {
        state: StreamState::new(width, cwd),
        finishing_after_drain: false,
        header_emitted: false,
    }
}
```

#### 推送增量内容
```rust
pub(crate) fn push(&mut self, delta: &str) -> bool {
    let state = &mut self.state;
    if !delta.is_empty() {
        state.has_seen_delta = true;
    }
    state.collector.push_delta(delta);
    
    // 包含换行符时提交完整行
    if delta.contains('\n') {
        let newly_completed = state.collector.commit_complete_lines();
        if !newly_completed.is_empty() {
            state.enqueue(newly_completed);
            return true; // 有新内容入队
        }
    }
    false
}
```

#### 最终化
```rust
pub(crate) fn finalize(&mut self) -> Option<Box<dyn HistoryCell>> {
    // 1. 最终化收集器
    let remaining = {
        let state = &mut self.state;
        state.collector.finalize_and_drain()
    };
    
    // 2. 收集所有输出
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
    
    // 4. 发射单元格
    self.emit(out_lines)
}
```

#### 单步提交（Smooth 模式）
```rust
pub(crate) fn on_commit_tick(&mut self) -> (Option<Box<dyn HistoryCell>>, bool) {
    let step = self.state.step();  // 排空一行
    (self.emit(step), self.state.is_idle())
}
```

#### 批量提交（CatchUp 模式）
```rust
pub(crate) fn on_commit_tick_batch(
    &mut self,
    max_lines: usize,
) -> (Option<Box<dyn HistoryCell>>, bool) {
    let step = self.state.drain_n(max_lines.max(1));
    (self.emit(step), self.state.is_idle())
}
```

#### 发射单元格
```rust
fn emit(&mut self, lines: Vec<Line<'static>>) -> Option<Box<dyn HistoryCell>> {
    if lines.is_empty() {
        return None;
    }
    Some(Box::new(history_cell::AgentMessageCell::new(lines, {
        let header_emitted = self.header_emitted;
        self.header_emitted = true;
        !header_emitted  // 返回是否首次发射
    })))
}
```

### PlanStreamController 实现

与 `StreamController` 核心逻辑类似，主要区别在于 `emit` 方法：

```rust
fn emit(
    &mut self,
    lines: Vec<Line<'static>>,
    include_bottom_padding: bool,
) -> Option<Box<dyn HistoryCell>> {
    if lines.is_empty() && !include_bottom_padding {
        return None;
    }

    let mut out_lines: Vec<Line<'static>> = Vec::new();
    let is_stream_continuation = self.header_emitted;
    
    // 添加头部
    if !self.header_emitted {
        out_lines.push(vec!["• ".dim(), "Proposed Plan".bold()].into());
        out_lines.push(Line::from(" "));
        self.header_emitted = true;
    }

    // 添加计划内容
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

### 公共查询接口

两个控制器都提供：
```rust
/// 返回当前队列深度
pub(crate) fn queued_lines(&self) -> usize {
    self.state.queued_len()
}

/// 返回最老行的年龄
pub(crate) fn oldest_queued_age(&self, now: Instant) -> Option<Duration> {
    self.state.oldest_queued_age(now)
}
```

## 关键代码路径与文件引用

### 本文件内关键函数

#### StreamController
- `new` (line 26-32): 构造
- `push` (line 35-49): 推送增量
- `finalize` (line 52-73): 最终化
- `on_commit_tick` (line 76-79): 单步提交
- `on_commit_tick_batch` (line 85-91): 批量提交
- `emit` (line 103-112): 发射单元格

#### PlanStreamController
- `new` (line 128-134): 构造
- `push` (line 137-151): 推送增量
- `finalize` (line 154-171): 最终化
- `on_commit_tick` (line 174-180): 单步提交
- `on_commit_tick_batch` (line 186-195): 批量提交
- `emit` (line 207-245): 发射单元格（带样式）

### 调用方

#### commit_tick.rs
- `drain_stream_controller` (line 180-188): 调用 `on_commit_tick`/`on_commit_tick_batch`
- `drain_plan_stream_controller` (line 194-202): 调用 Plan 版本的相同方法

#### chatwidget.rs
- 创建控制器 (line 3718-3721, 1979-1982):
  ```rust
  self.stream_controller = Some(StreamController::new(
      self.last_rendered_width.get().map(|w| w.saturating_sub(2)),
      &self.config.cwd,
  ));
  ```
- 推送内容：调用 `push` 方法
- 最终化：调用 `finalize` 方法

### 被调用方

#### StreamState (mod.rs)
- `StreamState::new`: 构造状态
- `StreamState::enqueue`: 入队行
- `StreamState::step`: 单步排空
- `StreamState::drain_n`: 批量排空
- `StreamState::drain_all`: 全量排空
- `StreamState::queued_len`: 队列深度
- `StreamState::oldest_queued_age`: 最老行年龄
- `StreamState::is_idle`: 是否空闲
- `StreamState::clear`: 清理状态

#### MarkdownStreamCollector
- `push_delta`: 推送增量
- `commit_complete_lines`: 提交完整行
- `finalize_and_drain`: 最终化并排空

#### history_cell.rs
- `AgentMessageCell::new`: 创建消息单元格
- `new_proposed_plan_stream`: 创建计划流单元格

#### line_utils.rs
- `prefix_lines`: 添加行前缀

#### style.rs
- `proposed_plan_style`: 获取计划样式

## 依赖与外部交互

### 依赖模块
- `std::path::Path`: 路径处理
- `std::time::{Duration, Instant}`: 时间类型
- `ratatui::text::Line`: 文本行类型
- `ratatui::prelude::Stylize`: 样式辅助

### 内部依赖
- `mod.rs`: `StreamState`
- `markdown_stream.rs`: `MarkdownStreamCollector`
- `history_cell.rs`: `HistoryCell` trait 和具体单元格类型
- `render/line_utils.rs`: `prefix_lines`
- `style.rs`: `proposed_plan_style`

### 测试
包含一个集成测试 `controller_loose_vs_tight_with_commit_ticks_matches_full`（line 272-395）：
- 测试松散 vs 紧凑列表项的流式处理
- 模拟真实场景的增量输入
- 验证流式输出与完整渲染结果一致

## 风险、边界与改进建议

### 风险点

1. **宽度计算**
   - 构造时传入的宽度用于 Markdown 渲染
   - 如果终端宽度变化，已排队的行不会重新换行

2. **CWD 快照**
   - 构造时快照当前工作目录
   - 如果会话中改变 CWD，文件链接渲染可能不一致

3. **头部状态**
   - `header_emitted` 状态在 `finalize` 后不重置
   - 依赖调用方重新创建控制器

4. **空内容处理**
   - `emit` 在空行时返回 `None`
   - 调用方需要正确处理 `None` 情况

### 边界条件

1. **空增量**
   - `push` 对空增量有特殊处理：设置 `has_seen_delta` 但不触发提交

2. **无换行符的增量**
   - 仅累积到缓冲区，不入队

3. **最终化时无内容**
   - `finalize` 可能返回 `None`（如果没有任何内容）

4. **批量提交上限**
   - `on_commit_tick_batch` 使用 `max(1)` 确保至少排空一行

### 改进建议

1. **动态宽度调整**
   ```rust
   // 建议：支持更新宽度
   pub(crate) fn update_width(&mut self, width: Option<usize>) {
       self.state.collector.update_width(width);
   }
   ```

2. **更精确的头部控制**
   ```rust
   // 建议：添加重置方法
   pub(crate) fn reset_header_state(&mut self) {
       self.header_emitted = false;
   }
   ```

3. **内容统计**
   ```rust
   // 建议：添加统计信息
   pub(crate) fn stats(&self) -> ControllerStats {
       ControllerStats {
           total_bytes_received: self.state.collector.total_bytes(),
           total_lines_emitted: self.state.total_lines_emitted(),
           queue_depth: self.state.queued_len(),
       }
   }
   ```

4. **测试增强**
   - 添加 `PlanStreamController` 的测试
   - 添加边界条件测试（空输入、单行长内容等）
   - 添加并发测试（多控制器协调）

5. **错误处理**
   - 当前 `finalize` 和 `push` 不返回错误
   - 考虑添加错误类型处理极端情况（如内存不足）

6. **性能优化**
   - `emit` 每次创建新的 `Vec` 和 `Box`
   - 考虑对象池减少分配（如果性能成为问题）
