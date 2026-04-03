# 研究文档：single_line_command_compact_when_fits.snap

## 场景与职责

此快照测试验证单行命令在终端宽度足够时的紧凑显示。当命令很短时，应该以紧凑的单行格式显示。

## 功能点目的

1. **紧凑显示**：短命令使用单行显示，节省空间
2. **可读性**：避免不必要的换行
3. **一致性**：保持命令显示的统一风格

## 具体技术实现

### 快照输出分析

```
• Ran echo ok
  └ (no output)
```

设计特点：
- 命令和指示器在同一行
- `└` 符号表示输出开始
- `(no output)` 明确表示没有输出

### 紧凑显示逻辑

```rust
fn render_command_compact(command: &str, output: Option<&CommandOutput>) -> Vec<Line> {
    let mut lines = vec![];
    
    // 检查命令长度是否适合单行显示
    if command.width() + "• Ran ".len() < width as usize {
        lines.push(Line::from(format!("• Ran {command}")));
    } else {
        // 使用多行显示
        lines.extend(render_command_multiline(command));
    }
    
    // 输出
    match output {
        Some(out) if !out.is_empty() => {
            lines.extend(render_output(out));
        }
        _ => {
            lines.push(Line::from("  └ (no output)"));
        }
    }
    
    lines
}
```

## 关键代码路径与文件引用

1. **命令渲染**：
   - `codex-rs/tui/src/exec_cell.rs`
   - `codex-rs/tui/src/history_cell.rs`

2. **输出处理**：
   - `crate::exec_cell::CommandOutput`

## 依赖与外部交互

### 相关类型
- `CommandOutput` - 命令输出结构

## 风险、边界与改进建议

### 边界情况
1. 命令正好等于最大宽度
2. 命令包含多字节字符
3. 空命令

### 改进建议
1. 考虑隐藏 `(no output)` 以进一步节省空间
2. 添加配置选项控制紧凑模式
3. 支持命令语法高亮
