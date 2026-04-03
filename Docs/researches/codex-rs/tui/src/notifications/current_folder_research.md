# Codex TUI Notifications 模块研究报告

## 1. 场景与职责

### 1.1 模块定位

`codex-rs/tui/src/notifications` 模块是 Codex TUI（终端用户界面）的**桌面通知子系统**，负责在终端失去焦点时向用户发送桌面级通知。该模块解决了以下核心场景：

- **异步任务完成提醒**：当 AI Agent 完成一轮对话（turn）时通知用户
- **审批请求提醒**：当需要用户批准执行命令、编辑文件或 MCP 工具调用时
- **用户输入请求**：当 Agent 需要用户回答问题以继续任务时
- **计划模式提示**：当进入计划模式（Plan Mode）需要用户确认时

### 1.2 使用场景

| 场景 | 触发条件 | 通知内容 |
|------|----------|----------|
| Agent 完成回复 | 模型生成响应完成 | "Agent turn complete" + 响应预览（前200字符） |
| 执行命令审批 | 需要用户批准执行 shell 命令 | "Approval requested: {command}" |
| 文件编辑审批 | 需要用户批准文件修改 | "Codex wants to edit {file}" |
| MCP 工具审批 | 需要用户批准 MCP 服务器操作 | "Approval requested by {server_name}" |
| 计划模式提示 | 进入计划实现或推理范围确认 | "Plan mode prompt: {title}" |
| 用户输入请求 | Agent 需要用户回答问题 | "Question requested: {summary}" |

### 1.3 核心职责

1. **终端能力检测**：自动检测终端模拟器支持的桌面通知协议
2. **通知协议实现**：支持 OSC 9 和 BEL 两种终端通知协议
3. **通知内容生成**：将内部通知事件转换为人类可读的文本
4. **通知优先级管理**：高优先级通知可覆盖低优先级待发送通知
5. **配置集成**：与 `config.toml` 配置系统深度集成

---

## 2. 功能点目的

### 2.1 双协议支持（OSC 9 vs BEL）

| 协议 | 技术原理 | 支持终端 | 消息内容 |
|------|----------|----------|----------|
| **OSC 9** | ANSI 转义序列 `\x1b]9;{message}\x07` | iTerm2, WezTerm, Ghostty, Kitty | 支持自定义消息内容 |
| **BEL** | ASCII 控制字符 `\x07` | 所有终端 | 仅触发系统默认提示音/通知 |

**设计决策**：
- OSC 9 提供更丰富的用户体验（显示具体消息内容）
- BEL 作为通用回退方案，确保兼容性
- 自动检测机制优先选择 OSC 9（如果终端支持）

### 2.2 自动检测机制

```rust
fn supports_osc9() -> bool {
    // Windows Terminal 明确不支持 OSC 9
    if env::var_os("WT_SESSION").is_some() { return false; }
    
    // 通过 TERM_PROGRAM 检测
    if matches!(env::var("TERM_PROGRAM").ok().as_deref(),
        Some("WezTerm" | "ghostty")) { return true; }
    
    // iTerm2 会话检测
    if env::var_os("ITERM_SESSION_ID").is_some() { return true; }
    
    // TERM 变量检测（覆盖 tmux/ssh 场景）
    matches!(env::var("TERM").ok().as_deref(),
        Some("xterm-kitty" | "wezterm" | "wezterm-mux"))
}
```

### 2.3 通知类型与过滤

**通知类型标识**（`type_name()` 方法返回）：
- `agent-turn-complete`：Agent 完成回复
- `approval-requested`：执行/编辑/MCP 审批请求（三类合并）
- `plan-mode-prompt`：计划模式提示
- `user-input-requested`：用户输入请求

**配置过滤机制**：
- `Notifications::Enabled(true)`：允许所有通知
- `Notifications::Enabled(false)`：禁止所有通知
- `Notifications::Custom(vec)`：仅允许列表中指定的通知类型

### 2.4 优先级系统

| 优先级 | 值 | 通知类型 |
|--------|-----|----------|
| 低 | 0 | AgentTurnComplete |
| 高 | 1 | ExecApprovalRequested, EditApprovalRequested, ElicitationRequested, PlanModePrompt, UserInputRequested |

**优先级行为**：
- 高优先级通知可覆盖待发送的低优先级通知
- 低优先级通知不会覆盖待发送的高优先级通知
- 同优先级遵循"后来者居上"原则

---

## 3. 具体技术实现

### 3.1 模块结构

```
codex-rs/tui/src/notifications/
├── mod.rs          # 主模块：后端枚举、自动检测、测试
├── osc9.rs         # OSC 9 协议实现
└── bel.rs          # BEL 协议实现
```

### 3.2 核心数据结构

#### 3.2.1 DesktopNotificationBackend（后端枚举）

```rust
#[derive(Debug)]
pub enum DesktopNotificationBackend {
    Osc9(Osc9Backend),
    Bel(BelBackend),
}

impl DesktopNotificationBackend {
    pub fn for_method(method: NotificationMethod) -> Self;
    pub fn method(&self) -> NotificationMethod;
    pub fn notify(&mut self, message: &str) -> io::Result<()>;
}
```

#### 3.2.2 OSC 9 实现

```rust
#[derive(Debug, Default)]
pub struct Osc9Backend;

impl Osc9Backend {
    pub fn notify(&mut self, message: &str) -> io::Result<()> {
        execute!(stdout(), PostNotification(message.to_string()))
    }
}

#[derive(Debug, Clone)]
pub struct PostNotification(pub String);

impl Command for PostNotification {
    fn write_ansi(&self, f: &mut impl fmt::Write) -> fmt::Result {
        write!(f, "\x1b]9;{}\x07", self.0)  // OSC 9 格式
    }
    // Windows 平台：强制使用 ANSI，拒绝 WinAPI
}
```

#### 3.2.3 BEL 实现

```rust
#[derive(Debug, Default)]
pub struct BelBackend;

impl BelBackend {
    pub fn notify(&mut self, _message: &str) -> io::Result<()> {
        execute!(stdout(), PostNotification)  // 忽略消息内容
    }
}

impl Command for PostNotification {
    fn write_ansi(&self, f: &mut impl fmt::Write) -> fmt::Result {
        write!(f, "\x07")  // BEL 字符
    }
}
```

### 3.3 通知事件定义（chatwidget.rs）

```rust
#[derive(Debug)]
enum Notification {
    AgentTurnComplete { response: String },
    ExecApprovalRequested { command: String },
    EditApprovalRequested { cwd: PathBuf, changes: Vec<PathBuf> },
    ElicitationRequested { server_name: String },
    PlanModePrompt { title: String },
    UserInputRequested { question_count: usize, summary: Option<String> },
}
```

### 3.4 配置类型定义（core/src/config/types.rs）

```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, Default)]
#[serde(rename_all = "lowercase")]
pub enum NotificationMethod {
    #[default]
    Auto,    // 自动检测
    Osc9,    // 强制使用 OSC 9
    Bel,     // 强制使用 BEL
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Default, JsonSchema)]
#[serde(untagged)]
pub enum Notifications {
    Enabled(bool),
    Custom(Vec<String>),
}
```

### 3.5 TUI 集成（tui.rs）

```rust
pub struct Tui {
    // ... 其他字段
    notification_backend: Option<DesktopNotificationBackend>,
    terminal_focused: Arc<AtomicBool>,  // 终端焦点状态
}

impl Tui {
    pub fn notify(&mut self, message: impl AsRef<str>) -> bool {
        // 1. 检查终端是否失去焦点
        if self.terminal_focused.load(Ordering::Relaxed) {
            return false;
        }
        
        // 2. 获取后端
        let Some(backend) = self.notification_backend.as_mut() else {
            return false;
        };
        
        // 3. 发送通知
        match backend.notify(&message) {
            Ok(()) => true,
            Err(err) => {
                // 发送失败时禁用后续通知（避免重复错误）
                self.notification_backend = None;
                false
            }
        }
    }
    
    pub fn set_notification_method(&mut self, method: NotificationMethod) {
        self.notification_backend = Some(detect_backend(method));
    }
}
```

### 3.6 ChatWidget 集成（chatwidget.rs）

```rust
pub struct ChatWidget {
    // ... 其他字段
    pending_notification: Option<Notification>,  // 待发送通知
    config: Arc<Config>,  // 包含 tui_notifications 配置
}

impl ChatWidget {
    fn notify(&mut self, notification: Notification) {
        // 1. 检查配置是否允许该类型通知
        if !notification.allowed_for(&self.config.tui_notifications) {
            return;
        }
        
        // 2. 优先级检查
        if let Some(existing) = self.pending_notification.as_ref()
            && existing.priority() > notification.priority() {
            return;
        }
        
        // 3. 设置待发送通知并请求重绘
        self.pending_notification = Some(notification);
        self.request_redraw();
    }
    
    pub(crate) fn maybe_post_pending_notification(&mut self, tui: &mut crate::tui::Tui) {
        if let Some(notif) = self.pending_notification.take() {
            tui.notify(notif.display());
        }
    }
}
```

### 3.7 主事件循环集成（app.rs）

```rust
// 初始化时设置通知方法
tui.set_notification_method(config.tui_notification_method);

// 每次绘制前检查并发送待处理通知
TuiEvent::Draw => {
    self.chat_widget.maybe_post_pending_notification(tui);
    // ... 渲染逻辑
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件

| 文件路径 | 行数 | 职责 |
|----------|------|------|
| `codex-rs/tui/src/notifications/mod.rs` | 156 | 后端枚举定义、自动检测逻辑、单元测试 |
| `codex-rs/tui/src/notifications/osc9.rs` | 37 | OSC 9 协议实现 |
| `codex-rs/tui/src/notifications/bel.rs` | 37 | BEL 协议实现 |
| `codex-rs/tui/src/tui.rs` | ~450 | TUI 结构体、通知方法设置、实际发送逻辑 |
| `codex-rs/tui/src/chatwidget.rs` | ~9450 | Notification 枚举定义、通知生成、优先级管理 |
| `codex-rs/tui/src/app.rs` | ~4600 | 主事件循环集成、配置传递 |

### 4.2 配置文件相关

| 文件路径 | 职责 |
|----------|------|
| `codex-rs/core/src/config/types.rs` | `NotificationMethod` 和 `Notifications` 类型定义 |
| `codex-rs/core/src/config/mod.rs` | 配置加载、默认值处理 |
| `codex-rs/core/config.schema.json` | JSON Schema 定义（供 IDE 提示使用） |

### 4.3 平行实现（tui_app_server）

| 文件路径 | 职责 |
|----------|------|
| `codex-rs/tui_app_server/src/notifications/mod.rs` | 与 tui 完全相同的实现 |
| `codex-rs/tui_app_server/src/notifications/osc9.rs` | OSC 9 实现（复制） |
| `codex-rs/tui_app_server/src/notifications/bel.rs` | BEL 实现（复制） |

### 4.4 关键代码路径流程

```
1. 配置加载
   core/src/config/mod.rs:2794-2803
   → 读取 [tui] notifications 和 notification_method

2. 初始化设置
   tui/src/app.rs:2004
   → tui.set_notification_method(config.tui_notification_method)

3. 事件触发
   tui/src/chatwidget.rs:1784,1862,3299,3331,3340,3379
   → self.notify(Notification::XXX)

4. 通知处理
   tui/src/chatwidget.rs:5612-5623
   → 检查 allowed_for → 优先级检查 → 设置 pending_notification

5. 发送时机
   tui/src/app.rs:2413
   → chat_widget.maybe_post_pending_notification(tui)

6. 实际发送
   tui/src/tui.rs:362-385
   → 检查焦点状态 → backend.notify(message)

7. 协议输出
   tui/src/notifications/osc9.rs:23
   → write!(f, "\x1b]9;{}\x07", self.0)
   
   tui/src/notifications/bel.rs:23
   → write!(f, "\x07")
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

```
notifications/
├── 依赖 codex_core::config::types::NotificationMethod
├── 依赖 crossterm::Command（终端控制）
├── 依赖 ratatui::crossterm::execute（终端执行）
└── 被依赖 tui/src/tui.rs
    └── 被依赖 tui/src/chatwidget.rs
        └── 被依赖 tui/src/app.rs
```

### 5.2 外部依赖（Cargo.toml）

```toml
[dependencies]
crossterm = { workspace = true, features = ["bracketed-paste", "event-stream"] }
ratatui = { workspace = true, ... }
codex-core = { workspace = true }
```

### 5.3 环境变量依赖

| 环境变量 | 用途 |
|----------|------|
| `WT_SESSION` | Windows Terminal 检测（禁用 OSC 9） |
| `TERM_PROGRAM` | 终端模拟器类型检测 |
| `ITERM_SESSION_ID` | iTerm2 检测 |
| `TERM` | 终端类型检测（kitty/wezterm） |

### 5.4 配置项（config.toml）

```toml
[tui]
# 启用/禁用通知，或指定允许的通知类型列表
notifications = true                    # 布尔值：启用所有
notifications = false                   # 布尔值：禁用所有
notifications = ["agent-turn-complete", "approval-requested"]  # 数组：仅指定类型

# 通知协议方法
notification_method = "auto"            # 自动检测（默认）
notification_method = "osc9"            # 强制使用 OSC 9
notification_method = "bel"             # 强制使用 BEL
```

---

## 6. 风险、边界与改进建议

### 6.1 当前风险

#### 6.1.1 代码重复风险

**问题**：`tui` 和 `tui_app_server` 两个 crate 包含完全相同的 notifications 模块代码（3 个文件，共约 230 行）。

**风险**：
- 一处修复需要同步修改两处
- 容易遗漏同步，导致行为不一致
- 违反 DRY 原则

**证据**：
```bash
$ diff codex-rs/tui/src/notifications/mod.rs codex-rs/tui_app_server/src/notifications/mod.rs
# 无差异
```

#### 6.1.2 环境变量检测脆弱性

**问题**：`supports_osc9()` 依赖环境变量检测，可能在以下场景失效：
- 通过 SSH 连接到远程服务器后运行（环境变量可能丢失）
- 使用不常见的终端模拟器
- 在复杂的 tmux/screen 嵌套会话中

**当前缓解**：
- 使用 `Auto` 模式时，无法检测则回退到 BEL
- 用户可手动指定 `notification_method = "osc9"`

#### 6.1.3 通知失败静默处理

**问题**：通知发送失败后会禁用整个通知后端：

```rust
Err(err) => {
    self.notification_backend = None;  // 永久禁用
    false
}
```

**风险**：
- 用户可能不知道通知已停止工作
- 临时 IO 错误导致永久功能丧失
- 没有重试机制

#### 6.1.4 Windows 支持限制

**问题**：Windows 平台强制使用 ANSI 序列：

```rust
#[cfg(windows)]
fn execute_winapi(&self) -> io::Result<()> {
    Err(std::io::Error::other(
        "tried to execute PostNotification using WinAPI; use ANSI instead"
    ))
}
```

**风险**：
- 旧版 Windows 控制台可能不支持这些 ANSI 序列
- 没有使用 Windows 原生通知 API

### 6.2 边界条件

#### 6.2.1 消息长度限制

OSC 9 协议本身没有长度限制，但：
- 终端模拟器可能有 OSC 序列长度限制
- 当前实现没有截断逻辑（仅 `AgentTurnComplete` 预览截断到 200 字符）

#### 6.2.2 并发通知

- 通知是同步发送的（`io::Result`）
- 没有队列机制，高优先级通知直接覆盖低优先级
- 如果用户长时间不聚焦终端，可能丢失通知

#### 6.2.3 焦点检测限制

焦点状态依赖 crossterm 的 `EnableFocusChange`：
- 某些终端可能不支持焦点事件
- 远程 SSH 会话可能无法正确传递焦点事件

### 6.3 改进建议

#### 6.3.1 提取共享库（高优先级）

将 notifications 模块提取到独立 crate（如 `codex-notifications`）：

```
codex-rs/
├── notifications/          # 新 crate
│   ├── src/
│   │   ├── lib.rs
│   │   ├── osc9.rs
│   │   └── bel.rs
│   └── Cargo.toml
├── tui/Cargo.toml        # 依赖 codex-notifications
└── tui_app_server/Cargo.toml  # 依赖 codex-notifications
```

**收益**：
- 消除代码重复
- 便于统一测试
- 降低维护成本

#### 6.3.2 添加通知失败重试

```rust
pub fn notify(&mut self, message: impl AsRef<str>) -> bool {
    // ... 现有检查 ...
    
    match backend.notify(&message) {
        Ok(()) => {
            self.notify_failures = 0;  // 重置失败计数
            true
        }
        Err(err) => {
            self.notify_failures += 1;
            if self.notify_failures >= MAX_NOTIFY_FAILURES {
                tracing::error!("通知连续失败 {} 次，禁用通知功能", MAX_NOTIFY_FAILURES);
                self.notification_backend = None;
            }
            false
        }
    }
}
```

#### 6.3.3 增强终端检测

添加更多检测机制：

```rust
fn supports_osc9() -> bool {
    // 现有检测...
    
    // 新增：检测 kitty 的特定环境变量
    if env::var_os("KITTY_WINDOW_ID").is_some() { return true; }
    
    // 新增：检测 alacritty（通过版本变量）
    if env::var_os("ALACRITTY_SOCKET").is_some() { return true; }
    
    // 新增：检测 foot 终端
    if env::var("TERM").ok().as_deref() == Some("foot") { return true; }
    
    // ...
}
```

#### 6.3.4 添加通知队列

```rust
pub struct Tui {
    notification_queue: VecDeque<String>,
    max_queued_notifications: usize,  // 例如 10
}

impl Tui {
    pub fn notify(&mut self, message: impl AsRef<str>) -> bool {
        if self.terminal_focused.load(Ordering::Relaxed) {
            return false;
        }
        
        // 如果后端忙或失败，加入队列
        if self.notification_backend.is_none() {
            if self.notification_queue.len() < self.max_queued_notifications {
                self.notification_queue.push_back(message.as_ref().to_string());
            }
            return false;
        }
        
        // 尝试发送队列中的通知 + 新通知
        // ...
    }
}
```

#### 6.3.5 支持更多通知协议

考虑添加对以下协议的支持：
- **OSC 777**：kitty 桌面通知协议（更现代）
- **D-Bus**：Linux 原生桌面通知
- **AppleScript**：macOS 原生通知（当不在终端内时）

```rust
pub enum DesktopNotificationBackend {
    Osc9(Osc9Backend),
    Osc777(Osc777Backend),  // 新增
    Bel(BelBackend),
    #[cfg(target_os = "linux")]
    Dbus(DbusBackend),      // 新增
}
```

#### 6.3.6 添加通知统计和调试

```rust
#[derive(Debug, Default)]
pub struct NotificationStats {
    pub sent_count: usize,
    pub suppressed_count: usize,  // 因焦点而抑制
    pub failed_count: usize,
    pub filtered_count: usize,    // 因配置过滤
}

impl Tui {
    pub fn notification_stats(&self) -> &NotificationStats;
}
```

### 6.4 测试覆盖

当前测试（`mod tests`）：
- ✅ 后端选择逻辑（Osc9/Bel/Auto）
- ✅ 环境变量检测（iTerm2、无 hint 场景）
- ⚠️ 缺少：实际 OSC 序列输出验证
- ⚠️ 缺少：焦点状态变化集成测试
- ⚠️ 缺少：配置过滤逻辑测试（在 chatwidget/tests.rs 中）

建议添加：
```rust
#[test]
fn test_osc9_sequence_format() {
    let backend = Osc9Backend;
    // 验证输出序列格式
}

#[test]
fn test_notification_priority_ordering() {
    // 验证优先级逻辑
}
```

---

## 7. 总结

`codex-rs/tui/src/notifications` 模块是一个**功能完整但相对简单**的桌面通知子系统。它通过 OSC 9 和 BEL 两种协议实现了在终端失去焦点时向用户发送通知的核心功能。

**优势**：
- 自动检测终端能力，提供最佳用户体验
- 与配置系统深度集成，用户可精细控制
- 优先级系统确保重要通知不被遗漏
- 代码结构清晰，易于理解

**主要问题**：
- 与 `tui_app_server` 的代码重复需要解决
- 通知失败处理过于激进（永久禁用）
- 缺乏对更多现代通知协议的支持

**维护建议**：
1. 短期：保持现状，注意同步修改两个 crate 的通知代码
2. 中期：提取共享库，消除代码重复
3. 长期：考虑添加原生桌面通知支持（D-Bus、AppleScript 等）
