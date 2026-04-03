# 研究文档：multiline_command_wraps_with_extra_indent_on_subsequent_lines.snap

## 场景与职责

此快照测试验证多行命令在需要换行时的额外缩进处理。当命令行很长需要换行时，后续行应该有额外的缩进，以区分新行和换行。

## 功能点目的

1. **换行缩进区分**：换行后的文本应该有额外缩进，与新行区分
2. **可读性提升**：通过缩进层次清晰展示命令结构
3. **长命令处理**：支持显示很长的命令（如复杂的 shell 管道）

## 具体技术实现

### 快照输出分析

```
• Ran set -o pipefail
  │ cargo test
  │ --all-features --quiet
  └ (no output)
```

观察：
- 这是一个多行命令（可能是 heredoc 或多行输入）
- 每行都有 `│` 前缀
- 命令行之间没有额外的缩进，因为它们都是独立行

### 与 wrap 测试的区别

此测试与 `multiline_command_both_lines_wrap_with_correct_prefixes` 的区别：
- 本测试：多行命令，每行都很短，不需要换行
- wrap 测试：单行命令很长，需要自动换行

## 关键代码路径与文件引用

1. **命令解析**：
   - `codex-rs/tui/src/exec_command.rs` - 命令解析和处理
   - `codex-rs/tui/src/exec_cell.rs` - 执行单元格

2. **文本处理**：
   - `crate::wrapping::adaptive_wrap_lines` - 自适应换行

## 依赖与外部交互

### 相关常量
- `crate::ui_consts::LIVE_PREFIX_COLS` - 实时前缀列数

## 风险、边界与改进建议

### 边界情况
1. 命令行包含前导空格
2. 命令行包含制表符
3. 命令行长度正好等于终端宽度

### 改进建议
1. 考虑对 shell 命令进行语法高亮
2. 添加命令折叠/展开功能
3. 支持点击复制完整命令
