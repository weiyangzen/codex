# Syntax Highlighted Insert Wraps Text 快照研究文档

## 场景与职责

此快照测试是 `syntax_highlighted_insert_wraps` 的**纯文本版本**，专注于验证换行后的文本内容正确性，而不包含终端样式信息。

### 与图形版本的区别

| 特性 | `syntax_highlighted_insert_wraps` | `syntax_highlighted_insert_wraps_text` |
|------|-----------------------------------|----------------------------------------|
| 输出格式 | 终端后端快照（含样式） | 纯文本拼接 |
| 验证重点 | 视觉布局和样式 | 文本内容和缩进 |
| 使用函数 | `snapshot_lines` | `snapshot_lines_text` |

### 测试场景
- 与图形版本相同：Rust 超长函数签名换行
- 验证文本截断和缩进符合预期

## 功能点目的

### 1. 纯文本内容验证
- 排除样式干扰，专注验证文本正确性
- 便于人工审查预期的文本输出

### 2. 缩进对齐验证
- 验证续行缩进使用空格而非制表符
- 确保缩进宽度与行号 gutter 对齐

### 3. 换行位置验证
- 确认换行发生在正确的字符边界
- 验证没有字符丢失或重复

## 具体技术实现

### 纯文本快照函数

```rust
fn snapshot_lines_text(name: &str, lines: &[RtLine<'static>]) {
    // 将 Lines 转换为纯文本行，并修剪尾部空格
    let text = lines
        .iter()
        .map(|l| {
            l.spans
                .iter()
                .map(|s| s.content.as_ref())
                .collect::<String>()
        })
        .map(|s| s.trim_end().to_string())  // 修剪尾部空格
        .collect::<Vec<_>>()
        .join("\n");
    assert_snapshot!(name, text);
}
```

### 与图形快照函数的对比

```rust
// 图形版本：保留完整终端状态
fn snapshot_lines(name: &str, lines: Vec<RtLine<'static>>, width: u16, height: u16) {
    let mut terminal = Terminal::new(TestBackend::new(width, height)).expect("terminal");
    terminal
        .draw(|f| {
            Paragraph::new(Text::from(lines))
                .wrap(Wrap { trim: false })
                .render_ref(f.area(), f.buffer_mut())
        })
        .expect("draw");
    assert_snapshot!(name, terminal.backend());  // 捕获完整终端状态
}
```

## 关键代码路径与文件引用

### 测试代码

```rust
#[test]
fn ui_snapshot_syntax_highlighted_insert_wraps_text() {
    let long_rust = "fn very_long_function_name(arg_one: String, arg_two: String, arg_three: String, arg_four: String) -> Result<String, Box<dyn std::error::Error>> { Ok(arg_one) }";

    let syntax_spans =
        highlight_code_to_styled_spans(long_rust, "rust").expect("rust highlighting");
    let spans = &syntax_spans[0];

    let lines = push_wrapped_diff_line_with_syntax_and_style_context(
        1,
        DiffLineType::Insert,
        long_rust,
        80,
        line_number_width(1),
        spans,
        current_diff_render_style_context(),
    );

    snapshot_lines_text("syntax_highlighted_insert_wraps_text", &lines);  // 使用文本快照
}
```

### 快照内容分析

```
1 +fn very_long_function_name(arg_one: String, arg_two: String, arg_three: Strin
   g, arg_four: String) -> Result<String, Box<dyn std::error::Error>> { Ok(arg_o
   ne) }
```

**第 1 行分析：**
- `1` - 行号（右对齐，宽度 1）
- ` ` - 行号后空格
- `+` - 插入符号
- `fn very_long_function_name...Strin` - 内容（截断于 `Strin`，`g` 被换行）

**第 2-3 行分析：**
- `   ` - 3 空格缩进（与行号宽度 1 + 符号 1 + 空格 1 对齐）
- 续行内容

## 依赖与外部交互

### 文本处理依赖

```rust
// 字符串修剪
.map(|s| s.trim_end().to_string())
```

- `trim_end()` 移除尾部空白字符（空格、制表符等）
- 使快照更易于阅读，避免显示大量填充空格

### Span 内容提取

```rust
l.spans
    .iter()
    .map(|s| s.content.as_ref())  // 提取 Span 内容引用
    .collect::<String>()           // 拼接为完整字符串
```

## 风险、边界与改进建议

### 纯文本快照的局限性

1. **样式信息丢失**
   - 无法验证语法高亮颜色是否正确应用
   - 无法检测背景色或修饰符（粗体、斜体等）

2. **布局信息缺失**
   - 不知道实际终端宽度
   - 无法验证右侧填充

3. **字符可见性**
   - 某些控制字符可能在纯文本中不可见
   - 零宽字符（如零宽空格）可能被忽略

### 改进建议

1. **组合测试策略**
   - 同时使用图形和文本快照
   - 图形验证视觉，文本验证内容

2. **增强文本表示**
   - 可考虑使用类似 `ansi-to-html` 的方式保留颜色信息
   - 或使用自定义格式编码样式

3. **差异可读性**
   - 当测试失败时，纯文本差异比终端缓冲区差异更易读
   - 考虑在 CI 输出中优先显示文本版本

4. **多编码支持**
   - 验证不同编码下的文本处理
   - 测试 UTF-8 边缘情况（如 4 字节字符）
