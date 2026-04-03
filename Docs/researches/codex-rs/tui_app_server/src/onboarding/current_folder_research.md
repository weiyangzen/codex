# Codex TUI App Server - Onboarding Module Research

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 模块定位

`codex-rs/tui_app_server/src/onboarding` 是 Codex TUI 应用的**用户引导模块**，负责处理用户首次使用或需要重新认证时的引导流程。该模块在应用启动时根据配置和认证状态决定是否显示引导界面。

### 核心职责

1. **欢迎展示**：显示 ASCII 动画欢迎界面，提升用户体验
2. **身份认证**：提供多种登录方式（ChatGPT 账号、设备码、API Key）
3. **目录信任确认**：询问用户是否信任当前工作目录，防范提示注入攻击
4. **状态管理**：管理引导流程的状态机，协调各步骤的切换

### 触发条件

根据 `lib.rs` 中的逻辑，引导流程在以下情况下触发：

```rust
// lib.rs:960-989
let should_show_trust_screen_flag = !remote_mode && should_show_trust_screen(&initial_config);
let needs_onboarding_app_server =
    should_show_trust_screen_flag || initial_config.model_provider.requires_openai_auth;

// 引导显示条件
fn should_show_onboarding(login_status: LoginStatus, config: &Config, show_trust_screen: bool) -> bool {
    if show_trust_screen { return true; }
    should_show_login_screen(login_status, config)
}

fn should_show_login_screen(login_status: LoginStatus, config: &Config) -> bool {
    if !config.model_provider.requires_openai_auth { return false; }
    login_status == LoginStatus::NotAuthenticated
}
```

---

## 功能点目的

### 1. 欢迎界面 (Welcome Widget)

**目的**：在用户未登录时展示品牌欢迎信息，通过 ASCII 动画提升视觉体验。

**功能特性**：
- 显示动态 ASCII 艺术动画（10 种变体）
- 支持 `Ctrl+.` 切换动画变体
- 根据终端尺寸自动适配（最小 60x37 字符）
- 已登录用户跳过此步骤

**文件位置**：`welcome.rs`

### 2. 身份认证 (Auth Widget)

**目的**：提供安全、灵活的用户认证机制，支持多种登录方式。

**支持的登录方式**：

| 方式 | 说明 | 适用场景 |
|------|------|----------|
| ChatGPT 登录 | 通过浏览器 OAuth 流程 | 有 ChatGPT 付费计划的用户 |
| 设备码登录 | 在无浏览器环境使用一次性设备码 | 远程/无头服务器 |
| API Key | 使用 OpenAI API Key | 偏好按量计费的用户 |

**安全特性**：
- 强制登录方法配置（`forced_login_method`）可限制可用选项
- API Key 支持从环境变量 `OPENAI_API_KEY` 预填充
- 支持取消正在进行的登录流程
- URL 使用 OSC 8 超链接协议，防止终端转义注入

**文件位置**：`auth.rs`, `auth/headless_chatgpt_login.rs`

### 3. 目录信任确认 (Trust Directory)

**目的**：防范提示注入攻击，让用户明确确认是否信任当前工作目录的内容。

**工作流程**：
1. 检测当前目录的信任级别（通过 `config.active_project.trust_level`）
2. 如果未设置信任级别，显示信任确认界面
3. 用户选择"信任"后，将项目标记为可信
4. 用户选择"退出"则终止应用

**安全提示**：
- 明确警告"处理不受信任的内容会带来更高的提示注入风险"
- 支持 Windows 沙箱创建提示

**文件位置**：`trust_directory.rs`

---

## 具体技术实现

### 架构设计

```
┌─────────────────────────────────────────────────────────────┐
│                    OnboardingScreen                         │
│                    (引导流程 orchestrator)                   │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   Welcome   │  │    Auth     │  │   TrustDirectory    │  │
│  │   Widget    │  │   Widget    │  │      Widget         │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 核心数据结构

#### StepState - 步骤状态枚举

```rust
// onboarding_screen.rs:48-53
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum StepState {
    Hidden,      // 隐藏（如已登录时跳过欢迎）
    InProgress,  // 进行中
    Complete,    // 已完成
}
```

#### SignInState - 登录状态机

```rust
// auth.rs:87-97
pub(crate) enum SignInState {
    PickMode,                           // 选择登录方式
    ChatGptContinueInBrowser(ContinueInBrowserState),  // 浏览器登录中
    ChatGptDeviceCode(ContinueWithDeviceCodeState),    // 设备码登录中
    ChatGptSuccessMessage,              // 登录成功提示
    ChatGptSuccess,                     // 登录完成
    ApiKeyEntry(ApiKeyInputState),      // API Key 输入
    ApiKeyConfigured,                   // API Key 已配置
}
```

#### TrustDirectorySelection - 信任选择

```rust
// trust_directory.rs:37-41
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TrustDirectorySelection {
    Trust,  // 信任此目录
    Quit,   // 退出应用
}
```

### 关键流程

#### 1. 引导流程初始化

```rust
// onboarding_screen.rs:79-146
impl OnboardingScreen {
    pub(crate) fn new(tui: &mut Tui, args: OnboardingScreenArgs) -> Self {
        // 1. 创建步骤列表
        let mut steps: Vec<Step> = Vec::new();
        
        // 2. 添加欢迎步骤（未登录时显示）
        steps.push(Step::Welcome(WelcomeWidget::new(...)));
        
        // 3. 添加认证步骤（需要登录且未认证时）
        if show_login_screen {
            steps.push(Step::Auth(AuthModeWidget { ... }));
        }
        
        // 4. 添加信任目录步骤（需要时）
        if show_trust_screen {
            steps.push(Step::TrustDirectory(TrustDirectoryWidget { ... }));
        }
        
        Self { steps, ... }
    }
}
```

#### 2. 事件处理循环

```rust
// onboarding_screen.rs:425-521
pub(crate) async fn run_onboarding_app(...) -> Result<OnboardingResult> {
    let mut onboarding_screen = OnboardingScreen::new(tui, args);
    
    while !onboarding_screen.is_done() {
        tokio::select! {
            // 处理 TUI 事件（键盘、粘贴、绘制）
            event = tui_events.next() => { ... }
            
            // 处理 AppServer 通知（登录完成、账户更新）
            event = app_server.next_event() => { ... }
        }
    }
    
    Ok(OnboardingResult { ... })
}
```

#### 3. 设备码登录流程

```rust
// auth/headless_chatgpt_login.rs:34-122
pub(super) fn start_headless_chatgpt_login(widget: &mut AuthModeWidget) {
    // 1. 创建设备码请求选项
    let mut opts = ServerOptions::new(...);
    opts.open_browser = false;  // 不自动打开浏览器
    
    tokio::spawn(async move {
        // 2. 请求设备码
        let device_code = match request_device_code(&opts).await {
            Ok(code) => code,
            Err(err) => {
                // 3. 失败时回退到浏览器登录
                fallback_to_browser_login(...).await;
                return;
            }
        };
        
        // 4. 等待用户完成设备码授权或取消
        tokio::select! {
            _ = cancel.notified() => {}  // 用户取消
            result = complete_device_code_login(opts, device_code) => {
                // 5. 处理登录结果
                handle_chatgpt_auth_tokens_login_result_for_active_attempt(...).await;
            }
        }
    });
}
```

### 渲染系统

#### 动态高度计算

```rust
// onboarding_screen.rs:315-378
impl WidgetRef for &OnboardingScreen {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        // 使用临时缓冲区测量每个步骤的实际高度
        let scratch = Buffer::empty(scratch_area);
        step.render_ref(scratch_area, &mut scratch);
        let h = used_rows(&scratch, width, max_h).min(max_h);
        
        // 按顺序渲染各步骤，动态分配高度
        for step in current_steps {
            step.render_ref(target, buf);
        }
    }
}
```

#### URL 超链接安全处理

```rust
// auth.rs:53-79
pub(crate) fn mark_url_hyperlink(buf: &mut Buffer, area: Rect, url: &str) {
    // 1. 清理 URL，防止 OSC 8 转义序列注入
    let safe_url: String = url
        .chars()
        .filter(|&c| c != '\x1B' && c != '\x07')
        .collect();
    
    // 2. 仅标记 cyan+underlined 样式的单元格
    for y in area.top()..area.bottom() {
        for x in area.left()..area.right() {
            let cell = &mut buf[(x, y)];
            if cell.fg != Color::Cyan || !cell.modifier.contains(Modifier::UNDERLINED) {
                continue;
            }
            // 3. 包装为 OSC 8 超链接
            cell.set_symbol(&format!("\x1B]8;;{safe_url}\x07{sym}\x1B]8;;\x07"));
        }
    }
}
```

---

## 关键代码路径与文件引用

### 模块结构

```
codex-rs/tui_app_server/src/onboarding/
├── mod.rs                          # 模块入口，导出公共接口
├── onboarding_screen.rs            # 引导流程主控制器（521 行）
├── welcome.rs                      # 欢迎界面组件（170 行）
├── auth.rs                         # 身份认证组件（1087 行）
├── auth/
│   └── headless_chatgpt_login.rs   # 设备码登录实现（546 行）
├── trust_directory.rs              # 目录信任确认组件（224 行）
└── snapshots/                      # 快照测试文件
    └── codex_tui_app_server__onboarding__trust_directory__tests__*.snap
```

### 关键文件详解

#### 1. `mod.rs`

**职责**：模块组织与公共接口导出

```rust
mod auth;
pub mod onboarding_screen;
mod trust_directory;
pub use trust_directory::TrustDirectorySelection;
mod welcome;
```

#### 2. `onboarding_screen.rs`

**核心组件**：
- `OnboardingScreen`：引导流程主控制器
- `Step` 枚举：引导步骤封装（Welcome/Auth/TrustDirectory）
- `KeyboardHandler` trait：键盘事件处理接口
- `StepStateProvider` trait：步骤状态查询接口
- `run_onboarding_app`：引导流程主循环

**关键类型**：
```rust
pub(crate) struct OnboardingScreenArgs {
    pub show_trust_screen: bool,
    pub show_login_screen: bool,
    pub login_status: LoginStatus,
    pub app_server_request_handle: Option<AppServerRequestHandle>,
    pub config: Config,
}

pub(crate) struct OnboardingResult {
    pub directory_trust_decision: Option<TrustDirectorySelection>,
    pub should_exit: bool,
}
```

#### 3. `auth.rs`

**核心组件**：
- `AuthModeWidget`：认证界面组件
- `SignInState`：登录状态机
- `SignInOption`：登录选项枚举
- `mark_url_hyperlink`：OSC 8 超链接安全渲染

**登录方式处理**：
```rust
fn handle_sign_in_option(&mut self, option: SignInOption) {
    match option {
        SignInOption::ChatGpt => self.start_chatgpt_login(),
        SignInOption::DeviceCode => self.start_device_code_login(),
        SignInOption::ApiKey => self.start_api_key_entry(),
    }
}
```

#### 4. `auth/headless_chatgpt_login.rs`

**核心功能**：
- `start_headless_chatgpt_login`：启动设备码登录流程
- `render_device_code_login`：渲染设备码登录界面
- 设备码状态管理函数组：
  - `begin_device_code_attempt`
  - `set_device_code_state_for_active_attempt`
  - `set_device_code_success_message_for_active_attempt`
  - `set_device_code_error_for_active_attempt`

#### 5. `trust_directory.rs`

**核心组件**：
- `TrustDirectoryWidget`：信任确认界面
- `TrustDirectorySelection`：用户选择枚举

**信任设置逻辑**：
```rust
fn handle_trust(&mut self) {
    let target = resolve_root_git_project_for_trust(&self.cwd)
        .unwrap_or_else(|| self.cwd.clone());
    if let Err(e) = set_project_trust_level(&self.codex_home, &target, TrustLevel::Trusted) {
        tracing::error!("Failed to set project trusted: {e:?}");
        self.error = Some(format!("Failed to set trust for {}: {e}", target.display()));
    }
    self.selection = Some(TrustDirectorySelection::Trust);
}
```

#### 6. `welcome.rs`

**核心组件**：
- `WelcomeWidget`：欢迎界面组件
- ASCII 动画集成（通过 `AsciiAnimation`）

**动画变体切换**：
```rust
fn handle_key_event(&mut self, key_event: KeyEvent) {
    if key_event.kind == KeyEventKind::Press
        && key_event.code == KeyCode::Char('.')
        && key_event.modifiers.contains(KeyModifiers::CONTROL)
    {
        let _ = self.animation.pick_random_variant();
    }
}
```

### 依赖文件

| 文件 | 用途 |
|------|------|
| `../lib.rs` | 引导流程调用入口（`run_onboarding_app`） |
| `../tui.rs` | TUI 基础设施（`Tui`, `FrameRequester`） |
| `../tui/frame_requester.rs` | 帧调度系统 |
| `../ascii_animation.rs` | ASCII 动画驱动 |
| `../frames.rs` | ASCII 动画帧数据 |
| `../shimmer.rs` | 闪光文字效果 |
| `../local_chatgpt_auth.rs` | 本地 ChatGPT 认证加载 |
| `../app_server_session.rs` | AppServer 会话管理 |
| `../selection_list.rs` | 选择列表渲染辅助 |
| `../render/` | 渲染辅助工具 |

---

## 依赖与外部交互

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `ratatui` | TUI 渲染框架 |
| `crossterm` | 跨平台终端控制（键盘、光标、颜色） |
| `tokio` | 异步运行时 |
| `codex_app_server_protocol` | AppServer 通信协议 |
| `codex_app_server_client` | AppServer 客户端 |
| `codex_core` | 核心功能（配置、认证、Git） |
| `codex_login` | 登录流程实现 |
| `codex_protocol` | 协议类型定义 |

### AppServer 协议交互

#### 登录相关请求

```rust
// 开始 ChatGPT 登录
ClientRequest::LoginAccount {
    params: LoginAccountParams::Chatgpt,
}

// 使用 API Key 登录
ClientRequest::LoginAccount {
    params: LoginAccountParams::ApiKey { api_key },
}

// 使用设备码 Token 登录
ClientRequest::LoginAccount {
    params: LoginAccountParams::ChatgptAuthTokens { access_token, chatgpt_account_id, chatgpt_plan_type },
}

// 取消登录
ClientRequest::CancelLoginAccount {
    params: CancelLoginAccountParams { login_id },
}
```

#### 服务器通知处理

```rust
// onboarding_screen.rs:216-230
fn handle_app_server_notification(&mut self, notification: ServerNotification) {
    match notification {
        ServerNotification::AccountLoginCompleted(notification) => {
            widget.on_account_login_completed(notification);
        }
        ServerNotification::AccountUpdated(notification) => {
            widget.on_account_updated(notification);
        }
        _ => {}
    }
}
```

### 核心模块交互

```
┌────────────────────────────────────────────────────────────────┐
│                     tui_app_server                               │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    onboarding                             │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐  │  │
│  │  │   welcome   │  │    auth     │  │ trust_directory │  │  │
│  │  └──────┬──────┘  └──────┬──────┘  └────────┬────────┘  │  │
│  │         │                │                   │          │  │
│  │         └────────────────┴───────────────────┘          │  │
│  │                          │                              │  │
│  │                    onboarding_screen                     │  │
│  └──────────────────────────┬──────────────────────────────┘  │
│                             │                                  │
│  ┌──────────────────────────┼──────────────────────────────┐  │
│  │                          ▼                              │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐  │  │
│  │  │     tui     │  │app_server_  │  │  local_chatgpt  │  │  │
│  │  │             │  │   session   │  │     _auth       │  │  │
│  │  └─────────────┘  └─────────────┘  └─────────────────┘  │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│                     codex_core                                   │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │   config    │  │    auth     │  │        git_info         │  │
│  │             │  │             │  │  (resolve_root_git_     │  │
│  │             │  │             │  │   project_for_trust)    │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
└────────────────────────────────────────────────────────────────┘
```

---

## 风险、边界与改进建议

### 已知风险

#### 1. 并发状态竞争

**风险**：设备码登录使用 `Arc<RwLock<SignInState>>` 共享状态，在快速切换登录方式时可能出现状态竞争。

**缓解措施**：
```rust
// headless_chatgpt_login.rs:192-201
fn device_code_attempt_matches(state: &SignInState, cancel: &Arc<Notify>) -> bool {
    matches!(
        state,
        SignInState::ChatGptDeviceCode(state)
            if state.cancel.as_ref().is_some_and(|existing| Arc::ptr_eq(existing, cancel))
    )
}
```

#### 2. URL 注入攻击

**风险**：恶意 URL 可能包含 OSC 序列终止字符（ESC、BEL）。

**缓解措施**：`mark_url_hyperlink` 函数会过滤掉 `\x1B` 和 `\x07` 字符。

#### 3. 终端尺寸适配

**边界**：欢迎动画需要最小 60x37 字符的终端尺寸，否则自动隐藏。

```rust
// welcome.rs:23-24
const MIN_ANIMATION_HEIGHT: u16 = 37;
const MIN_ANIMATION_WIDTH: u16 = 60;
```

### 测试覆盖

#### 单元测试

| 文件 | 测试项 |
|------|--------|
| `auth.rs` | API Key 流禁用测试、OSC 8 超链接渲染测试、URL 清理测试 |
| `trust_directory.rs` | 按键释放事件测试、快照测试 |
| `welcome.rs` | 动画渲染测试、尺寸断点测试、Ctrl+. 变体切换测试 |
| `headless_chatgpt_login.rs` | 设备码状态匹配测试、状态更新测试 |

#### 快照测试

```rust
// trust_directory.rs:204-223
#[test]
fn renders_snapshot_for_git_repo() {
    let widget = TrustDirectoryWidget { ... };
    let mut terminal = Terminal::new(VT100Backend::new(70, 14)).expect("terminal");
    terminal.draw(|f| (&widget).render_ref(f.area(), f.buffer_mut())).expect("draw");
    insta::assert_snapshot!(terminal.backend());
}
```

### 改进建议

#### 1. 状态管理优化

当前使用 `Arc<RwLock<T>>` 模式，可考虑使用更正式的状态机框架（如 `machine` crate）来减少手动状态检查。

#### 2. 错误处理增强

设备码登录的错误信息可以更加用户友好，区分网络错误、超时、用户取消等不同场景。

#### 3. 可访问性改进

- 为 ASCII 动画提供静态替代文本
- 增加屏幕阅读器支持（通过终端标题更新）

#### 4. 国际化准备

当前所有文本都是硬编码的英文，建议：
- 提取字符串到资源文件
- 支持从配置读取语言偏好

#### 5. 性能优化

```rust
// onboarding_screen.rs:324-347
// 当前每次渲染都创建临时缓冲区测量高度
let scratch = Buffer::empty(scratch_area);
step.render_ref(scratch_area, &mut scratch);
let h = used_rows(&scratch, width, max_h);

// 建议：缓存步骤高度，仅在尺寸变化时重新计算
```

### 配置项关联

| 配置项 | 影响 |
|--------|------|
| `model_provider.requires_openai_auth` | 决定是否显示登录界面 |
| `active_project.trust_level` | 决定是否显示信任确认 |
| `forced_login_method` | 限制可用登录选项 |
| `forced_chatgpt_workspace_id` | 强制特定工作空间 |
| `cli_auth_credentials_store_mode` | 控制凭据存储方式 |
| `animations` | 控制动画效果开关 |

---

## 总结

`onboarding` 模块是 Codex TUI 应用的入口体验模块，通过精心设计的引导流程平衡了安全性与易用性。模块采用清晰的分层架构：

1. **表现层**：`welcome.rs`, `auth.rs`, `trust_directory.rs` 负责具体 UI 渲染
2. **控制层**：`onboarding_screen.rs` 协调各步骤的状态流转
3. **服务层**：与 `AppServer` 和 `codex_core` 交互完成业务逻辑

关键设计亮点：
- 状态机模式管理复杂的登录流程
- OSC 8 超链接提升终端中的 URL 可点击性
- 动态高度计算适应不同终端尺寸
- 全面的测试覆盖（单元测试 + 快照测试）
