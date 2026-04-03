# App Link View Install Suggestion Snapshot 研究文档

## 场景与职责

此快照文件是 `codex_tui` crate 中 `app_link_view` 模块的测试快照，用于验证 **App Link View** 在安装应用建议场景下的 UI 渲染输出。与启用建议不同，此场景针对尚未安装的应用，引导用户完成安装流程。

### 业务场景
- 当 Codex 检测到用户可能需要使用某个未安装的应用（如 Google Calendar）时触发
- 作为工具建议（Tool Suggestion）流程的一部分，通过 MCP Elicitation 机制呈现
- 用户需要先在 ChatGPT 界面中安装应用，然后返回 Codex 确认

### 与 Enable Suggestion 的区别
| 维度 | Install Suggestion | Enable Suggestion |
|------|-------------------|-------------------|
| `is_installed` | `false` | `true` |
| `is_enabled` | `false` | `false`（待启用） |
| `suggestion_type` | `Install` | `Enable` |
| 操作选项 | "Install on ChatGPT", "Back" | "Manage on ChatGPT", "Enable app", "Back" |
| 屏幕流程 | Link → InstallConfirmation | 仅 Link 屏幕 |

## 功能点目的

### 核心功能
1. **应用安装引导**：引导用户到 ChatGPT 界面安装应用
2. **双屏流程**：
   - **Link 屏幕**：显示应用信息，提供"Install on ChatGPT"链接
   - **InstallConfirmation 屏幕**：用户返回后确认"I already Installed it"
3. **浏览器集成**：通过 `AppEvent::OpenUrlInBrowser` 打开安装链接
4. **连接器刷新**：安装完成后刷新连接器列表

### UI 元素（从快照可见）
```
Google Calendar                    # 应用标题（粗体）
Plan events and schedules.         # 应用描述（dim 样式）

Plan and reference events from your calendar  # 建议原因（斜体）

Install this app in your browser, then return here.  # 操作说明
Newly installed apps can take a few minutes to appear in /apps.
After installed, use $ to insert this app into the prompt.

› 1. Install on ChatGPT            # 选中项（› 标记）
  2. Back
Use tab / ↑ ↓ to move, enter to select, esc to close  # 底部提示
```

## 具体技术实现

### 关键状态机

```rust
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum AppLinkScreen {
    Link,                   // 初始屏幕
    InstallConfirmation,    // 安装确认屏幕（打开浏览器后）
}
```

### 屏幕切换逻辑

```rust
fn open_chatgpt_link(&mut self) {
    self.app_event_tx.send(AppEvent::OpenUrlInBrowser {
        url: self.url.clone(),
    });
    if !self.is_installed {
        // 未安装时切换到确认屏幕
        self.screen = AppLinkScreen::InstallConfirmation;
        self.selected_action = 0;
    }
}
```

### InstallConfirmation 屏幕内容

```rust
fn install_confirmation_lines(&self, width: u16) -> Vec<Line<'static>> {
    let mut lines: Vec<Line<'static>> = Vec::new();
    lines.push(Line::from("Finish App Setup".bold()));
    lines.push(Line::from(""));
    
    for line in wrap(
        "Complete app setup on ChatGPT in the browser window that just opened.",
        usable_width,
    ) { ... }
    
    lines.push(Line::from(vec!["Setup URL:".dim()]));
    let url_line = Line::from(vec![self.url.clone().cyan().underlined()]);
    lines.extend(adaptive_wrap_lines(vec![url_line], RtOptions::new(usable_width)));
    lines
}
```

### 操作标签逻辑

```rust
fn action_labels(&self) -> Vec<&'static str> {
    match self.screen {
        AppLinkScreen::Link => {
            if self.is_installed {
                vec!["Manage on ChatGPT", "Enable app", "Back"]
            } else {
                vec!["Install on ChatGPT", "Back"]  // Install 场景
            }
        }
        AppLinkScreen::InstallConfirmation => {
            vec!["I already Installed it", "Back"]
        }
    }
}
```

### 工具建议激活流程

```rust
fn activate_selected_action(&mut self) {
    if self.is_tool_suggestion() {
        match self.suggestion_type {
            Some(AppLinkSuggestionType::Install) | None => match self.screen {
                AppLinkScreen::Link => match self.selected_action {
                    0 => self.open_chatgpt_link(),      // 打开浏览器
                    _ => self.decline_tool_suggestion(), // 拒绝
                },
                AppLinkScreen::InstallConfirmation => match self.selected_action {
                    0 => self.refresh_connectors_and_close(), // 确认安装
                    _ => self.decline_tool_suggestion(),      // 返回/拒绝
                },
            },
            // ... Enable 场景
        }
    }
}
```

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui/src/bottom_pane/app_link_view.rs:315-344` | `install_confirmation_lines` 方法 |
| `codex-rs/tui/src/bottom_pane/app_link_view.rs:116-135` | `action_labels` 方法 |
| `codex-rs/tui/src/bottom_pane/app_link_view.rs:170-178` | `open_chatgpt_link` 方法 |
| `codex-rs/tui/src/bottom_pane/app_link_view.rs:180-188` | `refresh_connectors_and_close` 方法 |
| `codex-rs/tui/src/bottom_pane/app_link_view.rs:893-917` | 安装建议快照测试 |

### 相关测试用例

```rust
#[test]
fn install_tool_suggestion_resolves_elicitation_after_confirmation() {
    // 测试完整流程：Enter 打开链接 → Enter 确认安装 → 验证事件
    view.handle_key_event(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE));
    // 期望: OpenUrlInBrowser 事件
    
    view.handle_key_event(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE));
    // 期望: RefreshConnectors + ResolveElicitation(Accept) 事件
}
```

## 依赖与外部交互

### 关键事件

| 事件 | 方向 | 说明 |
|------|------|------|
| `AppEvent::OpenUrlInBrowser` | TUI → 系统 | 打开浏览器访问 ChatGPT 应用安装页 |
| `AppEvent::RefreshConnectors { force_refetch: true }` | TUI → 后端 | 强制刷新连接器列表 |
| `AppEvent::SubmitThreadOp { op: Op::ResolveElicitation }` | TUI → 后端 | 解析 elicitation 决策 |

### URL 处理

```rust
// adaptive_wrap_lines 确保长 URL 正确换行
lines.extend(adaptive_wrap_lines(
    vec![url_line],
    RtOptions::new(usable_width),
));
```

测试用例 `install_confirmation_does_not_split_long_url_like_token_without_scheme` 验证 URL 不会被错误分割。

## 风险、边界与改进建议

### 特殊边界情况

1. **URL 长度**: 
   - 测试用例验证了长达 200+ 字符的 URL 能正确显示
   - `adaptive_wrap_lines` 确保 URL 尾部可见

2. **无 Scheme 的 URL**:
   ```rust
   let url_like = "example.test/api/v1/projects/...";
   // 测试确保这类 URL 不会被当作多个 token 分割
   ```

3. **安装超时**:
   - 提示文本说明 "Newly installed apps can take a few minutes to appear"
   - 用户可能需要多次刷新才能看到新安装的应用

### 用户体验风险

1. **上下文切换**: 用户需要离开 Codex 去浏览器安装，可能遗忘返回
2. **安装状态检测**: Codex 无法自动检测安装完成，依赖用户手动确认
3. **重复安装**: 如果用户已安装但忘记返回确认，可能重复安装

### 改进建议

1. **自动检测**: 定期轮询连接器状态，自动检测新安装的应用
2. **通知机制**: 安装完成后通过系统通知提醒用户
3. **取消流程**: 当前拒绝后直接关闭，应提供"稍后再说"选项
4. **进度指示**: 添加"正在刷新连接器..."的加载状态
5. **帮助链接**: 添加指向应用文档的链接，帮助用户了解应用功能

### 测试覆盖建议

```rust
// 建议添加的测试
#[test]
fn install_confirmation_narrow_width_keeps_url_visible() { ... }

#[test]
fn declined_install_sends_decline_elicitation() { ... }

#[test]
fn back_from_confirmation_returns_to_link_screen() { ... }
```
