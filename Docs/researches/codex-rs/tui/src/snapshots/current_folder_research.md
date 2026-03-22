# Codex TUI Snapshots 目录研究文档

## 1. 场景与职责

### 1.1 目录定位

`snapshots` 目录位于 `codex-rs/tui/src/snapshots/`，是 Codex TUI（Terminal User Interface）项目的**快照测试（Snapshot Testing）**数据存储目录。该目录包含 83 个 `.snap` 文件，用于存储 UI 组件渲染结果的预期输出。

### 1.2 核心职责

该目录服务于以下核心职责：

1. **UI 回归测试**：捕获并验证 TUI 组件的视觉输出，确保 UI 变更不会意外破坏现有功能
2. **视觉文档**：作为 UI 组件行为的活文档，展示组件在不同状态下的渲染效果
3. **跨平台一致性验证**：确保 UI 在不同操作系统（如 macOS、Linux）上渲染一致
4. **渲染逻辑验证**：验证复杂渲染逻辑（如 Markdown 解析、Diff 高亮、语法着色）的正确性

### 1.3 项目上下文

Codex TUI 是一个基于 [ratatui](https://github.com/ratatui/ratatui) 构建的终端用户界面应用，用于与 OpenAI Codex 模型交互。快照测试是该项目的主要测试策略之一，由 [`insta`](https://github.com/mitsuhiko/insta) 框架驱动。

---

## 2. 功能点目的

### 2.1 快照测试覆盖的功能域

根据 snapshot 文件的命名和内容分析，测试覆盖以下功能域：

| 功能域 | 相关 Snapshot 文件数量 | 说明 |
|--------|------------------------|------|
| Diff 渲染 | ~20 | 代码差异高亮、语法着色、行号显示 |
| 历史记录单元格 | ~35 | 对话历史、命令输出、MCP 工具调用 |
| 应用级 UI | ~5 | 启动提示、模型迁移、Agent 选择器 |
| 分页覆盖层 | ~5 | 转录本覆盖层、静态覆盖层 |
| 会话选择器 | ~5 | 恢复/分叉会话界面 |
| Markdown 渲染 | ~2 | Markdown 解析和渲染 |
| 状态指示器 | ~5 | 工作状态、队列消息显示 |
| 多 Agent 协作 | ~2 | 协作 Agent 转录本 |
| CWD 提示 | ~2 | 工作目录选择模态框 |
| 更新提示 | ~1 | 版本更新提示界面 |

### 2.2 Snapshot 文件命名约定

所有 snapshot 文件遵循统一的命名模式：

```
codex_tui__{模块}__tests__{测试名称}.snap
```

例如：
- `codex_tui__diff_render__tests__diff_gallery_80x24.snap` - Diff 渲染测试，80x24 终端尺寸
- `codex_tui__history_cell__tests__completed_mcp_tool_call_success_snapshot.snap` - 历史单元格 MCP 工具调用成功场景
- `codex_tui__app__tests__startup_custom_prompt_deprecation_notice.snap` - 应用启动时自定义提示弃用通知

### 2.3 Snapshot 文件结构

每个 `.snap` 文件采用 YAML 前置元数据格式：

```yaml
---
source: tui/src/{源文件}.rs
expression: {表达式名称}  # 如 terminal.backend(), rendered, snapshot 等
assertion_line: {行号}    # 可选，断言所在行
---
{快照内容}
```

内容部分根据测试类型可以是：
- 终端屏幕的文本表示（包含 ANSI 转义序列）
- 纯文本渲染结果
- 多行字符串

---

## 3. 具体技术实现

### 3.1 测试框架与依赖

**核心依赖**（来自 `codex-rs/tui/Cargo.toml`）：

```toml
[dev-dependencies]
insta = { workspace = true }      # 快照测试框架
pretty_assertions = { workspace = true }  # 美观的断言输出
vt100 = { workspace = true }      # VT100 终端模拟器（可选特性）
```

**特性标志**：
- `vt100-tests`: 启用基于 VT100 模拟器的测试

### 3.2 测试后端架构

项目实现了两种测试后端：

#### 3.2.1 TestBackend（ratatui 内置）

用于基础 UI 测试，直接操作 ratatui 的 `TestBackend`：

```rust
use ratatui::Terminal;
use ratatui::backend::TestBackend;

let mut terminal = Terminal::new(TestBackend::new(80, 24)).expect("terminal");
terminal.draw(|f| widget.render(f.area(), f.buffer_mut())).expect("draw");
insta::assert_snapshot!(terminal.backend());
```

**适用场景**：
- 简单组件渲染测试
- 不需要 ANSI 转义序列的测试
- 快速执行的单元测试

#### 3.2.2 VT100Backend（自定义实现）

位于 `codex-rs/tui/src/test_backend.rs`，基于 `vt100::Parser` 实现：

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

impl fmt::Display for VT100Backend {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.crossterm_backend.writer().screen().contents())
    }
}
```

**核心特性**：
- 模拟真实终端的 ANSI 转义序列处理
- 支持颜色、光标移动、屏幕滚动等 VT100 功能
- 通过 `screen().contents()` 获取最终渲染的屏幕内容

**适用场景**：
- 复杂终端交互测试
- 需要验证 ANSI 颜色/样式的测试
- 分页、滚动功能测试

### 3.3 关键测试模式

#### 3.3.1 基础 Snapshot 测试模式

```rust
#[test]
fn transcript_overlay_snapshot_basic() {
    let mut overlay = TranscriptOverlay::new(vec![
        Arc::new(TestCell { lines: vec![Line::from("alpha")] }),
        Arc::new(TestCell { lines: vec![Line::from("beta")] }),
    ]);
    let mut term = Terminal::new(TestBackend::new(40, 10)).expect("term");
    term.draw(|f| overlay.render(f.area(), f.buffer_mut())).expect("draw");
    assert_snapshot!(term.backend());
}
```

#### 3.3.2 VT100 后端测试模式

```rust
#[test]
fn cwd_prompt_modal() {
    use crate::test_backend::VT100Backend;
    
    let mut terminal = Terminal::new(VT100Backend::new(80, 14)).expect("terminal");
    // ... 设置测试状态 ...
    terminal.draw(|f| { /* 渲染 UI */ }).expect("draw");
    insta::assert_snapshot!("cwd_prompt_modal", terminal.backend());
}
```

#### 3.3.3 文本渲染结果测试模式

```rust
#[test]
fn ps_output_empty_snapshot() {
    let cell = new_unified_exec_processes_output(Vec::new());
    let rendered = render_lines(&cell.display_lines(60)).join("\n");
    insta::assert_snapshot!(rendered);
}
```

### 3.4 Snapshot 更新工作流

根据 `AGENTS.md` 文档，snapshot 更新遵循以下流程：

```bash
# 1. 运行测试生成更新的 snapshot
 cargo test -p codex-tui

# 2. 查看待处理的 snapshot 变更
 cargo insta pending-snapshots -p codex-tui

# 3. 预览特定 snapshot 文件
 cargo insta show -p codex-tui path/to/file.snap.new

# 4. 接受所有新 snapshot（仅在确认变更符合预期后执行）
 cargo insta accept -p codex-tui
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心测试基础设施

| 文件路径 | 职责 |
|----------|------|
| `codex-rs/tui/src/test_backend.rs` | VT100Backend 实现，用于高级终端模拟 |
| `codex-rs/tui/Cargo.toml` | 测试依赖配置（insta、vt100 等） |

### 4.2 生成 Snapshot 的测试文件

| 文件路径 | 测试功能域 | Snapshot 数量 |
|----------|------------|---------------|
| `codex-rs/tui/src/diff_render.rs` | Diff 渲染 | ~20 |
| `codex-rs/tui/src/history_cell.rs` | 历史记录单元格 | ~35 |
| `codex-rs/tui/src/app.rs` | 应用级功能 | ~5 |
| `codex-rs/tui/src/pager_overlay.rs` | 分页覆盖层 | ~5 |
| `codex-rs/tui/src/resume_picker.rs` | 会话选择器 | ~5 |
| `codex-rs/tui/src/markdown_render_tests.rs` | Markdown 渲染 | ~2 |
| `codex-rs/tui/src/status_indicator_widget.rs` | 状态指示器 | ~5 |
| `codex-rs/tui/src/multi_agents.rs` | 多 Agent 协作 | ~2 |
| `codex-rs/tui/src/cwd_prompt.rs` | CWD 提示 | ~2 |
| `codex-rs/tui/src/update_prompt.rs` | 更新提示 | ~1 |
| `codex-rs/tui/src/model_migration.rs` | 模型迁移 | ~4 |

### 4.3 Snapshot 文件存储位置

```
codex-rs/tui/src/snapshots/
├── codex_tui__app__tests__*.snap
├── codex_tui__cwd_prompt__tests__*.snap
├── codex_tui__diff_render__tests__*.snap
├── codex_tui__history_cell__tests__*.snap
├── codex_tui__markdown_render__tests__*.snap
├── codex_tui__model_migration__tests__*.snap
├── codex_tui__multi_agents__tests__*.snap
├── codex_tui__pager_overlay__tests__*.snap
├── codex_tui__resume_picker__tests__*.snap
├── codex_tui__status_indicator_widget__tests__*.snap
└── codex_tui__update_prompt__tests__*.snap
```

---

## 5. 依赖与外部交互

### 5.1 外部依赖

| 依赖 | 版本 | 用途 |
|------|------|------|
| `insta` | workspace | 快照测试框架，提供 `assert_snapshot!` 宏 |
| `vt100` | workspace | VT100 终端模拟器，用于 `VT100Backend` |
| `ratatui` | workspace | TUI 框架，提供 `TestBackend` 和渲染基础设施 |
| `crossterm` | workspace | 跨平台终端控制，用于颜色输出强制 |
| `pretty_assertions` | workspace | 美观的断言差异输出 |

### 5.2 内部依赖

| 模块 | 依赖关系 |
|------|----------|
| `test_backend.rs` | 被 `cwd_prompt.rs`, `model_migration.rs`, `insert_history.rs`, `update_prompt.rs`, `resume_picker.rs`, `chatwidget/tests.rs`, `onboarding/trust_directory.rs`, `bottom_pane/footer.rs` 导入 |
| `snapshots/` | 被 `insta` 框架在测试时读取 |

### 5.3 与 Cargo/Insta 的集成

**Insta 配置**（通过 `Cargo.toml` 隐式使用默认配置）：
- Snapshot 输出目录：`src/snapshots/`（默认）
- Snapshot 格式：YAML 前置元数据 + 内联内容

**测试执行**：
```bash
# 运行特定 crate 的测试
cargo test -p codex-tui

# 查看 pending snapshots
cargo insta pending-snapshots -p codex-tui

# 接受 snapshots
cargo insta accept -p codex-tui
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 平台相关差异

**问题**：某些 snapshot 文件包含平台特定的内容（如 `renders_with_queued_messages@macos.snap`）。

**影响**：跨平台测试可能导致 snapshot 不匹配。

**缓解措施**：
- 使用条件编译 `#[cfg(target_os = "macos")]` 区分平台特定测试
- 使用 `insta::with_settings!` 设置平台无关的测试环境

#### 6.1.2 时间敏感渲染

**问题**：某些 UI 组件包含时间依赖的渲染（如计时器、spinner）。

**示例**：`status_indicator_widget.rs` 中的测试需要冻结时间：
```rust
w.is_paused = true;
w.elapsed_running = Duration::ZERO;
```

**风险**：如果时间未正确冻结，snapshot 将不稳定。

#### 6.1.3 ANSI 颜色序列依赖

**问题**：VT100Backend 生成的 snapshot 包含 ANSI 转义序列，人工审查困难。

**示例**：
```
"  └ assets/banner.txt (+3 -0)                                                   "
"    1 +HEADER	VALUE                                                             "
"    2 +rocket	🚀                                                                " Hidden by multi-width symbols: [(15, " ")]
```

### 6.2 边界情况

#### 6.2.1 终端尺寸边界

测试使用固定的终端尺寸（常见：80x24, 40x10, 120x40 等）。实际终端尺寸变化可能导致：
- 文本换行行为差异
- 截断/省略号显示差异

#### 6.2.2 多宽度字符处理

Snapshot 文件显示多宽度字符（如 emoji、CJK 字符）有特殊处理：
```
"    2 +rocket	🚀                                                                " Hidden by multi-width symbols: [(15, " ")]
```

这表明 `insta` 或自定义逻辑处理了多宽度字符的显示问题。

### 6.3 改进建议

#### 6.3.1 增加自动化审查工具

**建议**：开发脚本自动验证 snapshot 变更的合理性：
```bash
# 示例：检查新增 snapshot 是否包含意外变更
scripts/verify-snapshot-changes.sh
```

#### 6.3.2 统一测试辅助函数

**现状**：多个测试文件定义了类似的辅助函数（如 `snapshot_lines`, `render_lines`）。

**建议**：提取通用测试辅助函数到 `test_helpers.rs`：
```rust
// 建议新增文件: codex-rs/tui/src/test_helpers.rs
pub fn snapshot_widget<W: Widget>(name: &str, widget: W, width: u16, height: u16);
pub fn snapshot_lines(name: &str, lines: Vec<Line>, width: u16, height: u16);
pub fn render_lines(lines: &[Line]) -> Vec<String>;
```

#### 6.3.3 增加视觉回归测试覆盖率

**现状**：部分复杂组件（如 `chatwidget`）的 snapshot 测试分散在 `tests.rs` 子模块中。

**建议**：
- 为关键用户流程（如完整对话流程）添加集成级 snapshot 测试
- 考虑使用 `insta::glob!` 批量测试多种输入组合

#### 6.3.4 优化 CI 中的 Snapshot 测试

**建议**：
- 在 CI 中固定终端颜色输出设置（`FORCE_COLOR=1`）
- 使用 `INSTA_UPDATE=noop` 防止 CI 意外更新 snapshots
- 为不同平台（Linux、macOS）分别维护 platform-specific snapshots

#### 6.3.5 文档化 Snapshot 更新流程

**建议**：在项目文档中明确：
- 何时应该更新 snapshot（预期内 UI 变更）
- 如何审查 snapshot diff（使用 `cargo insta show`）
- 谁有权限接受 snapshot 变更（代码审查要求）

---

## 7. 附录：Snapshot 文件完整清单

截至研究时，目录包含 83 个 snapshot 文件，按模块分类：

### app（5 个）
- `codex_tui__app__tests__agent_picker_item_name.snap`
- `codex_tui__app__tests__clear_ui_after_long_transcript_fresh_header_only.snap`
- `codex_tui__app__tests__clear_ui_header_fast_status_gpt54_only.snap`
- `codex_tui__app__tests__model_migration_prompt_shows_for_hidden_model.snap`
- `codex_tui__app__tests__startup_custom_prompt_deprecation_notice.snap`

### cwd_prompt（2 个）
- `codex_tui__cwd_prompt__tests__cwd_prompt_fork_modal.snap`
- `codex_tui__cwd_prompt__tests__cwd_prompt_modal.snap`

### diff_render（20 个）
包含 diff 画廊（80x24, 94x35, 120x40）、添加/删除/更新块、语法高亮、换行等测试

### history_cell（35 个）
涵盖 MCP 工具调用、命令输出、计划更新、Web 搜索、会话信息等多种场景

### markdown_render（2 个）
- `codex_tui__markdown_render__markdown_render_tests__markdown_render_complex_snapshot.snap`
- `codex_tui__markdown_render__markdown_render_tests__markdown_render_file_link_snapshot.snap`

### model_migration（4 个）
- `codex_tui__model_migration__tests__model_migration_prompt.snap`
- `codex_tui__model_migration__tests__model_migration_prompt_gpt5_codex.snap`
- `codex_tui__model_migration__tests__model_migration_prompt_gpt5_codex_mini.snap`
- `codex_tui__model_migration__tests__model_migration_prompt_gpt5_family.snap`

### multi_agents（2 个）
- `codex_tui__multi_agents__tests__collab_agent_transcript.snap`
- `codex_tui__multi_agents__tests__collab_resume_interrupted.snap`

### pager_overlay（5 个）
涵盖转录本覆盖层、静态覆盖层、VT100 滚动等场景

### resume_picker（4 个）
- `codex_tui__resume_picker__tests__resume_picker_screen.snap`
- `codex_tui__resume_picker__tests__resume_picker_search_error.snap`
- `codex_tui__resume_picker__tests__resume_picker_table.snap`
- `codex_tui__resume_picker__tests__resume_picker_thread_names.snap`

### status_indicator_widget（5 个）
包含工作状态、队列消息、截断、换行等场景，其中一个为 macOS 特定

### update_prompt（1 个）
- `codex_tui__update_prompt__tests__update_prompt_modal.snap`

---

*文档生成时间：2026-03-22*
*基于 codex-rs/tui 代码库研究*
