# markdown_render.rs 研究文档

## 场景与职责

`markdown_render.rs` 是 Codex TUI 应用服务器的核心 Markdown 渲染模块，负责将 Markdown 文本转换为 `ratatui` 终端 UI 框架可渲染的 `Text<'static>` 对象。该模块是 TUI 转录本（transcript）渲染的基础组件，用于呈现 AI 助手的回复、代码块、文件链接等内容。

### 核心职责
1. **Markdown 解析与渲染**：使用 `pulldown-cmark` 库解析 Markdown，转换为带样式的终端文本
2. **本地文件链接特殊处理**：智能识别并渲染本地文件路径链接，支持路径简化和位置后缀（行号/列号）
3. **语法高亮集成**：通过 `highlight.rs` 为代码块提供语法高亮
4. **文本自动换行**：集成 `wrapping.rs` 的 URL 感知换行功能
5. **跨平台路径处理**：支持 Unix/Windows 路径格式、UNC 路径、`file://` URL 等

---

## 功能点目的

### 1. Markdown 基础渲染
| 功能 | 目的 |
|------|------|
| 标题 (H1-H6) | 区分不同层级标题，使用不同样式（粗体、斜体、下划线） |
| 段落 | 基本文本渲染，支持软换行和硬换行 |
| 代码块 | 支持围栏代码块和缩进代码块，集成语法高亮 |
| 行内代码 | 使用青色样式突出显示 |
| 列表 | 支持有序/无序列表，正确处理嵌套和缩进 |
| 引用块 | 绿色样式，支持多级嵌套 |
| 链接 | 区分网络链接和本地文件链接，不同渲染策略 |
| 强调/粗体/删除线 | 文本样式增强 |
| 水平线 | 使用 em-dash 字符渲染分隔线 |

### 2. 本地文件链接特殊处理
这是该模块最具特色的功能：
- **显示目标而非标签**：对于本地文件链接，显示实际路径而非 Markdown 标签文本
- **路径简化**：相对于当前工作目录缩短绝对路径
- **位置后缀支持**：识别并渲染 `#L10C5` 或 `:10:5` 格式的行号/列号
- **格式统一**：将 `#L..C..` 格式统一转换为 `:line:col` 格式

### 3. 语法高亮
- 通过 `highlight_code_to_lines` 调用 `render/highlight.rs`
- 支持 250+ 种语言的语法高亮
- 自动识别代码块语言标识（处理 `rust,no_run` 等复合 info 字符串）

### 4. 文本换行
- 集成 `wrapping.rs` 的 `adaptive_wrap_line` 功能
- 代码块保持原样（不换行），便于复制粘贴
- 支持首行缩进和后续行缩进的不同配置

---

## 具体技术实现

### 关键数据结构

```rust
// 样式配置结构体
struct MarkdownStyles {
    h1: Style,          // 粗体+下划线
    h2: Style,          // 粗体
    h3: Style,          // 粗体+斜体
    h4: Style,          // 斜体
    h5: Style,          // 斜体
    h6: Style,          // 斜体
    code: Style,        // 青色
    emphasis: Style,    // 斜体
    strong: Style,      // 粗体
    strikethrough: Style, // 删除线
    ordered_list_marker: Style,   // 浅蓝色
    unordered_list_marker: Style, // 默认
    link: Style,        // 青色+下划线
    blockquote: Style,  // 绿色
}

// 缩进上下文（用于列表和引用块嵌套）
struct IndentContext {
    prefix: Vec<Span<'static>>,   // 行前缀（如 "> " 或 "    "）
    marker: Option<Vec<Span<'static>>>, // 列表标记（如 "- " 或 "1. "）
    is_list: bool,               // 是否为列表上下文
}

// 链接状态
struct LinkState {
    destination: String,           // 链接目标 URL
    show_destination: bool,        // 是否显示目标（网络链接显示，本地链接隐藏）
    local_target_display: Option<String>, // 本地链接的预渲染显示文本
}

// Writer 结构体 - 核心渲染状态机
struct Writer<'a, I> where I: Iterator<Item = Event<'a>> {
    iter: I,                              // pulldown-cmark 事件迭代器
    text: Text<'static>,                  // 输出文本
    styles: MarkdownStyles,               // 样式配置
    inline_styles: Vec<Style>,            // 内联样式栈
    indent_stack: Vec<IndentContext>,     // 缩进上下文栈
    list_indices: Vec<Option<u64>>,       // 有序列表当前索引栈
    link: Option<LinkState>,              // 当前链接状态
    needs_newline: bool,                  // 是否需要换行
    pending_marker_line: bool,            // 是否有待处理的标记行
    in_paragraph: bool,                   // 是否在段落中
    in_code_block: bool,                  // 是否在代码块中
    code_block_lang: Option<String>,      // 代码块语言
    code_block_buffer: String,            // 代码块内容缓冲区
    wrap_width: Option<usize>,            // 换行宽度
    cwd: Option<PathBuf>,                 // 当前工作目录
    line_ends_with_local_link_target: bool, // 当前行是否以本地链接结尾
    pending_local_link_soft_break: bool,  // 待处理的本地链接软换行
    current_line_content: Option<Line<'static>>, // 当前行内容
    current_initial_indent: Vec<Span<'static>>,  // 当前首行缩进
    current_subsequent_indent: Vec<Span<'static>>, // 当前后续行缩进
    current_line_style: Style,            // 当前行样式
    current_line_in_code_block: bool,     // 当前行是否在代码块中
}
```

### 关键流程

#### 1. 主渲染流程
```rust
pub fn render_markdown_text(input: &str) -> Text<'static> {
    render_markdown_text_with_width(input, /*width*/ None)
}

pub(crate) fn render_markdown_text_with_width(input: &str, width: Option<usize>) -> Text<'static> {
    let cwd = std::env::current_dir().ok();
    render_markdown_text_with_width_and_cwd(input, width, cwd.as_deref())
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

#### 2. 事件处理循环
```rust
fn run(&mut self) {
    while let Some(ev) = self.iter.next() {
        self.handle_event(ev);
    }
    self.flush_current_line();
}

fn handle_event(&mut self, event: Event<'a>) {
    self.prepare_for_event(&event);
    match event {
        Event::Start(tag) => self.start_tag(tag),
        Event::End(tag) => self.end_tag(tag),
        Event::Text(text) => self.text(text),
        Event::Code(code) => self.code(code),
        Event::SoftBreak => self.soft_break(),
        Event::HardBreak => self.hard_break(),
        Event::Rule => { /* 渲染水平线 */ },
        Event::Html(html) => self.html(html, /*inline*/ false),
        Event::InlineHtml(html) => self.html(html, /*inline*/ true),
        Event::FootnoteReference(_) => {},
        Event::TaskListMarker(_) => {},
    }
}
```

#### 3. 本地文件链接处理流程
```rust
fn is_local_path_like_link(dest_url: &str) -> bool {
    dest_url.starts_with("file://")
        || dest_url.starts_with('/')
        || dest_url.starts_with("~/")
        || dest_url.starts_with("./")
        || dest_url.starts_with("../")
        || dest_url.starts_with("\\\\")
        || matches!(
            dest_url.as_bytes(),
            [drive, b':', separator, ..]
                if drive.is_ascii_alphabetic() && matches!(separator, b'/' | b'\\')
        )
}

fn render_local_link_target(dest_url: &str, cwd: Option<&Path>) -> Option<String> {
    let (path_text, location_suffix) = parse_local_link_target(dest_url)?;
    let mut rendered = display_local_link_path(&path_text, cwd);
    if let Some(location_suffix) = location_suffix {
        rendered.push_str(&location_suffix);
    }
    Some(rendered)
}

fn parse_local_link_target(dest_url: &str) -> Option<(String, Option<String>)> {
    if dest_url.starts_with("file://") {
        // 处理 file:// URL
        let url = Url::parse(dest_url).ok()?;
        let path_text = file_url_to_local_path_text(&url)?;
        let location_suffix = url.fragment()
            .and_then(normalize_hash_location_suffix_fragment);
        return Some((path_text, location_suffix));
    }
    // 处理普通路径，识别 #L.. 或 :line:col 后缀
}
```

#### 4. 代码块处理
```rust
fn start_codeblock(&mut self, lang: Option<String>, indent: Option<Span<'static>>) {
    // 提取语言标识（处理 "rust,no_run" 等复合 info 字符串）
    let lang = lang
        .as_deref()
        .and_then(|s| s.split([',', ' ', '\t']).next())
        .filter(|s| !s.is_empty())
        .map(std::string::ToString::to_string);
    self.code_block_lang = lang;
    self.code_block_buffer.clear();
}

fn end_codeblock(&mut self) {
    if let Some(lang) = self.code_block_lang.take() {
        let code = std::mem::take(&mut self.code_block_buffer);
        if !code.is_empty() {
            let highlighted = highlight_code_to_lines(&code, &lang);
            for hl_line in highlighted {
                self.push_line(Line::default());
                for span in hl_line.spans {
                    self.push_span(span);
                }
            }
        }
    }
}
```

#### 5. 列表处理
```rust
fn start_item(&mut self) {
    self.pending_marker_line = true;
    let depth = self.list_indices.len();
    let is_ordered = self.list_indices.last().map(Option::is_some).unwrap_or(false);
    let width = depth * 4 - 3;
    let marker = if let Some(last_index) = self.list_indices.last_mut() {
        match last_index {
            None => Some(vec![Span::styled(
                " ".repeat(width - 1) + "- ",
                self.styles.unordered_list_marker,
            )]),
            Some(index) => {
                *index += 1;
                Some(vec![Span::styled(
                    format!("{:width$}. ", *index - 1),
                    self.styles.ordered_list_marker,
                )])
            }
        }
    } else {
        None
    };
    // 构建缩进上下文...
}
```

### 正则表达式

```rust
// 匹配冒号位置后缀：:line[:col][-line[:col]]
// 例如：:74, :74:3, :74:3-76:9
static COLON_LOCATION_SUFFIX_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r":\d+(?::\d+)?(?:[-–]\d+(?::\d+)?)?$").unwrap());

// 匹配哈希位置后缀：#Lline[Ccol][-Lline[Ccol]]
// 例如：#L74, #L74C3, #L74C3-L76C9
static HASH_LOCATION_SUFFIX_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^L\d+(?:C\d+)?(?:-L\d+(?:C\d+)?)?$").unwrap());
```

---

## 关键代码路径与文件引用

### 核心文件
| 文件 | 作用 |
|------|------|
| `markdown_render.rs` | 主渲染实现，包含 Writer 状态机和所有渲染逻辑 |
| `markdown_render_tests.rs` | 测试文件，通过 `include!` 嵌入到主文件 |

### 依赖文件
| 文件 | 作用 |
|------|------|
| `render/highlight.rs` | 语法高亮实现，基于 syntect + two_face |
| `render/line_utils.rs` | 行工具函数：`line_to_static`, `push_owned_lines`, `prefix_lines` |
| `wrapping.rs` | 文本换行实现，URL 感知换行策略 |
| `markdown.rs` | 包装层，提供 `append_markdown` 函数 |
| `utils/string/src/lib.rs` | `normalize_markdown_hash_location_suffix` 函数 |

### 调用方
| 文件 | 调用点 |
|------|--------|
| `lib.rs` | `pub use markdown_render::render_markdown_text;` 公开 API |
| `markdown.rs` | `render_markdown_text_with_width_and_cwd` 包装调用 |
| `model_migration.rs` | 模型迁移提示的 Markdown 渲染 |
| `insert_history.rs` | 历史记录插入时的 Markdown 渲染 |

### 关键代码路径
```
render_markdown_text
  └── render_markdown_text_with_width
        └── render_markdown_text_with_width_and_cwd
              └── Writer::new(parser, width, cwd).run()
                    └── Writer::handle_event() [循环处理每个 Markdown 事件]
                          ├── start_tag() / end_tag()   [处理标签开始/结束]
                          ├── text() / code() / html()  [处理文本内容]
                          ├── soft_break() / hard_break() [处理换行]
                          └── flush_current_line()      [刷新当前行到输出]
```

---

## 依赖与外部交互

### 外部 Crate 依赖
| Crate | 用途 |
|-------|------|
| `pulldown-cmark` | Markdown 解析器，生成事件流 |
| `ratatui` | 终端 UI 框架，提供 `Text`, `Line`, `Span`, `Style` 等类型 |
| `regex_lite` | 正则表达式，用于位置后缀匹配 |
| `url` | URL 解析，处理 `file://` 链接 |
| `dirs` | 获取用户主目录，处理 `~/` 路径 |
| `codex_utils_string` | `normalize_markdown_hash_location_suffix` 函数 |

### 内部模块依赖
```rust
use crate::render::highlight::highlight_code_to_lines;
use crate::render::line_utils::line_to_static;
use crate::wrapping::RtOptions;
use crate::wrapping::adaptive_wrap_line;
use codex_utils_string::normalize_markdown_hash_location_suffix;
```

### 测试依赖
- `pretty_assertions`：更好的测试失败输出
- `insta`：快照测试

---

## 风险、边界与改进建议

### 已知风险

1. **正则表达式编译时 panic**
   - `COLON_LOCATION_SUFFIX_RE` 和 `HASH_LOCATION_SUFFIX_RE` 在 `LazyLock` 初始化时使用 `unwrap()`
   - 风险：如果正则表达式语法错误，程序启动时会 panic
   - 缓解：正则表达式是硬编码的，已通过测试验证

2. **路径解析的局限性**
   - `file_url_to_local_path_text` 对复杂 URL 编码的处理可能不完善
   - Windows UNC 路径和特殊编码依赖字符串重建回退

3. **语法高亮资源消耗**
   - 大文件（>512KB 或 >10000行）会被跳过高亮
   - 这是设计上的保护，但可能导致大代码块无高亮

4. **CRLF 处理**
   - 代码块中 CRLF 的处理依赖 `highlight_code_to_lines` 正确剥离 `\r`
   - 测试覆盖 `crlf_code_block_no_extra_blank_lines` 验证此行为

### 边界情况

1. **空输入**：返回空 `Text`
2. **纯空白输入**：正确处理，不产生幻影行
3. **嵌套列表深度**：理论无限制，但显示效果随深度降低
4. **表格/图片/脚注**：当前被忽略（渲染为空）
5. **HTML 内容**：原样渲染为文本
6. **任务列表**：任务标记被忽略，内容正常渲染

### 改进建议

1. **功能增强**
   - 添加表格渲染支持（当前被忽略）
   - 添加图片 alt 文本的特殊标记
   - 支持脚注的渲染
   - 添加数学公式支持

2. **性能优化**
   - 考虑对频繁渲染的相同内容添加缓存
   - 大文档的增量渲染支持

3. **可维护性**
   - 将 `Writer` 状态机拆分为更小的事件处理器
   - 添加更多内联文档说明复杂逻辑
   - 考虑使用 builder 模式构建 `MarkdownStyles`

4. **测试覆盖**
   - 添加更多边界情况测试（极端嵌套、特殊字符等）
   - 添加性能基准测试
   - 添加模糊测试验证解析器鲁棒性

5. **跨平台改进**
   - 更完善的 Windows 路径处理测试
   - WSL 路径转换支持

### 相关 Issue 区域
- 本地文件链接的路径简化逻辑在 Windows 上可能需要特殊处理
- 语法高亮失败时的回退行为需要保持一致
- 换行宽度计算与终端实际显示可能存在差异（考虑全角字符）
