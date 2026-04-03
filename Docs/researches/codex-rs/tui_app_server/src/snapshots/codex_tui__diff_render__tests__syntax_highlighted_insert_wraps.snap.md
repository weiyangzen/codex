# Syntax Highlighted Insert Wraps 快照研究文档

## 场景与职责

此快照测试展示了**带语法高亮的长行自动换行**功能。这是 diff 渲染中处理代码行的关键场景，确保：

1. 语法高亮样式在换行后仍然保持
2. 长行正确分割为多行显示
3. 续行缩进对齐正确

### 测试场景
- **代码语言**: Rust
- **代码内容**: 一个超长的函数签名（超过 80 列）
- **变更类型**: 插入行（`DiffLineType::Insert`）
- **渲染宽度**: 80 列（内容区约 77 列）

## 功能点目的

### 1. 语法高亮保持
- 使用 `highlight_code_to_styled_spans` 生成语法高亮跨度
- 换行时保持每个跨度的样式属性（颜色、粗体等）

### 2. 智能换行
- 在字符边界处分割，避免截断 Unicode 字符
- 使用 `wrap_styled_spans` 算法处理样式跨度

### 3. 续行缩进
- 首行：`1 +fn very_long_function_name...`（行号 + 符号 + 内容）
- 续行：`   g, arg_four...`（空格缩进对齐）

### 4. 显示宽度计算
- 正确处理 ASCII 字符（宽度 1）
- 处理 Tab 字符（宽度 4）
- 处理宽字符（CJK、Emoji，宽度 2）

## 具体技术实现

### 测试代码

```rust
#[test]
fn ui_snapshot_syntax_highlighted_insert_wraps() {
    let long_rust = "fn very_long_function_name(arg_one: String, arg_two: String, arg_three: String, arg_four: String) -> Result<String, Box<dyn std::error::Error>> { Ok(arg_one) }";

    let syntax_spans =
        highlight_code_to_styled_spans(long_rust, "rust").expect("rust highlighting");
    let spans = &syntax_spans[0];

    let lines = push_wrapped_diff_line_with_syntax_and_style_context(
        1,
        DiffLineType::Insert,
        long_rust,
        80,  // 渲染宽度
        line_number_width(1),
        spans,
        current_diff_render_style_context(),
    );

    assert!(lines.len() > 1, "syntax-highlighted long line should wrap to multiple lines");
    snapshot_lines("syntax_highlighted_insert_wraps", lines, 90, 10);
}
```

### 核心渲染函数

```rust
pub(crate) fn push_wrapped_diff_line_with_syntax_and_style_context(
    line_number: usize,
    kind: DiffLineType,
    text: &str,
    width: usize,
    line_number_width: usize,
    syntax_spans: &[RtSpan<'static>],
    style_context: DiffRenderStyleContext,
) -> Vec<RtLine<'static>> {
    push_wrapped_diff_line_inner_with_theme_and_color_level(
        line_number,
        kind,
        text,
        width,
        line_number_width,
        Some(syntax_spans),  // 传入语法高亮跨度
        style_context.theme,
        style_context.color_level,
        style_context.diff_backgrounds,
    )
}
```

### 样式跨度换行算法

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
            // 累积字符直到填满当前行
            let mut byte_end = 0;
            let mut chars_col = 0;

            for ch in remaining.chars() {
                let w = ch.width().unwrap_or(if ch == '\t' { TAB_WIDTH } else { 0 });
                if col + chars_col + w > max_cols {
                    break;  // 超出宽度限制，在此分割
                }
                byte_end += ch.len_utf8();
                chars_col += w;
            }

            if byte_end == 0 {
                // 单个字符宽度超过剩余空间，强制换行
                // ...
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
    // ...
}
```

### 行结构组装

```rust
// 带语法高亮的行渲染
if let Some(syn_spans) = syntax_spans {
    let gutter = format!("{ln_str:>gutter_width$} ");
    let sign = format!("{sign_char}");
    
    // 应用语法高亮样式，删除行添加 DIM 修饰
    let styled: Vec<RtSpan<'static>> = syn_spans
        .iter()
        .map(|sp| {
            let style = if matches!(kind, DiffLineType::Delete) {
                sp.style.add_modifier(Modifier::DIM)
            } else {
                sp.style
            };
            RtSpan::styled(sp.content.clone().into_owned(), style)
        })
        .collect();

    let available_content_cols = width.saturating_sub(prefix_cols + 1).max(1);
    let wrapped_chunks = wrap_styled_spans(&styled, available_content_cols);

    for (i, chunk) in wrapped_chunks.into_iter().enumerate() {
        let mut row_spans: Vec<RtSpan<'static>> = Vec::new();
        if i == 0 {
            // 首行：gutter + sign + content
            row_spans.push(RtSpan::styled(gutter.clone(), gutter_style));
            row_spans.push(RtSpan::styled(sign.clone(), sign_style));
        } else {
            // 续行：空 gutter + 双空格缩进
            let cont_gutter = format!("{:gutter_width$}  ", "");
            row_spans.push(RtSpan::styled(cont_gutter, gutter_style));
        }
        row_spans.extend(chunk);
        lines.push(RtLine::from(row_spans).style(line_bg));
    }
}
```

## 关键代码路径与文件引用

### 主要函数

| 函数名 | 位置 | 职责 |
|--------|------|------|
| `push_wrapped_diff_line_with_syntax_and_style_context` | diff_render.rs:815 | 带语法高亮的行渲染入口 |
| `push_wrapped_diff_line_inner_with_theme_and_color_level` | diff_render.rs:838 | 核心行渲染实现 |
| `wrap_styled_spans` | diff_render.rs:951 | 样式跨度智能换行 |
| `highlight_code_to_styled_spans` | render/highlight.rs | 语法高亮生成 |

### 语法高亮集成

```rust
// render/highlight.rs
pub fn highlight_code_to_styled_spans(
    code: &str,
    lang: &str,
) -> Option<Vec<Vec<RtSpan<'static>>>> {
    // 使用 syntect 进行语法高亮
    // 返回按行组织的样式跨度
}
```

### 快照内容分析

```
"1 +fn very_long_function_name(arg_one: String, arg_two: String, arg_three: Strin          "
"   g, arg_four: String) -> Result<String, Box<dyn std::error::Error>> { Ok(arg_o          "
"   ne) }                                                                                  "
```

- 第 1 行：行号 `1` + 符号 `+` + 截断的函数签名
- 第 2-3 行：3 空格缩进（对齐行号宽度）+ 续行内容
- 每行末尾有额外空格填充至终端宽度

## 依赖与外部交互

### syntect 语法高亮

```rust
// 通过 render/highlight.rs 集成 syntect
use syntect::easy::HighlightLines;
use syntect::parsing::SyntaxSet;
use syntect::highlighting::Theme;
```

### Unicode 宽度计算

```rust
use unicode_width::UnicodeWidthChar;

// 字符宽度计算
let w = ch.width().unwrap_or(if ch == '\t' { TAB_WIDTH } else { 0 });
```

### 样式继承

```rust
// 删除行使用 DIM 修饰降低视觉权重
let style = if matches!(kind, DiffLineType::Delete) {
    sp.style.add_modifier(Modifier::DIM)
} else {
    sp.style
};
```

## 风险、边界与改进建议

### 边界情况

1. **超长单词**
   - 单个标识符超过可用宽度时，`byte_end == 0` 分支强制分割
   - 可能导致单词内断行，影响可读性

2. **样式边界分割**
   - 当分割点位于样式跨度中间时，需要创建新的跨度
   - 当前实现正确保持样式，但可能产生大量小跨度

3. **Tab 字符处理**
   - Tab 宽度固定为 4 列
   - 在换行边界可能导致对齐问题

### 潜在风险

1. **性能问题**
   - 大量样式跨度时，换行算法复杂度为 O(n²)
   - 超长行（如 minified JS）可能导致性能下降

2. **内存分配**
   - 每个换行片段都创建新的 String
   - 频繁的小内存分配可能影响性能

3. **样式丢失**
   - 如果 `highlight_code_to_styled_spans` 返回 None，将回退到纯文本
   - 回退时可能丢失语言特定的视觉提示

### 改进建议

1. **智能断行**
   - 在标点符号或单词边界处优先断行
   - 参考 CSS `word-break` 和 `overflow-wrap` 策略

2. **性能优化**
   - 使用字符串切片而非克隆，减少内存分配
   - 对超长行限制最大渲染行数

3. **可配置 Tab 宽度**
   - 当前硬编码为 4，应支持用户配置
   - 检测 `.editorconfig` 或项目设置

4. **行号持久化**
   - 当前续行不显示行号
   - 可考虑在每行显示行号，便于引用

5. **测试扩展**
   - 添加更多语言的高亮换行测试
   - 测试极端情况（全宽字符、混合方向文本等）
