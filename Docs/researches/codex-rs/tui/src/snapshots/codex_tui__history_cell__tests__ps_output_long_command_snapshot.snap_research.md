# Research: 后台进程长命令截断测试快照

## 场景与职责

该快照测试验证 `UnifiedExecProcessesCell` 在渲染后台进程列表时，对超长命令的截断处理。当命令长度超过可用显示宽度时，需要智能截断并添加省略号提示。

这是 Codex TUI 后台终端管理功能的重要组成部分，确保即使是很长的命令也能在有限的空间内合理显示。

## 功能点目的

1. **命令截断**: 当命令过长时进行智能截断
2. **省略提示**: 添加 `[...]` 提示表示内容被截断
3. **首行优先**: 优先显示命令的第一行
4. **字符限制**: 限制显示的字符数（80个字符）

## 具体技术实现

### 渲染格式

```
/ps

Background terminals

  • rg "foo" src --glob '**/*. [...]
    ↳ searching...
```

格式说明：
- `rg "foo" src --glob '**/*. [...]`: 被截断的命令显示
- `[...]`: 截断提示（灰色）
- `↳ searching...`: 进程最近输出

### 关键代码逻辑

```rust
// history_cell.rs:684-722
let (snippet, snippet_truncated) = {
    let (first_line, has_more_lines) = match command.split_once('\n') {
        Some((first, _)) => (first, true),
        None => (command.as_str(), false),
    };
    let max_graphemes = 80;  // 最大字符数限制
    let mut graphemes = first_line.grapheme_indices(true);
    if let Some((byte_index, _)) = graphemes.nth(max_graphemes) {
        (first_line[..byte_index].to_string(), true)
    } else {
        (first_line.to_string(), has_more_lines)
    }
};

// 截断处理
let truncation_suffix = " [...]";
let truncation_suffix_width = UnicodeWidthStr::width(truncation_suffix);
if needs_suffix && budget > truncation_suffix_width {
    let available = budget.saturating_sub(truncation_suffix_width);
    let (truncated, _, _) = take_prefix_by_width(&snippet, available);
    out.push(vec![prefix.dim(), truncated.cyan(), truncation_suffix.dim()].into());
}
```

### 测试数据构造

```rust
// history_cell.rs:2822-2831
let cell = new_unified_exec_processes_output(vec![UnifiedExecProcessDetails {
    command_display: String::from(
        "rg \"foo\" src --glob '**/*.rs' --max-count 1000 --no-ignore --hidden --follow --glob '!target/**'",
    ),
    recent_chunks: vec!["searching...".to_string()],
}]);
let rendered = render_lines(&cell.display_lines(36)).join("\n");  // 窄宽度强制截断
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/history_cell.rs` | UnifiedExecProcessesCell 实现，测试位于行 2822-2831 |
| `codex-rs/tui/src/live_wrap.rs` | `take_prefix_by_width` 函数 |

### 测试代码位置

```rust
// history_cell.rs:2822-2831
#[test]
fn ps_output_long_command_snapshot() {
    let cell = new_unified_exec_processes_output(vec![UnifiedExecProcessDetails {
        command_display: String::from(
            "rg \"foo\" src --glob '**/*.rs' --max-count 1000 --no-ignore --hidden --follow --glob '!target/**'",
        ),
        recent_chunks: vec!["searching...".to_string()],
    }]);
    let rendered = render_lines(&cell.display_lines(36)).join("\n");
    insta::assert_snapshot!(rendered);
}
```

## 依赖与外部交互

### 外部依赖

1. **ratatui**: TUI 渲染框架
2. **unicode-width**: 字符串宽度计算
3. **unicode-segmentation**: Unicode 字符边界处理
4. **insta**: 快照测试

### 内部模块依赖

```rust
use crate::live_wrap::take_prefix_by_width;
use unicode_width::UnicodeWidthStr;
use unicode_segmentation::UnicodeSegmentation;
```

## 风险、边界与改进建议

### 潜在风险

1. **字符数与宽度**: `max_graphemes = 80` 是按字符数限制，而非显示宽度，可能导致宽度不一致
2. **截断位置**: 在单词中间截断可能影响可读性

### 边界情况

1. **极窄宽度**: 可用宽度小于截断提示长度时的处理
2. **多行命令**: 命令包含多行时的首行提取
3. **Unicode 字符**: 多字节 Unicode 字符的截断边界

### 改进建议

1. **智能截断**: 在单词边界处截断，而非字符边界
2. **悬停提示**: 鼠标悬停时显示完整命令
3. **展开功能**: 提供快捷键展开显示完整命令
4. **宽度优先**: 按显示宽度而非字符数进行限制

### 相关快照文件

- `ps_output_empty_snapshot.snap` - 空进程列表测试
- `ps_output_chunk_leading_whitespace_snapshot.snap` - 带缩进输出测试
- `ps_output_many_sessions_snapshot.snap` - 多进程测试
- `ps_output_multiline_snapshot.snap` - 多行输出测试
