# 研究文档: render_two_messages

## 场景与职责

本快照测试验证消息队列（MessageQueue）在多条消息场景下的渲染效果。当用户连续输入多条消息时，系统需要正确显示所有消息的预览。

**核心场景**: 用户在任务运行期间连续输入多条后续问题，系统将这些消息排队并显示预览。

## 功能点目的

1. **多消息渲染**: 验证多条消息的正确显示
2. **消息分隔**: 确保消息之间有清晰的分隔
3. **样式一致性**: 所有消息使用一致的样式

## 具体技术实现

### 测试构造

```rust
#[test]
fn render_two_messages() {
    let mut queue = PendingInputPreview::new();
    queue.queued_messages.push("Hello, world!".to_string());
    queue
        .queued_messages
        .push("This is another message".to_string());
    let width = 40;
    let height = queue.desired_height(width);
    let mut buf = Buffer::empty(Rect::new(0, 0, width, height));
    queue.render(Rect::new(0, 0, width, height), &mut buf);
    assert_snapshot!("render_two_messages", format!("{buf:?}"));
}
```

### 消息渲染循环

```rust
if !self.queued_messages.is_empty() {
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
```

### 节标题添加

```rust
fn push_section_header(lines: &mut Vec<Line<'static>>, width: u16, header: Line<'static>) {
    let mut spans = vec!["• ".dim()];
    spans.extend(header.spans);
    lines.extend(adaptive_wrap_lines(
        std::iter::once(Line::from(spans)),
        RtOptions::new(width as usize).subsequent_indent(Line::from("  ".dim())),
    ));
}
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `pending_input_preview.rs:180-191` | 测试用例 `render_two_messages` |
| `pending_input_preview.rs:99-117` | 消息队列渲染循环 |
| `pending_input_preview.rs:60-66` | `push_section_header` 节标题 |

## 依赖与外部交互

### 快照显示效果（40字符宽度）

```
Buffer {
    area: Rect { x: 0, y: 0, width: 40, height: 3 },
    content: [
        "  ↳ Hello, world!                       ",  // 消息1
        "  ↳ This is another message             ",  // 消息2
        "    alt + ↑ edit                        ",  // 编辑提示
    ],
    styles: [
        // 消息1样式
        x: 0, y: 0, modifier: DIM,
        x: 4, y: 0, modifier: DIM | ITALIC,
        x: 17, y: 0, modifier: NONE,
        // 消息2样式
        x: 0, y: 1, modifier: DIM,
        x: 4, y: 1, modifier: DIM | ITALIC,
        x: 27, y: 1, modifier: NONE,
        // 编辑提示样式
        x: 0, y: 2, modifier: DIM,
        x: 16, y: 2, modifier: NONE,
    ]
}
```

### 布局结构

```
┌─────────────────────────────────────────┐
│  ↳ Hello, world!                        │  ← 消息1（暗淡斜体）
│  ↳ This is another message              │  ← 消息2（暗淡斜体）
│    alt + ↑ edit                         │  ← 编辑提示（暗淡）
└─────────────────────────────────────────┘
```

## 风险边界与改进建议

### 风险边界

1. **消息数量限制**: 未测试大量消息的渲染性能
2. **重复消息**: 相同内容的消息难以区分
3. **顺序混淆**: 消息顺序可能不够明显

### 改进建议

1. **消息编号**: 为消息添加编号便于引用
   ```
   "  ↳ [1] Hello, world!"
   "  ↳ [2] This is another message"
   ```

2. **时间戳**: 显示消息输入时间
   ```rust
   struct QueuedMessage {
       content: String,
       timestamp: Instant,
   }
   ```

3. **数量限制**: 限制显示的最大消息数，避免界面过长
   ```rust
   const MAX_DISPLAYED_MESSAGES: usize = 5;
   ```

### 相关测试

- `render_one_message`: 单消息基础测试
- `render_more_than_three_messages`: 超过3条消息的测试
- `render_wrapped_message`: 消息换行测试
