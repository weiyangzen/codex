# Codex-RS Core 模块深度研究报告

## 目录
1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 1.1 模块定位

`codex-rs/core` 是 OpenAI Codex 项目的核心 Rust 库（crate 名：`codex-core`），承担着以下核心职责：

- **AI 会话管理**：管理用户与 AI 模型的多轮对话生命周期
- **工具调用编排**：协调各类工具（文件操作、Shell 执行、MCP 等）的注册、路由和执行
- **沙箱安全执行**：提供跨平台的命令执行沙箱（macOS Seatbelt、Linux Landlock/Seccomp、Windows 受限令牌）
- **配置管理**：加载、合并和验证多层配置（用户配置、项目配置、云要求配置）
- **状态持久化**：会话历史、Rollout 记录、状态数据库管理
- **认证与授权**：支持 API Key 和 ChatGPT OAuth 两种认证模式
- **实时对话**：支持 WebSocket 实时音频对话

### 1.2 架构分层

```
┌─────────────────────────────────────────────────────────────┐
│                     应用层 (TUI/CLI)                          │
├─────────────────────────────────────────────────────────────┤
│  Codex 主结构体 (codex.rs)                                    │
│  ├── Session 管理                                             │
│  ├── Turn (轮次) 执行流程                                      │
│  └── 事件循环 (submission_loop)                               │
├─────────────────────────────────────────────────────────────┤
│  工具层 (tools/)                                              │
│  ├── 工具注册表 (registry.rs)                                  │
│  ├── 工具路由 (router.rs)                                      │
│  ├── 并行执行 (parallel.rs)                                    │
│  └── 各类工具处理器 (handlers/)                                 │
├─────────────────────────────────────────────────────────────┤
│  执行层 (exec.rs, sandboxing/)                                │
│  ├── 命令执行参数构建                                          │
│  ├── 沙箱类型选择                                              │
│  └── 跨平台沙箱实现                                            │
├─────────────────────────────────────────────────────────────┤
│  模型客户端 (client.rs)                                        │
│  ├── Responses API 调用                                        │
│  ├── WebSocket 连接管理                                        │
│  └── 流式响应处理                                              │
├─────────────────────────────────────────────────────────────┤
│  配置与状态 (config/, state/)                                  │
│  ├── 多层配置合并                                              │
│  ├── 会话状态管理                                              │
│  └── 上下文管理器 (context_manager)                            │
└─────────────────────────────────────────────────────────────┘
```

### 1.3 核心使用场景

| 场景 | 描述 | 关键组件 |
|------|------|----------|
| 交互式编码会话 | 用户通过 TUI 与 AI 持续对话 | `Codex`, `Session`, `TurnContext` |
| 批量任务执行 | `codex exec` 非交互式执行 | `ConfigOverrides`, `AskForApproval::Never` |
| 多 Agent 协作 | 父 Agent 创建子 Agent 并行工作 | `multi_agents` 工具处理器 |
| Guardian 审批 | AI 自动评估命令风险 | `guardian/` 模块 |
| MCP 工具集成 | 外部 MCP 服务器工具调用 | `mcp/`, `mcp_connection_manager` |

---

## 功能点目的

### 2.1 会话生命周期管理

**目的**：管理从会话创建到关闭的完整生命周期，包括配置初始化、历史记录恢复、事件循环。

**关键功能**：
- 会话创建：`Codex::spawn()` 初始化 Session，配置模型、权限、沙箱策略
- 历史恢复：支持 New/Forked/Resumed 三种会话启动模式
- 事件循环：`submission_loop` 处理用户提交 (Op) 并生成事件流
- 优雅关闭：`shutdown_and_wait` 确保资源清理

### 2.2 工具系统

**目的**：提供可扩展的工具调用框架，让 AI 能够执行文件操作、命令执行等任务。

**工具分类**：

| 类别 | 工具示例 | 处理器位置 |
|------|----------|------------|
| 文件操作 | read_file, list_dir, apply_patch | `handlers/read_file.rs`, `handlers/list_dir.rs` |
| 命令执行 | shell, unified_exec | `handlers/shell.rs`, `handlers/unified_exec.rs` |
| 代码执行 | js_repl | `handlers/js_repl.rs` |
| 搜索 | grep_files, tool_search | `handlers/grep_files.rs`, `handlers/tool_search.rs` |
| Agent 管理 | spawn, send_input, wait, close_agent | `handlers/multi_agents/` |
| MCP 工具 | 动态 MCP 工具调用 | `handlers/mcp.rs` |
| 权限 | request_permissions | `handlers/request_permissions.rs` |

### 2.3 沙箱安全系统

**目的**：在允许 AI 执行任意命令的同时，通过操作系统级沙箱限制潜在危害。

**沙箱类型**：

| 平台 | 沙箱机制 | 实现文件 |
|------|----------|----------|
| macOS | Seatbelt (sandbox-exec) | `seatbelt.rs`, `sandboxing/macos_permissions.rs` |
| Linux | Landlock + Seccomp + Bubblewrap | `landlock.rs`, `spawn.rs` |
| Windows | 受限访问令牌 + 作业对象 | `windows_sandbox.rs` |

**权限粒度**：
- 文件系统：只读/读写/拒绝访问
- 网络：完全禁止/代理/允许
- 额外权限：通过 `with_additional_permissions` 动态申请

### 2.4 Guardian 审批系统

**目的**：当审批策略为 `on-request` 时，使用独立 AI 会话评估命令风险，自动批准低风险操作。

**工作流程**：
1. 用户命令触发审批请求
2. 构建 Guardian 提示（包含会话上下文和待执行命令）
3. 调用 Guardian 模型评估风险等级
4. 风险分数 < 80 自动批准，否则转人工审批

### 2.5 MCP (Model Context Protocol) 集成

**目的**：连接外部 MCP 服务器，扩展可用工具集。

**功能**：
- MCP 服务器配置管理
- OAuth 认证流程
- 工具/资源/资源模板发现
- 动态工具调用

### 2.6 配置系统

**目的**：支持灵活的配置层级和覆盖机制。

**配置层级**（从低到高）：
1. 默认配置
2. 用户全局配置 (`~/.codex/config.toml`)
3. 项目配置 (`.codex/config.toml`)
4. 云要求配置 (requirements.toml)
5. CLI 覆盖参数
6. 代码级覆盖 (`ConfigOverrides`)

---

## 具体技术实现

### 3.1 核心数据结构

#### 3.1.1 Codex 主结构体

```rust
// codex.rs
pub struct Codex {
    pub(crate) tx_sub: Sender<Submission>,    // 提交发送通道
    pub(crate) rx_event: Receiver<Event>,     // 事件接收通道
    pub(crate) agent_status: watch::Receiver<AgentStatus>,
    pub(crate) session: Arc<Session>,
    pub(crate) session_loop_termination: SessionLoopTermination,
}
```

#### 3.1.2 Session 结构体

```rust
// codex.rs
pub(crate) struct Session {
    pub(crate) conversation_id: ThreadId,
    tx_event: Sender<Event>,
    agent_status: watch::Sender<AgentStatus>,
    out_of_band_elicitation_paused: watch::Sender<bool>,
    state: Mutex<SessionState>,
    features: ManagedFeatures,
    conversation: Arc<RealtimeConversationManager>,
    active_turn: Mutex<Option<ActiveTurn>>,
    guardian_review_session: GuardianReviewSessionManager,
    services: SessionServices,
    js_repl: Arc<JsReplHandle>,
    next_internal_sub_id: AtomicU64,
}
```

#### 3.1.3 TurnContext

```rust
// codex.rs
pub(crate) struct TurnContext {
    pub(crate) sub_id: String,
    pub(crate) trace_id: Option<String>,
    pub(crate) realtime_active: bool,
    pub(crate) config: Arc<Config>,
    pub(crate) auth_manager: Option<Arc<AuthManager>>,
    pub(crate) model_info: ModelInfo,
    pub(crate) session_telemetry: SessionTelemetry,
    pub(crate) provider: ModelProviderInfo,
    pub(crate) reasoning_effort: Option<ReasoningEffortConfig>,
    pub(crate) reasoning_summary: ReasoningSummaryConfig,
    pub(crate) session_source: SessionSource,
    pub(crate) environment: Arc<Environment>,
    pub(crate) cwd: PathBuf,
    // ... 更多字段
}
```

### 3.2 关键流程

#### 3.2.1 会话初始化流程

```
Codex::spawn()
├── 加载技能 (skills_manager.skills_for_config)
├── 检查功能标志 (JsRepl, CodeMode)
├── 获取用户指令 (get_user_instructions)
├── 加载执行策略 (ExecPolicyManager)
├── 获取默认模型 (models_manager.get_default_model)
├── 构建 SessionConfiguration
├── Session::new()
│   ├── 初始化 RolloutRecorder
│   ├── 启动网络代理 (可选)
│   ├── 初始化 MCP 连接管理器
│   ├── 创建 ModelClient
│   └── 发送 SessionConfigured 事件
└── 启动 submission_loop 任务
```

**代码路径**：`codex.rs:392-645`

#### 3.2.2 工具调用流程

```
模型返回 FunctionCall
├── ToolRouter::build_tool_call()
│   ├── 解析 MCP 工具名称 (parse_mcp_tool_name)
│   └── 构建 ToolCall 结构体
└── ToolRouter::dispatch_tool_call_with_code_mode_result()
    ├── 检查功能限制 (js_repl_tools_only)
    ├── 构建 ToolInvocation
    └── ToolRegistry::dispatch_any()
        ├── 查找处理器
        └── 执行工具逻辑
```

**代码路径**：`tools/router.rs:116-251`

#### 3.2.3 命令执行与沙箱流程

```
process_exec_tool_call()
├── build_exec_request()
│   ├── 选择沙箱类型 (SandboxManager::select_initial)
│   │   ├── macOS + 严格策略 → Seatbelt
│   │   ├── Linux + 严格策略 → Landlock/Seccomp
│   │   └── Windows → RestrictedToken
│   └── 构建 CommandSpec
└── sandboxing::execute_env()
    ├── 应用沙箱转换 (SandboxManager::transform)
    │   ├── Seatbelt: 生成 sandbox-exec 参数
    │   ├── Landlock: 构建规则集
    │   └── Windows: 创建受限令牌
    └── spawn_child_async() 执行命令
```

**代码路径**：`exec.rs:183-205`, `sandboxing/mod.rs`

#### 3.2.4 模型调用流程

```
ModelClient::new_session()
├── 获取缓存的 WebSocket 会话
└── ModelClientSession::stream()
    ├── 构建请求体 (ResponsesApiRequest)
    ├── 尝试 WebSocket 流
    │   ├── 连接 WebSocket
    │   ├── 发送请求
    │   └── 流式接收响应
    └── WebSocket 失败 → 回退到 HTTP SSE
```

**代码路径**：`client.rs:285-400`

### 3.3 协议与通信

#### 3.3.1 内部事件协议

核心事件类型定义在 `codex-protocol` crate，主要包括：

```rust
// 来自 codex_protocol::protocol
pub enum EventMsg {
    SessionConfigured(SessionConfiguredEvent),
    AgentMessage(AgentMessageEvent),
    AgentReasoning(AgentReasoningEvent),
    ExecCommandOutputDelta(ExecCommandOutputDeltaEvent),
    ExecApprovalRequest(ExecApprovalRequestEvent),
    NetworkApprovalRequest(NetworkApprovalRequestEvent),
    FunctionCallOutput(FunctionCallOutputEvent),
    ItemCompleted(ItemCompletedEvent),
    Error(ErrorEvent),
    // ... 更多
}
```

#### 3.3.2 工具调用协议

工具调用使用 OpenAI Responses API 格式：

```rust
// 模型返回
ResponseItem::FunctionCall {
    name: String,           // 工具名称
    namespace: Option<String>, // MCP 服务器命名空间
    arguments: String,      // JSON 参数
    call_id: String,        // 调用 ID
}

// 执行结果返回
ResponseItem::FunctionCallOutput {
    call_id: String,
    output: String,         // 执行结果
    is_error: Option<bool>,
}
```

### 3.4 并发模型

#### 3.4.1 任务并发

- **Session Loop**：单任务，顺序处理提交
- **工具并行执行**：使用 `ToolCallRuntime` 并行执行独立工具调用
- **MCP 连接**：每个 MCP 服务器独立连接，并发初始化
- **文件监听**：独立任务监听技能文件变化

#### 3.4.2 同步原语使用

| 类型 | 用途 | 位置 |
|------|------|------|
| `tokio::sync::Mutex` | Session 状态保护 | `Session::state` |
| `tokio::sync::RwLock` | MCP 连接管理器 | `SessionServices::mcp_connection_manager` |
| `watch::channel` | Agent 状态广播 | `Session::agent_status` |
| `async_channel` | 事件流 | `Codex::rx_event` |
| `std::sync::Mutex` | WebSocket 会话缓存 | `ModelClientState::cached_websocket_session` |

---

## 关键代码路径与文件引用

### 4.1 核心模块文件映射

| 功能域 | 主文件 | 测试文件 |
|--------|--------|----------|
| 会话管理 | `codex.rs` | `codex_tests.rs`, `codex_tests_guardian.rs` |
| 模型客户端 | `client.rs` | `client_tests.rs` |
| 配置系统 | `config/mod.rs` | `config/config_tests.rs` |
| 配置加载 | `config_loader/mod.rs` | `config_loader/tests.rs` |
| 错误处理 | `error.rs` | `error_tests.rs` |
| 执行引擎 | `exec.rs` | `exec_tests.rs` |
| 沙箱系统 | `sandboxing/mod.rs` | `sandboxing/mod_tests.rs` |
| 工具路由 | `tools/router.rs` | `tools/router_tests.rs` |
| 工具注册表 | `tools/registry.rs` | `tools/registry_tests.rs` |
| MCP 管理 | `mcp/mod.rs` | `mcp/mod_tests.rs` |
| Guardian | `guardian/mod.rs` | `guardian/tests.rs` |
| 状态管理 | `state/session.rs` | `state/session_tests.rs` |
| 认证 | `auth.rs` | `auth_tests.rs` |

### 4.2 工具处理器文件映射

| 工具 | 实现文件 | 测试文件 |
|------|----------|----------|
| read_file | `tools/handlers/read_file.rs` | `tools/handlers/read_file_tests.rs` |
| list_dir | `tools/handlers/list_dir.rs` | `tools/handlers/list_dir_tests.rs` |
| shell | `tools/handlers/shell.rs` | `tools/handlers/shell_tests.rs` |
| apply_patch | `tools/handlers/apply_patch.rs` | `tools/handlers/apply_patch_tests.rs` |
| grep_files | `tools/handlers/grep_files.rs` | `tools/handlers/grep_files_tests.rs` |
| js_repl | `tools/handlers/js_repl.rs` | `tools/handlers/js_repl_tests.rs` |
| multi_agents | `tools/handlers/multi_agents.rs` | `tools/handlers/multi_agents_tests.rs` |
| unified_exec | `tools/handlers/unified_exec.rs` | `tools/handlers/unified_exec_tests.rs` |

### 4.3 关键代码片段

#### 3.2.1 会话初始化（codex.rs:418-645）

```rust
async fn spawn_internal(args: CodexSpawnArgs) -> CodexResult<CodexSpawnOk> {
    // 1. 解构参数
    let CodexSpawnArgs { config, auth_manager, ... } = args;
    
    // 2. 创建通道
    let (tx_sub, rx_sub) = async_channel::bounded(SUBMISSION_CHANNEL_CAPACITY);
    let (tx_event, rx_event) = async_channel::unbounded();
    
    // 3. 加载技能
    let loaded_skills = skills_manager.skills_for_config(&config);
    
    // 4. 功能标志检查
    if config.features.enabled(Feature::JsRepl) {
        // 检查 Node 运行时可用性
    }
    
    // 5. 构建 SessionConfiguration
    let session_configuration = SessionConfiguration { ... };
    
    // 6. 创建 Session
    let session = Session::new(session_configuration, ...).await?;
    
    // 7. 启动事件循环
    let session_loop_handle = tokio::spawn(async move {
        submission_loop(session_for_loop, config, rx_sub).await;
    });
    
    // 8. 返回 Codex 实例
    Ok(CodexSpawnOk { codex, thread_id, ... })
}
```

#### 3.4.2 工具路由分发（tools/router.rs:214-251）

```rust
pub async fn dispatch_tool_call_with_code_mode_result(
    &self,
    session: Arc<Session>,
    turn: Arc<TurnContext>,
    tracker: SharedTurnDiffTracker,
    call: ToolCall,
    source: ToolCallSource,
) -> Result<AnyToolResult, FunctionCallError> {
    // 1. 检查功能限制
    if source == ToolCallSource::Direct && turn.tools_config.js_repl_tools_only {
        // 拒绝非 js_repl 的直接调用
    }
    
    // 2. 构建调用上下文
    let invocation = ToolInvocation {
        session,
        turn,
        tracker,
        call_id,
        tool_name,
        tool_namespace,
        payload,
    };
    
    // 3. 分发到注册表
    self.registry.dispatch_any(invocation).await
}
```

#### 3.4.3 沙箱执行（sandboxing/mod.rs:103-150）

```rust
pub(crate) fn transform(&self, request: SandboxTransformRequest<'_>) -> Result<ExecRequest, SandboxTransformError> {
    match request.sandbox {
        SandboxType::None => self.transform_none(request),
        SandboxType::MacosSeatbelt => self.transform_seatbelt(request),
        SandboxType::LinuxSeccomp => self.transform_seccomp(request),
        SandboxType::WindowsRestrictedToken => self.transform_windows(request),
    }
}
```

---

## 依赖与外部交互

### 5.1 内部 Crate 依赖

| Crate | 用途 | 关键使用位置 |
|-------|------|--------------|
| `codex-protocol` | 协议类型定义 | 全模块 |
| `codex-api` | OpenAI API 客户端 | `client.rs` |
| `codex-config` | 配置约束系统 | `config/` |
| `codex-network-proxy` | 网络代理 | 网络沙箱 |
| `codex-otel` | 遥测和指标 | 全模块 |
| `codex-hooks` | 生命周期钩子 | `hook_runtime.rs` |
| `codex-rmcp-client` | MCP 客户端 | `mcp/` |
| `codex-state` | 状态数据库 | `state_db.rs` |

### 5.2 外部依赖

| Crate | 版本 | 用途 |
|-------|------|------|
| `tokio` | workspace | 异步运行时 |
| `serde`/`serde_json` | workspace | 序列化 |
| `reqwest` | workspace | HTTP 客户端 |
| `tokio-tungstenite` | workspace | WebSocket 客户端 |
| `landlock` | workspace | Linux 沙箱 |
| `seccompiler` | workspace | Seccomp BPF |
| `rmcp` | workspace | MCP 协议实现 |
| `tracing` | workspace | 结构化日志 |

### 5.3 系统交互

| 平台 | 交互组件 | 用途 |
|------|----------|------|
| macOS | `sandbox-exec` | Seatbelt 沙箱 |
| macOS | `core-foundation` | 系统权限检测 |
| Linux | `bwrap` (bubblewrap) | 命名空间沙箱 |
| Linux | Landlock LSM | 文件系统沙箱 |
| Linux | Seccomp BPF | 系统调用过滤 |
| Windows | Win32 API | 受限令牌和作业对象 |
| All | 系统 shell | 命令执行 (bash/zsh/powershell) |

---

## 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 安全风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 沙箱逃逸 | 恶意命令可能利用沙箱漏洞 | 多层沙箱、最小权限原则、Guardian 审批 |
| 提示注入 | 外部内容可能劫持 AI 行为 | 输入验证、技能注入控制 |
| 凭证泄露 | 环境变量或文件可能泄露敏感信息 | 密钥环存储、环境变量过滤 |
| MCP 服务器风险 | 外部 MCP 服务器可能恶意 | 用户确认、权限限制 |

#### 6.1.2 稳定性风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 资源耗尽 | 长会话可能导致内存/磁盘耗尽 | 自动压缩、Rollout 截断 |
| 死锁 | 异步锁使用不当可能导致死锁 | 锁层级规范、超时机制 |
| 网络中断 | API 调用可能失败 | 重试机制、优雅降级 |

### 6.2 边界条件

#### 6.2.1 配置边界

```rust
// 默认限制常量 (config/mod.rs)
pub(crate) const DEFAULT_AGENT_MAX_THREADS: Option<usize> = Some(6);
pub(crate) const DEFAULT_AGENT_MAX_DEPTH: i32 = 1;
pub(crate) const DEFAULT_AGENT_JOB_MAX_RUNTIME_SECONDS: Option<u64> = None;
pub(crate) const PROJECT_DOC_MAX_BYTES: usize = 32 * 1024; // 32 KiB
```

#### 6.2.2 执行边界

```rust
// 执行限制 (exec.rs)
pub const DEFAULT_EXEC_COMMAND_TIMEOUT_MS: u64 = 10_000;
pub(crate) const MAX_EXEC_OUTPUT_DELTAS_PER_CALL: usize = 10_000;
pub const IO_DRAIN_TIMEOUT_MS: u64 = 2_000;

// 输出限制 (tools/mod.rs)
pub(crate) const TELEMETRY_PREVIEW_MAX_BYTES: usize = 2 * 1024;
pub(crate) const TELEMETRY_PREVIEW_MAX_LINES: usize = 64;
```

#### 6.2.3 Guardian 边界

```rust
// Guardian 限制 (guardian/mod.rs)
const GUARDIAN_REVIEW_TIMEOUT: Duration = Duration::from_secs(90);
const GUARDIAN_MAX_MESSAGE_TRANSCRIPT_TOKENS: usize = 10_000;
const GUARDIAN_MAX_TOOL_TRANSCRIPT_TOKENS: usize = 10_000;
const GUARDIAN_APPROVAL_RISK_THRESHOLD: u8 = 80;
```

### 6.3 改进建议

#### 6.3.1 架构改进

1. **配置系统简化**
   - 当前配置层级复杂，建议引入配置验证和可视化工具
   - 考虑使用 JSON Schema 验证用户配置

2. **错误处理统一**
   - 部分模块仍使用 `anyhow::Error`，建议全面迁移到 `CodexErr`
   - 增加错误上下文链，便于调试

3. **测试覆盖**
   - 增加集成测试覆盖率，特别是跨平台沙箱行为
   - 添加性能基准测试

#### 6.3.2 性能优化

1. **上下文管理**
   - 当前 `ContextManager` 使用全量存储，大会话内存占用高
   - 建议实现分层存储，活跃部分在内存，历史部分持久化

2. **模型客户端连接池**
   - WebSocket 连接复用可进一步优化
   - 考虑连接预热和保活机制

3. **工具注册表缓存**
   - MCP 工具列表变化不频繁，可增加缓存层

#### 6.3.3 安全加固

1. **沙箱增强**
   - Linux: 考虑支持更多 LSM (AppArmor, SELinux)
   - 增加沙箱行为审计日志

2. **权限细化**
   - 当前 `SandboxPermissions` 粒度较粗
   - 建议支持更细粒度的能力控制 (Linux capabilities)

#### 6.3.4 可观测性

1. **指标增强**
   - 增加工具调用延迟分布指标
   - 增加沙箱决策指标

2. **链路追踪**
   - 完善 OpenTelemetry 集成
   - 增加跨 Agent 调用的链路传播

### 6.4 技术债务

| 位置 | 问题 | 建议 |
|------|------|------|
| `codex.rs:1050` | `original_config_do_not_use` 字段 | 重构配置传递方式，避免直接存储完整 Config |
| `config/mod.rs` | 配置加载逻辑分散 | 统一配置加载和验证逻辑 |
| `tools/handlers/` | 处理器代码重复 | 提取通用逻辑到基类或宏 |
| `mcp_connection_manager.rs` | 连接管理复杂 | 考虑使用状态机模式重构 |

---

## 附录

### A. 目录结构

```
codex-rs/core/src/
├── lib.rs                    # 库入口
├── codex.rs                  # 核心 Codex 结构体
├── codex_thread.rs           # 线程管理封装
├── client.rs                 # 模型 API 客户端
├── client_common.rs          # 客户端共享类型
├── config/                   # 配置系统
│   ├── mod.rs
│   ├── types.rs
│   ├── permissions.rs
│   └── ...
├── config_loader/            # 配置加载
├── tools/                    # 工具系统
│   ├── mod.rs
│   ├── router.rs
│   ├── registry.rs
│   ├── spec.rs
│   ├── handlers/             # 工具处理器
│   ├── code_mode/            # Code Mode 工具
│   └── ...
├── sandboxing/               # 沙箱系统
├── guardian/                 # Guardian 审批
├── mcp/                      # MCP 集成
├── skills/                   # 技能系统
├── state/                    # 状态管理
├── rollout/                  # Rollout 记录
├── agent/                    # Agent 控制
├── exec.rs                   # 命令执行
├── auth.rs                   # 认证管理
└── ...
```

### B. 参考资料

- [OpenAI Codex 文档](https://github.com/openai/codex)
- [Model Context Protocol 规范](https://modelcontextprotocol.io/)
- [Landlock 文档](https://docs.kernel.org/userspace-api/landlock.html)
- [macOS Seatbelt 文档](https://developer.apple.com/library/archive/documentation/Darwin/Reference/ManPages/man1/sandbox-exec.1.html)
