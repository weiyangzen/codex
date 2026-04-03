# Research: 多行命令无换行分支缩进测试快照

## 场景与职责

该快照测试验证 `ExecCell` 在渲染多行命令时的缩进行为，当命令包含多行内容但不需要换行（即每行都能在终端宽度内完整显示）时的渲染格式。

这是 TUI 命令执行历史显示的基础功能，确保简单多行命令的显示既美观又清晰。

## 功能点目的

1. **多行命令基础渲染**: 支持显示包含换行符的命令
2. **树形分支前缀**: 使用 `│` 字符作为多行命令的行前缀，形成视觉上的树形结构
3. **统一缩进**: 使用 8 个空格的缩进保持对齐
4. **简洁输出**: 当命令无输出时显示 `(no output)` 提示

## 具体技术实现

### 渲染格式

```
• Ran echo one
  │ echo two
  └ (no output)
```

格式说明：
- `• Ran `: 命令执行的标题前缀
- `echo one`: 第一行命令内容
- `│`: 多行命令的续行前缀（树形分支）
- `echo two`: 第二行命令内容
- `└`: 输出块的开始标记
- `(no output)`: 无输出提示

### 关键代码逻辑

```rust
// history_cell.rs 中的相关渲染逻辑
fn render_multiline_command(&self, lines: &[String], width: u16) -> Vec<Line<'static>> {
    let mut result = Vec::new();
    
    // 第一行使用 "• Ran " 前缀
    result.push(Line::from(vec![
        "• ".dim(),
        "Ran ".bold(),
        lines[0].into(),
    ]));
    
    // 后续行使用 "│ " 前缀 + 8 空格缩进
    for line in &lines[1..] {
        result.push(Line::from(vec![
            "│ ".dim(),
            line.into(),
        ]));
    }
    
    // 输出标记
    result.push(Line::from(vec![
        "└ ".dim(),
        "(no output)".dim().italic(),
    ]));
    
    result
}
```

### 测试数据构造

```rust
// history_cell.rs:3700-3720
let cmd = "echo one\necho two".to_string();
let call_id = "c1".to_string();
let mut cell = ExecCell::new(
    ExecCall {
        call_id: call_id.clone(),
        command: vec!["bash".into(), "-lc".into(), cmd],
        parsed: Vec::new(),
        output: None,
        source: ExecCommandSource::Agent,
        start_time: Some(Instant::now()),
        duration: None,
        interaction_input: None,
    },
    true,
);
cell.complete_call(&call_id, CommandOutput::default(), Duration::from_millis(1));

// 使用宽度 80，足够显示而不需要换行
let lines = cell.display_lines(80);
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/history_cell.rs` | 历史单元格渲染逻辑，测试位于行 3699-3720 |
| `codex-rs/tui/src/exec_cell/` | 命令执行单元格渲染实现 |

### 测试代码位置

```rust
// history_cell.rs:3699-3720
#[test]
fn multiline_command_without_wrap_uses_branch_then_eight_spaces() {
    let call_id = "c1".to_string();
    let cmd = "echo one\necho two".to_string();
    let mut cell = ExecCell::new(
        ExecCall {
            call_id: call_id.clone(),
            command: vec!["bash".into(), "-lc".into(), cmd],
            parsed: Vec::new(),
            output: None,
            source: ExecCommandSource::Agent,
            start_time: Some(Instant::now()),
            duration: None,
            interaction_input: None,
        },
        true,
    );
    cell.complete_call(&call_id, CommandOutput::default(), Duration::from_millis(1));
    let lines = cell.display_lines(80);
    let rendered = render_lines(&lines).join("\n");
    insta::assert_snapshot!(rendered);
}
```

## 依赖与外部交互

### 外部依赖

1. **ratatui**: 提供 TUI 渲染原语（`Line`、`Span` 等）
2. **insta**: 快照测试框架

### 内部模块依赖

```rust
use crate::exec_cell::CommandOutput;
use crate::exec_cell::ExecCall;
use crate::exec_cell::ExecCell;
use codex_protocol::protocol::ExecCommandSource;
```

## 风险、边界与改进建议

### 潜在风险

1. **前缀字符兼容性**: `│` 和 `└` 是 Unicode 字符，在某些终端可能显示不正确
2. **缩进硬编码**: 8 空格的缩进是硬编码的，可能不适合所有场景

### 边界情况

1. **空命令**: 命令为空字符串时的渲染
2. **仅空白字符**: 命令只包含空格或制表符
3. **尾随换行**: 命令以换行符结尾时的处理

### 改进建议

1. **配置化缩进**: 将 8 空格缩进提取为配置项
2. **ASCII 回退**: 在不支持 Unicode 的终端使用 ASCII 字符（`|` 和 `\`）
3. **语法高亮**: 对命令内容进行简单的语法高亮（如关键字、字符串等）
4. **折叠展开**: 对于超长的多行命令，支持折叠/展开交互

### 相关快照文件

- `multiline_command_both_lines_wrap_with_correct_prefixes.snap` - 双行换行测试
- `multiline_command_wraps_with_extra_indent_on_subsequent_lines.snap` - 单行换行测试
