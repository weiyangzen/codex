# Render Pending Steers Above Queued Messages

## 1. 场景与职责 (Scene and Responsibility)

### 测试场景
Tests rendering when both pending steers and queued messages are present, verifying that steers appear above queued messages.

### 组件职责
该快照测试针对 Codex TUI 的 **PendingInputPreview** 组件，负责验证：
- pending steers 和 queued messages 同时存在时的渲染顺序
- 两部分之间的空行分隔
- 各自的样式和提示正确显示

## 2. 功能点目的 (Feature Purpose)

### 测试目标
Validates that pending steers are rendered above queued messages when both are present.

### 验证要点
1. Pending steers 部分显示在上方
2. Queued messages 部分显示在下方
3. 两部分之间有空行分隔
4. Pending steers 显示 Esc 提示
5. Queued messages 显示编辑提示（Alt+↑）
6. 各自的样式正确应用（steers: dim, messages: dim+italic）

## 3. 具体技术实现 (Technical Implementation)

### 核心数据结构
```rust
pub(crate) struct PendingInputPreview {
    pub pending_steers: Vec<String>,
    pub queued_messages: Vec<String>,
    edit_binding: key_hint::KeyBinding,
}
```

### 测试数据
```rust
queue.pending_steers.push("Please continue.".to_string());
queue.pending_steers.push("Check the last command output.".to_string());
queue.queued_messages.push("Queued follow-up question".to_string());
```

### 渲染输出 (52x8)
```
• Messages to be submitted after next tool call
  (press esc to interrupt and send immediately)
  ↳ Please continue.
  ↳ Check the last command output.

• Queued follow-up messages
  ↳ Queued follow-up question
    ⌥ + ↑ edit last queued message
```

### 关键算法
1. **渲染顺序**: 先渲染 `pending_steers`，再渲染 `queued_messages`
2. **分隔空行**: 当 `lines` 非空时，添加空行 `Line::from("")`
3. **独立样式**: 两部分使用不同的样式设置

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 源文件
- **主文件**: `codex-rs/tui/src/bottom_pane/pending_input_preview.rs`

### 关键代码段
```rust
// 1. 渲染 Pending Steers
if !self.pending_steers.is_empty() {
    Self::push_section_header(&mut lines, width, /* ... */);
    for steer in &self.pending_steers {
        // 渲染每条 steer（dim 样式）
    }
}

// 2. 渲染 Queued Messages
if !self.queued_messages.is_empty() {
    if !lines.is_empty() {
        lines.push(Line::from(""));  // 分隔空行
    }
    Self::push_section_header(&mut lines, width, "Queued follow-up messages".into());
    for message in &self.queued_messages {
        // 渲染每条消息（dim+italic 样式）
    }
}

// 3. 添加编辑提示（仅当 queued_messages 非空）
if !self.queued_messages.is_empty() {
    lines.push(Line::from(vec![/* 编辑提示 */]).dim());
}
```

### 测试代码位置
```rust
#[test]
fn render_pending_steers_above_queued_messages() {
    let mut queue = PendingInputPreview::new();
    queue.pending_steers.push("Please continue.".to_string());
    queue.pending_steers.push("Check the last command output.".to_string());
    queue.queued_messages.push("Queued follow-up question".to_string());
    let width = 52;
    let height = queue.desired_height(width);
    let mut buf = Buffer::empty(Rect::new(0, 0, width, height));
    queue.render(Rect::new(0, 0, width, height), &mut buf);
    assert_snapshot!("render_pending_steers_above_queued_messages", format!("{buf:?}"));
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

## 6. 风险、边界与改进建议 (Risks, Edge Cases, Improvements)

### 潜在风险
1. **高度计算**: 两部分同时存在时，高度计算需要包含空行分隔
2. **视觉拥挤**: 内容较多时可能占用过多屏幕空间

### 边界情况
| 场景 | 行为 |
|------|------|
| 只有 steers | 不显示空行分隔，无编辑提示 |
| 只有 messages | 正常显示，有编辑提示 |
| 两者都有 | 空行分隔，steers 在上 |
| 大量 steers + messages | 可能占用大量垂直空间 |

### 改进建议
1. **可折叠**: 允许用户折叠/展开某一部分
2. **计数显示**: 显示每部分的条目数量
3. **优先级指示**: 更清晰地表明 steers 会先于 messages 发送

### 相关文档
- `Docs/researches/codex-rs/tui/src/bottom_pane/pending_input_preview.rs_research.md`
