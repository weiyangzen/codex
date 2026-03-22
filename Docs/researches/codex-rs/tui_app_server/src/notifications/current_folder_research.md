# Codex TUI App Server Notifications 模块研究文档

## 1. 场景与职责

### 1.1 模块定位

`codex-rs/tui_app_server/src/notifications` 模块是 Codex TUI（Terminal User Interface）应用服务器的**桌面通知子系统**，负责在终端失去焦点时向用户发送桌面级通知。该模块是连接 Codex 核心功能与用户桌面环境的桥梁，确保用户即使在终端未激活状态下也能及时获取重要事件提醒。

### 1.2 核心职责

1. **终端环境检测**：自动检测当前终端类型，判断是否支持高级通知协议（OSC 9）
2. **通知后端抽象**：提供统一的后端接口，支持多种通知机制（OSC 9、BEL）
3. **通知触发管理**：在特定用户交互事件发生时触发桌面通知
4. **配置集成**：与 Codex 配置系统深度集成，支持用户自定义通知行为

### 1.3 使用场景

| 场景 | 描述 |
|------|------|
| Agent 完成响应 | 当 AI Agent 完成一轮对话并生成回复时 |
| 执行命令审批 | 当需要用户批准执行 shell 命令时 |
| 文件编辑审批 | 当需要用户批准文件修改时 |
| MCP 服务器请求 | 当 MCP 服务器需要用户输入时 |
| 计划模式提示 | 当进入计划模式需要用户确认时 |
| 用户输入请求 | 当 Agent 需要向用户提问时 |

---

## 2. 功能点目的

### 2.1 双后端通知机制

模块实现了两种通知后端以适配不同终端环境：

#### OSC 9 后端（现代终端）
- **目的**：利用现代终端（iTerm2、WezTerm、Ghostty、Kitty）支持的 OSC 9 控制序列发送带内容的桌面通知
- **优势**：支持自定义通知内容，用户体验更佳
- **格式**：`\x1b]9;{message}\x07`

#### BEL 后端（通用回退）
- **目的**：在不支持 OSC 9 的终端中通过 BEL 字符（`\x07`）触发终端的默认通知机制
- **优势**：兼容性极强，几乎所有终端都支持
- **局限**：无法携带自定义消息内容

### 2.2 智能后端选择

模块通过 `NotificationMethod::Auto` 实现智能选择：

```rust
pub enum NotificationMethod {
    Auto,   // 自动检测并选择最佳后端
    Osc9,   // 强制使用 OSC 9
    Bel,    // 强制使用 BEL
}
```

### 2.3 通知类型与优先级

模块支持 6 种通知类型，按优先级分为两个等级：

| 优先级 | 通知类型 | 触发条件 |
|--------|----------|----------|
| 1 (高) | `ExecApprovalRequested` | 需要批准执行命令 |
| 1 (高) | `EditApprovalRequested` | 需要批准文件编辑 |
| 1 (高) | `ElicitationRequested` | MCP 服务器需要输入 |
| 1 (高) | `PlanModePrompt` | 计划模式提示 |
| 1 (高) | `UserInputRequested` | 需要用户回答问题 |
| 0 (低) | `AgentTurnComplete` | Agent 完成响应 |

高优先级通知会覆盖低优先级的待处理通知。

### 2.4 用户配置控制

通过 `Notifications` 配置类型，用户可以精细控制通知行为：

```rust
pub enum Notifications {
    Enabled(bool),           // 全局开关
    Custom(Vec<String>),     // 按类型启用
}
```

---

## 3. 具体技术实现

### 3.1 核心数据结构

#### DesktopNotificationBackend（后端枚举）

```rust
#[derive(Debug)]
pub enum DesktopNotificationBackend {
    Osc9(Osc9Backend),
    Bel(BelBackend),
}
```

位于：`codex-rs/tui_app_server/src/notifications/mod.rs:12-15`

#### Osc9Backend 实现

```rust
#[derive(Debug, Default)]
pub struct Osc9Backend;

impl Osc9Backend {
    pub fn notify(&mut self, message: &str) -> io::Result<()> {
        execute!(stdout(), PostNotification(message.to_string()))
    }
}
```

位于：`codex-rs/tui_app_server/src/notifications/osc9.rs:8-14`

`PostNotification` 是一个实现 `crossterm::Command` 的结构体，负责生成 OSC 9 序列：

```rust
impl Command for PostNotification {
    fn write_ansi(&self, f: &mut impl fmt::Write) -> fmt::Result {
        write!(f, "\x1b]9;{}\x07", self.0)  // OSC 9 格式
    }
    // ...
}
```

位于：`codex-rs/tui_app_server/src/notifications/osc9.rs:21-24`

#### BelBackend 实现

```rust
#[derive(Debug, Default)]
pub struct BelBackend;

impl BelBackend {
    pub fn notify(&mut self, _message: &str) -> io::Result<()> {
        execute!(stdout(), PostNotification)  // 忽略消息内容
    }
}
```

位于：`codex-rs/tui_app_server/src/notifications/bel.rs:8-14`

BEL 格式的 `PostNotification` 仅输出 `\x07`：

```rust
impl Command for PostNotification {
    fn write_ansi(&self, f: &mut impl fmt::Write) -> fmt::Result {
        write!(f, "\x07")  // BEL 字符
    }
    // ...
}
```

位于：`codex-rs/tui_app_server/src/notifications/bel.rs:22-24`

### 3.2 终端检测逻辑

`supports_osc9()` 函数通过环境变量检测终端类型：

```rust
fn supports_osc9() -> bool {
    // Windows Terminal 明确不支持 OSC 9
    if env::var_os("WT_SESSION").is_some() {
        return false;
    }
    
    // 优先检测 TERM_PROGRAM
    if matches!(
        env::var("TERM_PROGRAM").ok().as_deref(),
        Some("WezTerm" | "ghostty")
    ) {
        return true;
    }
    
    // iTerm 会话检测
    if env::var_os("ITERM_SESSION_ID").is_some() {
        return true;
    }
    
    // TERM 变量检测（覆盖 kitty/wezterm）
    matches!(
        env::var("TERM").ok().as_deref(),
        Some("xterm-kitty" | "wezterm" | "wezterm-mux")
    )
}
```

位于：`codex-rs/tui_app_server/src/notifications/mod.rs:51-72`

### 3.3 通知触发流程

#### 阶段 1：事件产生

在 `ChatWidget` 中，当特定事件发生时调用 `notify()`：

```rust
fn notify(&mut self, notification: Notification) {
    // 1. 检查通知是否被配置允许
    if !notification.allowed_for(&self.config.tui_notifications) {
        return;
    }
    
    // 2. 优先级检查：高优先级覆盖低优先级
    if let Some(existing) = self.pending_notification.as_ref()
        && existing.priority() > notification.priority()
    {
        return;
    }
    
    // 3. 存储待处理通知并请求重绘
    self.pending_notification = Some(notification);
    self.request_redraw();
}
```

位于：`codex-rs/tui_app_server/src/chatwidget.rs:6716-6727`

#### 阶段 2：待处理通知投递

在 TUI 绘制循环中，`maybe_post_pending_notification()` 被调用：

```rust
pub(crate) fn maybe_post_pending_notification(&mut self, tui: &mut crate::tui::Tui) {
    if let Some(notif) = self.pending_notification.take() {
        tui.notify(notif.display());
    }
}
```

位于：`codex-rs/tui_app_server/src/chatwidget.rs:6729-6733`

调用点位于 `app.rs` 的绘制事件处理中：

```rust
TuiEvent::Draw => {
    // ...
    self.chat_widget.maybe_post_pending_notification(tui);
    // ...
}
```

位于：`codex-rs/tui_app_server/src/app.rs:3312`

#### 阶段 3：TUI 层通知发送

`Tui::notify()` 执行实际的通知发送：

```rust
pub fn notify(&mut self, message: impl AsRef<str>) -> bool {
    // 1. 终端处于焦点时不发送通知
    if self.terminal_focused.load(Ordering::Relaxed) {
        return false;
    }
    
    let Some(backend) = self.notification_backend.as_mut() else {
        return false;
    };
    
    // 2. 调用后端发送通知
    let message = message.as_ref().to_string();
    match backend.notify(&message) {
        Ok(()) => true,
        Err(err) => {
            // 3. 发送失败时禁用后续通知
            let method = backend.method();
            tracing::warn!(...);
            self.notification_backend = None;
            false
        }
    }
}
```

位于：`codex-rs/tui_app_server/src/tui.rs:362-385`

### 3.4 通知内容生成

`Notification::display()` 方法生成人类可读的通知文本：

```rust
fn display(&self) -> String {
    match self {
        Notification::AgentTurnComplete { response } => {
            Notification::agent_turn_preview(response)
                .unwrap_or_else(|| "Agent turn complete".to_string())
        }
        Notification::ExecApprovalRequested { command } => {
            format!("Approval requested: {}", truncate_text(command, 30))
        }
        Notification::EditApprovalRequested { cwd, changes } => {
            format!("Codex wants to edit {}", ...)
        }
        // ... 其他类型
    }
}
```

位于：`codex-rs/tui_app_server/src/chatwidget.rs:10472-10510`

### 3.5 配置类型定义

`NotificationMethod` 和 `Notifications` 定义在核心配置模块：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, Default)]
#[serde(rename_all = "lowercase")]
pub enum NotificationMethod {
    #[default]
    Auto,
    Osc9,
    Bel,
}

#[derive(Serialize, Debug, Clone, PartialEq, Eq, Deserialize, JsonSchema)]
#[serde(untagged)]
pub enum Notifications {
    Enabled(bool),
    Custom(Vec<String>),
}
```

位于：`codex-rs/core/src/config/types.rs:685-683`

TUI 配置结构：

```rust
pub struct Tui {
    #[serde(default)]
    pub notifications: Notifications,
    #[serde(default)]
    pub notification_method: NotificationMethod,
    // ...
}
```

位于：`codex-rs/core/src/config/types.rs:715-724`

---

## 4. 关键代码路径与文件引用

### 4.1 模块文件结构

```
codex-rs/tui_app_server/src/notifications/
├── mod.rs      # 后端枚举、检测逻辑、单元测试
├── osc9.rs     # OSC 9 后端实现
└── bel.rs      # BEL 后端实现
```

### 4.2 关键代码路径

| 功能 | 文件路径 | 行号范围 |
|------|----------|----------|
| 后端枚举定义 | `notifications/mod.rs` | 11-45 |
| 终端检测逻辑 | `notifications/mod.rs` | 51-72 |
| OSC 9 后端 | `notifications/osc9.rs` | 1-37 |
| BEL 后端 | `notifications/bel.rs` | 1-37 |
| TUI 通知接口 | `tui.rs` | 362-385 |
| 通知类型定义 | `chatwidget.rs` | 10447-10572 |
| 通知触发逻辑 | `chatwidget.rs` | 6716-6733 |
| 配置类型定义 | `core/src/config/types.rs` | 672-724 |

### 4.3 调用链

```
用户事件触发
    ↓
ChatWidget::notify(Notification::XXX)  [chatwidget.rs:6716]
    ↓
pending_notification 存储
    ↓
TuiEvent::Draw 处理  [app.rs:3307]
    ↓
ChatWidget::maybe_post_pending_notification()  [chatwidget.rs:6729]
    ↓
Tui::notify(message)  [tui.rs:362]
    ↓
DesktopNotificationBackend::notify()  [notifications/mod.rs:39]
    ↓
Osc9Backend::notify() / BelBackend::notify()
    ↓
execute!(stdout(), PostNotification)
    ↓
终端显示桌面通知
```

### 4.4 测试覆盖

模块包含完整的单元测试：

```rust
#[cfg(test)]
mod tests {
    #[test]
    fn selects_osc9_method() { ... }
    
    #[test]
    fn selects_bel_method() { ... }
    
    #[test]
    #[serial]
    fn auto_prefers_bel_without_hints() { ... }
    
    #[test]
    #[serial]
    fn auto_uses_osc9_for_iterm() { ... }
}
```

位于：`codex-rs/tui_app_server/src/notifications/mod.rs:74-156`

测试使用 `EnvVarGuard` 结构安全地操作环境变量，并使用 `serial_test::serial` 确保测试串行执行。

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| 依赖模块 | 用途 |
|----------|------|
| `codex_core::config::types::NotificationMethod` | 配置类型定义 |
| `crate::tui::Tui` | TUI 层通知接口 |
| `crate::chatwidget::ChatWidget` | 通知触发源 |

### 5.2 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `crossterm` | 终端控制序列执行 |
| `ratatui` | 终端 UI 框架（通过 `ratatui::crossterm::execute`） |

### 5.3 协议依赖

模块通过 `codex_core::config::types` 与配置系统交互：

- `NotificationMethod`：定义通知方法选择策略
- `Notifications`：定义通知启用配置

### 5.4 并行实现

根据项目 AGENTS.md 规范，当 `tui_app_server` 的变更涉及 `tui` 时，需要在两者间保持同步。`codex-rs/tui/src/notifications/` 目录包含与 `tui_app_server` 完全相同的实现：

- `codex-rs/tui/src/notifications/mod.rs`
- `codex-rs/tui/src/notifications/osc9.rs`
- `codex-rs/tui/src/notifications/bel.rs`

### 5.5 App Server 协议交互

虽然 `opt_out_notification_methods` 在 app-server-protocol 中定义（`v1::InitializeCapabilities`），但 TUI 通知模块**不直接使用**该字段。该字段用于控制服务器向客户端发送的 RPC 通知，而本模块处理的是**终端桌面通知**。

```rust
// app-server-protocol 中的定义（供参考）
pub struct InitializeCapabilities {
    pub experimental_api: bool,
    pub opt_out_notification_methods: Option<Vec<String>>,  // 控制服务器通知
}
```

位于：`codex-rs/app-server-protocol/src/protocol/v1.rs:42-53`

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 风险 1：Windows Terminal 不支持 OSC 9
- **描述**：Windows Terminal 虽然设置了 `WT_SESSION`，但明确不支持 OSC 9 通知
- **缓解**：`supports_osc9()` 函数明确检查并排除 `WT_SESSION`
- **残余风险**：用户可能困惑为何在 Windows Terminal 中看不到富文本通知

#### 风险 2：通知失败静默禁用
- **描述**：当通知发送失败时，模块会永久禁用通知后端
- **代码**：`self.notification_backend = None;` [tui.rs:381]
- **影响**：用户可能错过重要通知且不知情
- **建议**：添加用户可见的警告或重试机制

#### 风险 3：环境变量检测的可靠性
- **描述**：终端检测依赖环境变量，可能在某些场景下失效（如通过脚本启动、远程 SSH）
- **案例**：tmux/ssh 可能不设置 `TERM_PROGRAM`
- **缓解**：使用 `TERM` 变量作为后备检测

### 6.2 边界条件

| 边界条件 | 行为 |
|----------|------|
| 终端处于焦点 | 不发送任何通知 |
| 通知后端为 None | 直接返回 false |
| 空消息内容 | 正常发送（OSC 9 发送空字符串，BEL 忽略） |
| 高优先级覆盖 | 新通知优先级 ≥ 现有时才替换 |
| 配置为禁用 | `notify()` 直接返回，不存储 |

### 6.3 改进建议

#### 建议 1：添加通知失败用户提示

当前通知失败仅记录日志，建议增加用户可见提示：

```rust
// 建议添加
if !success {
    self.status_line.show_warning("Desktop notifications disabled due to error");
}
```

#### 建议 2：支持更多终端原生通知

考虑增加对以下终端的支持：
- **tmux**：通过 `tmux display-message`
- **screen**：通过 `screen -X echo`
- **Alacritty**：OSC 9 支持（需验证）

#### 建议 3：通知去重机制

当前实现中，相同类型的重复通知会相互覆盖。建议添加去重窗口期（如 5 秒内相同类型不重复通知）。

#### 建议 4：配置热重载

当前 `notification_backend` 在 `Tui::new()` 中初始化后不可更改。建议支持配置热重载，允许用户在会话中调整通知设置。

#### 建议 5：通知历史记录

考虑添加通知历史记录功能，允许用户查看错过的通知。

### 6.4 代码质量建议

1. **文档完善**：`BelBackend::notify` 忽略 `message` 参数，应在文档中明确说明
2. **错误分类**：当前所有 IO 错误都导致后端禁用，应区分临时错误（如终端忙）和永久错误
3. **测试覆盖**：建议增加集成测试，验证在真实终端环境中的行为

---

## 附录：相关配置示例

### config.toml 配置

```toml
[tui]
# 启用桌面通知（默认 true）
notifications = true

# 或按类型启用
notifications = ["agent-turn-complete", "approval-requested", "user-input-requested"]

# 通知方法（默认 auto）
notification_method = "auto"  # 可选: "osc9", "bel"
```

### 环境变量调试

```bash
# 强制使用 BEL 后端
unset TERM_PROGRAM ITERM_SESSION_ID
export TERM=xterm

# 强制使用 OSC 9 后端（iTerm2）
export ITERM_SESSION_ID=w0t0p0:12345678-1234-1234-1234-123456789012

# Windows Terminal（将回退到 BEL）
export WT_SESSION=12345678-1234-1234-1234-123456789012
```

---

*文档生成时间：2026-03-22*
*研究范围：codex-rs/tui_app_server/src/notifications/*
*版本：基于主分支最新代码*
