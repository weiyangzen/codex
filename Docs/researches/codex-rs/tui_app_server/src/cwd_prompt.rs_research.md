# cwd_prompt.rs 研究文档

## 场景与职责

`cwd_prompt.rs` 是 Codex TUI 应用服务器的工作目录选择提示模块，负责在恢复（resume）或分叉（fork）会话时，提示用户选择使用哪个工作目录。该模块提供了一个模态对话框界面，让用户在"会话目录"和"当前目录"之间做出选择。

该模块处理以下场景：
- **恢复会话**：用户执行 `codex resume` 时，选择使用原会话的工作目录还是当前工作目录
- **分叉会话**：用户执行 `codex fork` 时，同样面临工作目录选择
- **键盘交互**：支持多种导航和选择方式（方向键、数字键、回车、ESC）

## 功能点目的

### 1. 动作类型定义 `CwdPromptAction`
- `Resume`：恢复会话操作
- `Fork`：分叉会话操作
- 提供 `verb()` 和 `past_participle()` 方法，用于 UI 文本生成

### 2. 选择类型定义 `CwdSelection`
- `Current`：使用当前工作目录
- `Session`：使用会话记录的工作目录
- 提供 `next()` 和 `prev()` 方法，支持循环导航

### 3. 结果类型定义 `CwdPromptOutcome`
- `Selection(CwdSelection)`：用户做出了选择
- `Exit`：用户选择退出（取消操作）

### 4. 主入口函数 `run_cwd_selection_prompt`
- 异步函数，运行目录选择提示界面
- 接收 TUI 实例、动作类型、当前目录和会话目录
- 返回用户的选择结果

### 5. 屏幕状态管理 `CwdPromptScreen`
- 管理提示界面的状态（高亮项、选择结果、退出标志）
- 处理键盘事件
- 实现 `WidgetRef` trait 用于渲染

## 具体技术实现

### 枚举定义

```rust
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum CwdPromptAction {
    Resume,
    Fork,
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
```

```rust
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum CwdSelection {
    Current,
    Session,
}

impl CwdSelection {
    fn next(self) -> Self {
        match self {
            CwdSelection::Current => CwdSelection::Session,
            CwdSelection::Session => CwdSelection::Current,
        }
    }

    fn prev(self) -> Self {
        // 与 next 相同，因为只有两个选项
        self.next()
    }
}
```

### 主入口函数

```rust
pub(crate) async fn run_cwd_selection_prompt(
    tui: &mut Tui,
    action: CwdPromptAction,
    current_cwd: &Path,
    session_cwd: &Path,
) -> Result<CwdPromptOutcome> {
    let mut screen = CwdPromptScreen::new(
        tui.frame_requester(),
        action,
        current_cwd.display().to_string(),
        session_cwd.display().to_string(),
    );
    
    // 初始渲染
    tui.draw(u16::MAX, |frame| {
        frame.render_widget_ref(&screen, frame.area());
    })?;

    // 事件循环
    let events = tui.event_stream();
    tokio::pin!(events);

    while !screen.is_done() {
        if let Some(event) = events.next().await {
            match event {
                TuiEvent::Key(key_event) => screen.handle_key(key_event),
                TuiEvent::Paste(_) => {}  // 忽略粘贴事件
                TuiEvent::Draw => {
                    tui.draw(u16::MAX, |frame| {
                        frame.render_widget_ref(&screen, frame.area());
                    })?;
                }
            }
        } else {
            break;
        }
    }

    // 返回结果
    if screen.should_exit {
        Ok(CwdPromptOutcome::Exit)
    } else {
        Ok(CwdPromptOutcome::Selection(
            screen.selection().unwrap_or(CwdSelection::Session),
        ))
    }
}
```

### 键盘事件处理

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
        self.request_frame.schedule_frame();
        return;
    }
    
    match key_event.code {
        KeyCode::Up | KeyCode::Char('k') => self.set_highlight(self.highlighted.prev()),
        KeyCode::Down | KeyCode::Char('j') => self.set_highlight(self.highlighted.next()),
        KeyCode::Char('1') => self.select(CwdSelection::Session),  // 数字快捷方式
        KeyCode::Char('2') => self.select(CwdSelection::Current),
        KeyCode::Enter => self.select(self.highlighted),  // 确认选择
        KeyCode::Esc => self.select(CwdSelection::Session),  // ESC 默认选择 Session
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

        // 标题和说明
        column.push("");
        column.push(Line::from(vec![
            "Choose working directory to ".into(),
            action_verb.bold(),
            " this session".into(),
        ]));
        column.push("");
        column.push(
            Line::from(format!("Session = latest cwd recorded in the {action_past} session"))
                .dim()
                .inset(Insets::tlbr(0, 2, 0, 0)),
        );
        // ... 更多行

        // 选项行
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
        
        // 提示信息
        column.push("");
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

## 关键代码路径与文件引用

### 定义位置
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/cwd_prompt.rs`

### 调用方
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/app.rs`：
  - 在恢复或分叉会话时调用 `run_cwd_selection_prompt`
  - 根据结果决定使用哪个工作目录

### 模块声明
- 在 `lib.rs` 中声明为 `mod cwd_prompt;`

### 导出类型
- `CwdPromptAction`、`CwdPromptOutcome`、`CwdSelection` 在 `lib.rs` 中重新导出

### 快照测试
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/snapshots/codex_tui__cwd_prompt__tests__cwd_prompt_modal.snap`
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/snapshots/codex_tui__cwd_prompt__tests__cwd_prompt_fork_modal.snap`
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/snapshots/codex_tui_app_server__cwd_prompt__tests__cwd_prompt_modal.snap`
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/snapshots/codex_tui_app_server__cwd_prompt__tests__cwd_prompt_fork_modal.snap`

## 依赖与外部交互

### 外部依赖
- `color_eyre::Result`：错误处理
- `crossterm::event`：键盘事件处理
- `ratatui`：UI 渲染组件
- `tokio_stream::StreamExt`：异步事件流处理

### 内部模块交互
- `key_hint`：键盘快捷键提示渲染
- `render::Insets` / `render::renderable`：渲染辅助工具
- `selection_list::selection_option_row`：选项行渲染
- `tui::Tui` / `tui::TuiEvent` / `tui::FrameRequester`：TUI 框架集成

## 风险、边界与改进建议

### 风险点

1. **默认选择行为**
   - ESC 键默认选择 `Session` 目录，这可能不符合所有用户的预期
   - **建议**：考虑添加配置选项或更明确的提示

2. **路径显示长度**
   - 长路径可能在窄终端中被截断
   - **当前状态**：使用 `selection_option_row` 处理，可能已做截断

3. **异步事件处理**
   - 使用 `tokio::pin!` 固定事件流
   - 如果 TUI 事件流异常关闭，可能导致提前退出

### 边界情况

1. **相同目录**
   - 如果 `current_cwd` 和 `session_cwd` 相同，提示可能显得多余
   - **建议**：添加检查，相同时跳过提示

2. **无效路径**
   - 路径字符串转换使用 `display().to_string()`
   - 对于非 UTF-8 路径可能丢失信息

3. **事件流结束**
   - 如果事件流提前结束（`events.next().await` 返回 `None`），循环退出
   - 此时返回 `Session` 作为默认值

### 改进建议

1. **UI 改进**
   - 添加路径存在性验证，如果某个目录不存在，显示警告
   - 添加相对路径显示（相对于 home 目录），使长路径更易读
   - 支持鼠标点击选择（如果终端支持）

2. **功能扩展**
   - 添加"浏览"选项，允许用户选择其他目录
   - 记住用户的选择偏好
   - 添加配置选项设置默认行为

3. **测试覆盖**
   - 当前有快照测试和基本功能测试
   - 建议添加：
     - 键盘导航测试（上下键循环）
     - 事件流异常测试
     - 长路径显示测试

4. **文档完善**
   - 添加模块级文档说明使用场景
   - 说明 ESC 键的默认行为
   - 添加快捷键说明（如 `1`、`2` 数字键）

5. **国际化**
   - 当前所有文本都是硬编码英文
   - 未来考虑支持本地化
