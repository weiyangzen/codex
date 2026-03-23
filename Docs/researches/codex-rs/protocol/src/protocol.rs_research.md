# Codex Protocol 深度研究文档

## 文件信息

- **目标文件**: `codex-rs/protocol/src/protocol.rs`
- **文件行数**: 4429 行
- **所属 Crate**: `codex-protocol`
- ** crate 路径**: `codex-rs/protocol/`

---

## 1. 场景与职责

### 1.1 核心定位

`protocol.rs` 是 Codex 系统的**核心协议定义文件**，它定义了客户端（UI/CLI）与 AI Agent 之间的完整通信协议。该文件采用 **SQ/EQ (Submission Queue / Event Queue)** 异步通信模式：

- **SQ (Submission Queue)**: 客户端向 Agent 发送的请求队列
- **EQ (Event Queue)**: Agent 向客户端发送的事件队列

### 1.2 主要职责

| 职责领域 | 说明 |
|---------|------|
| **消息协议定义** | 定义所有客户端-Agent 之间的消息类型和结构 |
| **沙盒策略** | 定义文件系统/网络访问的安全沙盒策略 |
| **审批流程** | 定义命令执行和代码补丁的审批机制 |
| **会话管理** | 定义会话生命周期、历史记录、恢复机制 |
| **实时对话** | 定义实时语音/文本对话的协议 |
| **协作模式** | 定义多 Agent 协作的通信协议 |
| **Token 计费** | 定义使用量统计和计费相关结构 |

### 1.3 使用场景

```
┌─────────────┐     Submission      ┌─────────────┐
│   Client    │ ──────────────────> │    Agent    │
│  (TUI/CLI)  │                     │   (Core)    │
│             │ <────────────────── │             │
└─────────────┘      Event          └─────────────┘
```

- **TUI (Terminal UI)**: 通过 `EventMsg` 渲染界面，通过 `Op` 发送用户操作
- **Core (Agent)**: 处理 `Op` 请求，生成 `EventMsg` 事件流
- **Exec**: 命令行执行模式，使用协议进行 JSONL 通信
- **MCP Server**: 作为 MCP 工具运行时，使用协议子集

---

## 2. 功能点目的

### 2.1 核心数据结构

#### 2.1.1 Submission (提交请求)

```rust
#[derive(Debug, Clone, Deserialize, Serialize, JsonSchema)]
pub struct Submission {
    /// 唯一 ID，用于关联 Event
    pub id: String,
    /// 请求负载
    pub op: Op,
    /// 可选的 W3C Trace Context（分布式追踪）
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub trace: Option<W3cTraceContext>,
}
```

**设计目的**:
- 为每个客户端请求分配唯一标识
- 支持分布式追踪（OpenTelemetry 集成）
- 实现请求-响应的异步关联

#### 2.1.2 Op (操作枚举)

`Op` 定义了客户端可以执行的所有操作，共 **30+ 种操作类型**：

| 操作类别 | 具体操作 | 用途 |
|---------|---------|------|
| **会话控制** | `Interrupt`, `Shutdown`, `CleanBackgroundTerminals` | 中断/关闭/清理 |
| **用户输入** | `UserInput`, `UserTurn` | 发送用户消息 |
| **实时对话** | `RealtimeConversationStart`, `RealtimeConversationAudio`, `RealtimeConversationText`, `RealtimeConversationClose` | 实时语音/文本 |
| **审批** | `ExecApproval`, `PatchApproval` | 审批命令/补丁 |
| **MCP** | `ResolveElicitation`, `ListMcpTools`, `RefreshMcpServers` | MCP 服务器管理 |
| **上下文** | `OverrideTurnContext`, `Compact`, `ThreadRollback`, `Undo` | 上下文管理 |
| **记忆** | `DropMemories`, `UpdateMemories` | 记忆系统 |
| **其他** | `AddToHistory`, `GetHistoryEntryRequest`, `ListCustomPrompts`, `ListSkills`, `SetThreadName`, `Review`, `RunUserShellCommand`, `ListModels` | 杂项功能 |

**关键设计**: `UserTurn` vs `UserInput`
- `UserTurn`: 现代推荐方式，包含完整上下文（cwd、沙盒策略、模型等）
- `UserInput`: 遗留方式，依赖会话级持久上下文

#### 2.1.3 Event (事件)

```rust
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Event {
    /// 关联的 Submission ID
    pub id: String,
    /// 事件负载
    pub msg: EventMsg,
}
```

#### 2.1.4 EventMsg (事件消息枚举)

`EventMsg` 定义了 **80+ 种事件类型**，涵盖：

| 事件类别 | 事件示例 | 触发时机 |
|---------|---------|---------|
| **生命周期** | `TurnStarted`, `TurnComplete`, `TurnAborted` | 会话生命周期 |
| **消息** | `AgentMessage`, `AgentMessageDelta`, `UserMessage` | 消息交换 |
| **推理** | `AgentReasoning`, `AgentReasoningDelta`, `AgentReasoningRawContent` | 模型推理 |
| **工具调用** | `ExecCommandBegin`, `ExecCommandOutputDelta`, `ExecCommandEnd` | 命令执行 |
| **MCP** | `McpToolCallBegin`, `McpToolCallEnd`, `McpStartupUpdate` | MCP 调用 |
| **搜索/生成** | `WebSearchBegin`, `WebSearchEnd`, `ImageGenerationBegin`, `ImageGenerationEnd` | 工具使用 |
| **审批** | `ExecApprovalRequest`, `ApplyPatchApprovalRequest`, `GuardianAssessment` | 审批流程 |
| **协作** | `CollabAgentSpawnBegin`, `CollabAgentInteractionEnd` | 多 Agent 协作 |
| **其他** | `TokenCount`, `ModelReroute`, `ContextCompacted`, `DeprecationNotice` | 其他事件 |

### 2.2 沙盒策略系统

#### 2.2.1 SandboxPolicy (沙盒策略)

```rust
pub enum SandboxPolicy {
    /// 完全无限制（危险模式）
    DangerFullAccess,
    /// 只读访问
    ReadOnly { access: ReadOnlyAccess, network_access: bool },
    /// 外部沙盒（已在外部沙盒中运行）
    ExternalSandbox { network_access: NetworkAccess },
    /// 工作区写入（推荐）
    WorkspaceWrite { 
        writable_roots: Vec<AbsolutePathBuf>,
        read_only_access: ReadOnlyAccess,
        network_access: bool,
        exclude_tmpdir_env_var: bool,
        exclude_slash_tmp: bool,
    },
}
```

**安全设计**:
- 默认使用 `WorkspaceWrite`，只允许写入当前工作目录
- 自动保护 `.git`、`.codex`、`.agents` 目录（只读）
- 支持网络访问独立控制

#### 2.2.2 ReadOnlyAccess (只读访问)

```rust
pub enum ReadOnlyAccess {
    /// 限制在显式根目录
    Restricted { 
        include_platform_defaults: bool,  // 包含平台默认路径
        readable_roots: Vec<AbsolutePathBuf>, 
    },
    /// 完全磁盘读取
    FullAccess,
}
```

#### 2.2.3 WritableRoot (可写根目录)

```rust
pub struct WritableRoot {
    pub root: AbsolutePathBuf,
    /// 在可写根目录下保持只读的子路径
    pub read_only_subpaths: Vec<AbsolutePathBuf>,
}
```

**安全特性**: 即使根目录可写，特定子路径（如 `.git`）仍保持只读

### 2.3 审批系统

#### 2.3.1 AskForApproval (审批策略)

```rust
pub enum AskForApproval {
    /// 仅对非可信命令询问（默认）
    UnlessTrusted,
    /// 失败时询问（已废弃）
    OnFailure,
    /// 模型决定何时询问（默认）
    OnRequest,
    /// 细粒度控制
    Granular(GranularApprovalConfig),
    /// 从不询问
    Never,
}
```

#### 2.3.2 GranularApprovalConfig (细粒度审批配置)

```rust
pub struct GranularApprovalConfig {
    pub sandbox_approval: bool,      // 沙盒命令审批
    pub rules: bool,                 // execpolicy 规则触发
    pub skill_approval: bool,        // Skill 脚本执行
    pub request_permissions: bool,   // request_permissions 工具
    pub mcp_elicitations: bool,      MCP 诱导请求
}
```

#### 2.3.3 ReviewDecision (审批决策)

```rust
pub enum ReviewDecision {
    Approved,                    // 批准
    ApprovedExecpolicyAmendment { proposed_execpolicy_amendment: ExecPolicyAmendment },  // 批准并添加前缀规则
    ApprovedForSession,          // 批准并缓存到会话
    NetworkPolicyAmendment { network_policy_amendment: NetworkPolicyAmendment },  // 网络策略修改
    Denied,                      // 拒绝但继续
    Abort,                       // 拒绝并停止
}
```

### 2.4 Token 计费系统

#### 2.4.1 TokenUsage (Token 使用)

```rust
#[derive(Debug, Clone, Deserialize, Serialize, Default, PartialEq, Eq, JsonSchema, TS)]
pub struct TokenUsage {
    #[ts(type = "number")]
    pub input_tokens: i64,
    #[ts(type = "number")]
    pub cached_input_tokens: i64,
    #[ts(type = "number")]
    pub output_tokens: i64,
    #[ts(type = "number")]
    pub reasoning_output_tokens: i64,
    #[ts(type = "number")]
    pub total_tokens: i64,
}
```

#### 2.4.2 TokenUsageInfo (Token 使用信息)

```rust
pub struct TokenUsageInfo {
    pub total_token_usage: TokenUsage,  // 总会话使用
    pub last_token_usage: TokenUsage,   // 最近一轮使用
    #[ts(type = "number | null")]
    pub model_context_window: Option<i64>,  // 上下文窗口大小
}
```

**关键功能**:
- `percent_of_context_window_remaining()`: 计算上下文窗口剩余百分比
- `blended_total()`: 计算显示用的总 Token 数（非缓存输入 + 输出）

### 2.5 实时对话系统

#### 2.5.1 RealtimeEvent (实时事件)

```rust
pub enum RealtimeEvent {
    SessionUpdated { session_id: String, instructions: Option<String> },
    InputAudioSpeechStarted(RealtimeInputAudioSpeechStarted),
    InputTranscriptDelta(RealtimeTranscriptDelta),
    OutputTranscriptDelta(RealtimeTranscriptDelta),
    AudioOut(RealtimeAudioFrame),
    ResponseCancelled(RealtimeResponseCancelled),
    ConversationItemAdded(Value),
    ConversationItemDone { item_id: String },
    HandoffRequested(RealtimeHandoffRequested),
    Error(String),
}
```

#### 2.5.2 RealtimeAudioFrame (音频帧)

```rust
pub struct RealtimeAudioFrame {
    pub data: String,              // Base64 编码音频数据
    pub sample_rate: u32,          // 采样率
    pub num_channels: u16,         // 通道数
    pub samples_per_channel: Option<u32>,
    pub item_id: Option<String>,
}
```

### 2.6 多 Agent 协作系统

定义了 8 种协作事件，支持 Agent 之间的：
- **Spawn**: 创建子 Agent
- **Interaction**: Agent 间交互
- **Waiting**: 等待其他 Agent
- **Close**: 关闭 Agent
- **Resume**: 恢复 Agent

```rust
pub struct CollabAgentSpawnBeginEvent {
    pub call_id: String,
    pub sender_thread_id: ThreadId,
    pub prompt: String,
    pub model: String,
    pub reasoning_effort: ReasoningEffortConfig,
}
```

---

## 3. 具体技术实现

### 3.1 序列化与类型安全

#### 3.1.1 序列化配置

```rust
#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, JsonSchema, TS)]
#[serde(tag = "type", rename_all = "snake_case")]
#[ts(tag = "type")]
#[strum(serialize_all = "snake_case")]
pub enum EventMsg {
    // ...
}
```

- **`tag = "type"`**: 使用内部标签进行多态序列化
- **`rename_all = "snake_case"`**: 字段名使用蛇形命名
- **`JsonSchema`**: 生成 JSON Schema 用于验证
- **`TS`**: 生成 TypeScript 类型定义

#### 3.1.2 向后兼容处理

```rust
#[serde(rename = "task_started", alias = "turn_started")]
TurnStarted(TurnStartedEvent),
```

使用 `alias` 支持旧版本字段名，实现协议兼容性。

### 3.2 沙盒路径解析

#### 3.2.1 可写根目录计算

```rust
pub fn get_writable_roots_with_cwd(&self, cwd: &Path) -> Vec<WritableRoot> {
    match self {
        SandboxPolicy::WorkspaceWrite { writable_roots, .. } => {
            // 1. 从配置的可写根目录开始
            let mut roots: Vec<AbsolutePathBuf> = writable_roots.clone();
            
            // 2. 添加当前工作目录
            roots.push(cwd_absolute?);
            
            // 3. 添加 /tmp (Unix)
            if cfg!(unix) && !exclude_slash_tmp {
                roots.push("/tmp".into());
            }
            
            // 4. 添加 $TMPDIR
            if !exclude_tmpdir_env_var {
                if let Some(tmpdir) = std::env::var_os("TMPDIR") {
                    roots.push(tmpdir.into());
                }
            }
            
            // 5. 为每个根目录计算只读子路径
            roots.into_iter().map(|root| WritableRoot {
                read_only_subpaths: default_read_only_subpaths_for_writable_root(&root),
                root,
            }).collect()
        }
        // ...
    }
}
```

#### 3.2.2 默认只读子路径

```rust
fn default_read_only_subpaths_for_writable_root(
    writable_root: &AbsolutePathBuf,
) -> Vec<AbsolutePathBuf> {
    let mut subpaths: Vec<AbsolutePathBuf> = Vec::new();
    
    // 保护 .git 目录
    let top_level_git = writable_root.join(".git").expect(".git is valid");
    if top_level_git.as_path().is_dir() || top_level_git.as_path().is_file() {
        subpaths.push(top_level_git);
    }
    
    // 保护 .agents 和 .codex 目录
    for subdir in &[".agents", ".codex"] {
        let path = writable_root.join(subdir).expect("valid path");
        if path.as_path().is_dir() {
            subpaths.push(path);
        }
    }
    
    subpaths
}
```

### 3.3 Git 工作树支持

```rust
fn resolve_gitdir_from_file(dot_git: &AbsolutePathBuf) -> Option<AbsolutePathBuf> {
    // 读取 .git 文件内容（gitdir 指针）
    let contents = std::fs::read_to_string(dot_git.as_path()).ok()?;
    let trimmed = contents.trim();
    
    // 解析 gitdir: <path> 格式
    let (_, gitdir_raw) = trimmed.split_once(':')?;
    let gitdir_raw = gitdir_raw.trim();
    
    // 解析为绝对路径
    let base = dot_git.as_path().parent()?;
    let gitdir_path = AbsolutePathBuf::resolve_path_against_base(gitdir_raw, base).ok()?;
    
    if gitdir_path.as_path().exists() {
        Some(gitdir_path)
    } else {
        None
    }
}
```

### 3.4 错误处理

#### 3.4.1 CodexErrorInfo (Codex 错误信息)

```rust
pub enum CodexErrorInfo {
    ContextWindowExceeded,           // 上下文窗口超限
    UsageLimitExceeded,              // 使用限制超限
    ServerOverloaded,                // 服务器过载
    HttpConnectionFailed { http_status_code: Option<u16> },
    ResponseStreamConnectionFailed { http_status_code: Option<u16> },
    InternalServerError,
    Unauthorized,
    BadRequest,
    SandboxError,
    ResponseStreamDisconnected { http_status_code: Option<u16> },
    ResponseTooManyFailedAttempts { http_status_code: Option<u16> },
    ThreadRollbackFailed,
    Other,
}
```

#### 3.4.2 错误影响判断

```rust
impl CodexErrorInfo {
    /// 判断此错误是否应在重放历史时标记当前轮次为失败
    pub fn affects_turn_status(&self) -> bool {
        match self {
            Self::ThreadRollbackFailed => false,  // 回滚失败不影响轮次状态
            _ => true,  // 其他错误都影响
        }
    }
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 协议文件结构

```
codex-rs/protocol/src/
├── lib.rs                    # crate 入口，模块导出
├── protocol.rs               # 核心协议定义（本文件）
├── items.rs                  # TurnItem 定义（消息项）
├── approvals.rs              # 审批相关类型
├── permissions.rs            # 权限/沙盒策略
├── user_input.rs             # 用户输入类型
├── models.rs                 # 模型相关类型（ResponseItem 等）
├── config_types.rs           # 配置类型
├── dynamic_tools.rs          # 动态工具
├── request_permissions.rs    # 权限请求
├── request_user_input.rs     # 用户输入请求
├── mcp.rs                    # MCP 协议
├── plan_tool.rs              # 计划工具
├── memory_citation.rs        # 记忆引用
├── message_history.rs        # 消息历史
├── openai_models.rs          # OpenAI 模型定义
├── parse_command.rs          # 命令解析
├── num_format.rs             # 数字格式化
├── thread_id.rs              # 线程 ID
├── account.rs                # 账户相关
└── custom_prompts.rs         # 自定义提示词
```

### 4.2 核心调用路径

#### 4.2.1 TUI → Core 请求路径

```
tui/src/app.rs
  └─> 创建 Op (如 Op::UserTurn)
      └─> 通过 ThreadManager 发送
          └─> core/src/codex_thread.rs
              └─> core/src/codex.rs (process_submission)
                  └─> 处理 Op，生成 EventMsg
```

#### 4.2.2 Core → TUI 事件路径

```
core/src/codex.rs
  └─> 生成 EventMsg
      └─> 通过 channel 发送 Event
          └─> tui/src/app.rs (process_event)
              └─> 更新 UI 状态
```

#### 4.2.3 审批流程路径

```
core/src/tools/handlers/unified_exec.rs
  └─> 需要审批
      └─> 发送 ExecApprovalRequestEvent
          └─> tui/src/bottom_pane/approval_overlay.rs
              └─> 用户决策
                  └─> 发送 Op::ExecApproval
                      └─> core 继续执行
```

### 4.3 关键类型关系图

```
Submission
    ├── id: String
    ├── op: Op
    └── trace: Option<W3cTraceContext>

Op (30+ variants)
    ├── UserTurn { items, cwd, approval_policy, sandbox_policy, model, ... }
    ├── ExecApproval { id, decision }
    ├── RealtimeConversationStart(params)
    └── ...

Event
    ├── id: String (关联 Submission)
    └── msg: EventMsg

EventMsg (80+ variants)
    ├── TurnStarted / TurnComplete
    ├── AgentMessage / AgentMessageDelta
    ├── ExecCommandBegin / ExecCommandOutputDelta / ExecCommandEnd
    ├── ExecApprovalRequest
    ├── TokenCount
    └── ...
```

---

## 5. 依赖与外部交互

### 5.1 Crate 依赖

```toml
[dependencies]
# 内部依赖
codex-execpolicy = { workspace = true }      # 执行策略
codex-git = { workspace = true }             # Git 操作
codex-utils-absolute-path = { workspace = true }  # 绝对路径工具

# 序列化/反序列化
serde = { workspace = true, features = ["derive"] }
serde_json = { workspace = true }
serde_with = { workspace = true, features = ["macros", "base64"] }

# JSON Schema / TypeScript 生成
schemars = { workspace = true }
ts-rs = { workspace = true, features = ["uuid-impl", "serde-json-impl", "no-serde-warnings"] }

# 枚举工具
strum = { workspace = true }
strum_macros = { workspace = true }

# 国际化
icu_decimal = { workspace = true }
icu_locale_core = { workspace = true }
icu_provider = { workspace = true, features = ["sync"] }
sys-locale = { workspace = true }

# 日志/追踪
tracing = { workspace = true }

# UUID
uuid = { workspace = true, features = ["serde", "v7", "v4"] }
```

### 5.2 外部系统交互

| 系统 | 交互方式 | 协议部分 |
|------|---------|---------|
| **OpenAI API** | HTTP/SSE | `ResponseItem`, `ContentItem` |
| **MCP Servers** | stdio/sse | `McpInvocation`, `CallToolResult` |
| **Sandbox (Seatbelt/bwrap)** | 进程执行 | `SandboxPolicy`, `WritableRoot` |
| **Git** | 命令执行 | `GitInfo`, `GhostCommit` |
| **Telemetry** | OTLP/gRPC | `W3cTraceContext` |

### 5.3 协议版本兼容性

- **v1 协议**: 使用 `task_started`/`task_complete` 字段名
- **v2 协议**: 使用 `turn_started`/`turn_complete` 字段名
- **兼容策略**: 使用 `#[serde(alias = "...")]` 支持双版本

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 安全风险

| 风险点 | 严重程度 | 说明 |
|-------|---------|------|
| `DangerFullAccess` 模式 | **高** | 完全禁用沙盒，仅在受控环境使用 |
| `ExternalSandbox` 网络配置 | 中 | 依赖外部沙盒正确配置 |
| Git 工作树解析 | 低 | 符号链接可能导致路径遍历 |

#### 6.1.2 兼容性风险

| 风险点 | 说明 |
|-------|------|
| `EventMsg` 非穷尽 | `#[non_exhaustive]` 标记，未来可能新增变体 |
| 序列化字段变更 | 使用 `skip_serializing_if` 可能导致字段缺失 |
| TypeScript 类型生成 | `ts-rs` 生成可能不完全匹配 Rust 类型 |

### 6.2 边界情况

#### 6.2.1 沙盒边界

```rust
// 处理 TMPDIR 环境变量不存在的情况
if !exclude_tmpdir_env_var
    && let Some(tmpdir) = std::env::var_os("TMPDIR")
    && !tmpdir.is_empty()
{
    // 处理 TMPDIR
}
```

**边界**: `$TMPDIR` 可能未设置或为空，需要优雅降级。

#### 6.2.2 路径解析边界

```rust
fn resolve_candidate_path(path: &Path, cwd: &Path) -> Option<AbsolutePathBuf> {
    if path.is_absolute() {
        AbsolutePathBuf::from_absolute_path(path).ok()
    } else {
        AbsolutePathBuf::resolve_path_against_base(path, cwd).ok()
    }
}
```

**边界**: 相对路径解析可能失败（如 cwd 无效）。

#### 6.2.3 Token 计算边界

```rust
pub fn percent_of_context_window_remaining(&self, context_window: i64) -> i64 {
    if context_window <= BASELINE_TOKENS {
        return 0;  // 上下文窗口过小，直接返回 0
    }
    // ...
}
```

**边界**: `BASELINE_TOKENS` (12000) 是经验值，可能不适用于所有模型。

### 6.3 改进建议

#### 6.3.1 架构改进

| 建议 | 优先级 | 说明 |
|------|-------|------|
| 协议版本显式声明 | 中 | 在 `Submission` 中添加 `protocol_version` 字段 |
| 沙盒策略验证器 | 中 | 添加独立的策略验证工具 |
| 事件压缩 | 低 | 高频事件（如 `AgentMessageDelta`）支持批量发送 |

#### 6.3.2 代码改进

| 建议 | 优先级 | 说明 |
|------|-------|------|
| 文档完善 | 高 | 为复杂类型添加更多示例 |
| 测试覆盖 | 中 | 增加边界条件测试 |
| 错误细化 | 中 | `CodexErrorInfo::Other` 过于笼统 |

#### 6.3.3 安全改进

| 建议 | 优先级 | 说明 |
|------|-------|------|
| 审计日志 | 高 | 记录所有 `DangerFullAccess` 使用 |
| 策略变更通知 | 中 | 沙盒策略变更时通知用户 |
| 路径规范化 | 中 | 统一使用 `canonicalize` 防止路径遍历 |

### 6.4 测试策略

文件包含 **200+ 行测试代码**，覆盖：

- 沙盒策略语义一致性
- 细粒度审批配置序列化
- 文件系统策略与遗留策略桥接
- `ItemStartedEvent` 遗留事件生成

**测试文件**: `protocol.rs` 内嵌 `#[cfg(test)]` 模块

---

## 7. 总结

`protocol.rs` 是 Codex 系统的**核心契约文件**，定义了：

1. **30+ 种操作类型** (`Op`) - 客户端请求
2. **80+ 种事件类型** (`EventMsg`) - Agent 响应
3. **4 级沙盒策略** - 安全隔离
4. **5 种审批策略** - 人机协作
5. **完整的协作协议** - 多 Agent 支持

该文件的设计体现了以下原则：
- **类型安全**: 大量使用 Rust 类型系统防止错误
- **向后兼容**: 使用 `alias` 和 `default` 支持协议演进
- **跨语言**: 通过 `JsonSchema` + `ts-rs` 支持 TypeScript
- **可观测性**: 内置 W3C Trace Context 支持分布式追踪
