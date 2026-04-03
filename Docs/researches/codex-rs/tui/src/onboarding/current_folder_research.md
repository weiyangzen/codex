# Codex TUI Onboarding 模块研究文档

## 目录
- [场景与职责](#场景与职责)
- [功能点目的](#功能点目的)
- [具体技术实现](#具体技术实现)
- [关键代码路径与文件引用](#关键代码路径与文件引用)
- [依赖与外部交互](#依赖与外部交互)
- [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 整体定位

`onboarding` 模块是 Codex TUI（终端用户界面）的**用户引导系统**，负责处理用户首次使用或需要重新认证时的引导流程。它是用户与 Codex CLI 交互的**第一道门槛**，承担着以下核心职责：

1. **用户认证管理**：提供多种登录方式（ChatGPT 账号、设备码、API Key）
2. **目录信任确认**：询问用户是否信任当前工作目录，防范提示注入攻击
3. **欢迎体验**：通过 ASCII 动画和视觉反馈提供友好的首次使用体验
4. **配置初始化**：根据用户选择初始化认证状态和项目信任级别

### 触发场景

根据 `lib.rs` 中的逻辑，onboarding 在以下情况触发：

```rust
// lib.rs:633-637
let should_show_onboarding =
    should_show_onboarding(login_status, &initial_config, should_show_trust_screen_flag);
```

具体触发条件：
- **未认证状态**：用户未登录且模型提供商需要 OpenAI 认证
- **未信任目录**：当前项目的 `trust_level` 为 `None`（未设置）
- **首次使用**：新用户首次启动 Codex CLI

### 模块组成

```
codex-rs/tui/src/onboarding/
├── mod.rs                      # 模块入口，导出公共接口
├── onboarding_screen.rs        # 核心流程编排（Step 状态机）
├── welcome.rs                  # 欢迎页面（ASCII 动画）
├── auth.rs                     # 认证流程 UI（登录方式选择）
├── auth/
│   └── headless_chatgpt_login.rs  # 设备码登录（无浏览器场景）
├── trust_directory.rs          # 目录信任确认页面
└── snapshots/                  # 快照测试文件
    └── codex_tui__onboarding__trust_directory__tests__renders_snapshot_for_git_repo.snap
```

---

## 功能点目的

### 1. 欢迎页面（WelcomeWidget）

**目的**：在用户未登录时展示品牌欢迎信息，提供视觉吸引力。

**关键特性**：
- **ASCII 动画**：使用 `AsciiAnimation` 驱动多帧 ASCII 艺术动画
- **响应式布局**：当终端尺寸小于 `MIN_ANIMATION_HEIGHT(37)` 或 `MIN_ANIMATION_WIDTH(60)` 时自动隐藏动画
- **交互彩蛋**：支持 `Ctrl+.` 切换动画变体（10 种不同风格）

**状态行为**：
- 已登录用户：`StepState::Hidden`（跳过此步骤）
- 未登录用户：`StepState::Complete`（展示后自动完成）

### 2. 认证流程（AuthModeWidget）

**目的**：提供灵活的多渠道认证方式，适配不同用户场景。

**三种登录方式**：

| 方式 | 适用场景 | 技术实现 |
|------|----------|----------|
| **ChatGPT 登录** | 有浏览器环境的桌面用户 | OAuth2 PKCE 流程，本地回调服务器 |
| **设备码登录** | 无浏览器/远程 SSH 环境 | OAuth2 Device Code 流程，轮询 token 端点 |
| **API Key** | 企业/开发者，按量计费 | 直接输入 `sk-*` 密钥，本地存储到 `auth.json` |

**状态机设计**：

```rust
pub(crate) enum SignInState {
    PickMode,                           // 选择登录方式
    ChatGptContinueInBrowser(...),      // 等待浏览器回调
    ChatGptDeviceCode(...),             // 展示设备码
    ChatGptSuccessMessage,              // 登录成功提示（含安全须知）
    ChatGptSuccess,                     // 登录完成
    ApiKeyEntry(...),                   // API Key 输入
    ApiKeyConfigured,                   // API Key 配置完成
}
```

**安全特性**：
- **强制登录方式**：通过 `forced_login_method` 配置可禁用某些登录方式
- **环境变量检测**：自动检测 `OPENAI_API_KEY` 环境变量并预填充
- **URL 安全**：`mark_url_hyperlink` 函数过滤 ESC (`\x1B`) 和 BEL (`\x07`) 字符防止终端注入

### 3. 目录信任确认（TrustDirectoryWidget）

**目的**：防范提示注入攻击，让用户明确确认工作目录的可信度。

**安全背景**：
- 恶意仓库可能在代码中嵌入提示注入攻击（如隐藏指令）
- 用户需要明确选择"信任"或"退出"

**行为逻辑**：
- **信任**：调用 `set_project_trust_level(..., TrustLevel::Trusted)` 持久化到配置
- **退出**：设置 `should_quit = true`，应用退出

**Windows 特殊处理**：
- 当 Windows Sandbox 禁用时，显示额外提示"Press Enter to continue and create a sandbox..."

---

## 具体技术实现

### 1. Step 状态机架构

`OnboardingScreen` 使用**组合式步骤状态机**管理多阶段流程：

```rust
// onboarding_screen.rs:34-38
#[allow(clippy::large_enum_variant)]
enum Step {
    Welcome(WelcomeWidget),
    Auth(AuthModeWidget),
    TrustDirectory(TrustDirectoryWidget),
}
```

**StepState 生命周期**：

```rust
pub(crate) enum StepState {
    Hidden,      // 步骤隐藏（如已登录用户的欢迎页）
    InProgress,  // 当前进行中
    Complete,    // 已完成
}
```

**状态流转规则**：
- `current_steps()` / `current_steps_mut()` 只返回 `Hidden` 以外的步骤
- 遇到第一个 `InProgress` 步骤即停止，实现**顺序执行**
- 已完成的步骤仍保留在列表中用于渲染（展示历史）

### 2. 异步事件循环

```rust
// onboarding_screen.rs:395-462
pub(crate) async fn run_onboarding_app(
    args: OnboardingScreenArgs,
    tui: &mut Tui,
) -> Result<OnboardingResult> {
    // 1. 初始化 onboarding 屏幕
    let mut onboarding_screen = OnboardingScreen::new(tui, args);
    
    // 2. 获取 TUI 事件流（键盘、粘贴、绘制）
    let tui_events = tui.event_stream();
    tokio::pin!(tui_events);
    
    // 3. 事件循环
    while !onboarding_screen.is_done() {
        match event {
            TuiEvent::Key(key_event) => onboarding_screen.handle_key_event(key_event),
            TuiEvent::Paste(text) => onboarding_screen.handle_paste(text),
            TuiEvent::Draw => { /* 渲染逻辑 */ }
        }
    }
}
```

**特殊处理**：
- ChatGPT 登录成功后执行**全屏清除**，重置 SGR 属性防止样式残留

### 3. 认证技术细节

#### 3.1 ChatGPT 登录（PKCE）

```rust
// auth.rs:718-771
fn start_chatgpt_login(&mut self) {
    let opts = ServerOptions::new(
        self.codex_home.clone(),
        CLIENT_ID.to_string(),
        self.forced_chatgpt_workspace_id.clone(),
        self.cli_auth_credentials_store_mode,
    );
    
    match run_login_server(opts) {
        Ok(child) => {
            tokio::spawn(async move {
                // 1. 展示授权 URL
                // 2. 等待回调或超时
                // 3. 成功后刷新 AuthManager
                auth_manager.reload();
            });
        }
        Err(e) => { /* 错误处理 */ }
    }
}
```

#### 3.2 设备码登录（Headless）

```rust
// auth/headless_chatgpt_login.rs:26-130
pub(super) fn start_headless_chatgpt_login(widget: &mut AuthModeWidget, mut opts: ServerOptions) {
    opts.open_browser = false;
    let cancel = begin_device_code_attempt(&sign_in_state, &request_frame);
    
    tokio::spawn(async move {
        // 1. 请求设备码
        let device_code = match request_device_code(&opts).await {
            Ok(code) => code,
            Err(err) if err.kind() == NotFound => {
                // 2. 设备码不支持时回退到浏览器流程
            }
        };
        
        // 3. 轮询 token 或等待取消
        tokio::select! {
            _ = cancel.notified() => {}
            r = complete_device_code_login(opts, device_code) => { /* 处理结果 */ }
        }
    });
}
```

**取消机制**：使用 `Arc<Notify>` 实现跨异步任务的取消信号。

#### 3.3 API Key 处理

```rust
// auth.rs:671-705
fn save_api_key(&mut self, api_key: String) {
    match login_with_api_key(
        &self.codex_home,
        &api_key,
        self.cli_auth_credentials_store_mode,
    ) {
        Ok(()) => {
            self.auth_manager.reload();
            *self.sign_in_state.write().unwrap() = SignInState::ApiKeyConfigured;
        }
        Err(err) => { /* 恢复输入状态 */ }
    }
}
```

### 4. 渲染系统

#### 4.1 动态高度计算

```rust
// onboarding_screen.rs:285-348
impl WidgetRef for &OnboardingScreen {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        // 1. 使用临时 Buffer 测量每个步骤的实际高度
        let scratch = Buffer::empty(scratch_area);
        step.render_ref(scratch_area, &mut scratch);
        let h = used_rows(&scratch, width, max_h).min(max_h);
        
        // 2. 按顺序渲染，自动换行
        // 3. 已完成步骤保留显示，当前步骤高亮
    }
}
```

#### 4.2 视觉动画

**Shimmer 效果**：
```rust
// shimmer.rs:21-68
pub(crate) fn shimmer_spans(text: &str) -> Vec<Span<'static>> {
    // 基于进程启动时间的正弦波扫过效果
    let sweep_seconds = 2.0f32;
    let pos_f = (elapsed_since_start().as_secs_f32() % sweep_seconds) 
                 / sweep_seconds * (period as f32);
    // 根据距离计算颜色混合
    let t = 0.5 * (1.0 + x.cos());
    blend(highlight_color, base_color, highlight * 0.9)
}
```

**ASCII 动画**：
```rust
// ascii_animation.rs:44-62
pub(crate) fn schedule_next_frame(&self) {
    // 基于帧间隔计算下一帧时间
    let delay_ms = if rem_ms == 0 { tick_ms } else { tick_ms - rem_ms };
    self.request_frame.schedule_frame_in(Duration::from_millis(delay_ms));
}
```

### 5. 键盘事件处理

```rust
// onboarding_screen.rs:215-283
impl KeyboardHandler for OnboardingScreen {
    fn handle_key_event(&mut self, key_event: KeyEvent) {
        // 1. 全局退出快捷键（Ctrl+C, Ctrl+D, q）
        // 2. 特殊处理：API Key 输入模式禁用 'q' 退出
        // 3. 转发到当前活动步骤
        if let Some(active_step) = self.current_steps_mut().into_iter().last() {
            active_step.handle_key_event(key_event);
        }
    }
    
    fn handle_paste(&mut self, pasted: String) {
        // 粘贴内容转发到当前步骤（主要用于 API Key 输入）
    }
}
```

---

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 | 关键类型/函数 |
|------|------|---------------|
| `onboarding_screen.rs` | 流程编排 | `OnboardingScreen`, `run_onboarding_app`, `StepState` |
| `welcome.rs` | 欢迎页 | `WelcomeWidget`, `AsciiAnimation` |
| `auth.rs` | 认证 UI | `AuthModeWidget`, `SignInState`, `mark_url_hyperlink` |
| `auth/headless_chatgpt_login.rs` | 设备码登录 | `start_headless_chatgpt_login`, `render_device_code_login` |
| `trust_directory.rs` | 目录信任 | `TrustDirectoryWidget`, `TrustDirectorySelection` |
| `mod.rs` | 模块导出 | `TrustDirectorySelection` |

### 依赖文件

| 文件 | 职责 | 关联点 |
|------|------|--------|
| `lib.rs` | TUI 入口 | 调用 `run_onboarding_app`，定义 `LoginStatus` |
| `tui.rs` | TUI 框架 | `Tui`, `TuiEvent`, `FrameRequester` |
| `tui/frame_requester.rs` | 帧调度 | `FrameRequester`, `FrameScheduler` |
| `ascii_animation.rs` | ASCII 动画 | `AsciiAnimation`, `ALL_VARIANTS` |
| `frames.rs` | 动画帧数据 | `FRAMES_*`, `FRAME_TICK_DEFAULT` |
| `shimmer.rs` | 闪烁效果 | `shimmer_spans` |
| `selection_list.rs` | 选择列表 UI | `selection_option_row` |
| `key_hint.rs` | 快捷键提示 | `KeyBinding`, `plain()` |
| `render/renderable.rs` | 渲染抽象 | `Renderable`, `ColumnRenderable` |
| `render/mod.rs` | 渲染工具 | `Insets`, `RectExt` |

### 外部依赖

| Crate | 用途 | 关键类型/函数 |
|-------|------|---------------|
| `codex_core` | 认证核心 | `AuthManager`, `CodexAuth`, `login_with_api_key` |
| `codex_login` | 登录流程 | `run_login_server`, `DeviceCode`, `request_device_code` |
| `codex_protocol` | 配置类型 | `ForcedLoginMethod`, `TrustLevel` |
| `ratatui` | TUI 渲染 | `WidgetRef`, `Buffer`, `Rect`, `Line`, `Paragraph` |
| `crossterm` | 终端控制 | `KeyEvent`, `KeyCode` |

---

## 依赖与外部交互

### 1. 与 codex_core 的交互

```rust
// 认证管理
use codex_core::AuthManager;
use codex_core::auth::login_with_api_key;
use codex_core::auth::read_openai_api_key_from_env;
use codex_core::auth::AuthMode;
use codex_core::config::set_project_trust_level;
use codex_core::git_info::resolve_root_git_project_for_trust;
```

**交互模式**：
- `AuthManager` 通过 `Arc<AuthManager>` 共享，登录成功后调用 `reload()`
- 信任级别通过 `set_project_trust_level` 持久化到 `config.toml`

### 2. 与 codex_login 的交互

```rust
use codex_login::DeviceCode;
use codex_login::ServerOptions;
use codex_login::ShutdownHandle;
use codex_login::run_login_server;
use codex_login::complete_device_code_login;
use codex_login::request_device_code;
```

**交互模式**：
- `run_login_server` 返回 `LoginServer` 句柄，包含 `auth_url` 和 `cancel_handle`
- 设备码流程使用异步轮询 + 取消通知机制

### 3. 与 TUI 框架的交互

```rust
// 帧调度
pub request_frame: FrameRequester,  // 请求重绘

// 事件流
pub fn event_stream(&self) -> Pin<Box<dyn Stream<Item = TuiEvent> + Send + 'static>>;
```

**交互模式**：
- 使用 `FrameRequester` 进行**协作式调度**，避免频繁重绘
- 帧率限制在 120 FPS（`MIN_FRAME_INTERVAL`）

### 4. 配置系统交互

```rust
// lib.rs:1208-1233
fn should_show_trust_screen(config: &Config) -> bool {
    config.active_project.trust_level.is_none()
}

fn should_show_login_screen(login_status: LoginStatus, config: &Config) -> bool {
    if !config.model_provider.requires_openai_auth {
        return false;
    }
    login_status == LoginStatus::NotAuthenticated
}
```

---

## 风险、边界与改进建议

### 1. 已知风险

#### 1.1 并发状态管理

**风险**：`SignInState` 使用 `Arc<RwLock<SignInState>>`，在极端情况下可能出现：
- 读写锁竞争导致的 UI 卡顿
- 异步任务取消时的状态竞争

**代码位置**：
```rust
// auth.rs:200
pub sign_in_state: Arc<RwLock<SignInState>>,
```

**缓解措施**：
- 使用 `device_code_attempt_matches` 函数验证取消令牌匹配
- 短时间持有锁，尽快释放

#### 1.2 终端注入风险

**风险**：恶意 URL 可能包含终端转义序列。

**防护措施**：
```rust
// auth.rs:54-60
let safe_url: String = url
    .chars()
    .filter(|&c| c != '\x1B' && c != '\x07')
    .collect();
```

#### 1.3 配置持久化失败

**风险**：`set_project_trust_level` 可能因磁盘错误失败，但 UI 仍显示成功。

**当前处理**：
```rust
// trust_directory.rs:144-152
if let Err(e) = set_project_trust_level(...) {
    tracing::error!("Failed to set project trusted: {e:?}");
    self.error = Some(format!("Failed to set trust for {}: {e}", ...));
}
```

### 2. 边界情况

| 场景 | 行为 | 测试覆盖 |
|------|------|----------|
| 终端尺寸过小 | 自动隐藏 ASCII 动画 | `welcome_skips_animation_below_height_breakpoint` |
| 设备码不支持 | 自动回退到浏览器流程 | `headless_chatgpt_login.rs` 内联处理 |
| 粘贴多行文本 | 仅接受第一行（trim） | `handle_api_key_entry_paste` |
| 登录过程中退出 | 调用 `shutdown()` 清理回调服务器 | `ContinueInBrowserState::Drop` |
| 重复触发登录 | 检测现有认证状态，直接跳转成功页 | `handle_existing_chatgpt_login` |

### 3. 改进建议

#### 3.1 可访问性改进

**当前问题**：
- ASCII 动画对屏幕阅读器用户无意义
- 颜色对比度依赖终端主题

**建议**：
- 添加 `--no-animation` 启动参数（已有 `animations_enabled` 配置，但 CLI 未暴露）
- 支持高对比度模式

#### 3.2 错误恢复增强

**当前问题**：
- 认证失败仅显示错误文本，无重试引导
- 网络错误区分度低

**建议**：
```rust
// 建议添加
enum AuthError {
    NetworkTransient { retry_after: Duration },
    InvalidCredentials,
    ServerError { code: u16 },
}
```

#### 3.3 状态机简化

**当前问题**：
- `SignInState` 包含 7 个变体，部分状态转换隐式
- `StepState` 与 `SignInState` 存在概念重叠

**建议**：
- 考虑使用 `state_machine` crate 或宏生成转换规则
- 将 `ChatGptSuccessMessage` 和 `ChatGptSuccess` 合并，使用子状态

#### 3.4 测试覆盖

**当前状态**：
- 单元测试覆盖核心状态转换
- 快照测试验证 UI 渲染

**缺失**：
- 异步登录流程的集成测试（依赖外部 OAuth 服务，难以自动化）
- 多步骤组合场景测试

**建议**：
- 为 `codex_login` 添加 mock 服务器支持
- 使用 `insta` 进行更多 UI 状态快照测试

#### 3.5 性能优化

**潜在问题**：
- `used_rows` 函数每次渲染都扫描整个 Buffer（O(width×height)）
- ASCII 动画在后台持续调度帧，即使用户不可见

**建议**：
```rust
// 添加可见性检测
if self.animations_enabled && self.is_visible {
    self.animation.schedule_next_frame();
}
```

### 4. 架构债务

| 问题 | 位置 | 建议 |
|------|------|------|
| `#[allow(clippy::unwrap_used)]` | `auth.rs:1` | 逐步替换为 `expect` 并添加错误上下文 |
| 硬编码的帧数（36帧） | `frames.rs` | 使用 `include_dir` 宏动态加载 |
| Windows 特殊逻辑分散 | `onboarding_screen.rs`, `trust_directory.rs` | 抽象 `PlatformHints` trait |
| 魔法数字 | `MIN_ANIMATION_HEIGHT=37` | 提取为配置常量 |

---

## 附录：关键数据结构

### SignInState 状态转换图

```
                    ┌─────────────────┐
                    │    PickMode     │
                    └────────┬────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
        ▼                    ▼                    ▼
┌───────────────┐   ┌────────────────┐   ┌───────────────┐
│ChatGptContinue│   │ChatGptDeviceCode│   │ ApiKeyEntry   │
│  InBrowser    │   │                │   │               │
└───────┬───────┘   └───────┬────────┘   └───────┬───────┘
        │                   │                    │
        │                   │                    │
        ▼                   ▼                    ▼
┌───────────────┐   ┌────────────────┐   ┌───────────────┐
│ChatGptSuccess │   │ChatGptSuccess  │   │ApiKeyConfigured│
│   Message     │──▶│    Success     │   │               │
└───────────────┘   └────────────────┘   └───────────────┘
```

### OnboardingScreen 初始化流程

```
run_main
  └── should_show_onboarding?
       ├── true
       │    └── run_onboarding_app
       │         ├── OnboardingScreen::new
       │         │    ├── Step::Welcome (总是添加)
       │         │    ├── Step::Auth (如果需要登录)
       │         │    └── Step::TrustDirectory (如果需要信任确认)
       │         └── 事件循环
       └── false
            └── 跳过 onboarding，直接进入 App::run
```

---

*文档生成时间：2026-03-22*
*基于代码版本：codex-rs/tui/src/onboarding/*
