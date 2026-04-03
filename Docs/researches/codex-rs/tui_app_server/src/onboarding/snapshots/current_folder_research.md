# 研究文档：codex-rs/tui_app_server/src/onboarding/snapshots

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 目录定位

`snapshots/` 目录位于 `codex-rs/tui_app_server/src/onboarding/` 下，是 **TUI App Server** 版本的 Codex CLI 的引导流程（Onboarding）UI 快照测试数据存储目录。

### 与 TUI 版本的关系

该目录与 `codex-rs/tui/src/onboarding/snapshots/` 目录存在**镜像关系**：
- `tui/` - 原始 TUI 实现
- `tui_app_server/` - 基于 App Server 架构的新版 TUI 实现

两个目录包含**相同内容的快照文件**，仅 `source` 字段不同：
- tui 版本：`source: tui/src/onboarding/trust_directory.rs`
- tui_app_server 版本：`source: tui_app_server/src/onboarding/trust_directory.rs`

### 职责范围

1. **UI 快照存储**：存储 `TrustDirectoryWidget` 组件的渲染输出快照
2. **回归测试保障**：确保信任目录选择界面的视觉输出在代码变更后保持一致
3. **跨架构一致性验证**：验证 tui 和 tui_app_server 两个版本的行为一致性

---

## 功能点目的

### 核心功能：目录信任确认界面

`snapshots/` 目录服务于 **Trust Directory（目录信任）** 引导步骤，该步骤是 Codex CLI 首次在目录中运行时的安全确认流程。

#### 用户场景

```
> You are in /workspace/project

  Do you trust the contents of this directory? Working with untrusted
  contents comes with higher risk of prompt injection.

› 1. Yes, continue                                                    
  2. No, quit

  Press enter to continue
```

#### 安全目的

1. **Prompt Injection 防护**：警告用户在未受信任目录中运行 Codex 的风险
2. **项目级信任管理**：通过 Git 仓库根目录识别项目，持久化信任决策到配置
3. **首次运行保护**：仅在 `trust_level` 未设置时显示（`should_show_trust_screen` 判断）

### 快照测试目的

| 目的 | 说明 |
|------|------|
| 视觉回归检测 | 捕获 UI 渲染输出的意外变更 |
| 跨平台一致性 | 验证不同平台下的渲染一致性 |
| 文档化预期输出 | 快照文件本身作为 UI 行为的文档 |

---

## 具体技术实现

### 快照文件结构

#### 文件列表

```
codex-rs/tui_app_server/src/onboarding/snapshots/
├── codex_tui__onboarding__trust_directory__tests__renders_snapshot_for_git_repo.snap
└── codex_tui_app_server__onboarding__trust_directory__tests__renders_snapshot_for_git_repo.snap
```

#### 快照文件格式（YAML）

```yaml
---
source: tui_app_server/src/onboarding/trust_directory.rs
expression: terminal.backend()
---
> You are in /workspace/project

  Do you trust the contents of this directory? Working with untrusted
  contents comes with higher risk of prompt injection.

› 1. Yes, continue                                                    
  2. No, quit

  Press enter to continue
```

### 测试实现详解

#### 测试代码（trust_directory.rs）

```rust
#[test]
fn renders_snapshot_for_git_repo() {
    let codex_home = TempDir::new().expect("temp home");
    let widget = TrustDirectoryWidget {
        codex_home: codex_home.path().to_path_buf(),
        cwd: PathBuf::from("/workspace/project"),
        show_windows_create_sandbox_hint: false,
        should_quit: false,
        selection: None,
        highlighted: TrustDirectorySelection::Trust,
        error: None,
    };

    let mut terminal = Terminal::new(VT100Backend::new(70, 14)).expect("terminal");
    terminal
        .draw(|f| (&widget).render_ref(f.area(), f.buffer_mut()))
        .expect("draw");

    insta::assert_snapshot!(terminal.backend());
}
```

#### 关键技术点

| 技术点 | 说明 |
|--------|------|
| `VT100Backend` | 自定义的 ratatui 后端，基于 vt100 仿真器捕获终端输出 |
| `tempfile::TempDir` | 创建隔离的临时配置目录，避免测试副作用 |
| `insta::assert_snapshot!` | 使用 insta crate 进行快照断言 |
| 终端尺寸 | 70x14，模拟标准终端窗口 |

### VT100Backend 实现

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
}

impl fmt::Display for VT100Backend {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.crossterm_backend.writer().screen().contents())
    }
}
```

### TrustDirectoryWidget 渲染逻辑

```rust
impl WidgetRef for &TrustDirectoryWidget {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        let mut column = ColumnRenderable::new();

        // 1. 当前目录显示
        column.push(Line::from(vec![
            "> ".into(),
            "You are in ".bold(),
            self.cwd.to_string_lossy().to_string().into(),
        ]));
        column.push("");

        // 2. 安全警告信息
        column.push(
            Paragraph::new(
                "Do you trust the contents of this directory? Working with untrusted contents comes with higher risk of prompt injection.".to_string(),
            )
                .wrap(Wrap { trim: true })
                .inset(Insets::tlbr(/*top*/ 0, /*left*/ 2, /*bottom*/ 0, /*right*/ 0)),
        );
        column.push("");

        // 3. 选项列表（Yes/No）
        let options: Vec<(&str, TrustDirectorySelection)> = vec![
            ("Yes, continue", TrustDirectorySelection::Trust),
            ("No, quit", TrustDirectorySelection::Quit),
        ];

        for (idx, (text, selection)) in options.iter().enumerate() {
            column.push(selection_option_row(
                idx,
                text.to_string(),
                self.highlighted == *selection,
            ));
        }
        // ... 错误提示和按键提示
    }
}
```

### 信任决策处理流程

```rust
impl TrustDirectoryWidget {
    fn handle_trust(&mut self) {
        // 1. 解析 Git 仓库根目录
        let target =
            resolve_root_git_project_for_trust(&self.cwd).unwrap_or_else(|| self.cwd.clone());
        
        // 2. 持久化信任级别到配置
        if let Err(e) = set_project_trust_level(&self.codex_home, &target, TrustLevel::Trusted) {
            tracing::error!("Failed to set project trusted: {e:?}");
            self.error = Some(format!("Failed to set trust for {}: {e}", target.display()));
        }

        self.selection = Some(TrustDirectorySelection::Trust);
    }
}
```

---

## 关键代码路径与文件引用

### 核心文件依赖图

```
snapshots/*.snap
    ↑（被验证）
trust_directory.rs
    ├── test_backend.rs (VT100Backend)
    ├── onboarding_screen.rs (StepState, KeyboardHandler)
    ├── codex_core::config::set_project_trust_level
    ├── codex_core::git_info::resolve_root_git_project_for_trust
    └── codex_protocol::config_types::TrustLevel
```

### 文件引用清单

| 文件路径 | 角色 | 关键引用 |
|----------|------|----------|
| `codex-rs/tui_app_server/src/onboarding/trust_directory.rs` | 主实现 | 包含快照测试用例 |
| `codex-rs/tui_app_server/src/onboarding/onboarding_screen.rs` | 流程编排 | `StepState`, `KeyboardHandler` trait |
| `codex-rs/tui_app_server/src/test_backend.rs` | 测试基础设施 | `VT100Backend` 结构体 |
| `codex-rs/tui_app_server/src/onboarding/mod.rs` | 模块导出 | `pub use trust_directory::TrustDirectorySelection` |
| `codex-rs/core/src/config/mod.rs` | 配置持久化 | `set_project_trust_level()` 函数 |
| `codex-rs/core/src/git_info.rs` | Git 仓库解析 | `resolve_root_git_project_for_trust()` 函数 |
| `codex-rs/protocol/src/config_types.rs` | 类型定义 | `TrustLevel` enum |
| `codex-rs/tui_app_server/Cargo.toml` | 依赖配置 | `insta = { workspace = true }` |

### 配置持久化细节

信任级别存储在 `CODEX_HOME/config.toml` 中：

```toml
[projects]
[projects."/path/to/project"]
trust_level = "trusted"
```

相关代码（`core/src/config/mod.rs`）：

```rust
pub fn set_project_trust_level(
    codex_home: &Path,
    project_path: &Path,
    trust_level: TrustLevel,
) -> anyhow::Result<()> {
    use crate::config::edit::ConfigEditsBuilder;

    ConfigEditsBuilder::new(codex_home)
        .set_project_trust_level(project_path, trust_level)
        .apply_blocking()
}
```

---

## 依赖与外部交互

### 外部 Crate 依赖

| Crate | 用途 | 版本来源 |
|-------|------|----------|
| `insta` | 快照测试框架 | workspace |
| `vt100` | 终端仿真器 | workspace |
| `ratatui` | TUI 渲染 | workspace |
| `crossterm` | 跨平台终端控制 | workspace |
| `tempfile` | 临时目录 | workspace |
| `pretty_assertions` | 测试断言增强 | workspace |

### 内部模块依赖

```rust
// 核心依赖
use codex_core::config::set_project_trust_level;
use codex_core::git_info::resolve_root_git_project_for_trust;
use codex_protocol::config_types::TrustLevel;

// TUI 渲染依赖
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::Stylize;
use ratatui::text::Line;
use ratatui::widgets::Paragraph;
use ratatui::widgets::WidgetRef;
use ratatui::widgets::Wrap;

// 输入处理依赖
use crossterm::event::KeyCode;
use crossterm::event::KeyEvent;
use crossterm::event::KeyEventKind;
```

### 与 App Server 的交互

在 `tui_app_server` 版本中，onboarding 流程通过 `AppServerSession` 与后端通信：

```rust
pub(crate) async fn run_onboarding_app(
    args: OnboardingScreenArgs,
    mut app_server: Option<AppServerSession>,
    tui: &mut Tui,
) -> Result<OnboardingResult> {
    // ... 事件循环处理 AppServerEvent
}
```

---

## 风险、边界与改进建议

### 已知风险

#### 1. 快照文件重复维护

**风险描述**：
- tui 和 tui_app_server 两个版本维护几乎相同的快照文件
- 代码变更时需要同时更新两个目录的快照

**当前状态**：
```
tui/src/onboarding/snapshots/codex_tui__onboarding__trust_directory__tests__renders_snapshot_for_git_repo.snap
tui_app_server/src/onboarding/snapshots/codex_tui_app_server__onboarding__trust_directory__tests__renders_snapshot_for_git_repo.snap
```

**建议**：
- 考虑将公共快照提取到共享位置
- 或者通过符号链接减少重复

#### 2. 测试覆盖范围有限

**当前覆盖**：
- 仅测试了 Git 仓库场景的快照
- 未覆盖错误状态、Windows 沙箱提示等场景

**建议扩展**：
```rust
// 建议添加的测试用例
#[test]
fn renders_snapshot_with_error() { ... }

#[test]
fn renders_snapshot_with_windows_sandbox_hint() { ... }

#[test]
fn renders_snapshot_quit_selected() { ... }
```

#### 3. 硬编码终端尺寸

**问题**：
```rust
let mut terminal = Terminal::new(VT100Backend::new(70, 14)).expect("terminal");
```

- 70x14 的尺寸可能无法覆盖所有 UI 布局场景
- 未测试窄终端或高终端的渲染效果

### 边界条件

| 边界条件 | 当前处理 | 潜在问题 |
|----------|----------|----------|
| 非 Git 目录 | 回退到 `cwd.clone()` | 信任设置粒度为当前目录 |
| Git worktree | 通过 `resolve_root_git_project_for_trust` 解析 | 复杂 worktree 结构可能解析失败 |
| 配置写入失败 | 显示错误信息 | 用户可能忽略错误提示 |
| 长路径显示 | 直接显示 | 可能超出终端宽度 |

### 改进建议

#### 1. 快照测试优化

```rust
// 建议：参数化测试覆盖更多场景
#[test]
fn renders_snapshot_for_various_states() {
    let states = vec![
        ("trust_selected", TrustDirectorySelection::Trust, None),
        ("quit_selected", TrustDirectorySelection::Quit, None),
        ("with_error", TrustDirectorySelection::Trust, Some("Error message")),
    ];
    
    for (name, highlighted, error) in states {
        // ... 使用 insta::with_settings 生成多快照
    }
}
```

#### 2. 路径截断处理

```rust
// 建议：在渲染时处理长路径
let display_path = if self.cwd.as_os_str().len() > max_width {
    format!("...{}", &self.cwd.to_string_lossy()[self.cwd.len() - max_width + 3..])
} else {
    self.cwd.to_string_lossy().to_string()
};
```

#### 3. 与 tui 版本的一致性检查

建议添加 CI 检查，确保两个版本的快照内容保持一致：

```bash
# 伪代码
diff <(cat tui/src/onboarding/snapshots/*.snap | grep -v "^source:") \
     <(cat tui_app_server/src/onboarding/snapshots/*.snap | grep -v "^source:")
```

### 相关 AGENTS.md 规范

根据项目 `AGENTS.md` 文件：

> **Snapshot tests**: any change that affects user-visible UI (including adding new UI) must include corresponding `insta` snapshot coverage

> **When UI or text output changes intentionally, update the snapshots**:
> - Run tests to generate any updated snapshots: `cargo test -p codex-tui`
> - Check what's pending: `cargo insta pending-snapshots -p codex-tui`
> - Review changes by reading the generated `*.snap.new` files
> - Only if you intend to accept all new snapshots in this crate, run: `cargo insta accept -p codex-tui`

---

## 总结

`snapshots/` 目录是 Codex CLI TUI App Server 版本 onboarding 流程的关键测试资产，主要用于：

1. **保障 Trust Directory UI 的视觉一致性**
2. **捕获回归问题**
3. **作为 UI 行为的活文档**

该目录与 `tui` 版本的对应目录存在镜像关系，需要在两个版本间保持同步。当前测试覆盖主要场景，但建议扩展更多边界条件的快照测试。
