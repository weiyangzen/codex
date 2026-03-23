# 研究文档：markdown_render_complex_snapshot.snap

## 场景与职责

此文件是 `codex-tui-app-server` crate 中 Markdown 渲染模块的 **insta 快照测试文件**，用于验证复杂 Markdown 文档的渲染输出是否符合预期。该快照捕获了 `markdown_render_tests.rs` 中 `markdown_render_complex_snapshot` 测试用例的完整渲染结果。

**核心职责**：
- 作为回归测试的基准，确保 Markdown 渲染器对各种 Markdown 元素的处理保持一致
- 验证复杂 Markdown 结构（标题、列表、代码块、表格、脚注等）的正确渲染
- 提供可视化的渲染输出参考，便于审查 UI 变更的影响

## 功能点目的

### 测试覆盖的 Markdown 元素

该快照测试覆盖了以下 Markdown 语法元素：

1. **标题（Headings）**：H1-H6 六级标题，验证层级结构和样式
2. **段落与文本格式**：
   - 粗体（`**text**`）
   - 斜体（`*text*`）
   - 行内代码（`` `code` ``）
   - 删除线（`~~text~~`）
   - 粗斜体组合（`***both***`）
   - 转义字符（`\*literal\*`）

3. **链接**：
   - 自动链接（`<https://example.com>`）
   - 引用链接（`[ref][r1]`）
   - 带标题的链接（`[hover me](url "title")`）
   - 邮件链接（`<mailto:test@example.com>`）

4. **图片**：`![alt text](url "title")`（图片仅显示 alt 文本）

5. **块引用（BlockQuote）**：多级嵌套引用，包含行内代码

6. **列表**：
   - 无序列表（`- item`）
   - 有序列表（`1. item`）
   - 嵌套列表（多级缩进）
   - 任务列表（`- [ ]` 和 `- [x]`）

7. **水平分隔线**：`---` 和 `***`

8. **表格**：对齐方式（左对齐、居中、右对齐）

9. **HTML**：行内 HTML（`<sup>`、`<sub>`）和 HTML 块

10. **代码块**：
    - 围栏代码块（带语言标识 JSON）
    - 波浪号围栏代码块
    - 缩进代码块

11. **脚注**：引用和定义

12. **定义列表**：术语和定义

13. **字符实体**：`&amp;`、`&lt;` 等

14. **硬换行**：行尾双空格

### 渲染特性验证

- **纯文本提取**：测试将渲染后的 `Text` 对象转换为纯文本行，忽略样式信息
- **结构保持**：验证 Markdown 结构（段落分隔、列表缩进、代码块边界）正确保留
- **特殊字符处理**：验证转义和实体解码正确

## 具体技术实现

### 快照生成流程

```rust
// 测试代码位置：codex-rs/tui_app_server/src/markdown_render_tests.rs:1105-1173
#[test]
fn markdown_render_complex_snapshot() {
    let md = r#"# H1: Markdown Streaming Test
    // ... 复杂 Markdown 内容
    "#;

    let text = render_markdown_text(md);
    // 将 Text 对象转换为纯文本行（忽略样式）
    let rendered = text
        .lines
        .iter()
        .map(|l| {
            l.spans
                .iter()
                .map(|s| s.content.clone())
                .collect::<String>()
        })
        .collect::<Vec<_>>()
        .join("\n");

    assert_snapshot!(rendered);  // 使用 insta 生成/比对快照
}
```

### 关键数据结构

**`Text<'static>`**：ratatui 的文本类型，包含多行 `Line`

**`Line`**：一行文本，由多个 `Span` 组成

**`Span`**：具有相同样式的文本片段，包含：
- `content: String` - 文本内容
- `style: Style` - 样式信息（颜色、加粗、斜体等）

### 渲染器核心实现

渲染逻辑位于 `codex-rs/tui_app_server/src/markdown_render.rs`：

1. **解析阶段**：使用 `pulldown-cmark` 库解析 Markdown
   ```rust
   let mut options = Options::empty();
   options.insert(Options::ENABLE_STRIKETHROUGH);
   let parser = Parser::new_ext(input, options);
   ```

2. **渲染阶段**：`Writer` 结构体遍历解析事件，构建 `Text` 对象
   - 处理 `Event::Start(Tag)` / `Event::End(TagEnd)` 管理嵌套结构
   - 处理 `Event::Text` / `Event::Code` 输出文本内容
   - 维护缩进栈 (`indent_stack`) 处理嵌套列表和引用

3. **样式应用**：`MarkdownStyles` 定义各元素的默认样式
   - H1: 粗体 + 下划线
   - H2: 粗体
   - H3: 粗体 + 斜体
   - H4-H6: 斜体
   - 代码: 青色 (cyan)
   - 引用: 绿色 (green)
   - 有序列表标记: 浅蓝色

## 关键代码路径与文件引用

### 主要文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/markdown_render.rs` | Markdown 渲染器主实现，包含 `Writer` 结构体和渲染逻辑 |
| `codex-rs/tui_app_server/src/markdown_render_tests.rs` | 测试用例，包含 `markdown_render_complex_snapshot` 测试 |
| `codex-rs/tui_app_server/src/snapshots/codex_tui_app_server__markdown_render__markdown_render_tests__markdown_render_complex_snapshot.snap` | 本快照文件 |

### 依赖文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/wrapping.rs` | 文本自动换行实现 (`adaptive_wrap_line`) |
| `codex-rs/tui_app_server/src/render/highlight.rs` | 代码语法高亮 |
| `codex-rs/tui_app_server/src/render/line_utils.rs` | 行工具函数 |
| `codex-rs/utils/string/src/lib.rs` | 字符串工具，包含位置后缀规范化 |

### 外部依赖

- **`pulldown-cmark`**：Markdown 解析器
- **`ratatui`**：TUI 框架，提供 `Text`/`Line`/`Span`/`Style` 类型
- **`insta`**：快照测试框架
- **`syntect`**：代码语法高亮（通过 `highlight.rs` 间接使用）

## 依赖与外部交互

### 测试执行流程

```
cargo test -p codex-tui-app-server markdown_render_complex_snapshot
    │
    ▼
调用 render_markdown_text(md) 
    │
    ▼
pulldown-cmark 解析 Markdown → Event 流
    │
    ▼
Writer::handle_event() 处理每个事件
    │
    ▼
构建 Text<'static> 对象
    │
    ▼
提取纯文本行 → 与快照比对
```

### 与 tui crate 的关系

`tui_app_server` 的 Markdown 渲染器是 `codex-rs/tui/src/markdown_render.rs` 的**并行实现**。根据 AGENTS.md 中的约定：

> "When a change lands in `codex-rs/tui` and `codex-rs/tui_app_server` has a parallel implementation of the same behavior, reflect the change in `codex-rs/tui_app_server` too"

两个文件内容高度一致，确保 TUI 和 App Server 的渲染行为统一。

## 风险、边界与改进建议

### 当前风险

1. **快照漂移**：任何渲染逻辑变更都会导致快照失败，需要人工审查确认
2. **双维护成本**：tui 和 tui_app_server 两个 crate 维护几乎相同的代码
3. **样式信息丢失**：快照仅捕获纯文本内容，不验证样式（颜色、加粗等）是否正确应用

### 边界情况

1. **图片渲染**：图片仅显示 alt 文本，不实际渲染图片内容
2. **表格渲染**：表格以纯文本形式渲染，不保留列对齐的视觉表现
3. **脚注位置**：脚注定义按原文顺序追加，不重新排序
4. **HTML 内容**：HTML 标签原样输出，不做解析或样式化

### 改进建议

1. **样式快照**：考虑增加样式感知测试，验证关键元素的样式应用
   ```rust
   // 示例：验证 H1 有下划线样式
   assert!(text.lines[0].spans.iter().any(|s| s.style.add_modifier(UNDERLINED)));
   ```

2. **合并实现**：考虑将渲染逻辑抽取到共享 crate，避免双维护

3. **细分快照**：将复杂测试拆分为多个小快照，便于定位问题
   - `heading_snapshot`
   - `list_snapshot`
   - `code_block_snapshot`

4. **文档化预期**：在快照文件中添加注释说明每个 Markdown 元素的预期渲染行为

5. **自动化审查**：CI 中增加快照变更的自动通知，确保 UI 变更有意识

### 相关测试命令

```bash
# 运行特定测试
cargo test -p codex-tui-app-server markdown_render_complex_snapshot

# 查看待接受快照
cargo insta pending-snapshots -p codex-tui-app-server

# 接受快照更新
cargo insta accept -p codex-tui-app-server
```
