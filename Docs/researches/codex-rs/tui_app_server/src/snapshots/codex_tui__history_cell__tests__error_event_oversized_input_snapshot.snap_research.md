# Error Event Oversized Input Snapshot

## 场景与职责

该快照测试验证当用户输入的消息超过系统允许的最大长度限制时，TUI（终端用户界面）如何正确渲染错误提示信息。这是 Codex CLI 中处理输入验证错误的一部分，确保用户能够清楚地了解为什么他们的输入被拒绝。

## 功能点目的

1. **输入长度限制提示**：当用户输入的消息超过最大允许长度（1,048,576 字符）时，显示清晰的错误信息
2. **视觉一致性**：使用统一的错误样式（红色方块符号 + 红色文本）呈现错误信息
3. **精确的错误详情**：错误信息包含最大允许长度和实际提供的字符数，帮助用户理解限制

## 具体技术实现

### 错误单元格创建

```rust
// 在 history_cell.rs 中
pub(crate) fn new_error_event(message: String) -> PlainHistoryCell {
    // 使用 hair space (U+200A) 在文本前创建微妙的间距
    // VS16 被故意省略以保持终端（如 Ghostty）中的紧凑间距
    let lines: Vec<Line<'static>> = vec![vec![format!("■ {message}").red()].into()];
    PlainHistoryCell { lines }
}
```

### 样式规范

- **前缀符号**：`■` (黑色方块) - 表示错误或阻断性信息
- **颜色**：红色 (`red()`) - 标准的错误指示色
- **间距**：使用 hair space (U+200A) 而非普通空格，在保持视觉紧凑的同时提供微妙的分隔

### 测试用例

```rust
#[test]
fn error_event_oversized_input_snapshot() {
    let cell = new_error_event(
        "Message exceeds the maximum length of 1048576 characters (1048577 provided)."
            .to_string(),
    );
    let rendered = render_lines(&cell.display_lines(120)).join("\n");
    insta::assert_snapshot!(rendered);
}
```

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/history_cell.rs` | 包含 `new_error_event` 函数，创建错误事件单元格 |
| `codex-rs/tui/src/history_cell.rs` (line 1976-1982) | `new_error_event` 函数实现 |
| `codex-rs/tui/src/history_cell.rs` (line 2861-2868) | 对应的快照测试 |

### 渲染流程

1. 调用 `new_error_event(message)` 创建 `PlainHistoryCell`
2. `PlainHistoryCell` 实现 `HistoryCell` trait，直接返回预定义的 lines
3. 渲染时通过 `display_lines()` 获取行列表
4. 使用 `render_lines()` 辅助函数将 lines 转换为可比较的字符串

## 依赖与外部交互

### 内部依赖

- **ratatui**: 提供 `Line`, `Span`, `Style` 等 TUI 渲染原语
- **Stylize trait**: 提供 `.red()` 等样式辅助方法

### 相关类型

```rust
// PlainHistoryCell 定义
#[derive(Debug)]
pub(crate) struct PlainHistoryCell {
    lines: Vec<Line<'static>>,
}

impl HistoryCell for PlainHistoryCell {
    fn display_lines(&self, _width: u16) -> Vec<Line<'static>> {
        self.lines.clone()
    }
}
```

### 调用方

错误事件单元格通常由应用层的错误处理逻辑创建，例如：
- 输入验证失败时
- API 返回 413 Payload Too Large 时
- 其他需要向用户展示阻断性错误的场景

## 风险、边界与改进建议

### 当前风险

1. **硬编码长度限制**：错误消息中的长度限制值是硬编码的，如果后端限制变更，消息可能不准确
2. **无国际化**：错误消息仅为英文，不支持多语言
3. **终端兼容性**：虽然使用了 hair space，但在某些老旧终端上可能显示异常

### 边界情况

| 场景 | 当前行为 | 评估 |
|-----|---------|------|
| 消息长度刚好等于限制 | 不会触发错误 | ✅ 正确 |
| 消息长度 = 限制 + 1 | 显示此错误 | ✅ 正确 |
| 宽度极窄的终端 | 文本会被截断或换行 | ⚠️ 依赖 ratatui 的默认行为 |
| 空消息 | 不会触发 | ✅ 正确 |

### 改进建议

1. **动态限制值**：从配置或 API 响应中动态获取最大长度限制，而非硬编码
   ```rust
   // 建议改进
   pub(crate) fn new_error_event(message: String, max_length: Option<usize>) -> PlainHistoryCell {
       let msg = match max_length {
           Some(limit) => format!("Message exceeds the maximum length of {} characters ({} provided).", 
                                  limit, message.len()),
           None => message,
       };
       // ...
   }
   ```

2. **国际化支持**：使用本地化框架支持多语言错误消息

3. **截断显示**：如果错误消息本身很长，考虑截断显示或提供滚动机制

4. **可访问性**：考虑为色盲用户提供除颜色外的其他错误指示（如前缀符号已部分解决）

### 测试覆盖

当前测试仅验证了渲染输出与快照一致。建议增加：
- 不同终端宽度下的渲染测试
- 包含特殊字符的错误消息测试
- 超长错误消息的截断行为测试
