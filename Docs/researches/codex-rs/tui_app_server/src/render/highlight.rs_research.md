# highlight.rs 研究文档

## 场景与职责

`highlight.rs` 是 TUI 应用服务器的语法高亮引擎，负责为代码块提供语法高亮显示。它是 TUI 渲染系统的核心组件之一，主要服务于：

1. **Markdown 代码块渲染** - 在 `markdown_render.rs` 中为 fenced code blocks 提供语法高亮
2. **Diff 渲染** - 在 `diff_render.rs` 中为代码差异提供语法高亮
3. **执行单元渲染** - 在 `exec_cell/render.rs` 中为 bash 命令提供高亮
4. **主题选择器** - 在 `theme_picker.rs` 中提供主题预览功能
5. **审批覆盖层** - 在 `bottom_pane/approval_overlay.rs` 中高亮显示 shell 命令

该模块通过包装 [syntect](https://github.com/trishume/syntect) 语法高亮库和 [two_face](https://github.com/CosmicHorrorDev/two-face) 语法/主题包，提供约 250 种语言的语法高亮支持和 32 种内置颜色主题。

## 功能点目的

### 1. 语法高亮核心功能
- **语言识别**：支持 250+ 编程语言的自动识别和语法解析
- **主题应用**：将 TextMate 主题样式应用到语法标记
- **安全限制**：对超大输入（>512KB 或 >10000 行）进行保护性降级

### 2. 主题管理系统
- **32 种内置主题**：包括 Catppuccin、Dracula、GitHub、Gruvbox、Nord、Solarized 等流行主题
- **自定义主题支持**：从 `{CODEX_HOME}/themes/*.tmTheme` 加载用户自定义主题
- **自适应默认主题**：根据终端背景亮度自动选择暗色/亮色主题
- **运行时主题切换**：支持主题选择器的实时预览功能

### 3. ANSI 主题支持
- 特殊处理 `ansi`、`base16`、`base16-256` 等 ANSI 调色板主题
- 通过 alpha 通道编码识别 ANSI 调色板语义（与 bat 兼容）
- 将 ANSI 索引正确映射到 ratatui 的命名颜色

### 4. Diff 范围背景色提取
- 从主题中提取 `markup.inserted`/`markup.deleted` 或 `diff.inserted`/`diff.deleted` 范围的背景色
- 用于 `diff_render.rs` 的主题感知差异渲染

## 具体技术实现

### 关键数据结构

```rust
// 全局单例（进程级）
static SYNTAX_SET: OnceLock<SyntaxSet>           // 语法数据库，初始化后不可变
static THEME: OnceLock<RwLock<Theme>>            // 活动主题，运行时可通过读写锁切换
static THEME_OVERRIDE: OnceLock<Option<String>> // 用户配置的主题覆盖（写一次）
static CODEX_HOME: OnceLock<Option<PathBuf>>     // 自定义主题发现根目录

// Diff 范围背景色 RGB 值
pub(crate) struct DiffScopeBackgroundRgbs {
    pub inserted: Option<(u8, u8, u8)>,
    pub deleted: Option<(u8, u8, u8)>,
}

// 主题条目（用于主题选择器）
pub(crate) struct ThemeEntry {
    pub name: String,      // kebab-case 标识符
    pub is_custom: bool,   // 是否来自 .tmTheme 文件
}
```

### 核心流程

#### 1. 主题初始化流程
```
set_theme_override(name, codex_home)
  ├── validate_theme_name(name, codex_home)     // 验证主题名称有效性
  ├── THEME_OVERRIDE.set(name)                  // 持久化用户偏好
  ├── CODEX_HOME.set(codex_home)                // 设置主题搜索路径
  └── set_syntax_theme(resolve_theme_with_override(...))  // 设置运行时主题
```

#### 2. 主题解析流程
```
resolve_theme_with_override(name, codex_home)
  ├── 尝试内置主题: parse_theme_name(name) -> EmbeddedThemeName
  ├── 尝试自定义主题: load_custom_theme(name, codex_home)
  └── 回退到自适应默认: adaptive_default_theme_selection()
      └── 根据终端背景亮度选择 catppuccin-latte（亮色）或 catppuccin-mocha（暗色）
```

#### 3. 语法高亮流程
```
highlight_code_to_lines(code, lang)
  ├── highlight_to_line_spans(code, lang)
  │   ├── 安全检查: 检查代码大小和行数限制
  │   ├── find_syntax(lang)                    // 语言识别（含别名补丁）
  │   ├── HighlightLines::new(syntax, theme)   // 创建高亮器
  │   └── 逐行高亮: highlight_line() -> convert_style() -> Span
  └── 失败时回退到纯文本行
```

#### 4. 样式转换（syntect -> ratatui）
```
convert_syntect_color(color)
  ├── alpha == 0x00: ANSI 调色板索引（通过 color.r）
  ├── alpha == 0x01: 终端默认前景色（返回 None）
  └── alpha == 0xFF: RGB 真彩色

convert_style(syn_style)
  ├── 转换前景色（背景色被故意跳过）
  ├── 应用粗体修饰符
  └── 故意跳过斜体和下划线（终端渲染质量问题）
```

### 关键常量

```rust
const MAX_HIGHLIGHT_BYTES: usize = 512 * 1024;   // 512KB 大小限制
const MAX_HIGHLIGHT_LINES: usize = 10_000;       // 10000 行限制

// ANSI alpha 编码（与 bat 兼容）
const ANSI_ALPHA_INDEX: u8 = 0x00;    // alpha=0 表示 ANSI 调色板索引
const ANSI_ALPHA_DEFAULT: u8 = 0x01;  // alpha=1 表示终端默认颜色
const OPAQUE_ALPHA: u8 = 0xFF;        // alpha=255 表示 RGB 真彩色
```

### 语言别名补丁

```rust
fn find_syntax(lang: &str) -> Option<&'static SyntaxReference> {
    let patched = match lang {
        "csharp" | "c-sharp" => "c#",
        "golang" => "go",
        "python3" => "python",
        "shell" => "bash",
        _ => lang,
    };
    // 尝试多种匹配策略...
}
```

## 关键代码路径与文件引用

### 内部依赖
| 文件 | 依赖类型 | 说明 |
|------|---------|------|
| `terminal_palette.rs` | 被调用 | 自适应默认主题选择时检测终端背景色 |
| `color.rs` | 被调用 | `is_light()` 判断颜色亮度 |

### 外部调用方
| 文件 | 调用函数 | 用途 |
|------|---------|------|
| `lib.rs:1263` | `set_theme_override()` | 启动时配置语法高亮主题 |
| `markdown_render.rs:8` | `highlight_code_to_lines()` | Markdown 代码块高亮 |
| `diff_render.rs:81-84` | `highlight_code_to_styled_spans()`, `diff_scope_background_rgbs()` | Diff 语法高亮和主题背景色 |
| `exec_cell/render.rs:8` | `highlight_bash_to_lines()` | Bash 命令高亮 |
| `theme_picker.rs:36-37` | `highlight::list_available_themes()`, `highlight::set_syntax_theme()` | 主题选择器 |
| `bottom_pane/approval_overlay.rs:16` | `highlight_bash_to_lines()` | 审批命令高亮 |
| `app.rs:4659-4914` | `resolve_theme_by_name()`, `set_syntax_theme()` | 应用主题切换逻辑 |

### 测试覆盖
- 模块包含全面的单元测试（约 600 行测试代码）
- 使用 `insta` 进行快照测试验证 ANSI 主题调色板
- 测试覆盖：语言识别、样式转换、主题解析、自定义主题加载、边界条件

## 依赖与外部交互

### 外部 crate 依赖
| crate | 用途 |
|-------|------|
| `syntect` | 核心语法高亮引擎（TextMate 语法兼容） |
| `two_face` | 预打包的语法定义（~250 语言）和主题（32 主题） |
| `ratatui` | 终端 UI 样式和渲染类型 |

### syntect 集成细节
- 使用 `two_face::syntax::extra_newlines()` 获取扩展语法集
- 使用 `two_face::theme::extra()` 获取扩展主题集
- 使用 `HighlightLines` 进行增量式行高亮
- 使用 `LinesWithEndings` 处理不同换行符风格

### two_face 主题列表（32 个内置主题）
```
1337, ansi, base16, base16-256, base16-eighties-dark, base16-mocha-dark,
base16-ocean-dark, base16-ocean-light, catppuccin-frappe, catppuccin-latte,
catppuccin-macchiato, catppuccin-mocha, coldark-cold, coldark-dark,
dark-neon, dracula, github, gruvbox-dark, gruvbox-light, inspired-github,
monokai-extended, monokai-extended-bright, monokai-extended-light,
monokai-extended-origin, nord, one-half-dark, one-half-light,
solarized-dark, solarized-light, sublime-snazzy, two-dark, zenburn
```

## 风险、边界与改进建议

### 已知风险

1. **全局状态管理**
   - 使用 `OnceLock` 和 `RwLock` 组合管理主题状态
   - 风险：`THEME_OVERRIDE` 和 `CODEX_HOME` 只能设置一次，重复调用会被静默忽略
   - 缓解：代码中有 `tracing::debug!` 记录重复调用情况

2. **Poisoned Lock 处理**
   - 使用 `poisoned.into_inner()` 模式处理可能中毒的锁
   - 这会在 panic 后恢复，但可能导致状态不一致

3. **大输入处理**
   - 超过 512KB 或 10000 行的输入会被拒绝高亮
   - 调用方必须正确处理 `None` 回退到纯文本

4. **ANSI 主题编码依赖**
   - 依赖特定的 alpha 通道编码约定（与 bat 兼容）
   - 如果上游 two_face/syntect 主题格式变更，可能导致 ANSI 主题显示异常
   - 缓解：`ansi_themes_use_only_ansi_palette_colors` 测试会在构建时捕获

### 边界条件

1. **空输入处理**：空字符串返回单行空 Line
2. **CRLF 处理**：自动剥离 `\r` 字符，避免残留
3. **尾随换行符**：使用 `lines()` 而非 `split('\n')` 避免幽灵空行
4. **未知语言**：返回纯文本，不报错

### 改进建议

1. **性能优化**
   - 考虑对频繁高亮的相同语言使用 `HighlightLines` 缓存
   - 当前每次调用都重新创建 `HighlightLines` 实例

2. **主题热重载**
   - 当前自定义主题只在启动时扫描
   - 可考虑添加文件系统监视实现主题热重载

3. **错误报告**
   - 自定义主题解析失败时仅返回警告字符串
   - 可考虑添加更详细的诊断信息

4. **并发优化**
   - `theme_lock()` 每次读取都获取锁
   - 读多写少场景可考虑使用 `RwLock` 的读锁优化

5. **语言检测增强**
   - 当前别名补丁是硬编码的
   - 可考虑从配置文件加载额外别名映射
