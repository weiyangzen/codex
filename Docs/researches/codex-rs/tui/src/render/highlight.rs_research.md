# highlight.rs 研究文档

## 场景与职责

`highlight.rs` 是 Codex TUI 的语法高亮引擎模块，负责将源代码文本转换为带有样式信息的 ratatui 文本行。它是 TUI 渲染系统的核心组件之一，主要用于：

1. **代码块高亮**：在 Markdown 渲染中为围栏代码块提供语法高亮
2. **Diff 渲染支持**：为代码差异展示提供语法高亮和作用域背景色提取
3. **Shell 命令高亮**：为执行单元格中的 bash 脚本提供高亮
4. **主题管理**：支持 32 种内置主题和自定义 `.tmTheme` 主题文件的动态切换

该模块位于 `codex-rs/tui/src/render/highlight.rs`，是 `render` 模块的子模块之一。

## 功能点目的

### 1. 语法高亮核心功能

使用 `syntect` 库配合 `two_face` 的语法和主题包，提供约 250 种语言的语法高亮支持。

### 2. 主题系统

- **32 种内置主题**：包括流行的主题如 Dracula、Nord、Catppuccin、Gruvbox、Solarized 等
- **自定义主题支持**：支持从 `{CODEX_HOME}/themes/{name}.tmTheme` 加载自定义主题
- **自适应默认主题**：根据终端背景亮度自动选择 CatppuccinLatte（浅色）或 CatppuccinMocha（深色）
- **运行时主题切换**：支持主题选择器的实时预览功能

### 3. 安全限制

- **大小限制**：超过 512 KB 的输入跳过高亮
- **行数限制**：超过 10,000 行的输入跳过高亮
- 这些限制防止病态输入导致的 CPU/内存过度使用

### 4. Diff 作用域背景色提取

从主题中提取 `markup.inserted`/`markup.deleted` 或 `diff.inserted`/`diff.deleted` 作用域的背景色，用于差异渲染。

## 具体技术实现

### 关键数据结构

```rust
// 全局单例 - 语法数据库（初始化后不可变）
static SYNTAX_SET: OnceLock<SyntaxSet> = OnceLock::new();

// 全局单例 - 活动主题（运行时可通过 RwLock 切换）
static THEME: OnceLock<RwLock<Theme>> = OnceLock::new();

// 全局单例 - 用户主题偏好（写一次）
static THEME_OVERRIDE: OnceLock<Option<String>> = OnceLock::new();

// 全局单例 - CODEX_HOME 路径（用于自定义主题发现）
static CODEX_HOME: OnceLock<Option<PathBuf>> = OnceLock::new();

// Diff 作用域背景色 RGB 值
pub(crate) struct DiffScopeBackgroundRgbs {
    pub inserted: Option<(u8, u8, u8)>,
    pub deleted: Option<(u8, u8, u8)>,
}

// 主题条目（用于主题选择器）
pub(crate) struct ThemeEntry {
    pub name: String,      // kebab-case 标识符
    pub is_custom: bool,   // 是否为自定义主题
}
```

### 核心流程

#### 1. 初始化流程

```rust
// 1. 启动时调用 set_theme_override 设置用户偏好和 CODEX_HOME
pub(crate) fn set_theme_override(
    name: Option<String>,
    codex_home: Option<PathBuf>,
) -> Option<String>  // 返回配置警告（如果有）

// 2. 首次访问 theme_lock() 时懒加载主题
fn theme_lock() -> &'static RwLock<Theme> {
    THEME.get_or_init(|| RwLock::new(build_default_theme()))
}
```

#### 2. 主题解析流程

```rust
fn resolve_theme_with_override(name: Option<&str>, codex_home: Option<&Path>) -> Theme {
    // 1. 尝试解析为内置主题
    if let Some(theme_name) = parse_theme_name(name) {
        return ts.get(theme_name).clone();
    }
    // 2. 尝试加载自定义 .tmTheme 文件
    if let Some(theme) = load_custom_theme(name, home) {
        return theme;
    }
    // 3. 使用自适应默认主题
    ts.get(adaptive_default_embedded_theme_name()).clone()
}
```

#### 3. 语法高亮流程

```rust
pub(crate) fn highlight_code_to_lines(code: &str, lang: &str) -> Vec<Line<'static>> {
    // 尝试高亮
    if let Some(line_spans) = highlight_to_line_spans(code, lang) {
        line_spans.into_iter().map(Line::from).collect()
    } else {
        // 回退：纯文本行
        code.lines().map(|l| Line::from(l.to_string())).collect()
    }
}

fn highlight_to_line_spans(code: &str, lang: &str) -> Option<Vec<Vec<Span<'static>>>> {
    // 1. 检查安全限制
    if code.len() > MAX_HIGHLIGHT_BYTES || code.lines().count() > MAX_HIGHLIGHT_LINES {
        return None;
    }
    // 2. 查找语法定义
    let syntax = find_syntax(lang)?;
    // 3. 使用 syntect 高亮
    let mut h = HighlightLines::new(syntax, theme);
    for line in LinesWithEndings::from(code) {
        let ranges = h.highlight_line(line, syntax_set()).ok()?;
        // 4. 转换样式并收集 spans
    }
}
```

#### 4. 语言别名处理

```rust
fn find_syntax(lang: &str) -> Option<&'static SyntaxReference> {
    // 别名映射（two_face 无法直接解析的）
    let patched = match lang {
        "csharp" | "c-sharp" => "c#",
        "golang" => "go",
        "python3" => "python",
        "shell" => "bash",
        _ => lang,
    };
    // 尝试多种查找策略：token -> name -> case-insensitive name -> extension
}
```

### ANSI 主题特殊处理

Syntect/bat 使用 alpha 通道编码 ANSI 调色板语义：

```rust
const ANSI_ALPHA_INDEX: u8 = 0x00;    // a=0 => 索引 ANSI 调色板（通过 RGB 负载）
const ANSI_ALPHA_DEFAULT: u8 = 0x01;  // a=1 => 终端默认颜色
const OPAQUE_ALPHA: u8 = 0xFF;        // a=255 => 普通 RGB

fn convert_syntect_color(color: SyntectColor) -> Option<RtColor> {
    match color.a {
        ANSI_ALPHA_INDEX => Some(ansi_palette_color(color.r)),  // color.r 存储调色板索引
        ANSI_ALPHA_DEFAULT => None,  // 使用终端默认前景色
        OPAQUE_ALPHA => Some(RtColor::Rgb(color.r, color.g, color.b)),
        _ => Some(RtColor::Rgb(color.r, color.g, color.b)),
    }
}
```

### 样式转换

```rust
fn convert_style(syn_style: SyntectStyle) -> Style {
    let mut rt_style = Style::default();
    if let Some(fg) = convert_syntect_color(syn_style.foreground) {
        rt_style = rt_style.fg(fg);
    }
    // 背景色被故意跳过，避免覆盖终端背景
    if syn_style.font_style.contains(FontStyle::BOLD) {
        rt_style.add_modifier |= Modifier::BOLD;
    }
    // 斜体和下划线被故意抑制（终端渲染问题）
    rt_style
}
```

## 关键代码路径与文件引用

### 内部依赖

| 文件 | 用途 |
|------|------|
| `codex-rs/tui/src/terminal_palette.rs` | 终端调色板查询（`default_bg()` 用于自适应主题） |
| `codex-rs/tui/src/color.rs` | 颜色工具（`is_light()` 判断背景亮度） |

### 外部调用方

| 文件 | 调用函数 | 用途 |
|------|----------|------|
| `markdown_render.rs` | `highlight_code_to_lines` | Markdown 代码块高亮 |
| `diff_render.rs` | `highlight_code_to_styled_spans`, `diff_scope_background_rgbs`, `exceeds_highlight_limits` | Diff 语法高亮 |
| `exec_cell/render.rs` | `highlight_bash_to_lines` | 执行单元格 bash 高亮 |
| `bottom_pane/approval_overlay.rs` | `highlight_bash_to_lines` | 审批覆盖层命令高亮 |
| `theme_picker.rs` | `highlight_code_to_styled_spans`, `current_syntax_theme`, `set_syntax_theme`, `list_available_themes`, `configured_theme_name`, `resolve_theme_by_name` | 主题选择器 |
| `lib.rs` | `set_theme_override`, `validate_theme_name` | 初始化和配置验证 |
| `app.rs` | `resolve_theme_by_name`, `set_syntax_theme`, `adaptive_default_theme_name` | 应用主题切换 |

### 关键常量

```rust
const MAX_HIGHLIGHT_BYTES: usize = 512 * 1024;  // 512 KB
const MAX_HIGHLIGHT_LINES: usize = 10_000;      // 1万行
```

### 32 种内置主题列表

```rust
const BUILTIN_THEME_NAMES: &[&str] = &[
    "1337", "ansi", "base16", "base16-256", "base16-eighties-dark",
    "base16-mocha-dark", "base16-ocean-dark", "base16-ocean-light",
    "catppuccin-frappe", "catppuccin-latte", "catppuccin-macchiato", "catppuccin-mocha",
    "coldark-cold", "coldark-dark", "dark-neon", "dracula", "github",
    "gruvbox-dark", "gruvbox-light", "inspired-github", "monokai-extended",
    "monokai-extended-bright", "monokai-extended-light", "monokai-extended-origin",
    "nord", "one-half-dark", "one-half-light", "solarized-dark", "solarized-light",
    "sublime-snazzy", "two-dark", "zenburn",
];
```

## 依赖与外部交互

### 外部 Crate

| Crate | 用途 |
|-------|------|
| `syntect` | 核心语法高亮引擎（TextMate 语法兼容） |
| `two_face` | 提供扩展的语法集（~250 语言）和 32 种主题包 |
| `ratatui` | 终端 UI 库（`Color`, `Style`, `Line`, `Span`） |

### 主题文件格式

- 自定义主题使用 `.tmTheme` 格式（TextMate/Sublime Text 主题格式）
- 存放位置：`{CODEX_HOME}/themes/{name}.tmTheme`
- 通过 `ThemeSet::get_theme()` 加载解析

### 配置集成

- 主题配置通过 `set_theme_override` 在启动时应用
- 配置验证通过 `validate_theme_name` 提供用户友好的警告
- 主题选择器通过 `list_available_themes` 获取可用主题列表

## 风险、边界与改进建议

### 已知风险

1. **全局状态管理**
   - 使用 `OnceLock` 和 `RwLock` 管理全局主题状态
   - 虽然 `RwLock` 允许多读，但写操作（主题切换）会阻塞所有读操作
   - 在极端高频渲染场景下可能成为瓶颈

2. **内存使用**
   - `SyntaxSet` 包含约 250 种语言的语法定义，占用较大内存
   - 每个自定义主题加载后会克隆到 `RwLock` 中

3. **回退行为不一致**
   - 超大输入回退到纯文本，但纯文本不保留原始样式信息
   - 某些语言识别失败时回退行为可能与用户预期不同

### 边界情况

1. **CRLF 处理**：代码明确处理 Windows 风格换行符，确保 `\r` 不会残留在输出中
2. **空输入处理**：空字符串返回单行空 Line，而非空 Vec
3. **尾部换行**：使用 `lines()` 而非 `split('\n')` 避免尾部空行幻象
4. **Poisoned Lock**：所有锁获取都处理 poison 情况，确保程序不会因 panic 而永久锁定

### 测试覆盖

模块包含全面的测试（约 35 个测试用例）：
- 语法高亮正确性测试
- 样式转换测试（包括 ANSI 主题特殊处理）
- 主题解析和验证测试
- 自定义主题加载测试
- 边界情况测试（大输入、多行、CRLF 等）
- 快照测试（`ansi_family_foreground_palette`）

### 改进建议

1. **性能优化**
   - 考虑使用 `arc-swap` 或类似模式实现无锁主题切换
   - 对高频渲染场景（如快速滚动）考虑缓存高亮结果

2. **功能扩展**
   - 支持行内代码高亮（目前仅支持代码块）
   - 支持更多自定义主题目录（目前仅支持 `{CODEX_HOME}/themes`）
   - 支持主题热重载（文件系统监听）

3. **错误处理**
   - 当前自定义主题解析失败仅返回警告，可考虑提供更详细的错误信息
   - 可考虑添加主题验证工具（独立命令）

4. **代码组织**
   - 模块已接近 1500 行，可考虑将主题管理和语法高亮拆分为独立子模块
   - 测试代码较多，可考虑移至 `tests/` 目录

### 安全注意事项

- 自定义主题文件解析使用 `ThemeSet::get_theme()`，依赖 syntect 的解析安全性
- 文件路径拼接使用标准库 `Path::join`，避免路径遍历
- 输入大小限制有效防止恶意大输入导致的 DoS
