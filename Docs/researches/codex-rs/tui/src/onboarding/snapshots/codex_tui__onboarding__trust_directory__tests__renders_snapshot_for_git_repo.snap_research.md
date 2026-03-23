# Trust Directory Snapshot 研究文档

## 文件基本信息

- **文件路径**: `codex-rs/tui/src/onboarding/snapshots/codex_tui__onboarding__trust_directory__tests__renders_snapshot_for_git_repo.snap`
- **来源代码**: `codex-rs/tui/src/onboarding/trust_directory.rs`
- **断言行号**: 218
- **测试框架**: `insta` (Rust snapshot testing)

---

## 1. 场景与职责

### 1.1 功能定位

该 snapshot 文件是 **Codex TUI（终端用户界面）** 中 **目录信任确认界面** 的 UI 渲染快照测试产物。它捕获了用户首次进入某个工作目录时，系统询问用户是否信任该目录内容的界面状态。

### 1.2 业务场景

当用户启动 Codex CLI 工具时，系统会检查当前工作目录的信任状态：

1. **首次访问**: 如果用户从未对该目录做出信任决策，显示信任确认界面
2. **Git 仓库检测**: 系统会尝试解析 Git 仓库根目录，以便在仓库级别统一应用信任设置
3. **安全决策**: 用户需要明确选择"信任并继续"或"不信任并退出"

### 1.3 安全背景

信任目录功能是为了防范 **Prompt Injection（提示注入攻击）**。当工作目录包含不受信任的内容（如从互联网克隆的仓库）时，恶意文件可能通过特殊构造的内容影响 AI 的行为。通过显式信任确认，用户可以意识到潜在风险。

---

## 2. 功能点目的

### 2.1 核心目的

| 目的 | 说明 |
|------|------|
| **安全提示** | 提醒用户当前工作目录可能存在 prompt injection 风险 |
| **信任决策** | 收集用户对工作目录的信任决策（信任/不信任） |
| **配置持久化** | 将信任决策保存到 `~/.codex/config.toml` 中 |
| **Git 仓库感知** | 支持 Git 工作树（worktree）场景，确保信任设置应用到正确的路径 |

### 2.2 Snapshot 测试目的

该 snapshot 测试验证：
- 信任目录界面的视觉渲染是否符合预期
- 文本内容、布局、样式是否正确
- 选项列表（"Yes, continue" / "No, quit"）是否正确显示
- 当前工作目录路径是否正确展示

---

## 3. 具体技术实现

### 3.1 关键数据结构

```rust
// TrustDirectoryWidget - 信任目录界面的核心组件
pub(crate) struct TrustDirectoryWidget {
    pub codex_home: PathBuf,                    // ~/.codex 目录路径
    pub cwd: PathBuf,                           // 当前工作目录
    pub show_windows_create_sandbox_hint: bool, // Windows 沙箱提示
    pub should_quit: bool,                      // 是否应该退出
    pub selection: Option<TrustDirectorySelection>, // 用户选择
    pub highlighted: TrustDirectorySelection,   // 当前高亮选项
    pub error: Option<String>,                  // 错误信息
}

// 信任选择枚举
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TrustDirectorySelection {
    Trust,  // 信任并继续
    Quit,   // 不信任，退出
}
```

### 3.2 关键流程

#### 3.2.1 界面渲染流程

```rust
impl WidgetRef for &TrustDirectoryWidget {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        let mut column = ColumnRenderable::new();

        // 1. 显示当前路径
        column.push(Line::from(vec![
            "> ".into(),
            "You are in ".bold(),
            self.cwd.to_string_lossy().to_string().into(),
        ]));

        // 2. 显示安全提示文本
        column.push(
            Paragraph::new("Do you trust the contents of this directory? ...")
                .wrap(Wrap { trim: true })
                .inset(Insets::tlbr(0, 2, 0, 0)),
        );

        // 3. 显示选项列表
        let options = vec![
            ("Yes, continue", TrustDirectorySelection::Trust),
            ("No, quit", TrustDirectorySelection::Quit),
        ];
        for (idx, (text, selection)) in options.iter().enumerate() {
            column.push(selection_option_row(idx, text.to_string(), self.highlighted == *selection));
        }

        // 4. 显示按键提示
        column.push(
            Line::from(vec![
                "Press ".dim(),
                key_hint::plain(KeyCode::Enter).into(),
                " to continue".dim(),
            ])
            .inset(Insets::tlbr(0, 2, 0, 0)),
        );

        column.render(area, buf);
    }
}
```

#### 3.2.2 键盘事件处理

```rust
impl KeyboardHandler for TrustDirectoryWidget {
    fn handle_key_event(&mut self, key_event: KeyEvent) {
        if key_event.kind == KeyEventKind::Release {
            return;  // 忽略按键释放事件
        }

        match key_event.code {
            KeyCode::Up | KeyCode::Char('k') => {
                self.highlighted = TrustDirectorySelection::Trust;
            }
            KeyCode::Down | KeyCode::Char('j') => {
                self.highlighted = TrustDirectorySelection::Quit;
            }
            KeyCode::Char('1') | KeyCode::Char('y') => self.handle_trust(),
            KeyCode::Char('2') | KeyCode::Char('n') => self.handle_quit(),
            KeyCode::Enter => match self.highlighted {
                TrustDirectorySelection::Trust => self.handle_trust(),
                TrustDirectorySelection::Quit => self.handle_quit(),
            },
            _ => {}
        }
    }
}
```

#### 3.2.3 信任设置处理

```rust
impl TrustDirectoryWidget {
    fn handle_trust(&mut self) {
        // 1. 解析 Git 仓库根目录（支持 worktree）
        let target = resolve_root_git_project_for_trust(&self.cwd)
            .unwrap_or_else(|| self.cwd.clone());
        
        // 2. 保存信任配置到 config.toml
        if let Err(e) = set_project_trust_level(
            &self.codex_home, 
            &target, 
            TrustLevel::Trusted
        ) {
            tracing::error!("Failed to set project trusted: {e:?}");
            self.error = Some(format!("Failed to set trust for {}: {e}", target.display()));
        }

        self.selection = Some(TrustDirectorySelection::Trust);
    }

    fn handle_quit(&mut self) {
        self.highlighted = TrustDirectorySelection::Quit;
        self.should_quit = true;
    }
}
```

### 3.3 信任级别配置协议

信任配置存储在 `~/.codex/config.toml` 中，格式如下：

```toml
[projects."/path/to/project"]
trust_level = "trusted"  # 或 "untrusted"
```

配置通过 `set_project_trust_level` 函数写入，使用 `toml_edit` 库确保格式美观（非内联表格形式）。

### 3.4 Git 仓库根目录解析

```rust
/// 解析用于信任检查的 Git 仓库根目录
/// 处理 worktree 场景，返回主仓库路径而非 worktree 路径
pub fn resolve_root_git_project_for_trust(cwd: &Path) -> Option<PathBuf> {
    let base = if cwd.is_dir() { cwd } else { cwd.parent()? };
    let (repo_root, dot_git) = find_ancestor_git_entry(base)?;
    
    if dot_git.is_dir() {
        return Some(canonicalize_or_raw(repo_root));
    }

    // 处理 .git 文件（worktree 场景）
    let git_dir_s = std::fs::read_to_string(&dot_git).ok()?;
    let git_dir_rel = git_dir_s.trim().strip_prefix("gitdir:")?.trim();
    let git_dir_path = canonicalize_or_raw(resolve_path(&repo_root, &PathBuf::from(git_dir_rel)));
    
    // 向上导航到主仓库目录
    let worktrees_dir = git_dir_path.parent()?;
    let common_dir = worktrees_dir.parent()?;
    let main_repo_root = common_dir.parent()?;
    Some(canonicalize_or_raw(main_repo_root.to_path_buf()))
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心实现文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/onboarding/trust_directory.rs` | TrustDirectoryWidget 实现，包含渲染、事件处理、信任设置逻辑 |
| `codex-rs/tui/src/onboarding/onboarding_screen.rs` | OnboardingScreen 状态机，管理多个 onboarding 步骤 |
| `codex-rs/tui/src/onboarding/mod.rs` | Onboarding 模块导出 |

### 4.2 依赖文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/selection_list.rs` | 选项列表渲染辅助函数 `selection_option_row` |
| `codex-rs/tui/src/key_hint.rs` | 按键提示渲染（如 "enter"） |
| `codex-rs/tui/src/render/renderable.rs` | 可渲染组件抽象（ColumnRenderable, RowRenderable 等） |
| `codex-rs/tui/src/render/mod.rs` | Insets 定义和 Rect 扩展 |
| `codex-rs/tui/src/test_backend.rs` | VT100Backend 测试后端实现 |

### 4.3 核心库依赖

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/src/config/mod.rs` | `set_project_trust_level` 配置写入函数 |
| `codex-rs/core/src/git_info.rs` | `resolve_root_git_project_for_trust` Git 仓库解析 |
| `codex-rs/protocol/src/config_types.rs` | `TrustLevel` 枚举定义（Trusted/Untrusted） |

### 4.4 并行实现

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui_app_server/src/onboarding/trust_directory.rs` | tui_app_server 中的并行实现，代码结构与 TUI 版本基本一致 |

---

## 5. 依赖与外部交互

### 5.1 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `ratatui` | 终端 UI 渲染框架 |
| `crossterm` | 跨平台终端事件处理（键盘输入） |
| `insta` | Snapshot 测试框架 |
| `tempfile` | 测试时创建临时目录 |
| `vt100` | VT100 终端模拟（测试后端） |
| `toml_edit` | TOML 配置文件编辑 |

### 5.2 项目内部 crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_core` | 配置管理、Git 信息解析 |
| `codex_protocol` | 共享类型定义（TrustLevel 等） |

### 5.3 配置交互

```
~/.codex/config.toml
├── [projects."<path>"]
│   └── trust_level = "trusted" | "untrusted"
```

### 5.4 与 Onboarding 流程的集成

```
lib.rs:run_ratatui_app()
├── should_show_trust_screen(&config)  [检查是否需要显示信任界面]
├── run_onboarding_app()               [如果未登录或未信任]
│   └── OnboardingScreen::new()
│       └── Step::TrustDirectory(TrustDirectoryWidget)
└── App::run(..., should_show_trust_screen, ...)
```

---

## 6. 风险、边界与改进建议

### 6.1 当前风险

#### 6.1.1 安全风险

| 风险 | 说明 | 缓解措施 |
|------|------|---------|
| Prompt Injection | 不受信任的目录内容可能包含恶意提示 | 强制信任确认界面 |
| 配置篡改 | `config.toml` 中的信任配置可能被恶意修改 | 文件权限控制（Unix mode 0o600）|
| Worktree 绕过 | 用户可能通过 worktree 路径绕过信任检查 | `resolve_root_git_project_for_trust` 统一解析到主仓库 |

#### 6.1.2 功能风险

| 风险 | 说明 |
|------|------|
| Snapshot 漂移 | UI 样式或文本变更会导致 snapshot 测试失败 |
| 路径编码问题 | Windows 路径中的反斜杠需要转义处理 |
| Git 命令超时 | `git_info.rs` 中的命令有 5 秒超时保护 |

### 6.2 边界情况

#### 6.2.1 测试边界

```rust
#[test]
fn renders_snapshot_for_git_repo() {
    let codex_home = TempDir::new().expect("temp home");
    let widget = TrustDirectoryWidget {
        codex_home: codex_home.path().to_path_buf(),
        cwd: PathBuf::from("/workspace/project"),  // 模拟路径
        show_windows_create_sandbox_hint: false,
        should_quit: false,
        selection: None,
        highlighted: TrustDirectorySelection::Trust,  // 默认高亮"信任"
        error: None,
    };

    // 70x14 的终端尺寸
    let mut terminal = Terminal::new(VT100Backend::new(70, 14)).expect("terminal");
    terminal.draw(|f| (&widget).render_ref(f.area(), f.buffer_mut())).expect("draw");

    insta::assert_snapshot!(terminal.backend());
}
```

**边界条件**:
- 终端尺寸固定为 70x14，可能无法覆盖所有实际场景
- 使用模拟路径 `/workspace/project`，非真实文件系统路径
- 测试不验证实际配置写入（仅验证渲染）

#### 6.2.2 运行时边界

| 场景 | 行为 |
|------|------|
| 非 Git 目录 | 直接使用 `cwd` 作为信任目标 |
| Git worktree | 解析到主仓库目录设置信任 |
| 配置写入失败 | 显示错误信息，不阻止用户继续 |
| 按键释放事件 | 被显式忽略，防止误触发 |

### 6.3 改进建议

#### 6.3.1 测试改进

1. **多尺寸 Snapshot 测试**
   ```rust
   // 建议添加不同终端尺寸的测试
   VT100Backend::new(50, 10)   // 小终端
   VT100Backend::new(100, 20)  // 大终端
   ```

2. **错误状态 Snapshot**
   ```rust
   // 测试配置写入失败时的错误显示
   error: Some("Failed to set trust...".to_string()),
   ```

3. **Windows 提示 Snapshot**
   ```rust
   // 测试 Windows 沙箱提示
   show_windows_create_sandbox_hint: true,
   ```

#### 6.3.2 功能改进

1. **信任撤销机制**
   - 当前一旦信任，只能通过手动编辑 `config.toml` 撤销
   - 建议添加"不再询问"但选择不信任的选项

2. **批量信任管理**
   - 提供命令行工具管理已信任的项目列表
   - 如 `codex trust list` / `codex trust remove <path>`

3. **信任过期机制**
   - 长时间未访问的信任目录可以提示重新确认

#### 6.3.3 代码改进

1. **国际化支持**
   - 当前界面文本硬编码为英文
   - 建议添加 i18n 支持

2. **可访问性**
   - 添加屏幕阅读器友好的输出
   - 支持高对比度模式

---

## 7. Snapshot 内容分析

### 7.1 实际 Snapshot 内容

```
---
source: tui/src/onboarding/trust_directory.rs
assertion_line: 218
expression: terminal.backend()
---
> You are in /workspace/project

  Do you trust the contents of this directory? Working with untrusted
  contents comes with higher risk of prompt injection.

› 1. Yes, continue                                                    
  2. No, quit

  Press enter to continue
```

### 7.2 内容解析

| 行 | 内容 | 说明 |
|---|------|------|
| 1 | `> You are in /workspace/project` | 路径提示，`>` 为提示符，路径高亮 |
| 2 | 空行 | 视觉分隔 |
| 3-4 | 安全提示文本 | 自动换行，左侧缩进 2 空格 |
| 5 | 空行 | 视觉分隔 |
| 6 | `› 1. Yes, continue` | 选中状态，`›` 为选中标记，青色高亮 |
| 7 | `  2. No, quit` | 未选中状态，普通样式 |
| 8 | 空行 | 视觉分隔 |
| 9 | `Press enter to continue` | 操作提示，灰色(dim)样式 |

### 7.3 样式验证点

- **路径**: 使用 `.bold()` 加粗显示
- **选中选项**: 使用 `.cyan()` 青色高亮
- **提示文本**: 使用 `.dim()` 灰色显示
- **缩进**: 安全提示和按键提示左侧缩进 2 空格

---

## 8. 相关测试覆盖

### 8.1 单元测试

| 测试函数 | 文件 | 说明 |
|---------|------|------|
| `renders_snapshot_for_git_repo` | `trust_directory.rs` | Snapshot 测试（本文件） |
| `release_event_does_not_change_selection` | `trust_directory.rs` | 验证按键释放不触发操作 |
| `windows_shows_trust_prompt_without_sandbox` | `lib.rs` | Windows 无沙箱场景 |
| `windows_shows_trust_prompt_with_sandbox` | `lib.rs` | Windows 有沙箱场景 |
| `untrusted_project_skips_trust_prompt` | `lib.rs` | 已标记不信任项目跳过提示 |

### 8.2 集成测试

- `config_rebuild_changes_trust_defaults_with_cwd` - 验证配置重载时信任设置生效

---

## 9. 总结

该 snapshot 文件是 Codex TUI 安全机制的重要组成部分，它：

1. **确保安全**: 通过显式信任确认，防范 prompt injection 攻击
2. **提供良好 UX**: 清晰的界面提示和键盘导航
3. **支持 Git 工作流**: 正确处理 worktree 场景
4. **持久化配置**: 信任决策保存到配置文件，避免重复询问

snapshot 测试确保了界面渲染的稳定性，任何 UI 变更都需要显式更新 snapshot，从而保证用户体验的一致性。
