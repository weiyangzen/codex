# update_prompt.rs 研究文档

## 场景与职责

`update_prompt.rs` 实现 Codex TUI 的更新提示界面，当检测到有新版本可用时，向用户展示模态对话框，提供更新、跳过或不再提醒的选项。

主要使用场景：
- TUI 启动后检查到新版本
- 根据安装方式显示相应的更新命令
- 处理用户的选择并执行相应操作

## 功能点目的

### 1. 更新提示流程控制

**主函数**：
```rust
pub(crate) async fn run_update_prompt_if_needed(
    tui: &mut Tui,
    config: &Config,
) -> Result<UpdatePromptOutcome>
```

**流程**：
1. 检查是否有可用更新（`updates::get_upgrade_version_for_popup`）
2. 检查是否支持自动更新（`get_update_action`）
3. 创建并显示更新提示界面
4. 等待用户输入并处理选择
5. 返回处理结果

**结果类型**：
```rust
pub(crate) enum UpdatePromptOutcome {
    Continue,           // 继续正常运行
    RunUpdate(UpdateAction),  // 执行更新
}
```

### 2. 更新选择枚举

**定义**：
```rust
enum UpdateSelection {
    UpdateNow,   // 立即更新
    NotNow,      // 暂不更新
    DontRemind,  // 不再提醒（当前版本）
}
```

**导航**：
- 支持键盘导航（↑/↓ 或 k/j）
- 支持数字快捷键（1/2/3）
- 支持 Enter 确认、Esc 取消
- 支持 Ctrl+C/Ctrl+D 取消

### 3. 更新提示界面渲染

**结构**：
```rust
struct UpdatePromptScreen {
    request_frame: FrameRequester,
    latest_version: String,
    current_version: String,
    update_action: UpdateAction,
    highlighted: UpdateSelection,
    selection: Option<UpdateSelection>,
}
```

**界面元素**：
- 标题："✨ Update available!"
- 版本信息：`current -> latest`
- 发布说明链接
- 三个选项（带高亮指示）
- 操作提示

### 4. 不再提醒功能

**实现**：
当用户选择 "Skip until next version" 时：
```rust
Some(UpdateSelection::DontRemind) => {
    if let Err(err) = updates::dismiss_version(config, screen.latest_version()).await {
        tracing::error!("Failed to persist update dismissal: {err}");
    }
    Ok(UpdatePromptOutcome::Continue)
}
```

将当前版本标记为已忽略，下次启动时不再提示。

## 具体技术实现

### 事件循环

```rust
let events = tui.event_stream();
tokio::pin!(events);

while !screen.is_done() {
    if let Some(event) = events.next().await {
        match event {
            TuiEvent::Key(key_event) => screen.handle_key(key_event),
            TuiEvent::Paste(_) => {}
            TuiEvent::Draw => {
                tui.draw(u16::MAX, |frame| {
                    frame.render_widget_ref(&screen, frame.area());
                })?;
            }
        }
    }
}
```

### 键盘处理

```rust
fn handle_key(&mut self, key_event: KeyEvent) {
    if key_event.kind == KeyEventKind::Release {
        return;
    }
    // Ctrl+C / Ctrl+D 取消
    if key_event.modifiers.contains(KeyModifiers::CONTROL)
        && matches!(key_event.code, KeyCode::Char('c') | KeyCode::Char('d'))
    {
        self.select(UpdateSelection::NotNow);
        return;
    }
    match key_event.code {
        KeyCode::Up | KeyCode::Char('k') => self.set_highlight(self.highlighted.prev()),
        KeyCode::Down | KeyCode::Char('j') => self.set_highlight(self.highlighted.next()),
        KeyCode::Char('1') => self.select(UpdateSelection::UpdateNow),
        KeyCode::Char('2') => self.select(UpdateSelection::NotNow),
        KeyCode::Char('3') => self.select(UpdateSelection::DontRemind),
        KeyCode::Enter => self.select(self.highlighted),
        KeyCode::Esc => self.select(UpdateSelection::NotNow),
        _ => {}
    }
}
```

### 渲染实现

实现 `WidgetRef` trait：
```rust
impl WidgetRef for &UpdatePromptScreen {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        Clear.render(area, buf);  // 清除背景
        let mut column = ColumnRenderable::new();
        
        // 标题和版本信息
        column.push(Line::from(vec![
            padded_emoji("  ✨").bold().cyan(),
            "Update available!".bold(),
            format!("{current} -> {latest}", ...).dim(),
        ]));
        
        // 选项行
        column.push(selection_option_row(...));
        
        column.render(area, buf);
    }
}
```

### 选择导航

```rust
impl UpdateSelection {
    fn next(self) -> Self {
        match self {
            UpdateSelection::UpdateNow => UpdateSelection::NotNow,
            UpdateSelection::NotNow => UpdateSelection::DontRemind,
            UpdateSelection::DontRemind => UpdateSelection::UpdateNow,
        }
    }

    fn prev(self) -> Self {
        match self {
            UpdateSelection::UpdateNow => UpdateSelection::DontRemind,
            UpdateSelection::NotNow => UpdateSelection::UpdateNow,
            UpdateSelection::DontRemind => UpdateSelection::NotNow,
        }
    }
}
```

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 |
|------|------|
| `update_prompt.rs` | 更新提示界面实现 |

### 依赖模块

| 模块 | 用途 |
|------|------|
| `updates` | 获取可用版本信息 |
| `update_action` | 确定更新命令 |
| `tui` | 终端 UI 基础设施 |
| `history_cell` | `padded_emoji` 辅助函数 |
| `key_hint` | 键盘提示显示 |
| `render` | 渲染辅助工具 |
| `selection_list` | 选择列表行渲染 |

### 调用方

| 文件 | 调用点 |
|------|--------|
| `main.rs` 或 `lib.rs` | TUI 启动流程中调用 `run_update_prompt_if_needed` |

### 依赖关系

```
update_prompt.rs
├── updates.rs              (版本检查)
├── update_action.rs        (更新命令)
├── tui.rs                  (TUI 基础设施)
├── history_cell.rs         (padded_emoji)
├── key_hint.rs             (键盘提示)
├── render/                 (渲染工具)
├── selection_list.rs       (选项行)
└── codex_core::config      (配置)
```

## 依赖与外部交互

### 外部 crate

| Crate | 用途 |
|-------|------|
| `ratatui` | UI 渲染（Buffer、Rect、Widget 等） |
| `crossterm` | 键盘事件处理 |
| `color-eyre` | 错误处理 |
| `tokio-stream` | 事件流处理 |

### 内部模块

| 模块 | 用途 |
|------|------|
| `crate::tui` | Tui 实例和事件流 |
| `crate::updates` | 版本检查和忽略功能 |
| `crate::update_action` | 更新动作枚举 |
| `crate::history_cell` | 表情符号填充 |
| `crate::key_hint` | 键盘提示渲染 |
| `crate::render` | 渲染辅助工具 |
| `crate::selection_list` | 选择列表 UI |

## 风险、边界与改进建议

### 已知风险

1. **调试构建禁用**
   - `#![cfg(not(debug_assertions))]` 使整个模块在调试构建中不可用
   - 可能导致发布构建与调试构建行为不一致
   - 缓解：测试时使用发布构建或条件编译测试

2. **网络依赖**
   - 版本检查依赖网络请求，可能阻塞或失败
   - 缓解：`updates` 模块使用后台任务和缓存

3. **更新命令失败**
   - 用户选择更新后，实际的包管理器命令可能失败
   - 当前实现返回 `RunUpdate` 后由调用方执行，错误处理在上层

### 边界条件

1. **无可用更新**
   - `get_upgrade_version_for_popup` 返回 `None` 时直接返回 `Continue`

2. **不支持自动更新**
   - `get_update_action` 返回 `None` 时直接返回 `Continue`

3. **终端大小变化**
   - 渲染使用 `u16::MAX` 高度，依赖 ratatui 自动处理

4. **事件流结束**
   - 如果事件流意外结束，退出循环返回 `Continue`

### 改进建议

1. **异步版本检查**
   - 当前在提示前同步检查版本，可考虑完全异步化
   - 在后台检查版本，准备好后再显示提示

2. **更新预览**
   - 显示更新日志摘要或变更列表
   - 帮助用户决定是否更新

3. **定时提醒**
   - "不再提醒" 当前仅针对单个版本
   - 可考虑添加 "一周后提醒" 选项

4. **更好的错误提示**
   - 如果 `dismiss_version` 失败，当前仅记录日志
   - 可向用户显示警告

5. **无障碍支持**
   - 添加屏幕阅读器友好的标签
   - 确保高对比度模式下的可见性

6. **测试覆盖**
   - 当前测试覆盖基本功能
   - 可添加更多边界条件测试（如极小终端尺寸）
