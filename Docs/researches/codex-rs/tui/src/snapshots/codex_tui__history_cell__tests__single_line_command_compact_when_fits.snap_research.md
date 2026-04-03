# Research Document: Single Line Command Compact When Fits Snapshot

## 场景与职责

此快照测试验证 **ExecCell** 组件在渲染短命令时的紧凑布局行为。当命令文本较短、能在单行内完整显示时，组件应采用内联（inline）布局，将命令与标题放在同一行，以节省垂直空间。

该组件负责：
- 智能判断命令长度，选择最优布局方式
- 短命令：标题和命令在同一行（紧凑布局）
- 长命令：标题单独一行，命令换行显示（展开布局）
- 展示命令执行状态（成功/失败/进行中）

## 功能点目的

**主要功能**：验证 ExecCell 对短命令的紧凑渲染效果：

1. **紧凑布局**：当命令 `"echo ok"` 能在标题 `"• Ran "` 后的剩余空间内完整显示时，使用单行布局
2. **无输出提示**：当命令没有输出时，显示 `"(no output)"`
3. **视觉一致性**：即使紧凑布局，也保持与其他历史记录单元一致的缩进和对齐

**预期输出结构**：
```
• Ran echo ok
  └ (no output)
```

对比长命令的展开布局：
```
• Ran
  │ a_very_long_token_without_spaces_to_force_wrapping
  └ (no output)
```

## 具体技术实现

### 核心布局逻辑

**紧凑布局判断**（`command_display_lines` 方法，位于 `exec_cell/render.rs`）：
```rust
let header_line = Line::from(vec![
    bullet.clone(), 
    " ".into(), 
    title.bold(), 
    " ".into()
]);
let header_prefix_width = header_line.width();

// 计算第一行可用宽度
let available_first_width = (width as usize)
    .saturating_sub(header_prefix_width)
    .max(1);

// 尝试在第一行放置命令
let first_opts = RtOptions::new(available_first_width)
    .word_splitter(WordSplitter::NoHyphenation);
let mut first_wrapped: Vec<Line<'static>> = Vec::new();
push_owned_lines(&adaptive_wrap_line(first, first_opts), &mut first_wrapped);

// 如果第一行能容纳整个命令，使用紧凑布局
if first_wrapped.len() == 1 {
    header_line.extend(first_wrapped[0].clone());
    lines.push(header_line);
} else {
    // 展开布局：标题单独一行
    lines.push(header_line);
    // 命令换行显示...
}
```

### 无输出处理

```rust
if raw_output.lines.is_empty() {
    if !call.is_unified_exec_interaction() {
        lines.extend(prefix_lines(
            vec![Line::from("(no output)".dim())],
            Span::from(layout.output_block.initial_prefix).dim(),  // "  └ "
            Span::from(layout.output_block.subsequent_prefix),     // "    "
        ));
    }
}
```

### 布局常量定义

```rust
const EXEC_DISPLAY_LAYOUT: ExecDisplayLayout = ExecDisplayLayout::new(
    PrefixedBlock::new("  │ ", "  │ "),     // 命令续行前缀
    /*command_continuation_max_lines*/ 2,
    PrefixedBlock::new("  └ ", "    "),     // 输出块前缀
    /*output_max_lines*/ 5,
);
```

### 样式应用

- 成功状态：`"•".green().bold()` + `"Ran".bold()`
- 命令文本：语法高亮（通过 `highlight_bash_to_lines`）
- 无输出提示：`"(no output)".dim()`

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/exec_cell/render.rs` | `command_display_lines` 方法，包含紧凑/展开布局判断逻辑 |
| `codex-rs/tui/src/exec_cell/model.rs` | ExecCell、ExecCall 数据模型 |
| `codex-rs/tui/src/history_cell.rs` | 测试用例 `single_line_command_compact_when_fits` |
| `codex-rs/tui/src/render/highlight.rs` | Bash 语法高亮 `highlight_bash_to_lines` |
| `codex-rs/tui/src/wrapping.rs` | 自适应换行 `adaptive_wrap_line` |

### 测试代码位置

```rust
// history_cell.rs 第 3654-3674 行
#[test]
fn single_line_command_compact_when_fits() {
    let call_id = "c1".to_string();
    let mut cell = ExecCell::new(
        ExecCall {
            call_id: call_id.clone(),
            command: vec!["echo".into(), "ok".into()],  // 短命令
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
    
    // 宽度 80 足够容纳 "• Ran echo ok"
    let lines = cell.display_lines(80);
    let rendered = render_lines(&lines).join("\n");
    insta::assert_snapshot!(rendered);
}
```

## 依赖与外部交互

### 内部依赖

- **ratatui**: `Line`、`Span` 类型和样式系统
- **textwrap**: `WordSplitter::NoHyphenation` 防止在命令中插入连字符
- **unicode-width**: 宽度计算

### 相关组件交互

```
ExecCell::command_display_lines
    ├── strip_bash_lc_and_escape (命令清理)
    ├── highlight_bash_to_lines (语法高亮)
    ├── adaptive_wrap_line (自适应换行)
    │       └── 判断是否需要展开布局
    └── prefix_lines (添加前缀)
```

## 风险、边界与改进建议

### 已知风险

1. **宽度计算误差**：某些 Unicode 字符宽度计算可能与实际显示不一致
2. **CJK 字符**：中日韩宽字符可能导致布局错位
3. **终端字体**：等宽字体假设在某些终端可能不成立

### 边界情况

| 场景 | 当前行为 |
|------|---------|
| 命令长度 = 可用宽度 - 1 | 紧凑布局 |
| 命令长度 = 可用宽度 | 紧凑布局 |
| 命令长度 = 可用宽度 + 1 | 展开布局 |
| 空命令 | 仅显示标题 |
| 多行命令 | 强制展开布局 |

### 改进建议

1. **动态阈值**：
   - 当前逻辑是"能放下就用紧凑布局"
   - 可考虑增加最小剩余空间阈值，避免过于拥挤

2. **配置选项**：
   - 允许用户强制使用展开布局（可读性优先）
   - 允许自定义紧凑布局的最大命令长度

3. **视觉优化**：
   - 紧凑布局时增加命令与标题的视觉分隔（如颜色对比）
   - 考虑使用不同符号区分紧凑/展开布局

4. **测试覆盖**：
   - 增加边界宽度测试（刚好能放下/刚好放不下）
   - 增加包含特殊字符的命令测试
