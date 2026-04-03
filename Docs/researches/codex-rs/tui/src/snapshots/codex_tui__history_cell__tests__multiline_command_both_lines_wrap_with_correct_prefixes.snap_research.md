# Research: 多行命令双行换行前缀测试快照

## 场景与职责

该快照测试验证 `ExecCell` 在渲染多行命令时的文本换行行为。当命令包含多行内容（通过 `\n` 分隔）且每行都足够长以至于需要换行时，系统需要正确处理每行的前缀缩进。

这是 TUI（终端用户界面）中命令执行历史显示的核心功能，确保用户在查看复杂命令时能够清晰地识别命令的不同部分。

## 功能点目的

1. **多行命令渲染**: 支持显示包含换行符的复杂命令
2. **智能换行**: 当命令行长度超过终端宽度时，自动换行并保持一致的前缀缩进
3. **前缀一致性**: 确保第一行和后续行都有正确的前缀标识（`│` 或空格）
4. **行数提示**: 当内容被截断时，显示剩余行数提示（如 `… +1 lines`）

## 具体技术实现

### 关键数据结构

```rust
// ExecCell 结构（位于 exec_cell/model.rs）
pub(crate) struct ExecCell {
    pub(crate) calls: Vec<ExecCall>,
    animations_enabled: bool,
}

pub(crate) struct ExecCall {
    pub(crate) call_id: String,
    pub(crate) command: Vec<String>,  // 命令参数
    pub(crate) parsed: Vec<ParsedCommand>,
    pub(crate) output: Option<CommandOutput>,
    pub(crate) source: ExecCommandSource,
    // ...
}
```

### 渲染流程

1. **命令解析**: 从 `ExecCall.command` 中提取命令字符串
2. **换行检测**: 使用 `adaptive_wrap_lines` 函数（位于 `wrapping.rs`）检测是否需要换行
3. **前缀处理**: 
   - 第一行使用 `• Ran ` 前缀
   - 多行命令的每行使用 `│` 前缀
   - 换行后的续行使用额外缩进（8个空格）

### 关键代码路径

```rust
// history_cell.rs 中的测试代码
let cmd = "first_token_is_long_enough_to_wrap\nsecond_token_is_also_long_enough_to_wrap".to_string();
let mut cell = ExecCell::new(
    ExecCall {
        call_id: call_id.clone(),
        command: vec!["bash".into(), "-lc".into(), cmd],
        // ...
    },
    true,
);
cell.complete_call(&call_id, CommandOutput::default(), Duration::from_millis(1));

// 使用宽度 28 强制换行
let width: u16 = 28;
let lines = cell.display_lines(width);
```

### 换行算法

使用 `textwrap` 库配合自定义的 `RtOptions` 配置：

```rust
// wrapping.rs
pub(crate) fn adaptive_wrap_lines(
    lines: impl IntoIterator<Item = Line<'static>>,
    opts: RtOptions,
) -> Vec<Line<'static>> {
    // 检测 URL 类内容，避免在 URL 中间换行
    // 使用 AsciiSpace 分词和自定义 WordSplitter
}
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/history_cell.rs` | 主要历史单元格渲染逻辑，包含该测试用例（行 3723-3744） |
| `codex-rs/tui/src/exec_cell/model.rs` | ExecCell 和 ExecCall 数据结构定义 |
| `codex-rs/tui/src/wrapping.rs` | 自适应换行算法实现 |
| `codex-rs/tui/src/exec_cell/` | 命令执行单元格的完整渲染实现 |

### 测试代码位置

```rust
// history_cell.rs:3723-3744
#[test]
fn multiline_command_both_lines_wrap_with_correct_prefixes() {
    let call_id = "c1".to_string();
    let cmd = "first_token_is_long_enough_to_wrap\nsecond_token_is_also_long_enough_to_wrap"
        .to_string();
    let mut cell = ExecCell::new(/* ... */);
    // ...
    let width: u16 = 28;
    let lines = cell.display_lines(width);
    let rendered = render_lines(&lines).join("\n");
    insta::assert_snapshot!(rendered);
}
```

## 依赖与外部交互

### 外部依赖

1. **textwrap**: 文本换行库，提供基础换行功能
2. **ratatui**: TUI 框架，提供 `Line`、`Span`、`Text` 等渲染原语
3. **unicode-width**: 用于计算字符串的显示宽度
4. **unicode-segmentation**: 处理 Unicode 字符边界

### 内部模块依赖

```rust
use crate::wrapping::RtOptions;
use crate::wrapping::adaptive_wrap_line;
use crate::wrapping::adaptive_wrap_lines;
use crate::exec_cell::CommandOutput;
use crate::exec_cell::ExecCall;
use crate::exec_cell::ExecCell;
```

## 风险、边界与改进建议

### 潜在风险

1. **宽度计算不准确**: 如果 `unicode-width` 对某些特殊字符的宽度计算有误，可能导致换行位置不正确
2. **性能问题**: 非常长的命令（数千行）可能在换行时产生性能瓶颈
3. **前缀错位**: 多行命令的前缀对齐逻辑复杂，容易在边界情况下出错

### 边界情况

1. **极窄终端**: 当终端宽度小于前缀长度时，渲染可能异常
2. **混合宽度字符**: 中英文混合、emoji 等可能导致宽度计算偏差
3. **空行处理**: 命令中包含空行时的前缀处理

### 改进建议

1. **增加最小宽度保护**: 在 `display_lines` 中添加最小宽度检查，避免极窄终端下的渲染问题
2. **性能优化**: 对于超长命令，考虑使用惰性渲染或虚拟滚动
3. **配置化前缀**: 将前缀字符（`│`、`•` 等）提取为可配置项，支持主题定制
4. **增强测试覆盖**: 增加以下测试用例：
   - 包含 emoji 的命令
   - 包含中文的命令
   - 极窄宽度（< 10）的渲染
   - 包含制表符的命令

### 相关快照文件

- `multiline_command_wraps_with_extra_indent_on_subsequent_lines.snap` - 单行换行缩进测试
- `multiline_command_without_wrap_uses_branch_then_eight_spaces.snap` - 无换行多行测试
- `single_line_command_wraps_with_four_space_continuation.snap` - 单行命令换行测试
