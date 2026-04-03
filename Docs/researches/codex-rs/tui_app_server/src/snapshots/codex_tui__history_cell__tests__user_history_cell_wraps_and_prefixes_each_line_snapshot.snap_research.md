# 研究文档：user_history_cell_wraps_and_prefixes_each_line_snapshot.snap

## 场景与职责

此快照测试验证用户历史记录单元格中用户输入文本的换行和前缀处理。当用户输入很长时，每行都应该有正确的前缀（`›`）。

## 功能点目的

1. **输入换行**：长用户输入需要正确换行
2. **前缀一致性**：每行都有 `›` 前缀
3. **可读性**：保持用户输入的可读性

## 具体技术实现

### 快照输出分析

```
› one two
  three
  four five
  six seven
```

显示结构：
- 第一行：`›` + 输入开始
- 后续行：空格对齐 + 输入继续
- 所有行左对齐

### 换行前缀逻辑

```rust
fn wrap_user_input(input: &str, width: u16) -> Vec<Line> {
    let mut lines = vec![];
    let prefix_width = "› ".width();
    let wrapped = textwrap::wrap(input, width as usize - prefix_width);
    
    for (i, line) in wrapped.iter().enumerate() {
        if i == 0 {
            lines.push(Line::from(format!("› {line}")));
        } else {
            // 后续行使用空格对齐到第一行内容位置
            lines.push(Line::from(format!("  {line}")));
        }
    }
    
    lines
}
```

## 关键代码路径与文件引用

1. **用户输入处理**：
   - `codex-rs/tui/src/history_cell.rs` - UserHistoryCell

2. **文本工具**：
   - `crate::render::line_utils`

## 依赖与外部交互

### 文本处理
- `unicode_width::UnicodeWidthStr` - 字符宽度计算

## 风险、边界与改进建议

### 潜在风险
1. **对齐问题**：不同字体的字符宽度可能不同
2. **前缀混淆**：`›` 可能与命令提示符混淆

### 边界情况
1. 输入包含换行符
2. 输入包含制表符
3. 输入全是空白字符

### 改进建议
1. 考虑使用不同的前缀符号
2. 支持富文本输入（Markdown）
3. 添加输入时间戳
