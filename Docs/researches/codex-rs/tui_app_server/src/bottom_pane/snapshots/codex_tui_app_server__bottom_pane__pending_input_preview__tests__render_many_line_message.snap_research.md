# render_many_line_message Snapshot 研究文档

## 场景与职责

本快照测试展示了 `PendingInputPreview` 组件处理**多行内容消息**时的渲染行为。当用户输入包含换行符的多行消息时，组件需要正确显示这些消息，同时遵守 `PREVIEW_LINE_LIMIT = 3` 的行数限制，并在超出时显示省略号。

**典型使用场景**：
- 用户粘贴包含多行文本的待发送消息
- 用户在输入框中输入了带换行的长文本后按 Enter 排队
- 需要预览多行内容但受限于底部面板空间

## 功能点目的

该测试验证以下核心功能：

1. **多行消息解析**：正确解析包含 `\n` 的消息内容为多行
2. **行数限制**：当消息行数超过 `PREVIEW_LINE_LIMIT`（3行）时截断
3. **省略号提示**：使用 `…` 字符表示内容被截断
4. **视觉层级**：通过缩进区分标题、消息内容和操作提示

**渲染输出特征**：
```
• Queued follow-up messages             <- 标题（dim 样式）
  ↳ This is                             <- 第一行（dim + italic）
    a message                           <- 续行（dim + italic）
    with many                           <- 续行（dim + italic）
    …                                   <- 截断提示（dim + italic）
    ⌥ + ↑ edit last queued message      <- 编辑提示（dim 样式）
```

## 具体技术实现

### 行数限制逻辑
```rust
const PREVIEW_LINE_LIMIT: usize = 3;

fn push_truncated_preview_lines(
    lines: &mut Vec<Line<'static>>,
    wrapped: Vec<Line<'static>>,
    overflow_line: Line<'static>,
) {
    let wrapped_len = wrapped.len();
    lines.extend(wrapped.into_iter().take(PREVIEW_LINE_LIMIT));
    if wrapped_len > PREVIEW_LINE_LIMIT {
        lines.push(overflow_line);  // 添加 "    …"
    }
}
```

### 文本换行处理
使用 `adaptive_wrap_lines` 函数处理文本换行：
```rust
let wrapped = adaptive_wrap_lines(
    message.lines().map(|line| Line::from(line.dim().italic())),
    RtOptions::new(width as usize)
        .initial_indent(Line::from("  ↳ ".dim()))
        .subsequent_indent(Line::from("    ")),
);
```

### 样式应用
- **标题行**：`"• "` 前缀使用 `DIM` 样式
- **消息内容**：`DIM | ITALIC` 组合样式
- **省略号**：`"    …"` 使用 `DIM | ITALIC`
- **编辑提示**：`"    ⌥ + ↑ edit last queued message"` 使用 `DIM`

## 关键代码路径与文件引用

### 主要文件
- `codex-rs/tui_app_server/src/bottom_pane/pending_input_preview.rs` - PendingInputPreview 组件实现

### 关键函数
| 函数 | 行号 | 职责 |
|------|------|------|
| `PendingInputPreview::new()` | 33-39 | 创建空预览组件 |
| `push_truncated_preview_lines()` | 48-58 | 截断预览行逻辑 |
| `push_section_header()` | 60-67 | 渲染节标题 |
| `as_renderable()` | 69-132 | 主渲染逻辑 |
| `render_many_line_message` (test) | 230-239 | 本测试用例 |

### 渲染流程
1. 测试创建包含 4 行文本的消息：`"This is\na message\nwith many\nlines"`
2. 调用 `desired_height(40)` 计算所需高度（6行）
3. 调用 `render()` 执行渲染
4. 验证输出包含：标题 + 3行内容 + 省略号 + 编辑提示

## 依赖与外部交互

### 依赖模块
- `crate::wrapping::adaptive_wrap_lines` - 自适应文本换行
- `crate::wrapping::RtOptions` - 换行选项配置
- `crate::key_hint` - 键盘快捷键提示
- `ratatui::text::Line` / `ratatui::widgets::Paragraph` - UI 渲染

### 数据结构
```rust
pub(crate) struct PendingInputPreview {
    pub pending_steers: Vec<String>,      // 待处理的 steer 消息
    pub queued_messages: Vec<String>,     // 排队的用户消息
    edit_binding: key_hint::KeyBinding,   // 编辑快捷键绑定（默认 Alt+Up）
}
```

## 风险、边界与改进建议

### 当前边界情况
1. **行数计算**：测试消息有 4 行，正好触发截断逻辑
2. **宽度限制**：测试使用 40 字符宽度，较窄的宽度可能导致单行被进一步换行
3. **样式一致性**：所有消息内容统一使用 `dim().italic()`，无法区分不同消息

### 潜在风险
1. **长 URL 处理**：如 `long_url_like_message_does_not_expand_into_wrapped_ellipsis_rows` 测试所示，URL 类长文本可能导致意外换行
2. **多消息混合**：当同时存在 `pending_steers` 和 `queued_messages` 时，总高度计算需要精确
3. **中文字符宽度**：当前实现可能未正确处理双宽度字符的截断

### 改进建议
1. **可配置行数限制**：将 `PREVIEW_LINE_LIMIT` 改为可配置参数
2. **展开/折叠功能**：添加交互式展开完整内容的快捷键
3. **消息计数提示**：在截断时显示 `"… 还有 N 行"` 而非单纯的省略号
4. **性能优化**：对于极长消息，考虑延迟加载或虚拟渲染
