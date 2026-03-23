# exec_cell/render.rs 研究文档

## 场景与职责

`exec_cell/render.rs` 是 TUI 中命令执行单元格的渲染引擎，负责将 `ExecCell` 数据模型转换为 ratatui 可显示的 `Line` 序列。该模块是用户体验的核心，直接影响命令执行过程的可读性和美观性。

### 核心职责

1. **双模式渲染**：
   - **探索模式（Exploring）**：聚合显示多个轻量级命令（Read/ListFiles/Search），显示为"Exploring"或"Explored"
   - **命令模式（Command）**：详细显示单个命令的完整信息，包括命令本身、输出、执行状态

2. **智能输出截断**：
   - 行数限制（默认 5 行，用户 Shell 命令 50 行）
   - 中间截断（显示头部和尾部，中间用"… +N lines"省略）
   - 视口感知（基于实际渲染行数而非逻辑行数）

3. **视觉反馈**：
   - 加载动画（spinner/shimmer）
   - 成功/失败状态指示（绿色/红色圆点）
   - 语法高亮（bash 命令）

4. **转录模式支持**：
   - `Ctrl+T` 转录覆盖层使用独立的 `transcript_lines` 实现
   - 显示 `$` 前缀的命令和退出状态

## 功能点目的

### 核心常量

```rust
pub(crate) const TOOL_CALL_MAX_LINES: usize = 5;
const USER_SHELL_TOOL_CALL_MAX_LINES: usize = 50;
const MAX_INTERACTION_PREVIEW_CHARS: usize = 80;
```

| 常量 | 值 | 用途 |
|------|-----|------|
| `TOOL_CALL_MAX_LINES` | 5 | Agent 工具调用的默认输出行限制 |
| `USER_SHELL_TOOL_CALL_MAX_LINES` | 50 | 用户 Shell 命令的输出限制（更宽松） |
| `MAX_INTERACTION_PREVIEW_CHARS` | 80 | 统一执行交互输入预览的最大字符数 |

### 输出渲染参数

```rust
pub(crate) struct OutputLinesParams {
    pub(crate) line_limit: usize,
    pub(crate) only_err: bool,           // 仅显示错误输出
    pub(crate) include_angle_pipe: bool, // 包含角管道前缀
    pub(crate) include_prefix: bool,     // 包含缩进前缀
}
```

### 工厂函数

```rust
pub(crate) fn new_active_exec_command(
    call_id: String,
    command: Vec<String>,
    parsed: Vec<ParsedCommand>,
    source: ExecCommandSource,
    interaction_input: Option<String>,
    animations_enabled: bool,
) -> ExecCell
```

创建新的活跃执行命令单元格，自动设置开始时间为当前时间。

### 输出处理函数

```rust
pub(crate) fn output_lines(
    output: Option<&CommandOutput>,
    params: OutputLinesParams,
) -> OutputLines
```

将命令输出处理为可显示的行序列，支持：
- 仅错误模式（`only_err=true` 且 exit_code=0 时返回空）
- 头部/尾部分段显示
- 省略计数

### 加载动画

```rust
pub(crate) fn spinner(start_time: Option<Instant>, animations_enabled: bool) -> Span<'static>
```

智能加载指示器：
- 动画禁用时显示静态"•"
- 支持真彩色终端使用 shimmer 效果
- 回退到 600ms 周期的闪烁动画

## 具体技术实现

### HistoryCell Trait 实现

```rust
impl HistoryCell for ExecCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
        if self.is_exploring_cell() {
            self.exploring_display_lines(width)
        } else {
            self.command_display_lines(width)
        }
    }

    fn transcript_lines(&self, width: u16) -> Vec<Line<'static>> {
        // 转录模式：$ 前缀命令 + 退出状态
    }
}
```

### 探索模式渲染流程

```rust
fn exploring_display_lines(&self, width: u16) -> Vec<Line<'static>>
```

1. **标题行**：
   - 活跃状态：`• Exploring`（带动画）
   - 完成状态：`• Explored`（灰色静态）

2. **命令聚合**：
   - 连续 `Read` 命令合并显示（如 `Read file1, file2, file3`）
   - 其他命令类型单独显示

3. **格式化**：
   ```
   • Exploring
     └ Read file1, file2
       List /path
       Search "query" in /path
   ```

### 命令模式渲染流程

```rust
fn command_display_lines(&self, width: u16) -> Vec<Line<'static>>
```

1. **标题行**：
   - 状态圆点（绿色/红色/动画）
   - 标题文本（"Running"/"You ran"/"Ran"）
   - 命令本身（bash 语法高亮）

2. **命令续行**：
   - 长命令自动换行
   - 使用 `"  │ "` 前缀保持对齐
   - 限制最大续行数（2 行）

3. **输出块**：
   - 使用 `"  └ "` 和 `"    "` 前缀
   - 自适应换行（URL 感知）
   - 中间截断处理

### 智能截断算法

```rust
fn truncate_lines_middle(
    lines: &[Line<'static>],
    max_rows: usize,
    width: u16,
    omitted_hint: Option<usize>,
    ellipsis_prefix: Option<Line<'static>>,
) -> Vec<Line<'static>>
```

**算法步骤**：

1. **行高计算**：
   ```rust
   let line_rows: Vec<usize> = lines
       .iter()
       .map(|line| {
           Paragraph::new(Text::from(vec![line.clone()]))
               .wrap(Wrap { trim: false })
               .line_count(width)
       })
       .collect();
   ```

2. **预算分配**：
   - 总预算 = `max_rows`
   - 省略行占 1
   - 头部预算 = `(max_rows - 1) / 2`
   - 尾部预算 = `max_rows - head_budget - 1`

3. **内容选择**：
   - 从头部开始累加，直到超出预算
   - 从尾部反向累加，直到超出预算
   - 中间插入省略行 `"… +N lines"`

### 统一执行交互格式化

```rust
fn format_unified_exec_interaction(command: &[String], input: Option<&str>) -> String
```

- 提取 bash 脚本内容（去除 `bash -lc` 包装）
- 输入预览截断（80 字符限制，换行转义为 `\n`）
- 生成 `"Interacted with '{cmd}', sent '{preview}'"` 或 `"Waited for '{cmd}'"`

### 布局配置

```rust
const EXEC_DISPLAY_LAYOUT: ExecDisplayLayout = ExecDisplayLayout::new(
    PrefixedBlock::new("  │ ", "  │ "),
    /*command_continuation_max_lines*/ 2,
    PrefixedBlock::new("  └ ", "    "),
    /*output_max_lines*/ 5,
);
```

| 元素 | 首行前缀 | 续行前缀 | 最大行数 |
|------|----------|----------|----------|
| 命令续行 | `  │ ` | `  │ ` | 2 |
| 输出块 | `  └ ` | `    ` | 5 |

## 关键代码路径与文件引用

### 渲染调用链

```
TUI 主循环
    ↓
HistoryCell::display_lines(width)
    ↓
ExecCell::exploring_display_lines / command_display_lines
    ↓
自适应换行 (adaptive_wrap_line / adaptive_wrap_lines)
    ↓
语法高亮 (highlight_bash_to_lines)
    ↓
ANSI 转义处理 (ansi_escape_line)
    ↓
ratatui::Line 序列
```

### 外部依赖

| 模块 | 用途 |
|------|------|
| `crate::wrapping` | URL 感知的自适应文本换行 |
| `crate::render::highlight` | bash 语法高亮 |
| `crate::render::line_utils` | 行工具（prefix_lines, push_owned_lines）|
| `crate::shimmer` | 真彩色 shimmer 动画效果 |
| `codex_ansi_escape` | ANSI 转义序列处理 |
| `codex_shell_command::bash` | bash 命令提取 |
| `codex_utils_elapsed` | 持续时间格式化 |

### 与 tui/src/exec_cell/render.rs 的关系

`tui_app_server/src/exec_cell/render.rs` 与 `tui/src/exec_cell/render.rs` 是平行实现，遵循 AGENTS.md 中的约定：

> When a change lands in `codex-rs/tui` and `codex-rs/tui_app_server` has a parallel implementation of the same behavior, reflect the change in `codex-rs/tui_app_server` too unless there is a documented reason not to.

两者代码结构高度相似，维护时需同步更新。

## 依赖与外部交互

### 上游数据流

```
protocol::ExecCommandBeginEvent
    → new_active_exec_command() → ExecCell

protocol::ExecCommandOutputEvent
    → ExecCell::append_output() → 更新 aggregated_output

protocol::ExecCommandEndEvent
    → ExecCell::complete_call() → 设置 output, duration
```

### 下游渲染流

```
ExecCell::display_lines(width)
    → Vec<Line<'static>>
    → ratatui::Paragraph::new()
    → 终端缓冲区
```

### 跨模块 trait 实现

```rust
// history_cell.rs 定义 trait
pub(crate) trait HistoryCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>>;
    fn transcript_lines(&self, width: u16) -> Vec<Line<'static>>;
    fn desired_height(&self, width: u16) -> u16;
    fn desired_transcript_height(&self, width: u16) -> u16;
}

// render.rs 为 ExecCell 实现
display_lines() 和 transcript_lines()
```

## 风险、边界与改进建议

### 当前风险

1. **panic 风险**：`command_display_lines` 中使用 `let [call] = &self.calls.as_slice() else { panic!(...) }`
   - 触发条件：探索模式单元格错误地进入命令渲染路径
   - 缓解：`display_lines` 已正确分支，但防御性编程可考虑返回错误行而非 panic

2. **性能风险**：`truncate_lines_middle` 使用 `Paragraph::line_count` 计算每行高度
   - 复杂度：O(n × Paragraph 渲染)
   - 触发条件：极宽终端 + 极长行
   - 现状：测试覆盖了大 URL 场景，表现可接受

3. **URL 检测误判**：`adaptive_wrap_line` 的 URL 启发式检测可能产生假阳性/假阴性
   - 假阳性：非 URL 被保护，导致换行不自然
   - 假阴性：URL 被分割，终端中不可点击

### 边界情况

1. **零宽度终端**：多处使用 `width.max(1)` 防止除零，但 `width=0` 时渲染结果为空

2. **空输出**：`output_lines` 处理 `None` 和空字符串，显示 `(no output)` 或空

3. **超长 URL**：测试用例显示 2000+ 字符的 URL 能正确处理，中间截断算法按视口行数计算

4. **ANSI 序列**：`ansi_escape_line` 处理包含颜色代码的输出，但警告多行输入

### 测试覆盖

模块包含 7 个测试用例：

| 测试 | 目的 |
|------|------|
| `user_shell_output_is_limited_by_screen_lines` | 验证视口行数限制（非逻辑行数）|
| `truncate_lines_middle_keeps_omitted_count_in_line_units` | 省略计数使用逻辑行单位 |
| `truncate_lines_middle_does_not_truncate_blank_prefixed_output_lines` | 空白前缀行正确处理 |
| `command_display_does_not_split_long_url_token` | 命令中的 URL 不被分割 |
| `exploring_display_does_not_split_long_url_like_search_query` | 探索模式 URL 处理 |
| `output_display_does_not_split_long_url_like_token_without_scheme` | 无 scheme URL 处理 |
| `desired_transcript_height_accounts_for_wrapped_url_like_rows` | 转录高度计算包含换行 |

### 改进建议

1. **错误处理强化**：
   ```rust
   // 替代 panic
   fn command_display_lines(&self, width: u16) -> Vec<Line<'static>> {
       match self.calls.as_slice() {
           [call] => /* 正常渲染 */,
           _ => vec![Line::from("Error: Invalid exec cell state".red())],
       }
   }
   ```

2. **缓存优化**：
   ```rust
   // 缓存行高计算结果
   struct CachedLineHeight {
       line: Line<'static>,
       width: u16,
       height: usize,
   }
   ```

3. **配置外部化**：
   ```rust
   // 将常量改为可配置
   pub struct RenderConfig {
       tool_call_max_lines: usize,
       user_shell_max_lines: usize,
       interaction_preview_chars: usize,
   }
   ```

4. **无障碍增强**：
   - 为颜色编码状态（绿/红）添加符号或文字备用
   - 支持减少动画偏好（prefers-reduced-motion）

5. **代码复用**：
   - `tui` 和 `tui_app_server` 的 render.rs 有大量重复代码
   - 考虑提取公共库或宏减少维护负担

### 相关变更注意事项

- 修改 `PrefixedBlock` 前缀会影响整个 TUI 的视觉风格
- 调整 `TOOL_CALL_MAX_LINES` 需同步更新测试中的期望值
- 新增 `ParsedCommand` 类型需更新 `exploring_display_lines` 的匹配逻辑
- ANSI 处理逻辑变更需检查 `ansi_escape_line` 的兼容性
