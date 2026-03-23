# cwd_prompt.rs 深度研究文档

## 场景与职责

`cwd_prompt.rs` 是 Codex TUI 的工作目录选择提示模块，负责在恢复（resume）或分支（fork）会话时提示用户选择使用哪个工作目录。当用户恢复或分支一个之前的会话时，系统需要决定是继续使用当前工作目录，还是切换到会话记录的工作目录。

### 核心职责

1. **目录选择 UI**: 提供一个模态对话框让用户选择工作目录
2. **恢复/分支支持**: 支持两种操作模式：Resume 和 Fork
3. **键盘交互**: 处理方向键、数字键、回车键等输入
4. **视觉呈现**: 使用 ratatui 渲染清晰的选项界面

### 使用场景

当用户执行以下操作时触发：
- `codex resume <session_id>` - 恢复之前的会话
- `codex fork <session_id>` - 基于之前会话创建新分支
- `codex resume --picker` 或 `codex fork --picker` - 通过选择器选择会话

系统需要询问用户：
- 使用会话记录的工作目录（Session）
- 使用当前工作目录（Current）

## 功能点目的

### 1. 操作类型定义

```rust
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum CwdPromptAction {
    Resume,
    Fork,
}
```

区分是恢复会话还是创建分支，影响 UI 显示的动词和描述。

### 2. 选择类型定义

```rust
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum CwdSelection {
    Current,
    Session,
}
```

用户的选择：使用当前目录或会话目录。

### 3. 结果类型定义

```rust
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum CwdPromptOutcome {
    Selection(CwdSelection),
    Exit,
}
```

操作结果：用户做出了选择，或选择退出。

### 4. 主入口函数

```rust
pub(crate) async fn run_cwd_selection_prompt(
    tui: &mut Tui,
    action: CwdPromptAction,
    current_cwd: &Path,
    session_cwd: &Path,
) -> Result<CwdPromptOutcome>
```

异步函数，运行完整的目录选择提示流程。

### 5. 键盘导航

支持多种导航方式：
- `↑/k` - 向上选择
- `↓/j` - 向下选择
- `1` - 直接选择 Session
- `2` - 直接选择 Current
- `Enter` - 确认选择
- `Esc` - 默认选择 Session
- `Ctrl+C/D` - 退出

## 具体技术实现

### 状态机设计

```rust
struct CwdPromptScreen {
    request_frame: FrameRequester,  // 帧请求
    action: CwdPromptAction,        // 操作类型
    current_cwd: String,            // 当前目录显示
    session_cwd: String,            // 会话目录显示
    highlighted: CwdSelection,      // 当前高亮选项
    selection: Option<CwdSelection>, // 最终选择
    should_exit: bool,              // 是否退出
}
```

### 主循环实现

```rust
pub(crate) async fn run_cwd_selection_prompt(...) -> Result<CwdPromptOutcome> {
    // 1. 初始化屏幕状态
    let mut screen = CwdPromptScreen::new(...);
    
    // 2. 初始渲染
    tui.draw(u16::MAX, |frame| {
        frame.render_widget_ref(&screen, frame.area());
    })?;
    
    // 3. 事件循环
    let events = tui.event_stream();
    tokio::pin!(events);
    
    while !screen.is_done() {
        if let Some(event) = events.next().await {
            match event {
                TuiEvent::Key(key_event) => screen.handle_key(key_event),
                TuiEvent::Paste(_) => {}  // 忽略粘贴
                TuiEvent::Draw => {        // 重绘请求
                    tui.draw(u16::MAX, |frame| {
                        frame.render_widget_ref(&screen, frame.area());
                    })?;
                }
            }
        } else {
            break;  // 事件流结束
        }
    }
    
    // 4. 返回结果
    if screen.should_exit {
        Ok(CwdPromptOutcome::Exit)
    } else {
        Ok(CwdPromptOutcome::Selection(
            screen.selection().unwrap_or(CwdSelection::Session)
        ))
    }
}
```

### 键盘处理

```rust
fn handle_key(&mut self, key_event: KeyEvent) {
    // 忽略按键释放事件
    if key_event.kind == KeyEventKind::Release {
        return;
    }
    
    // Ctrl+C/D 退出
    if key_event.modifiers.contains(KeyModifiers::CONTROL)
        && matches!(key_event.code, KeyCode::Char('c') | KeyCode::Char('d'))
    {
        self.selection = None;
        self.should_exit = true;
        self.request_frame.schedule_frame();
        return;
    }
    
    match key_event.code {
        KeyCode::Up | KeyCode::Char('k') => self.set_highlight(self.highlighted.prev()),
        KeyCode::Down | KeyCode::Char('j') => self.set_highlight(self.highlighted.next()),
        KeyCode::Char('1') => self.select(CwdSelection::Session),
        KeyCode::Char('2') => self.select(CwdSelection::Current),
        KeyCode::Enter => self.select(self.highlighted),
        KeyCode::Esc => self.select(CwdSelection::Session),  // 默认选择
        _ => {}
    }
}
```

### 渲染实现

```rust
impl WidgetRef for &CwdPromptScreen {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        Clear.render(area, buf);  // 清除背景
        let mut column = ColumnRenderable::new();
        
        // 标题
        column.push(Line::from(vec![
            "Choose working directory to ".into(),
            self.action.verb().bold(),
            " this session".into(),
        ]));
        
        // 说明文字
        column.push(format!("Session = latest cwd recorded in the {}", 
            self.action.past_participle()).dim());
        column.push("Current = your current working directory".dim());
        
        // 选项
        column.push(selection_option_row(0, 
            format!("Use session directory ({})", self.session_cwd),
            self.highlighted == CwdSelection::Session));
        column.push(selection_option_row(1, 
            format!("Use current directory ({})", self.current_cwd),
            self.highlighted == CwdSelection::Current));
        
        // 提示
        column.push(Line::from(vec![
            "Press ".dim(),
            key_hint::plain(KeyCode::Enter).into(),
            " to continue".dim(),
        ]));
        
        column.render(area, buf);
    }
}
```

### 选择切换逻辑

```rust
impl CwdSelection {
    fn next(self) -> Self {
        match self {
            CwdSelection::Current => CwdSelection::Session,
            CwdSelection::Session => CwdSelection::Current,
        }
    }
    
    fn prev(self) -> Self {
        // 只有两个选项，next 和 prev 相同
        self.next()
    }
}
```

## 关键代码路径与文件引用

### 定义位置
- **文件**: `codex-rs/tui/src/cwd_prompt.rs`
- **行数**: 315 行
- **测试**: 65 行测试代码

### 调用方

| 文件 | 用途 |
|------|------|
| `lib.rs` | 模块声明，导入类型 |
| `app.rs` | 在恢复/分支流程中调用 |

### 使用示例（来自 lib.rs）

```rust
use cwd_prompt::CwdPromptAction;
use cwd_prompt::CwdPromptOutcome;
use cwd_prompt::CwdSelection;

// 在恢复/分支流程中
let action_and_target_session_if_resume_or_fork = match &session_selection {
    resume_picker::SessionSelection::Resume(target_session) => {
        Some((CwdPromptAction::Resume, target_session))
    }
    resume_picker::SessionSelection::Fork(target_session) => {
        Some((CwdPromptAction::Fork, target_session))
    }
    _ => None,
};

let fallback_cwd = match action_and_target_session_if_resume_or_fork {
    Some((action, target_session)) => {
        match resolve_cwd_for_resume_or_fork(
            &mut tui,
            &config,
            &current_cwd,
            target_session.thread_id,
            &target_session.path,
            action,
            allow_prompt,
        ).await?
        {
            ResolveCwdOutcome::Continue(cwd) => cwd,
            ResolveCwdOutcome::Exit => { /* 处理退出 */ }
        }
    }
    None => None,
};
```

### 依赖模块

```rust
use crate::key_hint;
use crate::render::Insets;
use crate::render::renderable::ColumnRenderable;
use crate::render::renderable::Renderable;
use crate::render::renderable::RenderableExt as _;
use crate::selection_list::selection_option_row;
use crate::tui::FrameRequester;
use crate::tui::Tui;
use crate::tui::TuiEvent;
use crossterm::event::KeyCode;
use crossterm::event::KeyEvent;
use crossterm::event::KeyEventKind;
use crossterm::event::KeyModifiers;
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::prelude::Widget;
use ratatui::style::Stylize as _;
use ratatui::text::Line;
use ratatui::widgets::Clear;
use ratatui::widgets::WidgetRef;
use tokio_stream::StreamExt;
```

## 依赖与外部交互

### 外部依赖

| Crate | 用途 |
|-------|------|
| `ratatui` | UI 渲染 |
| `crossterm` | 键盘事件处理 |
| `tokio-stream` | 异步事件流 |
| `color-eyre` | 错误处理 |

### 内部依赖

| 模块 | 用途 |
|------|------|
| `key_hint` | 键盘提示显示 |
| `render` | 渲染辅助工具 |
| `selection_list` | 选项行渲染 |
| `tui` | TUI 框架 |

### 与 TUI 的集成

```
用户执行 resume/fork 命令
    |
    v
lib.rs 解析命令行参数
    |
    v
确定需要目录选择
    |
    v
call run_cwd_selection_prompt()
    |
    v
显示模态对话框
    |
    v
用户选择 -> 返回 CwdPromptOutcome
    |
    v
根据选择继续恢复/分支流程
```

## 风险、边界与改进建议

### 潜在风险

1. **路径显示过长**: 工作目录路径可能很长，超出屏幕宽度
   - 缓解: 使用 `selection_option_row` 处理截断
   - 建议: 考虑添加路径缩写功能

2. **相同目录**: 当前目录和会话目录可能相同
   - 风险: 用户困惑，选择无意义
   - 建议: 检测相同情况，跳过提示

3. **目录不存在**: 会话记录的工作目录可能已被删除
   - 风险: 选择后操作失败
   - 建议: 预检查目录存在性，标记无效选项

4. **并发问题**: 异步事件处理可能有竞态条件
   - 缓解: 使用 `tokio::pin!` 固定事件流

### 边界情况

1. **空目录路径**: 理论上不应发生，但代码未显式检查
2. **特殊字符路径**: 路径包含控制字符可能影响显示
3. **快速按键**: 用户快速按键可能导致帧率问题
4. **终端大小变化**: 未处理终端大小变化事件

### 改进建议

1. **目录验证**: 预检查目录存在性和可访问性

```rust
fn validate_cwd(path: &Path) -> Result<(), CwdValidationError> {
    if !path.exists() {
        return Err(CwdValidationError::NotExists);
    }
    if !path.is_dir() {
        return Err(CwdValidationError::NotDirectory);
    }
    // 检查读写权限...
}
```

2. **智能跳过**: 当两个目录相同时自动跳过提示

```rust
if current_cwd == session_cwd {
    return Ok(CwdPromptOutcome::Selection(CwdSelection::Current));
}
```

3. **路径缩写**: 显示缩写路径，如 `~/projects/foo` 而非完整路径

4. **记住选择**: 添加"记住此选择"选项，避免重复提示

5. **更多快捷键**: 添加 `y/n` 快捷键作为 `Enter/Esc` 的替代

6. **帮助文本**: 添加更详细的帮助说明差异

### 测试覆盖

当前测试包括：
- 快照测试（UI 渲染）
- 默认选择测试
- 键盘导航测试
- 退出测试

建议添加：
- 长路径处理测试
- 特殊字符路径测试
- 并发事件测试

### 代码质量建议

1. **常量提取**: 提取 UI 文本常量

```rust
const TITLE_PREFIX: &str = "Choose working directory to ";
const SESSION_DESCRIPTION: &str = "Session = latest cwd recorded in the ";
const CURRENT_DESCRIPTION: &str = "Current = your current working directory";
```

2. **日志记录**: 添加 `tracing` 日志

```rust
tracing::info!("cwd_prompt: user selected {:?}", selection);
```

3. **文档完善**: 添加更多使用示例和截图
