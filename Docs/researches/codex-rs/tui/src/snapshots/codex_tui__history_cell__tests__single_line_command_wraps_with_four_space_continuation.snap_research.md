# Research Document: Single Line Command Wraps With Four Space Continuation Snapshot

## 场景与职责

此快照测试验证 **ExecCell** 组件在渲染长命令时的换行和缩进行为。当单条命令文本超过终端可用宽度时，需要正确换行并使用一致的缩进保持视觉层次。

该组件负责：
- 检测命令文本是否超过可用宽度
- 实现智能换行（保持 URL 类文本完整）
- 使用统一的缩进前缀保持树形结构
- 确保续行与首行对齐

## 功能点目的

**主要功能**：验证 ExecCell 对长单条命令的换行渲染效果：

1. **换行检测**：命令 `a_very_long_token_without_spaces_to_force_wrapping` 超过 24 列宽度时触发换行
2. **续行缩进**：使用 `"  │ "` 作为续行前缀，与树形结构保持一致
3. **无连字符分割**：使用 `WordSplitter::NoHyphenation` 避免在长 token 中插入连字符
4. **输出块分隔**：命令和输出之间使用 `"  └ "` 分隔

**预期输出结构**（宽度 24）：
```
• Ran a_very_long_token_
  │ without_spaces_to_
  │ force_wrapping
  └ (no output)
```

## 具体技术实现

### 换行算法

**自适应换行**（`adaptive_wrap_line` 位于 `wrapping.rs`）：
```rust
pub fn adaptive_wrap_line(line: &Line, opts: RtOptions) -> Vec<Line<'static>> {
    // 使用 textwrap 进行换行
    // 特殊处理：保持 URL 类 token 不分割
}
```

**布局配置**（`exec_cell/render.rs`）：
```rust
const EXEC_DISPLAY_LAYOUT: ExecDisplayLayout = ExecDisplayLayout::new(
    PrefixedBlock::new("  │ ", "  │ "),     // 命令续行前缀
    /*command_continuation_max_lines*/ 2,
    PrefixedBlock::new("  └ ", "    "),     // 输出块前缀
    /*output_max_lines*/ 5,
);
```

### 关键渲染流程

1. **计算可用宽度**：
```rust
let header_line = Line::from(vec![
    bullet.clone(), 
    " ".into(), 
    title.bold(), 
    " ".into()
]);
let header_prefix_width = header_line.width();  // "• Ran " = 6

let available_first_width = (width as usize)
    .saturating_sub(header_prefix_width)
    .max(1);  // 24 - 6 = 18
```

2. **尝试紧凑布局失败**：
```rust
let first_opts = RtOptions::new(available_first_width)
    .word_splitter(WordSplitter::NoHyphenation);
// 命令长度 > 18，换行后产生多行，触发展开布局
```

3. **展开布局渲染**：
```rust
// 标题单独一行
lines.push(header_line);  // "• Ran "

// 命令续行
let continuation_opts = RtOptions::new(continuation_wrap_width)
    .word_splitter(WordSplitter::NoHyphenation);

// 应用前缀
lines.extend(prefix_lines(
    continuation_lines,
    Span::from(layout.command_continuation.initial_prefix).dim(),  // "  │ "
    Span::from(layout.command_continuation.subsequent_prefix).dim(), // "  │ "
));
```

### 缩进结构

```
• Ran                          <- 标题行（bullet + 标题 + 命令首段）
  │ without_spaces_to_         <- 续行 1（4 空格 + "│" + 1 空格）
  │ force_wrapping             <- 续行 2
  └ (no output)                <- 输出块（4 空格 + "└" + 1 空格）
```

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/exec_cell/render.rs` | `command_display_lines` 方法，第 356-499 行 |
| `codex-rs/tui/src/exec_cell/render.rs` | `PrefixedBlock` 布局常量定义，第 637-687 行 |
| `codex-rs/tui/src/wrapping.rs` | `adaptive_wrap_line` 自适应换行 |
| `codex-rs/tui/src/render/line_utils.rs` | `prefix_lines` 行前缀添加 |
| `codex-rs/tui/src/history_cell.rs` | 测试用例，第 3677-3697 行 |

### 测试代码位置

```rust
// history_cell.rs 第 3677-3697 行
#[test]
fn single_line_command_wraps_with_four_space_continuation() {
    let call_id = "c1".to_string();
    let long = "a_very_long_token_without_spaces_to_force_wrapping".to_string();
    let mut cell = ExecCell::new(
        ExecCall {
            call_id: call_id.clone(),
            command: vec!["bash".into(), "-lc".into(), long],  // 长命令
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
    
    // 窄宽度 24 强制换行
    let lines = cell.display_lines(24);
    let rendered = render_lines(&lines).join("\n");
    insta::assert_snapshot!(rendered);
}
```

## 依赖与外部交互

### 内部依赖

- **textwrap**: 核心换行算法
  - `WrapAlgorithm::FirstFit`
  - `WordSplitter::NoHyphenation`
- **unicode-width**: 字符宽度计算
- **ratatui**: 行和跨度组装

### 换行策略对比

| 策略 | 行为 | 适用场景 |
|------|------|---------|
| `NoHyphenation` | 不在单词内插入连字符 | 命令、代码、URL |
| `HyphenSplitter` | 允许在单词内断行 | 普通文本 |

## 风险、边界与改进建议

### 已知风险

1. **超长无空格文本**：如 Base64 字符串，可能导致单行过长
2. **CJK 文本**：中日韩字符宽度计算可能不准确
3. **组合字符**：Unicode 组合字符（如 emoji 修饰符）宽度计算复杂

### 边界情况

| 场景 | 当前行为 |
|------|---------|
| 宽度 = 0 | 返回空 Vec |
| 宽度 < 前缀宽度 | 最小宽度保护为 1 |
| 命令包含换行符 | 每行独立处理，各自缩进 |
| 空命令 | 仅显示标题 |

### 改进建议

1. **智能断行**：
   - 对无空格的长 token（如 SHA、UUID）使用特定断点规则
   - 考虑在标点符号处优先断行

2. **配置化**：
   - 允许用户自定义续行前缀（有人喜欢 `>` 而不是 `│`）
   - 可配置最大续行数

3. **性能优化**：
   - 缓存换行结果，避免重复计算
   - 对于静态内容使用预计算布局

4. **可访问性**：
   - 为屏幕阅读器提供续行提示
   - 支持 Braille 显示器的特殊处理
