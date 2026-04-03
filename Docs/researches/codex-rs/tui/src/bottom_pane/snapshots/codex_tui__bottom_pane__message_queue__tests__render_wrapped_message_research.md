# 研究文档: render_wrapped_message

## 场景与职责

本快照测试验证消息队列（MessageQueue）在消息需要自动换行时的渲染效果。当消息内容超过可用宽度时，系统需要正确换行显示。

**核心场景**: 用户输入较长的消息，在窄终端窗口中需要自动换行显示。

## 功能点目的

1. **自动换行**: 消息内容超过宽度时自动换行
2. **缩进保持**: 换行后的续行保持适当的缩进
3. **多消息处理**: 多个消息各自独立换行

## 具体技术实现

### 测试构造

```rust
#[test]
fn render_wrapped_message() {
    let mut queue = PendingInputPreview::new();
    queue
        .queued_messages
        .push("This is a longer message that should be wrapped".to_string());
    queue
        .queued_messages
        .push("This is another message".to_string());
    let width = 40;
    let height = queue.desired_height(width);
    let mut buf = Buffer::empty(Rect::new(0, 0, width, height));
    queue.render(Rect::new(0, 0, width, height), &mut buf);
    assert_snapshot!("render_wrapped_message", format!("{buf:?}"));
}
```

### 自适应换行

```rust
use crate::wrapping::adaptive_wrap_lines;
use crate::wrapping::RtOptions;

let wrapped = adaptive_wrap_lines(
    message.lines().map(|line| Line::from(line.dim().italic())),
    RtOptions::new(width as usize)
        .initial_indent(Line::from("  ↳ ".dim()))      // 首行缩进
        .subsequent_indent(Line::from("    ")),        // 续行缩进
);
```

### 换行选项

```rust
// RtOptions 配置
RtOptions::new(width as usize)
    .initial_indent(Line::from("  ↳ ".dim()))      // 第一行前缀
    .subsequent_indent(Line::from("    "))          // 后续行前缀
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `pending_input_preview.rs:214-227` | 测试用例 `render_wrapped_message` |
| `wrapping.rs` | `adaptive_wrap_lines` 实现 |
| `pending_input_preview.rs:105-117` | 消息换行渲染 |

## 依赖与外部交互

### 快照显示效果（40字符宽度）

```
Buffer {
    area: Rect { x: 0, y: 0, width: 40, height: 4 },
    content: [
        "  ↳ This is a longer message that should",  // 消息1第1行
        "    be wrapped                          ",  // 消息1第2行（续行）
        "  ↳ This is another message             ",  // 消息2（未换行）
        "    alt + ↑ edit                        ",  // 编辑提示
    ],
    styles: [
        // 消息1第1行
        x: 0, y: 0, modifier: DIM,
        x: 4, y: 0, modifier: DIM | ITALIC,
        x: 0, y: 1, modifier: NONE,  // 续行无前缀
        x: 4, y: 1, modifier: DIM | ITALIC,
        x: 14, y: 1, modifier: NONE,
        // ...
    ]
}
```

### 换行效果分析

消息1: "This is a longer message that should be wrapped"
- 40字符宽度，减去前缀 "  ↳ "（4字符），可用36字符
- "This is a longer message that should" = 36字符，刚好
- "be wrapped" = 10字符，续行显示

### 缩进对比

| 行类型 | 前缀 | 效果 |
|--------|------|------|
| 首行 | "  ↳ " | 带箭头指示 |
| 续行 | "    " | 纯空格对齐 |

## 风险边界与改进建议

### 风险边界

1. **单词截断**: 当前实现可能在单词中间截断
2. **URL处理**: 长URL可能导致不美观的换行
3. **CJK字符**: 中日韩宽字符的换行可能不准确

### 改进建议

1. **单词边界换行**: 使用 `textwrap` 的 word-aware 换行
   ```rust
   use textwrap::Options;
   let options = Options::new(width).word_splitter(textwrap::WordSplitter::NoHyphenation);
   ```

2. **URL特殊处理**: 检测到URL时使用特殊换行策略
   ```rust
   fn wrap_message(message: &str, width: usize) -> Vec<String> {
       if looks_like_url(message) {
           vec![truncate_with_ellipsis(message, width)]
       } else {
           textwrap::wrap(message, width)
       }
   }
   ```

3. **宽字符支持**: 使用 `unicode-width` 计算显示宽度
   ```rust
   use unicode_width::UnicodeWidthStr;
   let display_width = text.width();
   ```

### 相关测试

- `long_url_like_message_does_not_expand_into_wrapped_ellipsis_rows`: URL特殊处理
- `render_many_line_message`: 多行消息截断测试
