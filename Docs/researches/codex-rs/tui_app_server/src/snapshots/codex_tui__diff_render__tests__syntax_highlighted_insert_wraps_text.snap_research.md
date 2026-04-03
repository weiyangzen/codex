# 研究文档: syntax_highlighted_insert_wraps_text

## 场景与职责

该测试是 `syntax_highlighted_insert_wraps` 的纯文本版本，验证语法高亮长行的换行逻辑在纯文本层面的正确性。与主测试的区别在于，此测试只关注文本内容的换行结果，而不涉及终端渲染的样式信息。

这种分离测试的设计允许开发者：
1. 快速验证换行逻辑的正确性（无需比较样式转义序列）
2. 更清晰地查看换行后的文本结构
3. 减少快照文件的大小和噪音

## 功能点目的

1. **纯文本换行验证**: 确认长代码行被正确分割为多个逻辑行
2. **内容完整性**: 确保换行后所有字符都被保留，无丢失或重复
3. **缩进一致性**: 验证续行的缩进对齐（两个空格）

测试使用与主测试相同的超长 Rust 函数：
```rust
fn very_long_function_name(arg_one: String, arg_two: String, arg_three: String, arg_four: String) -> Result<String, Box<dyn std::error::Error>> { Ok(arg_one) }
```

## 具体技术实现

### 测试流程

1. **生成语法高亮** (行 1731-1733):
   ```rust
   let syntax_spans = highlight_code_to_styled_spans(long_rust, "rust").expect("rust highlighting");
   let spans = &syntax_spans[0];
   ```

2. **执行换行渲染** (行 1736-1744):
   ```rust
   let lines = push_wrapped_diff_line_with_syntax_and_style_context(
       1,
       DiffLineType::Insert,
       long_rust,
       80,
       line_number_width(1),
       spans,
       current_diff_render_style_context(),
   );
   ```

3. **纯文本快照** (行 1746):
   ```rust
   snapshot_lines_text("syntax_highlighted_insert_wraps_text", &lines);
   ```

### 辅助函数: `snapshot_lines_text`

位于行 1387-1402，将 `RtLine` 列表转换为纯文本字符串：

```rust
fn snapshot_lines_text(name: &str, lines: &[RtLine<'static>]) {
    let text = lines
        .iter()
        .map(|l| {
            l.spans
                .iter()
                .map(|s| s.content.as_ref())
                .collect::<String>()
        })
        .map(|s| s.trim_end().to_string())  // 去除尾部空格
        .collect::<Vec<_>>()
        .join("\n");
    assert_snapshot!(name, text);
}
```

### 输出格式

```
1 +fn very_long_function_name(arg_one: String, arg_two: String, arg_three: Strin
   g, arg_four: String) -> Result<String, Box<dyn std::error::Error>> { Ok(arg_o
   ne) }
```

与终端渲染版本相比，纯文本版本：
- 不包含样式转义序列
- 去除了行末填充空格
- 更易读和验证

## 关键代码路径与文件引用

### 主要文件

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/diff_render.rs` | 包含测试代码和 `snapshot_lines_text` 辅助函数 |

### 关键代码位置

| 元素 | 行号 | 说明 |
|------|------|------|
| `ui_snapshot_syntax_highlighted_insert_wraps_text` | 1728-1747 | 测试函数 |
| `snapshot_lines_text` | 1387-1402 | 纯文本快照辅助函数 |
| `push_wrapped_diff_line_with_syntax_and_style_context` | 815-835 | 带语法高亮的换行入口 |

### 相关测试模式

该测试遵循 TUI 测试中的常见模式：
- `ui_snapshot_*` - 终端渲染快照测试
- `*_text` 后缀 - 纯文本版本（无样式）

其他类似测试对：
- `apply_update_block_wraps_long_lines` / `apply_update_block_wraps_long_lines_text`
- `line_numbers_three_digits` / `line_numbers_three_digits_text`

## 依赖与外部交互

### 测试依赖

| 依赖 | 用途 |
|------|------|
| `insta::assert_snapshot` | 快照断言 |
| `ratatui::text::RtLine` | 行数据结构 |
| `ratatui::text::RtSpan` | 带样式的文本片段 |

### 与主测试的关系

```
syntax_highlighted_insert_wraps
├── 终端渲染版本 (syntax_highlighted_insert_wraps.snap)
│   └── 包含样式转义序列和填充空格
└── 纯文本版本 (syntax_highlighted_insert_wraps_text.snap)
    └── 仅包含可见字符，去除样式信息
```

两个测试共享相同的输入数据和换行逻辑，只是输出格式不同。

## 风险、边界与改进建议

### 测试冗余度

**现状**: 两个测试使用相同的输入和逻辑，只是输出格式不同。

**风险**: 
- 维护成本增加（需要更新两个快照）
- 如果逻辑改变，两个测试都会失败

**建议**:
1. 保留两个测试，但明确分工：
   - 文本版本：验证换行逻辑正确性
   - 终端版本：验证样式渲染正确性
2. 或者合并为一个测试，使用多表达式快照

### 边界情况覆盖

当前测试仅覆盖：
- ✅ 单行超长 Rust 代码
- ✅ 插入类型（`+`）差异行

未覆盖：
- ❌ 删除类型（`-`）长行
- ❌ 多行代码块
- ❌ 不同语言的高亮
- ❌ 包含特殊 Unicode 字符的代码

### 改进建议

1. **添加删除行测试**: 验证删除行的换行同样正确
   ```rust
   #[test]
   fn ui_snapshot_syntax_highlighted_delete_wraps_text() { ... }
   ```

2. **参数化测试**: 使用 `rstest` 或类似框架参数化语言类型
   ```rust
   #[test_case("rust")]
   #[test_case("python")]
   #[test_case("javascript")]
   fn syntax_highlighted_wraps(lang: &str) { ... }
   ```

3. **验证换行位置**: 当前仅验证整体输出，可添加断言验证特定字符是否位于预期行
   ```rust
   assert!(lines[0].spans.iter().any(|s| s.content.contains("arg_three")));
   assert!(lines[1].spans.iter().any(|s| s.content.contains("arg_four")));
   ```

4. **文档化换行算法**: 在 `wrap_styled_spans` 函数中添加更多注释，说明换行决策逻辑
