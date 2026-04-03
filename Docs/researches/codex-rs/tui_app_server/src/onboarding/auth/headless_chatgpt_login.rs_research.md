# headless_chatgpt_login.rs 深度研究文档

## 1. 场景与职责

### 1.1 模块定位

`headless_chatgpt_login.rs` 是 Codex TUI 应用服务器（`tui_app_server` crate）中负责**无头设备码登录流程**的核心模块。它实现了在终端 UI 环境下不依赖浏览器自动弹窗的 ChatGPT OAuth 登录方式，适用于：

- **远程/无头环境**：SSH 会话、容器环境、CI/CD 流水线
- **浏览器不可用场景**：用户无法或不愿在本地启动浏览器
- **备用登录路径**：当标准浏览器登录流程失败时的降级方案

### 1.2 架构位置

```
codex-rs/tui_app_server/src/
├── onboarding/
│   ├── mod.rs                    # 导出 onboarding 模块
│   ├── onboarding_screen.rs      # 主导航流程控制器
│   ├── auth.rs                   # 认证模式选择器（AuthModeWidget）
│   ├── auth/
│   │   └── headless_chatgpt_login.rs  # ← 本文件：设备码登录实现
│   ├── trust_directory.rs        # 目录信任选择
│   └── welcome.rs                # 欢迎界面
├── local_chatgpt_auth.rs         # 本地认证状态加载
└── shimmer.rs                    # UI 动画效果
```

### 1.3 与 tui crate 的关系

`tui_app_server` 和 `tui` 两个 crate 存在**并行实现**关系：

| 文件路径 | 用途 |
|---------|------|
| `codex-rs/tui/src/onboarding/auth/headless_chatgpt_login.rs` | 主 TUI crate 的实现 |
| `codex-rs/tui_app_server/src/onboarding/auth/headless_chatgpt_login.rs` | App Server 模式下的实现 |

两者核心逻辑高度相似，但存在关键差异：
- `tui` 版本使用 `AuthManager` 直接管理认证状态
- `tui_app_server` 版本通过 **App Server Protocol** 与后端通信，使用 `LoginAccountParams::ChatgptAuthTokens` 提交令牌

---

## 2. 功能点目的

### 2.1 核心功能

| 功能 | 说明 |
|-----|------|
| **设备码请求** | 向 OpenAI 设备授权端点请求用户码（user_code）和验证 URL |
| **轮询令牌** | 在后台轮询 `/deviceauth/token` 端点等待用户授权完成 |
| **令牌交换** | 使用授权码通过 PKCE 流程交换 OAuth 令牌 |
| **状态管理** | 维护登录流程的 UI 状态机，支持取消操作 |
| **降级回退** | 设备码服务不可用时（404）回退到浏览器登录 |

### 2.2 用户流程

```
用户选择 "Sign in with Device Code"
           ↓
    ┌─────────────────┐
    │ 请求设备码       │ ← POST /api/accounts/deviceauth/usercode
    └─────────────────┘
           ↓
    ┌─────────────────┐
    │ 显示验证 URL     │ ← https://chatgpt.com/codex/device
    │ 显示用户码       │ ← 例如：ABCD-EFGH
    └─────────────────┘
           ↓
    用户在外部浏览器中打开 URL 并输入用户码
           ↓
    ┌─────────────────┐
    │ 轮询令牌端点     │ ← POST /api/accounts/deviceauth/token
    │ (最长15分钟)     │
    └─────────────────┘
           ↓
    ┌─────────────────┐
    │ 交换 OAuth 令牌  │ ← POST /oauth/token
    └─────────────────┘
           ↓
    ┌─────────────────┐
    │ 提交令牌给服务器 │ ← LoginAccountParams::ChatgptAuthTokens
    └─────────────────┘
           ↓
      登录成功
```

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 SignInState（来自 auth.rs）

```rust
#[derive(Clone)]
pub(crate) enum SignInState {
    PickMode,                              // 选择登录方式
    ChatGptContinueInBrowser(ContinueInBrowserState),  // 浏览器登录中
    ChatGptDeviceCode(ContinueWithDeviceCodeState),    // 设备码登录中 ← 本模块核心
    ChatGptSuccessMessage,                 // 登录成功提示
    ChatGptSuccess,                        // 登录完成
    ApiKeyEntry(ApiKeyInputState),         // API Key 输入
    ApiKeyConfigured,                      // API Key 已配置
}
```

#### 3.1.2 ContinueWithDeviceCodeState

```rust
#[derive(Clone)]
pub(crate) struct ContinueWithDeviceCodeState {
    device_code: Option<DeviceCode>,      // 设备码信息
    cancel: Option<Arc<Notify>>,          // 取消信号
}
```

#### 3.1.3 DeviceCode（来自 codex_login crate）

```rust
#[derive(Debug, Clone)]
pub struct DeviceCode {
    pub verification_url: String,         // 用户需访问的验证 URL
    pub user_code: String,                // 显示给用户的代码
    device_auth_id: String,               // 内部设备授权 ID
    interval: u64,                        // 轮询间隔（秒）
}
```

### 3.2 核心流程实现

#### 3.2.1 启动设备码登录

```rust
pub(super) fn start_headless_chatgpt_login(widget: &mut AuthModeWidget) {
    // 1. 配置 ServerOptions
    let mut opts = ServerOptions::new(
        widget.codex_home.clone(),
        CLIENT_ID.to_string(),
        widget.forced_chatgpt_workspace_id.clone(),
        widget.cli_auth_credentials_store_mode,
    );
    opts.open_browser = false;  // 关键：不自动打开浏览器

    // 2. 初始化取消令牌和状态
    let cancel = begin_device_code_attempt(&sign_in_state, &request_frame);

    // 3. 在后台任务中执行登录流程
    tokio::spawn(async move {
        // 请求设备码
        let device_code = match request_device_code(&opts).await {
            Ok(dc) => dc,
            Err(err) if err.kind() == NotFound => {
                // 404 时回退到浏览器登录
                fallback_to_browser_login(...).await;
                return;
            }
            Err(err) => { /* 显示错误 */ return; }
        };

        // 更新状态显示设备码
        set_device_code_state_for_active_attempt(...);

        // 等待完成或取消
        tokio::select! {
            _ = cancel.notified() => {}  // 用户取消
            result = complete_device_code_login(opts, device_code) => {
                // 登录完成，加载本地认证并提交给服务器
                let local_auth = load_local_chatgpt_auth(...);
                handle_chatgpt_auth_tokens_login_result_for_active_attempt(...).await;
            }
        }
    });
}
```

#### 3.2.2 设备码渲染

```rust
pub(super) fn render_device_code_login(
    widget: &AuthModeWidget,
    area: Rect,
    buf: &mut Buffer,
    state: &ContinueWithDeviceCodeState,
) {
    // 动态横幅（带 shimmer 动画）
    let banner = if state.device_code.is_some() {
        "Finish signing in via your browser"
    } else {
        "Preparing device code login"
    };

    // 显示验证 URL（OSC 8 超链接）
    lines.push(Line::from(vec![
        "  ".into(),
        device_code.verification_url.as_str().cyan().underlined(),
    ]));

    // 显示用户码
    lines.push(Line::from(vec![
        "  ".into(),
        device_code.user_code.as_str().cyan().bold(),
    ]));

    // 安全提示
    lines.push("  Device codes are a common phishing target. Never share this code.".dim().into());

    // 使用 OSC 8 标记可点击链接
    if let Some(url) = &verification_url {
        mark_url_hyperlink(buf, area, url);
    }
}
```

#### 3.2.3 令牌提交给 App Server

与 `tui` crate 版本的关键差异：使用 App Server Protocol 提交令牌：

```rust
async fn handle_chatgpt_auth_tokens_login_result_for_active_attempt(
    request_handle: AppServerRequestHandle,
    // ... 其他参数
    local_auth: Result<LocalChatgptAuth, String>,
) {
    let local_auth = match local_auth { Ok(a) => a, Err(e) => { /* 错误处理 */ return; } };

    // 通过 App Server Protocol 提交令牌
    let result = request_handle
        .request_typed::<LoginAccountResponse>(ClientRequest::LoginAccount {
            request_id: onboarding_request_id(),
            params: LoginAccountParams::ChatgptAuthTokens {
                access_token: local_auth.access_token,
                chatgpt_account_id: local_auth.chatgpt_account_id,
                chatgpt_plan_type: local_auth.chatgpt_plan_type,
            },
        })
        .await;

    apply_chatgpt_auth_tokens_login_response_for_active_attempt(...);
}
```

### 3.3 状态安全机制

使用 `Arc<Notify>` 作为取消令牌，通过指针比较确保状态一致性：

```rust
fn device_code_attempt_matches(state: &SignInState, cancel: &Arc<Notify>) -> bool {
    matches!(
        state,
        SignInState::ChatGptDeviceCode(state)
            if state
                .cancel
                .as_ref()
                .is_some_and(|existing| Arc::ptr_eq(existing, cancel))
    )
}
```

所有状态更新操作都先验证 `device_code_attempt_matches`，防止：
- 过期任务的状态污染
- 竞态条件下的状态错乱
- 取消后迟到的回调影响

---

## 4. 关键代码路径与文件引用

### 4.1 本文件核心函数

| 函数 | 行号 | 职责 |
|-----|------|------|
| `start_headless_chatgpt_login` | 34-122 | 启动设备码登录流程 |
| `render_device_code_login` | 124-190 | 渲染设备码登录 UI |
| `device_code_attempt_matches` | 192-201 | 验证状态一致性 |
| `begin_device_code_attempt` | 203-214 | 初始化登录尝试 |
| `set_device_code_state_for_active_attempt` | 216-231 | 安全状态更新 |
| `fallback_to_browser_login` | 269-322 | 404 回退逻辑 |
| `handle_chatgpt_auth_tokens_login_result_for_active_attempt` | 324-363 | 提交令牌给服务器 |

### 4.2 依赖文件路径

```
codex-rs/
├── tui_app_server/src/
│   ├── onboarding/
│   │   ├── auth.rs                    # SignInState 定义、AuthModeWidget
│   │   └── auth/
│   │       └── headless_chatgpt_login.rs  # ← 本文件
│   ├── local_chatgpt_auth.rs          # LocalChatgptAuth、load_local_chatgpt_auth
│   ├── shimmer.rs                     # shimmer_spans 动画
│   └── tui/
│       └── frame_requester.rs         # FrameRequester
├── login/src/
│   ├── lib.rs                         # 导出 device_code_auth 模块
│   ├── device_code_auth.rs            # DeviceCode、request_device_code、complete_device_code_login
│   └── server.rs                      # ServerOptions、令牌交换
├── app-server-protocol/src/protocol/
│   └── v2.rs                          # LoginAccountParams、LoginAccountResponse
└── core/src/
    └── auth.rs                        # AuthCredentialsStoreMode、CLIENT_ID
```

### 4.3 协议端点

| 端点 | 方法 | 用途 |
|-----|------|------|
| `/api/accounts/deviceauth/usercode` | POST | 请求设备码 |
| `/api/accounts/deviceauth/token` | POST | 轮询授权结果 |
| `/oauth/token` | POST | 交换 OAuth 令牌 |

---

## 5. 依赖与外部交互

### 5.1 Crate 依赖

```rust
// 内部 crate
use codex_app_server_protocol::{ClientRequest, LoginAccountParams, LoginAccountResponse};
use codex_core::auth::CLIENT_ID;
use codex_login::{ServerOptions, complete_device_code_login, request_device_code};

// TUI 渲染
use ratatui::{buffer::Buffer, layout::Rect, prelude::Widget, style::Stylize, ...};

// 并发与同步
use std::sync::{Arc, RwLock};
use tokio::sync::Notify;
```

### 5.2 与 codex_login crate 的交互

```rust
// 1. 请求设备码
pub async fn request_device_code(opts: &ServerOptions) -> io::Result<DeviceCode> {
    let client = build_reqwest_client_with_custom_ca(...)?;
    let uc = request_user_code(&client, &api_base_url, &opts.client_id).await?;
    Ok(DeviceCode {
        verification_url: format!("{base_url}/codex/device"),
        user_code: uc.user_code,
        device_auth_id: uc.device_auth_id,
        interval: uc.interval,
    })
}

// 2. 完成登录
pub async fn complete_device_code_login(opts: ServerOptions, device_code: DeviceCode) -> io::Result<()> {
    // 轮询获取授权码
    let code_resp = poll_for_token(...).await?;
    // PKCE 令牌交换
    let tokens = crate::server::exchange_code_for_tokens(...).await?;
    // 工作空间验证
    crate::server::ensure_workspace_allowed(...)?;
    // 持久化令牌
    crate::server::persist_tokens_async(...).await
}
```

### 5.3 与 App Server 的交互

通过 `AppServerRequestHandle` 发送 `ClientRequest::LoginAccount`：

```rust
ClientRequest::LoginAccount {
    request_id: onboarding_request_id(),  // UUID v4
    params: LoginAccountParams::ChatgptAuthTokens {
        access_token,           // JWT access token
        chatgpt_account_id,     // 工作空间/账户 ID
        chatgpt_plan_type,      // 计划类型（可选）
    },
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|-----|------|---------|
| **设备码钓鱼** | 用户可能在假网站输入用户码 | UI 显示安全警告；使用 OSC 8 链接确保 URL 可点击 |
| **15分钟超时** | 用户码有效期限制 | 清晰的过期提示；支持 Esc 取消重试 |
| **404 回退失败** | 设备码服务不可用且浏览器也无法启动 | 显示错误信息；保持 PickMode 状态 |
| **竞态条件** | 快速切换登录方式可能导致状态错乱 | `Arc<Notify>` 指针比较验证；所有状态更新先验证匹配性 |
| **令牌泄露** | 日志中可能意外记录敏感令牌 | `codex_login` crate 实现了 URL 敏感参数脱敏 |

### 6.2 边界情况处理

```rust
// 1. 设备码服务返回 404 → 回退到浏览器登录
if err.kind() == std::io::ErrorKind::NotFound {
    fallback_to_browser_login(...).await;
}

// 2. 用户按 Esc 取消 → 通知后台任务终止
tokio::select! {
    _ = cancel.notified() => {}  // 优雅退出
    result = complete_device_code_login(...) => { ... }
}

// 3. 状态过期 → 拒绝更新
if !device_code_attempt_matches(&guard, cancel) {
    return false;  // 不更新状态
}
```

### 6.3 改进建议

#### 6.3.1 可观测性增强

```rust
// 建议：添加结构化日志追踪登录流程
tracing::info!(
    device_auth_id = %device_code.device_auth_id,
    "device_code_login_started"
);

tracing::info!(
    device_auth_id = %device_code.device_auth_id,
    elapsed_secs = %start.elapsed().as_secs(),
    "device_code_login_completed"
);
```

#### 6.3.2 重试机制

当前实现遇到网络错误直接失败，建议添加指数退避重试：

```rust
// 建议：在 request_device_code 和 poll_for_token 中添加重试
let backoff = tokio::time::Duration::from_secs(2);
for attempt in 0..MAX_RETRIES {
    match request_device_code(&opts).await {
        Ok(dc) => return Ok(dc),
        Err(e) if attempt < MAX_RETRIES - 1 => {
            tokio::time::sleep(backoff * 2_u32.pow(attempt)).await;
        }
        Err(e) => return Err(e),
    }
}
```

#### 6.3.3 与 tui crate 的代码复用

`tui` 和 `tui_app_server` 两个 crate 中存在大量重复代码。建议：

1. 提取通用逻辑到 `codex_login` 或新建 `codex_onboarding` crate
2. 使用 trait 抽象 `AuthManager` 和 `AppServerRequestHandle` 的差异

```rust
// 建议的抽象
trait AuthTokenSubmitter {
    async fn submit_tokens(&self, tokens: LocalChatgptAuth) -> Result<(), LoginError>;
}

impl AuthTokenSubmitter for AuthManager { ... }
impl AuthTokenSubmitter for AppServerRequestHandle { ... }
```

#### 6.3.4 测试覆盖

当前测试主要集中在状态机验证，建议补充：

- 集成测试：使用 `wiremock` 模拟完整的设备码流程
- 超时测试：验证 15 分钟超时行为
- 取消测试：验证异步取消的及时性

---

## 7. 附录：代码统计

| 指标 | 数值 |
|-----|------|
| 总行数 | ~546 行 |
| 核心函数 | 8 个 |
| 单元测试 | 5 个 |
| 外部依赖 crate | 6 个（codex_login、codex_core、ratatui 等）|

---

*文档生成时间：2026-03-23*
*研究范围：codex-rs/tui_app_server/src/onboarding/auth/headless_chatgpt_login.rs 及其直接依赖*
