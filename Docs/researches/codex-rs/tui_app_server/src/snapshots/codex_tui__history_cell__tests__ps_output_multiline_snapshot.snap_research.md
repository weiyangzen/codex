# 研究文档：ps_output_multiline_snapshot.snap

## 场景与职责

此快照测试验证 `/ps` 命令输出中多行输出的显示。当后台会话的输出包含多行时，应该正确显示这些输出。

## 功能点目的

1. **多行输出支持**：支持显示包含多行的会话输出
2. **输出标识**：清晰标识哪些行是会话输出
3. **层次结构**：保持命令和输出的层次关系

## 具体技术实现

### 快照输出分析

```
/ps

Background terminals

  • echo hello [...]
    ↳ hello
      done
  • rg "foo" src
    ↳ src/main.rs:12:foo
```

显示结构：
- `• echo hello [...]` - 会话命令（截断显示）
- `↳ hello` - 输出第一行
- `  done` - 输出第二行（额外缩进）
- `• rg "foo" src` - 另一个会话
- `↳ src/main.rs:12:foo` - 其输出

### 多行输出处理

```rust
fn format_session_output(output: &[String]) -> Vec<Line> {
    let mut lines = vec![];
    for (i, line) in output.iter().enumerate() {
        if i == 0 {
            lines.push(Line::from(format!("↳ {line}")));
        } else {
            // 后续行有额外缩进
            lines.push(Line::from(format!("  {line}")));
        }
    }
    lines
}
```

## 关键代码路径与文件引用

1. **输出处理**：
   - `crate::exec_cell::output_lines`
   - `codex-rs/tui/src/exec_cell.rs`

2. **会话显示**：
   - `codex-rs/tui/src/history_cell.rs`

## 依赖与外部交互

### 相关类型
- `CommandOutput` - 命令输出
- `OutputLinesParams` - 输出行参数

## 风险、边界与改进建议

### 潜在风险
1. **输出过长**：大量输出行可能导致显示过长
2. **格式混乱**：输出中的特殊字符可能破坏格式

### 边界情况
1. 空输出
2. 只有空白字符的输出
3. 输出包含 ANSI 转义序列

### 改进建议
1. 限制显示的输出行数，提供展开功能
2. 支持 ANSI 颜色序列的解析和显示
3. 添加输出搜索功能
