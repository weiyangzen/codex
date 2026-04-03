# Render Two Messages

## 1. 场景与职责 (Scene and Responsibility)

### 测试场景
Tests rendering of two queued messages.

### 组件职责
该快照测试针对 Codex TUI 的 **PendingInputPreview** 组件，负责验证：
- 多条排队消息的渲染正确性
- 每条消息都有独立的前缀和样式
- 编辑提示只显示一次在底部

## 2. 功能点目的 (Feature Purpose)

### 测试目标
Validates rendering of multiple queued messages with proper formatting.

### 验证要点
1. 两条消息都正确显示
2. 每条消息都有 "↳" 前缀
3. 消息内容使用 `dim().italic()` 样式
4. 编辑提示只显示一次

## 3. 具体技术实现 (Technical Implementation)

### 测试数据
```rust
queue.queued_messages.push("Hello, world!".to_string());
queue.queued_messages.push("This is another message".to_string());
```

### 渲染输出 (40x4)
```
• Queued follow-up messages
  ↳ Hello, world!
  ↳ This is another message
    ⌥ + ↑ edit last queued message
```

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 源文件
- **主文件**: `codex-rs/tui/src/bottom_pane/pending_input_preview.rs`

### 测试代码位置
```rust
#[test]
fn render_two_messages() {
    let mut queue = PendingInputPreview::new();
    queue.queued_messages.push("Hello, world!".to_string());
    queue.queued_messages.push("This is another message".to_string());
    let width = 40;
    let height = queue.desired_height(width);
    let mut buf = Buffer::empty(Rect::new(0, 0, width, height));
    queue.render(Rect::new(0, 0, width, height), &mut buf);
    assert_snapshot!("render_two_messages", format!("{buf:?}"));
}
```

## 5. 依赖与外部交互 (Dependencies)

### 外部 Crates
| Crate | 用途 |
|-------|------|
| `ratatui` | TUI 渲染框架 |
| `insta` | 快照测试框架 |

## 6. 风险、边界与改进建议 (Risks, Edge Cases, Improvements)

### 潜在风险
1. **消息数量**: 消息数量无上限，可能占用过多空间

### 改进建议
1. 考虑限制显示的消息数量
2. 添加消息序号

### 相关文档
- `Docs/researches/codex-rs/tui/src/bottom_pane/pending_input_preview.rs_research.md`
