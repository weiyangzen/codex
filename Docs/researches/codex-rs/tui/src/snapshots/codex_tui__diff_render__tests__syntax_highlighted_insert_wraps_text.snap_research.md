# Syntax Highlighted Insert Wraps Text Snapshot 研究文档

## 场景与职责

此快照测试与 `syntax_highlighted_insert_wraps` 测试类似，但关注的是**纯文本输出**而非终端渲染输出。它验证了带语法高亮的长行在转换为纯文本格式时的正确性。

该测试的主要用途：
1. 验证换行逻辑不依赖终端特定的渲染特性
2. 便于在测试中直接阅读和理解输出内容
3. 作为 `terminal.backend()` 快照的人类可读补充

## 功能点目的

### 纯文本输出验证

与终端渲染版本的区别：

| 特性 | 终端渲染版本 | 纯文本版本 |
|------|-------------|-----------|
| 表达式 | `terminal.backend()` | `text` |
| 输出格式 | 终端缓冲区（含样式信息） | 纯字符串 |
| 可读性 | 需要特殊工具查看 | 直接可读 |
| 用途 | 验证视觉布局 | 验证内容正确性 |

### 测试内容

测试验证了同一段 Rust 代码的换行：

```rust
fn very_long_function_name(arg_one: String, arg_two: String, arg_three: String, arg_four: String) -> Result<String, Box<dyn std::error::Error>> { Ok(arg_one) }
```

在 80 列宽度下换行为 3 行：

```
1 +fn very_long_function_name(arg_one: String, arg_two: String, arg_three: Strin
   g, arg_four: String) -> Result<String, Box<dyn std::error::Error>> { Ok(arg_o
   ne) }
```

## 具体技术实现

### 文本提取逻辑

```rust
fn snapshot_lines_text(name: &str, lines: &[RtLine<'static>]) {
    // 将 Lines 转换为纯文本行，并去除尾部空格
    let text = lines
        .iter()
        .map(|l| {
            l.spans
                .iter()
                .map(|s| s.content.as_ref())  // 提取 span 内容
                .collect::<String>()          // 合并为字符串
        })
        .map(|s| s.trim_end().to_string())   // 去除尾部空格
        .collect::<Vec<_>>()
        .join("\n");
    assert_snapshot!(name, text);
}
```

### 与终端渲染的关系

```rust
// 终端渲染版本
fn snapshot_lines(name: &str, lines: Vec<RtLine<'static>>, width: u16, height: u16) {
    let mut terminal = Terminal::new(TestBackend::new(width, height)).expect("terminal");
    terminal
        .draw(|f| {
            Paragraph::new(Text::from(lines))
                .wrap(Wrap { trim: false })
                .render_ref(f.area(), f.buffer_mut())
        })
        .expect("draw");
    assert_snapshot!(name, terminal.backend());  // 捕获终端缓冲区
}
```

两个测试使用相同的 `lines` 输入，但验证不同方面：
- `syntax_highlighted_insert_wraps`：验证终端布局和样式
- `syntax_highlighted_insert_wraps_text`：验证文本内容和换行位置

## 关键代码路径与文件引用

### 测试辅助函数

| 函数 | 位置 | 行号 | 说明 |
|------|------|------|------|
| `snapshot_lines_text` | `diff_render.rs` (tests) | 1387-1402 | 纯文本快照辅助函数 |
| `ui_snapshot_syntax_highlighted_insert_wraps_text` | `diff_render.rs` | 1728-1747 | 本测试用例 |

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

    snapshot_lines_text("syntax_highlighted_insert_wraps_text", &lines);
}
```

### 输出格式对比

**终端渲染输出**（`syntax_highlighted_insert_wraps.snap`）：
```
"1 +fn very_long_function_name(arg_one: String, arg_two: String, arg_three: Strin          "
"   g, arg_four: String) -> Result<String, Box<dyn std::error::Error>> { Ok(arg_o          "
"   ne) }                                                                                  "
```

**纯文本输出**（`syntax_highlighted_insert_wraps_text.snap`）：
```
1 +fn very_long_function_name(arg_one: String, arg_two: String, arg_three: Strin
   g, arg_four: String) -> Result<String, Box<dyn std::error::Error>> { Ok(arg_o
   ne) }
```

注意终端版本包含尾部空格填充到终端宽度，而文本版本已去除。

## 依赖与外部交互

### 依赖关系

```
ui_snapshot_syntax_highlighted_insert_wraps_text
  ├── highlight_code_to_styled_spans (语法高亮)
  ├── push_wrapped_diff_line_with_syntax_and_style_context (带换行的行渲染)
  └── snapshot_lines_text (纯文本提取)
       └── assert_snapshot! (insta 快照断言)
```

### 无外部终端依赖

该测试不依赖：
- 终端模拟器
- 颜色支持检测
- 字体渲染

只验证纯文本内容的正确性。

## 风险、边界与改进建议

### 当前限制

1. **样式信息丢失**：
   - 纯文本版本无法验证语法高亮颜色
   - 无法检测样式相关的 bug

2. **空格处理**：
   ```rust
   .map(|s| s.trim_end().to_string())
   ```
   去除尾部空格可能掩盖某些布局问题

3. **重复测试**：
   - 与终端版本测试高度重叠
   - 维护成本增加

### 改进建议

1. **合并测试**：
   - 考虑将两个测试合并，同时验证终端和文本输出
   - 减少重复代码

2. **增强文本版本**：
   - 添加简单的样式标记（如 ANSI 转义序列）到文本输出
   - 允许在纯文本中验证颜色和样式

3. **差异化测试策略**：
   - 终端版本：专注布局、样式、对齐
   - 文本版本：专注内容正确性、换行位置

4. **自动化验证**：
   - 添加脚本验证两个快照的一致性
   - 确保文本版本是终端版本的准确子集

5. **扩展覆盖**：
   - 为其他复杂场景（如多行删除、混合上下文）添加文本版本测试
   - 便于代码审查时快速理解测试意图
