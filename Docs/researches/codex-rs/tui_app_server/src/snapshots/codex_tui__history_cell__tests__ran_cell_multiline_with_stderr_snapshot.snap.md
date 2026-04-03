# 研究文档：ran_cell_multiline_with_stderr_snapshot

## 场景与职责

该快照测试验证 `ExecCell` 在完成状态下（"Ran"）渲染多行命令和 stderr 输出的行为。当 Codex 执行一个命令且该命令产生错误输出时，需要清晰地展示命令本身、执行状态以及 stderr 输出。

**核心职责**：
- 渲染已完成的命令执行单元（显示 "Ran" 而非 "Running"）
- 处理多行命令的换行和缩进
- 显示 stderr 输出，使用合适的视觉前缀区分
- 在窄宽度终端上正确处理文本换行

## 功能点目的

**从快照内容分析**：
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

**功能特性**：
1. **命令头**：`• Ran echo` - 使用绿色/红色粗体点表示完成状态
2. **命令延续**：使用 `│` 符号作为多行命令的延续前缀
3. **截断提示**：`… +2 lines` 表示命令被截断
4. **输出块**：使用 `└` 符号作为输出块的开始
5. **stderr 显示**：错误输出使用缩进对齐

## 具体技术实现

### ExecCell 渲染架构

**文件位置**：`codex-rs/tui/src/exec_cell/render.rs`

**核心结构**：
```rust
impl HistoryCell for ExecCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
        if self.is_exploring_cell() {
            self.exploring_display_lines(width)
        } else {
            self.command_display_lines(width)
        }
    }
}
```

### 命令显示布局

**常量定义**（第 682-687 行）：
```rust
const EXEC_DISPLAY_LAYOUT: ExecDisplayLayout = ExecDisplayLayout::new(
    PrefixedBlock::new("  │ ", "  │ "),  // 命令延续前缀
    /*command_continuation_max_lines*/ 2,  // 最大延续行数
    PrefixedBlock::new("  └ ", "    "),   // 输出块前缀
    /*output_max_lines*/ 5,                // 最大输出行数
);
```

### 渲染流程

**1. 头部渲染**（第 356-419 行）：
```rust
fn command_display_lines(&self, width: u16) -> Vec<Line<'static>> {
    let success = call.output.as_ref().map(|o| o.exit_code == 0);
    let bullet = match success {
        Some(true) => "•".green().bold(),
        Some(false) => "•".red().bold(),
        None => spinner(call.start_time, self.animations_enabled()),
    };
    
    let title = if call.is_user_shell_command() {
        "You ran"
    } else {
        "Ran"
    };
    
    // 构建头部行：• Ran <命令>
    let mut header_line = Line::from(vec![
        bullet.clone(), " ".into(), title.bold(), " ".into()
    ]);
    
    // 尝试将命令内联到头部
    let available_first_width = (width as usize).saturating_sub(header_prefix_width).max(1);
    // ... 换行和截断逻辑 ...
}
```

**2. 输出渲染**（第 433-496 行）：
```rust
if let Some(output) = call.output.as_ref() {
    let raw_output = output_lines(
        Some(output),
        OutputLinesParams {
            line_limit: TOOL_CALL_MAX_LINES,  // 5 行
            only_err: false,
            include_angle_pipe: false,
            include_prefix: false,
        },
    );
    
    // 使用 "  └ " 和 "    " 作为前缀
    let prefixed_output = prefix_lines(
        wrapped_output,
        Span::from(layout.output_block.initial_prefix).dim(),  // "  └ "
        Span::from(layout.output_block.subsequent_prefix),      // "    "
    );
}
```

### 中间截断算法

**`truncate_lines_middle`**（第 530-622 行）：
```rust
fn truncate_lines_middle(
    lines: &[Line<'static>],
    max_rows: usize,
    width: u16,
    omitted_hint: Option<usize>,
    ellipsis_prefix: Option<&Line<'static>>,
) -> Vec<Line<'static>> {
    // 计算每行的实际显示行数（考虑换行）
    let line_rows: Vec<usize> = lines
        .iter()
        .map(|line| {
            Paragraph::new(Text::from(vec![line.clone()]))
                .wrap(Wrap { trim: false })
                .line_count(width)
                .max(1)
        })
        .collect();
    
    // 保留头部和尾部，中间用省略号代替
    let head_budget = (max_rows - 1) / 2;
    let tail_budget = max_rows - head_budget - 1;
    // ... 截断逻辑 ...
}
```

## 关键代码路径与文件引用

### 主要文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui/src/exec_cell/render.rs` | `ExecCell` 渲染实现 |
| `codex-rs/tui/src/exec_cell/model.rs` | `ExecCell` 和 `ExecCall` 数据模型 |
| `codex-rs/tui/src/history_cell.rs` | HistoryCell trait 定义 |

### 测试代码

**位置**：`codex-rs/tui/src/history_cell.rs` 第 3792-3840 行

```rust
#[test]
fn ran_cell_multiline_with_stderr_snapshot() {
    let call_id = "c_wrap_err".to_string();
    let long_cmd =
        "echo this_is_a_very_long_single_token_that_will_wrap_across_the_available_width";
    let mut cell = ExecCell::new(
        ExecCall {
            call_id: call_id.clone(),
            command: vec!["bash".into(), "-lc".into(), long_cmd.to_string()],
            parsed: Vec::new(),
            output: None,
            source: ExecCommandSource::Agent,
            start_time: Some(Instant::now()),
            duration: None,
            interaction_input: None,
        },
        true,
    );

    let stderr = "error: first line on stderr\nerror: second line on stderr".to_string();
    cell.complete_call(
        &call_id,
        CommandOutput {
            exit_code: 1,
            formatted_output: String::new(),
            aggregated_output: stderr,
        },
        Duration::from_millis(5),
    );

    let width: u16 = 28;
    let rendered = cell
        .display_lines(width)
        .iter()
        .map(|l| { /* 提取文本 */ })
        .collect::<Vec<_>>()
        .join("\n");
    insta::assert_snapshot!(rendered);
}
```

### 关键数据结构

```rust
// ExecCell 模型
pub(crate) struct ExecCell {
    pub(crate) calls: Vec<ExecCall>,
    animations_enabled: bool,
}

pub(crate) struct ExecCall {
    pub(crate) call_id: String,
    pub(crate) command: Vec<String>,
    pub(crate) parsed: Vec<ParsedCommand>,
    pub(crate) output: Option<CommandOutput>,
    pub(crate) source: ExecCommandSource,
    pub(crate) start_time: Option<Instant>,
    pub(crate) duration: Option<Duration>,
    pub(crate) interaction_input: Option<String>,
}

pub(crate) struct CommandOutput {
    pub(crate) exit_code: i32,
    pub(crate) aggregated_output: String,
    pub(crate) formatted_output: String,
}
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `ratatui` | 终端 UI 渲染框架 |
| `textwrap` | 文本换行处理 |
| `unicode_width` | Unicode 字符串宽度计算 |

### 内部依赖

- `crate::exec_command::strip_bash_lc_and_escape`：清理 bash 命令显示
- `crate::render::highlight::highlight_bash_to_lines`：Bash 语法高亮
- `crate::wrapping::adaptive_wrap_line`：自适应文本换行
- `crate::render::line_utils::prefix_lines`：行前缀处理

### 渲染流程图

```
ExecCell::display_lines(width)
└── command_display_lines(width)
    ├── 1. 构建头部（bullet + title + 命令第一行）
    │   └── 如果命令太长，使用 "  │ " 前缀继续
    ├── 2. 限制延续行数（最多 2 行）
    │   └── 超出部分显示 "… +N lines"
    └── 3. 渲染输出
        ├── 如果无输出：显示 "(no output)"
        └── 如果有输出：
            ├── 使用 "  └ " 作为第一行前缀
            ├── 使用 "    " 作为后续行前缀
            └── 限制最多 5 行，中间截断
```

## 风险、边界与改进建议

### 潜在风险

1. **硬编码限制**：
   - `command_continuation_max_lines = 2` 可能不足以显示复杂命令
   - `output_max_lines = 5` 可能遗漏重要错误信息

2. **宽度计算精度**：
   - 使用 `Paragraph::line_count` 估算行数，可能与实际渲染有偏差
   - 某些 Unicode 字符的宽度计算可能不准确

3. **stderr/stdout 混淆**：
   - `aggregated_output` 混合了 stderr 和 stdout
   - 无法区分错误输出和正常输出

### 边界情况

| 场景 | 当前行为 | 评估 |
|-----|---------|------|
| 命令极短 | 内联显示在头部 | ✅ 节省空间 |
| 命令超长 | 截断，显示 "… +N lines" | ⚠️ 可能丢失关键信息 |
| 无输出 | 显示 "(no output)" | ✅ 明确 |
| 输出超过 5 行 | 中间截断，显示省略号 | ⚠️ 可能遗漏重要信息 |
| 非零退出码 | 使用红色点表示 | ✅ 视觉提示清晰 |

### 改进建议

1. **可配置的限制**：
   ```rust
   pub struct ExecDisplayConfig {
       pub max_command_lines: usize,  // 默认 2
       pub max_output_lines: usize,   // 默认 5
   }
   ```

2. **展开/折叠功能**：
   - 添加键盘快捷键（如 Enter）展开完整命令和输出
   - 使用 `...` 作为可点击的展开提示

3. **分离 stderr 和 stdout**：
   ```rust
   pub(crate) struct CommandOutput {
       pub(crate) exit_code: i32,
       pub(crate) stdout: String,
       pub(crate) stderr: String,
       // 分别渲染 stderr（红色）和 stdout（正常）
   }
   ```

4. **智能截断**：
   ```rust
   // 优先保留关键信息（如错误消息、文件名等）
   fn smart_truncate(output: &str, max_lines: usize) -> String {
       // 识别并保留错误行、堆栈跟踪等
   }
   ```

5. **改进视觉层次**：
   ```rust
   // 使用不同颜色区分命令和输出
   // 命令：青色
   // 输出：默认色
   // 错误：红色
   ```

6. **添加时间戳**：
   ```rust
   // 在 "Ran" 后显示执行时间
   "• Ran echo (in 1.2s)"
   ```
