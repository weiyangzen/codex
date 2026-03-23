# markdown_render_tests.rs 研究文档

## 场景与职责

`markdown_render_tests.rs` 是 `markdown_render.rs` 的配套测试文件，通过 Rust 的 `include!` 宏被嵌入到主模块中（位于 `markdown_render.rs` 末尾的 `#[cfg(test)]` 模块内）。该测试文件负责验证 Markdown 渲染器的各项功能，确保渲染输出符合预期。

### 核心职责
1. **功能回归测试**：验证各种 Markdown 元素的渲染行为
2. **边界情况验证**：测试空输入、嵌套结构、特殊字符等边界情况
3. **样式验证**：确保正确的样式（颜色、粗体、斜体等）被应用到渲染输出
4. **本地文件链接测试**：验证路径简化、位置后缀处理等特殊功能
5. **文本换行测试**：验证宽度限制下的正确换行行为
6. **快照测试**：使用 `insta` 进行复杂输出的快照比对

---

## 功能点目的

### 1. 基础渲染测试
验证最基本的 Markdown 元素渲染：
- 空输入处理
- 单行/多行段落
- 软换行（单个 `\n`）vs 硬段落分隔（`\n\n`）

### 2. 标题测试
- H1-H6 六级标题的渲染
- 标题样式验证（粗体、斜体、下划线组合）

### 3. 引用块测试
- 单行/多行引用块
- 软换行在引用块中的处理
- 多级嵌套引用
- 引用块与列表的组合
- 引用块与标题、代码块的组合

### 4. 列表测试
- 无序列表（`-`）
- 有序列表（`1.`）及自定义起始编号
- 嵌套列表（混合有序/无序）
- 紧凑列表 vs 松散列表
- 列表项内的引用块
- 深层嵌套（5级+）

### 5. 行内样式测试
- 行内代码（`` `code` ``）
- 粗体（`**text**`）
- 斜体（`*text*`）
- 删除线（`~~text~~`）
- 组合样式（粗体+斜体）

### 6. 链接测试
- 普通 URL 链接（显示标签+目标）
- 本地文件链接（特殊处理：显示简化路径）
- 文件链接的位置后缀（`:line`, `:line:col`, 范围）
- `file://` URL 的哈希锚点（`#L10C5`）
- 多行标签的本地文件链接

### 7. 代码块测试
- 围栏代码块（带语言标识）
- 缩进代码块
- 语法高亮验证
- 未知语言回退
- 无语言标识代码块
- CRLF 行尾处理
- 嵌套代码块（围栏内包含围栏）
- 代码块内的空行保留

### 8. 文本换行测试
- 纯文本换行
- 列表项换行（保持缩进）
- 嵌套列表换行
- 有序列表换行
- 引用块换行
- 代码块不换行（保护复制粘贴）
- URL 类 token 不被截断

### 9. HTML 内容测试
- 行内 HTML 原样渲染
- HTML 块原样渲染
- HTML 在列表项中的处理

### 10. 水平线测试
- 水平线渲染为 em-dash 字符

### 11. 快照测试
- 复杂 Markdown 文档的完整渲染快照
- 文件链接渲染快照

---

## 具体技术实现

### 测试组织结构

```rust
// 测试辅助函数
fn render_markdown_text_for_cwd(input: &str, cwd: &Path) -> Text<'static> {
    render_markdown_text_with_width_and_cwd(input, None, Some(cwd))
}

// 基础测试
#[test]
fn empty() { ... }

#[test]
fn paragraph_single() { ... }

// 按功能分组的测试...
```

### 测试断言模式

#### 1. 精确相等断言（使用 `pretty_assertions`）
```rust
#[test]
fn paragraph_single() {
    assert_eq!(
        render_markdown_text("Hello, world!"),
        Text::from("Hello, world!")
    );
}
```

#### 2. 行内容提取验证
```rust
let lines: Vec<String> = text
    .lines
    .iter()
    .map(|l| {
        l.spans
            .iter()
            .map(|s| s.content.clone())
            .collect::<String>()
    })
    .collect();
assert_eq!(lines, vec!["expected line 1", "expected line 2"]);
```

#### 3. 样式验证
```rust
#[test]
fn headings() {
    let text = render_markdown_text(md);
    let expected = Text::from_iter([
        Line::from_iter(["# ".bold().underlined(), "Heading 1".bold().underlined()]),
        // ...
    ]);
    assert_eq!(text, expected);
}
```

#### 4. 快照测试（使用 `insta`）
```rust
#[test]
fn markdown_render_complex_snapshot() {
    let md = r#"...复杂 Markdown..."#;
    let text = render_markdown_text(md);
    let rendered = text
        .lines
        .iter()
        .map(|l| /* 提取内容 */)
        .collect::<Vec<_>>()
        .join("\n");
    assert_snapshot!(rendered);
}
```

### 关键测试用例详解

#### 本地文件链接测试组
```rust
#[test]
fn file_link_hides_destination() {
    let text = render_markdown_text_for_cwd(
        "[codex-rs/tui/src/markdown_render.rs](/Users/example/code/codex/codex-rs/tui/src/markdown_render.rs)",
        Path::new("/Users/example/code/codex"),
    );
    // 验证：显示相对于 cwd 的路径，而非完整绝对路径
    let expected = Text::from(Line::from_iter(["codex-rs/tui/src/markdown_render.rs".cyan()]));
    assert_eq!(text, expected);
}

#[test]
fn file_link_appends_line_number_when_label_lacks_it() {
    let text = render_markdown_text_for_cwd(
        "[markdown_render.rs](/Users/example/code/codex/codex-rs/tui/src/markdown_render.rs:74)",
        Path::new("/Users/example/code/codex"),
    );
    // 验证：保留位置后缀 :74
    let expected = Text::from(Line::from_iter(["codex-rs/tui/src/markdown_render.rs:74".cyan()]));
    assert_eq!(text, expected);
}

#[test]
fn file_link_keeps_absolute_paths_outside_cwd() {
    let text = render_markdown_text_for_cwd(
        "[README.md:74](/Users/example/code/codex/README.md:74)",
        Path::new("/Users/example/code/codex/codex-rs/tui"),
    );
    // 验证：路径不在 cwd 下时，保留完整绝对路径
    let expected = Text::from(Line::from_iter(["/Users/example/code/codex/README.md:74".cyan()]));
    assert_eq!(text, expected);
}
```

#### 列表项内本地链接软换行测试
```rust
#[test]
fn unordered_list_local_file_link_stays_inline_with_following_text() {
    let text = render_markdown_text_with_width_and_cwd(
        "- [binary](/Users/example/code/codex/codex-rs/README.md:93): core is the agent/business logic...",
        Some(72),
        Some(Path::new("/Users/example/code/codex")),
    );
    // 验证：链接后的冒号和描述文本保持在同一行
    assert_eq!(
        rendered,
        vec![
            "- codex-rs/README.md:93: core is the agent/business logic, tui is the",
            "  terminal UI, exec is the headless automation surface, and cli is the",
            "  top-level multitool binary.",
        ]
    );
}

#[test]
fn unordered_list_local_file_link_soft_break_before_colon_stays_inline() {
    let text = render_markdown_text_with_width_and_cwd(
        "- [binary](/Users/example/code/codex/codex-rs/README.md:93)\n  : core is the agent/business logic.",
        Some(72),
        Some(Path::new("/Users/example/code/codex")),
    );
    // 验证：Markdown 软换行在冒号前时，仍保持内联渲染
    assert_eq!(
        rendered,
        vec!["- codex-rs/README.md:93: core is the agent/business logic."]
    );
}
```

#### 语法高亮测试
```rust
#[test]
fn code_block_known_lang_has_syntax_colors() {
    let text = render_markdown_text("```rust\nfn main() {}\n```\n");
    // 验证内容保留
    assert!(content.iter().any(|c| c == "fn main() {}"));
    // 验证有颜色样式（非默认样式）
    let has_colored_span = text
        .lines
        .iter()
        .flat_map(|l| l.spans.iter())
        .any(|sp| sp.style.fg.is_some());
    assert!(has_colored_span, "expected syntax-highlighted spans with color");
}

#[test]
fn code_block_unknown_lang_plain() {
    let text = render_markdown_text("```xyzlang\nhello world\n```\n");
    // 验证无语法高亮（所有 span 都是默认样式）
    let has_colored_span = text
        .lines
        .iter()
        .flat_map(|l| l.spans.iter())
        .any(|sp| sp.style.fg.is_some());
    assert!(!has_colored_span, "expected no syntax coloring for unknown lang");
}
```

#### 文本换行测试
```rust
#[test]
fn wraps_plain_text_when_width_provided() {
    let markdown = "This is a simple sentence that should wrap.";
    let rendered = render_markdown_text_with_width(markdown, Some(16));
    let lines = lines_to_strings(&rendered);
    assert_eq!(
        lines,
        vec![
            "This is a simple".to_string(),
            "sentence that".to_string(),
            "should wrap.".to_string(),
        ]
    );
}

#[test]
fn does_not_wrap_code_blocks() {
    let markdown = "````\nfn main() { println!(\"hi from a long line\"); }\n````";
    let rendered = render_markdown_text_with_width(markdown, Some(10));
    let lines = lines_to_strings(&rendered);
    // 代码块保持原样，不换行
    assert_eq!(
        lines,
        vec!["fn main() { println!(\"hi from a long line\"); }".to_string(),]
    );
}
```

#### 引用块复杂交互测试
```rust
#[test]
fn blockquote_list_then_nested_blockquote() {
    let md = "> - parent\n>   > child\n";
    let text = render_markdown_text(md);
    let expected = Text::from_iter([
        Line::from_iter(["> ", "- ", "parent"]).green(),
        Line::from_iter(["> ", "  ", "> ", "child"]).green(),
    ]);
    assert_eq!(text, expected);
}
```

### 快照测试文件

测试生成两个快照文件：

1. **`markdown_render_complex_snapshot.snap`**
   - 测试复杂 Markdown 文档的完整渲染
   - 包含：标题、段落、各种样式、列表、引用块、代码块、HTML、表格语法等
   - 用于捕获整体渲染行为的回归

2. **`markdown_render_file_link_snapshot.snap`**
   - 测试文件链接的渲染输出
   - 验证路径简化和位置后缀的正确显示

---

## 关键代码路径与文件引用

### 测试文件结构
```
codex-rs/tui_app_server/src/
├── markdown_render.rs              # 主模块，包含 #[cfg(test)] mod markdown_render_tests
├── markdown_render_tests.rs        # 本测试文件（被 include! 嵌入）
└── snapshots/
    ├── codex_tui_app_server__markdown_render__markdown_render_tests__markdown_render_complex_snapshot.snap
    └── codex_tui_app_server__markdown_render__markdown_render_tests__markdown_render_file_link_snapshot.snap
```

### 被测试的函数
| 函数 | 测试覆盖 |
|------|----------|
| `render_markdown_text` | 大多数测试用例 |
| `render_markdown_text_with_width` | 换行相关测试 |
| `render_markdown_text_with_width_and_cwd` | 本地文件链接测试 |

### 导入的测试依赖
```rust
use pretty_assertions::assert_eq;  // 更好的 diff 输出
use ratatui::style::Stylize;       // 样式构造（.bold(), .cyan() 等）
use ratatui::text::Line;
use ratatui::text::Span;
use ratatui::text::Text;
use std::path::Path;
use crate::markdown_render::COLON_LOCATION_SUFFIX_RE;      // 正则导出（测试用）
use crate::markdown_render::HASH_LOCATION_SUFFIX_RE;       // 正则导出（测试用）
use crate::markdown_render::render_markdown_text;
use crate::markdown_render::render_markdown_text_with_width_and_cwd;
use insta::assert_snapshot;  // 快照测试
```

---

## 依赖与外部交互

### 测试框架
- **内置测试框架**：使用 Rust 内置 `#[test]` 属性
- **断言库**：`pretty_assertions` 提供彩色 diff
- **快照测试**：`insta` crate 用于复杂输出的快照比对

### 被测试模块
测试通过 `include!("markdown_render_tests.rs")` 嵌入到 `markdown_render.rs` 中，因此：
- 可以直接访问 `markdown_render` 模块的私有项
- 可以测试非公开函数（如正则表达式的静态初始化）

### 外部依赖
| Crate | 测试中的用途 |
|-------|-------------|
| `ratatui` | 构造期望的 `Text`, `Line`, `Span` 输出 |
| `insta` | 快照测试断言 |
| `pretty_assertions` | 更好的测试失败输出 |

---

## 风险、边界与改进建议

### 测试覆盖分析

#### 充分覆盖的区域
1. ✅ 基础 Markdown 元素（段落、标题、列表、引用块）
2. ✅ 行内样式（粗体、斜体、代码、删除线）
3. ✅ 本地文件链接的特殊处理（路径简化、位置后缀）
4. ✅ 代码块语法高亮（已知语言、未知语言、无语言）
5. ✅ 文本换行（各种上下文中的换行行为）
6. ✅ 嵌套结构（多级列表、引用块嵌套）

#### 覆盖不足的区域
1. ⚠️ 表格：被忽略，无专门测试
2. ⚠️ 图片：仅测试 alt 文本渲染，无特殊处理测试
3. ⚠️ 脚注：被忽略，无测试
4. ⚠️ 任务列表：仅测试内容渲染，无复选框特殊处理
5. ⚠️ 极端输入：超长行、极端嵌套深度、特殊 Unicode

### 已知测试模式

#### 1. 正则表达式懒加载测试
```rust
#[test]
fn load_location_suffix_regexes() {
    let _colon = &*COLON_LOCATION_SUFFIX_RE;
    let _hash = &*HASH_LOCATION_SUFFIX_RE;
}
```
此测试确保正则表达式能正确编译（虽然它们在 `LazyLock` 中已验证）。

#### 2. 行内容提取模式
多个测试使用以下模式提取行内容：
```rust
let lines: Vec<String> = text
    .lines
    .iter()
    .map(|l| l.spans.iter().map(|s| s.content.clone()).collect::<String>())
    .collect();
```
这可以提取纯文本内容，忽略样式信息。

### 潜在风险

1. **样式测试的脆弱性**
   - 样式测试直接比较 `Text` 对象，如果 `ratatui` 的 `Style` 实现变化，测试会失败
   - 缓解：样式变更通常是故意的，需要更新测试

2. **快照测试的维护成本**
   - 复杂快照可能需要频繁更新
   - 缓解：使用 `cargo insta review` 仔细审查变更

3. **路径测试的平台依赖**
   - 本地文件链接测试使用 Unix 风格路径
   - 在 Windows 上可能需要调整

4. **正则测试的局限性**
   - `load_location_suffix_regexes` 仅验证编译，不验证匹配行为
   - 正则匹配逻辑通过集成测试间接验证

### 改进建议

1. **增加负面测试**
   - 测试无效 Markdown 的处理
   - 测试畸形链接的降级行为
   - 测试极端输入（空字符串、仅空白、超长行）

2. **平台兼容性测试**
   - 添加 Windows 路径格式的测试
   - 测试 UNC 路径 (`\\server\share`)

3. **性能测试**
   - 大文档渲染性能基准
   - 内存使用验证

4. **模糊测试**
   - 使用 `cargo-fuzz` 测试解析器的鲁棒性
   - 防止畸形输入导致的 panic

5. **测试组织优化**
   - 将相关测试分组到模块中
   - 使用 `rstest` 或类似工具进行参数化测试
   - 提取更多测试辅助函数减少重复代码

6. **快照测试增强**
   - 添加更多场景的快照（表格、图片、复杂嵌套）
   - 考虑使用内联快照便于审查

### 维护注意事项

1. **更新快照**：当渲染输出有意变更时，运行：
   ```bash
   cargo insta accept -p codex-tui-app-server
   ```

2. **添加新测试**：遵循现有模式：
   - 使用 `render_markdown_text` 进行基础测试
   - 使用 `render_markdown_text_for_cwd` 测试文件链接
   - 使用 `render_markdown_text_with_width_and_cwd` 测试换行

3. **样式变更**：如果修改 `MarkdownStyles`，需要更新所有依赖特定样式的测试
