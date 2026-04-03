# Syntax Highlighted Insert Wraps Snapshot 研究文档

## 场景与职责

此快照测试验证了**带语法高亮的长行自动换行**功能。测试场景是一段 Rust 代码，由于长度超过终端宽度，需要在保持语法高亮的同时正确换行。

这是 diff 渲染中最复杂的场景之一，因为需要：
1. 保持语法高亮的样式信息（颜色、字体样式）
2. 在字符边界正确分割长行
3. 确保换行后的缩进对齐

## 功能点目的

### 核心功能

1. **语法高亮保持**：换行后每个片段保持原有的语法高亮样式
2. **智能缩进**：
   - 第一行：显示行号 + `+` 符号 + 内容
   - 续行：显示空白 gutter（对齐到内容列）+ 2 空格缩进 + 内容

### 换行布局示例

```
1 +fn very_long_function_name(arg_one: String, arg_two: String, arg_three: Strin
   g, arg_four: String) -> Result<String, Box<dyn std::error::Error>> { Ok(arg_o
   ne) }
```

布局说明：
- 第 1 行：`1`（行号）+ `+`（符号）+ 内容前段
- 第 2-3 行：空白 gutter + 2 空格 + 内容续段

## 具体技术实现

### 核心算法

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
            // 累积字符直到填满当前行
            let mut byte_end = 0;
            let mut chars_col = 0;

            for ch in remaining.chars() {
                let w = ch.width().unwrap_or(if ch == '\t' { TAB_WIDTH } else { 0 });
                if col + chars_col + w > max_cols {
                    break;  // 超出行宽，停止累积
                }
                byte_end += ch.len_utf8();
                chars_col += w;
            }

            if byte_end == 0 {
                // 单个字符宽于剩余空间，强制换行
                if !current_line.is_empty() {
                    result.push(std::mem::take(&mut current_line));
                }
                // 取至少一个字符避免无限循环
                let ch = remaining.chars().next().unwrap();
                current_line.push(RtSpan::styled(
                    remaining[..ch.len_utf8()].to_string(), 
                    style
                ));
                col = ch.width().unwrap_or(1);
                remaining = &remaining[ch.len_utf8()..];
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
    // ...
}
```

### 样式保持机制

```rust
// 对语法高亮的 spans 进行换行
let styled: Vec<RtSpan<'static>> = syn_spans
    .iter()
    .map(|sp| {
        let style = if matches!(kind, DiffLineType::Delete) {
            sp.style.add_modifier(Modifier::DIM)  // 删除行添加 DIM
        } else {
            sp.style  // 保持原有语法高亮样式
        };
        RtSpan::styled(sp.content.clone().into_owned(), style)
    })
    .collect();

let wrapped_chunks = wrap_styled_spans(&styled, available_content_cols);
```

### 行组装逻辑

```rust
let mut lines: Vec<RtLine<'static>> = Vec::new();
for (i, chunk) in wrapped_chunks.into_iter().enumerate() {
    let mut row_spans: Vec<RtSpan<'static>> = Vec::new();
    if i == 0 {
        // 第一行：gutter + 符号 + 内容
        row_spans.push(RtSpan::styled(gutter.clone(), gutter_style));
        row_spans.push(RtSpan::styled(sign.clone(), sign_style));
    } else {
        // 续行：空白 gutter + 2 空格缩进
        let cont_gutter = format!("{:gutter_width$}  ", "");
        row_spans.push(RtSpan::styled(cont_gutter, gutter_style));
    }
    row_spans.extend(chunk);
    lines.push(RtLine::from(row_spans).style(line_bg));
}
```

## 关键代码路径与文件引用

### 核心函数

| 函数 | 文件 | 行号 | 职责 |
|------|------|------|------|
| `wrap_styled_spans` | `diff_render.rs` | 951-1020 | 带样式的文本换行核心算法 |
| `push_wrapped_diff_line_inner_with_theme_and_color_level` | `diff_render.rs` | 838-938 | 单行 diff 渲染（含换行） |
| `ui_snapshot_syntax_highlighted_insert_wraps` | `diff_render.rs` | 1699-1726 | 本测试用例 |

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
        80,  // 目标宽度
        line_number_width(1),
        spans,
        current_diff_render_style_context(),
    );

    assert!(lines.len() > 1, "syntax-highlighted long line should wrap to multiple lines");
    snapshot_lines("syntax_highlighted_insert_wraps", lines, 90, 10);
}
```

### 依赖模块

- `crate::render::highlight::highlight_code_to_styled_spans`：语法高亮
- `unicode_width::UnicodeWidthChar`：字符宽度计算

## 依赖与外部交互

### 语法高亮集成

```rust
// 从 syntect 获取高亮结果
pub fn highlight_code_to_styled_spans(
    code: &str,
    language: &str,
) -> Option<Vec<Vec<RtSpan<'static>>>>
```

返回的 `RtSpan` 包含：
- `content`：文本内容
- `style`：ratatui 样式（前景色、背景色、修饰符）

### Unicode 宽度计算

使用 `unicode-width` crate 处理：
- ASCII 字符：宽度 1
- Tab 字符：宽度 4（`TAB_WIDTH` 常量）
- CJK 字符：宽度 2
- 零宽字符：宽度 0

## 风险、边界与改进建议

### 边界情况

1. **极宽字符**：
   - 某些 Unicode 字符可能占 2 列以上
   - 当前代码假设最大宽度为 2

2. **零宽字符**：
   - 零宽连接符、变体选择符等
   - 可能被错误地分割导致显示异常

3. **Tab 字符处理**：
   ```rust
   let w = ch.width().unwrap_or(if ch == '\t' { TAB_WIDTH } else { 0 });
   ```
   Tab 在换行边界时可能导致对齐问题

4. **样式边界**：
   - 如果换行正好落在样式变化的位置
   - 需要确保样式正确应用到续行

### 性能考虑

```rust
// 当前实现遍历每个字符
for ch in remaining.chars() {
    let w = ch.width().unwrap_or(...);
    // ...
}
```

对于极长行（如 10KB 的单行），逐字符处理可能成为性能瓶颈。

### 改进建议

1. **性能优化**：
   - 使用 SIMD 或字节级操作加速宽度计算
   - 对已知宽度的字符（如 ASCII）进行批量处理

2. **对齐优化**：
   - 考虑使用制表符停止位（tab stops）而非固定缩进
   - 允许用户配置续行缩进宽度

3. **样式优化**：
   - 在续行前添加视觉提示（如 `↳` 或 `...`）
   - 考虑对续行使用略微不同的背景色

4. **边界处理**：
   - 添加对组合字符（grapheme clusters）的正确处理
   - 测试各种极端 Unicode 场景

5. **可配置性**：
   - 允许用户禁用语法高亮（提高性能）
   - 配置是否启用自动换行
