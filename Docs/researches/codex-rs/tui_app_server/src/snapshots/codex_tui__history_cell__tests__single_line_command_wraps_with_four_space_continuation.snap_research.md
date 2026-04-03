# 研究文档：single_line_command_wraps_with_four_space_continuation.snap

## 场景与职责

此快照测试验证单行命令在需要换行时的缩进处理。当命令很长需要换行时，后续行应该有 4 个空格的缩进。

## 功能点目的

1. **换行缩进**：长命令换行后使用 4 空格缩进
2. **可读性**：通过缩进区分命令的不同部分
3. **一致性**：保持命令显示风格的一致性

## 具体技术实现

### 快照输出分析

```
• Ran a_very_long_token_
  │ without_spaces_to_
  │ force_wrapping
  └ (no output)
```

关键观察：
- 第一行：`• Ran` + 命令开头
- 后续行：`│` + 4 空格 + 命令继续
- 使用 `│` 符号表示命令延续

### 换行缩进逻辑

```rust
const CONTINUATION_INDENT: usize = 4;

fn wrap_command_with_indent(command: &str, width: u16) -> Vec<Line> {
    let mut lines = vec![];
    let wrapped = textwrap::wrap(command, width as usize - "• Ran ".len());
    
    for (i, line) in wrapped.iter().enumerate() {
        if i == 0 {
            lines.push(Line::from(format!("• Ran {line}")));
        } else {
            let indent = " ".repeat(CONTINUATION_INDENT);
            lines.push(Line::from(format!("  │{indent}{line}")));
        }
    }
    
    lines
}
```

## 关键代码路径与文件引用

1. **命令换行**：
   - `crate::wrapping::adaptive_wrap_line`
   - `codex-rs/tui/src/wrapping.rs`

2. **命令显示**：
   - `codex-rs/tui/src/exec_cell.rs`

## 依赖与外部交互

### 换行依赖
- `textwrap` - 文本换行库

## 风险、边界与改进建议

### 潜在风险
1. **缩进不一致**：4 空格可能与其他部分的缩进不匹配
2. **宽度计算错误**：Unicode 字符宽度计算可能不准确

### 边界情况
1. 命令包含极长的无空格 token
2. 终端宽度极窄
3. 命令包含制表符

### 改进建议
1. 考虑使用自适应缩进，根据上下文调整
2. 对极长 token 使用特殊处理（如截断）
3. 支持配置缩进宽度
