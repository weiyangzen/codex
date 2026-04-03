# render_more_than_three_messages Snapshot 研究文档

## 场景与职责

本快照测试展示了 `PendingInputPreview` 组件处理**超过三条排队消息**时的渲染行为。当用户连续排队多条消息时，组件会显示所有消息（不截断消息数量），但每条消息仍受 `PREVIEW_LINE_LIMIT` 限制。

**典型使用场景**：
- 用户快速连续发送多条问题或指令
- 批量操作场景下积累多个待处理消息
- 需要查看完整的消息队列概览

## 功能点目的

该测试验证以下核心功能：

1. **多消息显示**：正确渲染四条排队消息
2. **消息前缀一致性**：每条消息以 `"  ↳ "` 前缀标识
3. **编辑提示**：在队列底部显示 `"⌥ + ↑ edit last queued message"` 提示
4. **视觉分隔**：通过缩进和样式区分不同消息

**渲染输出特征**：
```
• Queued follow-up messages             <- 标题（dim 样式）
  ↳ Hello, world!                       <- 消息 1（dim + italic）
  ↳ This is another message             <- 消息 2（dim + italic）
  ↳ This is a third message             <- 消息 3（dim + italic）
  ↳ This is a fourth message            <- 消息 4（dim + italic）
    ⌥ + ↑ edit last queued message      <- 编辑提示（dim 样式）
```

## 具体技术实现

### 消息迭代渲染
```rust
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
```

### 编辑提示渲染
```rust
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
```

### 高度计算
```rust
fn desired_height_one_message() {
    assert_eq!(queue.desired_height(40), 3);  // 标题 + 消息 + 提示
}
```

## 关键代码路径与文件引用

### 主要文件
- `codex-rs/tui_app_server/src/bottom_pane/pending_input_preview.rs` - PendingInputPreview 组件实现

### 关键函数
| 函数 | 行号 | 职责 |
|------|------|------|
| `render_more_than_three_messages` (test) | 194-211 | 本测试用例 |
| `as_renderable()` | 69-132 | 主渲染逻辑 |
| `push_truncated_preview_lines()` | 48-58 | 单条消息行数限制 |

### 测试数据
```rust
queue.queued_messages.push("Hello, world!".to_string());
queue.queued_messages.push("This is another message".to_string());
queue.queued_messages.push("This is a third message".to_string());
queue.queued_messages.push("This is a fourth message".to_string());
```

## 依赖与外部交互

### 依赖模块
- `crate::wrapping::adaptive_wrap_lines` - 自适应文本换行
- `crate::key_hint` - 键盘快捷键提示（默认 Alt+Up）
- `ratatui::text::Line` / `ratatui::widgets::Paragraph` - UI 渲染

### 快捷键绑定
```rust
edit_binding: key_hint::alt(KeyCode::Up),  // 默认 ⌥ + ↑
```

## 风险、边界与改进建议

### 当前边界情况
1. **消息数量无限制**：当前实现显示所有消息，可能导致极高面板
2. **总高度计算**：每条消息独立计算换行，总高度 = 标题 + Σ(每条消息高度) + 提示
3. **宽度一致性**：所有消息使用相同的 40 字符宽度

### 潜在风险
1. **极端消息数量**：如果用户排队 100 条消息，面板将非常高
2. **性能问题**：大量消息可能导致渲染延迟
3. **视觉混乱**：消息之间缺乏明显分隔，难以快速区分

### 改进建议
1. **消息数量限制**：添加 `MAX_QUEUED_MESSAGES_DISPLAY` 限制显示数量
2. **滚动支持**：当消息过多时提供滚动功能
3. **消息计数器**：在标题后显示 `"(4 messages)"`
4. **消息分隔线**：在消息之间添加空行或分隔符提高可读性
5. **批量操作**：支持多选删除或重新排序消息
