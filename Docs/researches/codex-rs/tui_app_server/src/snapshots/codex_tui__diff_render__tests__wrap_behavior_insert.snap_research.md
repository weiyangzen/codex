# Research: Diff Render Wrap Behavior for Insert Lines

## 场景与职责

该快照测试验证 Codex TUI 中 diff 渲染器对插入行（Insert lines）的自动换行（wrap）行为。在终端界面中显示代码差异时，当单行内容超出可用列宽，需要正确地将长行分割为多行显示，同时保持行号、符号（+）和语法高亮样式的正确对齐。

## 功能点目的

1. **自动换行**: 当 diff 行的内容超过可用宽度时，自动将内容换行到下一行
2. **视觉对齐**: 换行后的内容应与第一行的内容对齐（缩进），而非与行号对齐
3. **符号位置**: 只有第一行显示 `+` 符号，续行使用空格缩进保持对齐
4. **样式保持**: 换行过程中保持语法高亮和 diff 背景色样式

## 具体技术实现

### 核心函数
```rust
push_wrapped_diff_line_inner_with_theme_and_color_level(
    line_number: usize,
    kind: DiffLineType,
    text: &str,
    width: usize,
    line_number_width: usize,
    syntax_spans: Option<&[RtSpan<'static>]>,
    theme: DiffTheme,
    color_level: DiffColorLevel,
    diff_backgrounds: ResolvedDiffBackgrounds,
) -> Vec<RtLine<'static>>
```

### 换行逻辑
1. 计算可用内容列数：`available_content_cols = width.saturating_sub(prefix_cols + 1).max(1)`
2. 调用 `wrap_styled_spans()` 将样式化的 spans 分割成适合宽度的 chunks
3. 第一行包含：行号（右对齐）+ 符号（+）+ 内容
4. 续行包含：空 gutter（与行号同宽）+ 两空格缩进 + 内容

### 测试代码位置
- 文件: `codex-rs/tui/src/diff_render.rs`
- 测试函数: `ui_snapshot_wrap_behavior_insert`
- 行号: 约 1489-1506

```rust
#[test]
fn ui_snapshot_wrap_behavior_insert() {
    let long_line = "this is a very long line that should wrap across multiple terminal columns and continue";
    let lines = push_wrapped_diff_line_with_style_context(
        1,
        DiffLineType::Insert,
        long_line,
        80,
        line_number_width(1),
        current_diff_render_style_context(),
    );
    snapshot_lines("wrap_behavior_insert", lines, 90, 8);
}
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/diff_render.rs` | Diff 渲染核心实现，包含换行逻辑 |
| `codex-rs/tui/src/diff_render.rs:838-938` | `push_wrapped_diff_line_inner_with_theme_and_color_level` 函数 |
| `codex-rs/tui/src/diff_render.rs:951-1020` | `wrap_styled_spans` 函数，处理样式化文本的换行 |

### 依赖模块
- `unicode_width::UnicodeWidthChar`: 计算字符显示宽度（处理 CJK、emoji 等宽字符）
- `ratatui::text::Line/Span`: 终端 UI 文本渲染
- `diffy::Patch`: 解析 unified diff 格式

## 依赖与外部交互

### 输入
- 长文本字符串（如 `"this is a very long line that should wrap..."`）
- 终端宽度约束（测试中使用 80 列宽度，90 列终端）
- 样式上下文（主题、颜色级别、背景色）

### 输出
- 多行 `RtLine` 向量，每行包含适当的 spans 和样式
- 快照输出显示：
  - 第1行: `1 +this is a very long line that should wrap across multiple terminal columns an`
  - 第2行: `   d continue`（缩进对齐）

### 相关配置
- `TAB_WIDTH`: 制表符显示宽度（4 列）
- `DiffTheme::Dark/Light`: 暗色/亮色主题
- `DiffColorLevel`: 颜色深度（TrueColor/Ansi256/Ansi16）

## 风险、边界与改进建议

### 潜在风险
1. **CJK 字符处理**: 虽然使用了 `UnicodeWidthChar`，但在极端情况下宽字符可能导致对齐偏差
2. **性能**: 极长的单行（如数千字符）可能导致大量换行计算
3. **终端兼容性**: ANSI-16 模式下背景色处理与 TrueColor 不同

### 边界情况
1. **单字符超宽**: 当单个字符宽度超过剩余可用空间时的强制换行处理（`byte_end == 0` 分支）
2. **空行处理**: 空行应至少返回一个空 Line
3. **语法高亮跨行**: 确保 syntax spans 在换行边界正确分割，保持样式连续性

### 改进建议
1. **性能优化**: 对于超长的 diff 内容，考虑在渲染前进行预截断（已有 `exceeds_highlight_limits` 检查）
2. **可配置换行**: 支持用户配置是否启用换行或截断
3. **水平滚动**: 作为换行的替代方案，考虑支持水平滚动模式
4. **测试覆盖**: 增加对删除行（Delete）、上下文行（Context）的换行测试，以及混合内容的测试
