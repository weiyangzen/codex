# Wrap Behavior Insert Snapshot 研究文档

## 场景与职责

此快照测试验证了**纯文本长行（无语法高亮）的自动换行**功能。与 `syntax_highlighted_insert_wraps` 测试不同，此测试关注无样式文本的换行行为。

测试场景：
- 一行较长的纯文本需要换行
- 无语法高亮（`syntax_spans = None`）
- 验证基本换行逻辑的正确性

## 功能点目的

### 纯文本换行

```
1 +this is a very long line that should wrap across multiple terminal columns an
   d continue
```

关键验证点：
1. **行号显示**：第一行显示行号 `1`
2. **符号显示**：第一行显示 `+` 号
3. **续行缩进**：续行使用空白 gutter + 2 空格缩进
4. **单词边界换行**：在单词边界处断开（`an` / `d`）

### 与语法高亮换行的区别

| 特性 | 纯文本换行 | 语法高亮换行 |
|------|-----------|-------------|
| 输入 | `&str` | `&[RtSpan]` |
| 样式 | 单一样式 | 多段不同样式 |
| 处理 | 直接按字符宽度换行 | 需保持样式边界 |
| 性能 | 较快 | 较慢（需处理 spans）|

## 具体技术实现

### 纯文本渲染路径

```rust
// 无语法高亮时的渲染
} else {
    let available_content_cols = width.saturating_sub(prefix_cols + 1).max(1);
    // 创建单一样式的 span
    let styled = vec![RtSpan::styled(text.to_string(), content_style)];
    // 使用与语法高亮相同的换行逻辑
    let wrapped_chunks = wrap_styled_spans(&styled, available_content_cols);

    let mut lines: Vec<RtLine<'static>> = Vec::new();
    for (i, chunk) in wrapped_chunks.into_iter().enumerate() {
        let mut row_spans: Vec<RtSpan<'static>> = Vec::new();
        if i == 0 {
            // 第一行：gutter + 符号
            let gutter = format!("{ln_str:>gutter_width$} ");
            let sign = format!("{sign_char}");
            row_spans.push(RtSpan::styled(gutter, gutter_style));
            row_spans.push(RtSpan::styled(sign, sign_style));
        } else {
            // 续行：空白 gutter + 2 空格
            let cont_gutter = format!("{:gutter_width$}  ", "");
            row_spans.push(RtSpan::styled(cont_gutter, gutter_style));
        }
        row_spans.extend(chunk);
        lines.push(RtLine::from(row_spans).style(line_bg));
    }
    lines
}
```

### 样式定义

```rust
let (sign_char, sign_style, content_style) = match kind {
    DiffLineType::Insert => (
        '+',
        style_sign_add(theme, color_level, diff_backgrounds),
        style_add(theme, color_level, diff_backgrounds),
    ),
    // ...
};
```

对于插入行：
- 符号 `+`：绿色（暗色主题）或仅绿色前景（亮色主题）
- 内容：绿色前景 + 绿色背景（暗色）或仅绿色背景（亮色）

### 换行算法

使用与语法高亮相同的 `wrap_styled_spans` 函数：

```rust
fn wrap_styled_spans(spans: &[RtSpan<'static>], max_cols: usize) -> Vec<Vec<RtSpan<'static>>> {
    // 算法详情见 syntax_highlighted_insert_wraps 文档
    // ...
}
```

对于纯文本，输入是只有一个 span 的数组，算法简化为：
1. 按字符宽度累积
2. 超过 `max_cols` 时换行
3. 处理宽字符和 Tab

## 关键代码路径与文件引用

### 核心函数

| 函数 | 文件 | 行号 | 职责 |
|------|------|------|------|
| `push_wrapped_diff_line_inner_with_theme_and_color_level` | `diff_render.rs` | 838-938 | 单行 diff 渲染（含纯文本分支） |
| `wrap_styled_spans` | `diff_render.rs` | 951-1020 | 文本换行核心算法 |
| `ui_snapshot_wrap_behavior_insert` | `diff_render.rs` | 1489-1506 | 本测试用例 |

### 测试代码

```rust
#[test]
fn ui_snapshot_wrap_behavior_insert() {
    let long_line = "this is a very long line that should wrap across multiple terminal columns and continue";

    // 直接调用换行函数，精确控制宽度
    let lines = push_wrapped_diff_line_with_style_context(
        1,
        DiffLineType::Insert,
        long_line,
        80,  // 换行宽度
        line_number_width(1),
        current_diff_render_style_context(),
    );

    // 渲染到小终端捕获视觉布局
    snapshot_lines("wrap_behavior_insert", lines, 90, 8);
}
```

### 样式上下文

```rust
pub(crate) struct DiffRenderStyleContext {
    theme: DiffTheme,                    // 当前主题
    color_level: DiffColorLevel,         // 颜色深度
    diff_backgrounds: ResolvedDiffBackgrounds,  // 解析后的背景色
}
```

## 依赖与外部交互

### 样式系统

- `style_add`：插入行内容样式
- `style_sign_add`：插入行符号样式
- `style_gutter_for`：行号 gutter 样式
- `style_line_bg_for`：行背景样式

### 颜色级别

```rust
enum DiffColorLevel {
    TrueColor,  // 24-bit 真彩色
    Ansi256,    // 256 色
    Ansi16,     // 16 色（无背景）
}
```

## 风险、边界与改进建议

### 边界情况

1. **极长单词**：
   - 如果单词长度超过可用宽度
   - 算法会强制在字符边界断开
   - 可能导致单词被不自然地分割

2. **Tab 字符**：
   - Tab 宽度为 4 列
   - 在换行边界可能导致对齐问题
   - 示例：`"ab\tcde"` 在 5 列宽度下可能显示为：
     ```
     1 +ab  
        cde
     ```

3. **Unicode 宽字符**：
   - CJK 字符占 2 列
   - Emoji 可能占 2 列
   - 某些字符宽度检测可能不准确

4. **空行或空白行**：
   - 空行仍需显示行号和符号
   - 续行可能只有空白

### 潜在问题

1. **换行位置**：
   ```
   1 +this is a very long line that should wrap across multiple terminal columns an
      d continue
   ```
   单词 `and` 被分割为 `an` / `d`，可能影响阅读

2. **性能**：
   - 逐字符处理长行
   - 对于 10KB+ 的单行，可能影响性能

3. **样式一致性**：
   - 续行使用与第一行相同的行背景
   - 但在某些终端上可能有渲染差异

### 改进建议

1. **智能换行**：
   - 优先在单词边界换行
   - 对于超长单词，考虑使用连字符（hyphenation）
   - 或添加视觉提示（如 `↳`）表示续行

2. **Tab 处理**：
   - 考虑将 Tab 扩展为空格后换行
   - 或实现 Tab 停止位对齐

3. **性能优化**：
   - 使用字节级操作而非字符迭代
   - 对 ASCII 字符进行批量处理

4. **可配置性**：
   - 允许用户配置续行缩进宽度
   - 允许配置是否启用自动换行
   - 配置 Tab 宽度（当前硬编码为 4）

5. **视觉增强**：
   - 在续行前添加 `...` 或 `↳` 提示
   - 对续行使用略微不同的背景色
   - 添加行尾标记（如 `¶`）

6. **测试覆盖**：
   - 添加 Tab 字符换行测试
   - 添加 CJK 字符换行测试
   - 添加空行和空白行测试
