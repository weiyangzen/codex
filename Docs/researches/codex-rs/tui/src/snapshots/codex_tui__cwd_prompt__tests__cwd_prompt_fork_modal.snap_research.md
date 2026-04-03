# CWD Prompt Fork Modal 研究文档

## 场景与职责

该组件负责在用户使用 `/fork` 命令分叉（fork）会话时，提示用户选择工作目录。当用户分叉一个已有会话时，系统需要确认是使用原会话记录的工作目录，还是使用当前 shell 的工作目录，以确保文件操作在正确的上下文中执行。

## 功能点目的

CWD 选择提示（Fork 场景）的核心目的：

1. **工作目录确认**：明确告知用户两种目录选项的含义
2. **会话连续性**：支持使用原会话目录保持上下文连续性
3. **灵活性**：允许切换到当前目录以适应新的工作场景
4. **防止误操作**：避免在错误的目录下执行文件操作

## 具体技术实现

### 枚举定义

```rust
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum CwdPromptAction {
    Resume,  // 恢复会话
    Fork,    // 分叉会话
}

impl CwdPromptAction {
    fn verb(self) -> &'static str {
        match self {
            CwdPromptAction::Resume => "resume",
            CwdPromptAction::Fork => "fork",
        }
    }

    fn past_participle(self) -> &'static str {
        match self {
            CwdPromptAction::Resume => "resumed",
            CwdPromptAction::Fork => "forked",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum CwdSelection {
    Current,  // 使用当前工作目录
    Session,  // 使用会话记录的工作目录
}
```

### 提示界面结构

```
Choose working directory to fork this session

  Session = latest cwd recorded in the forked session                           
  Current = your current working directory

› 1. Use session directory (/Users/example/session)                              
  2. Use current directory (/Users/example/current)

  Press enter to continue
```

### 核心渲染逻辑

```rust
impl WidgetRef for &CwdPromptScreen {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        Clear.render(area, buf);
        let mut column = ColumnRenderable::new();

        let action_verb = self.action.verb();        // "fork"
        let action_past = self.action.past_participle(); // "forked"
        let current_cwd = self.current_cwd.as_str();
        let session_cwd = self.session_cwd.as_str();

        column.push("");
        column.push(Line::from(vec![
            "Choose working directory to ".into(),
            action_verb.bold(),
            " this session".into(),
        ]));
        column.push("");
        column.push(
            Line::from(format!(
                "Session = latest cwd recorded in the {action_past} session"
            ))
            .dim()
            .inset(Insets::tlbr(0, 2, 0, 0)),
        );
        column.push(
            Line::from("Current = your current working directory".dim())
                .inset(Insets::tlbr(0, 2, 0, 0)),
        );
        column.push("");
        column.push(selection_option_row(
            0,
            format!("Use session directory ({session_cwd})"),
            self.highlighted == CwdSelection::Session,
        ));
        column.push(selection_option_row(
            1,
            format!("Use current directory ({current_cwd})"),
            self.highlighted == CwdSelection::Current,
        ));
        // ... 继续渲染
    }
}
```

### 键盘交互

```rust
fn handle_key(&mut self, key_event: KeyEvent) {
    if key_event.kind == KeyEventKind::Release {
        return;
    }
    // Ctrl+C / Ctrl+D 退出
    if key_event.modifiers.contains(KeyModifiers::CONTROL)
        && matches!(key_event.code, KeyCode::Char('c') | KeyCode::Char('d'))
    {
        self.selection = None;
        self.should_exit = true;
        return;
    }
    match key_event.code {
        KeyCode::Up | KeyCode::Char('k') => self.set_highlight(self.highlighted.prev()),
        KeyCode::Down | KeyCode::Char('j') => self.set_highlight(self.highlighted.next()),
        KeyCode::Char('1') => self.select(CwdSelection::Session),
        KeyCode::Char('2') => self.select(CwdSelection::Current),
        KeyCode::Enter => self.select(self.highlighted),
        KeyCode::Esc => self.select(CwdSelection::Session),
        _ => {}
    }
}
```

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `/home/sansha/Github/codex/codex-rs/tui/src/cwd_prompt.rs` | CWD 提示核心实现（第 1-315 行） |
| `/home/sansha/Github/codex/codex-rs/tui/src/cwd_prompt.rs` | `CwdPromptAction` 枚举（第 26-46 行） |
| `/home/sansha/Github/codex/codex-rs/tui/src/cwd_prompt.rs` | `CwdPromptScreen` 结构体（第 120-191 行） |
| `/home/sansha/Github/codex/codex-rs/tui/src/cwd_prompt.rs` | `run_cwd_selection_prompt` 函数（第 76-118 行） |
| `/home/sansha/Github/codex/codex-rs/tui/src/app.rs` | `resolve_cwd_for_resume_or_fork` 调用（第 2463-2472 行） |

### 调用流程
```
用户执行 /fork
    └── AppEvent::ForkCurrentSession
        └── 如果 rollout_path 存在:
            └── resolve_cwd_for_resume_or_fork(
                    tui, config, current_cwd, 
                    target_session.thread_id, 
                    target_session.path,
                    CwdPromptAction::Fork,  // <-- Fork 动作
                    allow_prompt: true
                )
                └── run_cwd_selection_prompt(tui, CwdPromptAction::Fork, current_cwd, session_cwd)
                    ├── 渲染 CwdPromptScreen
                    ├── 等待用户选择
                    └── 返回 CwdPromptOutcome
```

## 依赖与外部交互

### 依赖模块
- `crate::selection_list::selection_option_row` - 选择列表项渲染
- `crate::render::Insets` - 渲染内边距
- `crate::key_hint` - 键盘提示
- `tokio_stream::StreamExt` - 异步事件流

### 目录信息来源
| 信息项 | 来源 |
|-------|------|
| 当前工作目录 | `std::env::current_dir()` 或传入参数 |
| 会话工作目录 | 会话配置文件中的 `cwd` 字段 |

### 与 App 模块的交互
```rust
// app.rs 中的调用
match crate::resolve_cwd_for_resume_or_fork(
    tui,
    &config,
    &current_cwd,
    target_session.thread_id,
    &target_session.path,
    CwdPromptAction::Fork,  // Fork 场景
    /*allow_prompt*/ true,
).await?
{
    crate::ResolveCwdOutcome::Continue(Some(cwd)) => cwd,
    crate::ResolveCwdOutcome::Continue(None) => current_cwd.clone(),
    crate::ResolveCwdOutcome::Exit => {
        return Ok(AppRunControl::Exit(ExitReason::UserRequested));
    }
}
```

## 风险、边界与改进建议

### 边界情况

1. **目录不存在**：会话记录的目录可能已被删除或移动
2. **权限问题**：用户可能无权访问会话目录
3. **相同目录**：当前目录和会话目录相同时的优化
4. **长路径显示**：超长路径可能导致界面换行

### 潜在风险

1. **路径混淆**：用户可能误解 "Session" 和 "Current" 的含义
2. **默认选择**：默认选择 Session 目录可能不符合用户预期
3. **取消操作**：Ctrl+C 退出后用户可能不清楚会话状态

### 改进建议

1. **目录存在性检查**：
   ```rust
   // 建议在选择前验证目录存在性
   fn validate_directory(path: &Path) -> DirectoryStatus {
       if !path.exists() {
           DirectoryStatus::NotFound
       } else if !path.is_dir() {
           DirectoryStatus::NotADirectory
       } else if std::fs::read_dir(path).is_err() {
           DirectoryStatus::NoPermission
       } else {
           DirectoryStatus::Valid
       }
   }
   ```

2. **路径截断显示**：
   ```rust
   // 建议对长路径进行智能截断
   fn format_path_for_display(path: &str, max_len: usize) -> String {
       if path.len() <= max_len {
           path.to_string()
       } else {
           format!("...{}", &path[path.len() - max_len + 3..])
       }
   }
   ```

3. **最近使用目录记录**：
   ```rust
   // 建议记录用户的选择偏好
   struct CwdSelectionHistory {
       last_selection: CwdSelection,
       session_dir_frequency: f64,
       current_dir_frequency: f64,
   }
   ```

4. **目录预览**：
   ```rust
   // 建议显示目录内容预览
   struct DirectoryPreview {
       path: PathBuf,
       file_count: usize,
       git_repo: bool,
       recent_files: Vec<String>,
   }
   ```

5. **快捷操作**：
   - 添加 "记住我的选择" 选项
   - 支持直接输入自定义路径
   - 提供目录浏览器（如果终端支持）

### 相关测试
- `cwd_prompt_fork_snapshot` - Fork 场景 CWD 提示快照测试
- `cwd_prompt_fork_modal` - Fork 模态框测试
- `cwd_prompt_selects_session_by_default` - 默认选择测试
- `cwd_prompt_can_select_current` - 当前目录选择测试
- `cwd_prompt_ctrl_c_exits_instead_of_selecting` - 退出行为测试
