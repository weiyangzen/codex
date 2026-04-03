# app_server_session.rs 研究文档

## 场景与职责

`app_server_session.rs` 是 Codex TUI 应用服务器会话管理的核心模块，负责在 TUI（终端用户界面）与 App Server 之间建立和维护通信会话。该模块作为 TUI 层与后端 App Server 之间的桥梁，封装了所有与线程（Thread）、回合（Turn）、实时对话（Realtime Conversation）相关的 RPC 调用。

### 核心职责
1. **会话生命周期管理**：处理 TUI 启动时的引导（bootstrap）流程，包括账户信息获取、模型列表加载、速率限制查询
2. **线程操作封装**：提供线程的创建（start）、恢复（resume）、分叉（fork）、读取（read）、列表查询（list）等操作
3. **回合管理**：处理用户回合的开始（turn_start）、中断（interrupt）、引导（steer）等操作
4. **实时对话支持**：管理实时语音对话的启动、音频/文本追加、停止等功能
5. **协议转换**：在 App Server Protocol 类型与 Core Protocol 类型之间进行转换

## 功能点目的

### 1. AppServerBootstrap - 启动引导数据结构
```rust
pub(crate) struct AppServerBootstrap {
    pub(crate) account_auth_mode: Option<AuthMode>,
    pub(crate) account_email: Option<String>,
    pub(crate) auth_mode: Option<TelemetryAuthMode>,
    pub(crate) status_account_display: Option<StatusAccountDisplay>,
    pub(crate) plan_type: Option<PlanType>,
    pub(crate) default_model: String,
    pub(crate) feedback_audience: FeedbackAudience,
    pub(crate) has_chatgpt_account: bool,
    pub(crate) available_models: Vec<ModelPreset>,
    pub(crate) rate_limit_snapshots: Vec<RateLimitSnapshot>,
}
```
该结构体承载了 TUI 启动时从 App Server 获取的所有必要信息，包括用户认证状态、可用模型、默认模型选择、速率限制状态等。

### 2. AppServerSession - 会话核心
```rust
pub(crate) struct AppServerSession {
    client: AppServerClient,
    next_request_id: i64,
}
```
封装了 App Server 客户端连接和请求 ID 生成器，提供类型安全的 RPC 调用接口。

### 3. ThreadSessionState - 线程会话状态
```rust
pub(crate) struct ThreadSessionState {
    pub(crate) thread_id: ThreadId,
    pub(crate) forked_from_id: Option<ThreadId>,
    pub(crate) thread_name: Option<String>,
    pub(crate) model: String,
    pub(crate) model_provider_id: String,
    pub(crate) service_tier: Option<ServiceTier>,
    pub(crate) approval_policy: AskForApproval,
    pub(crate) approvals_reviewer: ApprovalsReviewer,
    pub(crate) sandbox_policy: SandboxPolicy,
    pub(crate) cwd: PathBuf,
    pub(crate) reasoning_effort: Option<ReasoningEffort>,
    pub(crate) history_log_id: u64,
    pub(crate) history_entry_count: u64,
    pub(crate) network_proxy: Option<SessionNetworkProxyRuntime>,
    pub(crate) rollout_path: Option<PathBuf>,
}
```
维护了单个线程的完整运行时状态，用于 UI 状态同步和会话恢复。

## 具体技术实现

### 关键流程

#### 1. Bootstrap 流程（`bootstrap` 方法）
```rust
pub(crate) async fn bootstrap(&mut self, config: &Config) -> Result<AppServerBootstrap>
```
启动时顺序执行三个关键 RPC 调用：
1. `GetAccount` - 获取用户账户信息（API Key 或 ChatGPT 账户）
2. `ModelList` - 获取可用模型列表（包含隐藏模型）
3. `GetAccountRateLimits` - 获取账户速率限制信息

根据账户类型（API Key vs ChatGPT）设置不同的反馈受众（FeedbackAudience）：
- OpenAI 员工（@openai.com 邮箱）→ `FeedbackAudience::OpenAiEmployee`
- 外部用户 → `FeedbackAudience::External`

#### 2. 线程生命周期管理

**线程启动（`start_thread`）**：
```rust
pub(crate) async fn start_thread(&mut self, config: &Config) -> Result<AppServerStartedThread>
```
- 根据配置生成 `ThreadStartParams`
- 区分 Embedded（进程内）和 Remote（远程）两种模式
- Embedded 模式传递本地 `cwd` 和 `model_provider`
- Remote 模式省略本地特定配置

**线程恢复（`resume_thread`）**：
```rust
pub(crate) async fn resume_thread(&mut self, config: Config, thread_id: ThreadId) -> Result<AppServerStartedThread>
```
- 用于从历史记录中恢复已有线程
- 保留原线程的所有对话回合（turns）

**线程分叉（`fork_thread`）**：
```rust
pub(crate) async fn fork_thread(&mut self, config: Config, thread_id: ThreadId) -> Result<AppServerStartedThread>
```
- 从现有线程创建分支，保留历史但开启新对话上下文

#### 3. 回合操作

**回合开始（`turn_start`）**：
```rust
pub(crate) async fn turn_start(
    &mut self,
    thread_id: ThreadId,
    items: Vec<UserInput>,
    cwd: PathBuf,
    approval_policy: AskForApproval,
    approvals_reviewer: ApprovalsReviewer,
    sandbox_policy: SandboxPolicy,
    model: String,
    effort: Option<ReasoningEffort>,
    summary: Option<ReasoningSummary>,
    service_tier: Option<Option<ServiceTier>>,
    collaboration_mode: Option<CollaborationMode>,
    personality: Option<Personality>,
    output_schema: Option<serde_json::Value>,
) -> Result<TurnStartResponse>
```
参数涵盖了模型选择、审批策略、沙箱策略、推理努力度、协作模式、人格设定等完整配置。

#### 4. 实时对话支持

```rust
pub(crate) async fn thread_realtime_start(&mut self, thread_id: ThreadId, params: ConversationStartParams) -> Result<()>
pub(crate) async fn thread_realtime_audio(&mut self, thread_id: ThreadId, params: ConversationAudioParams) -> Result<()>
pub(crate) async fn thread_realtime_text(&mut self, thread_id: ThreadId, params: ConversationTextParams) -> Result<()>
pub(crate) async fn thread_realtime_stop(&mut self, thread_id: ThreadId) -> Result<()>
```
支持实时语音对话的完整生命周期：启动、音频帧推送、文本追加、停止。

### 数据结构

#### ThreadParamsMode 枚举
```rust
enum ThreadParamsMode {
    Embedded,  // 进程内模式，使用本地配置
    Remote,    // 远程模式，配置由服务器管理
}
```
决定了线程参数是否包含本地路径和模型提供者信息。

#### 模型预设转换（`model_preset_from_api_model`）
将 App Server 返回的 `ApiModel` 转换为 TUI 使用的 `ModelPreset`，处理：
- 模型升级信息（upgrade）
- 推理努力度映射
- 可用性提示（NUX - New User Experience）
- 输入模态（input modalities）

### 协议转换

#### 沙箱策略转换（`sandbox_mode_from_policy`）
```rust
fn sandbox_mode_from_policy(policy: SandboxPolicy) -> Option<SandboxMode>
```
将 Core 层的 `SandboxPolicy` 转换为 App Server 协议的 `SandboxMode`：
- `DangerFullAccess` → `SandboxMode::DangerFullAccess`
- `ReadOnly` → `SandboxMode::ReadOnly`
- `WorkspaceWrite` → `SandboxMode::WorkspaceWrite`
- `ExternalSandbox` → `None`（外部沙箱由其他机制管理）

#### 速率限制转换
```rust
fn app_server_rate_limit_snapshots_to_core(response: GetAccountRateLimitsResponse) -> Vec<RateLimitSnapshot>
```
将 App Server 的速率限制响应转换为 Core 层的 `RateLimitSnapshot` 向量，支持按 limit_id 分组的多重限制。

## 关键代码路径与文件引用

### 主要依赖

| 依赖模块 | 路径 | 用途 |
|---------|------|------|
| AppServerClient | `codex-rs/app-server-client/src/lib.rs` | RPC 客户端封装 |
| AppServerProtocol | `codex-rs/app-server-protocol/src/protocol/v2.rs` | 协议类型定义 |
| Core Config | `codex-rs/core/src/config/mod.rs` | 配置管理 |
| Protocol | `codex-rs/protocol/src/` | Core 层协议类型 |

### 调用关系

```
TUI App (app.rs)
    ↓
AppServerSession (app_server_session.rs)
    ↓
AppServerClient (app-server-client/src/lib.rs)
    ↓
InProcessAppServerClient / RemoteAppServerClient
    ↓
App Server Runtime
```

### 关键方法调用链

**线程启动流程**：
1. `App::start_session()` → `AppServerSession::start_thread()`
2. → `thread_start_params_from_config()` （参数构建）
3. → `client.request_typed(ClientRequest::ThreadStart)`
4. → `started_thread_from_start_response()` （响应解析）
5. → `thread_session_state_from_thread_start_response()` （状态构建）

**回合开始流程**：
1. `ChatWidget::submit_message()` → `App::handle_app_event()`
2. → `AppServerSession::turn_start()`
3. → `client.request_typed(ClientRequest::TurnStart)`

## 依赖与外部交互

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_app_server_client` | App Server 客户端 |
| `codex_app_server_protocol` | 协议类型定义 |
| `codex_core` | 核心配置和类型 |
| `codex_protocol` | Core 层协议类型 |
| `codex_otel` | 遥测认证模式 |
| `color_eyre` | 错误处理 |

### 配置依赖

- **`config.model`**：默认模型选择
- **`config.model_provider_id`**：模型提供者（Embedded 模式）
- **`config.cwd`**：当前工作目录（Embedded 模式）
- **`config.permissions.approval_policy`**：审批策略
- **`config.permissions.sandbox_policy`**：沙箱策略
- **`config.approvals_reviewer`**：审批审核者
- **`config.ephemeral`**：临时会话标志
- **`config.active_profile`**：活动配置档案

### 事件交互

通过 `AppServerEvent` 接收服务器事件：
- `ServerNotification`：服务器通知（如回合完成、状态更新）
- `ServerRequest`：服务器请求（如需要用户审批）
- `Lagged`：事件流滞后警告
- `Disconnected`：连接断开

## 风险、边界与改进建议

### 潜在风险

1. **请求 ID 溢出**：使用 `i64` 自增生成请求 ID，在极端长时间运行的会话中可能溢出（虽然实际概率极低）
   ```rust
   fn next_request_id(&mut self) -> RequestId {
       let request_id = self.next_request_id;
       self.next_request_id += 1;
       RequestId::Integer(request_id)
   }
   ```

2. **模式切换风险**：`ThreadParamsMode` 的区分在 Embedded 和 Remote 之间切换时可能导致配置丢失

3. **错误处理粒度**：所有 RPC 错误都使用 `wrap_err` 包装，可能丢失原始错误细节

### 边界情况

1. **空模型列表**：bootstrap 时会检查模型列表是否为空，返回明确的错误信息
   ```rust
   .wrap_err("model/list returned no models for TUI bootstrap")?
   ```

2. **账户类型变化**：支持 API Key 和 ChatGPT 两种认证模式，但切换时需要重新 bootstrap

3. **历史记录元数据**：`history_log_id` 和 `history_entry_count` 依赖本地文件系统，可能在多设备场景下不一致

### 改进建议

1. **请求 ID 生成**：考虑使用 UUID 或循环计数器避免溢出风险
   ```rust
   // 建议
   fn next_request_id(&mut self) -> RequestId {
       RequestId::String(uuid::Uuid::new_v4().to_string())
   }
   ```

2. **批量操作支持**：当前 `turn_start` 等操作是单个请求，对于批量消息发送可以考虑批量接口

3. **连接状态监控**：当前仅在调用时检测连接失败，可以增加心跳或连接状态回调

4. **配置缓存**：bootstrap 获取的模型列表和速率限制可以添加本地缓存和过期策略，减少启动延迟

5. **类型安全增强**：部分 `Option<Option<T>>` 类型（如 `service_tier`）语义复杂，建议拆分为更明确的枚举

6. **测试覆盖**：当前测试主要集中在参数生成，可以增加对错误路径和边界条件的测试

### 性能考虑

1. **同步调用**：所有 RPC 调用都是 `async` 但顺序执行，bootstrap 时的三个调用（account、models、rate_limits）可以并行化
2. **内存拷贝**：`ThreadSessionState` 包含多个 `String` 和 `PathBuf`，在频繁切换线程时可能产生较多内存分配

### 安全考虑

1. **敏感信息**：`account_email` 在日志中可能暴露，需要确保 tracing 配置正确过滤
2. **路径遍历**：`cwd` 和 `rollout_path` 来自配置，需要确保上游已经验证
