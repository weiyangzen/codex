# wrapping.rs 深度研究文档

## 文件位置
`codex-rs/tui_app_server/src/wrapping.rs`

---

## 1. 场景与职责

### 1.1 核心问题
在 Codex TUI（Terminal User Interface）中，文本渲染经常包含 URLs —— 包括命令输出、Markdown 内容、Agent 消息、工具调用结果等。标准的 `textwrap` 库在进行文本换行时，会将 `/` 和 `-` 视为合法的断点（split points），这会导致：
- URL 被错误地拆分到多行
- 终端模拟器无法识别被拆分的 URL 为可点击链接
- 用户无法直接在终端中点击打开链接

### 1.2 模块职责
`wrapping.rs` 模块提供 **URL 感知的智能文本换行** 功能，核心职责包括：

1. **URL 保护换行**：检测文本中的 URL 类 token，确保 URL 在换行时保持完整
2. **自适应换行策略**：根据内容类型自动选择标准换行或 URL 保护换行
3. **样式保持**：在换行过程中保留 ratatui 的样式信息（颜色、高亮等）
4. **缩进支持**：支持首行和后续行的不同缩进配置
5. **光标位置计算**：为 textarea 提供字节范围映射，支持光标定位

### 1.3 使用场景

| 场景 | 使用的 API | 说明 |
|------|-----------|------|
| 历史消息渲染 | `adaptive_wrap_lines` | 对话历史中的消息内容 |
| Markdown 渲染 | `adaptive_wrap_line` | Markdown 文本的换行处理 |
| 终端回滚插入 | `adaptive_wrap_line` + URL 检测 | 插入历史行到终端 |
| 状态卡片显示 | `adaptive_wrap_lines` | 状态信息展示 |
| Textarea 光标定位 | `wrap_ranges` | 计算光标位置的字节范围 |
| 执行单元渲染 | `adaptive_wrap_line/lines` | 命令输出渲染 |
| 待输入预览 | `adaptive_wrap_lines` | 待提交消息预览 |

---

## 2. 功能点目的

### 2.1 双路径换行设计

```
┌─────────────────────────────────────────────────────────┐
│                    输入文本 (Line)                        │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │  是否包含 URL-like token? │
              └────────────────────────┘
                    │              │
                    ▼              ▼
            ┌──────────┐    ┌──────────────┐
            │   是      │    │      否       │
            └──────────┘    └──────────────┘
                 │                │
                 ▼                ▼
    ┌─────────────────────┐  ┌─────────────────────┐
    │ URL 保护换行配置      │  │  标准换行配置        │
    │ - AsciiSpace 分词    │  │ - 默认分词器         │
    │ - 自定义 WordSplitter │  │ - HyphenSplitter    │
    │ - break_words=false  │  │ - break_words=true  │
    └─────────────────────┘  └─────────────────────┘
```

### 2.2 URL 检测启发式规则

模块实现了保守的 URL 检测策略，避免误判文件路径：

**识别的 URL 模式：**
- 绝对 URL（带 scheme）：`https://...`, `ftp://...`, `myapp://...`
- 裸域名 URL：`example.com/path`, `www.example.com`
- IPv4 带路径：`192.168.1.1:8080/health`
- `localhost` 带端口和路径：`localhost:3000/api`

**拒绝的非 URL 模式：**
- 文件路径：`src/main.rs`, `foo/bar`
- 无路径/查询的裸域名：`hello.world`
- 无效端口：`localhost:99999/path`

**标点处理：**
- 自动去除 URL 周围的标点符号：`()`, `[]`, `{}`, `<>`, `,.;:!'"`
- 支持带标点的 URL：`(https://example.com)`

### 2.3 主要公共 API

| API | 用途 | 特点 |
|-----|------|------|
| `adaptive_wrap_line` | 单行自适应换行 | 自动检测 URL 并选择策略 |
| `adaptive_wrap_lines` | 多行自适应换行 | 支持初始/后续缩进 |
| `word_wrap_line` | 标准单行换行 | 保持样式，支持缩进 |
| `word_wrap_lines` | 标准多行换行 | 批量处理 |
| `wrap_ranges` | 字节范围计算 | 用于光标定位，含尾随空格 |
| `wrap_ranges_trim` | 字节范围计算（去空格） | 通用范围计算 |
| `line_contains_url_like` | URL 检测 | 检查 Line 是否含 URL |
| `line_has_mixed_url_and_non_url_tokens` | 混合内容检测 | 用于特殊处理策略 |

---

## 3. 具体技术实现

### 3.1 核心数据结构

#### RtOptions - 换行配置封装

```rust
#[derive(Debug, Clone)]
pub struct RtOptions<'a> {
    pub width: usize,                           // 换行宽度
    pub line_ending: textwrap::LineEnding,      // 行尾符
    pub initial_indent: Line<'a>,               // 首行缩进（ratatui Line）
    pub subsequent_indent: Line<'a>,            // 后续行缩进
    pub break_words: bool,                      // 是否允许断词
    pub wrap_algorithm: textwrap::WrapAlgorithm,// 换行算法
    pub word_separator: textwrap::WordSeparator,// 分词器
    pub word_splitter: textwrap::WordSplitter,  // 词分割器
}
```

**设计特点：**
- 使用 builder 模式（消耗性 setter）
- 与 `textwrap::Options` 双向兼容（`From` trait）
- 支持 ratatui 的 `Line` 类型作为缩进

#### LineInput - 输入抽象

```rust
enum LineInput<'a> {
    Borrowed(&'a Line<'a>),
    Owned(Line<'a>),
}
```

支持多种输入类型的统一处理：`&Line`, `Line`, `String`, `&str`, `Cow<str>`, `Span`, `Vec<Span>`

### 3.2 URL 检测实现

#### 检测流程

```rust
fn is_url_like_token(raw_token: &str) -> bool {
    let token = trim_url_token(raw_token);
    !token.is_empty() && (is_absolute_url_like(token) || is_bare_url_like(token))
}
```

#### 绝对 URL 检测

```rust
fn is_absolute_url_like(token: &str) -> bool {
    if !token.contains("://") {
        return false;
    }

    // 优先使用 url crate 解析标准 scheme
    if let Ok(url) = url::Url::parse(token) {
        let scheme = url.scheme().to_ascii_lowercase();
        if matches!(scheme.as_str(), "http" | "https" | "ftp" | "ftps" | "ws" | "wss") {
            return url.host_str().is_some();
        }
        return true; // 非标准 scheme 也接受
    }

    // 回退：自定义 scheme 验证
    has_valid_scheme_prefix(token)
}
```

#### 裸域名 URL 检测

```rust
fn is_bare_url_like(token: &str) -> bool {
    let (host_port, has_trailer) = split_host_port_and_trailer(token);
    
    // 裸域名需要路径/查询/片段，除非以 www. 开头
    if !has_trailer && !host_port.to_ascii_lowercase().starts_with("www.") {
        return false;
    }

    let (host, port) = split_host_and_port(host_port);
    
    // 验证 host 类型
    host.eq_ignore_ascii_case("localhost") || is_ipv4(host) || is_domain_name(host)
}
```

#### 域名验证

```rust
fn is_domain_name(host: &str) -> bool {
    let host = host.to_ascii_lowercase();
    if !host.contains('.') {
        return false;
    }

    let mut labels = host.split('.');
    let tld = labels.next_back()?;
    
    // TLD 必须是纯字母，长度 2-63
    if !is_tld(tld) {
        return false;
    }

    // 所有标签必须符合域名规范
    labels.all(is_domain_label)
}
```

### 3.3 自定义 WordSplitter

```rust
fn split_non_url_word(word: &str) -> Vec<usize> {
    if is_url_like_token(word) {
        return Vec::new(); // URL token 不分割
    }

    // 非 URL token 在每个字符边界分割
    word.char_indices().skip(1).map(|(idx, _)| idx).collect()
}
```

### 3.4 URL 保护换行配置

```rust
pub(crate) fn url_preserving_wrap_options<'a>(opts: RtOptions<'a>) -> RtOptions<'a> {
    opts.word_separator(textwrap::WordSeparator::AsciiSpace)  // 只在空格处分词
        .word_splitter(textwrap::WordSplitter::Custom(split_non_url_word))
        .break_words(false)  // 不在词内断行
}
```

### 3.5 字节范围映射（用于光标定位）

`wrap_ranges` 函数的核心挑战：`textwrap` 返回的 `Cow::Owned` 行可能包含合成的连字符（hyphenation penalty），需要映射回原始文本的字节范围。

```rust
fn map_owned_wrapped_line_to_range(
    text: &str,
    cursor: usize,
    wrapped: &str,
    synthetic_prefix: &str,
) -> Range<usize> {
    // 1. 去除合成的前缀缩进
    let wrapped = if synthetic_prefix.is_empty() {
        wrapped
    } else {
        wrapped.strip_prefix(synthetic_prefix).unwrap_or(wrapped)
    };

    // 2. 跳过前导空格找到起始位置
    let mut start = cursor;
    while start < text.len() && !wrapped.starts_with(' ') {
        // ...
    }

    // 3. 字符级匹配，跳过合成的连字符
    let mut end = start;
    let mut saw_source_char = false;
    for ch in wrapped.chars() {
        if ch == source_char {
            end += src.len_utf8();
            saw_source_char = true;
        } else if ch == '-' && is_last_char {
            // 跳过合成的连字符
            continue;
        }
    }

    start..end
}
```

### 3.6 样式保持的换行

`word_wrap_line` 函数在换行时保持 ratatui 样式：

```rust
pub(crate) fn word_wrap_line<'a, O>(line: &'a Line<'a>, width_or_options: O) -> Vec<Line<'a>> {
    // 1. 扁平化 Line 为字符串，记录 span 边界
    let mut flat = String::new();
    let mut span_bounds = Vec::new();
    for s in &line.spans {
        let text = s.content.as_ref();
        let start = acc;
        flat.push_str(text);
        acc += text.len();
        span_bounds.push((start..acc, s.style));
    }

    // 2. 使用 textwrap 计算换行点
    let wrapped = wrap_ranges_trim(&flat, opts);

    // 3. 使用 slice_line_spans 将字节范围映射回原始 spans，保持样式
    for range in wrapped {
        let sliced = slice_line_spans(line, &span_bounds, range);
        out.push(sliced);
    }
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 模块依赖图

```
wrapping.rs
    │
    ├── 依赖导入
    │   ├── ratatui::text::{Line, Span}     # 文本渲染类型
    │   ├── textwrap::{Options, WordSeparator, WordSplitter, ...}  # 换行核心
    │   ├── url::Url                         # URL 解析
    │   └── crate::render::line_utils::push_owned_lines  # 行工具
    │
    ├── 被调用方（内部模块）
    │   ├── history_cell.rs                  # 历史单元格渲染
    │   ├── markdown_render.rs               # Markdown 渲染
    │   ├── insert_history.rs                # 历史插入
    │   ├── exec_cell/render.rs              # 执行单元渲染
    │   ├── status/card.rs                   # 状态卡片
    │   ├── status_indicator_widget.rs       # 状态指示器
    │   ├── bottom_pane/textarea.rs          # 文本编辑区
    │   ├── bottom_pane/pending_input_preview.rs  # 输入预览
    │   ├── bottom_pane/pending_thread_approvals.rs
    │   ├── bottom_pane/selection_popup_common.rs
    │   ├── bottom_pane/app_link_view.rs
    │   └── chatwidget.rs                    # 聊天组件
    │
    └── 测试（模块内）
        └── 47 个单元测试，覆盖 URL 检测、换行、缩进、样式保持等
```

### 4.2 关键调用路径

#### 路径 1：历史消息渲染
```
history_cell.rs:render()
    └── adaptive_wrap_lines()
        ├── line_contains_url_like()      # 检测 URL
        ├── url_preserving_wrap_options() # URL 保护配置
        └── word_wrap_line()              # 实际换行
            └── slice_line_spans()        # 样式保持
```

#### 路径 2：Markdown 渲染
```
markdown_render.rs
    └── adaptive_wrap_line()
        └── word_wrap_line()
```

#### 路径 3：Textarea 光标定位
```
bottom_pane/textarea.rs
    └── wrap_ranges()
        └── map_owned_wrapped_line_to_range()  # 字节范围映射
```

#### 路径 4：终端历史插入
```
insert_history.rs
    ├── line_contains_url_like()
    ├── line_has_mixed_url_and_non_url_tokens()
    └── adaptive_wrap_line()
```

### 4.3 关键函数签名

```rust
// 自适应换行（推荐入口）
pub(crate) fn adaptive_wrap_line<'a>(line: &'a Line<'a>, base: RtOptions<'a>) -> Vec<Line<'a>>;
pub(crate) fn adaptive_wrap_lines<'a, I, L>(lines: I, width_or_options: RtOptions<'a>) -> Vec<Line<'static>>;

// 标准换行
pub(crate) fn word_wrap_line<'a, O>(line: &'a Line<'a>, width_or_options: O) -> Vec<Line<'a>>;
pub(crate) fn word_wrap_lines<'a, I, O, L>(lines: I, width_or_options: O) -> Vec<Line<'static>>;

// 字节范围计算
pub(crate) fn wrap_ranges<'a, O>(text: &str, width_or_options: O) -> Vec<Range<usize>>;
pub(crate) fn wrap_ranges_trim<'a, O>(text: &str, width_or_options: O) -> Vec<Range<usize>>;

// URL 检测
pub(crate) fn line_contains_url_like(line: &Line<'_>) -> bool;
pub(crate) fn line_has_mixed_url_and_non_url_tokens(line: &Line<'_>) -> bool;
pub(crate) fn text_contains_url_like(text: &str) -> bool;
```

---

## 5. 依赖与外部交互

### 5.1 外部 crate 依赖

| Crate | 用途 | 版本 |
|-------|------|------|
| `textwrap` | 核心换行算法 | workspace |
| `ratatui` | TUI 渲染类型（Line, Span, Style） | workspace |
| `url` | URL 解析验证 | workspace |
| `unicode-width` | 显示宽度计算（通过 ratatui） | workspace |

### 5.2 内部模块依赖

```rust
use crate::render::line_utils::push_owned_lines;
```

`line_utils.rs` 提供：
- `line_to_static()`: 将借用的 Line 转换为拥有的 'static Line
- `push_owned_lines()`: 将换行结果追加到输出向量
- `prefix_lines()`: 为行添加前缀
- `is_blank_line_spaces_only()`: 空白行检测

### 5.3 textwrap 集成细节

**配置映射：**
```rust
let opts = Options::new(rt_opts.width)
    .line_ending(rt_opts.line_ending)
    .break_words(rt_opts.break_words)
    .wrap_algorithm(rt_opts.wrap_algorithm)
    .word_separator(rt_opts.word_separator)
    .word_splitter(rt_opts.word_splitter);
```

**WordSeparator 选择：**
- 标准模式：`textwrap::WordSeparator::new()`（Unicode 语义分词）
- URL 保护模式：`textwrap::WordSeparator::AsciiSpace`（仅空格分词）

**WordSplitter 选择：**
- 标准模式：`textwrap::WordSplitter::HyphenSplitter`
- URL 保护模式：自定义 `split_non_url_word` 回调

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 风险 1：URL 检测误判

**问题：** 保守的启发式规则可能漏检某些有效的 URL 格式。

**当前限制：**
- 不支持 IPv6 括号表示法：`[::1]:8080`
- 裸域名必须有路径/查询或 `www.` 前缀
- 自定义 scheme 仅验证语法，不验证语义

**缓解：** 漏检的 URL 会被正常换行，只是可能断开，不影响功能。

#### 风险 2：字节范围映射的复杂性

**问题：** `map_owned_wrapped_line_to_range` 处理 `textwrap` 的合成输出时存在边缘情况。

**当前处理：**
- 跳过合成的连字符（hyphenation penalty）
- 处理合成的前缀缩进
- 非源字符的恢复机制（警告日志）

**测试覆盖：** 有专门的测试用例验证复杂场景（如 `wrap_ranges_indent_prefix_coincides_with_source_char`）。

#### 风险 3：性能考虑

**URL 检测开销：** 每行换行都需要进行 URL 检测，包括：
- 分词（`split_ascii_whitespace`）
- 正则/模式匹配
- 可能的 `url::Url::parse` 调用

**优化：** 模块使用保守的短路逻辑，先检查 `contains("://")` 再调用 URL 解析。

### 6.2 边界情况

| 边界情况 | 处理方式 |
|---------|---------|
| 空输入 | 返回单空行 |
| 宽度为 0 | 使用 `max(1, width)` 确保最小宽度 |
| 超长单词（无空格） | 根据 `break_words` 设置决定是否断词 |
| 全角字符（Emoji/CJK） | 依赖 `textwrap` + `unicode-width` 正确处理 |
| 混合样式 Line | 通过 `slice_line_spans` 保持样式 |
| 缩进宽度超过总宽度 | 缩进后至少保留 1 字符空间 |

### 6.3 改进建议

#### 建议 1：IPv6 支持

当前代码明确注释不支持 IPv6 括号表示法。如果需要支持：

```rust
// 在 split_host_and_port 中添加 IPv6 处理
fn split_host_and_port(host_port: &str) -> (&str, Option<&str>) {
    if host_port.starts_with('[') {
        // 处理 [IPv6]:port 格式
        if let Some((host, port)) = host_port.rsplit_once("]:") {
            return (&host[1..], Some(port)); // 去除 '['
        }
    }
    // ... 现有 IPv4 处理
}
```

#### 建议 2：缓存 URL 检测结果

对于频繁重绘的 UI 组件，可以缓存每行的 URL 检测结果：

```rust
struct CachedUrlDetection {
    text_hash: u64,
    has_url: bool,
}
```

#### 建议 3：国际化域名（IDN）支持

当前域名验证仅支持 ASCII。如需支持 IDN（如 `例子.测试`），需要：
- 使用 `idna` crate 进行编码转换
- 在 `is_domain_name` 中添加 punycode 处理

#### 建议 4：更精确的 URL 字符分类

当前 `split_non_url_word` 对非 URL token 使用字符级分割，可能导致 CJK 文本在不当位置断开。可以考虑：
- 使用 `unicode-segmentation` 的 grapheme cluster
- 针对 CJK 使用不断行规则

### 6.4 测试覆盖

模块包含 47 个单元测试，覆盖：

| 测试类别 | 数量 | 示例 |
|---------|------|------|
| 基础换行 | 8 | `trivial_unstyled_no_indents_wide_width` |
| 样式保持 | 3 | `styled_split_within_span_preserves_style` |
| 缩进处理 | 5 | `with_initial_and_subsequent_indents` |
| Unicode/Emoji | 2 | `wide_unicode_wraps_by_display_width` |
| URL 检测 | 8 | `text_contains_url_like_matches_expected_tokens` |
| 自适应换行 | 4 | `adaptive_wrap_line_keeps_long_url_like_token_intact` |
| 字节范围映射 | 5 | `wrap_ranges_indent_prefix_coincides_with_source_char` |
| 多行换行 | 4 | `wrap_lines_applies_initial_indent_only_once` |
| 边界情况 | 8 | `empty_input_yields_single_empty_line` |

---

## 7. 代码规范与约定

根据项目 `AGENTS.md` 的 TUI 风格约定：

1. **使用 ratatui 的 Stylize trait**：`"text".red()`, `"text".dim()` 等
2. **简洁转换**：`"text".into()`, `vec![...].into()`
3. **避免硬编码白色**：不使用 `.white()`，使用默认前景色
4. **文本换行**：使用 `textwrap::wrap` 处理纯字符串，使用本模块处理 ratatui Line

---

## 8. 总结

`wrapping.rs` 是 Codex TUI 中负责文本换行的核心模块，其设计亮点包括：

1. **URL 感知**：智能检测 URL 并保护其不被断开，提升终端用户体验
2. **双路径设计**：根据内容自动选择最佳换行策略
3. **样式保持**：在换行过程中完整保留 ratatui 的样式信息
4. **灵活配置**：通过 `RtOptions` 提供丰富的换行配置选项
5. **光标支持**：提供字节范围映射，支持 textarea 的光标定位

模块通过保守的启发式规则和充分的测试覆盖，在保证正确性的前提下提供了良好的用户体验。
