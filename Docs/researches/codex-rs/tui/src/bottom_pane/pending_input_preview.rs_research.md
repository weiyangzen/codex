# pending_input_preview.rs 深度研究文档

## 场景与职责

`PendingInputPreview` 是 Codex TUI 底部面板中的一个**预览小部件**，用于显示两类待处理输入：

1. **Pending Steers（待处理引导消息）**：用户发送的引导消息，将在下一个工具/结果边界后提交
2. **Queued Messages（排队消息）**：用户在任务运行时输入的后续消息，排队等待发送

该组件的主要职责是：
- 向用户可视化当前待处理的输入状态
- 提供编辑提示（如 Alt+Up 编辑最后一条排队消息）
- 限制预览行数，避免占用过多屏幕空间

## 功能点目的

### 1. 待处理引导消息显示
- **场景**：用户发送消息时，如果当前正在执行工具调用，消息不会立即发送
- **目的**：告知用户消息将在何时发送，并提供 Esc 键立即发送的选项

### 2. 排队消息显示
- **场景**：用户在任务运行时输入多条后续消息
- **目的**：显示排队的消息列表，让用户知道输入已被记录

### 3. 编辑提示
- **功能**：显示按键提示（如 Alt+Up 或 Shift+Left）编辑最后一条排队消息
- **可配置性**：提示的按键绑定可根据终端类型调整

### 4. 行数限制与截断
- **限制**：每类消息最多显示 3 行预览
- **截断指示**：超过限制时显示 "..." 提示

## 具体技术实现

### 核心数据结构

```rust
pub(crate) struct PendingInputPreview {
    pub pending_steers: Vec<String>,      // 待处理引导消息
    pub queued_messages: Vec<String>,     // 排队消息
    edit_binding: key_hint::KeyBinding,   // 编辑提示显示的按键绑定
}

const PREVIEW_LINE_LIMIT: usize = 3;      // 每类消息的最大预览行数
```

### 渲染流程

```rust
fn as_renderable(&self, width: u16) -> Box<dyn Renderable> {
    // 1. 检查是否有内容可显示
    if (self.pending_steers.is_empty() && self.queued_messages.is_empty()) || width < 4 {
        return Box::new(());  // 空渲染
    }

    let mut lines = vec![];

    // 2. 渲染 Pending Steers 部分
    if !self.pending_steers.is_empty() {
        // 添加节标题："Messages to be submitted after next tool call"
        // 添加每条 steer 的预览（带 ↳ 前缀）
    }

    // 3. 渲染 Queued Messages 部分
    if !self.queued_messages.is_empty() {
        // 添加节标题："Queued follow-up messages"
        // 添加每条消息的预览（带 ↳ 前缀，斜体样式）
        // 添加编辑提示行
    }

    Paragraph::new(lines).into()
}
```

### 文本包装与缩进

使用 `adaptive_wrap_lines` 进行智能文本包装：

```rust
let wrapped = adaptive_wrap_lines(
    steer.lines().map(|line| Line::from(line.dim())),
    RtOptions::new(width as usize)
        .initial_indent(Line::from("  ↳ ".dim()))      // 首行缩进
        .subsequent_indent(Line::from("    ")),         // 后续行缩进
);
```

### 节标题包装

```rust
fn push_section_header(lines: &mut Vec<Line<'static>>, width: u16, header: Line<'static>) {
    let mut spans = vec!["• ".dim()];
    spans.extend(header.spans);
    lines.extend(adaptive_wrap_lines(
        std::iter::once(Line::from(spans)),
        RtOptions::new(width as usize)
            .subsequent_indent(Line::from("  ".dim())),
    ));
}
```

## 关键代码路径与文件引用

### 主要调用方

| 调用方 | 文件路径 | 用途 |
|--------|----------|------|
| `BottomPane` | `codex-rs/tui/src/bottom_pane/mod.rs` | 拥有并管理预览组件 |
| `ChatWidget` | `codex-rs/tui/src/chatwidget.rs` | 更新待处理输入状态 |

### 集成代码

**`bottom_pane/mod.rs` 中的定义：**
```rust
pub(crate) struct BottomPane {
    // ...
    /// Preview of pending steers and queued drafts shown above the composer.
    pending_input_preview: PendingInputPreview,
    // ...
}

impl BottomPane {
    pub fn new(params: BottomPaneParams) -> Self {
        Self {
            // ...
            pending_input_preview: PendingInputPreview::new(),
            // ...
        }
    }

    /// Update the pending-input preview shown above the composer.
    pub(crate) fn set_pending_input_preview(
        &mut self,
        queued: Vec<String>,
        pending_steers: Vec<String>,
    ) {
        self.pending_input_preview.pending_steers = pending_steers;
        self.pending_input_preview.queued_messages = queued;
        self.request_redraw();
    }

    /// Update the key hint shown next to queued messages.
    pub(crate) fn set_queued_message_edit_binding(&mut self, binding: KeyBinding) {
        self.pending_input_preview.set_edit_binding(binding);
        self.request_redraw();
    }
}
```

**`chatwidget.rs` 中的更新：**
```rust
// 在 pending_steers 或 queued_messages 变化时
self.bottom_pane.set_pending_input_preview(
    queued_messages,
    pending_steers,
);

// 根据终端类型设置编辑绑定
let binding = queued_message_edit_binding_for_terminal(terminal_name);
self.bottom_pane.set_queued_message_edit_binding(binding);
```

### 终端特定的编辑绑定

```rust
fn queued_message_edit_binding_for_terminal(terminal_name: TerminalName) -> KeyBinding {
    match terminal_name {
        // Apple Terminal、Warp、VSCode 集成终端拦截 Alt+Up
        TerminalName::AppleTerminal | TerminalName::WarpTerminal | TerminalName::VsCode => {
            key_hint::shift(KeyCode::Left)
        }
        // 其他终端使用更直观的 Alt+Up
        _ => key_hint::alt(KeyCode::Up),
    }
}
```

### 渲染实现

```rust
impl Renderable for PendingInputPreview {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        if area.is_empty() {
            return;
        }
        self.as_renderable(area.width).render(area, buf);
    }

    fn desired_height(&self, width: u16) -> u16 {
        self.as_renderable(width).desired_height(width)
    }
}
```

## 依赖与外部交互

### 依赖模块

| 模块 | 用途 |
|------|------|
| `crossterm::event::KeyCode` | 按键绑定定义 |
| `ratatui::{buffer::Buffer, layout::Rect, style::Stylize, text::Line, widgets::Paragraph}` | TUI 渲染 |
| `crate::key_hint` | 按键提示生成 |
| `crate::render::renderable::Renderable` | 可渲染 trait |
| `crate::wrapping::{RtOptions, adaptive_wrap_lines}` | 文本包装 |

### 样式约定

遵循 `codex-rs/tui/styles.md` 中的约定：

```rust
// 使用 Stylize trait 的简洁样式
"• ".dim()                           // 项目符号暗淡
"Messages to be submitted...".into() // 普通文本
line.dim()                           // steer 内容暗淡
line.dim().italic()                  // 排队消息斜体暗淡
"/agent".cyan().bold()               // 命令高亮
```

### 与 `ChatWidget` 的交互

1. **状态更新**：`ChatWidget` 在 `pending_steers` 或 `queued_messages` 变化时调用 `set_pending_input_preview`
2. **编辑绑定**：`ChatWidget` 根据检测到的终端类型设置适当的编辑按键提示
3. **编辑操作**：用户触发编辑时，`ChatWidget` 处理按键事件并将最后一条排队消息移回编辑器

## 风险、边界与改进建议

### 已知风险

1. **宽度不足**
   - 当 `width < 4` 时，组件返回空渲染
   - 在极窄终端中可能完全不显示待处理输入提示

2. **长消息截断**
   - 超过 3 行的消息被截断，用户可能不知道完整内容
   - 当前仅显示 "..." 提示，不提供展开功能

3. **编辑绑定冲突**
   - 某些终端拦截 Alt+Up，需要回退到 Shift+Left
   - 但 Shift+Left 在编辑器中有其他含义（选择），可能造成混淆

### 边界条件

| 场景 | 行为 |
|------|------|
| 无待处理输入 | 高度为 0，不渲染 |
| 仅 pending_steers | 显示 steer 部分，无编辑提示 |
| 仅 queued_messages | 显示消息部分和编辑提示 |
| 两者都有 | 中间添加空行分隔 |
| 消息超过 3 行 | 显示前 3 行和 "..." |
| 宽度 < 4 | 空渲染 |

### 测试覆盖

位于文件底部的测试模块使用 `insta` 进行快照测试：

| 测试名称 | 验证内容 |
|----------|----------|
| `desired_height_empty` | 空状态高度为 0 |
| `desired_height_one_message` | 单条消息高度计算 |
| `render_one_message` | 单条消息渲染快照 |
| `render_two_messages` | 多条消息渲染快照 |
| `render_more_than_three_messages` | 超过 3 条消息的截断行为 |
| `render_wrapped_message` | 长消息包装 |
| `render_many_line_message` | 多行消息渲染 |
| `long_url_like_message_does_not_expand_into_wrapped_ellipsis_rows` | URL 类消息不展开 |
| `render_one_pending_steer` | 单个 steer 渲染 |
| `render_pending_steers_above_queued_messages` | 两者同时显示 |
| `render_multiline_pending_steer_uses_single_prefix_and_truncates` | 多行 steer 截断 |

### 改进建议

1. **展开功能**
   - 添加按键（如 Enter 或 Space）展开截断的消息查看完整内容
   - 或提供悬停/工具提示显示完整内容

2. **消息计数**
   - 当消息超过 3 条时，显示具体计数（如 "... 还有 2 条消息"）

3. **删除功能**
   - 允许用户直接从预览中删除特定的排队消息
   - 添加 Delete 键支持

4. **重新排序**
   - 允许用户调整排队消息的顺序
   - 使用 Alt+Up/Down 或其他快捷键

5. **更好的编辑提示**
   - 考虑在提示中显示实际的消息预览（如 "Alt+Up 编辑 '请继续...'"）

6. **响应式宽度**
   - 在极窄终端中考虑垂直堆叠而非水平布局

### 相关文件

- `codex-rs/tui/src/bottom_pane/mod.rs`：BottomPane 容器
- `codex-rs/tui/src/chatwidget.rs`：状态更新和编辑绑定
- `codex-rs/tui/src/key_hint.rs`：按键提示生成
- `codex-rs/tui/src/wrapping.rs`：文本包装工具
- `codex-rs/tui/styles.md`：样式约定
