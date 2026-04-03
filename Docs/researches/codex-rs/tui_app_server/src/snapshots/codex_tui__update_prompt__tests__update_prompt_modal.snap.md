# UpdatePrompt - 更新提示模态框测试

## 场景与职责

该快照测试验证了 `UpdatePromptScreen` 组件的渲染输出。当检测到 Codex CLI 有新版本可用时，系统会在启动时显示此模态框，提示用户进行更新。这是一个关键的版本管理功能，确保用户能够及时获取最新功能和安全修复。

**典型使用场景：**
- CLI 启动时自动检查版本更新
- 用户执行特定命令时触发更新检查
- 提供多种更新选项（立即更新、跳过、不再提醒）
- 显示版本变更信息和发布说明链接

## 功能点目的

### 核心功能
1. **版本信息展示**：显示当前版本和最新版本对比
2. **发布说明链接**：提供 GitHub Releases 链接供用户查看详情
3. **多选项交互**：提供三个明确的用户选择
4. **键盘导航**：支持方向键、数字键和 Enter 键操作

### 渲染输出分析
根据快照内容：
```
  ✨ Update available! 0.0.0 -> 9.9.9

  Release notes: https://github.com/openai/codex/releases/latest

› 1. Update now (runs `npm install -g @openai/codex@latest`)                    
  2. Skip
  3. Skip until next version

  Press enter to continue
```

**视觉层次：**
- 标题行：✨ emoji + 粗体 "Update available!" + 暗淡版本对比
- 空行：视觉分隔
- 链接行："Release notes:" 标签 + 下划线链接
- 空行：视觉分隔
- 选项列表：高亮当前选中项（› 前缀）
- 空行：视觉分隔
- 提示行：操作指引

### 选项说明

| 选项 | 快捷键 | 行为 |
|-----|-------|------|
| Update now | 1 / Enter | 执行更新命令并退出 |
| Skip | 2 / Down + Enter | 继续使用当前版本 |
| Skip until next version | 3 | 跳过此版本，下次启动不再提示 |

## 具体技术实现

### 核心数据结构

```rust
pub(crate) enum UpdatePromptOutcome {
    Continue,           // 继续正常启动
    RunUpdate(UpdateAction),  // 执行更新后退出
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum UpdateSelection {
    UpdateNow,
    NotNow,
    DontRemind,
}

struct UpdatePromptScreen {
    request_frame: FrameRequester,
    latest_version: String,
    current_version: String,
    update_action: UpdateAction,
    highlighted: UpdateSelection,
    selection: Option<UpdateSelection>,
}
```

### 主流程函数

```rust
pub(crate) async fn run_update_prompt_if_needed(
    tui: &mut Tui,
    config: &Config,
) -> Result<UpdatePromptOutcome> {
    // 1. 检查是否需要显示更新提示
    let Some(latest_version) = updates::get_upgrade_version_for_popup(config) else {
        return Ok(UpdatePromptOutcome::Continue);
    };
    let Some(update_action) = crate::update_action::get_update_action() else {
        return Ok(UpdatePromptOutcome::Continue);
    };

    // 2. 创建并显示提示屏幕
    let mut screen = UpdatePromptScreen::new(
        tui.frame_requester(),
        latest_version.clone(),
        update_action,
    );
    tui.draw(u16::MAX, |frame| {
        frame.render_widget_ref(&screen, frame.area());
    })?;

    // 3. 事件循环等待用户输入
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
        } else {
            break;
        }
    }

    // 4. 处理用户选择
    match screen.selection() {
        Some(UpdateSelection::UpdateNow) => {
            tui.terminal.clear()?;
            Ok(UpdatePromptOutcome::RunUpdate(update_action))
        }
        Some(UpdateSelection::NotNow) | None => Ok(UpdatePromptOutcome::Continue),
        Some(UpdateSelection::DontRemind) => {
            if let Err(err) = updates::dismiss_version(config, screen.latest_version()).await {
                tracing::error!("Failed to persist update dismissal: {err}");
            }
            Ok(UpdatePromptOutcome::Continue)
        }
    }
}
```

### 键盘事件处理

```rust
fn handle_key(&mut self, key_event: KeyEvent) {
    if key_event.kind == KeyEventKind::Release {
        return;
    }
    // Ctrl+C / Ctrl+D 视为跳过
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

```rust
impl WidgetRef for &UpdatePromptScreen {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        Clear.render(area, buf);  // 清除背景
        let mut column = ColumnRenderable::new();

        let update_command = self.update_action.command_str();

        // 标题
        column.push("");
        column.push(Line::from(vec![
            padded_emoji("  ✨").bold().cyan(),
            "Update available!".bold(),
            " ".into(),
            format!("{current} -> {latest}", ...).dim(),
        ]));
        
        // 发布说明链接
        column.push("");
        column.push(Line::from(vec![
            "Release notes: ".dim(),
            "https://github.com/openai/codex/releases/latest".dim().underlined(),
        ]).inset(Insets::tlbr(0, 2, 0, 0)));
        
        // 选项列表
        column.push("");
        column.push(selection_option_row(0, format!("Update now (runs `{update_command}`)"), ...));
        column.push(selection_option_row(1, "Skip".to_string(), ...));
        column.push(selection_option_row(2, "Skip until next version".to_string(), ...));
        
        // 提示
        column.push("");
        column.push(Line::from(vec![
            "Press ".dim(),
            key_hint::plain(KeyCode::Enter).into(),
            " to continue".dim(),
        ]).inset(Insets::tlbr(0, 2, 0, 0)));
        
        column.render(area, buf);
    }
}
```

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui/src/update_prompt.rs` | 主实现文件 |
| `codex-rs/tui/src/selection_list.rs` | `selection_option_row()` 实现 |
| `codex-rs/tui/src/key_hint.rs` | 按键提示渲染 |
| `codex-rs/tui/src/history_cell.rs` | `padded_emoji()` 工具函数 |
| `codex-rs/tui/src/render/renderable.rs` | `ColumnRenderable` 和 `Insets` |
| `codex-rs/tui/src/updates.rs` | 版本检查和更新逻辑 |
| `codex-rs/tui/src/update_action.rs` | `UpdateAction` 定义 |

### 条件编译

```rust
#![cfg(not(debug_assertions))]
```
- 仅在非调试构建时包含此模块
- 避免开发过程中频繁弹出更新提示

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `ratatui` | UI 渲染框架 |
| `crossterm` | 键盘事件处理 |
| `tokio` | 异步运行时 |
| `tokio-stream` | 事件流处理 |
| `color-eyre` | 错误处理 |
| `codex_core` | 配置管理（`Config`） |

### 配置交互

```rust
// 检查是否需要显示更新提示
updates::get_upgrade_version_for_popup(config)

// 持久化"不再提醒"选择
updates::dismiss_version(config, screen.latest_version()).await
```

### 退出行为

当用户选择 "Update now" 时：
1. 清除终端屏幕
2. 返回 `UpdatePromptOutcome::RunUpdate(action)`
3. 主程序执行更新命令后退出

## 风险、边界与改进建议

### 潜在风险

1. **网络依赖**：
   - 版本检查需要网络连接
   - 离线环境下可能延迟启动
   - 建议：添加超时机制和离线缓存

2. **更新命令失败**：
   - `npm install` 可能因权限、网络等问题失败
   - 当前实现仅执行命令，不验证结果
   - 建议：添加更新后验证和回滚机制

3. **版本比较准确性**：
   - 依赖语义化版本比较
   - 非标准版本号可能导致误判

### 边界情况

1. **CI/自动化环境**：
   - 非交互式环境无法显示模态框
   - 条件编译仅在非调试构建启用
   - 建议：添加 `--no-update-check` 标志

2. **并发更新**：
   - 多个 CLI 实例同时检测到更新
   - 同时执行更新命令可能冲突
   - 建议：添加文件锁机制

3. **权限问题**：
   - 全局安装可能需要 sudo/admin 权限
   - 更新命令失败时用户体验差
   - 建议：预先检查权限并给出提示

### 改进建议

1. **更新渠道**：
   - 当前仅支持 npm 全局安装
   - 建议：支持其他安装方式（brew、cargo 等）
   - 根据安装方式自动选择更新命令

2. **变更日志集成**：
   - 当前仅提供链接
   - 建议：在终端内显示简要变更摘要
   - 使用 Markdown 渲染显示格式化内容

3. **自动更新选项**：
   - 添加 "自动更新" 配置选项
   - 在后台静默更新（需用户授权）

4. **更新频率控制**：
   - 当前每次启动都检查
   - 建议：添加检查间隔（如每天一次）
   - 缓存上次检查时间

5. **可访问性**：
   - 当前依赖颜色区分状态
   - 建议：添加无颜色模式支持
   - 为屏幕阅读器优化

6. **国际化**：
   - 所有文本为硬编码英文
   - 建议：添加本地化支持

### 相关测试

- `update_prompt_snapshot`：基础渲染测试
- `update_prompt_confirm_selects_update`：确认选择测试
- `update_prompt_dismiss_option_leaves_prompt_in_normal_state`：跳过选项测试
- `update_prompt_dont_remind_selects_dismissal`：不再提醒测试
- `update_prompt_ctrl_c_skips_update`：Ctrl+C 处理测试
- `update_prompt_navigation_wraps_between_entries`：导航循环测试

### 安全考虑

1. **URL 验证**：
   - 发布说明链接指向 GitHub
   - 确保链接指向官方仓库
   - 防止中间人攻击篡改更新源

2. **命令注入**：
   - `update_command` 来自配置
   - 需要验证命令安全性
   - 避免执行恶意代码
