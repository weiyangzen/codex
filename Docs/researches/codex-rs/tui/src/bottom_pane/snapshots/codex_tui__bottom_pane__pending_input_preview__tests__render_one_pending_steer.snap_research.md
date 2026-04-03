# Render One Pending Steer

## 1. 场景与职责 (Scene and Responsibility)

### 测试场景
Tests rendering of a single pending steer message.

### 组件职责
该快照测试针对 Codex TUI 的 **PendingInputPreview** 组件，负责验证：
- 单条 pending steer 的渲染正确性
- 节标题和提示文本的完整显示
- 与 queued messages 不同的样式（无斜体）

## 2. 功能点目的 (Feature Purpose)

### 测试目标
Validates the rendering of a single pending steer message in the pending input preview widget.

### 验证要点
1. 节标题 "Messages to be submitted after next tool call" 正确显示
2. 提示文本 "(press esc to interrupt and send immediately)" 显示
3. 消息前缀 "↳" 正确显示
4. steer 内容 "Please continue." 正确显示
5. 无编辑提示（因为只有 queued_messages 有编辑提示）
6. 样式使用 DIM（暗淡），但无 ITALIC

## 3. 具体技术实现 (Technical Implementation)

### 核心数据结构
```rust
pub(crate) struct PendingInputPreview {
    pub pending_steers: Vec<String>,      // 待处理引导消息
    pub queued_messages: Vec<String>,     // 排队消息
    edit_binding: key_hint::KeyBinding,
}
```

### 测试数据
```rust
queue.pending_steers.push("Please continue.".to_string());
```

### 渲染输出 (48x3)
```
• Messages to be submitted after next tool call
  (press esc to interrupt and send immediately)
  ↳ Please continue.
```

### 关键算法
1. **节标题包装**: 标题和提示文本作为一个整体进行自适应包装
2. **steer 渲染**: 使用 `dim()` 样式，无 `italic()`
3. **无编辑提示**: 仅当 `queued_messages` 非空时才显示编辑提示

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 源文件
- **主文件**: `codex-rs/tui/src/bottom_pane/pending_input_preview.rs`

### 关键代码段
```rust
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
            steer.lines().map(|line| Line::from(line.dim())),  // 注意：无 italic
            RtOptions::new(width as usize)
                .initial_indent(Line::from("  ↳ ".dim()))
                .subsequent_indent(Line::from("    ")),
        );
        Self::push_truncated_preview_lines(&mut lines, wrapped, Line::from("    …".dim()));
    }
}
```

### 测试代码位置
```rust
#[test]
fn render_one_pending_steer() {
    let mut queue = PendingInputPreview::new();
    queue.pending_steers.push("Please continue.".to_string());
    let width = 48;
    let height = queue.desired_height(width);
    let mut buf = Buffer::empty(Rect::new(0, 0, width, height));
    queue.render(Rect::new(0, 0, width, height), &mut buf);
    assert_snapshot!("render_one_pending_steer", format!("{buf:?}"));
}
```

## 5. 依赖与外部交互 (Dependencies)

### 外部 Crates
| Crate | 用途 |
|-------|------|
| `ratatui` | TUI 渲染框架 |
| `crossterm` | 提供 `KeyCode::Esc` |
| `insta` | 快照测试框架 |

### 内部模块依赖
- `crate::key_hint` - 按键提示生成
- `crate::wrapping::{RtOptions, adaptive_wrap_lines}` - 文本包装

### 样式差异
| 元素 | Pending Steers | Queued Messages |
|------|----------------|-----------------|
| 内容样式 | `dim()` | `dim().italic()` |
| 截断提示 | `dim()` | `dim().italic()` |
| 编辑提示 | 无 | 有 |

## 6. 风险、边界与改进建议 (Risks, Edge Cases, Improvements)

### 潜在风险
1. **样式混淆**: 用户可能难以区分 pending steers 和 queued messages 的视觉差异
2. **Esc 提示**: 提示文本较长，在窄终端可能包装到多行

### 边界情况
| 场景 | 行为 |
|------|------|
| 空 steer | 只显示 ↳ 前缀 |
| 长 steer | 包装到多行，最多 3 行 |
| 无 pending_steers | 不显示此部分 |

### 改进建议
1. **视觉区分**: 考虑使用不同颜色或图标区分 steer 和 message
2. **交互功能**: 允许用户取消特定的 pending steer
3. **时间戳**: 显示 steer 发送时间

### 相关文档
- `Docs/researches/codex-rs/tui/src/bottom_pane/pending_input_preview.rs_research.md`
