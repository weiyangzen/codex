# 长行自动换行渲染测试快照研究文档

## 场景与职责

### 测试场景
本快照测试验证当diff中的代码行长度超过终端可用宽度时，渲染器能够正确地将长行折行显示。测试构造了一个包含超长修改行的diff（超过80列），验证内容在72列宽度限制下的折行表现。

### 业务场景
在实际代码审查中，以下情况会产生长行：
1. **长字符串字面量**：URL、SQL查询、错误消息
2. **复杂表达式**：嵌套函数调用、链式方法调用
3. **生成的代码**：JSON、XML、HTML 内嵌内容
4. **日志文件**：包含时间戳、日志级别、长消息
5. **数据文件**：CSV、TSV 等表格数据

### 组件职责
- **文本折行引擎** (`wrap_styled_spans`): 智能分割带样式的文本，保持语法高亮
- **行号连续性**: 确保折行后的续行正确缩进，与首行对齐
- **符号列处理**: 仅在首行显示 `+`/`-` 符号，续行使用空格填充
- **Unicode宽度计算**: 正确处理全角字符（CJK）和Emoji

## 功能点目的

### 核心功能
1. **自动折行**: 当内容超过可用宽度时自动换行
2. **视觉对齐**: 续行与首行内容列对齐，保持可读性
3. **样式保持**: 语法高亮样式在折行处正确延续
4. **符号处理**: 差异符号（+/-/空格）仅在首行显示

### 测试验证点
```rust
let original = "line 1\nshort\nline 3\n";
let modified = "line 1\nshort this_is_a_very_long_modified_line_that_should_wrap_across_multiple_terminal_columns_and_continue_even_further_beyond_eighty_columns_to_force_multiple_wraps\nline 3\n";
let patch = diffy::create_patch(original, modified).to_string();

// 使用 72 列的 wrap 宽度
let lines = create_diff_summary(&changes, &PathBuf::from("/"), 72);
```

### 预期输出分析
```
"• Edited long_example.txt (+1 -1)                                               "
"    1  line 1                                                                   "
"    2 -short                                                                    "
"    2 +short this_is_a_very_long_modified_line_that_should_wrap_across_m        "  ← 首行：行号+符号+内容
"       ultiple_terminal_columns_and_continue_even_further_beyond_eighty_        "  ← 续行1：空格填充+内容
"       columns_to_force_multiple_wraps                                          "  ← 续行2：空格填充+内容
"    3  line 3                                                                   "
```

关键观察：
- 第2行被修改，从 "short" 变为超长行
- 行号列宽为1（最大行号3是一位数）
- 可用内容宽度 = 72 - 4（行号+符号+空格）= 68列
- 续行使用空格填充，与首行内容起始位置对齐

## 具体技术实现

### 折行算法核心
```rust
fn wrap_styled_spans(spans: &[RtSpan<'static>], max_cols: usize) -> Vec<Vec<RtSpan<'static>>> {
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
                let w = ch.width().unwrap_or(if ch == '\t' { TAB_WIDTH } else { 0 });
                if col + chars_col + w > max_cols {
                    break;  // 超过宽度限制，在此处分割
                }
                byte_end += ch.len_utf8();
                chars_col += w;
            }

            if byte_end == 0 {
                // 单个字符超过剩余宽度，强制换行
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

            // 正常分割
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

    // 确保至少有一行输出
    if !current_line.is_empty() || result.is_empty() {
        result.push(current_line);
    }

    result
}
```

### 行渲染与折行集成
```rust
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
    let ln_str = line_number.to_string();
    let gutter_width = line_number_width.max(1);
    let prefix_cols = gutter_width + 1;  // +1 for sign column

    // 计算可用内容宽度
    let available_content_cols = width.saturating_sub(prefix_cols + 1).max(1);

    // 获取符号字符
    let (sign_char, sign_style, content_style) = match kind {
        DiffLineType::Insert => ('+', ...),
        DiffLineType::Delete => ('-', ...),
        DiffLineType::Context => (' ', ...),
    };

    // 执行折行
    let styled = vec![RtSpan::styled(text.to_string(), content_style)];
    let wrapped_chunks = wrap_styled_spans(&styled, available_content_cols);

    // 构建输出行
    let mut lines: Vec<RtLine<'static>> = Vec::new();
    for (i, chunk) in wrapped_chunks.into_iter().enumerate() {
        let mut row_spans: Vec<RtSpan<'static>> = Vec::new();
        if i == 0 {
            // 首行：行号 + 符号 + 内容
            let gutter = format!("{ln_str:>gutter_width$} ");
            let sign = format!("{sign_char}");
            row_spans.push(RtSpan::styled(gutter, gutter_style));
            row_spans.push(RtSpan::styled(sign, sign_style));
        } else {
            // 续行：空格填充（与行号列+符号列对齐）
            let cont_gutter = format!("{:gutter_width$}  ", "");  // gutter_width空格 + 2空格
            row_spans.push(RtSpan::styled(cont_gutter, gutter_style));
        }
        row_spans.extend(chunk);
        lines.push(RtLine::from(row_spans).style(line_bg));
    }

    lines
}
```

### Unicode宽度处理
```rust
use unicode_width::UnicodeWidthChar;

// 字符宽度计算
let w = ch.width().unwrap_or(if ch == '\t' { TAB_WIDTH } else { 0 });
```

宽度规则：
- 半角字符（ASCII）：宽度1
- 全角字符（CJK）：宽度2
- Tab字符：固定宽度4（`TAB_WIDTH`常量）
- 零宽字符（如组合符号）：宽度0
- 其他：默认宽度1

## 关键代码路径与文件引用

### 核心实现文件
| 文件路径 | 功能描述 |
|---------|---------|
| `codex-rs/tui/src/diff_render.rs` | 包含 `wrap_styled_spans` 和行渲染逻辑 |
| `codex-rs/tui/src/snapshots/codex_tui__diff_render__tests__apply_update_block_wraps_long_lines.snap` | 本快照文件 |

### 关键函数调用链
```
ui_snapshot_apply_update_block_wraps_long_lines (test)
  └── create_diff_summary(&changes, &PathBuf::from("/"), 72)
        └── render_changes_block(rows, 72, cwd)
              └── render_change(&r.change, &mut lines, wrap_cols - 4, lang)
                    └── FileChange::Update 分支
                          ├── 计算 max_line_number → 3
                          ├── line_number_width(3) → 1
                          └── 对每个 diff line:
                                └── push_wrapped_diff_line_inner_with_theme_and_color_level
                                      ├── available_content_cols = 72 - 4 = 68
                                      ├── wrap_styled_spans(&styled, 68)
                                      │   └── 返回 Vec<Vec<RtSpan>>（折行后的片段）
                                      └── 构建 RtLine，处理首行/续行差异
```

### 相关常量
```rust
const TAB_WIDTH: usize = 4;  // 制表符显示宽度
```

### 样式相关
续行使用与首行相同的 `gutter_style`，确保视觉一致性：
```rust
let cont_gutter = format!("{:gutter_width$}  ", "");
row_spans.push(RtSpan::styled(cont_gutter, gutter_style));
```

## 依赖与外部交互

### 外部依赖
| 依赖包 | 用途 |
|-------|------|
| `unicode-width` | Unicode字符显示宽度计算 |
| `ratatui` | 终端UI渲染，提供 `RtSpan`、`RtLine` 类型 |
| `diffy` | diff解析，提供 `Patch`、`Hunk` 结构 |

### 与语法高亮的交互
当启用语法高亮时，折行需要保持样式连续性：

```rust
// 带语法高亮的折行
if let Some(syn_spans) = syntax_spans {
    let styled: Vec<RtSpan<'static>> = syn_spans
        .iter()
        .map(|sp| {
            let style = if matches!(kind, DiffLineType::Delete) {
                sp.style.add_modifier(Modifier::DIM)  // 删除行变暗
            } else {
                sp.style
            };
            RtSpan::styled(sp.content.clone().into_owned(), style)
        })
        .collect();
    
    let wrapped_chunks = wrap_styled_spans(&styled, available_content_cols);
    // ... 后续处理
}
```

### 测试框架
- `insta::assert_snapshot!`: 捕获终端后端输出
- `ratatui::backend::TestBackend`: 模拟终端环境

## 风险、边界与改进建议

### 已知风险

1. **CJK字符截断**
   - 风险：CJK字符宽度为2，可能在边界处被错误分割
   - 现状：`wrap_styled_spans` 按字符边界分割，不会截断UTF-8序列
   - 潜在问题：宽度计算与实际显示可能不一致（取决于终端字体）

2. **超长单词**
   - 风险：单个单词超过可用宽度时，强制分割可能破坏语义
   - 现状：算法会强制分割，确保至少一个字符输出
   - 示例：`this_is_a_very_long_identifier` 可能被分割为 `this_is_a_very_long_i` 和 `dentifier`

3. **ANSI转义序列**
   - 风险：内容中包含ANSI转义序列时，宽度计算可能出错
   - 现状：未明确处理内嵌ANSI序列

4. **性能问题**
   - 风险：超长行（如MB级JSON）可能导致内存和性能问题
   - 现状：未设置行长度上限

### 边界条件

| 场景 | 预期行为 | 测试状态 |
|-----|---------|---------|
| 空字符串 | 输出空行 | 未直接测试 |
| 恰好等于宽度 | 不折行 | 未测试 |
| 超出宽度1字符 | 折行为两行 | 本测试覆盖 |
| 全CJK内容 | 按宽度2计算 | 未直接测试 |
| 混合Emoji和文本 | Emoji宽度通常为2 | 未测试 |
| 包含Tab字符 | Tab扩展为4空格 | 未测试 |
| 包含换行符 | 输入预处理已去除 | 依赖上游 |

### 改进建议

1. **添加智能断词**
   ```rust
   // 优先在单词边界处断行
   fn find_word_boundary(text: &str, max_width: usize) -> usize {
       // 从max_width向前查找空格或标点
       // 如果找不到，则强制分割
   }
   ```

2. **配置折行宽度**
   ```toml
   [display]
   wrap_width = 80  # 0表示不折行
   wrap_strategy = "word"  # 或 "char"
   ```

3. **添加续行指示符**
   ```
   2 +short this_is_a_very_long_line_that_
   |      wraps_across_multiple_lines
   ```
   使用 `|` 或 `\` 指示折行

4. **优化超长行处理**
   ```rust
   const MAX_LINE_LENGTH: usize = 10_000;
   
   if text.len() > MAX_LINE_LENGTH {
       // 截断并显示省略号
       text = format!("{}... [truncated {} chars]", 
           &text[..MAX_LINE_LENGTH], 
           text.len() - MAX_LINE_LENGTH);
   }
   ```

5. **添加更多测试用例**
   ```rust
   #[test]
   fn wrap_cjk_characters() {
       let text = "这是一段很长的中文文本，需要折行显示";
       // 验证CJK宽度计算
   }
   
   #[test]
   fn wrap_with_emoji() {
       let text = "🚀🚀🚀 very long text with emoji 🎉🎉🎉";
       // 验证Emoji宽度处理
   }
   
   #[test]
   fn wrap_exact_width_boundary() {
       // 测试恰好等于边界的情况
   }
   ```

6. **支持弹性Tab宽度**
   ```rust
   // 当前：固定TAB_WIDTH = 4
   // 建议：可配置，或根据上下文动态调整
   fn tab_width_at_column(col: usize) -> usize {
       TAB_WIDTH - (col % TAB_WIDTH)
   }
   ```

7. **改进续行缩进**
   ```rust
   // 当前：与行号列对齐
   // 建议：可选的额外缩进，区分续行和新行
   let cont_gutter = format!("{:gutter_width$}  {} ", "", CONTINUATION_MARKER);
   ```

8. **性能优化**
   - 使用迭代器而非递归处理长文本
   - 考虑使用 `memchr` 等快速字符串搜索库

### 相关代码审查建议
当前 `wrap_styled_spans` 函数较长（约80行），建议拆分为更小的函数：

```rust
fn wrap_styled_spans(...) -> Vec<Vec<RtSpan<'static>>> {
    // 主循环
    for span in spans {
        wrap_single_span(span, max_cols, &mut result, &mut current_line, &mut col);
    }
    finalize_wrapping(result, current_line)
}

fn wrap_single_span(...) { ... }
fn finalize_wrapping(...) -> Vec<...> { ... }
```
