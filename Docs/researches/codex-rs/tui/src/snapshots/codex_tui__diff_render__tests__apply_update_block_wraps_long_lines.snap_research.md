# Diff Render - 长行自动换行渲染测试（Backend 视图）

## 场景与职责

该快照测试验证 TUI 中**超长代码行的自动换行**渲染效果。当 diff 中的某行代码超过终端可用宽度时，需要智能地进行换行，同时保持行号、标记符和缩进的一致性，确保用户能够完整阅读被截断的内容。

此测试使用 `terminal.backend()` 捕获完整的终端缓冲区状态，包括样式信息。

## 功能点目的

1. **长行自动换行**：超过终端宽度的行自动折行显示
2. **视觉连续性**：换行后的内容保持对齐，便于阅读
3. **标记符位置**：仅在首行显示 `-`/`+` 标记，续行使用缩进
4. **行号处理**：仅在首行显示行号，续行使用空白占位
5. **样式保持**：语法高亮样式在换行后保持一致

## 具体技术实现

### 换行核心算法

```rust
fn wrap_styled_spans(
    spans: &[RtSpan<'static>], 
    max_cols: usize
) -> Vec<Vec<RtSpan<'static>>> {
    let mut result: Vec<Vec<RtSpan<'static>>> = Vec::new();
    let mut current_line: Vec<RtSpan<'static>> = Vec::new();
    let mut col: usize = 0;

    for span in spans {
        let style = span.style;
        let text = span.content.as_ref();
        let mut remaining = text;

        while !remaining.is_empty() {
            // 计算当前行还能容纳多少字符
            let mut byte_end = 0;
            let mut chars_col = 0;

            for ch in remaining.chars() {
                let w = ch.width().unwrap_or(if ch == '	' { TAB_WIDTH } else { 0 });
                if col + chars_col + w > max_cols {
                    break;
                }
                byte_end += ch.len_utf8();
                chars_col += w;
            }

            if byte_end == 0 {
                // 单个字符超过剩余空间，强制换行
                if !current_line.is_empty() {
                    result.push(std::mem::take(&mut current_line));
                }
                // 取至少一个字符避免死循环
                let ch = remaining.chars().next().unwrap();
                let ch_len = ch.len_utf8();
                current_line.push(RtSpan::styled(remaining[..ch_len].to_string(), style));
                col = ch.width().unwrap_or(1);
                remaining = &remaining[ch_len..];
                continue;
            }

            let (chunk, rest) = remaining.split_at(byte_end);
            current_line.push(RtSpan::styled(chunk.to_string(), style));
            col += chars_col;
            remaining = rest;

            if col >= max_cols {
                result.push(std::mem::take(&mut current_line));
                col = 0;
            }
        }
    }

    if !current_line.is_empty() || result.is_empty() {
        result.push(current_line);
    }

    result
}
```

### 续行渲染逻辑

```rust
// diff_render.rs:898-914
for (i, chunk) in wrapped_chunks.into_iter().enumerate() {
    let mut row_spans: Vec<RtSpan<'static>> = Vec::new();
    if i == 0 {
        // 首行：行号 + 标记 + 内容
        row_spans.push(RtSpan::styled(gutter.clone(), gutter_style));
        row_spans.push(RtSpan::styled(sign.clone(), sign_style));
    } else {
        // 续行：空白占位（保持对齐）
        let cont_gutter = format!("{:gutter_width$}  ", "");
        row_spans.push(RtSpan::styled(cont_gutter, gutter_style));
    }
    row_spans.extend(chunk);
    lines.push(RtLine::from(row_spans).style(line_bg));
}
```

### 可用内容宽度计算

```rust
// diff_render.rs:851-854, 893-894, 917
let gutter_width = line_number_width.max(1);
let prefix_cols = gutter_width + 1; // +1 for sign

// 计算内容可用宽度
let available_content_cols = width.saturating_sub(prefix_cols + 1).max(1);
```

### 关键代码路径

```rust
// diff_render.rs:837-938
fn push_wrapped_diff_line_inner_with_theme_and_color_level(
    line_number: usize,
    kind: DiffLineType,
    text: &str,
    width: usize,
    line_number_width: usize,
    syntax_spans: Option<&[RtSpan<'static>]>,
    theme: DiffTheme,
    color_level: DiffColorLevel,
    diff_backgrounds: ResolvedDiffBackgrounds,
) -> Vec<RtLine<'static>> {
    // 1. 计算列宽
    let gutter_width = line_number_width.max(1);
    let prefix_cols = gutter_width + 1;
    let available_content_cols = width.saturating_sub(prefix_cols + 1).max(1);

    // 2. 获取样式
    let (sign_char, sign_style, content_style) = match kind { /* ... */ };
    let line_bg = style_line_bg_for(kind, diff_backgrounds);
    let gutter_style = style_gutter_for(kind, theme, color_level);

    // 3. 准备内容 spans
    let styled = if let Some(syn_spans) = syntax_spans { /* ... */ } 
                 else { vec![RtSpan::styled(text.to_string(), content_style)] };

    // 4. 执行换行
    let wrapped_chunks = wrap_styled_spans(&styled, available_content_cols);

    // 5. 组装每行
    let mut lines: Vec<RtLine<'static>> = Vec::new();
    for (i, chunk) in wrapped_chunks.into_iter().enumerate() {
        // 首行：行号 + 标记
        // 续行：空白占位
    }
    lines
}
```

## 关键代码路径与文件引用

| 组件 | 文件路径 | 职责 |
|------|----------|------|
| 换行核心 | `diff_render.rs:940-1020` | `wrap_styled_spans` 函数 |
| 单行渲染 | `diff_render.rs:837-938` | `push_wrapped_diff_line_inner_with_theme_and_color_level` |
| 测试用例 | `diff_render.rs:1605-1625` | `ui_snapshot_apply_update_block_wraps_long_lines` |

### 测试参数

```rust
let lines = create_diff_summary(&changes, &PathBuf::from("/"), 72);
snapshot_lines("apply_update_block_wraps_long_lines", lines, 80, 12);
```

- `wrap_cols = 72`：diff 内容换行宽度
- `backend_width = 80`：终端缓冲区宽度（略大于换行宽度）

## 依赖与外部交互

### 外部依赖

1. **unicode-width**：Unicode 字符显示宽度计算
2. **ratatui**：终端 UI 渲染和测试后端

### 内部依赖

- `TAB_WIDTH = 4`：Tab 字符显示宽度常量

### 特殊字符处理

| 字符类型 | 处理方式 |
|----------|----------|
| ASCII | 宽度 1 |
| CJK 字符 | 宽度 2（通过 unicode-width） |
| Tab | 宽度 4（`TAB_WIDTH`） |
| 零宽字符 | 宽度 0 |
| 其他 | 默认宽度 1 |

## 风险、边界与改进建议

### 潜在风险

1. **性能问题**：超长行（如 minified JS）可能导致大量换行
2. **内存占用**：大量换行结果占用内存
3. **CJK 字符**：某些 CJK 字符宽度计算可能不准确
4. **组合字符**：Unicode 组合字符的宽度计算

### 边界情况

1. **单行超长**：单行超过 10000 字符的处理
2. **无空白字符**：无法按单词换行时的强制截断
3. **Tab 位置**：Tab 在换行边界时的处理
4. **空内容**：空字符串的换行行为
5. **精确填充**：内容恰好填满一行时的处理

### 测试场景分析

测试数据：
```
原始行："short this_is_a_very_long_modified_line_that_should_wrap..."
长度：超过 72 字符
```

预期输出：
```
"    2 +short this_is_a_very_long_modified_line_that_should_wrap_across_m        "
"       ultiple_terminal_columns_and_continue_even_further_beyond_eighty_        "
"       columns_to_force_multiple_wraps                                          "
```

验证点：
- 首行显示行号（2）和标记（+）
- 续行使用空白占位保持对齐
- 内容正确分割（在字符边界）
- 背景色保持一致

### 改进建议

1. **智能换行**：
   - 优先在单词边界换行
   - 支持连字符断词
   - 考虑语言特定的换行规则

2. **性能优化**：
   - 流式处理超长行
   - 限制最大换行数
   - 延迟渲染不可见区域

3. **可视化增强**：
   - 续行标记（如 `↪` 符号）
   - 行号续行指示
   - 折叠/展开长行功能

4. **配置选项**：
   - 换行宽度自定义
   - 是否启用自动换行
   - 截断替代换行的选项

5. **边界处理**：
   - 更好的 CJK 支持
   - Emoji 宽度正确处理
   - 双向文本（RTL）支持

6. **交互功能**：
   - 水平滚动查看完整行
   - 双击展开长行
   - 复制完整行内容

### 相关测试

```rust
// diff_render.rs:2285-2303
#[test]
fn fallback_wrapping_uses_display_width_for_tabs_and_wide_chars() {
    let lines = push_wrapped_diff_line_with_style_context(
        1,
        DiffLineType::Insert,
        "abcd\t界🙂",
        width,
        line_number_width(1),
        current_diff_render_style_context(),
    );
    // 验证 Tab 和宽字符正确处理
}
```
