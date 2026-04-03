# Research: Error Event Oversized Input Snapshot

## 场景与职责

此快照测试验证 Codex TUI 在接收到超过最大长度限制的用户输入时的错误展示能力。当用户输入的消息超过系统限制（1,048,576 字符）时，UI 需要清晰地展示错误信息，告知用户输入超限。

## 功能点目的

1. **输入长度验证**：防止过大的输入导致性能问题或内存溢出
2. **清晰错误提示**：向用户明确说明输入超限及具体数值
3. **视觉区分**：通过红色方块符号（■）和红色文本标识错误

## 具体技术实现

### 错误事件单元格

```rust
// history_cell.rs:1976-1982
pub(crate) fn new_error_event(message: String) -> PlainHistoryCell {
    // 使用 hair space (U+200A) 创建微妙的间距
    // VS16 被省略以保持终端中的紧凑间距
    let lines: Vec<Line<'static>> = vec![vec![format!("■ {message}").red()].into()];
    PlainHistoryCell { lines }
}
```

### PlainHistoryCell 实现

```rust
// history_cell.rs:473-488
#[derive(Debug)]
pub(crate) struct PlainHistoryCell {
    lines: Vec<Line<'static>>,
}

impl PlainHistoryCell {
    pub(crate) fn new(lines: Vec<Line<'static>>) -> Self {
        Self { lines }
    }
}

impl HistoryCell for PlainHistoryCell {
    fn display_lines(&self, _width: u16) -> Vec<Line<'static>> {
        self.lines.clone()  // 直接返回预构建的行，不进行换行处理
    }
}
```

### 测试场景

```rust
// history_cell.rs:2861-2868
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

### 输出格式

```
■ Message exceeds the maximum length of 1048576 characters (1048577 provided).
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/history_cell.rs` | 错误事件单元格实现，测试位于 line 2861-2868 |
| `codex_protocol` | 输入验证和错误类型定义 |

### 错误展示流程

```
输入验证失败（长度 1048577 > 限制 1048576）
    ↓
生成错误消息字符串
    ↓
new_error_event(message)
    ↓
PlainHistoryCell {
    lines: vec!["■ {message}".red()]
}
    ↓
display_lines() → 返回预构建的行
    ↓
渲染红色错误消息
```

## 依赖与外部交互

### 外部依赖

- `ratatui::style::Stylize`: 提供 `.red()` 等样式方法
- 标准库字符串格式化

### 内部常量

```rust
// 最大输入长度限制（1MB）
const MAX_INPUT_LENGTH: usize = 1_048_576; // 1024 * 1024
```

## 风险、边界与改进建议

### 潜在风险

1. **硬编码限制**：最大长度限制硬编码，不便于配置调整
2. **错误信息固定**：错误信息格式固定，不支持国际化
3. **无恢复建议**：未提供用户如何解决问题的指导

### 边界情况

1. **刚好超限**：1048577 与 1048576 的边界
2. **极大输入**：数 GB 级别的输入处理（应在更早阶段拦截）
3. **多字节字符**：字符数与字节数的区别
4. **空消息**：`new_error_event("")` 的行为

### 改进建议

1. **可配置限制**：将最大长度限制提取为配置项
2. **友好提示**：
   - 显示输入的实际长度（如 "你的输入为 2.5MB"）
   - 建议截断或分段发送
   - 提供文件上传替代方案
3. **国际化支持**：错误消息支持多语言
4. **视觉增强**：
   - 添加警告图标
   - 使用更醒目的样式
5. **操作指引**：
   - 提供 "/file" 命令建议，将大内容作为文件发送
   - 提供分割输入的示例
6. **前置拦截**：在输入编辑阶段就显示长度警告

### 相关测试

- `new_warning_event`：警告事件展示
- `new_info_event`：信息事件展示
- `new_deprecation_notice`：弃用通知展示

### 相关代码

```rust
// 其他事件类型对比

// 警告事件（黄色）
pub(crate) fn new_warning_event(message: String) -> PrefixedWrappedHistoryCell {
    PrefixedWrappedHistoryCell::new(message.yellow(), "⚠ ".yellow(), "  ")
}

// 信息事件（默认色 + 暗色提示）
pub(crate) fn new_info_event(message: String, hint: Option<String>) -> PlainHistoryCell {
    let mut line = vec!["• ".dim(), message.into()];
    if let Some(hint) = hint {
        line.push(" ".into());
        line.push(hint.dark_gray());
    }
    PlainHistoryCell { lines: vec![line.into()] }
}
```
