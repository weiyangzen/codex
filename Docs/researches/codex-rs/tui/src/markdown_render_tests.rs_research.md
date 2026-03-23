# markdown_render_tests.rs 研究文档

## 场景与职责

`markdown_render_tests.rs` 是 `markdown_render.rs` 的配套测试文件，位于 `codex-rs/tui/src/markdown_render_tests.rs`（约 1343 行）。它通过 `include!` 宏被嵌入到 `markdown_render.rs` 的测试模块中：

```rust
#[cfg(test)]
mod markdown_render_tests {
    include!("markdown_render_tests.rs");
}
```

该文件包含全面的单元测试，验证 Markdown 渲染引擎在各种场景下的正确性，包括：
- 基本块级元素（段落、标题、引用块、代码块）
- 列表（有序/无序、嵌套、紧凑/松散）
- 行内格式（粗体、斜体、删除线、代码）
- 链接（URL 链接、本地文件链接）
- 复杂嵌套结构
- HTML 内容
- 边界情况

## 功能点目的

### 1. 基础渲染验证

测试基本 Markdown 结构的渲染：
- 空输入处理
- 单段落和多段落
- 软换行和硬换行
- 六级标题（H1-H6）及其样式

### 2. 引用块测试

验证引用块的多种场景：
- 单层和嵌套引用块
- 引用块内的列表
- 引用块内的代码块
- 引用块内的标题
- 多段落引用块

### 3. 列表测试

全面的列表渲染测试：
- 有序和无序列表
- 嵌套列表（最多 5 层）
- 紧凑（tight）和松散（loose）列表项
- 列表项内的多段落
- 自定义起始编号

### 4. 链接测试

重点测试本地文件链接的特殊处理：
- 绝对路径缩短为相对路径
- 行号/列号后缀保留
- 范围后缀（`:start-end`）
- `file://` URL 处理
- 哈希锚点（`#L10`）转换

### 5. 代码块测试

验证代码块渲染：
- 围栏代码块（带语言标识）
- 缩进代码块
- 语法高亮（验证颜色输出）
- 未知语言回退
- CRLF 换行处理

### 6. 流式渲染测试

验证增量/流式渲染的正确性：
- 分块输入的累积渲染
- 不完整的 Markdown 结构处理
- 与完整渲染的一致性

## 具体技术实现

### 测试组织结构

```rust
// 基础测试
#[test]
fn empty() { ... }

// 段落测试
#[test]
fn paragraph_single() { ... }
#[test]
fn paragraph_soft_break() { ... }

// 标题测试
#[test]
fn headings() { ... }

// 引用块测试（约 20 个测试）
#[test]
fn blockquote_single() { ... }
// ...

// 列表测试（约 25 个测试）
#[test]
fn list_unordered_single() { ... }
// ...

// 链接测试（约 15 个测试）
#[test]
fn file_link_hides_destination() { ... }
// ...

// 代码块测试（约 10 个测试）
#[test]
fn code_block_known_lang_has_syntax_colors() { ... }
// ...

// HTML 测试
#[test]
fn html_inline_is_verbatim() { ... }

// 复杂场景测试
#[test]
fn markdown_render_complex_snapshot() { ... }
```

### 辅助函数

```rust
fn render_markdown_text_for_cwd(input: &str, cwd: &Path) -> Text<'static> {
    render_markdown_text_with_width_and_cwd(input, None, Some(cwd))
}
```

提供带工作目录的便捷渲染函数。

### 测试断言模式

1. **精确相等**: 使用 `assert_eq!` 比较完整 `Text` 对象
   ```rust
   assert_eq!(render_markdown_text("Hello, world!"), Text::from("Hello, world!"));
   ```

2. **内容提取**: 提取纯文本内容验证结构
   ```rust
   let lines: Vec<String> = text.lines.iter().map(|l| {
       l.spans.iter().map(|s| s.content.clone()).collect::<String>()
   }).collect();
   ```

3. **样式验证**: 检查特定 span 的颜色
   ```rust
   assert_eq!(marker_span.style.fg, Some(Color::LightBlue));
   ```

4. **快照测试**: 使用 `insta::assert_snapshot!` 验证复杂输出
   ```rust
   assert_snapshot!(rendered);
   ```

### 关键测试用例详解

#### 本地文件链接测试

```rust
#[test]
fn file_link_hides_destination() {
    let text = render_markdown_text_for_cwd(
        "[codex-rs/tui/src/markdown_render.rs](/Users/example/code/codex/codex-rs/tui/src/markdown_render.rs)",
        Path::new("/Users/example/code/codex"),
    );
    // 验证显示相对路径而非完整路径
    let expected = Text::from(Line::from_iter([
        "codex-rs/tui/src/markdown_render.rs".cyan()
    ]));
    assert_eq!(text, expected);
}
```

#### 嵌套列表测试

```rust
#[test]
fn deeply_nested_mixed_three_levels() {
    let md = "1. A\n    - B\n        1. C\n2. D\n";
    let text = render_markdown_text(md);
    let expected = Text::from_iter([
        Line::from_iter(["1. ".light_blue(), "A".into()]),
        Line::from_iter(["    - ", "B"]),
        Line::from_iter(["        1. ".light_blue(), "C".into()]),
        Line::from_iter(["2. ".light_blue(), "D".into()]),
    ]);
    assert_eq!(text, expected);
}
```

#### 复杂快照测试

```rust
#[test]
fn markdown_render_complex_snapshot() {
    let md = r#"# H1: Markdown Streaming Test
Intro paragraph with bold **text**, italic *text*, and inline code `x=1`.
...
"#;
    let text = render_markdown_text(md);
    let rendered = text.lines.iter().map(|l| {
        l.spans.iter().map(|s| s.content.clone()).collect::<String>()
    }).collect::<Vec<_>>().join("\n");
    assert_snapshot!(rendered);
}
```

## 关键代码路径与文件引用

### 被测试代码

| 文件 | 说明 |
|------|------|
| `codex-rs/tui/src/markdown_render.rs` | 主渲染引擎 |

### 测试依赖

| 文件/模块 | 用途 |
|-----------|------|
| `pretty_assertions` | 更好的 diff 输出 |
| `insta` | 快照测试 |
| `ratatui::style::Stylize` | 样式构造 |

### 导入项

```rust
use pretty_assertions::assert_eq;
use ratatui::style::Stylize;
use ratatui::text::Line;
use ratatui::text::Span;
use ratatui::text::Text;
use std::path::Path;

use crate::markdown_render::COLON_LOCATION_SUFFIX_RE;
use crate::markdown_render::HASH_LOCATION_SUFFIX_RE;
use crate::markdown_render::render_markdown_text;
use crate::markdown_render::render_markdown_text_with_width_and_cwd;
```

## 依赖与外部交互

### 与 markdown_render.rs 的关系

测试文件通过 `include!` 成为 `markdown_render.rs` 的一部分，因此：
- 可以直接访问模块私有项
- 共享相同的 crate 导入
- 编译为同一个测试二进制文件

### 测试框架

- **标准测试**: 使用 Rust 内置 `#[test]`
- **断言库**: `pretty_assertions` 提供彩色 diff
- **快照测试**: `insta` crate 用于复杂输出的回归测试

## 风险、边界与改进建议

### 当前风险

1. **测试维护成本**: 样式变更需要更新大量测试
2. **平台差异**: 路径测试在 Windows/Unix 上可能有差异
3. **快照漂移**: 快照测试需要定期审查更新

### 边界情况覆盖

已覆盖的边界情况：
- ✅ 空输入
- ✅ 不完整的 Markdown（流式场景）
- ✅ 特殊字符（Unicode、emoji）
- ✅ CRLF 换行
- ✅ 深层嵌套（5+ 层）
- ✅ 空代码块

### 改进建议

1. **测试组织**:
   - 按功能模块分组使用 `mod` 组织测试
   - 添加更多文档注释说明测试目的

2. **覆盖率**:
   - 添加性能/压力测试（大文档渲染）
   - 添加模糊测试发现边缘情况
   - 测试错误处理路径

3. **可维护性**:
   - 提取更多辅助函数减少重复代码
   - 使用参数化测试（如 `rstest`）减少相似测试

4. **平台兼容性**:
   - 添加 Windows 特定的路径测试
   - 验证不同终端颜色支持

### 测试数据示例

文件中包含的测试 Markdown 样本：

```markdown
# H1: Markdown Streaming Test
Intro paragraph with bold **text**, italic *text*, and inline code `x=1`.
Combined bold-italic ***both*** and escaped asterisks \*literal\*.
Auto-link: <https://example.com> and reference link [ref][r1].
> Blockquote level 1
>> Blockquote level 2 with `inline code`
- Unordered list item 1
  - Nested bullet with italics _inner_
1. Ordered item one
   1) Alt-numbered subitem
---
```json
{ "a": 1, "b": [true, false] }
```
```

---

*文档生成时间: 2026-03-23*
*基于代码版本: codex-rs/tui/src/markdown_render_tests.rs (1343 lines)*
