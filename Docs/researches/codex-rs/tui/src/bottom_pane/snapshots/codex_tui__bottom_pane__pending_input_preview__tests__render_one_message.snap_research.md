# Render One Message

## 1. 场景与职责 (Scene and Responsibility)

### 测试场景
Tests rendering of a single queued message with proper formatting.

### 组件职责
该快照测试针对 Codex TUI 的 **PendingInputPreview** 组件，负责验证：
- 单条排队消息的渲染正确性
- 节标题、消息内容和编辑提示的完整显示
- 样式应用（DIM + ITALIC）

## 2. 功能点目的 (Feature Purpose)

### 测试目标
Validates the basic rendering of a single queued message in the pending input preview widget.

### 验证要点
1. 节标题 "Queued follow-up messages" 正确显示
2. 消息前缀 "↳" 正确显示
3. 消息内容 "Hello, world!" 正确显示
4. 编辑提示 "⌥ + ↑ edit last queued message" 显示在底部
5. 样式使用 DIM（暗淡）和 ITALIC（斜体）

## 3. 具体技术实现 (Technical Implementation)

### 核心数据结构
```rust
pub(crate) struct PendingInputPreview {
    pub pending_steers: Vec<String>,
    pub queued_messages: Vec<String>,
    edit_binding: key_hint::KeyBinding,  // 默认为 Alt+Up
}
```

### 测试数据
```rust
queue.queued_messages.push("Hello, world!".to_string());
```

### 渲染输出 (40x3)
```
• Queued follow-up messages
  ↳ Hello, world!
    ⌥ + ↑ edit last queued message
```

### 关键算法
1. **节标题渲染**: 使用 `push_section_header()` 添加带项目符号的标题
2. **消息渲染**: 使用 `adaptive_wrap_lines()` 包装消息文本
3. **编辑提示**: 仅当 `queued_messages` 非空时显示

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 源文件
- **主文件**: `codex-rs/tui/src/bottom_pane/pending_input_preview.rs`

### 关键代码段
```rust
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
            Line::from("    …".dim().italic()),
        );
    }
}

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

### 测试代码位置
```rust
#[test]
fn render_one_message() {
    let mut queue = PendingInputPreview::new();
    queue.queued_messages.push("Hello, world!".to_string());
    let width = 40;
    let height = queue.desired_height(width);
    let mut buf = Buffer::empty(Rect::new(0, 0, width, height));
    queue.render(Rect::new(0, 0, width, height), &mut buf);
    assert_snapshot!("render_one_message", format!("{buf:?}"));
}
```

## 5. 依赖与外部交互 (Dependencies)

### 外部 Crates
| Crate | 用途 |
|-------|------|
| `ratatui` | TUI 渲染框架 |
| `insta` | 快照测试框架 |
| `pretty_assertions` | 测试失败时提供美观的差异对比 |

### 内部模块依赖
- `crate::key_hint` - 键盘提示生成
- `crate::wrapping::{RtOptions, adaptive_wrap_lines}` - 文本包装

## 6. 风险、边界与改进建议 (Risks, Edge Cases, Improvements)

### 潜在风险
1. **终端尺寸变化**: 极端窄的终端可能导致布局问题
2. **编辑绑定差异**: 不同终端显示不同的编辑按键提示

### 边界情况
| 场景 | 行为 |
|------|------|
| 空消息 | 只显示 ↳ 前缀 |
| 极长消息 | 包装到多行，最多 3 行 |
| 无 queued_messages | 不显示此部分 |

### 改进建议
1. 添加空消息过滤
2. 考虑显示消息序号
3. 添加删除单条消息的功能

### 相关文档
- `Docs/researches/codex-rs/tui/src/bottom_pane/pending_input_preview.rs_research.md`
