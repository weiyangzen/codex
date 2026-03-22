# codex-rs/tui/tests 目录研究文档

## 1. 场景与职责

### 1.1 目录定位

`codex-rs/tui/tests` 是 Codex TUI（Terminal User Interface）模块的集成测试目录，负责验证 TUI 的核心功能、终端渲染逻辑、PTY 交互以及配置管理等功能。该测试目录与单元测试不同，专注于端到端的集成场景验证。

### 1.2 核心职责

1. **集成测试聚合**：作为所有集成测试的入口，通过 `all.rs` 聚合各个子模块测试
2. **VT100 终端模拟测试**：使用 VT100 模拟器验证终端渲染逻辑，无需真实终端环境
3. **PTY 交互测试**：通过伪终端（Pseudo Terminal）测试 TUI 与真实进程交互
4. **回归测试**：捕获并防止已知问题的再次发生（如启动崩溃、状态指示器问题等）

### 1.3 测试分类

| 测试类型 | 说明 | 代表文件 |
|---------|------|---------|
| VT100 模拟测试 | 使用 vt100 crate 模拟终端，验证渲染输出 | `vt100_history.rs`, `vt100_live_commit.rs` |
| PTY 集成测试 | 通过 PTY 与真实 codex 进程交互 | `model_availability_nux.rs`, `no_panic_on_startup.rs` |
| 单元式集成测试 | 测试特定组件的公共接口 | `status_indicator.rs` |

---

## 2. 功能点目的

### 2.1 测试模块详细说明

#### 2.1.1 `all.rs` - 测试入口

**功能**：单一集成测试二进制文件的入口点，聚合所有子模块测试。

**关键设计**：
- 使用 `#[cfg(feature = "vt100-tests")]` 条件编译控制 VT100 相关测试
- 通过 `mod suite` 聚合所有子模块
- 保留 `codex_cli` 作为 dev-dependency 以确保 cargo-shear 不会误删

```rust
// Single integration test binary that aggregates all test modules.
#[cfg(feature = "vt100-tests")]
mod test_backend;

#[allow(unused_imports)]
use codex_cli as _; // Keep dev-dep for cargo-shear

mod suite;
```

#### 2.1.2 `suite/mod.rs` - 子模块聚合

**功能**：聚合所有独立的集成测试模块。

**包含模块**：
- `model_availability_nux` - 模型可用性 NUX（New User Experience）测试
- `no_panic_on_startup` - 启动时崩溃回归测试
- `status_indicator` - 状态指示器组件测试
- `vt100_history` - 历史记录插入 VT100 测试
- `vt100_live_commit` - 实时提交 VT100 测试

#### 2.1.3 `suite/vt100_history.rs` - 历史记录渲染测试

**功能**：验证 `insert_history_lines` 函数在各种场景下的正确性。

**测试场景**：

| 测试函数 | 目的 |
|---------|------|
| `basic_insertion_no_wrap` | 基础插入，无换行 |
| `long_token_wraps` | 长文本自动换行，验证字符不丢失 |
| `emoji_and_cjk` | Emoji 和 CJK（中日韩）字符处理 |
| `mixed_ansi_spans` | 混合 ANSI 样式的 span 处理 |
| `cursor_restoration` | 光标位置恢复验证 |
| `word_wrap_no_mid_word_split` | 单词换行不截断单词 |
| `em_dash_and_space_word_wrap` | 特殊标点（em-dash）换行处理 |

**技术实现**：
- 使用 `VT100Backend` 创建虚拟终端
- 通过 `TestScenario` 结构体封装测试逻辑
- 使用 `assert_contains!` 宏验证屏幕内容

```rust
struct TestScenario {
    term: codex_tui::custom_terminal::Terminal<VT100Backend>,
}

impl TestScenario {
    fn new(width: u16, height: u16, viewport: Rect) -> Self {
        let backend = VT100Backend::new(width, height);
        let mut term = codex_tui::custom_terminal::Terminal::with_options(backend)
            .expect("failed to construct terminal");
        term.set_viewport_area(viewport);
        Self { term }
    }
}
```

#### 2.1.4 `suite/vt100_live_commit.rs` - 实时提交测试

**功能**：验证 `RowBuilder` 的 `drain_commit_ready` 机制，确保在缓冲区溢出时正确提交旧行。

**核心测试**：`live_001_commit_on_overflow`
- 构建 5 行文本，每行宽度 20
- 保留最近 3 行在 live ring 中
- 验证前 2 行被正确提交到历史记录

```rust
let mut rb = codex_tui::live_wrap::RowBuilder::new(20);
rb.push_fragment("one\n");
rb.push_fragment("two\n");
rb.push_fragment("three\n");
rb.push_fragment("four\n");
rb.push_fragment("five\n");

let commit_rows = rb.drain_commit_ready(3);
```

#### 2.1.5 `suite/model_availability_nux.rs` - 模型可用性提示测试

**功能**：验证恢复会话时不会消耗模型可用性 NUX 计数。

**测试流程**：
1. 创建临时 CODEX_HOME 目录
2. 修改模型目录，为第一个模型添加 `availability_nux` 配置
3. 配置 config.toml，设置已显示计数为 1
4. 使用 `codex exec` 创建会话种子
5. 使用 `codex resume --last` 恢复会话
6. 验证 config.toml 中的计数仍保持为 1（未被消耗）

**关键技术**：
- 使用 `codex_utils_pty::spawn_pty_process` 启动 PTY 进程
- 模拟光标位置查询响应（`ESC[6n` → `ESC[1;1R`）
- 超时控制和进程终止管理

```rust
let spawned = codex_utils_pty::spawn_pty_process(
    codex.to_string_lossy().as_ref(),
    &args,
    &repo_root,
    &env,
    &None,
    codex_utils_pty::TerminalSize::default(),
).await?;
```

#### 2.1.6 `suite/no_panic_on_startup.rs` - 启动崩溃回归测试

**功能**：回归测试，验证当 `rules` 是文件而非目录时，TUI 不会 panic。

**关联 Issue**：https://github.com/openai/codex/issues/8803

**测试逻辑**：
1. 创建临时目录作为 CODEX_HOME
2. 将 `rules` 创建为文件（而非目录）
3. 启动 codex CLI
4. 验证退出码非 0（表示错误）
5. 验证输出包含预期的错误信息

**注意**：该测试被标记为 `#[ignore = "TODO(mbolin): flaky")]`，表示存在不稳定性。

#### 2.1.7 `suite/status_indicator.rs` - 状态指示器测试

**功能**：验证 `StatusIndicatorWidget` 正确清理 ANSI 转义序列。

**测试方法**：
- 使用 `codex_ansi_escape::ansi_escape_line` 函数
- 验证 ANSI 红色文本（`\x1b[31mRED\x1b[0m`）被正确处理
- 确认输出不包含原始转义字节

```rust
let text_in_ansi_red = "\x1b[31mRED\x1b[0m";
let line = ansi_escape_line(text_in_ansi_red);
let combined: String = line.spans.iter()
    .map(|span| span.content.to_string())
    .collect();
assert_eq!(combined, "RED");
```

### 2.2 测试基础设施

#### 2.2.1 `test_backend.rs` - VT100 测试后端

**功能**：为测试提供 VT100 模拟终端后端。

**实现特点**：
- 包装 `CrosstermBackend<vt100::Parser>`
- 避免调用写入 stdout 的 crossterm 方法
- 提供 `vt100()` 方法访问底层解析器以验证屏幕状态

```rust
pub struct VT100Backend {
    crossterm_backend: CrosstermBackend<vt100::Parser>,
}

impl VT100Backend {
    pub fn new(width: u16, height: u16) -> Self {
        crossterm::style::force_color_output(true);
        Self {
            crossterm_backend: CrosstermBackend::new(vt100::Parser::new(height, width, 0)),
        }
    }

    pub fn vt100(&self) -> &vt100::Parser {
        self.crossterm_backend.writer()
    }
}
```

#### 2.2.2 `fixtures/oss-story.jsonl` - 测试夹具

**功能**：记录真实 TUI 会话的事件日志，用于回放测试。

**内容结构**：
- 时间戳（ts）
- 方向（dir）：`to_tui` / `from_tui`
- 事件类型（kind）：`key_event`, `app_event`, `codex_event`, `insert_history`, `log_line`
- 事件详情（event/payload/variant）

**用途**：
- 理解 TUI 事件流
- 开发回放/调试工具
- 验证事件处理逻辑

---

## 3. 具体技术实现

### 3.1 VT100 测试架构

```
┌─────────────────────────────────────────────────────────────┐
│                     Test Function                           │
│  (e.g., vt100_history.rs::basic_insertion_no_wrap)         │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                   TestScenario                              │
│  - 创建 VT100Backend                                        │
│  - 初始化 CustomTerminal                                    │
│  - 设置 viewport_area                                       │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                  VT100Backend                               │
│  - 包装 CrosstermBackend<vt100::Parser>                     │
│  - 实现 ratatui::backend::Backend trait                     │
│  - 提供 vt100() 访问屏幕状态                                │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│              vt100::Parser (external crate)                 │
│  - 解析 ANSI 转义序列                                       │
│  - 维护屏幕缓冲区状态                                       │
│  - 提供 screen().contents() 等查询方法                      │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 PTY 测试架构

```
┌─────────────────────────────────────────────────────────────┐
│                    Test Function                            │
│  (e.g., model_availability_nux.rs)                          │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│          codex_utils_pty::spawn_pty_process()               │
│  - 创建伪终端                                               │
│  - 启动 codex 进程                                          │
│  - 返回 SpawnedProcess（包含 session, stdout_rx, etc）      │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                   SpawnedProcess                            │
│  - session: ProcessHandle（PTY 会话控制）                   │
│  - stdout_rx: 标准输出接收器                                │
│  - stderr_rx: 标准错误接收器                                │
│  - exit_rx: 进程退出码接收器                                │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│              combine_output_receivers()                     │
│  - 合并 stdout/stderr 到单一广播接收器                      │
│  - 便于统一处理输出                                         │
└─────────────────────────────────────────────────────────────┘
```

### 3.3 关键数据结构

#### 3.3.1 `RowBuilder`（live_wrap.rs）

```rust
pub struct RowBuilder {
    target_width: usize,
    current_line: String,  // 当前逻辑行缓冲区
    rows: Vec<Row>,        // 已生成的行
}

pub struct Row {
    pub text: String,
    pub explicit_break: bool,  // 是否显式换行（vs 自动换行）
}
```

**核心方法**：
- `push_fragment(&str)` - 添加文本片段，自动处理换行
- `drain_commit_ready(max_keep)` - 保留最近 max_keep 行，返回溢出的行
- `set_width(width)` - 动态调整宽度，重新包装所有文本

#### 3.3.2 `Terminal`（custom_terminal.rs）

```rust
pub struct Terminal<B: Backend + Write> {
    backend: B,
    buffers: [Buffer; 2],  // 双缓冲
    current: usize,        // 当前缓冲区索引
    hidden_cursor: bool,
    viewport_area: Rect,   // 视口区域
    last_known_screen_size: Size,
    last_known_cursor_pos: Position,
    visible_history_rows: u16,  // 视口上方可见历史行数
}
```

#### 3.3.3 `RtOptions`（wrapping.rs）

```rust
pub struct RtOptions<'a> {
    pub width: usize,
    pub line_ending: textwrap::LineEnding,
    pub initial_indent: Line<'a>,
    pub subsequent_indent: Line<'a>,
    pub break_words: bool,
    pub wrap_algorithm: textwrap::WrapAlgorithm,
    pub word_separator: textwrap::WordSeparator,
    pub word_splitter: textwrap::WordSplitter,
}
```

### 3.4 URL 感知换行算法

**问题**：标准 `textwrap` 在 `/` 和 `-` 处断行，破坏 URL 可点击性。

**解决方案**：

```rust
pub fn adaptive_wrap_line<'a>(line: &'a Line<'a>, base: RtOptions<'a>) -> Vec<Line<'a>> {
    let selected = if line_contains_url_like(line) {
        url_preserving_wrap_options(base)
    } else {
        base
    };
    word_wrap_line(line, selected)
}

fn url_preserving_wrap_options<'a>(opts: RtOptions<'a>) -> RtOptions<'a> {
    opts.word_separator(textwrap::WordSeparator::AsciiSpace)
        .word_splitter(textwrap::WordSplitter::Custom(split_non_url_word))
        .break_words(false)
}

fn split_non_url_word(word: &str) -> Vec<usize> {
    if is_url_like_token(word) {
        return Vec::new();  // URL 不分割
    }
    word.char_indices().skip(1).map(|(idx, _)| idx).collect()
}
```

**URL 检测规则**：
- 绝对 URL（`https://...`, `ftp://...`）
- 裸域名（`example.com/path`, `localhost:3000`）
- IPv4 地址（`192.168.1.1:8080/health`）

### 3.5 历史记录插入流程

```rust
pub fn insert_history_lines<B>(
    terminal: &mut Terminal<B>,
    lines: Vec<Line>,
) -> io::Result<()>
where
    B: Backend + Write,
{
    // 1. 预包装行（URL 感知）
    let wrap_width = area.width.max(1) as usize;
    for line in &lines {
        let line_wrapped = if line_contains_url_like(line) && !mixed {
            vec![line.clone()]
        } else {
            adaptive_wrap_line(line, RtOptions::new(wrap_width))
        };
        wrapped.extend(line_wrapped);
    }

    // 2. 调整滚动区域
    queue!(writer, SetScrollRegion(1..area.top()))?;

    // 3. 写入包装后的行
    for line in wrapped {
        queue!(writer, Print("\r\n"))?;
        write_spans(writer, line.spans.iter())?;
    }

    // 4. 恢复滚动区域和光标
    queue!(writer, ResetScrollRegion)?;
    queue!(writer, MoveTo(last_cursor_pos.x, last_cursor_pos.y))?;
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 测试文件结构

```
codex-rs/tui/tests/
├── all.rs                              # 测试入口
├── test_backend.rs                     # VT100Backend 包装器
├── fixtures/
│   └── oss-story.jsonl                 # 会话事件夹具
└── suite/
    ├── mod.rs                          # 子模块聚合
    ├── model_availability_nux.rs       # NUX 计数测试
    ├── no_panic_on_startup.rs          # 启动崩溃回归测试
    ├── status_indicator.rs             # 状态指示器测试
    ├── vt100_history.rs                # 历史记录 VT100 测试
    └── vt100_live_commit.rs            # 实时提交 VT100 测试
```

### 4.2 被测源代码文件

| 测试文件 | 被测源代码 | 测试重点 |
|---------|-----------|---------|
| `vt100_history.rs` | `src/insert_history.rs` | 历史记录插入、换行、ANSI 处理 |
| `vt100_live_commit.rs` | `src/live_wrap.rs` | RowBuilder、drain_commit_ready |
| `status_indicator.rs` | `codex-ansi-escape crate` | ANSI 转义序列清理 |
| `model_availability_nux.rs` | `src/lib.rs`, `src/app.rs` | 会话恢复、配置管理 |
| `no_panic_on_startup.rs` | `src/lib.rs` | 错误处理、启动流程 |

### 4.3 关键依赖库

| 库 | 用途 | 版本 |
|---|------|------|
| `vt100` | VT100 终端模拟 | workspace |
| `ratatui` | TUI 框架 | workspace |
| `crossterm` | 跨平台终端控制 | workspace |
| `textwrap` | 文本换行 | workspace |
| `codex-utils-pty` | PTY 进程管理 | workspace |
| `codex-utils-cargo-bin` | 测试二进制文件定位 | workspace |

### 4.4 代码路径追踪

**VT100 测试路径**：
```
test function
  → TestScenario::new()
    → VT100Backend::new()
      → CrosstermBackend::new(vt100::Parser::new(...))
    → Terminal::with_options(backend)
  → scenario.run_insert(lines)
    → insert_history_lines(&mut term, lines)
      → adaptive_wrap_line() [wrapping.rs]
      → queue!(writer, SetScrollRegion(...))
      → write_spans() [insert_history.rs]
  → term.backend().vt100().screen().contents()
    → 验证屏幕内容
```

**PTY 测试路径**：
```
test function
  → codex_utils_cargo_bin::cargo_bin("codex")
    → 解析 CARGO_BIN_EXE_* 环境变量
    → Bazel runfiles 解析（如适用）
  → codex_utils_pty::spawn_pty_process(...)
    → 创建 PTY
    → 启动 codex 进程
  → combine_output_receivers(stdout_rx, stderr_rx)
  → 循环读取输出
    → 检测 ESC[6n（光标位置查询）
    → 响应 ESC[1;1R
  → 验证退出码和输出内容
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

```
codex-rs/tui/tests/
├── codex-tui (被测库)
│   ├── codex-core
│   ├── codex-protocol
│   ├── codex-app-server-protocol
│   └── ...
├── codex-utils-pty (PTY 工具)
├── codex-utils-cargo-bin (二进制定位)
└── codex-cli (dev-dependency，用于集成测试)
```

### 5.2 外部 crate 依赖

**VT100 测试专用**：
- `vt100` - VT100 终端模拟器
- `ratatui` - TUI 框架（带 `scrolling-regions`, `unstable-backend-writer` 等特性）

**PTY 测试专用**：
- `tokio` - 异步运行时（带 `rt-multi-thread`, `process`, `time` 等特性）
- `tempfile` - 临时目录管理
- `serde_json` / `toml` - 配置解析

**通用测试**：
- `anyhow` - 错误处理
- `pretty_assertions` - 更好的断言输出

### 5.3 环境交互

**Cargo 环境变量**：
- `CARGO_BIN_EXE_codex` - codex 二进制文件路径
- `CARGO_MANIFEST_DIR` - 测试清单目录

**Bazel Runfiles**（Bazel 构建时）：
- `RUNFILES_MANIFEST_ONLY` - 仅使用 manifest 策略
- `RUNFILES_MANIFEST_FILE` - runfiles manifest 路径
- `BAZEL_PACKAGE` - Bazel 包名

**测试专用环境变量**：
- `CODEX_HOME` - Codex 配置主目录
- `OPENAI_API_KEY` - API 密钥（测试中可使用 dummy 值）
- `CODEX_RS_SSE_FIXTURE` - SSE 夹具文件路径

### 5.4 平台限制

| 测试 | Windows 支持 | 说明 |
|-----|-------------|------|
| VT100 测试 | ✅ | 纯模拟，无平台依赖 |
| PTY 测试 | ❌ | `run_codex_cli()` 明确跳过 Windows |

**Windows 跳过逻辑**：
```rust
// run_codex_cli() does not work on Windows due to PTY limitations.
if cfg!(windows) {
    return Ok(());
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 测试不稳定性

**问题**：`no_panic_on_startup` 测试被标记为 `#[ignore]`，原因是 flaky。

```rust
#[tokio::test]
#[ignore = "TODO(mbolin): flaky"]
async fn malformed_rules_should_not_panic() -> anyhow::Result<()> {
```

**可能原因**：
- 临时目录作为工作目录导致测试挂起（代码中有相关 TODO）
- PTY 输出时序问题
- 进程启动竞争条件

#### 6.1.2 Windows 平台覆盖不足

**问题**：PTY 测试完全跳过 Windows，导致 Windows 平台的 TUI 启动流程缺乏自动化测试。

**影响**：
- Windows 特定的路径处理、权限问题难以捕获
- ConPTY 行为差异无法验证

#### 6.1.3 测试夹具维护

**问题**：`fixtures/oss-story.jsonl` 是 1000+ 行的事件日志，格式变更时可能需要更新。

**风险**：
- 事件格式变更导致夹具失效
- 夹具文件过大，增加仓库体积

### 6.2 边界情况

#### 6.2.1 VT100 测试边界

| 边界情况 | 处理方式 |
|---------|---------|
| 零宽度字符 | `display_width()` 函数特殊处理 |
| OSC 转义序列 | 从宽度计算中剥离 |
| 宽字符（CJK） | `UnicodeWidthChar::width()` 计算 |
| 屏幕边界 | `take_prefix_by_width()` 处理 |

#### 6.2.2 URL 检测边界

**误报风险**：
- `src/main.rs` 等文件路径可能被误判为 URL
- 解决方案：要求主机部分为有效域名、IPv4 或 localhost

**漏报风险**：
- IPv6 地址（`[::1]:8080`）不被处理
- 无路径的裸域名（`example.com`）需要 `www.` 前缀

#### 6.2.3 换行边界

**问题**：`word_wrap_line` 在处理 `Cow::Owned` 时，需要映射回原始字节范围。

**复杂性**：
- textwrap 可能在连字符处插入惩罚字符（`-`）
- 需要区分合成字符和源文本字符

### 6.3 改进建议

#### 6.3.1 测试稳定性改进

**建议 1**：修复 `no_panic_on_startup` 测试的不稳定性
- 使用固定的临时目录命名
- 增加重试机制
- 使用更可靠的进程同步原语

**建议 2**：增加 Windows PTY 测试支持
- 使用 `conpty` 或 `windows-sys` 的 ConPTY API
- 或者使用 WSL 进行测试

#### 6.3.2 测试覆盖率改进

**建议 3**：增加更多 VT100 测试场景
- 多行 URL 处理
- 极端宽度（1 列、65535 列）
- 大量历史记录插入性能测试

**建议 4**：增加交互式测试
- 键盘输入序列测试
- 鼠标事件测试
- 窗口大小变化测试

#### 6.3.3 代码结构改进

**建议 5**：提取通用测试工具
- 将 `TestScenario` 移到独立的测试工具模块
- 提供更易用的屏幕内容断言宏

**建议 6**：改进夹具管理
- 使用代码生成或压缩减小夹具体积
- 提供夹具更新工具

#### 6.3.4 文档改进

**建议 7**：增加测试编写指南
- 如何添加新的 VT100 测试
- 如何调试失败的 PTY 测试
- 测试命名和分类规范

### 6.4 技术债务

| 项目 | 位置 | 说明 |
|-----|------|------|
| Windows WinAPI 支持 | `insert_history.rs` | `SetScrollRegion` 和 `ResetScrollRegion` 的 WinAPI 执行标记为 TODO |
| 路径规范化 | `cargo-bin/src/lib.rs` | `normalize_runfile_path` 可能需要更健壮的实现 |

---

## 7. 总结

`codex-rs/tui/tests` 目录提供了 Codex TUI 模块的核心集成测试能力，涵盖：

1. **VT100 模拟测试**：无需真实终端即可验证渲染逻辑
2. **PTY 集成测试**：验证与真实 codex 进程的交互
3. **回归测试**：防止已知问题再次发生

测试架构设计良好，通过 `VT100Backend` 和 `codex_utils_pty` 提供了强大的测试基础设施。主要风险在于 Windows 平台覆盖不足和部分测试的不稳定性，建议优先解决这些问题以提高测试可靠性。
