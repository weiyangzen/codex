# 研究文档: render_many_line_message

## 场景与职责

本快照测试验证消息队列（MessageQueue）在多行消息场景下的渲染效果。当用户输入包含换行符的多行消息时，界面需要正确显示并处理行数限制。

**核心场景**: 用户粘贴或输入多行文本作为消息，系统需要预览并可能截断显示。

## 功能点目的

1. **多行消息渲染**: 正确处理包含换行符的消息
2. **行数限制**: 限制预览显示的行数，避免占用过多空间
3. **截断提示**: 当消息被截断时显示省略号提示

## 具体技术实现

### 消息队列渲染

```rust
// pending_input_preview.rs 或 message_queue.rs
fn render_many_line_message() {
    let mut queue = PendingInputPreview::new();
    queue
        .queued_messages
        .push("This is\na message\nwith many\nlines".to_string());
    // ...
}
```

### 行数限制处理

```rust
const PREVIEW_LINE_LIMIT: usize = 3;  // 最多显示3行

fn push_truncated_preview_lines(
    lines: &mut Vec<Line<'static>>,
    wrapped: Vec<Line<'static>>,
    overflow_line: Line<'static>,
) {
    let wrapped_len = wrapped.len();
    lines.extend(wrapped.into_iter().take(PREVIEW_LINE_LIMIT));
    if wrapped_len > PREVIEW_LINE_LIMIT {
        lines.push(overflow_line);  // 添加 "..." 提示
    }
}
```

### 换行处理

```rust
let wrapped = adaptive_wrap_lines(
    message.lines().map(|line| Line::from(line.dim().italic())),
    RtOptions::new(width as usize)
        .initial_indent(Line::from("  ↳ ".dim()))
        .subsequent_indent(Line::from("    ")),
);
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `pending_input_preview.rs:229-240` | 测试用例 `render_many_line_message` |
| `pending_input_preview.rs:48-58` | `push_truncated_preview_lines` 截断处理 |
| `wrapping.rs` | `adaptive_wrap_lines` 自适应换行 |

## 依赖与外部交互

### 快照显示效果（40字符宽度）

```
Buffer {
    area: Rect { x: 0, y: 0, width: 40, height: 5 },
    content: [
        "  ↳ This is                             ",  // 第1行
        "    a message                           ",  // 第2行
        "    with many                           ",  // 第3行（限制）
        "    …                                   ",  // 省略号提示
        "    alt + ↑ edit                        ",  // 编辑提示
    ],
    styles: [
        // DIM 样式应用于前缀和消息内容
        // ITALIC 样式应用于消息文本
    ]
}
```

### 样式应用

- **前缀 "↳"**: 暗淡 (`DIM`)
- **消息内容**: 暗淡 + 斜体 (`DIM | ITALIC`)
- **省略号**: 暗淡 + 斜体
- **编辑提示**: 暗淡

## 风险边界与改进建议

### 风险边界

1. **信息截断**: 只显示前3行，用户可能看不到完整消息
2. **换行符丢失**: 渲染后无法区分原始换行和自动换行
3. **编辑困难**: 多行消息的编辑体验可能不佳

### 改进建议

1. **展开功能**: 允许用户展开查看完整消息
   ```rust
   if message.lines().count() > PREVIEW_LINE_LIMIT {
       show_expand_button = true;
   }
   ```

2. **行号显示**: 显示行号帮助用户定位
   ```
   "  ↳ 1. This is"
   "    2. a message"
   ```

3. **智能截断**: 截断时保留首尾，省略中间
   ```rust
   fn smart_truncate(lines: &[&str], limit: usize) -> Vec<&str> {
       if lines.len() <= limit { return lines.to_vec(); }
       let head = limit / 2;
       let tail = limit - head - 1;
       // 返回 head + ["..."] + tail
   }
   ```

### 相关测试

- `render_one_message`: 单行消息基础测试
- `render_wrapped_message`: 自动换行测试
- `long_url_like_message_does_not_expand_into_wrapped_ellipsis_rows`: URL特殊处理
