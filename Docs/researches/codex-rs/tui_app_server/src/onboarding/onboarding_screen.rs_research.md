# onboarding_screen.rs 研究文档

## 场景与职责

`onboarding_screen.rs` 是 Codex TUI 的**新手引导流程协调器**，负责管理和协调用户在首次使用时的多步骤引导体验。它是 onboarding 模块的核心协调组件，整合多个子步骤（Welcome、Auth、Trust Directory）形成一个连贯的用户流程。

### 核心职责

1. **步骤生命周期管理**：创建、协调和销毁 onboarding 的各个步骤
2. **事件路由**：将键盘事件、粘贴事件、App Server 通知路由到正确的步骤
3. **状态流转控制**：根据各步骤的完成状态决定流程走向
4. **渲染协调**：动态计算和渲染当前活跃的步骤

### 使用场景

- 用户首次运行 Codex CLI 且未登录时
- 用户首次在特定目录运行且需要信任决策时
- 用户通过 `--resume` 或 `--fork` 恢复会话前的配置确认

## 功能点目的

### 1. 多步骤流程管理

Onboarding 包含三个可选步骤：

```
┌─────────────┐    ┌─────────────┐    ┌─────────────────┐
│   Welcome   │ → │    Auth     │ → │ Trust Directory │
│  (欢迎页)    │    │  (登录认证)  │    │  (目录信任决策) │
└─────────────┘    └─────────────┘    └─────────────────┘
      ↓                  ↓                    ↓
   已登录时           需要 OpenAI            远程模式或
   自动跳过           认证时显示             已决策时跳过
```

### 2. 动态步骤状态

每个步骤有三种状态：
- `Hidden`：未开始/已跳过
- `InProgress`：当前活跃，接收用户输入
- `Complete`：已完成，显示为摘要

### 3. 事件驱动架构

```rust
// 主事件循环
tokio::select! {
    event = tui_events.next() => {
        // 处理键盘、粘贴、绘制事件
    }
    event = app_server.next_event() => {
        // 处理服务器通知（如登录完成）
    }
}
```

### 4. 安全退出处理

- 认证过程中退出：直接退出应用（避免未认证状态）
- 信任决策时选择退出：设置 `should_exit` 标志

## 具体技术实现

### 关键数据结构

```rust
/// 步骤枚举，包含所有可能的 onboarding 步骤
#[allow(clippy::large_enum_variant)]
enum Step {
    Welcome(WelcomeWidget),
    Auth(AuthModeWidget),
    TrustDirectory(TrustDirectoryWidget),
}

/// 步骤状态，驱动 UI 显示和流程控制
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum StepState {
    Hidden,      // 未显示
    InProgress,  // 进行中
    Complete,    // 已完成
}

/// Onboarding 屏幕主结构
pub(crate) struct OnboardingScreen {
    request_frame: FrameRequester,     // 帧请求器
    steps: Vec<Step>,                  // 步骤列表
    is_done: bool,                     // 是否完成
    should_exit: bool,                 // 是否应该退出应用
}

/// 创建参数
pub(crate) struct OnboardingScreenArgs {
    pub show_trust_screen: bool,       // 是否显示信任屏幕
    pub show_login_screen: bool,       // 是否显示登录屏幕
    pub login_status: LoginStatus,     // 当前登录状态
    pub app_server_request_handle: Option<AppServerRequestHandle>,
    pub config: Config,                // 应用配置
}

/// 返回结果
pub(crate) struct OnboardingResult {
    pub directory_trust_decision: Option<TrustDirectorySelection>,
    pub should_exit: bool,
}
```

### 步骤创建逻辑

```rust
impl OnboardingScreen {
    pub(crate) fn new(tui: &mut Tui, args: OnboardingScreenArgs) -> Self {
        let mut steps: Vec<Step> = Vec::new();
        
        // 1. 添加欢迎步骤（始终添加，但已登录时状态为 Hidden）
        steps.push(Step::Welcome(WelcomeWidget::new(
            !matches!(login_status, LoginStatus::NotAuthenticated),
            tui.frame_requester(),
            config.animations,
        )));
        
        // 2. 条件添加登录步骤
        if show_login_screen {
            if let Some(app_server_request_handle) = app_server_request_handle {
                steps.push(Step::Auth(AuthModeWidget { ... }));
            }
        }
        
        // 3. 条件添加信任目录步骤
        if show_trust_screen {
            steps.push(Step::TrustDirectory(TrustDirectoryWidget { ... }));
        }
        
        // ...
    }
}
```

### 事件处理流程

#### 键盘事件处理

```rust
impl KeyboardHandler for OnboardingScreen {
    fn handle_key_event(&mut self, key_event: KeyEvent) {
        // 1. 检查退出快捷键（Ctrl+C, Ctrl+D, q）
        let should_quit = /* ... */;
        
        if should_quit {
            if self.is_auth_in_progress() {
                // 认证中退出 → 直接退出应用
                self.should_exit = true;
            }
            self.is_done = true;
        } else {
            // 2. 欢迎步骤特殊处理（任何键都可继续）
            if let Some(Step::Welcome(widget)) = /* ... */ {
                widget.handle_key_event(key_event);
            }
            
            // 3. 转发到当前活跃步骤
            if let Some(active_step) = self.current_steps_mut().into_iter().last() {
                active_step.handle_key_event(key_event);
            }
            
            // 4. 检查信任步骤是否请求退出
            if /* TrustDirectoryWidget.should_quit() */ {
                self.should_exit = true;
                self.is_done = true;
            }
        }
        
        self.request_frame.schedule_frame();
    }
}
```

#### App Server 通知处理

```rust
fn handle_app_server_notification(&mut self, notification: ServerNotification) {
    match notification {
        ServerNotification::AccountLoginCompleted(notification) => {
            if let Some(widget) = self.auth_widget_mut() {
                widget.on_account_login_completed(notification);
            }
        }
        ServerNotification::AccountUpdated(notification) => {
            if let Some(widget) = self.auth_widget_mut() {
                widget.on_account_updated(notification);
            }
        }
        _ => {}
    }
}
```

### 动态渲染系统

```rust
impl WidgetRef for &OnboardingScreen {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        Clear.render(area, buf);  // 清空区域
        
        let mut y = area.y;
        let current_steps = self.current_steps();
        
        for step in current_steps {
            // 1. 创建临时缓冲区计算实际高度
            let scratch_area = Rect::new(0, 0, width, max_h);
            let mut scratch = Buffer::empty(scratch_area);
            
            // 2. 渲染到临时缓冲区
            step.render_ref(scratch_area, &mut scratch);
            
            // 3. 计算实际使用的高度
            let h = used_rows(&scratch, width, max_h).min(max_h);
            
            // 4. 渲染到实际缓冲区
            if h > 0 {
                let target = Rect { x: area.x, y, width, height: h };
                Clear.render(target, buf);
                step.render_ref(target, buf);
                y += h;
            }
        }
    }
}
```

### 主事件循环

```rust
pub(crate) async fn run_onboarding_app(
    args: OnboardingScreenArgs,
    mut app_server: Option<AppServerSession>,
    tui: &mut Tui,
) -> Result<OnboardingResult> {
    let mut onboarding_screen = OnboardingScreen::new(tui, args);
    let mut did_full_clear_after_success = false;
    
    // 初始绘制
    tui.draw(u16::MAX, |frame| {
        frame.render_widget_ref(&onboarding_screen, frame.area());
    })?;
    
    let tui_events = tui.event_stream();
    tokio::pin!(tui_events);
    
    while !onboarding_screen.is_done() {
        tokio::select! {
            // 处理 TUI 事件（键盘、粘贴、绘制）
            event = tui_events.next() => {
                match event {
                    TuiEvent::Key(key_event) => onboarding_screen.handle_key_event(key_event),
                    TuiEvent::Paste(text) => onboarding_screen.handle_paste(text),
                    TuiEvent::Draw => {
                        // 特殊处理：登录成功后清除屏幕（防止样式残留）
                        if !did_full_clear_after_success && is_chatgpt_success_message() {
                            reset_terminal_styles();
                            tui.terminal.clear()?;
                            did_full_clear_after_success = true;
                        }
                        tui.draw(u16::MAX, |frame| {
                            frame.render_widget_ref(&onboarding_screen, frame.area());
                        });
                    }
                }
            }
            // 处理 App Server 事件
            event = async { app_server.as_mut()?.next_event().await }, if app_server.is_some() => {
                match event {
                    AppServerEvent::ServerNotification(notification) => {
                        onboarding_screen.handle_app_server_notification(notification);
                    }
                    AppServerEvent::Disconnected { message } => {
                        return Err(color_eyre::eyre::eyre!(message));
                    }
                    // 忽略其他事件类型
                    _ => {}
                }
            }
        }
    }
    
    // 清理
    if let Some(app_server) = app_server {
        app_server.shutdown().await.ok();
    }
    
    Ok(OnboardingResult {
        directory_trust_decision: onboarding_screen.directory_trust_decision(),
        should_exit: onboarding_screen.should_exit(),
    })
}
```

## 关键代码路径与文件引用

### 内部依赖

| 文件 | 用途 |
|------|------|
| `auth.rs` | `AuthModeWidget` - 认证步骤实现 |
| `trust_directory.rs` | `TrustDirectoryWidget` - 信任决策步骤 |
| `welcome.rs` | `WelcomeWidget` - 欢迎步骤 |
| `../tui.rs` | `Tui`, `FrameRequester`, `TuiEvent` - TUI 基础设施 |
| `../app_server_session.rs` | `AppServerSession` - App Server 会话管理 |

### Trait 定义

```rust
// 键盘事件处理 trait
pub(crate) trait KeyboardHandler {
    fn handle_key_event(&mut self, key_event: KeyEvent);
    fn handle_paste(&mut self, _pasted: String) {}
}

// 步骤状态提供 trait
pub(crate) trait StepStateProvider {
    fn get_step_state(&self) -> StepState;
}
```

### 外部协议类型

| 类型 | 来源 | 用途 |
|------|------|------|
| `ServerNotification` | `codex_app_server_protocol` | 服务器推送通知 |
| `AccountLoginCompletedNotification` | `codex_app_server_protocol` | 登录完成通知 |
| `AccountUpdatedNotification` | `codex_app_server_protocol` | 账号更新通知 |
| `ForcedLoginMethod` | `codex_protocol::config_types` | 强制登录方法配置 |

## 依赖与外部交互

### 与 lib.rs 的交互

```rust
// lib.rs 中的调用点
let onboarding_result = run_onboarding_app(
    OnboardingScreenArgs {
        show_login_screen,
        show_trust_screen: should_show_trust_screen_flag,
        login_status,
        app_server_request_handle: onboarding_app_server.as_ref().map(...),
        config: initial_config.clone(),
    },
    if show_login_screen { onboarding_app_server.take() } else { None },
    &mut tui,
).await?;

// 处理结果
if onboarding_result.should_exit {
    // 用户选择退出
    return Ok(AppExitInfo { ... });
}

trust_decision_was_made = onboarding_result.directory_trust_decision.is_some();
```

### 与 App Server 的交互

通过 `AppServerSession` 接收异步通知：
- `AccountLoginCompletedNotification`：OAuth 登录完成
- `AccountUpdatedNotification`：账号状态更新

### 配置依赖

从 `Config` 读取：
- `forced_login_method`：强制登录方式
- `forced_chatgpt_workspace_id`：强制工作区
- `animations`：动画开关
- `cwd`：当前工作目录
- `codex_home`：Codex 主目录
- `cli_auth_credentials_store_mode`：凭证存储模式

## 风险、边界与改进建议

### 风险分析

1. **状态不一致风险**（中等）
   - 问题：`current_steps()` 和 `current_steps_mut()` 使用动态计算，可能在并发场景下不一致
   - 缓解：目前使用单线程事件循环，无并发问题
   - 建议：考虑缓存步骤状态，避免重复计算

2. **内存泄漏风险**（低）
   - 问题：`OnboardingScreen` 持有 `AppServerSession`，需要确保正确关闭
   - 缓解：`run_onboarding_app` 函数在返回前调用 `app_server.shutdown()`

3. **渲染闪烁风险**（低）
   - 问题：动态高度计算使用临时缓冲区，可能导致闪烁
   - 缓解：使用 `Clear` widget 在渲染前清除区域

### 边界情况

1. **空步骤列表**
   - 如果 `show_login_screen` 和 `show_trust_screen` 都为 false，且欢迎步骤自动完成
   - `is_done()` 会立即返回 true，onboarding 快速跳过

2. **App Server 断开**
   - 在 `tokio::select!` 中处理 `AppServerEvent::Disconnected`
   - 立即返回错误，中断 onboarding

3. **窗口大小变化**
   - 每次 `TuiEvent::Draw` 重新计算布局
   - 动态高度计算适应新窗口大小

4. **ChatGPT 登录成功后的样式残留**
   - 特殊处理：检测 `ChatGptSuccessMessage` 状态
   - 重置 SGR 属性并执行 `terminal.clear()`

### 改进建议

1. **代码结构优化**
   - 文件长度 521 行，处于合理范围
   - 可考虑将 `run_onboarding_app` 函数提取到单独文件（如 `onboarding_runner.rs`）

2. **错误处理增强**
   ```rust
   // 当前：App Server 断开直接返回错误
   AppServerEvent::Disconnected { message } => {
       return Err(color_eyre::eyre::eyre!(message));
   }
   
   // 建议：添加重试逻辑或优雅降级
   AppServerEvent::Disconnected { message } => {
       if retry_count < MAX_RETRIES {
           // 尝试重连
       } else {
           // 显示错误并允许用户选择退出或重试
       }
   }
   ```

3. **可访问性改进**
   - 添加屏幕阅读器支持（ANSI 转义序列）
   - 为视觉障碍用户提供纯文本模式

4. **测试覆盖**
   - 当前测试：基本的状态转换测试
   - 建议添加：
     - 事件路由测试
     - 渲染输出快照测试（使用 `insta`）
     - 超时处理测试

5. **性能优化**
   ```rust
   // 当前：每次绘制都重新计算 current_steps
   let current_steps = self.current_steps();
   
   // 建议：缓存步骤状态，只在状态变化时重新计算
   struct OnboardingScreen {
       cached_current_steps: Vec<Step>,
       steps_version: u64,  // 步骤列表变更时递增
   }
   ```

### 已知限制

1. **Windows 沙盒提示**：`show_windows_create_sandbox_hint` 只在 Windows 平台且沙盒禁用时显示，但这与信任决策无直接关系，位置略显突兀。

2. **步骤顺序固定**：当前步骤顺序硬编码为 Welcome → Auth → Trust，不支持配置化重排。

3. **异步事件顺序**：如果用户在登录完成前快速按键，事件处理顺序可能导致状态不一致（虽然概率极低）。
