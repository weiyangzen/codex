# 研究文档：multiline_command_both_lines_wrap_with_correct_prefixes.snap

## 场景与职责

此快照测试验证多行命令在换行时前缀符号的正确显示。当命令文本很长需要换行时，每一行的前缀符号（如 `│`）应该正确显示，保持命令的可读性。

## 功能点目的

1. **多行命令显示**：支持显示包含换行符的命令
2. **前缀符号一致性**：确保换行后的每一行都有正确的前缀
3. **视觉层次清晰**：通过前缀符号区分命令的不同部分

## 具体技术实现

### 命令显示结构

```
• Ran first_token_is_long_en
  │ ough_to_wrap
  │ second_token_is_also_lon
  │ … +1 lines
  └ (no output)
```

### 前缀符号系统

- `• Ran` - 命令执行指示器
- `│` - 命令行的延续前缀（垂直线）
- `… +1 lines` - 省略指示，表示有更多行
- `└` - 结果/输出的开始标记

### 代码实现要点

```rust
// 来自 history_cell.rs 中的 ExecCell 实现
fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
    // 1. 分割命令行为多个物理行
    // 2. 为每行添加适当的前缀
    // 3. 处理换行和省略逻辑
}
```

## 关键代码路径与文件引用

1. **命令执行单元格**：
   - `codex-rs/tui/src/exec_cell.rs` - ExecCell 实现
   - `codex-rs/tui/src/history_cell.rs` - 历史记录单元格 trait

2. **行工具函数**：
   - `crate::render::line_utils::prefix_lines` - 为行添加前缀
   - `crate::render::line_utils::push_owned_lines` - 行操作工具

3. **样式定义**：
   - `crate::style::user_message_style` - 用户消息样式

## 依赖与外部交互

### 命令执行相关
- `crate::exec_command::strip_bash_lc_and_escape` - 命令清理
- `crate::exec_command::relativize_to_home` - 路径简化

### 渲染相关
- `ratatui::text::Line` - 文本行
- `ratatui::text::Span` - 文本片段

## 风险、边界与改进建议

### 潜在风险
1. **前缀对齐问题**：不同宽度的字符可能导致前缀对齐不准确
2. **省略逻辑错误**：计算省略行数时可能出现偏差

### 边界情况
1. 命令行数非常多（>100 行）
2. 命令包含控制字符或 ANSI 转义序列
3. 终端宽度极窄的情况

### 改进建议
1. 添加配置选项，允许用户设置最大显示行数
2. 支持点击展开查看完整命令
3. 添加语法高亮，区分命令和参数
4. 考虑对长命令进行智能折叠，只显示关键部分
