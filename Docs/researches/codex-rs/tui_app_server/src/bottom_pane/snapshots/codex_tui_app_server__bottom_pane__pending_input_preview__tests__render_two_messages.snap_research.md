# render_two_messages Snapshot 研究文档

## 场景与职责

本快照测试展示了 `PendingInputPreview` 组件处理**两条排队消息**时的渲染行为。验证组件能够正确渲染多条消息，并保持适当的视觉结构和间距。

**典型使用场景**：
- 用户连续输入两条问题或指令后排队等待
- 验证多消息情况下的高度计算和渲染
- 作为从单条消息到多条消息的过渡测试

## 功能点目的

该测试验证以下核心功能：

1. **多消息渲染**：正确渲染两条独立的排队消息
2. **消息前缀**：每条消息以 `"  ↳ "` 前缀标识
3. **高度计算**：验证两条消息时的正确高度（4行）
4. **视觉一致性**：保持与单条消息相同的样式规范

**渲染输出特征**：
```
• Queued follow-up messages             <- 标题行（dim 样式）
  ↳ Hello, world!                       <- 消息 1（dim + italic）
  ↳ This is another message             <- 消息 2（dim + italic）
    ⌥ + ↑ edit last queued message      <- 编辑提示（dim 样式）
```

## 具体技术实现

### 高度计算
```rust
// 单条消息：3 行（标题 + 消息 + 提示）
// 两条消息：4 行（标题 + 消息1 + 消息2 + 提示）
```

### 渲染流程
```rust
#[test]
fn render_two_messages() {
    let mut queue = PendingInputPreview::new();
    queue.queued_messages.push("Hello, world!".to_string());
    queue.queued_messages.push("This is another message".to_string());
    let width = 40;
    let height = queue.desired_height(width);  // = 4
    let mut buf = Buffer::empty(Rect::new(0, 0, width, height));
    queue.render(Rect::new(0, 0, width, height), &mut buf);
    assert_snapshot!("render_two_messages", format!("{buf:?}"));
}
```

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

## 关键代码路径与文件引用

### 主要文件
- `codex-rs/tui_app_server/src/bottom_pane/pending_input_preview.rs` - PendingInputPreview 组件实现

### 关键函数
| 函数 | 行号 | 职责 |
|------|------|------|
| `render_two_messages` (test) | 180-191 | 本测试用例 |
| `as_renderable()` | 69-132 | 主渲染逻辑 |

### 测试数据
```rust
queue.queued_messages.push("Hello, world!".to_string());
queue.queued_messages.push("This is another message".to_string());
```

## 依赖与外部交互

### 依赖模块
- `crate::wrapping::adaptive_wrap_lines` - 自适应文本换行
- `crate::key_hint` - 键盘快捷键提示
- `ratatui::buffer::Buffer` - 渲染缓冲区

### 高度计算逻辑
```rust
// 标题：1 行
// 每条消息：1 行（假设不触发换行）
// 编辑提示：1 行
// 总计：1 + N + 1 = N + 2 行（N 为消息数量）
```

## 风险、边界与改进建议

### 当前边界情况
1. **消息长度**：测试消息较短，未触发换行
2. **消息数量**：仅测试 2 条，未测试更多数量
3. **宽度充足**：40 字符宽度足够显示完整内容

### 潜在风险
1. **消息增长**：随着消息数量增加，高度线性增长
2. **换行影响**：如果消息触发换行，高度计算会更复杂
3. **样式一致性**：所有消息使用相同样式，难以区分

### 改进建议
1. **消息分隔**：在消息之间添加轻微分隔（如缩进变化或空行）
2. **消息编号**：显示消息序号，如 `"  ↳ [1] Hello, world!"`
3. **滚动预览**：当消息过多时，显示滚动指示器
4. **高度限制**：添加最大高度限制，超出时显示 `"... 还有 N 条"`
5. **消息预览**：只显示每条消息的前 N 个字符，避免单行过长
