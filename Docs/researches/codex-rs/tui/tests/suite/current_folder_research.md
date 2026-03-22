# codex-rs/tui/tests/suite 目录研究文档

## 目录概述

本目录包含 Codex TUI（Terminal User Interface）的集成测试套件，位于 `codex-rs/tui/tests/suite/`。这些测试验证 TUI 的核心功能，包括终端渲染、历史记录插入、ANSI 转义序列处理以及启动行为等。

---

## 1. 场景与职责

### 1.1 测试场景

| 测试文件 | 场景描述 |
|---------|---------|
| `mod.rs` | 测试模块聚合入口，声明所有子模块 |
| `model_availability_nux.rs` | 验证模型可用性 NUX（New User Experience）在 resume 操作时不会重复消耗计数 |
| `no_panic_on_startup.rs` | 回归测试：确保当 rules 配置错误时（文件而非目录），TUI 不会 panic 而是优雅退出 |
| `status_indicator.rs` | 验证 `StatusIndicatorWidget` 对 ANSI 转义序列的清理功能 |
| `vt100_history.rs` | VT100 终端模拟器测试：验证历史记录插入、文本换行、Unicode/Emoji 支持、光标恢复等 |
| `vt100_live_commit.rs` | 验证实时输出（live wrap）的溢出提交机制 |

### 1.2 核心职责

1. **终端渲染正确性**：确保 TUI 在各种终端尺寸和内容类型下正确渲染
2. **历史记录管理**：验证 `insert_history_lines` 函数正确处理滚动、换行和样式
3. **启动健壮性**：确保配置错误或异常输入不会导致 panic
4. **ANSI 安全**：防止未过滤的 ANSI 转义序列污染终端缓冲区
5. **用户体验一致性**：验证 NUX 计数器等用户状态正确维护

---

## 2. 功能点目的

### 2.1 model_availability_nux 测试

**目的**：确保当用户执行 `codex resume` 恢复会话时，模型可用性提示的显示计数不会意外增加。

**业务背景**：
- 某些模型在首次可用时会显示 NUX 提示（New User Experience）
- 配置项 `tui.model_availability_nux.{model_slug}` 记录已显示次数
- 恢复会话不应被视为新使用，不应增加计数

### 2.2 no_panic_on_startup 测试

**目的**：回归测试，修复 GitHub Issue #8803。

**场景**：当 `rules` 应该是一个目录但被配置为文件时，TUI 应该：
- 不 panic
- 以非零退出码退出
- 显示有意义的错误信息

### 2.3 status_indicator 测试

**目的**：验证 `ansi_escape_line` 函数正确剥离 ANSI 转义序列。

**安全考虑**：
- 原始 ANSI 转义序列（如 `\x1b[31m`）写入终端缓冲区可能导致渲染异常
- 状态指示器需要显示纯文本，必须清理输入中的控制字符

### 2.4 vt100_history 测试

**目的**：使用 VT100 终端模拟器验证历史记录插入的多种场景：

| 测试用例 | 验证内容 |
|---------|---------|
| `basic_insertion_no_wrap` | 基础插入，无换行 |
| `long_token_wraps` | 长文本自动换行，字符不丢失 |
| `emoji_and_cjk` | Unicode 宽字符（Emoji、中文）正确处理 |
| `mixed_ansi_spans` | ANSI 样式跨段正确合并 |
| `cursor_restoration` | 光标位置在插入后正确恢复 |
| `word_wrap_no_mid_word_split` | 单词不在中间断开 |
| `em_dash_and_space_word_wrap` | 特殊标点（em-dash）处理 |

### 2.5 vt100_live_commit 测试

**目的**：验证 `RowBuilder` 的 `drain_commit_ready` 机制：
- 当实时输出行数超过限制时，最旧的行被提交到历史记录
- 保留最新的 N 行在"实时环"中

---

## 3. 具体技术实现

### 3.1 关键数据结构与类型

#### VT100Backend（测试后端）

```rust
// codex-rs/tui/src/test_backend.rs
pub struct VT100Backend {
    crossterm_backend: CrosstermBackend<vt100::Parser>,
}
```

- 包装 `crossterm` 后端和 `vt100::Parser`
- 将终端输出捕获到内存中的 VT100 屏幕缓冲区
- 允许测试代码检查最终渲染状态（字符、颜色、光标位置）

#### RowBuilder（实时文本构建器）

```rust
// codex-rs/tui/src/live_wrap.rs
pub struct RowBuilder {
    target_width: usize,
    current_line: String,
    rows: Vec<Row>,
}

pub struct Row {
    pub text: String,
    pub explicit_break: bool,  // true = 显式换行符，false = 自动换行
}
```

功能：
- 增量式构建文本行
- 支持动态宽度调整（`set_width`）
- 管理显式换行 vs 自动换行的区别

#### Terminal（自定义终端）

```rust
// codex-rs/tui/src/custom_terminal.rs
pub struct Terminal<B: Backend + Write> {
    backend: B,
    buffers: [Buffer; 2],  // 双缓冲
    viewport_area: Rect,   // 视口区域
    last_known_cursor_pos: Position,
    visible_history_rows: u16,
}
```

特性：
- 派生自 ratatui 的 Terminal
- 支持视口区域设置（用于 inline 模式）
- 跟踪历史记录行数

### 3.2 关键流程

#### 历史记录插入流程

```rust
// codex-rs/tui/src/insert_history.rs
pub fn insert_history_lines<B>(
    terminal: &mut Terminal<B>,
    lines: Vec<Line>,
) -> io::Result<()>
```

流程步骤：

1. **预换行处理**：
   - 检测 URL-only 行（保持完整，让终端自动换行以保持可点击性）
   - 混合行（URL + 文本）使用自适应换行
   - 普通文本使用标准换行

2. **视口调整**：
   - 如果视口不在屏幕底部，向下滚动以腾出空间
   - 使用 DECSTBM（设置滚动区域）和 RI（反向索引）ANSI 序列

3. **内容写入**：
   - 设置滚动区域为视口上方区域
   - 逐行写入内容，处理样式（前景色、背景色、修饰符）
   - 清除 URL 行的延续行以避免残留字符

4. **光标恢复**：
   - 恢复原始光标位置
   - 更新视口区域（如有必要）

#### ANSI 转义处理流程

```rust
// codex-rs/ansi-escape/src/lib.rs
pub fn ansi_escape_line(s: &str) -> Line<'static> {
    let s = expand_tabs(s);  // 将 tab 替换为 4 空格
    let text = ansi_escape(&s);  // 使用 ansi_to_tui 解析
    // 返回第一行（警告多行输入）
}
```

#### PTY 进程启动流程（用于集成测试）

```rust
// codex-rs/utils/pty/src/pty.rs
pub async fn spawn_process(
    program: &str,
    args: &[String],
    cwd: &Path,
    env: &HashMap<String, String>,
    arg0: &Option<String>,
    size: TerminalSize,
) -> Result<SpawnedProcess>
```

组件：
- 使用 `portable-pty` 创建 PTY
- 分离的读取/写入任务（tokio 异步）
- 支持 Unix 信号和进程组管理
- 支持文件描述符继承（用于特殊场景）

### 3.3 协议与命令

#### ANSI 控制序列使用

| 序列 | 用途 |
|-----|------|
| `ESC [ {top};{bottom} r` | DECSTBM - 设置滚动区域 |
| `ESC M` | RI - 反向索引（向上滚动） |
| `ESC [ r` | 重置滚动区域 |
| `ESC [ 6 n` | DSR - 设备状态报告（查询光标位置） |
| `ESC [ {row};{col} R` | CPR - 光标位置报告 |

#### 测试中的光标位置模拟

测试代码通过检测 `\x1b[6n`（DSR）并响应 `\x1b[1;1R`（CPR）来模拟终端行为，使 TUI 能够在无真实终端的环境下初始化。

---

## 4. 关键代码路径与文件引用

### 4.1 测试文件结构

```
codex-rs/tui/tests/
├── all.rs                    # 测试入口（聚合所有测试）
├── test_backend.rs           # VT100Backend 重导出
├── fixtures/
│   └── oss-story.jsonl       # 测试固件（大型故事文本）
└── suite/
    ├── mod.rs                # 模块声明
    ├── model_availability_nux.rs
    ├── no_panic_on_startup.rs
    ├── status_indicator.rs
    ├── vt100_history.rs
    └── vt100_live_commit.rs
```

### 4.2 被测试的核心模块

| 测试文件 | 被测试模块 | 关键函数/类型 |
|---------|-----------|--------------|
| `model_availability_nux.rs` | `codex_core::config`, `codex_tui` | `spawn_pty_process`, `codex exec`, `codex resume` |
| `no_panic_on_startup.rs` | `codex_tui::lib` | `run_main`, 配置加载 |
| `status_indicator.rs` | `codex_ansi_escape` | `ansi_escape_line` |
| `vt100_history.rs` | `codex_tui::insert_history`, `custom_terminal` | `insert_history_lines`, `Terminal::set_viewport_area` |
| `vt100_live_commit.rs` | `codex_tui::live_wrap`, `insert_history` | `RowBuilder::drain_commit_ready` |

### 4.3 关键依赖路径

```
测试代码
  ├──> codex_utils_cargo_bin::cargo_bin  # 定位被测二进制文件
  ├──> codex_utils_pty::spawn_pty_process  # PTY 进程管理
  │       └──> portable-pty
  ├──> VT100Backend  # 测试专用终端后端
  │       └──> vt100::Parser
  └──> codex_tui::insert_history_lines
          └──> wrapping::adaptive_wrap_line
```

---

## 5. 依赖与外部交互

### 5.1 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `vt100` | VT100 终端模拟器解析器，用于测试验证渲染输出 |
| `portable-pty` | 跨平台 PTY 实现 |
| `ansi-to-tui` | ANSI 序列到 ratatui Text 的转换 |
| `textwrap` | 文本换行算法 |
| `ratatui` | 终端 UI 框架 |
| `crossterm` | 跨平台终端控制 |
| `tokio` | 异步运行时 |
| `tempfile` | 临时目录/文件创建 |
| `serde_json` | JSON 配置解析 |

### 5.2 工作空间内部依赖

```
codex-tui (测试目标)
├── codex-ansi-escape        # ANSI 转义序列处理
├── codex-core               # 核心配置、认证、状态管理
├── codex-protocol           # 协议类型定义
├── codex-utils-pty          # PTY 工具（测试辅助）
└── codex-utils-cargo-bin    # 二进制文件定位（测试辅助）
```

### 5.3 环境交互

#### 环境变量

| 变量 | 用途 |
|-----|------|
| `CODEX_HOME` | 配置目录路径（测试中使用临时目录） |
| `OPENAI_API_KEY` | API 密钥（测试中设为 dummy） |
| `CODEX_RS_SSE_FIXTURE` | SSE 响应固件路径 |
| `OPENAI_BASE_URL` | API 基础 URL（测试中设为 unused） |

#### 平台限制

- **Windows**：PTY 测试被跳过（`cfg!(windows)` 检查）
- **Unix**：使用 `openpty` 系统调用创建 PTY

---

## 6. 风险、边界与改进建议

### 6.1 已知风险与问题

#### 6.1.1 测试稳定性

| 问题 | 文件 | 状态 |
|-----|------|------|
| Flaky 测试标记 | `no_panic_on_startup.rs:9` | `#[ignore = "TODO(mbolin): flaky"]` |
| 临时目录导致 hang | `no_panic_on_startup.rs:23-24` | 使用当前目录而非 temp dir |

#### 6.1.2 平台差异

- Windows 不支持 PTY 测试（PTY 限制）
- 路径分隔符、权限模型差异未完全覆盖

#### 6.1.3 竞态条件

`model_availability_nux` 测试：
- 使用固定 2 秒延迟后发送中断信号
- 依赖超时（15 秒）确保测试完成
- 可能存在时间敏感的不稳定性

### 6.2 边界情况

#### 6.2.1 文本换行边界

| 场景 | 处理策略 |
|-----|---------|
| URL-only 行 | 不换行，让终端自动处理（保持可点击） |
| 混合行（URL + 文本） | 自适应换行，URL 保持完整 |
| 超长单词（> 行宽） | 字符级拆分（除非 break_words=false） |
| CJK/Emoji 字符 | Unicode 宽度计算（宽度 2） |

#### 6.2.2 终端尺寸边界

- 最小宽度：1 列
- 视口高度：0 行（空区域处理）
- 屏幕尺寸变化：自动调整检测

### 6.3 改进建议

#### 6.3.1 测试覆盖率

1. **增加快照测试**：
   - `status_indicator.rs` 当前仅测试 `ansi_escape_line`
   - 建议添加 `insta` 快照测试验证完整 Widget 渲染

2. **增加边界测试**：
   - 零宽度终端
   - 极大宽度（> 1000 列）
   - 包含控制字符的输入

3. **平台覆盖**：
   - Windows 特定的 ConPTY 测试
   - macOS/Linux 差异测试

#### 6.3.2 代码结构

1. **测试辅助函数提取**：
   - `model_availability_nux.rs` 和 `no_panic_on_startup.rs` 有重复的 PTY 输出读取逻辑
   - 建议提取到共享的测试工具模块

2. **配置生成辅助**：
   - TOML 配置字符串拼接容易出错
   - 建议使用结构化配置生成

#### 6.3.3 性能优化

1. **VT100 测试性能**：
   - 当前使用 8KB 读取缓冲区
   - 考虑使用更大的缓冲区减少系统调用

2. **换行算法**：
   - `adaptive_wrap_line` 在超长行上可能性能下降
   - 考虑添加长度限制或流式处理

#### 6.3.4 可维护性

1. **文档**：
   - `vt100_history.rs` 中的 `assert_contains!` 宏很有用
   - 考虑将其提升到共享测试库

2. **错误信息**：
   - 测试失败时的诊断信息可以更详细
   - 建议包含屏幕内容转储

---

## 7. 附录：关键代码片段

### 7.1 测试中的 PTY 输出读取模式

```rust
// 来自 no_panic_on_startup.rs
let exit_code_result = timeout(Duration::from_secs(10), async {
    loop {
        select! {
            result = output_rx.recv() => match result {
                Ok(chunk) => {
                    // 检测光标位置查询并响应
                    if chunk.windows(4).any(|window| window == b"\x1b[6n") {
                        let _ = writer_tx.send(b"\x1b[1;1R".to_vec()).await;
                    }
                    output.extend_from_slice(&chunk);
                }
                Err(tokio::sync::broadcast::error::RecvError::Closed) => break exit_rx.await,
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => {}
            },
            result = &mut exit_rx => break result,
        }
    }
}).await;
```

### 7.2 VT100 测试场景设置

```rust
// 来自 vt100_history.rs
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

    fn run_insert(&mut self, lines: Vec<Line<'static>>) {
        codex_tui::insert_history::insert_history_lines(&mut self.term, lines)
            .expect("Failed to insert history lines in test");
    }
}
```

### 7.3 RowBuilder 使用模式

```rust
// 来自 vt100_live_commit.rs
let mut rb = codex_tui::live_wrap::RowBuilder::new(20);
rb.push_fragment("one\n");
rb.push_fragment("two\n");
// ...

// 保留最后 3 行，提交超出的行
let commit_rows = rb.drain_commit_ready(3);
let lines: Vec<Line<'static>> = commit_rows.into_iter().map(|r| r.text.into()).collect();
```

---

## 8. 总结

`codex-rs/tui/tests/suite` 目录包含 Codex TUI 的核心集成测试，覆盖：

1. **终端渲染正确性**（VT100 模拟测试）
2. **启动健壮性**（错误处理、配置验证）
3. **用户体验一致性**（NUX 计数器、状态指示器）

测试设计采用分层策略：
- 单元测试（`insert_history.rs` 中的 `mod tests`）验证内部函数
- 集成测试（本目录）验证端到端行为
- PTY 测试验证真实终端交互

主要技术挑战包括：
- 跨平台终端行为差异
- ANSI 序列的正确处理
- Unicode 宽字符的准确渲染
- 异步 PTY 进程的可靠测试
