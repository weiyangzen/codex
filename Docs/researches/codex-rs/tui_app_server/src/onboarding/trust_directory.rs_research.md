# trust_directory.rs 研究文档

## 场景与职责

`trust_directory.rs` 是 Codex TUI onboarding 流程中的**目录信任决策模块**，负责在用户首次于特定目录运行 Codex 时，询问用户是否信任该目录的内容。这是 Codex 安全模型的关键组成部分，旨在防止 prompt injection 攻击。

### 核心职责

1. **信任决策 UI**：提供交互界面让用户选择是否信任当前目录
2. **安全配置持久化**：将用户决策保存到配置中，影响后续会话的默认行为
3. **Git 项目识别**：自动识别 Git 仓库根目录，在正确的粒度上设置信任级别

### 使用场景

- 用户首次在特定目录运行 Codex 时
- 项目信任级别未配置时（`trust_level: None`）
- 非远程模式下（远程模式跳过此步骤）

## 功能点目的

### 1. 目录信任提示

向用户展示：
- 当前工作目录路径
- 安全风险说明（prompt injection 风险）
- 两个选项："Yes, continue" 或 "No, quit"

### 2. Git 仓库感知

```rust
let target = resolve_root_git_project_for_trust(&self.cwd)
    .unwrap_or_else(|| self.cwd.clone());
```

- 如果当前目录在 Git 仓库中，信任决策应用于仓库根目录
- 确保同一仓库的所有子目录共享相同的信任设置

### 3. 信任级别持久化

```rust
set_project_trust_level(&self.codex_home, &target, TrustLevel::Trusted)
```

- 将决策保存到 `config.toml` 的 `[projects."path"]` 部分
- 影响后续会话的权限策略（如 `AskForApproval` 默认值）

### 4. Windows 沙盒提示

```rust
if self.show_windows_create_sandbox_hint {
    " to continue and create a sandbox..."
}
```

- 在 Windows 平台上提示用户将创建沙盒环境
- 提供额外的安全保证信息

## 具体技术实现

### 关键数据结构

```rust
/// 信任目录选择 Widget
pub(crate) struct TrustDirectoryWidget {
    pub codex_home: PathBuf,                    // Codex 主目录（配置存储位置）
    pub cwd: PathBuf,                           // 当前工作目录
    pub show_windows_create_sandbox_hint: bool, // 是否显示 Windows 沙盒提示
    pub should_quit: bool,                      // 用户是否选择退出
    pub selection: Option<TrustDirectorySelection>, // 用户选择（None = 未选择）
    pub highlighted: TrustDirectorySelection,   // 当前高亮的选项
    pub error: Option<String>,                  // 错误信息
}

/// 信任决策选项
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TrustDirectorySelection {
    Trust,  // 信任该目录
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
        
        // 2. 安全风险说明
        column.push(
            Paragraph::new(
                "Do you trust the contents of this directory? \
                 Working with untrusted contents comes with higher risk of prompt injection."
            )
            .wrap(Wrap { trim: true })
            .inset(Insets::tlbr(0, 2, 0, 0))
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
        
        // 4. 错误信息（如果有）
        if let Some(error) = &self.error {
            column.push(
                Paragraph::new(error.to_string())
                    .red()
                    .wrap(Wrap { trim: true })
                    .inset(Insets::tlbr(0, 2, 0, 0))
            );
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
            .inset(Insets::tlbr(0, 2, 0, 0))
        );
        
        column.render(area, buf);
    }
}
```

### 键盘事件处理

```rust
impl KeyboardHandler for TrustDirectoryWidget {
    fn handle_key_event(&mut self, key_event: KeyEvent) {
        // 忽略释放事件（只处理按下）
        if key_event.kind == KeyEventKind::Release {
            return;
        }
        
        match key_event.code {
            // 方向键切换选项
            KeyCode::Up | KeyCode::Char('k') => {
                self.highlighted = TrustDirectorySelection::Trust;
            }
            KeyCode::Down | KeyCode::Char('j') => {
                self.highlighted = TrustDirectorySelection::Quit;
            }
            // 快捷键直接选择
            KeyCode::Char('1') | KeyCode::Char('y') => self.handle_trust(),
            KeyCode::Char('2') | KeyCode::Char('n') => self.handle_quit(),
            // Enter 确认当前高亮选项
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
        // 1. 识别 Git 仓库根目录（或直接使用当前目录）
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
            StepState::Complete
        } else {
            StepState::InProgress
        }
    }
}
```

- 用户做出选择或选择退出时，步骤标记为 `Complete`
- onboarding 流程可以继续到下一步或退出

## 关键代码路径与文件引用

### 内部依赖

| 文件 | 用途 |
|------|------|
| `onboarding_screen.rs` | 定义 `KeyboardHandler` 和 `StepStateProvider` trait，集成 `TrustDirectoryWidget` |
| `../render/` | `ColumnRenderable`, `Insets`, `Renderable` 等渲染基础设施 |
| `../selection_list.rs` | `selection_option_row()` 用于渲染选项行 |
| `../key_hint.rs` | `key_hint::plain()` 用于渲染按键提示 |

### 外部依赖

| Crate/Module | 用途 |
|--------------|------|
| `codex_core::config::set_project_trust_level` | 持久化信任级别到配置 |
| `codex_core::git_info::resolve_root_git_project_for_trust` | 识别 Git 仓库根目录 |
| `codex_protocol::config_types::TrustLevel` | 信任级别枚举定义 |
| `ratatui` | TUI 渲染框架 |
| `crossterm` | 键盘事件处理 |

### 核心函数调用链

```
TrustDirectoryWidget::handle_trust()
    ↓
resolve_root_git_project_for_trust(&self.cwd)  [codex_core::git_info]
    ↓
set_project_trust_level(&self.codex_home, &target, TrustLevel::Trusted)  [codex_core::config]
    ↓
写入 config.toml [projects."path"].trust_level = "trusted"
```

## 依赖与外部交互

### 与 onboarding_screen.rs 的交互

```rust
// onboarding_screen.rs 中的集成
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

// 检查用户是否选择退出
if self.steps.iter().any(|step| {
    if let Step::TrustDirectory(widget) = step {
        widget.should_quit()
    } else {
        false
    }
}) {
    self.should_exit = true;
    self.is_done = true;
}
```

### 与 lib.rs 的交互

```rust
// lib.rs 中的使用
let should_show_trust_screen_flag = !remote_mode && should_show_trust_screen(&initial_config);

fn should_show_trust_screen(config: &Config) -> bool {
    config.active_project.trust_level.is_none()
}

// 处理结果
let onboarding_result = run_onboarding_app(...).await?;
trust_decision_was_made = onboarding_result.directory_trust_decision.is_some();

// 如果用户做了信任决策，重新加载配置
if trust_decision_was_made {
    load_config_or_exit(...).await
}
```

### 配置影响

信任决策影响以下配置项：

```toml
[projects."/path/to/project"]
trust_level = "trusted"  # 或 "untrusted"
```

这会影响：
- `permissions.approval_policy` 默认值
- `permissions.sandbox_policy` 默认值

## 风险、边界与改进建议

### 风险分析

1. **配置写入失败**（已处理）
   - 问题：`set_project_trust_level` 可能失败（磁盘满、权限不足等）
   - 缓解：错误被捕获并显示在 UI 中，用户可以看到失败原因
   - 代码：
     ```rust
     if let Err(e) = set_project_trust_level(...) {
         self.error = Some(format!("Failed to set trust for {}: {e}", target.display()));
     }
     ```

2. **Git 仓库识别错误**（中等风险）
   - 问题：`resolve_root_git_project_for_trust` 可能识别错误的根目录
   - 影响：信任设置应用到错误的目录范围
   - 缓解：如果识别失败，回退到当前目录（`unwrap_or_else`）

3. **用户困惑**（UX 风险）
   - 问题："prompt injection" 对普通用户可能过于技术化
   - 建议：提供更通俗的解释或链接到文档

### 边界情况

1. **Release 事件处理**
   ```rust
   // 测试用例验证
   #[test]
   fn release_event_does_not_change_selection() {
       let release = KeyEvent {
           kind: KeyEventKind::Release,
           ..KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE)
       };
       widget.handle_key_event(release);
       assert_eq!(widget.selection, None);  // 确认未改变
   }
   ```

2. **非 Git 目录**
   - 直接使用 `self.cwd` 作为目标
   - 信任设置仅应用于当前目录

3. **远程模式**
   - `show_trust_screen` 为 false，跳过此步骤
   - 信任决策在远程服务器端处理

4. **重复运行**
   - 一旦 `trust_level` 被设置，`should_show_trust_screen()` 返回 false
   - 用户不会重复看到此提示

### 改进建议

1. **UI/UX 改进**
   - 添加 "了解更多" 链接，解释 prompt injection 风险
   - 提供 "仅本次" 选项（不持久化到配置）
   - 显示当前目录的 Git 状态（如果是 Git 仓库）

2. **安全增强**
   ```rust
   // 当前：默认选中 "Trust"
   highlighted: TrustDirectorySelection::Trust,
   
   // 建议：默认选中 "Quit"，强制用户主动选择信任
   highlighted: TrustDirectorySelection::Quit,
   ```
   - 理由：安全默认值应该是"不信任"，用户必须主动选择信任

3. **错误恢复**
   ```rust
   // 当前：错误显示后用户需要重新选择
   // 建议：添加重试机制
   fn handle_trust(&mut self) {
       let target = /* ... */;
       match set_project_trust_level(...) {
           Ok(()) => self.selection = Some(TrustDirectorySelection::Trust),
           Err(e) => {
               self.error = Some(format!("..."));
               // 建议：添加重试按钮或自动重试逻辑
           }
       }
   }
   ```

4. **测试覆盖**
   - 当前测试：
     - `release_event_does_not_change_selection` - 键盘事件处理
     - `renders_snapshot_for_git_repo` - 渲染快照
   - 建议添加：
     - `handle_trust_sets_project_trusted` - 信任设置持久化
     - `handle_quit_sets_should_quit` - 退出逻辑
     - `git_repo_uses_root_directory` - Git 根目录识别

5. **可访问性**
   - 添加屏幕阅读器提示（ANSI 转义序列）
   - 为色盲用户提供非颜色指示器（图标或文字）

### 已知限制

1. **二进制选择**：当前只有 "Trust" 或 "Quit" 两个选项，没有 "Trust with restrictions" 的中间选项。

2. **全局信任**：一旦信任，该项目的所有操作都使用相同的权限策略，不支持细粒度控制（如只读信任）。

3. **Windows 提示位置**：`show_windows_create_sandbox_hint` 显示在按键提示中，可能不够醒目。

### 代码质量

- 文件长度 224 行，结构清晰
- 职责单一：只处理信任决策 UI 和持久化
- 与 `onboarding_screen.rs` 的接口简洁明了
- 测试覆盖基本场景，可进一步增强
