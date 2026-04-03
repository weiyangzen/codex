# CWD Prompt Fork Modal - Technical Research Document

## Snapshot File
`codex_tui_app_server__cwd_prompt__tests__cwd_prompt_fork_modal.snap`

## Snapshot Content
```

Choose working directory to fork this session

  Session = latest cwd recorded in the forked session                           
  Current = your current working directory

› 1. Use session directory (/Users/example/session)                              
  2. Use current directory (/Users/example/current)

  Press enter to continue
```

---

## 1. 场景与职责 (Scenario & Responsibilities)

### 1.1 功能场景
此快照测试验证 **会话派生（Fork）时的工作目录选择提示模态框**。当用户执行 `/fork` 命令派生当前会话时，系统需要确认使用哪个工作目录继续工作。

### 1.2 业务职责
- **派生会话决策**: 允许用户选择继续使用原会话目录或切换到当前目录
- **路径冲突处理**: 解决会话保存路径与当前工作路径不一致的问题
- **用户体验保障**: 通过清晰的 UI 提示避免用户在不正确的目录下操作

### 1.3 与 Resume 的区别
| 场景 | 动作 | 标题 |
|------|------|------|
| Resume | 恢复之前保存的会话 | "Choose working directory to resume this session" |
| Fork | 从当前会话派生新分支 | "Choose working directory to fork this session" |

---

## 2. 功能点目的 (Feature Purpose)

### 2.1 核心功能
1. **工作目录选择界面**: 提供交互式选择界面让用户决定使用哪个工作目录
2. **路径信息展示**: 清晰显示两个候选目录的绝对路径
3. **默认选项预设**: 默认选中 "Session" 目录

### 2.2 UI 元素解析
```
Choose working directory to fork this session

  Session = latest cwd recorded in the forked session                           
  Current = your current working directory

› 1. Use session directory (/Users/example/session)                              
  2. Use current directory (/Users/example/current)

  Press enter to continue
```

| 元素 | 说明 |
|------|------|
| 标题 | "Choose working directory to fork this session"（注意动词是 "fork"）|
| 说明文本 | 解释 Session 和 Current 的含义 |
| 选项 1 | 使用会话目录，带路径显示，默认选中（› 标记）|
| 选项 2 | 使用当前目录，带路径显示 |
| 操作提示 | "Press enter to continue" |

### 2.3 Fork 操作概念
Fork（派生）操作：
- 从当前会话创建一个新的分支会话
- 保留当前会话的历史记录和上下文
- 允许在新分支中独立进行工作
- 常用于尝试不同的解决方案或实验性更改

---

## 3. 具体技术实现 (Technical Implementation)

### 3.1 数据结构
```rust
// cwd_prompt.rs
pub(crate) enum CwdPromptAction {
    Resume,  // 恢复会话
    Fork,    // 派生会话（本测试场景）
}

pub(crate) enum CwdSelection {
    Current,  // 使用当前目录
    Session,  // 使用会话目录
}

pub(crate) enum CwdPromptOutcome {
    Selection(CwdSelection),
    Exit,
}
```

### 3.2 动态标题生成
```rust
// CwdPromptScreen 渲染逻辑
let action_verb = self.action.verb();  // "resume" 或 "fork"
column.push(Line::from(vec![
    "Choose working directory to ".into(),
    action_verb.bold(),
    " this session".into(),
]));
```

### 3.3 测试实现
```rust
// cwd_prompt.rs:259-276
fn new_fork_prompt() -> CwdPromptScreen {
    CwdPromptScreen::new(
        FrameRequester::test_dummy(),
        CwdPromptAction::Fork,  // 关键区别：Fork 动作
        "/Users/example/current".to_string(),
        "/Users/example/session".to_string(),
    )
}

#[test]
fn cwd_prompt_fork_modal_snapshot() {
    let screen = new_fork_prompt();
    let mut terminal = Terminal::new(VT100Backend::new(80, 14)).expect("terminal");
    terminal.draw(|frame| frame.render_widget_ref(&screen, frame.area()))
        .expect("render fork prompt");
    insta::assert_snapshot!("cwd_prompt_fork_modal", terminal.backend());
}
```

---

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 4.1 核心文件
| 文件路径 | 职责 |
|---------|------|
| `tui_app_server/src/cwd_prompt.rs` | CWD 提示模态框完整实现 |
| `tui_app_server/src/selection_list.rs` | `selection_option_row` 辅助函数 |
| `tui_app_server/src/app.rs` | Fork 命令处理 |

### 4.2 调用链
```
用户输入 /fork
  └── App::handle_app_command()
        └── App::fork_session()
              └── run_cwd_selection_prompt(
                      action: CwdPromptAction::Fork,
                      current_cwd,
                      session_cwd,
                  )
                    └── CwdPromptScreen::new()
                          └── render_ref()  // 渲染 UI
```

### 4.3 与 Resume 共享代码
```rust
// cwd_prompt.rs:76-118
pub(crate) async fn run_cwd_selection_prompt(
    tui: &mut Tui,
    action: CwdPromptAction,  // 通过参数区分 Resume/Fork
    current_cwd: &Path,
    session_cwd: &Path,
) -> Result<CwdPromptOutcome> {
    let mut screen = CwdPromptScreen::new(
        FrameRequester::new(),
        action,  // 传入动作类型
        current_cwd.display().to_string(),
        session_cwd.display().to_string(),
    );
    
    // 事件循环...
}
```

---

## 5. 依赖与外部交互 (Dependencies & External Interactions)

### 5.1 外部依赖
| 依赖包 | 用途 |
|--------|------|
| `ratatui` | TUI 渲染框架 |
| `crossterm` | 跨平台终端控制 |

### 5.2 内部模块依赖
```rust
use crate::selection_list::selection_option_row;
use crate::render::renderable::{ColumnRenderable, Renderable};
use crate::tui::{FrameRequester, Tui, TuiEvent};
```

---

## 6. 风险、边界与改进建议 (Risks, Edge Cases & Improvements)

### 6.1 与 Resume 共享的风险
由于 Fork 和 Resume 共享大部分代码，需要注意：
- **标题混淆**: 确保动词正确显示（fork vs resume）
- **行为差异**: Fork 可能需要在派生后执行额外操作
- **状态管理**: Fork 后的会话状态需要正确处理

### 6.2 边界情况
| 场景 | 当前行为 | 评估 |
|------|---------|------|
| 两个目录相同 | 仍显示选择界面 | 可优化：自动跳过选择 |
| 会话目录不存在 | 显示路径但不验证 | 风险：用户可能选择无效目录 |
| 派生操作取消 | 返回 Exit 结果 | 正确：不创建新会话 |

### 6.3 改进建议
1. **Fork 特定选项**
   ```rust
   // 添加 Fork 特有的选项
   enum CwdSelection {
       Current,
       Session,
       NewDirectory,  // Fork 特有：选择新目录
   }
   ```

2. **智能跳过**
   ```rust
   // 当两个目录相同时自动跳过选择
   if current_cwd == session_cwd {
       return Ok(CwdPromptOutcome::Selection(CwdSelection::Session));
   }
   ```

3. **Fork 后操作**
   - 提示用户输入新会话名称
   - 显示 Fork 来源信息
   - 提供 "返回原会话" 选项

### 6.4 相关快照对比
- `cwd_prompt_modal.snap`: Resume 动作变体
- `cwd_prompt_fork_modal.snap`: Fork 动作变体（本测试）
- 两个快照 UI 结构相同，仅标题动词变化

---

## 7. 相关文档链接

- [CWD Prompt Modal](../codex_tui_app_server__cwd_prompt__tests__cwd_prompt_modal.snap_research.md) - Resume 变体文档
