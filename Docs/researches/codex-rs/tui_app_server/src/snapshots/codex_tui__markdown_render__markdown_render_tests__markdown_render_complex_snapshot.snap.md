# Markdown 复杂渲染测试

## 场景与职责

该快照测试验证 `markdown_render` 模块对复杂 Markdown 文档的渲染能力。Codex TUI 需要正确渲染 AI 返回的 Markdown 格式响应，包括：

1. 标题层级（H1-H6）
2. 文本样式（粗体、斜体、删除线）
3. 代码（行内代码、代码块）
4. 列表（有序、无序、嵌套、任务列表）
5. 链接（自动链接、引用链接、带标题链接）
6. 引用块（多级嵌套）
7. 表格
8. HTML 内容
9. 水平分割线
10. 脚注

这是 TUI 中最复杂的渲染功能之一，直接影响 AI 响应的可读性。

## 功能点目的

### 支持的 Markdown 特性
| 特性 | 示例 | 渲染效果 |
|-----|------|---------|
| 标题 | `# H1` | `# H1`（粗体+下划线） |
| 粗体 | `**text**` | `text`（粗体） |
| 斜体 | `*text*` | `text`（斜体） |
| 代码 | `` `code` `` | `code`（青色） |
| 链接 | `[text](url)` | `text (url)`（URL青色+下划线） |
| 引用 | `> quote` | `> quote`（绿色） |
| 列表 | `- item` | `- item` |
| 代码块 | ` ```json ` | 语法高亮 |

### 测试文档结构
测试文档包含 50+ 个 Markdown 元素，覆盖：
- 6 级标题
- 多种文本样式组合
- 嵌套引用块
- 多级列表（有序/无序混合）
- 任务列表
- 表格
- 多种代码块
- HTML 标签
- 特殊字符转义
- 脚注

## 具体技术实现

### 渲染入口
```rust
// markdown_render.rs:89-115
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

### Writer 结构
```rust
// markdown_render.rs:147-173
struct Writer<'a, I> {
    iter: I,                          // pulldown-cmark 解析器
    text: Text<'static>,              // 输出文本
    styles: MarkdownStyles,           // 样式配置
    inline_styles: Vec<Style>,        // 内联样式栈
    indent_stack: Vec<IndentContext>, // 缩进上下文栈
    list_indices: Vec<Option<u64>>,   // 列表索引栈
    link: Option<LinkState>,          // 当前链接状态
    // ... 其他字段
}
```

### 样式定义
```rust
// markdown_render.rs:32-70
struct MarkdownStyles {
    h1: Style,                    // 粗体+下划线
    h2: Style,                    // 粗体
    h3: Style,                    // 粗体+斜体
    h4: Style,                    // 斜体
    h5: Style,                    // 斜体
    h6: Style,                    // 斜体
    code: Style,                  // 青色
    emphasis: Style,              // 斜体
    strong: Style,                // 粗体
    strikethrough: Style,         // 删除线
    ordered_list_marker: Style,   // 浅蓝色
    unordered_list_marker: Style, // 默认
    link: Style,                  // 青色+下划线
    blockquote: Style,            // 绿色
}
```

### 关键渲染逻辑

1. **标题渲染**（第326-348行）：
   ```rust
   fn start_heading(&mut self, level: HeadingLevel) {
       let heading_style = match level {
           HeadingLevel::H1 => self.styles.h1,  // 粗体+下划线
           HeadingLevel::H2 => self.styles.h2,  // 粗体
           // ... H3-H6
       };
       let content = format!("{} ", "#".repeat(level as usize));
       self.push_line(Line::from(vec![Span::styled(content, heading_style)]));
       self.push_inline_style(heading_style);
   }
   ```

2. **代码块渲染**（第526-571行）：
   ```rust
   fn start_codeblock(&mut self, lang: Option<String>, indent: Option<Span<'static>>) {
       // 提取语言标记
       let lang = lang
           .as_deref()
           .and_then(|s| s.split([',', ' ', '\t']).next())
           .filter(|s| !s.is_empty())
           .map(std::string::ToString::to_string);
       self.code_block_lang = lang;
   }
   
   fn end_codeblock(&mut self) {
       if let Some(lang) = self.code_block_lang.take() {
           let code = std::mem::take(&mut self.code_block_buffer);
           let highlighted = highlight_code_to_lines(&code, &lang);
           // ...
       }
   }
   ```

3. **链接处理**（第583-618行）：
   ```rust
   fn push_link(&mut self, dest_url: String) {
       let show_destination = should_render_link_destination(&dest_url);
       self.link = Some(LinkState {
           show_destination,
           local_target_display: if is_local_path_like_link(&dest_url) {
               render_local_link_target(&dest_url, self.cwd.as_deref())
           } else {
               None
           },
           destination: dest_url,
       });
   }
   ```

## 关键代码路径与文件引用

### 主要文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/markdown_render.rs` | Markdown 渲染核心实现 |
| `codex-rs/tui/src/markdown_render_tests.rs` | 测试用例 |
| `codex-rs/tui/src/render/highlight.rs` | 语法高亮 |

### 关键函数
| 函数 | 位置 | 描述 |
|-----|------|------|
| `render_markdown_text` | `markdown_render.rs:89` | 主入口 |
| `Writer::run` | `markdown_render.rs:206-211` | 事件循环 |
| `Writer::handle_event` | `markdown_render.rs:213-235` | 事件处理 |
| `start_heading` | `markdown_render.rs:326` | 标题开始 |
| `end_codeblock` | `markdown_render.rs:553` | 代码块结束 |

### 测试代码
- 位置：`markdown_render_tests.rs:1105-1170`
- 函数：`markdown_render_complex_snapshot`

## 依赖与外部交互

### 外部依赖
```rust
use pulldown_cmark::Parser;        // Markdown 解析
use syntect::parsing::SyntaxSet;   // 语法高亮（间接）
use ratatui::text::{Line, Span, Text}; // TUI 文本
```

### 语法高亮
```rust
// render/highlight.rs
pub fn highlight_code_to_lines(code: &str, lang: &str) -> Vec<Line<'static>> {
    // 使用 syntect 进行语法高亮
}
```

### pulldown-cmark 配置
```rust
let mut options = Options::empty();
options.insert(Options::ENABLE_STRIKETHROUGH); // 启用删除线
```

## 风险、边界与改进建议

### 已知限制

1. **表格渲染**
   - 当前将表格渲染为纯文本
   - 不保留列对齐
   - 建议：添加表格边框和对齐支持

2. **图片渲染**
   - 终端中无法直接显示图片
   - 当前仅显示 alt 文本
   - 建议：添加图片链接或可点击打开

3. **HTML 支持**
   - 有限的 HTML 标签支持
   - 复杂 HTML 可能渲染异常

4. **脚注**
   - 脚注引用显示为纯文本
   - 脚注内容显示在文档末尾
   - 建议：添加脚注跳转支持

### 边界情况

| 场景 | 行为 | 风险 |
|-----|------|------|
| 嵌套引用 | 支持多级 | 低 |
| 代码块内特殊字符 | 原样输出 | 低 |
| 超长行 | 不换行（除非指定宽度） | 中 |
| 空文档 | 返回空 Text | 低 |

### 改进建议

1. **表格美化**
   ```rust
   // 当前: | Left | Center | Right |
   // 建议: ┌──────┬────────┬───────┐
   //       │ Left │ Center │ Right │
   //       └──────┴────────┴───────┘
   ```

2. **图片占位符**
   ```rust
   // 当前: "alt text"
   // 建议: "[🖼️ Image: alt text]"
   ```

3. **链接点击支持**
   - 使用终端超链接转义序列（OSC 8）
   - 允许用户点击链接在浏览器中打开

4. **代码块复制**
   - 添加代码块标识符
   - 支持复制代码块内容

5. **Emoji 支持**
   ```rust
   // 支持 GitHub 风格的 emoji shortcodes
   // :sparkles: → ✨
   ```

### 相关测试
| 测试名称 | 描述 |
|---------|------|
| `markdown_render_file_link_snapshot` | 文件链接渲染 |
| `headings` | 标题样式 |
| `blockquote_nested_two_levels` | 嵌套引用 |
| `code_block_known_lang_has_syntax_colors` | 语法高亮 |

### 性能考虑
- 大文档解析可能较慢
- 建议：对流式响应进行增量渲染
- 避免一次性解析超大 Markdown 文档
