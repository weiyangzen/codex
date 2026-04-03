# 研究文档：ran_cell_multiline_with_stderr_snapshot.snap

## 场景与职责

此快照测试验证命令执行单元格在多行命令且有 stderr 输出时的显示效果。这是综合测试，验证命令和错误输出的正确显示。

## 功能点目的

1. **多行命令显示**：正确显示包含多行的命令
2. **stderr 分离**：清晰区分 stdout 和 stderr 输出
3. **错误标识**：通过样式或前缀标识错误输出

## 具体技术实现

### 快照输出分析

```
• Ran echo
  │ this_is_a_very_long_si
  │ ngle_token_that_will_w
  │ … +2 lines
  └ error: first line on
    stderr
    error: second line on
    stderr
```

关键元素：
- `• Ran echo` - 命令开始
- `│` - 命令行延续
- `… +2 lines` - 省略指示
- `└` - 输出开始
- `error:` - stderr 输出（红色样式）

### stderr 处理

```rust
fn render_command_output(stdout: &[String], stderr: &[String]) -> Vec<Line> {
    let mut lines = vec![];
    
    // 渲染 stdout
    for line in stdout {
        lines.push(Line::from(line.as_str()));
    }
    
    // 渲染 stderr（带错误样式）
    for line in stderr {
        lines.push(Line::from(Span::styled(line, Style::new().red())));
    }
    
    lines
}
```

## 关键代码路径与文件引用

1. **命令执行**：
   - `codex-rs/tui/src/exec_cell.rs` - ExecCell 实现
   - `codex-rs/tui/src/exec_command.rs` - 命令执行

2. **输出处理**：
   - `crate::exec_cell::CommandOutput`
   - `crate::exec_cell::output_lines`

## 依赖与外部交互

### 相关常量
- `TOOL_CALL_MAX_LINES` - 工具调用最大行数

## 风险、边界与改进建议

### 潜在风险
1. **stderr 过多**：大量错误输出可能淹没正常输出
2. **混合输出**：stdout 和 stderr 的时序关系丢失

### 边界情况
1. 只有 stderr 没有 stdout
2. stderr 包含二进制数据
3. 非常大的 stderr 输出

### 改进建议
1. 添加 stderr 折叠功能
2. 显示 stdout/stderr 的比例指示
3. 支持单独复制 stdout 或 stderr
4. 添加错误计数显示
