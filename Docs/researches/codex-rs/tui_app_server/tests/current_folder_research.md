# codex-rs/tui_app_server/tests 目录研究文档

## 1. 场景与职责

### 1.1 目录定位

`codex-rs/tui_app_server/tests` 是 Codex TUI 应用服务器的集成测试目录，负责验证 TUI（Terminal User Interface）的核心功能、终端渲染逻辑、以及与 App Server 的交互行为。

### 1.2 核心职责

| 职责领域 | 说明 |
|---------|------|
| **集成测试** | 验证 TUI 与 App Server 的端到端交互 |
| **终端模拟测试** | 使用 VT100 模拟器测试终端渲染行为 |
| **回归测试** | 防止已修复问题（如 panic、内存泄漏）再次发生 |
| **架构约束测试** | 验证代码架构约束（如禁止直接依赖 Manager） |

### 1.3 测试分类

```
tests/
├── all.rs                          # 测试入口，聚合所有测试模块
├── manager_dependency_regression.rs # 架构约束回归测试
├── test_backend.rs                 # VT100 测试后端导出
├── fixtures/
│   └── oss-story.jsonl            # 测试固件：OSS 会话事件日志
└── suite/
    ├── mod.rs                      # 测试套件模块聚合
    ├── model_availability_nux.rs  # 模型可用性 NUX 测试
    ├── no_panic_on_startup.rs     # 启动稳定性回归测试
    ├── status_indicator.rs        # 状态指示器组件测试
    ├── vt100_history.rs           # VT100 历史记录渲染测试
    └── vt100_live_commit.rs       # VT100 实时提交测试
```

---

## 2. 功能点目的

### 2.1 测试入口 (`all.rs`)

**目的**：提供单一的集成测试二进制文件入口。

**关键逻辑**：
- 条件编译 `vt100-tests` feature 控制 VT100 相关测试
- 引入 `codex_cli` 作为 dev-dependency 保持依赖关系
- 聚合 `suite` 模块下的所有测试

```rust
#[cfg(feature = "vt100-tests")]
mod test_backend;

#[allow(unused_imports)]
use codex_cli as _; // Keep dev-dep for cargo-shear

mod suite;
```

### 2.2 Manager 依赖回归测试 (`manager_dependency_regression.rs`)

**目的**：防止运行时源代码意外引入对 `AuthManager` 和 `ThreadManager` 的直接依赖，确保架构分层清晰。

**测试逻辑**：
1. 递归扫描 `src/` 目录下所有 Rust 源文件
2. 检查禁止的模式：`AuthManager`、`ThreadManager`、`auth_manager(`、`thread_manager(`
3. 发现违规时输出详细错误信息

**架构意义**：
- 强制通过 `AppServerSession` 等抽象层访问管理功能
- 避免绕过正常的权限和生命周期控制

### 2.3 模型可用性 NUX 测试 (`model_availability_nux.rs`)

**目的**：验证恢复会话时不会重复消耗模型可用性 NUX（New User Experience）计数。

**测试场景**：
1. 创建临时 CODEX_HOME 目录
2. 构造自定义模型目录（包含 `availability_nux` 配置）
3. 使用 `codex exec` 创建会话种子
4. 使用 `codex resume --last` 恢复会话
5. 验证配置文件中 NUX 计数保持为 1（未被消耗）

**关键技术点**：
- 使用 `codex_utils_pty::spawn_pty_process` 在 PTY 中运行 TUI
- 处理终端光标位置查询（`ESC[6n` → `ESC[1;1R`）
- 超时控制和进程终止管理

### 2.4 启动稳定性测试 (`no_panic_on_startup.rs`)

**目的**：回归测试验证 Issue #8803 - 当 `rules` 是文件而非目录时，TUI 不应 panic。

**测试场景**：
1. 在 CODEX_HOME 中创建 `rules` 文件（而非目录）
2. 启动 codex CLI
3. 验证进程以非零退出码退出，而非 panic
4. 验证错误输出包含预期的错误信息

**状态**：当前标记为 `#[ignore = "TODO(mbolin): flaky"]`，存在稳定性问题。

### 2.5 状态指示器测试 (`status_indicator.rs`)

**目的**：验证 `StatusIndicatorWidget` 正确处理 ANSI 转义序列，避免将原始 `\x1b` 字节写入缓冲区。

**测试方法**：
- 使用 `codex_ansi_escape::ansi_escape_line` 处理带 ANSI 颜色的文本
- 验证输出中不包含原始转义字节
- 验证可见字符正确保留

### 2.6 VT100 历史记录测试 (`vt100_history.rs`)

**目的**：验证 `insert_history` 模块在各种场景下的终端渲染行为。

**测试用例矩阵**：

| 测试用例 | 验证点 |
|---------|--------|
| `basic_insertion_no_wrap` | 基本插入，无换行 |
| `long_token_wraps` | 长文本自动换行，字符不丢失 |
| `emoji_and_cjk` | Unicode 宽字符（Emoji、CJK）正确处理 |
| `mixed_ansi_spans` | ANSI 样式跨段合并 |
| `cursor_restoration` | 光标位置正确恢复 |
| `word_wrap_no_mid_word_split` | 单词边界换行，不截断单词 |
| `em_dash_and_space_word_wrap` | 特殊标点（em-dash）处理 |

**技术实现**：
- 使用 `VT100Backend` 模拟终端
- 通过 `vt100::Parser` 解析屏幕内容
- 验证字符位置、样式、光标状态

### 2.7 VT100 实时提交测试 (`vt100_live_commit.rs`)

**目的**：验证 `live_wrap` 模块的实时行构建和提交逻辑。

**测试场景**：
1. 构建 5 行显式文本（每行以 `\n` 结尾）
2. 保留最后 3 行在 live ring 中
3. 提交前 2 行到历史记录
4. 验证提交的行正确显示在屏幕上

---

## 3. 具体技术实现

### 3.1 VT100 测试后端架构

```rust
// src/test_backend.rs
pub struct VT100Backend {
    crossterm_backend: CrosstermBackend<vt100::Parser>,
}

impl VT100Backend {
    pub fn new(width: u16, height: u16) -> Self {
        crossterm::style::force_color_output(true);
        Self {
            crossterm_backend: CrosstermBackend::new(
                vt100::Parser::new(height, width, 0)
            ),
        }
    }

    pub fn vt100(&self) -> &vt100::Parser {
        self.crossterm_backend.writer()
    }
}
```

**设计要点**：
- 包装 `CrosstermBackend` 和 `vt100::Parser`
- 避免直接写入 stdout（所有输出到 Parser）
- 提供屏幕内容查询接口

### 3.2 历史记录插入机制 (`insert_history.rs`)

**核心函数**：`insert_history_lines`

**处理流程**：

```rust
pub fn insert_history_lines<B>(
    terminal: &mut Terminal<B>,
    lines: Vec<Line>,
) -> io::Result<()>
where
    B: Backend + Write,
{
    // 1. 预包装行（处理 URL、自适应换行）
    let wrap_width = area.width.max(1) as usize;
    for line in &lines {
        let line_wrapped = if line_contains_url_like(line) 
            && !line_has_mixed_url_and_non_url_tokens(line) {
            vec![line.clone()]  // URL 行保持完整，让终端处理
        } else {
            adaptive_wrap_line(line, RtOptions::new(wrap_width))
        };
    }

    // 2. 处理视口滚动（如果视口不在屏幕底部）
    if area.bottom() < screen_size.height {
        // 使用 DECSTBM 设置滚动区域
        // 使用 Reverse Index (RI, ESC M) 滚动
    }

    // 3. 在滚动区域内插入行
    queue!(writer, SetScrollRegion(1..area.top()))?;
    
    // 4. 逐行写入，处理多行 URL 的清除
    for line in wrapped {
        queue!(writer, Print("\r\n"))?;
        // 清除续行上的旧内容
        // 设置颜色
        // 写入 spans
    }

    // 5. 恢复光标位置
    queue!(writer, MoveTo(last_cursor_pos.x, last_cursor_pos.y))?;
}
```

**关键设计决策**：
- URL 行不硬换行，保留终端可点击性
- 使用 DECSTBM（Set Scroll Region）控制滚动范围
- Reverse Index (ESC M) 实现向上滚动
- 多行 URL 的续行预清除，避免残留字符

### 3.3 行包装器 (`live_wrap.rs`)

**数据结构**：

```rust
pub struct Row {
    pub text: String,
    pub explicit_break: bool,  // true = 显式换行符，false = 自动换行
}

pub struct RowBuilder {
    target_width: usize,
    current_line: String,  // 当前逻辑行缓冲区
    rows: Vec<Row>,        // 已完成的行
}
```

**核心算法**：

```rust
pub fn drain_commit_ready(&mut self, max_keep: usize) -> Vec<Row> {
    let display_count = self.rows.len() + 
        if self.current_line.is_empty() { 0 } else { 1 };
    
    if display_count <= max_keep {
        return Vec::new();
    }
    
    let to_commit = display_count - max_keep;
    let commit_count = to_commit.min(self.rows.len());
    
    // 移除并返回最旧的行
    let mut drained = Vec::with_capacity(commit_count);
    for _ in 0..commit_count {
        drained.push(self.rows.remove(0));
    }
    drained
}
```

### 3.4 自定义终端 (`custom_terminal.rs`)

**基于 ratatui::Terminal 的定制**：

```rust
pub struct Terminal<B: Backend + Write> {
    backend: B,
    buffers: [Buffer; 2],  // 双缓冲
    current: usize,
    hidden_cursor: bool,
    viewport_area: Rect,
    last_known_screen_size: Size,
    last_known_cursor_pos: Position,
    visible_history_rows: u16,  // 新增：可见历史行计数
}
```

**关键特性**：
- 双缓冲机制（current/previous）实现增量更新
- 视口区域跟踪（支持 inline 模式）
- 历史行插入计数（用于滚动管理）
- 自定义 `display_width` 处理 OSC 转义序列

**缓冲区差异算法**：

```rust
fn diff_buffers(a: &Buffer, b: &Buffer) -> Vec<DrawCommand> {
    // 1. 计算每行最后一个非空列
    // 2. 生成 ClearToEnd 命令优化尾部清除
    // 3. 遍历单元格，生成 Put 命令
    // 4. 处理宽字符（CJK、Emoji）的占位逻辑
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 测试执行路径

```
cargo test -p codex-tui-app-server
    └── tests/all.rs
        ├── test_backend.rs (conditional)
        └── suite/mod.rs
            ├── model_availability_nux.rs
            ├── no_panic_on_startup.rs
            ├── status_indicator.rs
            ├── vt100_history.rs
            └── vt100_live_commit.rs
```

### 4.2 被测试的源代码路径

| 测试文件 | 被测试的源代码 |
|---------|--------------|
| `manager_dependency_regression.rs` | `src/**/*.rs` (架构约束) |
| `model_availability_nux.rs` | `src/lib.rs`, `src/app_server_session.rs` |
| `no_panic_on_startup.rs` | `src/lib.rs`, `src/cli.rs` |
| `status_indicator.rs` | `src/status_indicator_widget.rs` |
| `vt100_history.rs` | `src/insert_history.rs`, `src/custom_terminal.rs` |
| `vt100_live_commit.rs` | `src/live_wrap.rs`, `src/insert_history.rs` |

### 4.3 关键依赖模块

```rust
// 测试基础设施
codex-rs/tui_app_server/src/test_backend.rs    // VT100Backend
codex-rs/utils/cargo-bin/src/lib.rs             // cargo_bin(), find_resource!()
codex-rs/utils/pty/src/lib.rs                   // spawn_pty_process()

// 被测试的核心模块
codex-rs/tui_app_server/src/insert_history.rs   // 历史记录插入
codex-rs/tui_app_server/src/live_wrap.rs        // 实时行包装
codex-rs/tui_app_server/src/custom_terminal.rs  // 自定义终端
codex-rs/tui_app_server/src/wrapping.rs         // 文本换行
```

### 4.4 外部依赖

| Crate | 用途 |
|-------|------|
| `vt100` | VT100 终端模拟器解析 |
| `ratatui` | TUI 框架 |
| `crossterm` | 跨平台终端控制 |
| `tokio` | 异步运行时 |
| `tempfile` | 临时目录管理 |
| `serde_json` | JSON 配置处理 |
| `insta` | 快照测试（dev-dependency） |

---

## 5. 依赖与外部交互

### 5.1 测试固件依赖

**`fixtures/oss-story.jsonl`**：
- 格式：JSON Lines，每行一个事件
- 内容：真实的 OSS 模型会话事件流
- 用途：为集成测试提供真实的事件序列

**事件类型示例**：
```json
{"ts":"2025-08-10T03:12:26.500Z","dir":"meta","kind":"session_start",...}
{"ts":"2025-08-10T03:12:26.502Z","dir":"to_tui","kind":"codex_event",...}
{"ts":"2025-08-10T03:12:28.561Z","dir":"to_tui","kind":"key_event",...}
```

### 5.2 外部二进制依赖

**`codex` CLI 二进制**：
- 测试通过 `codex_utils_cargo_bin::cargo_bin("codex")` 定位
- 用于端到端测试（`model_availability_nux.rs`, `no_panic_on_startup.rs`）
- 支持通过 `CODEX_RS_SSE_FIXTURE` 环境变量使用 SSE 固件

### 5.3 PTY 交互模式

**`codex_utils_pty` 模块**：

```rust
let spawned = codex_utils_pty::spawn_pty_process(
    codex_cli.to_string_lossy().as_ref(),
    &args,
    cwd.as_ref(),
    &env,
    &None,
    codex_utils_pty::TerminalSize::default(),
).await?;
```

**交互协议**：
1. 发送命令行参数启动进程
2. 通过 `stdout_rx`/`stderr_rx` 接收输出
3. 响应终端查询（如 `ESC[6n` 光标位置查询）
4. 通过 `writer_sender()` 发送输入
5. 监控 `exit_rx` 等待进程退出

### 5.4 环境变量配置

| 变量 | 用途 |
|------|------|
| `CODEX_HOME` | 临时配置目录 |
| `OPENAI_API_KEY` | API 认证（测试用 dummy 值） |
| `CODEX_RS_SSE_FIXTURE` | SSE 固件文件路径 |
| `OPENAI_BASE_URL` | API 基础 URL（测试用 unused.local） |

---

## 6. 风险、边界与改进建议

### 6.1 当前风险

#### 6.1.1 平台兼容性风险

**问题**：多个测试在 Windows 上被跳过

```rust
// run_codex_cli() does not work on Windows due to PTY limitations.
if cfg!(windows) {
    return Ok(());
}
```

**影响**：Windows 平台的测试覆盖率不足

**建议**：
- 评估使用 Windows ConPTY API 替代 POSIX PTY
- 或者使用模拟层（如 `insta` 快照测试）替代端到端测试

#### 6.1.2 测试稳定性风险

**问题**：`no_panic_on_startup` 测试被标记为 flaky

```rust
#[ignore = "TODO(mbolin): flaky"]
async fn malformed_rules_should_not_panic() -> anyhow::Result<()>
```

**可能原因**：
- 临时目录使用当前工作目录而非真正的临时目录
- 超时设置（10秒）在某些环境下不足
- PTY 输出同步问题

#### 6.1.3 架构约束测试的局限性

**问题**：`manager_dependency_regression.rs` 使用字符串匹配，可能产生误报

```rust
let forbidden = [
    "AuthManager",
    "ThreadManager",
    "auth_manager(",
    "thread_manager(",
];
```

**风险**：
- 注释或文档字符串中的提及会触发误报
- 无法检测通过 trait 对象或动态调用的间接依赖

### 6.2 边界情况

#### 6.2.1 VT100 测试的屏幕尺寸限制

当前测试使用固定尺寸（20x6, 40x10 等），可能无法覆盖：
- 极小终端（1行或1列）
- 超大终端（1000+ 列）
- 终端动态 resize

#### 6.2.2 Unicode 处理边界

虽然测试覆盖了 Emoji 和 CJK，但未覆盖：
- 组合字符（如带变音符号的拉丁字母）
- 双向文本（RTL 语言）
- 零宽字符（Zero-width joiner）

#### 6.2.3 URL 检测边界

`line_contains_url_like` 函数使用启发式检测，可能：
- 误报：普通文本被识别为 URL
- 漏报：非标准 scheme 的 URL 未被识别

### 6.3 改进建议

#### 6.3.1 测试架构改进

| 优先级 | 建议 | 预期收益 |
|-------|------|---------|
| 高 | 引入 `insta` 快照测试替代部分手动断言 | 提高测试可读性，简化维护 |
| 高 | 为 Windows 实现 PTY 支持或模拟层 | 提高平台覆盖率 |
| 中 | 参数化 VT100 测试的屏幕尺寸 | 提高边界覆盖 |
| 中 | 使用 AST 解析替代字符串匹配检测 Manager 依赖 | 降低误报率 |
| 低 | 引入模糊测试（fuzzing）测试输入解析 | 发现边界情况 |

#### 6.3.2 代码质量改进

**`insert_history.rs`**：
- 当前行包装逻辑较复杂，建议提取为独立的 `LineWrapper` 结构体
- URL 检测逻辑与换行逻辑耦合，建议解耦

**`live_wrap.rs`**：
- `drain_commit_ready` 的语义不够直观，建议添加更详细的文档
- 考虑使用环形缓冲区替代 `Vec` 的 `remove(0)` 操作（O(n) 复杂度）

#### 6.3.3 测试固件管理

**当前问题**：`oss-story.jsonl` 是二进制级的事件日志，难以维护

**建议**：
1. 使用文本格式的测试 DSL 描述事件序列
2. 提供工具将 DSL 编译为 JSONL
3. 版本控制 DSL 源码而非生成的 JSONL

示例 DSL：
```
SESSION_START model="gpt-oss:20b"
KEY_PRESS 'h' 'e' 'l' 'l' 'o'
KEY_PRESS Enter
AGENT_DELTA "Hello! How can I help you today?"
```

#### 6.3.4 持续集成建议

```yaml
# 建议的 CI 配置
- name: Run TUI tests
  run: cargo test -p codex-tui-app-server --features vt100-tests
  
- name: Run architecture constraint tests
  run: cargo test -p codex-tui-app-server manager_dependency_regression
  
- name: Check test coverage
  run: cargo tarpaulin -p codex-tui-app-server --out Xml
```

### 6.4 技术债务追踪

| 问题 | 位置 | 优先级 | 跟踪方式 |
|------|------|--------|---------|
| flaky 测试 | `no_panic_on_startup.rs` | 高 | TODO(mbolin) |
| Windows PTY 支持 | 多个测试文件 | 高 | 条件编译跳过 |
| 字符串匹配架构检查 | `manager_dependency_regression.rs` | 中 | 当前实现 |

---

## 7. 附录：关键数据结构

### 7.1 测试场景结构

```rust
// suite/vt100_history.rs
struct TestScenario {
    term: codex_tui_app_server::custom_terminal::Terminal<VT100Backend>,
}

impl TestScenario {
    fn new(width: u16, height: u16, viewport: Rect) -> Self {
        let backend = VT100Backend::new(width, height);
        let mut term = Terminal::with_options(backend).expect("...");
        term.set_viewport_area(viewport);
        Self { term }
    }

    fn run_insert(&mut self, lines: Vec<Line<'static>>) {
        insert_history_lines(&mut self.term, lines).expect("...");
    }
}
```

### 7.2 行包装选项

```rust
// wrapping.rs
pub struct RtOptions {
    pub width: usize,
    pub initial_indent: &'static str,
    pub subsequent_indent: &'static str,
}
```

### 7.3 终端大小配置

```rust
// codex_utils_pty
pub struct TerminalSize {
    pub rows: u16,
    pub cols: u16,
}

impl Default for TerminalSize {
    fn default() -> Self {
        Self { rows: 24, cols: 80 }
    }
}
```

---

## 8. 参考文档

- [AGENTS.md](../../../../AGENTS.md) - 项目级开发规范
- [codex-rs/tui/styles.md](../../../tui/styles.md) - TUI 样式规范
- [ratatui 文档](https://docs.rs/ratatui/) - TUI 框架
- [vt100 crate 文档](https://docs.rs/vt100/) - 终端模拟器
- [crossterm 文档](https://docs.rs/crossterm/) - 终端控制
