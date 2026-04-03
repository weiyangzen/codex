# Wrap Behavior Insert 快照研究文档

## 场景与职责

此快照测试展示了**纯文本插入行的自动换行**行为。与 `syntax_highlighted_insert_wraps` 不同，此测试验证不带语法高亮的长行换行，确保基础换行功能正常工作。

### 测试场景
- **变更类型**: 插入行（`DiffLineType::Insert`）
- **内容**: 纯文本长句（无代码）
- **渲染宽度**: 80 列
- **高亮**: 无（`syntax_spans = None`）

### 核心验证点
1. 纯文本长行正确换行
2. 续行缩进对齐正确
3. 无语法高亮时的默认样式应用
4. 插入行背景色正确应用

## 功能点目的

### 1. 基础换行功能
- 验证 `wrap_styled_spans` 对纯文本的处理
- 确保无高亮时的降级渲染正常

### 2. 插入行样式
- 应用插入行背景色（绿色调）
- 显示 `+` 符号
- 行号右对齐

### 3. 续行一致性
- 首行：`行号 + 符号 + 内容`
- 续行：`空格缩进 + 内容`
- 所有行应用相同的行背景色

## 具体技术实现

### 测试代码

```rust
#[test]
fn ui_snapshot_wrap_behavior_insert() {
    let long_line = "this is a very long line that should wrap across multiple terminal columns and continue";

    // 使用纯文本渲染（无语法高亮）
    let lines = push_wrapped_diff_line_with_style_context(
        1,
        DiffLineType::Insert,
        long_line,
        80,  // 渲染宽度
        line_number_width(1),
        current_diff_render_style_context(),  // 使用当前样式上下文
    );

    snapshot_lines("wrap_behavior_insert", lines, 90, 8);
}
```

### 纯文本渲染路径

```rust
pub(crate) fn push_wrapped_diff_line_with_style_context(
    line_number: usize,
    kind: DiffLineType,
    text: &str,
    width: usize,
    line_number_width: usize,
    style_context: DiffRenderStyleContext,
) -> Vec<RtLine<'static>> {
    push_wrapped_diff_line_inner_with_theme_and_color_level(
        line_number,
        kind,
        text,
        width,
        line_number_width,
        /*syntax_spans*/ None,  // 无语法高亮
        style_context.theme,
        style_context.color_level,
        style_context.diff_backgrounds,
    )
}
```

### 纯文本行渲染

```rust
// 无语法高亮时的渲染路径
let available_content_cols = width.saturating_sub(prefix_cols + 1).max(1);
let styled = vec![RtSpan::styled(text.to_string(), content_style)];
let wrapped_chunks = wrap_styled_spans(&styled, available_content_cols);

let mut lines: Vec<RtLine<'static>> = Vec::new();
for (i, chunk) in wrapped_chunks.into_iter().enumerate() {
    let mut row_spans: Vec<RtSpan<'static>> = Vec::new();
    if i == 0 {
        let gutter = format!("{ln_str:>gutter_width$} ");
        let sign = format!("{sign_char}");
        row_spans.push(RtSpan::styled(gutter, gutter_style));
        row_spans.push(RtSpan::styled(sign, sign_style));
    } else {
        let cont_gutter = format!("{:gutter_width$}  ", "");
        row_spans.push(RtSpan::styled(cont_gutter, gutter_style));
    }
    row_spans.extend(chunk);
    lines.push(RtLine::from(row_spans).style(line_bg));
}
```

### 样式应用

```rust
// 获取插入行样式
let (sign_char, sign_style, content_style) = match kind {
    DiffLineType::Insert => (
        '+',
        style_sign_add(theme, color_level, diff_backgrounds),
        style_add(theme, color_level, diff_backgrounds),
    ),
    // ...
};

let line_bg = style_line_bg_for(kind, diff_backgrounds);
let gutter_style = style_gutter_for(kind, theme, color_level);
```

## 关键代码路径与文件引用

### 核心函数

| 函数名 | 位置 | 职责 |
|--------|------|------|
| `push_wrapped_diff_line_with_style_context` | diff_render.rs:787 | 纯文本行渲染入口 |
| `push_wrapped_diff_line_inner_with_theme_and_color_level` | diff_render.rs:838 | 核心行渲染实现 |
| `style_add` | diff_render.rs:1258 | 插入行内容样式 |
| `style_sign_add` | diff_render.rs:1224 | 插入行符号样式 |
| `style_line_bg_for` | diff_render.rs:1140 | 行背景样式 |

### 样式函数

```rust
// 插入行内容样式
fn style_add(
    theme: DiffTheme,
    color_level: DiffColorLevel,
    diff_backgrounds: ResolvedDiffBackgrounds,
) -> Style {
    match (theme, color_level, diff_backgrounds.add) {
        (_, DiffColorLevel::Ansi16, _) => Style::default().fg(Color::Green),
        (DiffTheme::Light, _, Some(bg)) => Style::default().bg(bg),
        (DiffTheme::Dark, _, Some(bg)) => Style::default().fg(Color::Green).bg(bg),
        (DiffTheme::Light, _, None) => Style::default(),
        (DiffTheme::Dark, _, None) => Style::default().fg(Color::Green),
    }
}

// 行背景样式
fn style_line_bg_for(kind: DiffLineType, diff_backgrounds: ResolvedDiffBackgrounds) -> Style {
    match kind {
        DiffLineType::Insert => diff_backgrounds
            .add
            .map_or_else(Style::default, |bg| Style::default().bg(bg)),
        DiffLineType::Delete => diff_backgrounds
            .del
            .map_or_else(Style::default, |bg| Style::default().bg(bg)),
        DiffLineType::Context => Style::default(),
    }
}
```

### 快照内容分析

```
"1 +this is a very long line that should wrap across multiple terminal columns an          "
"   d continue                                                                             "
```

**第 1 行：**
- `1` - 行号（右对齐）
- ` ` - 空格分隔
- `+` - 插入符号
- `this is a very long line...an` - 内容（在 `an` 处截断，`d` 换到下一行）
- 尾部空格填充至终端宽度

**第 2 行：**
- `   ` - 3 空格缩进（与行号宽度 1 + 符号 1 + 空格 1 对齐）
- `d continue` - 续行内容

## 依赖与外部交互

### 样式上下文

```rust
pub(crate) fn current_diff_render_style_context() -> DiffRenderStyleContext {
    let theme = diff_theme();  // 检测终端主题
    let color_level = diff_color_level();  // 检测颜色支持
    let diff_backgrounds = resolve_diff_backgrounds(theme, color_level);
    DiffRenderStyleContext {
        theme,
        color_level,
        diff_backgrounds,
    }
}
```

### 宽度计算

```rust
// 可用内容宽度 = 总宽度 - gutter 宽度 - 符号宽度
let prefix_cols = line_number_width.max(1) + 1;  // gutter + 符号
let available_content_cols = width.saturating_sub(prefix_cols + 1).max(1);
```

## 风险、边界与改进建议

### 边界情况

1. **单词内换行**
   - 当前实现在字符边界换行
   - 可能导致单词被分割（如示例中的 `and` → `an` + `d`）
   - 可考虑在单词边界优先换行

2. **空内容**
   - 空字符串应至少生成一行
   - `wrap_styled_spans` 确保 `result.is_empty()` 时推送空行

3. **极窄宽度**
   - 当宽度小于 gutter 宽度时
   - `max(1)` 确保至少 1 列内容宽度

### 潜在风险

1. **样式上下文过时**
   - `current_diff_render_style_context` 每帧重新查询
   - 如果主题在渲染过程中切换，可能导致样式不一致

2. **背景色与前景色对比**
   - 某些主题组合可能导致可读性问题
   - 需要确保前景色与背景色有足够对比度

3. **性能**
   - 每行都创建新的 String
   - 大量长行时可能影响性能

### 改进建议

1. **智能断行**
   - 在单词边界优先断行
   - 使用 `unicode-segmentation` 识别单词边界

2. **连字符支持**
   - 长单词可在适当位置添加连字符换行
   - 参考 CSS `hyphens` 属性

3. **行高亮**
   - 为续行添加视觉提示（如 `↳` 符号）
   - 帮助用户识别续行关系

4. **配置选项**
   - 允许用户配置换行宽度
   - 或禁用自动换行（水平滚动）

5. **性能优化**
   - 使用字符串池减少内存分配
   - 对静态内容使用缓存

6. **测试扩展**
   - 添加删除行换行测试
   - 添加上下文行换行测试
   - 测试各种宽度和内容组合
