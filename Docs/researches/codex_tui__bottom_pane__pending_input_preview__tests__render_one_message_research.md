# Pending Input Preview - Render One Message 研究报告

## 1. 场景与职责

### UI场景
该快照展示了 **Pending Input Preview** 组件在 **单条队列消息** 场景下的渲染效果。当用户在任务运行中输入了一条后续消息并按下 Tab 键将其加入队列时，系统会在底部显示该队列消息的预览。

### 组件职责
- **队列消息预览**: 预览用户已排队等待发送的消息
- **待处理引导**: 显示待处理（steer）消息的预览
- **编辑提示**: 提供编辑最后队列消息的快捷键提示
- **视觉区分**: 使用不同样式区分 steer 和队列消息

## 2. 功能点目的

### 核心功能
1. **队列消息展示**: 显示已排队的用户消息内容
2. **编辑提示**: 提示用户如何编辑最后一条队列消息
3. **视觉层次**: 使用缩进和符号区分不同层级
4. **宽度适配**: 自动换行适应不同终端宽度

### 用户体验目标
- 让用户了解已排队等待发送的消息
- 提供便捷的消息编辑入口
- 保持界面简洁不干扰当前任务

## 3. 具体技术实现

### 关键数据结构

```rust
/// 待处理输入预览
pub(crate) struct PendingInputPreview {
    pub pending_steers: Vec<String>,      // 待处理引导消息
    pub queued_messages: Vec<String>,     // 队列消息
    pub edit_binding: key_hint::KeyBinding, // 编辑快捷键
}

const PREVIEW_LINE_LIMIT: usize = 3;  // 每消息预览行数限制
```

### 渲染实现

```rust
impl PendingInputPreview {
    fn as_renderable(&self, width: u16) -> Box<dyn Renderable> {
        if (self.pending_steers.is_empty() && self.queued_messages.is_empty()) || width < 4 {
            return Box::new(());
        }
        
        let mut lines = vec![];
        
        // 渲染待处理 steer 消息
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
        
        // 渲染队列消息
        if !self.queued_messages.is_empty() {
            if !lines.is_empty() {
                lines.push(Line::from(""));
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
                    Line::from("    …".dim().italic())
                );
            }
        }
        
        // 添加编辑提示
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
}
```

### 渲染输出示例

```
Buffer {
    area: Rect { x: 0, y: 0, width: 40, height: 3 },
    content: [
        "• Queued follow-up messages             ",
        "  ↳ Hello, world!                       ",
        "    ⌥ + ↑ edit last queued message      ",
    ],
    styles: [
        // DIM 样式用于次要信息
        // ITALIC 样式用于队列消息内容
    ]
}
```

## 4. 关键代码路径与文件引用

### 主要源文件
| 文件路径 | 职责 |
|---------|------|
| `/home/sansha/Github/codex/codex-rs/tui/src/bottom_pane/pending_input_preview.rs` | PendingInputPreview 完整实现 |

### 关键代码路径

1. **渲染实现**:
   ```
   pending_input_preview.rs:69-133 -> as_renderable()
   ```

2. **行截断**:
   ```
   pending_input_preview.rs:48-58 -> push_truncated_preview_lines()
   ```

3. **节标题**:
   ```
   pending_input_preview.rs:60-67 -> push_section_header()
   ```

4. **高度计算**:
   ```
   pending_input_preview.rs:144-147 -> desired_height()
   ```

## 5. 依赖与外部交互

### 内部依赖

| 依赖模块 | 用途 |
|---------|------|
| `crate::wrapping::adaptive_wrap_lines` | 自适应文本换行 |
| `crate::wrapping::RtOptions` | 换行选项 |
| `crate::key_hint` | 快捷键提示 |
| `ratatui::widgets::Paragraph` | 段落渲染 |

### 外部交互

1. **编辑绑定设置**:
   ```rust
   pub(crate) fn set_edit_binding(&mut self, binding: key_hint::KeyBinding)
   ```
   - 允许上层设置编辑快捷键

2. **队列更新**:
   ```rust
   pub(crate) fn set_pending_input_preview(&mut self, queued: Vec<String>, pending_steers: Vec<String>)
   ```
   - 从 BottomPane 接收队列消息更新

## 6. 风险、边界与改进建议

### 潜在风险

1. **消息过长**:
   - 风险: 长消息可能占用过多屏幕空间
   - 缓解: 限制为 3 行并显示省略号

2. **多消息堆叠**:
   - 风险: 多条消息可能超出可用高度
   - 缓解: 考虑折叠或滚动

3. **快捷键冲突**:
   - 风险: 编辑快捷键可能与终端快捷键冲突
   - 缓解: 允许配置替代快捷键

### 边界情况

1. **空队列**:
   - 队列为空时返回空渲染（高度为 0）

2. **极窄终端**:
   - 宽度小于 4 时不渲染

3. **多行消息**:
   - 正确处理包含换行符的消息

### 改进建议

1. **消息计数**:
   - 建议: 显示队列消息数量（如"3 messages queued"）

2. **消息删除**:
   - 建议: 提供删除特定队列消息的快捷键

3. **消息重排**:
   - 建议: 支持调整队列消息顺序

4. **发送时机提示**:
   - 建议: 显示预计何时发送队列消息

5. **批量编辑**:
   - 建议: 支持批量编辑所有队列消息
