# pending_input_preview.rs 深入研究

## 场景与职责

`pending_input_preview.rs` 实现了 **PendingInputPreview** 组件，用于在聊天输入框上方显示两类待处理输入的预览：

1. **Pending Steers（待处理引导消息）**：将在下一个工具/结果边界后自动提交的消息
2. **Queued Messages（排队消息）**：用户在当前回合进行中时输入的后续消息

### 用户体验目标

- **透明度**：让用户了解哪些消息将在何时被提交
- **可控性**：提供 Esc 键立即中断并发送、Alt+Up 编辑排队消息的快捷方式
- **空间效率**：限制预览行数（最多 3 行），避免占用过多屏幕空间

### 架构定位

该组件是 `BottomPane` 的一部分，与 `ChatComposer` 和 `StatusIndicatorWidget` 协同工作，构成底部面板的完整交互界面。

---

## 功能点目的

### 1. 待处理引导消息预览

当用户发送引导消息（如 "请继续"、"检查上一个命令输出"）而当前有正在执行的工具调用时，这些消息会被暂存并在工具完成后自动提交。

**显示信息**：
- 提示文本："Messages to be submitted after next tool call"
- 操作提示："(press Esc to interrupt and send immediately)"
- 每条消息的缩略预览（最多 3 行）

### 2. 排队消息预览

当用户在一个回合进行中时输入了多条消息，这些消息会被排队等待当前回合完成后提交。

**显示信息**：
- 标题："Queued follow-up messages"
- 每条消息的缩略预览（斜体显示，最多 3 行）
- 编辑提示："Alt+Up edit last queued message"（可配置）

### 3. 自适应文本换行

使用 `adaptive_wrap_lines` 处理长文本，确保在窄屏幕上也能合理显示。

---

## 具体技术实现

### 核心数据结构

```rust
pub(crate) struct PendingInputPreview {
    pub pending_steers: Vec<String>,      // 待处理引导消息
    pub queued_messages: Vec<String>,     // 排队消息
    edit_binding: key_hint::KeyBinding,   // 编辑快捷键（默认可配置）
}

const PREVIEW_LINE_LIMIT: usize = 3;  // 每条消息最多显示行数
```

### 渲染流程

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

### 内部渲染逻辑

```rust
fn as_renderable(&self, width: u16) -> Box<dyn Renderable> {
    // 空状态优化
    if (self.pending_steers.is_empty() && self.queued_messages.is_empty()) || width < 4 {
        return Box::new(());
    }

    let mut lines = vec![];

    // 1. 渲染待处理引导消息部分
    if !self.pending_steers.is_empty() {
        Self::push_section_header(
            &mut lines,
            width,
            Line::from(vec![
                "Messages to be submitted after next tool call".into(),
                " (press ".dim(),
                key_hint::plain(KeyCode::Esc).into(),
                " to interrupt and send immediately)".dim(),
            ]),
        );

        for steer in &self.pending_steers {
            let wrapped = adaptive_wrap_lines(
                steer.lines().map(|line| Line::from(line.dim())),
                RtOptions::new(width as usize)
                    .initial_indent(Line::from("  ↳ ".dim()))
                    .subsequent_indent(Line::from("    ")),
            );
            Self::push_truncated_preview_lines(&mut lines, wrapped, Line::from("    …".dim()));
        }
    }

    // 2. 渲染排队消息部分
    if !self.queued_messages.is_empty() {
        if !lines.is_empty() {
            lines.push(Line::from(""));  // 分隔空行
        }
        Self::push_section_header(&mut lines, width, "Queued follow-up messages".into());

        for message in &self.queued_messages {
            let wrapped = adaptive_wrap_lines(
                message.lines().map(|line| Line::from(line.dim().italic())),
                RtOptions::new(width as usize)
                    .initial_indent(Line::from("  ↳ ".dim()))
                    .subsequent_indent(Line::from("    ")),
            );
            Self::push_truncated_preview_lines(
                &mut lines,
                wrapped,
                Line::from("    …".dim().italic()),
            );
        }
    }

    // 3. 编辑提示（仅当有排队消息时显示）
    if !self.queued_messages.is_empty() {
        lines.push(
            Line::from(vec![
                "    ".into(),
                self.edit_binding.into(),
                " edit last queued message".into(),
            ])
            .dim(),
        );
    }

    Paragraph::new(lines).into()
}
```

### 辅助方法

```rust
/// 截断预览行数，超过限制时添加省略行
fn push_truncated_preview_lines(
    lines: &mut Vec<Line<'static>>,
    wrapped: Vec<Line<'static>>,
    overflow_line: Line<'static>,
) {
    let wrapped_len = wrapped.len();
    lines.extend(wrapped.into_iter().take(PREVIEW_LINE_LIMIT));
    if wrapped_len > PREVIEW_LINE_LIMIT {
        lines.push(overflow_line);
    }
}

/// 添加带项目符号的章节标题
fn push_section_header(
    lines: &mut Vec<Line<'static>>,
    width: u16,
    header: Line<'static>,
) {
    let mut spans = vec!["• ".dim()];
    spans.extend(header.spans);
    lines.extend(adaptive_wrap_lines(
        std::iter::once(Line::from(spans)),
        RtOptions::new(width as usize).subsequent_indent(Line::from("  ".dim())),
    ));
}
```

---

## 关键代码路径与文件引用

### 核心实现文件

| 文件 | 职责 |
|------|------|
| `codex-rs/tui_app_server/src/bottom_pane/pending_input_preview.rs` | PendingInputPreview 组件实现 |
| `codex-rs/tui_app_server/src/bottom_pane/mod.rs` | BottomPane 集成，持有 PendingInputPreview 实例 |

### 依赖模块

| 模块 | 用途 |
|------|------|
| `crate::key_hint` | 快捷键提示渲染（如 "Esc", "Alt+Up"） |
| `crate::render::renderable::Renderable` | 渲染 trait 接口 |
| `crate::wrapping::{RtOptions, adaptive_wrap_lines}` | 自适应文本换行 |

### 集成点（BottomPane）

```rust
// 在 mod.rs 中
pub(crate) struct BottomPane {
    // ...
    pending_input_preview: PendingInputPreview,
    // ...
}

// 更新预览内容
fn update_pending_input(&mut self, steers: Vec<String>, queued: Vec<String>) {
    self.pending_input_preview.pending_steers = steers;
    self.pending_input_preview.queued_messages = queued;
}
```

### 快捷键配置

```rust
/// 设置编辑快捷键（用于终端不支持 Alt+Up 的情况）
pub(crate) fn set_edit_binding(&mut self, binding: key_hint::KeyBinding) {
    self.edit_binding = binding;
}
```

---

## 依赖与外部交互

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `crossterm::event::KeyCode` | 快捷键代码定义 |
| `ratatui::{buffer::Buffer, layout::Rect, style::Stylize, text::Line, widgets::Paragraph}` | TUI 渲染基础设施 |

### 内部模块依赖

| 模块 | 用途 |
|------|------|
| `crate::key_hint` | 快捷键绑定渲染 |
| `crate::render::renderable::Renderable` | 统一渲染接口 |
| `crate::wrapping` | URL 感知的自适应文本换行 |

### 样式约定

- **标题**：普通文本 + dim 修饰的提示
- **待处理引导**：dim 样式
- **排队消息**：dim + italic 样式
- **项目符号**："• " + dim
- **消息前缀**："  ↳ " + dim
- **省略号**：根据上下文使用 dim 或 dim+italic

---

## 风险、边界与改进建议

### 已知风险

1. **行数估算不准确**
   - `desired_height` 依赖 `as_renderable` 的计算，可能与实际渲染有细微差异
   - 极端窄宽度（<4）时直接返回空，可能丢失重要信息

2. **长 URL 处理**
   - 已有测试 `long_url_like_message_does_not_expand_into_wrapped_ellipsis_rows` 确保 URL 不会导致额外的省略行
   - 但极长 URL 仍可能导致单行溢出

3. **快捷键冲突**
   - Alt+Up 在某些终端中可能被拦截
   - 已通过 `set_edit_binding` 提供可配置性，但默认行为可能不适用于所有用户

### 边界条件

| 边界 | 处理 |
|------|------|
| 空列表 | 返回空渲染（高度 0） |
| 单条消息 | 标题 + 消息 + 编辑提示 |
| 多条消息 | 每条最多 3 行，超出显示省略号 |
| 多行消息 | 使用 ↳ 前缀，后续行缩进 |
| 极窄宽度（<4） | 返回空渲染 |

### 测试覆盖

模块包含快照测试（使用 `insta`）：
- `render_one_message`：单条排队消息渲染
- `render_two_messages`：多条消息渲染
- `render_more_than_three_messages`：超过 3 条消息的截断
- `render_wrapped_message`：长文本换行
- `render_many_line_message`：多行消息处理
- `long_url_like_message_does_not_expand_into_wrapped_ellipsis_rows`：URL 特殊处理
- `render_one_pending_steer`：待处理引导消息
- `render_pending_steers_above_queued_messages`：两部分同时显示
- `render_multiline_pending_steer_uses_single_prefix_and_truncates`：多行引导消息截断

### 改进建议

1. **动态行数限制**
   - 根据可用屏幕高度动态调整 `PREVIEW_LINE_LIMIT`
   - 在高分屏上显示更多内容

2. **交互增强**
   - 添加鼠标悬停提示显示完整消息
   - 支持点击排队消息直接编辑

3. **可访问性**
   - 为屏幕阅读器添加更详细的 ARIA 标签等效信息
   - 考虑色盲用户的样式区分

4. **性能优化**
   - 缓存 `as_renderable` 结果，避免每次渲染重新计算
   - 对于大量排队消息，考虑虚拟化渲染

5. **国际化**
   - 硬编码的英文提示需要国际化支持
   - 考虑不同语言的文本长度差异

### 相关文档

- `codex-rs/tui/styles.md`：TUI 样式约定
- `codex-rs/tui_app_server/src/wrapping.rs`：文本换行实现细节
