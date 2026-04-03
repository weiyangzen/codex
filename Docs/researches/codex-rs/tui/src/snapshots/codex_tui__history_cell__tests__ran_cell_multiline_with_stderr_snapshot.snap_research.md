# Research Document: Ran Cell Multiline with Stderr Snapshot

## 场景与职责

此快照测试验证 **ExecCell** 组件在渲染已完成的命令执行（"Ran"状态）时的行为，特别是当命令文本较长需要换行、且命令产生 stderr 输出时的渲染效果。这是 Codex TUI 中命令执行历史记录展示的核心场景之一。

该组件负责：
- 展示命令执行状态（Running/Ran/You ran）
- 渲染命令本身的文本（支持语法高亮和自动换行）
- 展示命令的输出结果（stdout/stderr）
- 处理长命令的换行和缩进对齐

## 功能点目的

**主要功能**：验证 ExecCell 在以下复杂场景下的渲染正确性：

1. **长命令换行**：命令文本 `this_is_a_very_long_single_token_that_will_wrap_across_the_available_width` 超过终端宽度时需要正确换行
2. **视觉层次**：使用树形结构符号（`•`、`│`、`└`）构建清晰的视觉层次
3. **stderr 输出展示**：错误输出需要以特定的前缀和样式展示
4. **行数限制与省略**：当输出行数超过限制时，显示 `… +N lines` 省略提示

**预期输出结构**：
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

## 具体技术实现

### 核心数据结构

**ExecCell**（位于 `exec_cell/model.rs`）：
```rust
#[derive(Debug)]
pub(crate) struct ExecCell {
    pub(crate) calls: Vec<ExecCall>,
    animations_enabled: bool,
}

#[derive(Clone, Debug, Default)]
pub(crate) struct CommandOutput {
    pub(crate) exit_code: i32,
    pub(crate) aggregated_output: String,  // 聚合的 stderr + stdout
    pub(crate) formatted_output: String,   // 格式化后的模型可见输出
}
```

**ExecDisplayLayout**（位于 `exec_cell/render.rs`）：
```rust
const EXEC_DISPLAY_LAYOUT: ExecDisplayLayout = ExecDisplayLayout::new(
    PrefixedBlock::new("  │ ", "  │ "),     // 命令续行前缀
    /*command_continuation_max_lines*/ 2,
    PrefixedBlock::new("  └ ", "    "),     // 输出块前缀
    /*output_max_lines*/ 5,
);
```

### 关键渲染流程

1. **命令渲染**（`command_display_lines` 方法）：
   - 使用 `strip_bash_lc_and_escape` 处理命令文本
   - 通过 `highlight_bash_to_lines` 应用语法高亮
   - 使用 `adaptive_wrap_line` 进行自适应换行（保持 URL 类文本不分割）

2. **输出渲染**（`output_lines` 函数）：
   - 解析 `aggregated_output` 为行列表
   - 应用 ANSI 转义序列处理（`ansi_escape_line`）
   - 实现头尾展示策略：显示前 `line_limit` 行和后 `line_limit` 行，中间用省略号

3. **行数截断**（`truncate_lines_middle` 方法）：
   - 计算每行在视口中的实际占用行数（考虑自动换行）
   - 保留头部和尾部，中间插入 `… +N lines`

### 样式应用

- 成功状态：`"•".green().bold()`
- 失败状态：`"•".red().bold()`
- 进行中状态：`spinner()` 动画
- 输出文本：应用 `Modifier::DIM` 变暗样式

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/exec_cell/model.rs` | ExecCell 数据模型定义 |
| `codex-rs/tui/src/exec_cell/render.rs` | ExecCell 渲染逻辑，包括 `command_display_lines`、`output_lines`、`truncate_lines_middle` |
| `codex-rs/tui/src/history_cell.rs` | HistoryCell trait 定义，包含测试用例 `ran_cell_multiline_with_stderr_snapshot` |
| `codex-rs/tui/src/wrapping.rs` | 自适应换行逻辑 `adaptive_wrap_line` |
| `codex-rs/tui/src/render/line_utils.rs` | 行工具函数 `prefix_lines`、`push_owned_lines` |

### 测试代码位置

```rust
// history_cell.rs 第 3793-3840 行
#[test]
fn ran_cell_multiline_with_stderr_snapshot() {
    let call_id = "c_wrap_err".to_string();
    let long_cmd = "echo this_is_a_very_long_single_token_that_will_wrap...";
    let mut cell = ExecCell::new(...);
    let stderr = "error: first line on stderr\nerror: second line on stderr".to_string();
    cell.complete_call(&call_id, CommandOutput { ... }, Duration::from_millis(5));
    let width: u16 = 28;  // 窄宽度强制换行
    insta::assert_snapshot!(rendered);
}
```

## 依赖与外部交互

### 内部依赖

- **ratatui**: 终端 UI 渲染框架，使用 `Line`、`Span`、`Paragraph`、`Wrap` 等类型
- **textwrap**: 文本换行算法库
- **unicode-width**: Unicode 字符宽度计算
- **codex-ansi-escape**: ANSI 转义序列处理

### 外部协议依赖

- **codex-protocol**: `ParsedCommand`、`ExecCommandSource` 等协议类型

### 相关组件交互

```
ChatWidget (聊天主组件)
    └── HistoryCell (历史记录单元)
            └── ExecCell (命令执行单元)
                    ├── ExecCall (单个调用)
                    │       ├── command: Vec<String>
                    │       └── output: Option<CommandOutput>
                    └── 渲染输出
```

## 风险、边界与改进建议

### 已知风险

1. **宽度计算精度**：在极端窄宽度（< 4 列）下可能出现布局错乱
2. **Unicode 字符处理**：某些宽字符（如 CJK）的宽度计算可能存在偏差
3. **ANSI 序列嵌套**：复杂的 ANSI 颜色嵌套可能导致样式丢失

### 边界情况

| 场景 | 当前行为 |
|------|---------|
| 命令为空 | 渲染为 `"(no output)"` |
| 输出为空 | 显示 `"(no output)"` |
| 输出行数 > 2*line_limit | 显示头尾，中间省略 |
| 终端宽度极窄 | 最小宽度保护为 1 |

### 改进建议

1. **性能优化**：
   - 对于超大型输出（如 MB 级日志），考虑延迟加载或虚拟滚动
   - 缓存渲染结果避免重复计算

2. **可访问性**：
   - 增加对屏幕阅读器的支持，为符号（`•`、`│`、`└`）提供语义化替代文本
   - 支持高对比度模式

3. **功能扩展**：
   - 支持点击/快捷键展开折叠的输出内容
   - 增加输出内容的搜索功能
   - 支持输出内容的复制

4. **代码质量**：
   - 将 `EXEC_DISPLAY_LAYOUT` 的硬编码参数改为可配置
   - 增加更多边界情况的单元测试
