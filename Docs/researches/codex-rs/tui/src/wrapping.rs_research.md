# wrapping.rs 深度研究文档

## 概述

`wrapping.rs` 是 Codex TUI (Terminal User Interface) 中负责文本换行处理的核心模块。它基于 `textwrap` 库构建，但针对 TUI 场景进行了深度定制，特别是解决了 URL 在终端中可点击性的关键问题。

---

## 场景与职责

### 核心场景

1. **聊天记录渲染** (`history_cell.rs`)
   - 用户消息、AI 回复、工具调用结果的换行显示
   - 需要保持 URL 完整以便终端模拟器识别为可点击链接

2. **Markdown 渲染** (`markdown_render.rs`)
   - Markdown 文本转换为终端可显示的格式
   - 代码块、列表、引用等元素的换行处理

3. **编辑器文本区域** (`bottom_pane/textarea.rs`)
   - 用户输入的换行和光标位置计算
   - 支持软换行（visual wrapping）与逻辑行的映射

4. **状态与提示信息** (`status_indicator_widget.rs`, `status/card.rs`)
   - 状态卡片、提示信息的自动换行

5. **历史记录插入** (`insert_history.rs`)
   - 向终端回滚缓冲区插入历史记录时的换行处理
   - 区分纯 URL 行和混合内容行的不同策略

6. **执行单元格渲染** (`exec_cell/render.rs`)
   - 命令输出、工具调用结果的换行显示

7. **选择弹窗** (`bottom_pane/selection_popup_common.rs`)
   - 选项描述的换行处理

8. **待处理输入预览** (`bottom_pane/pending_input_preview.rs`)
   - 待发送消息的预览换行

9. **应用链接视图** (`bottom_pane/app_link_view.rs`)
   - 应用安装/启用提示的换行

10. **待处理线程审批** (`bottom_pane/pending_thread_approvals.rs`)
    - 多线程审批提示的换行

### 核心职责

| 职责 | 说明 |
|------|------|
| **标准换行** | 基于 `textwrap` 的普通文本换行，支持缩进、样式保留 |
| **URL 感知换行** | 检测 URL 并防止其在换行时被拆分，保持终端可点击性 |
| **样式保留** | 换行时保留 ratatui 的 `Span` 样式信息 |
| **范围映射** | 为 textarea 提供字节范围到换行位置的映射，支持光标定位 |
| **自适应策略** | 根据内容类型自动选择最佳换行策略 |

---

## 功能点目的

### 1. 双路径换行架构

模块提供两种换行路径：

```rust
// 标准路径 - 纯文本换行
pub(crate) fn word_wrap_line<'a, O>(line: &'a Line<'a>, width_or_options: O) -> Vec<Line<'a>>
pub(crate) fn word_wrap_lines<'a, I, O, L>(lines: I, width_or_options: O) -> Vec<Line<'static>>

// 自适应路径 - URL 感知换行
pub(crate) fn adaptive_wrap_line<'a>(line: &'a Line<'a>, base: RtOptions<'a>) -> Vec<Line<'a>>
pub(crate) fn adaptive_wrap_lines<'a, I, L>(lines: I, width_or_options: RtOptions<'a>) -> Vec<Line<'static>>
```

**设计目的**：
- **标准路径**：用于确定不含 URL 的内容（如代码块、纯数字输出），获得最佳性能
- **自适应路径**：用于可能包含 URL 的内容，自动检测并保护 URL 不被拆分

### 2. URL 检测与保护机制

**问题背景**：
标准 `textwrap` 将 `/` 和 `-` 视为单词分割点，这会导致 URL 被拆分到多行：
```
https://example.com/long-
path-with-dashes
```
被拆分后的 URL 无法被终端模拟器识别为可点击链接。

**解决方案**：

1. **URL 检测** (`text_contains_url_like`)
   - 识别带 scheme 的绝对 URL (`https://`, `ftp://`, 自定义 scheme)
   - 识别裸域名 URL (`example.com/path`, `www.example.com`)
   - 识别 IPv4 带路径 (`192.168.1.1:8080/health`)
   - 识别 `localhost` 带端口和路径

2. **URL 保护策略** (`url_preserving_wrap_options`)
   - 使用 `AsciiSpace` 单词分隔器（只在空格处分割，不在 `/` `-` 处分割）
   - 禁用 `break_words`（不允许在单词中间断开）
   - 自定义 `WordSplitter`：对 URL 返回空分割点（不分割），对非 URL 返回字符级分割点

3. **混合行处理** (`line_has_mixed_url_and_non_url_tokens`)
   - 检测一行中同时包含 URL 和非 URL 内容的情况
   - 非 URL 部分仍允许正常换行，URL 部分保持完整

### 3. 范围映射功能

为 textarea 的 cursor-position 逻辑提供支持：

```rust
pub(crate) fn wrap_ranges<'a, O>(text: &str, width_or_options: O) -> Vec<Range<usize>>
pub(crate) fn wrap_ranges_trim<'a, O>(text: &str, width_or_options: O) -> Vec<Range<usize>>
```

**功能**：
- 返回每个换行后行对应的原文字本字节范围
- 包含尾随空格和哨兵字节（+1）用于 cursor 计算
- 处理 `textwrap` 产生的 `Cow::Owned` 行（含连字符等合成字符）

### 4. 样式保留换行

ratatui 的 `Line` 由多个 `Span` 组成，每个 `Span` 有独立的样式。换行时需要：

1. **扁平化**：将多 `Span` 的 `Line` 扁平化为连续字符串
2. **记录边界**：记录每个 `Span` 的字节范围
3. **切片映射**：根据换行结果将字节范围映射回 `Span`
4. **样式继承**：确保换行后的片段保留原样式

---

## 具体技术实现

### 关键数据结构

#### `RtOptions<'a>` - 换行选项封装

```rust
#[derive(Debug, Clone)]
pub struct RtOptions<'a> {
    pub width: usize,                           // 换行宽度
    pub line_ending: textwrap::LineEnding,      // 行尾符
    pub initial_indent: Line<'a>,               // 首行缩进
    pub subsequent_indent: Line<'a>,            // 后续行缩进
    pub break_words: bool,                      // 是否允许单词内断开
    pub wrap_algorithm: textwrap::WrapAlgorithm,// 换行算法
    pub word_separator: textwrap::WordSeparator,// 单词分隔策略
    pub word_splitter: textwrap::WordSplitter,  // 单词分割策略
}
```

**设计特点**：
- 使用 builder 模式（`new()`, `width()`, `initial_indent()` 等）
- 支持从 `usize` 隐式转换（仅设置 width，其他默认值）
- 与 `textwrap::Options` 兼容但额外支持 ratatui 的 `Line` 类型缩进

#### `LineInput<'a>` - 行输入抽象

```rust
enum LineInput<'a> {
    Borrowed(&'a Line<'a>),
    Owned(Line<'a>),
}
```

允许 `word_wrap_lines` 接受多种输入类型：`&Line`, `Line`, `String`, `&str`, `Cow<str>`, `Span`, `Vec<Span>`。

### 关键流程

#### 1. 自适应换行流程 (`adaptive_wrap_line`)

```rust
pub(crate) fn adaptive_wrap_line<'a>(line: &'a Line<'a>, base: RtOptions<'a>) -> Vec<Line<'a>> {
    // 1. 检测行中是否包含 URL
    let selected = if line_contains_url_like(line) {
        url_preserving_wrap_options(base)  // 使用 URL 保护选项
    } else {
        base  // 使用标准选项
    };
    // 2. 执行标准换行
    word_wrap_line(line, selected)
}
```

#### 2. 标准换行流程 (`word_wrap_line`)

```rust
pub(crate) fn word_wrap_line<'a, O>(line: &'a Line<'a>, width_or_options: O) -> Vec<Line<'a>>
where
    O: Into<RtOptions<'a>>,
{
    // 1. 扁平化：将 Line 的多个 Span 合并为连续字符串
    // 2. 记录每个 Span 的字节范围 (span_bounds)
    // 3. 计算首行可用宽度（减去 initial_indent 宽度）
    // 4. 调用 wrap_ranges_trim 获取首行字节范围
    // 5. 使用 slice_line_spans 将字节范围映射回 Span，构建首行 Line
    // 6. 对剩余文本使用 subsequent_indent 宽度，重复步骤 4-5
    // 7. 返回所有换行后的 Line
}
```

#### 3. URL 检测流程 (`text_contains_url_like`)

```rust
pub(crate) fn text_contains_url_like(text: &str) -> bool {
    text.split_ascii_whitespace().any(is_url_like_token)
}

fn is_url_like_token(raw_token: &str) -> bool {
    let token = trim_url_token(raw_token);  // 去除标点
    !token.is_empty() && (is_absolute_url_like(token) || is_bare_url_like(token))
}
```

**绝对 URL 检测** (`is_absolute_url_like`):
1. 检查是否包含 `://`
2. 尝试用 `url::Url::parse` 解析（支持标准 scheme: http, https, ftp, ftps, ws, wss）
3. 对自定义 scheme 使用 `has_valid_scheme_prefix` 回退检测

**裸域名 URL 检测** (`is_bare_url_like`):
1. 分割主机:端口和路径/查询/片段
2. 检查主机是否为 `localhost`、IPv4 地址或有效域名
3. 验证端口有效性（如果存在）
4. 域名需有有效 TLD（2-63 个字母）

#### 4. 范围映射流程 (`map_owned_wrapped_line_to_range`)

处理 `textwrap` 返回 `Cow::Owned` 的情况（通常是因为插入了连字符 `-`）：

```rust
fn map_owned_wrapped_line_to_range(
    text: &str,
    cursor: usize,
    wrapped: &str,
    synthetic_prefix: &str,
) -> Range<usize> {
    // 1. 去除合成的前缀（如缩进）
    // 2. 跳过前导空格
    // 3. 逐字符匹配 wrapped 和原始 text
    // 4. 跳过 textwrap 合成的连字符（penalty char）
    // 5. 返回匹配的字节范围
}
```

### URL 保护技术细节

#### `url_preserving_wrap_options`

```rust
pub(crate) fn url_preserving_wrap_options<'a>(opts: RtOptions<'a>) -> RtOptions<'a> {
    opts.word_separator(textwrap::WordSeparator::AsciiSpace)  // 只在空格处分隔
        .word_splitter(textwrap::WordSplitter::Custom(split_non_url_word))  // 自定义分割
        .break_words(false)  // 不允许在单词中间断开
}
```

#### `split_non_url_word`

```rust
fn split_non_url_word(word: &str) -> Vec<usize> {
    if is_url_like_token(word) {
        return Vec::new();  // URL 不分割
    }
    word.char_indices().skip(1).map(|(idx, _)| idx).collect()  // 非 URL 字符级分割
}
```

---

## 关键代码路径与文件引用

### 模块声明
- `codex-rs/tui/src/lib.rs:247`: `mod wrapping;`

### 公共 API 导出

| 函数/类型 | 可见性 | 用途 |
|-----------|--------|------|
| `RtOptions` | `pub` | 换行选项配置 |
| `word_wrap_line` | `pub(crate)` | 单行标准换行 |
| `word_wrap_lines` | `pub(crate)` | 多行标准换行 |
| `adaptive_wrap_line` | `pub(crate)` | 单行 URL 感知换行 |
| `adaptive_wrap_lines` | `pub(crate)` | 多行 URL 感知换行 |
| `wrap_ranges` | `pub(crate)` | 字节范围换行（textarea 用） |
| `wrap_ranges_trim` | `pub(crate)` | 无尾随空格的范围换行 |
| `line_contains_url_like` | `pub(crate)` | 检测 Line 中是否含 URL |
| `line_has_mixed_url_and_non_url_tokens` | `pub(crate)` | 检测混合内容行 |
| `text_contains_url_like` | `pub(crate)` | 检测字符串中是否含 URL |

### 调用方分布

```
codex-rs/tui/src/
├── history_cell.rs:36-38          → adaptive_wrap_line, adaptive_wrap_lines
├── markdown_render.rs:10-11       → adaptive_wrap_line, RtOptions
├── insert_history.rs:5-8          → adaptive_wrap_line, line_contains_url_like, line_has_mixed_url_and_non_url_tokens
├── exec_cell/render.rs:12-14      → adaptive_wrap_line, adaptive_wrap_lines
├── status_indicator_widget.rs:31-32 → word_wrap_lines
├── status/card.rs:43-44           → adaptive_wrap_lines
├── bottom_pane/
│   ├── textarea.rs:1278           → wrap_ranges
│   ├── selection_popup_common.rs:99-100,271-272 → word_wrap_line
│   ├── pending_input_preview.rs:10-11 → adaptive_wrap_lines
│   ├── pending_thread_approvals.rs:8-9 → adaptive_wrap_lines
│   └── app_link_view.rs:32-33     → adaptive_wrap_lines
└── markdown_stream.rs:240         → word_wrap_lines
```

### 依赖模块

```rust
// 外部依赖
use textwrap::Options;
use ratatui::text::Line;
use ratatui::text::Span;
use std::borrow::Cow;
use std::ops::Range;

// 内部依赖
use crate::render::line_utils::push_owned_lines;
```

### 测试覆盖

测试模块位于文件末尾（`#[cfg(test)] mod tests`），包含：

| 测试类别 | 测试函数示例 |
|----------|--------------|
| 基础换行 | `trivial_unstyled_no_indents_wide_width`, `simple_unstyled_wrap_narrow_width` |
| 样式保留 | `styled_split_within_span_preserves_style` |
| 缩进处理 | `with_initial_and_subsequent_indents`, `indent_consumes_width_leaving_one_char_space` |
| Unicode | `wide_unicode_wraps_by_display_width`, `line_height_counts_double_width_emoji` |
| URL 检测 | `text_contains_url_like_matches_expected_tokens`, `text_contains_url_like_rejects_non_urls` |
| 自适应换行 | `adaptive_wrap_line_keeps_long_url_like_token_intact`, `adaptive_wrap_line_mixed_line_wraps_long_non_url_token` |
| 范围映射 | `wrap_ranges_indent_prefix_coincides_with_source_char`, `map_owned_wrapped_line_to_range_indent_coincides_with_source` |

---

## 依赖与外部交互

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `textwrap` | 核心换行算法 |
| `ratatui` | `Line`, `Span`, `Style` 等 TUI 类型 |
| `url` | URL 解析验证 |
| `tracing` | 警告日志（`map_owned_wrapped_line_to_range` 中的不匹配警告） |

### 与 `textwrap` 的集成

```rust
// 从 RtOptions 构建 textwrap::Options
let opts = Options::new(rt_opts.width)
    .line_ending(rt_opts.line_ending)
    .break_words(rt_opts.break_words)
    .wrap_algorithm(rt_opts.wrap_algorithm)
    .word_separator(rt_opts.word_separator)
    .word_splitter(rt_opts.word_splitter);

// 执行换行
let wrapped = textwrap::wrap(text, &opts);
```

### 与 ratatui 的集成

```rust
// 输入: &Line<'_>
// 输出: Vec<Line<'a>>

// 样式保留通过 slice_line_spans 实现：
// 1. 根据字节范围找到对应的原始 Span
// 2. 截取子字符串（保持 Cow::Borrowed 当可能）
// 3. 复制原始样式
```

### 与 `line_utils` 的交互

```rust
// wrapping.rs 使用
use crate::render::line_utils::push_owned_lines;

// 将换行结果（借用）转换为 owned 'static 版本并追加到输出
pub fn push_owned_lines<'a>(src: &[Line<'a>], out: &mut Vec<Line<'static>>)
```

---

## 风险、边界与改进建议

### 已知风险

#### 1. URL 检测误报/漏报

**误报风险**：
- 文件路径如 `src/main.rs` 被错误识别为 URL（当前通过要求有效 TLD 或 scheme 避免）
- 带点的普通文本如 `hello.world`（当前通过要求路径/查询/片段或 `www.` 前缀避免）

**漏报风险**：
- IPv6 地址（明确不支持，`is_bare_url_like` 注释说明）
- 非标准端口号（超过 65535 会被拒绝）
- 无路径/查询的裸域名（如 `example.com`，除非以 `www.` 开头）

#### 2. 性能考虑

- **URL 检测**：每行需要遍历所有 token，进行正则式解析验证
- **范围映射**：`map_owned_wrapped_line_to_range` 逐字符比较，最坏情况 O(n²)
- **样式保留**：需要为每个 Span 计算字节范围，增加内存分配

#### 3. 边界情况

| 场景 | 行为 |
|------|------|
| 宽度为 0 | `max(1)` 保护，至少为 1 |
| 空行 | 返回单条空行 |
| 全空格行 | 返回单条空行 |
| 超长单词（无空格） | 根据 `break_words` 设置，可能溢出或字符级分割 |
| 缩进宽度过大 | `saturating_sub` 保护，确保至少 1 字符可用宽度 |

#### 4. 安全考虑

- `wrap_ranges` 使用 `unsafe { slice.as_ptr().offset_from(text.as_ptr()) }` 计算字节偏移，依赖输入字符串的内存布局
- 虽然当前使用场景安全，但需确保输入字符串生命周期足够长

### 改进建议

#### 1. URL 检测增强

```rust
// 建议：添加对常见文件扩展名的排除
const FILE_EXTENSIONS: &[&str] = &[".rs", ".js", ".ts", ".py", ".md", ".txt", ".json"];

// 建议：支持 IPv6 地址
fn is_ipv6(host: &str) -> bool {
    host.starts_with('[') && host.contains(']')
}
```

#### 2. 性能优化

```rust
// 建议：对无样式的简单文本使用快速路径
pub(crate) fn word_wrap_line_fast(text: &str, width: usize) -> Vec<&str> {
    // 直接返回 textwrap 结果，避免 Span 处理开销
}

// 建议：缓存 URL 检测结果
use std::collections::HashMap;
static URL_CACHE: LazyLock<Mutex<HashMap<String, bool>>> = ...;
```

#### 3. 功能扩展

```rust
// 建议：支持 CJK 字符的更佳换行（基于规则而非仅字符边界）
pub(crate) fn cjk_aware_wrap_options<'a>(opts: RtOptions<'a>) -> RtOptions<'a> {
    opts.word_splitter(textwrap::WordSplitter::Custom(cjk_split_word))
}

// 建议：支持表格对齐的换行
pub(crate) fn table_aware_wrap(
    lines: &[Line<'_>],
    column_widths: &[usize],
) -> Vec<Vec<Line<'static>>> {
    // 保持列对齐的换行
}
```

#### 4. 测试增强

- 添加模糊测试（fuzzing）验证范围映射的正确性
- 添加性能基准测试（criterion）监控回归
- 添加更多 CJK、RTL（从右到左）文本的测试用例

#### 5. 文档改进

- 添加更多示例代码展示不同场景的使用
- 为 `RtOptions` 的每个字段添加详细说明和最佳实践
- 添加架构图展示数据流

### 维护注意事项

1. **textwrap 升级**：升级时需验证 `Cow::Owned` 的行为是否变化，可能影响 `map_owned_wrapped_line_to_range`
2. **ratatui 升级**：`Line`, `Span` 的 API 变化需要同步更新
3. **URL 标准演进**：新的 TLD 或 URL scheme 可能需要更新检测逻辑
4. **AGENTS.md 合规**：修改后需运行 `just fmt` 和 `cargo test -p codex-tui`

---

## 总结

`wrapping.rs` 是 Codex TUI 文本渲染的核心基础设施，通过巧妙的双路径架构平衡了性能与功能需求。其 URL 感知换行机制解决了终端环境下链接可点击性的关键问题，是用户体验的重要保障。模块设计遵循 Rust 最佳实践，使用 builder 模式、类型安全和详尽的测试覆盖，是 TUI 文本处理的优秀实现参考。
