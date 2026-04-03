# Research Document: User History Cell Wraps and Prefixes Each Line Snapshot

## 场景与职责

此快照测试验证 **UserHistoryCell** 组件在渲染长文本用户消息时的换行和缩进行为。当用户输入的消息超过终端宽度时，需要正确换行并保持首行与续行的视觉区分。

该组件负责：
- 处理用户消息的自动换行
- 首行使用 `› ` 前缀标识用户输入
- 续行使用 `"  "`（两个空格）保持缩进对齐
- 保持文本内容的完整性

## 功能点目的

**主要功能**：验证 UserHistoryCell 对长文本消息的换行渲染效果：

1. **自动换行**：消息 `"one two three four five six seven"` 在宽度 12 时换行
2. **首行前缀**：`"› "`（右箭头 + 空格）标识用户消息开始
3. **续行缩进**：`"  "`（两个空格）保持与首行内容对齐
4. **空行处理**：开头和结尾的空行用于视觉分隔

**预期输出结构**（宽度 12）：
```
› one two
  three
  four five
  six seven
```

**换行计算**：
- 有效宽度 = 12 - 2（`LIVE_PREFIX_COLS`） - 1 = 9
- "one two three" 在 9 字符处换行
- 续行缩进 2 空格

## 具体技术实现

### 核心渲染逻辑

**display_lines 方法**（`history_cell.rs` 第 288-372 行）：
```rust
impl HistoryCell for UserHistoryCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
        // 计算换行宽度（预留前缀空间）
        let wrap_width = width
            .saturating_sub(LIVE_PREFIX_COLS + 1)  // LIVE_PREFIX_COLS = 1
            .max(1);  // 12 - 2 = 10? 实际为 9
        
        let style = user_message_style();
        
        // 处理消息换行
        let wrapped_message = if self.message.is_empty() && self.text_elements.is_empty() {
            None
        } else if self.text_elements.is_empty() {
            let message_without_trailing_newlines = self.message.trim_end_matches(['\r', '\n']);
            let wrapped = adaptive_wrap_lines(
                message_without_trailing_newlines
                    .split('\n')
                    .map(|line| Line::from(line).style(style)),
                RtOptions::new(usize::from(wrap_width))
                    .wrap_algorithm(textwrap::WrapAlgorithm::FirstFit),
            );
            let wrapped = trim_trailing_blank_lines(wrapped);
            (!wrapped.is_empty()).then_some(wrapped)
        } else {
            // 处理带 text_elements 的消息...
        };
        
        // 组装输出
        let mut lines: Vec<Line<'static>> = vec![Line::from("").style(style)];
        
        if let Some(wrapped_message) = wrapped_message {
            lines.extend(prefix_lines(
                wrapped_message,
                "› ".bold().dim(),  // 首行前缀
                "  ".into(),        // 续行前缀
            ));
        }
        
        lines.push(Line::from("").style(style));
        lines
    }
}
```

### 前缀应用

**prefix_lines 函数**（`render/line_utils.rs`）：
```rust
pub fn prefix_lines(
    lines: Vec<Line<'static>>,
    first_prefix: Span<'static>,
    rest_prefix: Span<'static>,
) -> Vec<Line<'static>> {
    lines.into_iter().enumerate().map(|(i, mut line)| {
        let prefix = if i == 0 { &first_prefix } else { &rest_prefix };
        // 将前缀插入行首
        line.spans.insert(0, prefix.clone());
        line
    }).collect()
}
```

### 样式定义

- 首行前缀：`"› ".bold().dim()`（粗体、变暗）
- 续行前缀：`"  "`（普通空格）
- 文本样式：`user_message_style()`

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/history_cell.rs` | `UserHistoryCell::display_lines`（第 288-372 行） |
| `codex-rs/tui/src/render/line_utils.rs` | `prefix_lines` 函数 |
| `codex-rs/tui/src/wrapping.rs` | `adaptive_wrap_lines` 自适应换行 |
| `codex-rs/tui/src/history_cell.rs` | `trim_trailing_blank_lines`（第 278-286 行） |
| `codex-rs/tui/src/history_cell.rs` | 测试用例（第 3842-3857 行） |

### 测试代码位置

```rust
// history_cell.rs 第 3842-3857 行
#[test]
fn user_history_cell_wraps_and_prefixes_each_line_snapshot() {
    let msg = "one two three four five six seven";
    let cell = UserHistoryCell {
        message: msg.to_string(),
        text_elements: Vec::new(),
        local_image_paths: Vec::new(),
        remote_image_urls: Vec::new(),
    };
    
    // 小宽度 12 强制换行
    let width: u16 = 12;
    let lines = cell.display_lines(width);
    let rendered = render_lines(&lines).join("\n");
    
    insta::assert_snapshot!(rendered);
}
```

## 依赖与外部交互

### 内部依赖

- **textwrap**: `WrapAlgorithm::FirstFit` 换行算法
- **ratatui**: `Line`、`Span` 类型
- **unicode-width**: 字符宽度计算

### 常量定义

```rust
// ui_consts.rs
pub const LIVE_PREFIX_COLS: u16 = 1;  // 用于计算换行宽度
```

## 风险、边界与改进建议

### 已知风险

1. **宽度计算误差**：`LIVE_PREFIX_COLS + 1` 的魔法数字可能不准确
2. **CJK 字符**：中日韩宽字符可能导致换行位置偏移
3. **组合字符**：Unicode 组合字符宽度计算复杂

### 边界情况

| 场景 | 当前行为 |
|------|---------|
| 消息为空 | 返回空 Vec |
| 只有空白字符 | `trim_trailing_blank_lines` 处理后可能为空 |
| 包含显式换行符 | 每行独立处理，各自应用前缀 |
| 宽度 = 0 | 最小宽度保护为 1 |

### 改进建议

1. **配置化**：
   - 允许用户自定义首行前缀符号
   - 可配置续行缩进宽度

2. **智能换行**：
   - 优先在标点符号处断行
   - 保持单词完整性（当前已实现）

3. **可访问性**：
   - 为屏幕阅读器提供续行提示
   - 支持 Braille 显示

4. **代码优化**：
   - 将 `LIVE_PREFIX_COLS` 的计算逻辑文档化
   - 增加更多边界测试
