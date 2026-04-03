# Research: 多行命令换行额外缩进测试快照

## 场景与职责

该快照测试验证 `ExecCell` 在渲染多行命令时的换行行为，特别是当命令的某一行内容过长需要换行时，后续换行行的额外缩进处理。

这是 TUI 命令执行历史显示的重要功能，确保长命令在换行时仍能保持良好的可读性。

## 功能点目的

1. **长行自动换行**: 当命令行长度超过终端宽度时自动换行
2. **续行缩进**: 换行后的内容使用额外缩进（4个空格）与原始行区分
3. **多行独立处理**: 每行命令独立进行换行处理
4. **树形前缀保持**: 即使换行也保持树形前缀的视觉连贯性

## 具体技术实现

### 渲染格式

```
• Ran set -o pipefail
  │ cargo test
  │ --all-features --quiet
  └ (no output)
```

格式说明：
- `• Ran `: 命令执行的标题前缀
- `set -o pipefail`: 第一行命令（较短，无需换行）
- `│ cargo test`: 第二行命令的开始
- `│ --all-features --quiet`: 第二行命令的续行（4空格缩进）
- `└ (no output)`: 输出标记

### 关键代码逻辑

```rust
// 多行命令换行处理逻辑
fn render_wrapped_multiline_command(
    &self,
    lines: &[String],
    width: u16,
) -> Vec<Line<'static>> {
    let mut result = Vec::new();
    let prefix_width = 2; // "│ " 的宽度
    let continuation_indent = "    "; // 4 空格续行缩进
    
    // 第一行使用 "• Ran " 前缀
    result.push(Line::from(vec![
        "• ".dim(),
        "Ran ".bold(),
        lines[0].into(),
    ]));
    
    // 处理后续行
    for line in &lines[1..] {
        let wrap_width = width.saturating_sub(prefix_width + continuation_indent.len() as u16);
        let wrapped = textwrap::wrap(line, wrap_width as usize);
        
        for (idx, wrapped_line) in wrapped.iter().enumerate() {
            if idx == 0 {
                // 第一行使用 "│ " 前缀
                result.push(Line::from(vec![
                    "│ ".dim(),
                    wrapped_line.to_string().into(),
                ]));
            } else {
                // 续行使用 "│ " + 4 空格前缀
                result.push(Line::from(vec![
                    "│ ".dim(),
                    continuation_indent.into(),
                    wrapped_line.to_string().into(),
                ]));
            }
        }
    }
    
    result
}
```

### 测试数据构造

```rust
// history_cell.rs:3626-3651
let cmd = "set -o pipefail\ncargo test --all-features --quiet".to_string();
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

// 使用宽度 28 强制第二行换行
let width: u16 = 28;
let lines = cell.display_lines(width);
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/history_cell.rs` | 历史单元格渲染逻辑，测试位于行 3626-3651 |
| `codex-rs/tui/src/exec_cell/` | 命令执行单元格渲染实现 |
| `codex-rs/tui/src/wrapping.rs` | 自适应换行算法 |

### 测试代码位置

```rust
// history_cell.rs:3626-3651
#[test]
fn multiline_command_wraps_with_extra_indent_on_subsequent_lines() {
    let cmd = "set -o pipefail\ncargo test --all-features --quiet".to_string();
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

    let width: u16 = 28;
    let lines = cell.display_lines(width);
    let rendered = render_lines(&lines).join("\n");
    insta::assert_snapshot!(rendered);
}
```

## 依赖与外部交互

### 外部依赖

1. **textwrap**: 文本换行库
2. **ratatui**: TUI 渲染框架
3. **insta**: 快照测试框架

### 内部模块依赖

```rust
use crate::wrapping::adaptive_wrap_lines;
use crate::wrapping::RtOptions;
use crate::exec_cell::CommandOutput;
use crate::exec_cell::ExecCall;
use crate::exec_cell::ExecCell;
```

## 风险、边界与改进建议

### 潜在风险

1. **缩进层级混乱**: 多行命令的换行缩进与多行命令本身的缩进可能产生混淆
2. **宽度计算误差**: 续行缩进占用的宽度需要从可用宽度中减去，计算错误会导致渲染问题

### 边界情况

1. **单词过长**: 单个单词超过可用宽度时的处理
2. **多行同时换行**: 多行命令的每一行都需要换行时的渲染
3. **混合内容**: 命令中包含 URL、路径等不应被截断的内容

### 改进建议

1. **智能缩进**: 根据命令结构（如管道符 `|`、逻辑运算符 `&&` 等）进行智能缩进
2. **语法感知换行**: 在语法边界（如空格后）优先换行
3. **URL 保护**: 使用 `adaptive_wrap_lines` 避免在 URL 中间换行
4. **配置选项**: 允许用户自定义续行缩进宽度

### 相关快照文件

- `multiline_command_both_lines_wrap_with_correct_prefixes.snap` - 双行换行测试
- `multiline_command_without_wrap_uses_branch_then_eight_spaces.snap` - 无换行多行测试
