# SKILL.md 研究文档: test-tui

## 概述

`test-tui` Skill 是 Codex CLI/TUI 项目的交互式测试指南，位于 `.codex/skills/test-tui/SKILL.md`。它提供了如何启动和使用 Codex TUI 进行手动验证变更的说明。

---

## 1. 场景与职责

### 1.1 定位与目标受众

| 属性 | 描述 |
|------|------|
| **文件路径** | `.codex/skills/test-tui/SKILL.md` |
| **目标受众** | 开发者、测试人员、AI Agent |
| **使用场景** | 手动验证 TUI 变更、调试交互式功能 |
| **相关模块** | `codex-rs/tui`, `codex-rs/tui_app_server` |

### 1.2 核心职责

1. **交互式测试指导**: 提供启动 TUI 的标准流程
2. **调试配置**: 说明如何启用详细日志记录
3. **测试消息发送**: 指导如何程序化发送测试消息
4. **集成 just 工具**: 说明使用 `just codex` 快捷命令

### 1.3 使用场景

- **功能开发验证**: 开发者在实现新功能后，需要手动验证 TUI 行为
- **Bug 修复确认**: 修复交互式 Bug 后，验证修复是否生效
- **回归测试**: 在关键路径变更后，确保 TUI 仍能正常启动和运行
- **日志调试**: 当需要深入了解 TUI 内部状态时，启用 trace 级别日志

---

## 2. 功能点目的

### 2.1 核心功能点详解

#### 2.1.1 交互式启动 (Start interactively)

```bash
# 标准启动方式
just codex

# 带参数启动
just codex -c log_dir=/tmp/codex_logs
```

**目的**: 确保 TUI 在真实终端环境中运行，而非后台或模拟环境。

**技术背景**: 
- TUI 依赖 `crossterm` 进行终端控制
- 需要真实的 TTY 来接收键盘事件和渲染输出
- 代码路径: `codex-rs/tui/src/tui.rs::init()` - 检查 `stdin().is_terminal()` 和 `stdout().is_terminal()`

#### 2.1.2 Trace 日志记录 (RUST_LOG="trace")

```bash
RUST_LOG="trace" just codex
```

**目的**: 捕获最详细的运行时信息，用于调试。

**技术实现**:
```rust
// codex-rs/tui/src/lib.rs:481-486
let env_filter = || {
    EnvFilter::try_from_default_env().unwrap_or_else(|_| {
        EnvFilter::new("codex_core=info,codex_tui=info,codex_rmcp_client=info")
    })
};
```

- 使用 `tracing-subscriber` 的 `EnvFilter`
- 日志写入位置: `codex_core::config::log_dir(&config)?` 返回的目录
- 默认日志文件: `codex-tui.log`

#### 2.1.3 日志目录配置 (-c log_dir=<dir>)

```bash
just codex -c log_dir=/tmp/codex_debug
```

**目的**: 将日志输出到指定目录，便于收集和分析。

**配置优先级**:
1. CLI 覆盖 (`-c log_dir=...`)
2. 配置文件中的 `log_dir` 设置
3. 默认: `$CODEX_HOME/log/`

**代码路径**: `codex-rs/core/src/config/mod.rs:2971-2973`
```rust
pub fn log_dir(cfg: &Config) -> std::io::Result<PathBuf> {
    Ok(cfg.log_dir.clone())
}
```

#### 2.1.4 测试消息发送规范

> "When sending a test message programmatically, send text first, then send Enter in a separate write"

**目的**: 避免输入缓冲问题，确保消息正确提交。

**技术背景**:
- TUI 使用 `crossterm` 的事件流处理键盘输入
- `chat_composer.rs` 处理 Enter 键的提交逻辑
- 批量写入可能导致事件解析错误

**正确示例** (伪代码):
```python
# 正确: 分开发送
write("hello world")
flush()
write("\r")  # Enter
flush()

# 错误: 一次性发送
write("hello world\r")
flush()
```

---

## 3. 具体技术实现

### 3.1 TUI 架构概览

```
┌─────────────────────────────────────────────────────────────┐
│                         TUI Application                      │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │   ChatWidget │  │  BottomPane  │  │   App (主循环)    │  │
│  │  (聊天界面)   │  │  (底部输入)   │  │  (事件处理)      │  │
│  └──────────────┘  └──────────────┘  └──────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │  AppEvent    │  │   TuiEvent   │  │  ThreadManager   │  │
│  │  (应用事件)   │  │  (终端事件)   │  │  (线程管理)      │  │
│  └──────────────┘  └──────────────┘  └──────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │   VT100      │  │   Crossterm  │  │   ratatui        │  │
│  │  (测试后端)   │  │  (终端控制)   │  │  (UI 框架)       │  │
│  └──────────────┘  └──────────────┘  └──────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 关键流程

#### 3.2.1 启动流程

```rust
// codex-rs/tui/src/main.rs
fn main() -> anyhow::Result<()> {
    arg0_dispatch_or_else(|arg0_paths: Arg0DispatchPaths| async move {
        let top_cli = TopCli::parse();
        // ... 配置加载
        let use_app_server_tui = codex_tui::should_use_app_server_tui(&inner).await?;
        let exit_info = if use_app_server_tui {
            // 使用新的 app-server TUI
            codex_tui_app_server::run_main(...).await?
        } else {
            // 使用传统 TUI
            run_main(inner, arg0_paths, ...).await?
        };
        // ... 输出 token 使用情况
    })
}
```

#### 3.2.2 事件循环

```rust
// codex-rs/tui/src/tui.rs:241-258
pub struct Tui {
    frame_requester: FrameRequester,
    draw_tx: broadcast::Sender<()>,
    event_broker: Arc<EventBroker>,
    terminal: Terminal,
    // ... 其他字段
}

// 事件流生成
tokio::select! {
    event = event_stream.next() => {
        match event {
            Some(TuiEvent::Key(key)) => handle_key_event(key),
            Some(TuiEvent::Paste(text)) => handle_paste(text),
            Some(TuiEvent::Draw) => render_frame(),
            None => break,
        }
    }
}
```

#### 3.2.3 日志系统初始化

```rust
// codex-rs/tui/src/lib.rs:460-500
let log_dir = codex_core::config::log_dir(&config)?;
std::fs::create_dir_all(&log_dir)?;

let mut log_file_opts = OpenOptions::new();
log_file_opts.create(true).append(true);
#[cfg(unix)]
{
    use std::os::unix::fs::OpenOptionsExt;
    log_file_opts.mode(0o600);  // 仅所有者可读写
}

let log_file = log_file_opts.open(log_dir.join("codex-tui.log"))?;
let (non_blocking, _guard) = non_blocking(log_file);

let file_layer = tracing_subscriber::fmt::layer()
    .with_writer(non_blocking)
    .with_target(true)
    .with_ansi(false)
    .with_span_events(FmtSpan::NEW | FmtSpan::CLOSE)
    .with_filter(env_filter());
```

### 3.3 数据结构

#### 3.3.1 AppEvent (应用事件)

```rust
// codex-rs/tui/src/app_event.rs:71-200
pub(crate) enum AppEvent {
    CodexEvent(Event),                    // 来自后端的协议事件
    OpenAgentPicker,                      // 打开 Agent 选择器
    SubmitThreadOp { thread_id, op },     // 提交操作到指定线程
    Exit(ExitMode),                       // 退出请求
    StartFileSearch(String),              // 开始文件搜索
    FileSearchResult { query, matches },  // 文件搜索结果
    InsertHistoryCell(Box<dyn HistoryCell>), // 插入历史记录单元
    // ... 更多变体
}
```

#### 3.3.2 TuiEvent (终端事件)

```rust
// codex-rs/tui/src/tui.rs:234-239
pub enum TuiEvent {
    Key(KeyEvent),    // 键盘事件
    Paste(String),    // 粘贴事件 (bracketed paste)
    Draw,             // 绘制请求
}
```

#### 3.3.3 VT100Backend (测试后端)

```rust
// codex-rs/tui/src/test_backend.rs:21-37
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

### 3.4 协议与命令

#### 3.4.1 just 命令

| 命令 | 描述 | 实现 |
|------|------|------|
| `just codex` | 运行 Codex TUI | `cargo run --bin codex` |
| `just exec` | 运行 exec 子命令 | `cargo run --bin codex -- exec` |
| `just test` | 运行测试 | `cargo nextest run --no-fail-fast` |
| `just fmt` | 格式化代码 | `cargo fmt` |

#### 3.4.2 CLI 参数

```rust
// codex-rs/tui/src/cli.rs
pub struct Cli {
    pub prompt: Option<String>,           // 初始提示
    pub images: Vec<PathBuf>,             // 附加图片
    pub model: Option<String>,            // 模型选择
    pub sandbox_mode: Option<SandboxModeCliArg>,
    pub approval_policy: Option<ApprovalModeCliArg>,
    pub full_auto: bool,                  // 全自动模式
    pub no_alt_screen: bool,              // 禁用备用屏幕
    pub config_overrides: CliConfigOverrides, // -c 覆盖
    // ...
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件映射

| 文件路径 | 职责 |
|----------|------|
| `.codex/skills/test-tui/SKILL.md` | **本 Skill 文档** - 测试指南 |
| `codex-rs/tui/src/main.rs` | TUI 入口点，CLI 解析，app-server 路由 |
| `codex-rs/tui/src/lib.rs` | 主运行逻辑，日志初始化，配置加载 |
| `codex-rs/tui/src/cli.rs` | CLI 参数定义 (clap) |
| `codex-rs/tui/src/app.rs` | 主应用状态机，事件处理循环 |
| `codex-rs/tui/src/tui.rs` | 终端抽象，事件流，备用屏幕管理 |
| `codex-rs/tui/src/app_event.rs` | 应用事件定义 |
| `codex-rs/tui/src/app_event_sender.rs` | 事件发送器 |
| `codex-rs/tui/src/chatwidget.rs` | 聊天界面主组件 |
| `codex-rs/tui/src/bottom_pane/chat_composer.rs` | 底部输入框，键盘处理 |
| `codex-rs/tui/src/test_backend.rs` | VT100 测试后端 |
| `codex-rs/tui/src/custom_terminal.rs` | 自定义终端实现 |
| `codex-rs/tui/src/insert_history.rs` | 历史记录插入逻辑 |
| `codex-rs/tui/styles.md` | TUI 样式规范 |
| `codex-rs/tui/Cargo.toml` | 依赖和特性定义 |
| `justfile` | 快捷命令定义 |

### 4.2 测试文件映射

| 文件路径 | 测试类型 |
|----------|----------|
| `codex-rs/tui/tests/all.rs` | 测试入口 |
| `codex-rs/tui/tests/suite/no_panic_on_startup.rs` | PTY 集成测试 |
| `codex-rs/tui/tests/suite/vt100_history.rs` | VT100 历史记录测试 |
| `codex-rs/tui/tests/suite/vt100_live_commit.rs` | VT100 实时提交测试 |
| `codex-rs/tui/tests/suite/status_indicator.rs` | 状态指示器测试 |
| `codex-rs/tui/tests/suite/model_availability_nux.rs` | 模型可用性测试 |
| `codex-rs/tui/tests/test_backend.rs` | VT100Backend 导出 |

### 4.3 关键代码片段

#### 日志目录解析
```rust
// codex-rs/core/src/config/mod.rs:2572-2575
let log_dir = cfg
    .log_dir
    .clone()
    .map(|p| p.into_path_buf())
    .unwrap_or_else(|| codex_home.join("log"));
```

#### 终端初始化检查
```rust
// codex-rs/tui/src/tui.rs:208-224
pub fn init() -> Result<Terminal> {
    if !stdin().is_terminal() {
        return Err(std::io::Error::other("stdin is not a terminal"));
    }
    if !stdout().is_terminal() {
        return Err(std::io::Error::other("stdout is not a terminal"));
    }
    set_modes()?;
    flush_terminal_input_buffer();
    set_panic_hook();
    // ...
}
```

#### App-Server 路由决策
```rust
// codex-rs/tui/src/app_server_tui_dispatch.rs:43-45
pub async fn should_use_app_server_tui(cli: &Cli) -> std::io::Result<bool> {
    should_use_app_server_tui_with(cli, Config::load_with_cli_overrides_and_harness_overrides).await
}
// 检查 config.features.enabled(Feature::TuiAppServer)
```

---

## 5. 依赖与外部交互

### 5.1 外部依赖

| 依赖 | 用途 |
|------|------|
| `ratatui` | TUI 渲染框架 |
| `crossterm` | 跨平台终端控制 |
| `tokio` | 异步运行时 |
| `tracing` | 结构化日志 |
| `clap` | CLI 解析 |
| `vt100` | VT100 终端模拟 (测试) |
| `codex-core` | 核心配置、认证、线程管理 |
| `codex-protocol` | 协议类型定义 |
| `codex-app-server-protocol` | App-Server 协议 |

### 5.2 内部模块交互

```
┌─────────────────────────────────────────────────────────────┐
│                        codex-tui                            │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │  codex-core  │  │ codex-protocol│  │codex-app-server- │  │
│  │  (配置/认证)  │  │  (协议类型)   │  │    protocol      │  │
│  └──────────────┘  └──────────────┘  └──────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │codex-chatgpt │  │ codex-client  │  │ codex-backend-   │  │
│  │  (ChatGPT)   │  │  (客户端)     │  │    client        │  │
│  └──────────────┘  └──────────────┘  └──────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 5.3 环境变量

| 变量 | 用途 |
|------|------|
| `RUST_LOG` | 日志级别控制 (e.g., `trace`, `debug`, `info`) |
| `CODEX_HOME` | Codex 配置主目录 |
| `CODEX_SANDBOX` | 沙盒模式标识 |
| `CODEX_SANDBOX_NETWORK_DISABLED` | 网络禁用标识 |
| `OPENAI_API_KEY` | OpenAI API 密钥 |

### 5.4 配置文件

| 文件 | 用途 |
|------|------|
| `$CODEX_HOME/config.toml` | 主配置文件 |
| `$CODEX_HOME/log/codex-tui.log` | TUI 日志文件 |
| `$CODEX_HOME/threads/` | 会话存储目录 |

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 PTY 测试限制
```rust
// codex-rs/tui/tests/suite/no_panic_on_startup.rs:11-14
#[tokio::test]
#[ignore = "TODO(mbolin): flaky"]
async fn malformed_rules_should_not_panic() -> anyhow::Result<()> {
    // run_codex_cli() does not work on Windows due to PTY limitations.
    if cfg!(windows) {
        return Ok(());
    }
```

**风险**: Windows 平台无法运行 PTY 集成测试。
**影响**: 测试覆盖率在 Windows 上降低。

#### 6.1.2 测试不稳定性
- `no_panic_on_startup` 测试被标记为 `#[ignore]` 因为不稳定
- 使用临时目录作为 CWD 可能导致测试挂起

#### 6.1.3 终端兼容性
- 某些终端 (如 Apple Terminal, Warp, VSCode) 拦截 `Alt+Up`
- 需要回退到 `Shift+Left` 绑定
- 代码: `chatwidget.rs:196-212`

### 6.2 边界情况

#### 6.2.1 输入处理边界
- **粘贴检测**: Windows 终端可能不发送 bracketed paste 事件
  - 解决方案: `PasteBurst` 状态机检测快速字符输入
  - 代码: `codex-rs/tui/src/bottom_pane/paste_burst.rs`

- **IME 输入**: 非 ASCII 字符输入不应被粘贴检测延迟
  - 代码: `chat_composer.rs` 中的 `handle_non_ascii_char`

#### 6.2.2 日志边界
- 日志文件权限: Unix 系统使用 `0o600` 模式
- 日志轮转: 依赖外部工具或手动清理
- 多实例: 多个 TUI 实例可能并发写入同一日志文件

#### 6.2.3 备用屏幕边界
- `--no-alt-screen` 模式用于 Zellij 等终端复用器
- 内联模式保留滚动历史但可能影响性能

### 6.3 改进建议

#### 6.3.1 测试基础设施

| 优先级 | 建议 | 预期收益 |
|--------|------|----------|
| 高 | 稳定 `no_panic_on_startup` 测试 | 提高 CI 可靠性 |
| 高 | 添加 Windows PTY 支持 | 完整跨平台测试 |
| 中 | 增加快照测试覆盖率 | 防止 UI 回归 |
| 中 | 自动化交互式测试流程 | 减少手动测试负担 |

#### 6.3.2 日志系统

```rust
// 建议: 添加日志轮转支持
pub struct LogConfig {
    pub max_file_size: usize,  // 例如: 10MB
    pub max_files: usize,      // 保留文件数
    pub rotation_policy: RotationPolicy, // 按大小/时间轮转
}
```

#### 6.3.3 调试工具

| 建议 | 描述 |
|------|------|
| 添加 `/debug` 命令 | 在 TUI 内显示当前状态、事件队列 |
| 事件录制/回放 | 记录用户交互用于回归测试 |
| 性能分析模式 | 显示帧率、事件处理延迟 |

#### 6.3.4 文档改进

1. **添加故障排除章节**:
   - 常见启动失败原因
   - 日志解读指南
   - 终端兼容性矩阵

2. **扩展示例**:
   - 程序化交互的完整示例代码
   - 不同终端的配置建议

3. **自动化测试脚本**:
   ```bash
   # 建议添加的脚本
   scripts/test-tui-interactive.sh
   scripts/collect-debug-info.sh
   ```

### 6.4 监控与可观测性

建议添加的指标:
- 启动时间
- 事件处理延迟
- 渲染帧率
- 内存使用情况
- 活跃会话数

---

## 7. 附录

### 7.1 快速参考

```bash
# 启动并启用详细日志
RUST_LOG="trace" just codex

# 指定日志目录
just codex -c log_dir=/tmp/codex_logs

# 运行特定测试
cargo test -p codex-tui --features vt100-tests

# 运行所有测试
just test
```

### 7.2 相关文档

- `codex-rs/tui/styles.md` - TUI 样式规范
- `codex-rs/tui/README.md` - TUI 模块文档 (如存在)
- `AGENTS.md` - 项目级 Agent 指南
- `docs/tui-chat-composer.md` - 聊天编辑器状态机文档

### 7.3 变更历史

| 日期 | 变更 | 作者 |
|------|------|------|
| 2026-03-22 | 创建研究文档 | AI Agent |

---

*本文档基于对 `.codex/skills/test-tui/SKILL.md` 及其相关代码的深入分析生成。*
