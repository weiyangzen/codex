# trust_directory.rs 深度研究文档

## 场景与职责

`trust_directory.rs` 实现 Codex TUI 的"目录信任确认"功能，是 onboarding 流程的最后一步。由于 Codex 是一个 AI 编程助手，具有执行代码和访问文件系统的能力，因此在不受信任的目录中运行可能存在安全风险（如 prompt injection 攻击）。该模块通过显式询问用户是否信任当前工作目录，提供了一层安全保护。

## 功能点目的

### 1. 安全确认
- 向用户解释当前工作目录
- 说明在不受信任目录中工作的风险
- 获取用户明确的信任/退出决策

### 2. 信任持久化
- 用户选择"信任"后，将信任级别持久化到配置
- 下次在同一目录启动时跳过此步骤
- 支持 Git 仓库级别的信任（通过 `resolve_root_git_project_for_trust`）

### 3. Windows 沙盒提示
- 在 Windows 平台上，提示用户将创建沙盒环境
- 通过 `show_windows_create_sandbox_hint` 标志控制

## 具体技术实现

### 关键数据结构

```rust
// 目录信任部件
pub(crate) struct TrustDirectoryWidget {
    pub codex_home: PathBuf,           // Codex 配置目录
    pub cwd: PathBuf,                  // 当前工作目录
    pub show_windows_create_sandbox_hint: bool,  // Windows 沙盒提示
    pub should_quit: bool,             // 是否应退出
    pub selection: Option<TrustDirectorySelection>,  // 用户选择
    pub highlighted: TrustDirectorySelection,        // 当前高亮选项
    pub error: Option<String>,         // 错误信息
}

// 信任选择枚举
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TrustDirectorySelection {
    Trust,  // 信任并继续
    Quit,   // 不信任，退出
}
```

### 渲染实现

```rust
impl WidgetRef for &TrustDirectoryWidget {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        let mut column = ColumnRenderable::new();

        // 1. 显示当前目录
        column.push(Line::from(vec![
            "> ".into(),
            "You are in ".bold(),
            self.cwd.to_string_lossy().to_string().into(),
        ]));
        column.push("");

        // 2. 风险提示（带缩进）
        column.push(
            Paragraph::new(
                "Do you trust the contents of this directory? 
                 Working with untrusted contents comes with higher risk of prompt injection."
                    .to_string(),
            )
            .wrap(Wrap { trim: true })
            .inset(Insets::tlbr(0, 2, 0, 0)),  // 左侧缩进 2 字符
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

        // 4. 错误显示
        if let Some(error) = &self.error {
            column.push(
                Paragraph::new(error.to_string())
                    .red()
                    .wrap(Wrap { trim: true })
                    .inset(Insets::tlbr(0, 2, 0, 0)),
            );
            column.push("");
        }

        // 5. 操作提示
        column.push(
            Line::from(vec![
                "Press ".dim(),
                key_hint::plain(KeyCode::Enter).into(),
                if self.show_windows_create_sandbox_hint {
                    " to continue and create a sandbox...".dim()
                } else {
                    " to continue".dim()
                },
            ])
            .inset(Insets::tlbr(0, 2, 0, 0)),
        );

        column.render(area, buf);
    }
}
```

### 键盘事件处理

```rust
impl KeyboardHandler for TrustDirectoryWidget {
    fn handle_key_event(&mut self, key_event: KeyEvent) {
        // 忽略按键释放事件
        if key_event.kind == KeyEventKind::Release {
            return;
        }

        match key_event.code {
            // 方向键导航
            KeyCode::Up | KeyCode::Char('k') => {
                self.highlighted = TrustDirectorySelection::Trust;
            }
            KeyCode::Down | KeyCode::Char('j') => {
                self.highlighted = TrustDirectorySelection::Quit;
            }
            // 快捷键选择
            KeyCode::Char('1') | KeyCode::Char('y') => self.handle_trust(),
            KeyCode::Char('2') | KeyCode::Char('n') => self.handle_quit(),
            // Enter 确认
            KeyCode::Enter => match self.highlighted {
                TrustDirectorySelection::Trust => self.handle_trust(),
                TrustDirectorySelection::Quit => self.handle_quit(),
            },
            _ => {}
        }
    }
}
```

### 信任处理逻辑

```rust
impl TrustDirectoryWidget {
    fn handle_trust(&mut self) {
        // 1. 解析 Git 仓库根目录（如果在 Git 仓库中）
        let target = resolve_root_git_project_for_trust(&self.cwd)
            .unwrap_or_else(|| self.cwd.clone());
        
        // 2. 设置信任级别
        if let Err(e) = set_project_trust_level(
            &self.codex_home, 
            &target, 
            TrustLevel::Trusted
        ) {
            tracing::error!("Failed to set project trusted: {e:?}");
            self.error = Some(format!("Failed to set trust for {}: {e}", target.display()));
        }

        // 3. 标记选择完成
        self.selection = Some(TrustDirectorySelection::Trust);
    }

    fn handle_quit(&mut self) {
        self.highlighted = TrustDirectorySelection::Quit;
        self.should_quit = true;
    }

    pub fn should_quit(&self) -> bool {
        self.should_quit
    }
}
```

### 步骤状态提供

```rust
impl StepStateProvider for TrustDirectoryWidget {
    fn get_step_state(&self) -> StepState {
        if self.selection.is_some() || self.should_quit {
            StepState::Complete  // 已做选择或决定退出 = 完成
        } else {
            StepState::InProgress
        }
    }
}
```

## 关键代码路径与文件引用

### 内部依赖
| 文件 | 用途 |
|------|------|
| `onboarding_screen.rs` | `KeyboardHandler`, `StepStateProvider`, `StepState` |
| `../key_hint.rs` | 键盘提示渲染 |
| `../render/renderable.rs` | `ColumnRenderable`, `Renderable`, `RenderableExt` |
| `../render/renderable.rs` | `Insets` 缩进工具 |
| `../selection_list.rs` | `selection_option_row` 选项行渲染 |

### 外部依赖
| Crate | 模块 | 用途 |
|-------|------|------|
| `codex_core` | `config::set_project_trust_level` | 持久化信任设置 |
| `codex_core` | `git_info::resolve_root_git_project_for_trust` | Git 仓库检测 |
| `codex_protocol` | `config_types::TrustLevel` | 信任级别枚举 |
| `ratatui` | - | UI 渲染 |
| `crossterm` | `event` | 键盘事件 |

### 核心调用链
```
用户选择 Trust
    ↓
handle_trust()
    ↓
resolve_root_git_project_for_trust(&cwd)  // 检测 Git 根目录
    ↓
set_project_trust_level(&codex_home, &target, TrustLevel::Trusted)
    ↓
持久化到配置文件
```

## 依赖与外部交互

### 与 codex_core 的交互

1. **Git 仓库检测**
   ```rust
   use codex_core::git_info::resolve_root_git_project_for_trust;
   
   // 如果在 /workspace/project/src 启动，返回 /workspace/project
   let target = resolve_root_git_project_for_trust(&self.cwd);
   ```

2. **信任级别设置**
   ```rust
   use codex_core::config::set_project_trust_level;
   use codex_protocol::config_types::TrustLevel;
   
   set_project_trust_level(&self.codex_home, &target, TrustLevel::Trusted)?;
   ```

### 与 onboarding_screen 的交互

在 `OnboardingScreen::new` 中创建：
```rust
let show_windows_create_sandbox_hint = if cfg!(target_os = "windows") {
    WindowsSandboxLevel::from_config(&config) == WindowsSandboxLevel::Disabled
} else {
    false
};

if show_trust_screen {
    steps.push(Step::TrustDirectory(TrustDirectoryWidget {
        cwd,
        codex_home,
        show_windows_create_sandbox_hint,
        should_quit: false,
        selection: None,
        highlighted: TrustDirectorySelection::Trust,  // 默认选中"信任"
        error: None,
    }))
}
```

在 `OnboardingScreen::handle_key_event` 中检查退出：
```rust
if self.steps.iter().any(|step| {
    if let Step::TrustDirectory(widget) = step {
        widget.should_quit()
    } else { false }
}) {
    self.should_exit = true;
    self.is_done = true;
}
```

## 风险、边界与改进建议

### 风险点

1. **默认选中"信任"**
   ```rust
   highlighted: TrustDirectorySelection::Trust,  // 默认信任
   ```
   - 用户可能误按 Enter 而未经思考地信任目录
   - 建议改为默认选中"Quit"或没有默认选中

2. **错误处理**
   - 信任设置失败仅显示错误信息，不阻止用户继续
   - 用户可能在信任未持久化的情况下继续

3. **Git 仓库检测依赖**
   - 如果 `resolve_root_git_project_for_trust` 失败，回退到 `cwd`
   - 可能导致子目录被单独信任

### 边界情况

1. **非交互式环境**
   - 在无 TTY 环境中，此步骤会阻塞等待输入
   - 需要 `--yes` 或 `--trust` 等命令行标志绕过

2. **Release 事件处理**
   ```rust
   #[test]
   fn release_event_does_not_change_selection() {
       // 测试确保 Release 事件不会触发选择
       let release = KeyEvent {
           kind: KeyEventKind::Release,
           ..KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE)
       };
       widget.handle_key_event(release);
       assert_eq!(widget.selection, None);
   }
   ```

3. **路径显示**
   - 使用 `to_string_lossy()` 处理非 UTF-8 路径
   - 可能丢失部分路径信息

### 改进建议

1. **安全增强**
   ```rust
   // 建议：添加更明显的风险提示
   column.push(
       Paragraph::new(
           "⚠️  Warning: Codex can execute code and modify files. \
            Only trust directories you fully understand."
       )
       .yellow()
       .wrap(Wrap { trim: true })
   );
   ```

2. **默认行为调整**
   ```rust
   // 建议：默认不选中任何选项，强制用户主动选择
   pub highlighted: Option<TrustDirectorySelection>,  // 改为 Option
   
   // 渲染时检查
   let is_selected = self.highlighted == Some(*selection);
   ```

3. **命令行绕过**
   ```rust
   // 建议：添加 CLI 参数支持
   pub struct Cli {
       #[arg(long)]
       trust_current_dir: bool,  // 自动信任当前目录
       
       #[arg(long)]
       no_trust_prompt: bool,    // 跳过信任提示（默认不信任）
   }
   ```

4. **信任级别细化**
   ```rust
   // 建议：支持更多信任级别
   pub enum TrustLevel {
       Untrusted,      // 不信任
       ReadOnly,       // 只读访问
       AskBeforeWrite, // 写入前询问
       Trusted,        // 完全信任
   }
   ```

5. **测试增强**
   - 当前只有一个 snapshot 测试
   - 建议添加：
     - 信任设置成功/失败的单元测试
     - Git 仓库检测的集成测试
     - 键盘导航的交互测试
