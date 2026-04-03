# 研究文档：multiline_command_without_wrap_uses_branch_then_eight_spaces.snap

## 场景与职责

此快照测试验证多行命令在不需要换行时的显示格式。当命令包含多行但每行都能在当前终端宽度内显示时，应该使用分支符号和缩进来保持层次结构。

## 功能点目的

1. **紧凑多行显示**：当命令行不需要换行时，保持紧凑显示
2. **缩进一致性**：使用 8 空格缩进来对齐多行命令
3. **视觉层次**：通过分支符号（`│`）和缩进清晰展示命令结构

## 具体技术实现

### 快照输出分析

```
• Ran echo one
  │ echo two
  └ (no output)
```

显示结构：
- `• Ran` - 命令执行指示器
- `echo one` - 第一行命令（紧跟在指示器后）
- `│ echo two` - 第二行命令，使用 `│` 前缀 + 空格 + 命令
- `└ (no output)` - 输出指示

### 缩进逻辑

```rust
// 伪代码表示缩进逻辑
const INDENT_WIDTH: usize = 8; // 8 空格缩进

fn format_multiline_command(lines: &[String]) -> Vec<Line> {
    let mut result = vec![];
    for (i, line) in lines.iter().enumerate() {
        if i == 0 {
            result.push(Line::from(format!("• Ran {line}")));
        } else {
            // 使用 │ 前缀 + 空格 + 命令
            result.push(Line::from(format!("  │ {line}")));
        }
    }
    result
}
```

## 关键代码路径与文件引用

1. **命令格式化**：
   - `codex-rs/tui/src/exec_cell.rs` - 命令执行单元格
   - `codex-rs/tui/src/history_cell.rs` - 历史记录渲染

2. **行工具**：
   - `crate::render::line_utils` - 行操作工具

## 依赖与外部交互

### 核心依赖
- `crate::exec_cell::CommandOutput` - 命令输出结构
- `crate::ui_consts::LIVE_PREFIX_COLS` - 前缀列数常量

## 风险、边界与改进建议

### 边界情况
1. 空命令行
2. 只有空白字符的行
3. 包含制表符的行

### 改进建议
1. 考虑使用自适应缩进，根据命令深度调整
2. 添加选项显示/隐藏行号
3. 支持对命令进行语法高亮
