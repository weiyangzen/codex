# 研究文档：markdown_render_complex_snapshot.snap

## 场景与职责

此快照测试验证 Codex TUI 的 Markdown 渲染器对复杂 Markdown 文档的渲染效果。这是全面的功能测试，覆盖多种 Markdown 元素。

## 功能点目的

1. **完整 Markdown 支持**：支持标准 Markdown 语法
2. **样式应用**：为不同元素应用适当的样式
3. **换行处理**：正确处理长文本换行

## 具体技术实现

### 支持的 Markdown 元素

从快照中可以看到支持的元素：

```markdown
# H1: Markdown Streaming Test

**bold text**, *italic text*, `inline code`

Auto-link: https://example.com

> Blockquote level 1
> > Blockquote level 2

- Unordered list
1. Ordered list
- [ ] Task list
- [x] Checked task

| Table | Header |
|-------|--------|
| cell  | cell   |

```json
{ "code": "block" }
```
```

### 渲染实现

```rust
// codex-rs/tui/src/markdown_render.rs
pub fn render_markdown_text(input: &str) -> Text<'static> {
    render_markdown_text_with_width(input, /*width*/ None)
}

pub(crate) fn render_markdown_text_with_width_and_cwd(
    input: &str,
    width: Option<usize>,
    cwd: Option<&Path>,
) -> Text<'static> {
    let mut options = Options::empty();
    options.insert(Options::ENABLE_STRIKETHROUGH);
    let parser = Parser::new_ext(input, options);
    let mut w = Writer::new(parser, width, cwd);
    w.run();
    w.text
}
```

## 关键代码路径与文件引用

1. **Markdown 渲染器**：
   - `codex-rs/tui/src/markdown_render.rs` - 主实现
   - `codex-rs/tui/src/markdown_render_tests.rs` - 测试

2. **依赖库**：
   - `pulldown_cmark` - Markdown 解析器
   - `syntect` - 语法高亮

## 依赖与外部交互

### 解析依赖
- `pulldown_cmark::Parser` - Markdown 事件解析
- `pulldown_cmark::Options` - 解析选项

### 样式依赖
- `ratatui::style::Style` - 样式定义
- `crate::render::highlight::highlight_code_to_lines` - 代码高亮

## 风险、边界与改进建议

### 潜在风险
1. **解析性能**：复杂文档可能导致解析缓慢
2. **内存使用**：大量嵌套元素可能消耗大量内存

### 边界情况
1. 嵌套列表层级过深
2. 表格列数不一致
3. 代码块语言未知

### 改进建议
1. 添加更多 Markdown 扩展支持（如 GFM）
2. 优化大文档的渲染性能
3. 添加图片渲染支持
4. 支持链接点击跳转
