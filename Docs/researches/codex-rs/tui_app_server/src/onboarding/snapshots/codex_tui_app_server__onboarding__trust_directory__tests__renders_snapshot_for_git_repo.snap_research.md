# 研究文档：codex_tui_app_server__onboarding__trust_directory__tests__renders_snapshot_for_git_repo.snap

## 场景与职责

此文件是 **insta snapshot 测试快照文件**，用于验证 `codex-rs/tui_app_server/src/onboarding/trust_directory.rs` 中 `TrustDirectoryWidget` 组件的 UI 渲染输出。

### 关键背景：tui_app_server 与 tui 的关系
根据项目 `AGENTS.md` 规范：
> "When a change lands in `codex-rs/tui` and `codex-rs/tui_app_server` has a parallel implementation of the same behavior, reflect the change in `codex-rs/tui_app_server` too unless there is a documented reason not to."

`tui_app_server` 是 `tui` 的并行实现，两者共享相同的 onboarding 流程和 UI 组件逻辑。此快照文件确保 `tui_app_server` 版本的 `TrustDirectoryWidget` 渲染输出与 `tui` 版本保持一致。

### 业务场景
当用户通过 app-server 模式启动 Codex TUI 时，系统需要用户确认是否信任当前工作目录。这是 Codex 的安全机制，防止在不信任的代码库中执行可能包含 prompt injection 风险的操作。

## 功能点目的

### 1. 并行实现的 UI 快照测试
- **目的**：验证 `tui_app_server` 版本的 `TrustDirectoryWidget` 渲染正确性
- **测试名称**：`renders_snapshot_for_git_repo`
- **源文件**：`tui_app_server/src/onboarding/trust_directory.rs`
- **验证内容**：与 `tui` 版本一致的终端渲染输出

### 2. 跨 crate 一致性保证
两个 crate 的快照内容几乎完全一致，确保：
- 用户体验的一致性（无论通过哪种入口启动）
- 代码变更时的同步更新提醒

### 快照内容对比
| 字段 | tui 版本 | tui_app_server 版本 |
|------|----------|---------------------|
| source | `tui/src/onboarding/trust_directory.rs` | `tui_app_server/src/onboarding/trust_directory.rs` |
| assertion_line | 218 | （未显示，推测类似） |
| 渲染输出 | 完全一致 | 完全一致 |

## 具体技术实现

### 代码复用结构
`tui_app_server` 的 `trust_directory.rs` 与 `tui` 版本是**逐行复制**的相同实现：

```rust
// 两个文件内容基本一致
// codex-rs/tui/src/onboarding/trust_directory.rs
// codex-rs/tui_app_server/src/onboarding/trust_directory.rs
```

#### TrustDirectoryWidget 结构
```rust
pub(crate) struct TrustDirectoryWidget {
    pub codex_home: PathBuf,                    // Codex 配置目录
    pub cwd: PathBuf,                           // 当前工作目录
    pub show_windows_create_sandbox_hint: bool, // Windows 沙箱提示
    pub should_quit: bool,                      // 是否退出标志
    pub selection: Option<TrustDirectorySelection>, // 用户选择
    pub highlighted: TrustDirectorySelection,   // 当前高亮选项
    pub error: Option<String>,                  // 错误信息
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TrustDirectorySelection {
    Trust,  // 选项 1: Yes, continue
    Quit,   // 选项 2: No, quit
}
```

### 渲染实现

#### 界面布局（WidgetRef::render_ref）
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

        // 2. 风险提示（带自动换行）
        column.push(
            Paragraph::new("Do you trust the contents...")
                .wrap(Wrap { trim: true })
                .inset(Insets::tlbr(0, 2, 0, 0)),
        );
        column.push("");

        // 3. 选项列表
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
        // ... 继续按钮和错误显示
    }
}
```

#### 选项行渲染样式
```rust
// selection_list.rs
pub(crate) fn selection_option_row(
    index: usize,
    label: String,
    is_selected: bool,
) -> Box<dyn Renderable> {
    let prefix = if is_selected {
        format!("› {}. ", index + 1)  // 选中：› 1. （青色）
    } else {
        format!("  {}. ", index + 1)  // 未选中：  2. （默认）
    };
    let style = if is_selected {
        Style::default().cyan()
    } else {
        Style::default()
    };
    // ...
}
```

### 键盘事件处理
```rust
impl KeyboardHandler for TrustDirectoryWidget {
    fn handle_key_event(&mut self, key_event: KeyEvent) {
        if key_event.kind == KeyEventKind::Release {
            return;
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

### 信任设置核心逻辑
```rust
fn handle_trust(&mut self) {
    // 1. 解析 Git 仓库根目录（支持普通仓库和 worktree）
    let target = resolve_root_git_project_for_trust(&self.cwd)
        .unwrap_or_else(|| self.cwd.clone());
    
    // 2. 写入信任配置到 ~/.codex/config.toml
    if let Err(e) = set_project_trust_level(&self.codex_home, &target, TrustLevel::Trusted) {
        tracing::error!("Failed to set project trusted: {e:?}");
        self.error = Some(format!("Failed to set trust for {}: {e}", target.display()));
    }

    self.selection = Some(TrustDirectorySelection::Trust);
}
```

### Git 仓库根目录解析
```rust
// codex-rs/core/src/git_info.rs:606-628
pub fn resolve_root_git_project_for_trust(cwd: &Path) -> Option<PathBuf> {
    let base = if cwd.is_dir() { cwd } else { cwd.parent()? };
    let (repo_root, dot_git) = find_ancestor_git_entry(base)?;
    
    // 普通 Git 仓库：.git 是目录
    if dot_git.is_dir() {
        return Some(canonicalize_or_raw(repo_root));
    }

    // Git worktree：.git 是文件，包含 gitdir 指向实际仓库
    let git_dir_s = std::fs::read_to_string(&dot_git).ok()?;
    let git_dir_rel = git_dir_s.trim().strip_prefix("gitdir:")?.trim();
    // ... 解析到主仓库根目录
    let main_repo_root = common_dir.parent()?;
    Some(canonicalize_or_raw(main_repo_root.to_path_buf()))
}
```

## 关键代码路径与文件引用

### 测试相关
| 文件 | 职责 |
|------|------|
| `codex-rs/tui_app_server/src/onboarding/trust_directory.rs:204-223` | 快照测试定义 |
| `codex-rs/tui_app_server/src/onboarding/snapshots/*.snap` | 期望的渲染输出快照 |

### 并行实现文件
| tui 版本 | tui_app_server 版本 | 说明 |
|----------|---------------------|------|
| `tui/src/onboarding/trust_directory.rs` | `tui_app_server/src/onboarding/trust_directory.rs` | 完全相同的实现 |
| `tui/src/onboarding/mod.rs` | `tui_app_server/src/onboarding/mod.rs` | 模块导出 |
| `tui/src/onboarding/onboarding_screen.rs` | `tui_app_server/src/onboarding/onboarding_screen.rs` | Step 状态机 |

### 共享依赖
| 文件 | 职责 |
|------|------|
| `codex-rs/core/src/config/mod.rs:1146-1156` | `set_project_trust_level` 配置写入 |
| `codex-rs/core/src/git_info.rs:606-628` | Git 仓库根目录解析 |
| `codex-rs/protocol/src/config_types.rs` | `TrustLevel` 枚举定义 |

### onboarding 流程集成
```rust
// onboarding_screen.rs:34-50
#[allow(clippy::large_enum_variant)]
enum Step {
    Welcome(WelcomeWidget),
    Auth(AuthModeWidget),
    TrustDirectory(TrustDirectoryWidget),  // 信任确认步骤
}

// onboarding_screen.rs:120-131
if show_trust_screen {
    steps.push(Step::TrustDirectory(TrustDirectoryWidget {
        cwd,
        codex_home,
        show_windows_create_sandbox_hint,
        should_quit: false,
        selection: None,
        highlighted: TrustDirectorySelection::Trust,
        error: None,
    }))
}
```

## 依赖与外部交互

### 内部模块依赖图
```
tui_app_server/src/onboarding/trust_directory.rs
├── codex_core::config::set_project_trust_level
│   └── 写入 ~/.codex/config.toml
├── codex_core::git_info::resolve_root_git_project_for_trust
│   └── 解析 Git 仓库结构
├── codex_protocol::config_types::TrustLevel
│   └── trusted / untrusted 枚举
├── crate::selection_list::selection_option_row
│   └── 选项行渲染辅助
└── crate::onboarding::onboarding_screen
    └── Step 状态机集成
```

### 配置文件格式
信任配置以 TOML 格式存储在用户配置目录：
```toml
# ~/.codex/config.toml
[projects]
[projects."/workspace/project"]
trust_level = "trusted"
```

配置写入使用 `toml_edit` 库确保：
- 保持人类可读的格式（非内联表）
- 保留文件中的注释和其他配置
- 原子性写入（先写临时文件再重命名）

## 风险、边界与改进建议

### 当前风险

1. **双 crate 维护负担**
   - `tui` 和 `tui_app_server` 的代码几乎完全相同
   - 任何变更需要在两个 crate 中同步更新
   - 存在遗漏同步的风险

2. **快照测试重复**
   - 两个 crate 各自维护独立的快照文件
   - 内容相同但文件名不同，增加了维护复杂度

3. **测试基础设施差异**
   - `tui` 版本使用 `VT100Backend` 进行测试
   - `tui_app_server` 版本可能使用不同的测试后端
   - 需要确保两者测试行为一致

### 边界情况

| 场景 | 处理逻辑 |
|------|----------|
| 普通 Git 仓库 | 信任设置应用到仓库根目录 |
| Git worktree | 解析到主仓库目录进行信任设置 |
| 非 Git 目录 | 使用当前工作目录 |
| 配置写入失败 | UI 显示红色错误信息，用户可重试 |
| Windows 平台 | 显示额外的沙箱创建提示 |

### 改进建议

1. **代码共享机制**
   - 考虑将共同的 onboarding 组件提取到共享 crate（如 `codex-tui-common`）
   - 减少代码重复，降低维护成本

2. **统一测试基础设施**
   - 如果两个 crate 的测试逻辑相同，考虑共享测试代码
   - 或者使用宏生成重复的测试代码

3. **快照文件合并**
   - 考虑使用 insta 的 `glob!` 或类似机制减少重复快照文件
   - 或者建立符号链接/复制脚本确保一致性

4. **补充测试覆盖**
   - 添加键盘导航交互测试
   - 添加错误状态渲染测试
   - 添加 Windows 平台特定提示测试

5. **文档同步**
   - 在 `AGENTS.md` 中明确说明两个 crate 的关系
   - 添加变更同步检查清单
