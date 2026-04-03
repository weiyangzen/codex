# CWD Prompt Resume Modal 研究文档

## 场景与职责

该组件负责在用户使用 `/resume` 命令或从会话选择器恢复会话时，提示用户选择工作目录。与 Fork 场景类似，但专门针对恢复（Resume）操作，帮助用户决定是回到原会话的工作环境，还是在当前目录继续工作。

## 功能点目的

CWD 选择提示（Resume 场景）的核心目的：

1. **恢复上下文选择**：允许用户选择恢复完整上下文或仅恢复对话
2. **工作目录决策**：明确区分 "Session"（原会话目录）和 "Current"（当前目录）
3. **项目切换支持**：支持在不同项目目录间恢复会话历史
4. **一致性维护**：确保文件操作命令在预期的目录下执行

## 具体技术实现

### Resume 场景特定实现

```rust
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum CwdPromptAction {
    Resume,  // 恢复会话 - 此场景使用
    Fork,    // 分叉会话
}

impl CwdPromptAction {
    fn verb(self) -> &'static str {
        match self {
            CwdPromptAction::Resume => "resume",  // 动词: resume
            CwdPromptAction::Fork => "fork",
        }
    }

    fn past_participle(self) -> &'static str {
        match self {
            CwdPromptAction::Resume => "resumed",  // 过去分词: resumed
            CwdPromptAction::Fork => "forked",
        }
    }
}
```

### 提示界面结构

```
Choose working directory to resume this session

  Session = latest cwd recorded in the resumed session                           
  Current = your current working directory

› 1. Use session directory (/Users/example/session)                              
  2. Use current directory (/Users/example/current)

  Press enter to continue
```

### 与 Fork 场景的区别

| 特性 | Resume 场景 | Fork 场景 |
|------|------------|----------|
| 标题动词 | "resume" | "fork" |
| 说明文本 | "resumed session" | "forked session" |
| 默认行为 | 恢复原有工作流 | 创建新的分支工作流 |
| 会话状态 | 继续原有会话 | 创建新会话副本 |

### 核心渲染逻辑

```rust
impl WidgetRef for &CwdPromptScreen {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        Clear.render(area, buf);
        let mut column = ColumnRenderable::new();

        let action_verb = self.action.verb();        // "resume"
        let action_past = self.action.past_participle(); // "resumed"
        
        // Resume 场景特定的标题
        column.push(Line::from(vec![
            "Choose working directory to ".into(),
            action_verb.bold(),
            " this session".into(),
        ]));
        column.push("");
        
        // Resume 场景特定的说明
        column.push(
            Line::from(format!(
                "Session = latest cwd recorded in the {action_past} session"
            ))
            .dim()
            .inset(Insets::tlbr(0, 2, 0, 0)),
        );
        // ...
    }
}
```

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `/home/sansha/Github/codex/codex-rs/tui/src/cwd_prompt.rs` | CWD 提示核心实现（第 1-315 行） |
| `/home/sansha/Github/codex/codex-rs/tui/src/cwd_prompt.rs` | `CwdPromptAction::Resume` 定义（第 27-28 行） |
| `/home/sansha/Github/codex/codex-rs/tui/src/cwd_prompt.rs` | `run_cwd_selection_prompt` 函数（第 76-118 行） |
| `/home/sansha/Github/codex/codex-rs/tui/src/app.rs` | Resume 场景调用（第 2463-2472 行） |
| `/home/sansha/Github/codex/codex-rs/tui/src/resume_picker.rs` | 会话选择器 |

### 调用流程
```
用户执行 /resume 或从选择器选择会话
    └── AppEvent::OpenResumePicker
        └── 用户选择目标会话
            └── resolve_cwd_for_resume_or_fork(
                    tui, config, current_cwd,
                    target_session.thread_id,
                    target_session.path,
                    CwdPromptAction::Resume,  // <-- Resume 动作
                    allow_prompt: true
                )
                └── run_cwd_selection_prompt(
                        tui, 
                        CwdPromptAction::Resume,  // 传递 Resume 类型
                        current_cwd, 
                        session_cwd
                    )
                    ├── 渲染 CwdPromptScreen
                    ├── 等待用户选择
                    └── 返回 CwdPromptOutcome
                        ├── Selection(CwdSelection::Session) -> 使用原目录
                        ├── Selection(CwdSelection::Current) -> 使用当前目录
                        └── Exit -> 退出恢复流程
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
| 当前工作目录 | `config.cwd` 或 `std::env::current_dir()` |
| 会话工作目录 | 会话 rollout 文件中的 `session_configured.cwd` |

### 与 App 模块的交互
```rust
// app.rs 中 Resume 场景的调用
SessionSelection::Resume(target_session) => {
    let current_cwd = self.config.cwd.clone();
    let resume_cwd = match crate::resolve_cwd_for_resume_or_fork(
        tui,
        &self.config,
        &current_cwd,
        target_session.thread_id,
        &target_session.path,
        CwdPromptAction::Resume,  // Resume 场景
        /*allow_prompt*/ true,
    ).await?
    {
        crate::ResolveCwdOutcome::Continue(Some(cwd)) => cwd,
        crate::ResolveCwdOutcome::Continue(None) => current_cwd.clone(),
        crate::ResolveCwdOutcome::Exit => {
            return Ok(AppRunControl::Exit(ExitReason::UserRequested));
        }
    };
    // 继续恢复流程...
}
```

## 风险、边界与改进建议

### 边界情况

1. **目录已删除**：原会话目录可能已被删除
2. **Git 仓库变化**：原目录可能已不再是 Git 仓库
3. **环境变量变化**：原目录依赖的环境变量可能已改变
4. **相同目录**：当前目录和会话目录相同

### 潜在风险

1. **上下文丢失**：选择当前目录可能导致某些相对路径引用失效
2. **配置不一致**：不同目录可能有不同的 `.codex/config.toml`
3. **权限变化**：用户可能对原目录失去访问权限

### 改进建议

1. **目录健康检查**：
   ```rust
   // 建议在选择前进行健康检查
   struct DirectoryHealth {
       exists: bool,
       readable: bool,
       writable: bool,
       git_repo: Option<GitRepoStatus>,
       codex_config: Option<CodexConfigStatus>,
   }
   
   fn check_directory_health(path: &Path) -> DirectoryHealth {
       // 检查目录状态...
   }
   ```

2. **配置差异提示**：
   ```rust
   // 建议显示两个目录的配置差异
   struct ConfigDiff {
       session_dir_config: Config,
       current_dir_config: Config,
       differences: Vec<ConfigDifference>,
   }
   ```

3. **智能默认选择**：
   ```rust
   // 建议基于上下文智能选择默认项
   fn suggest_default_selection(
       session_cwd: &Path,
       current_cwd: &Path,
       recent_selections: &[CwdSelection],
   ) -> CwdSelection {
       if session_cwd == current_cwd {
           CwdSelection::Session
       } else if is_subdirectory(current_cwd, session_cwd) {
           CwdSelection::Session
       } else {
           // 基于历史选择模式
           analyze_selection_pattern(recent_selections)
       }
   }
   ```

4. **目录书签**：
   ```rust
   // 建议支持常用目录书签
   struct DirectoryBookmarks {
       bookmarks: Vec<BookmarkedDirectory>,
       quick_select_keys: Vec<char>,
   }
   ```

5. **可视化目录树**：
   ```rust
   // 建议显示目录结构预览
   fn render_directory_tree(path: &Path, depth: usize) -> Vec<Line> {
       // 渲染目录树...
   }
   ```

### 相关测试
- `cwd_prompt_snapshot` - Resume 场景 CWD 提示快照测试
- `cwd_prompt_modal` - Resume 模态框测试
- `cwd_prompt_selects_session_by_default` - 默认选择测试
- `cwd_prompt_can_select_current` - 当前目录选择测试
- `cwd_prompt_ctrl_c_exits_instead_of_selecting` - 退出行为测试
