# 研究文档：single_line_command_wraps_with_four_space_continuation

## 场景与职责

该快照测试验证 `ExecCell` 在单行长命令需要换行时的渲染行为。当命令虽然逻辑上是单行，但由于长度超过可用宽度而需要换行时，系统应该使用合适的延续前缀保持视觉层次。

**核心职责**：
- 检测命令是否需要换行
- 使用 `│` 符号作为命令延续的视觉指示
- 保持命令的语法高亮
- 正确处理无输出情况

## 功能点目的

**从快照内容分析**：
```
• Ran a_very_long_token_
  │ without_spaces_to_
  │ force_wrapping
  └ (no output)
```

**功能特性**：
1. **头部截断**：`• Ran a_very_long_token_` - 命令在头部行被截断
2. **命令延续**：使用 `│` 符号前缀继续显示命令
3. **无连字符分割**：长 token 保持完整，不插入连字符
4. **输出提示**：`(no output)` 使用 `└` 前缀

## 具体技术实现

### 换行检测与处理

**代码位置**：`codex-rs/tui/src/exec_cell/render.rs` 第 391-431 行

```rust
let continuation_wrap_width = layout.command_continuation.wrap_width(width);
let continuation_opts =
    RtOptions::new(continuation_wrap_width).word_splitter(WordSplitter::NoHyphenation);

let mut continuation_lines: Vec<Line<'static>> = Vec::new();

if let Some((first, rest)) = highlighted_lines.split_first() {
    let available_first_width = (width as usize).saturating_sub(header_prefix_width).max(1);
    let first_opts =
        RtOptions::new(available_first_width).word_splitter(WordSplitter::NoHyphenation);

    let mut first_wrapped: Vec<Line<'static>> = Vec::new();
    push_owned_lines(&adaptive_wrap_line(first, first_opts), &mut first_wrapped);
    let mut first_wrapped_iter = first_wrapped.into_iter();
    if let Some(first_segment) = first_wrapped_iter.next() {
        header_line.extend(first_segment);  // 第一片段内联
    }
    continuation_lines.extend(first_wrapped_iter);  // 剩余片段放入延续行

    // 处理剩余行
    for line in rest {
        push_owned_lines(
            &adaptive_wrap_line(line, continuation_opts.clone()),
            &mut continuation_lines,
        );
    }
}
```

### 延续行限制

**代码位置**：第 421-431 行

```rust
let continuation_lines = Self::limit_lines_from_start(
    &continuation_lines,
    layout.command_continuation_max_lines,  // 2
);
if !continuation_lines.is_empty() {
    lines.extend(prefix_lines(
        continuation_lines,
        Span::from(layout.command_continuation.initial_prefix).dim(),  // "  │ "
        Span::from(layout.command_continuation.subsequent_prefix).dim(), // "  │ "
    ));
}
```

### 布局配置

```rust
const EXEC_DISPLAY_LAYOUT: ExecDisplayLayout = ExecDisplayLayout::new(
    PrefixedBlock::new("  │ ", "  │ "),  // 命令延续前缀
    /*command_continuation_max_lines*/ 2,  // 最多 2 行延续
    PrefixedBlock::new("  └ ", "    "),   // 输出块前缀
    /*output_max_lines*/ 5,
);
```

### 无连字符分割

**关键配置**：
```rust
.word_splitter(WordSplitter::NoHyphenation)
```

这确保长 token（如 `a_very_long_token_without_spaces_to_force_wrapping`）不会被强制分割，而是完整换行。

## 关键代码路径与文件引用

### 主要文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui/src/exec_cell/render.rs` | `ExecCell::command_display_lines` 实现 |
| `codex-rs/tui/src/exec_cell/mod.rs` | 模块导出 |

### 测试代码

**位置**：`codex-rs/tui/src/history_cell.rs` 第 3676-3697 行

```rust
#[test]
fn single_line_command_wraps_with_four_space_continuation() {
    let call_id = "c1".to_string();
    let long = "a_very_long_token_without_spaces_to_force_wrapping".to_string();
    let mut cell = ExecCell::new(
        ExecCall {
            call_id: call_id.clone(),
            command: vec!["bash".into(), "-lc".into(), long],
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
    
    // 宽度 24 强制换行
    let lines = cell.display_lines(24);
    let rendered = render_lines(&lines).join("\n");
    insta::assert_snapshot!(rendered);
}
```

### 关键函数

**`limit_lines_from_start`**（第 501-512 行）：
```rust
fn limit_lines_from_start(lines: &[Line<'static>], keep: usize) -> Vec<Line<'static>> {
    if lines.len() <= keep {
        return lines.to_vec();
    }
    if keep == 0 {
        return vec![Self::ellipsis_line(lines.len())];
    }

    let mut out: Vec<Line<'static>> = lines[..keep].to_vec();
    out.push(Self::ellipsis_line(lines.len() - keep));
    out
}
```

**`PrefixedBlock::wrap_width`**（第 651-655 行）：
```rust
fn wrap_width(self, total_width: u16) -> usize {
    let prefix_width = UnicodeWidthStr::width(self.initial_prefix)
        .max(UnicodeWidthStr::width(self.subsequent_prefix));
    usize::from(total_width).saturating_sub(prefix_width).max(1)
}
```

对于 `"  │ "` 前缀（6 字符），`continuation_wrap_width = 24 - 6 = 18`。

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `ratatui` | 终端 UI 渲染 |
| `textwrap` | 文本换行，特别是 `WordSplitter::NoHyphenation` |
| `unicode_width` | Unicode 宽度计算 |

### 内部依赖

- `crate::wrapping::RtOptions`：换行选项配置
- `crate::wrapping::adaptive_wrap_line`：自适应换行
- `crate::render::line_utils::prefix_lines`：行前缀处理
- `crate::render::line_utils::push_owned_lines`：行收集

### 渲染流程

```
ExecCell::display_lines(24)
└── command_display_lines(24)
    ├── 1. 构建头部："• Ran "（宽度 = 10）
    ├── 2. 可用宽度：24 - 10 = 14
    ├── 3. 命令 "a_very_long_token_without_spaces_to_force_wrapping"
    │   ├── 第一片段（14 字符）："a_very_long_token_"
    │   │   └── 内联到头部："• Ran a_very_long_token_"
    │   └── 剩余片段放入延续行
    │       ├── "without_spaces_to_"（宽度 18）
    │       └── "force_wrapping"（宽度 14）
    ├── 4. 添加延续前缀 "  │ "
    │   ├── "  │ without_spaces_to_"
    │   └── "  │ force_wrapping"
    └── 5. 无输出，显示：
        └── "  └ (no output)"
```

## 风险、边界与改进建议

### 潜在风险

1. **延续行数限制**：
   - `command_continuation_max_lines = 2` 可能不足以显示复杂命令
   - 超出部分被截断，用户无法看到完整命令

2. **宽度计算误差**：
   - `available_first_width` 计算可能因样式字符而偏差
   - 某些终端对 ANSI 转义序列的宽度处理不同

3. **长 token 问题**：
   - `NoHyphenation` 保持 token 完整，但可能导致行尾大量空白
   - 极端长的 URL 或路径可能超出单行

### 边界情况

| 场景 | 当前行为 | 评估 |
|-----|---------|------|
| 命令刚好填满头部 | 无延续行 | ✅ 最优布局 |
| 命令需要 3+ 行 | 截断为 2 行，显示省略号 | ⚠️ 信息丢失 |
| 极窄终端（< 10） | 头部可能无法完整显示 | ⚠️ 显示异常 |
| 包含 ANSI 序列 | 可能宽度计算错误 | ⚠️ 需要测试 |

### 改进建议

1. **可配置的延续行数**：
   ```rust
   pub struct ExecDisplayConfig {
       pub max_command_continuation_lines: usize,  // 默认 2
   }
   ```

2. **智能截断提示**：
   ```rust
   // 显示被截断的内容预览
   if continuation_lines.len() > max_lines {
       out.push(format!("  │ ... ({} more chars)", remaining_chars).dim());
   }
   ```

3. **展开功能**：
   - 添加键盘快捷键（如 Tab）展开完整命令
   - 使用 `...` 作为可点击的展开指示器

4. **改进长 token 处理**：
   ```rust
   // 对于极长 token，允许在特定字符处分割（如 /、-、_）
   fn smart_split(token: &str, max_width: usize) -> Vec<&str> {
       // 优先在路径分隔符处分割
   }
   ```

5. **动态宽度调整**：
   ```rust
   // 如果终端宽度变化，重新计算布局
   fn on_resize(&mut self, new_width: u16) {
       self.cached_lines = None;  // 清除缓存
   }
   ```

6. **语法高亮保持**：
   ```rust
   // 确保换行后语法高亮仍然正确
   // 当前实现可能已经处理，但需要验证
   ```
