# Render Wrapped Message

## 1. 场景与职责 (Scene and Responsibility)

### 测试场景
Tests rendering of messages that need to be wrapped due to limited width.

### 组件职责
该快照测试针对 Codex TUI 的 **PendingInputPreview** 组件，负责验证：
- 长消息在窄宽度下的自动换行
- 首行和后续行的不同缩进
- 多条消息的换行处理

## 2. 功能点目的 (Feature Purpose)

### 测试目标
Validates that long messages are properly wrapped when the terminal width is limited.

### 验证要点
1. 第一条长消息被包装到两行
2. 首行有 "↳" 前缀，后续行有 4 空格缩进
3. 第二条短消息正常显示
4. 编辑提示正确显示

## 3. 具体技术实现 (Technical Implementation)

### 核心数据结构
```rust
const PREVIEW_LINE_LIMIT: usize = 3;  // 单条消息最大行数
```

### 测试数据
```rust
queue.queued_messages.push("This is a longer message that should be wrapped".to_string());
queue.queued_messages.push("This is another message".to_string());
```

### 渲染输出 (40x5)
```
• Queued follow-up messages
  ↳ This is a longer message that should
    be wrapped
  ↳ This is another message
    ⌥ + ↑ edit last queued message
```

### 关键算法
1. **文本包装**: 使用 `adaptive_wrap_lines()` 根据宽度自动换行
2. **缩进配置**:
   - 首行: `initial_indent` = "  ↳ " (2空格 + ↳ + 空格)
   - 后续行: `subsequent_indent` = "    " (4空格)

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 源文件
- **主文件**: `codex-rs/tui/src/bottom_pane/pending_input_preview.rs`

### 关键代码段
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

### 测试代码位置
```rust
#[test]
fn render_wrapped_message() {
    let mut queue = PendingInputPreview::new();
    queue.queued_messages.push("This is a longer message that should be wrapped".to_string());
    queue.queued_messages.push("This is another message".to_string());
    let width = 40;
    let height = queue.desired_height(width);
    let mut buf = Buffer::empty(Rect::new(0, 0, width, height));
    queue.render(Rect::new(0, 0, width, height), &mut buf);
    assert_snapshot!("render_wrapped_message", format!("{buf:?}"));
}
```

## 5. 依赖与外部交互 (Dependencies)

### 外部 Crates
| Crate | 用途 |
|-------|------|
| `ratatui` | TUI 渲染框架 |
| `insta` | 快照测试框架 |

### 内部模块依赖
- `crate::wrapping::{RtOptions, adaptive_wrap_lines}` - 文本包装

## 6. 风险、边界与改进建议 (Risks, Edge Cases, Improvements)

### 潜在风险
1. **URL 类文本**: 长 URL 可能导致不理想的换行
2. **宽字符**: CJK 字符的宽度计算

### 边界情况
| 场景 | 行为 |
|------|------|
| 正好适应宽度 | 不换行 |
| 超长单词 | 可能超出边界或被强制断开 |
| 多行消息 | 每行独立包装 |

### 改进建议
1. **URL 特殊处理**: URL 类文本使用不同换行策略
2. **断词优化**: 考虑使用更智能的断词算法
3. **测试覆盖**: 添加 CJK 字符、emoji 的测试

### 相关文档
- `Docs/researches/codex-rs/tui/src/bottom_pane/pending_input_preview.rs_research.md`
- `codex-rs/tui/src/wrapping.rs` - 文本包装实现
