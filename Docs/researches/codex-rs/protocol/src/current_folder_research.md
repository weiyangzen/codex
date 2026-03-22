# Codex Protocol Crate 深度研究文档

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 1.1 定位与目标

`codex-protocol` crate 是 Codex 生态系统的**核心协议层**，承担以下关键职责：

- **类型定义中心**：定义所有跨 crate 通信的数据结构（内部 core↔tui 通信 + 外部 app-server 协议）
- **协议契约**：通过 SQ (Submission Queue) / EQ (Event Queue) 模式实现异步通信
- **序列化/反序列化**：提供 JSON/TypeScript 兼容的序列化支持（serde + ts-rs + schemars）
- **最小依赖原则**：保持极少的依赖，确保协议层稳定可靠

### 1.2 架构位置

```
┌─────────────────────────────────────────────────────────────┐
│                      调用方 (Consumers)                       │
├─────────────────────────────────────────────────────────────┤
│  codex-core  │  codex-tui  │  app-server  │  app-server-client │
└──────────────┴─────────────┴──────────────┴────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    codex-protocol (本 crate)                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │  protocol   │  │   models    │  │   config_types      │  │
│  │  (核心协议)  │  │  (模型相关)  │  │    (配置类型)        │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ permissions │  │  approvals  │  │   dynamic_tools     │  │
│  │  (权限系统)  │  │  (审批流程)  │  │    (动态工具)        │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      基础依赖 crates                         │
│     codex-execpolicy │ codex-git │ codex-utils-* │ mcp      │
└─────────────────────────────────────────────────────────────┘
```

### 1.3 核心使用场景

| 场景 | 说明 |
|------|------|
| **Core-TUI 通信** | codex-core 与 codex-tui 之间的内部事件传递 |
| **App Server 协议** | 与 codex app-server 的外部 API 交互 |
| **MCP 集成** | Model Context Protocol 类型定义 |
| **沙箱策略** | 文件系统/网络权限控制策略定义 |
| **审批流程** | 命令执行审批、补丁应用审批等 |

---

## 功能点目的

### 2.1 核心协议系统 (protocol.rs)

#### 2.1.1 SQ/EQ 通信模式

```rust
// Submission Queue Entry - 用户请求
pub struct Submission {
    pub id: String,      // 唯一标识，用于关联 Event
    pub op: Op,          // 操作类型
    pub trace: Option<W3cTraceContext>,  // W3C 分布式追踪
}

// Event Queue Entry - 代理响应
pub struct Event {
    pub id: String,      // 关联的 Submission id
    pub msg: EventMsg,   // 事件消息
}
```

#### 2.1.2 Op 枚举 - 用户操作类型

| 操作 | 用途 |
|------|------|
| `Interrupt` | 中止当前任务 |
| `CleanBackgroundTerminals` | 清理后台终端进程 |
| `RealtimeConversationStart/Audio/Text/Close` | 实时对话流控制 |
| `UserInput` | 传统用户输入（Legacy） |
| `UserTurn` | 完整的用户回合（推荐） |
| `OverrideTurnContext` | 覆盖回合上下文 |
| `ExecApproval/PatchApproval` | 执行/补丁审批 |
| `ResolveElicitation` | MCP 引导请求解析 |
| `DynamicToolResponse` | 动态工具响应 |
| `AddToHistory/GetHistoryEntryRequest` | 历史记录管理 |
| `ListMcpTools/RefreshMcpServers` | MCP 工具管理 |
| `Compact/DropMemories/UpdateMemories` | 记忆系统管理 |
| `Review` | 代码审查请求 |

#### 2.1.3 EventMsg 枚举 - 代理事件类型

**生命周期事件**：
- `TurnStarted/TurnComplete` - 回合开始/完成
- `TurnAborted` - 回合中止
- `SessionConfigured` - 会话配置完成
- `ShutdownComplete` - 关闭完成

**内容事件**：
- `AgentMessage/AgentMessageDelta` - 代理消息/增量
- `AgentReasoning/AgentReasoningDelta` - 推理内容/增量
- `UserMessage` - 用户消息回显

**工具执行事件**：
- `ExecCommandBegin/OutputDelta/End` - 命令执行生命周期
- `McpToolCallBegin/End` - MCP 工具调用
- `WebSearchBegin/End` - 网络搜索
- `ImageGenerationBegin/End` - 图像生成

**审批事件**：
- `ExecApprovalRequest` - 执行审批请求
- `ApplyPatchApprovalRequest` - 补丁审批请求
- `RequestPermissions` - 权限请求
- `GuardianAssessment` - Guardian 风险评估

**协作事件 (Collab)**：
- `CollabAgentSpawnBegin/End` - 代理生成
- `CollabAgentInteractionBegin/End` - 代理交互
- `CollabWaitingBegin/End` - 等待状态
- `CollabClose/Resume Begin/End` - 关闭/恢复

### 2.2 沙箱策略系统 (permissions.rs + protocol.rs)

#### 2.2.1 SandboxPolicy - 传统沙箱策略

```rust
pub enum SandboxPolicy {
    DangerFullAccess,           // 完全访问（危险）
    ReadOnly {                 // 只读访问
        access: ReadOnlyAccess,
        network_access: bool,
    },
    ExternalSandbox {          // 外部沙箱
        network_access: NetworkAccess,
    },
    WorkspaceWrite {           // 工作区写入（最常用）
        writable_roots: Vec<AbsolutePathBuf>,
        read_only_access: ReadOnlyAccess,
        network_access: bool,
        exclude_tmpdir_env_var: bool,
        exclude_slash_tmp: bool,
    },
}
```

#### 2.2.2 FileSystemSandboxPolicy - 新一代文件系统策略

```rust
pub struct FileSystemSandboxPolicy {
    pub kind: FileSystemSandboxKind,      // Unrestricted/Restricted/ExternalSandbox
    pub entries: Vec<FileSystemSandboxEntry>,
}

pub struct FileSystemSandboxEntry {
    pub path: FileSystemPath,             // 路径（普通或特殊）
    pub access: FileSystemAccessMode,     // None/Read/Write
}

pub enum FileSystemPath {
    Path { path: AbsolutePathBuf },
    Special { value: FileSystemSpecialPath },
}

pub enum FileSystemSpecialPath {
    Root,
    Minimal,                    // 平台默认最小集合
    CurrentWorkingDirectory,
    ProjectRoots { subpath: Option<PathBuf> },
    Tmpdir,
    SlashTmp,
    Unknown { path: String },   // 向前兼容
}
```

**关键特性**：
- 支持特殊路径标记（`:root`, `:minimal`, `:cwd`, `:project_roots`, `:tmpdir`, `:slash_tmp`）
- 路径特异性优先级（更具体的路径优先）
- 访问模式冲突解决（`None` > `Write` > `Read`）
- 自动保护敏感目录（`.git`, `.codex`, `.agents`）

### 2.3 审批系统 (approvals.rs)

#### 2.3.1 AskForApproval - 审批策略

```rust
pub enum AskForApproval {
    UnlessTrusted,              // 仅信任命令自动批准
    OnFailure,                  // 失败时询问（已弃用）
    OnRequest,                  // 模型决定何时询问（默认）
    Granular(GranularApprovalConfig),  // 细粒度控制
    Never,                      // 从不询问
}

pub struct GranularApprovalConfig {
    pub sandbox_approval: bool,       // 沙箱审批
    pub rules: bool,                  // execpolicy 规则审批
    pub skill_approval: bool,         // Skill 脚本审批
    pub request_permissions: bool,    // request_permissions 工具
    pub mcp_elicitations: bool,       MCP 引导
}
```

#### 2.3.2 审批请求/响应

```rust
pub struct ExecApprovalRequestEvent {
    pub call_id: String,
    pub approval_id: Option<String>,
    pub turn_id: String,
    pub command: Vec<String>,
    pub cwd: PathBuf,
    pub reason: Option<String>,
    pub network_approval_context: Option<NetworkApprovalContext>,
    pub proposed_execpolicy_amendment: Option<ExecPolicyAmendment>,
    pub proposed_network_policy_amendments: Option<Vec<NetworkPolicyAmendment>>,
    pub additional_permissions: Option<PermissionProfile>,
    pub skill_metadata: Option<ExecApprovalRequestSkillMetadata>,
    pub available_decisions: Option<Vec<ReviewDecision>>,
    pub parsed_cmd: Vec<ParsedCommand>,
}

pub enum ReviewDecision {
    Approved,
    ApprovedExecpolicyAmendment { proposed_execpolicy_amendment: ExecPolicyAmendment },
    ApprovedForSession,
    NetworkPolicyAmendment { network_policy_amendment: NetworkPolicyAmendment },
    Denied,
    Abort,
}
```

### 2.4 模型相关类型 (openai_models.rs + models.rs)

#### 2.4.1 模型元数据

```rust
pub struct ModelInfo {
    pub slug: String,
    pub display_name: String,
    pub description: Option<String>,
    pub default_reasoning_level: Option<ReasoningEffort>,
    pub supported_reasoning_levels: Vec<ReasoningEffortPreset>,
    pub shell_type: ConfigShellToolType,
    pub visibility: ModelVisibility,
    pub supported_in_api: bool,
    pub priority: i32,
    pub base_instructions: String,
    pub model_messages: Option<ModelMessages>,
    pub supports_reasoning_summaries: bool,
    pub truncation_policy: TruncationPolicyConfig,
    pub supports_parallel_tool_calls: bool,
    pub context_window: Option<i64>,
    pub input_modalities: Vec<InputModality>,  // Text/Image
}
```

#### 2.4.2 ReasoningEffort - 推理努力级别

```rust
pub enum ReasoningEffort {
    None, Minimal, Low, Medium, High, XHigh
}
```

#### 2.4.3 DeveloperInstructions - 开发者指令生成

根据沙箱策略和审批策略自动生成开发者指令：

```rust
impl DeveloperInstructions {
    pub fn from(
        approval_policy: AskForApproval,
        exec_policy: &Policy,
        exec_permission_approvals_enabled: bool,
        request_permissions_tool_enabled: bool,
    ) -> DeveloperInstructions;
    
    pub fn from_policy(
        sandbox_policy: &SandboxPolicy,
        approval_policy: AskForApproval,
        exec_policy: &Policy,
        cwd: &Path,
        ...
    ) -> Self;
}
```

### 2.5 MCP 集成 (mcp.rs)

```rust
pub struct Tool {
    pub name: String,
    pub title: Option<String>,
    pub description: Option<String>,
    pub input_schema: serde_json::Value,
    pub output_schema: Option<serde_json::Value>,
    pub annotations: Option<serde_json::Value>,
}

pub struct Resource {
    pub name: String,
    pub uri: String,
    pub mime_type: Option<String>,
    pub size: Option<i64>,
}

pub struct ResourceTemplate {
    pub uri_template: String,
    pub name: String,
}

pub struct CallToolResult {
    pub content: Vec<serde_json::Value>,
    pub structured_content: Option<serde_json::Value>,
    pub is_error: Option<bool>,
}

pub enum RequestId {
    String(String),
    Integer(i64),
}
```

### 2.6 协作模式 (config_types.rs)

```rust
pub struct CollaborationMode {
    pub mode: ModeKind,           // Plan/Default
    pub settings: Settings,
}

pub struct Settings {
    pub model: String,
    pub reasoning_effort: Option<ReasoningEffort>,
    pub developer_instructions: Option<String>,
}

pub enum ModeKind {
    Plan,      // 计划模式
    Default,   // 默认模式（原 code/pair_programming/execute/custom 的别名）
    #[doc(hidden)]
    PairProgramming,
    #[doc(hidden)]
    Execute,
}
```

### 2.7 用户输入 (user_input.rs)

```rust
pub enum UserInput {
    Text {
        text: String,
        text_elements: Vec<TextElement>,  // UI 特殊元素标记
    },
    Image { image_url: String },
    LocalImage { path: PathBuf },
    Skill { name: String, path: PathBuf },
    Mention { name: String, path: String },
}

pub struct TextElement {
    pub byte_range: ByteRange,        // UTF-8 字节范围
    placeholder: Option<String>,     // 占位符文本
}
```

### 2.8 回合项 (items.rs)

```rust
pub enum TurnItem {
    UserMessage(UserMessageItem),
    AgentMessage(AgentMessageItem),
    Plan(PlanItem),
    Reasoning(ReasoningItem),
    WebSearch(WebSearchItem),
    ImageGeneration(ImageGenerationItem),
    ContextCompaction(ContextCompactionItem),
}
```

---

## 具体技术实现

### 3.1 序列化策略

#### 3.1.1 标签化枚举序列化

```rust
#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, JsonSchema, TS)]
#[serde(tag = "type", rename_all = "snake_case")]
#[ts(tag = "type")]
pub enum EventMsg {
    Error(ErrorEvent),
    AgentMessage(AgentMessageEvent),
    // ...
}
```

序列化示例：
```json
{
  "type": "agent_message",
  "message": "Hello!",
  "phase": "final_answer"
}
```

#### 3.1.2 向后兼容处理

```rust
#[serde(default, skip_serializing_if = "Option::is_none")]
#[ts(optional)]
pub phase: Option<MessagePhase>,
```

#### 3.1.3 别名支持

```rust
#[serde(rename = "task_started", alias = "turn_started")]
TurnStarted(TurnStartedEvent),
```

### 3.2 沙箱策略实现细节

#### 3.2.1 路径解析流程

```rust
// 1. 解析特殊路径
fn resolve_file_system_special_path(
    value: &FileSystemSpecialPath,
    cwd: Option<&AbsolutePathBuf>,
) -> Option<AbsolutePathBuf> {
    match value {
        FileSystemSpecialPath::Root => None,  // 根路径单独处理
        FileSystemSpecialPath::CurrentWorkingDirectory => cwd.cloned(),
        FileSystemSpecialPath::Tmpdir => {
            std::env::var_os("TMPDIR")
                .and_then(|t| AbsolutePathBuf::from_absolute_path(PathBuf::from(&t)).ok())
        }
        // ...
    }
}

// 2. 解析条目路径
fn resolve_entry_path(
    path: &FileSystemPath,
    cwd: Option<&AbsolutePathBuf>,
) -> Option<AbsolutePathBuf> {
    match path {
        FileSystemPath::Special { value: FileSystemSpecialPath::Root } => {
            cwd.map(absolute_root_path_for_cwd)
        }
        _ => resolve_file_system_path(path, cwd),
    }
}
```

#### 3.2.2 访问权限解析

```rust
pub fn resolve_access_with_cwd(&self, path: &Path, cwd: &Path) -> FileSystemAccessMode {
    // 1. 非受限策略直接返回 Write
    if !matches!(self.kind, FileSystemSandboxKind::Restricted) {
        return FileSystemAccessMode::Write;
    }
    
    // 2. 解析目标路径
    let Some(path) = resolve_candidate_path(path, cwd) else {
        return FileSystemAccessMode::None;
    };
    
    // 3. 查找匹配的条目，按特异性排序
    self.resolved_entries_with_cwd(cwd)
        .into_iter()
        .filter(|entry| path.as_path().starts_with(entry.path.as_path()))
        .max_by_key(resolved_entry_precedence)
        .map(|entry| entry.access)
        .unwrap_or(FileSystemAccessMode::None)
}
```

#### 3.2.3 可写根计算

```rust
pub fn get_writable_roots_with_cwd(&self, cwd: &Path) -> Vec<WritableRoot> {
    // 1. 收集所有可写条目
    let writable_entries: Vec<AbsolutePathBuf> = resolved_entries
        .iter()
        .filter(|entry| entry.access.can_write())
        .map(|entry| entry.path.clone())
        .collect();
    
    // 2. 为每个可写根计算只读子路径
    writable_entries.into_iter().map(|root| {
        let mut read_only_subpaths = default_read_only_subpaths_for_writable_root(&root);
        
        // 添加显式非写条目作为只读子路径
        read_only_subpaths.extend(
            resolved_entries
                .iter()
                .filter(|entry| !entry.access.can_write())
                .filter_map(|entry| {
                    // 路径匹配逻辑...
                })
        );
        
        WritableRoot { root, read_only_subpaths }
    }).collect()
}
```

### 3.3 Token 使用统计

```rust
pub struct TokenUsage {
    pub input_tokens: i64,
    pub cached_input_tokens: i64,
    pub output_tokens: i64,
    pub reasoning_output_tokens: i64,
    pub total_tokens: i64,
}

impl TokenUsage {
    /// 用于显示的混合总数（非缓存输入 + 输出）
    pub fn blended_total(&self) -> i64 {
        (self.non_cached_input() + self.output_tokens.max(0)).max(0)
    }
    
    /// 计算上下文窗口剩余百分比
    pub fn percent_of_context_window_remaining(&self, context_window: i64) -> i64 {
        const BASELINE_TOKENS: i64 = 12000;  // 系统提示和工具开销
        if context_window <= BASELINE_TOKENS {
            return 0;
        }
        let effective_window = context_window - BASELINE_TOKENS;
        let used = (self.tokens_in_context_window() - BASELINE_TOKENS).max(0);
        let remaining = (effective_window - used).max(0);
        ((remaining as f64 / effective_window as f64) * 100.0).round() as i64
    }
}
```

### 3.4 ThreadId 实现

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, TS, Hash)]
#[ts(type = "string")]
pub struct ThreadId {
    uuid: Uuid,  // 内部使用 UUID v7
}

impl ThreadId {
    pub fn new() -> Self {
        Self { uuid: Uuid::now_v7() }  // UUID v7 包含时间戳，排序友好
    }
}

// 自定义序列化为字符串
impl Serialize for ThreadId {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.collect_str(&self.uuid)
    }
}
```

### 3.5 数字格式化

```rust
// 使用 ICU 进行本地化数字格式化
pub fn format_with_separators(n: i64) -> String {
    formatter().format(&Decimal::from(n)).to_string()
}

// SI 后缀格式化（1.2K, 3.4M）
pub fn format_si_suffix(n: i64) -> String {
    // 根据数值大小自动选择 K/M/G 后缀
    // 保持 3 位有效数字
}
```

---

## 关键代码路径与文件引用

### 4.1 文件结构

```
codex-rs/protocol/src/
├── lib.rs                    # crate 入口，模块声明
├── protocol.rs               # 核心协议类型（~4400 行）
│   ├── Submission/Event      # SQ/EQ 基础结构
│   ├── Op                    # 用户操作枚举
│   ├── EventMsg              # 代理事件枚举
│   ├── SandboxPolicy         # 沙箱策略
│   ├── AskForApproval        # 审批策略
│   ├── TokenUsage            # Token 统计
│   └── 大量事件类型定义
├── models.rs                 # 模型相关类型（~1000 行）
│   ├── ResponseItem          # API 响应项
│   ├── DeveloperInstructions # 开发者指令生成
│   ├── ContentItem           # 内容项
│   └── SandboxPermissions    # 沙箱权限
├── openai_models.rs          # OpenAI 模型元数据（~776 行）
│   ├── ModelInfo             # 模型信息
│   ├── ModelPreset           # 模型预设
│   ├── ReasoningEffort       # 推理努力级别
│   └── InputModality         # 输入模态
├── permissions.rs            # 文件系统权限（~1000+ 行）
│   ├── FileSystemSandboxPolicy
│   ├── FileSystemSandboxEntry
│   ├── FileSystemPath
│   └── FileSystemSpecialPath
├── approvals.rs              # 审批系统（~319 行）
│   ├── ExecApprovalRequestEvent
│   ├── GuardianAssessmentEvent
│   └── ReviewDecision
├── config_types.rs           # 配置类型（~563 行）
│   ├── CollaborationMode
│   ├── ModeKind
│   ├── ReasoningSummary
│   └── WebSearchConfig
├── items.rs                  # 回合项（~295 行）
│   └── TurnItem
├── user_input.rs             # 用户输入（~109 行）
│   └── UserInput
├── mcp.rs                    # MCP 类型（~328 行）
│   ├── Tool/Resource/ResourceTemplate
│   └── CallToolResult
├── dynamic_tools.rs          # 动态工具（~131 行）
├── plan_tool.rs              # 计划工具（~29 行）
├── thread_id.rs              # 线程 ID（~103 行）
├── account.rs                # 账户类型（~21 行）
├── memory_citation.rs        # 记忆引用（~20 行）
├── message_history.rs        # 消息历史（~11 行）
├── custom_prompts.rs         # 自定义提示（~20 行）
├── num_format.rs             # 数字格式化（~103 行）
├── parse_command.rs          # 命令解析（~31 行）
├── request_permissions.rs    # 权限请求（~74 行）
└── request_user_input.rs     # 用户输入请求（~55 行）

prompts/                      # 内联提示模板
├── base_instructions/default.md
├── permissions/
│   ├── approval_policy/
│   │   ├── never.md
│   │   ├── unless_trusted.md
│   │   ├── on_failure.md
│   │   ├── on_request_rule.md
│   │   └── on_request_rule_request_permission.md
│   └── sandbox_mode/
│       ├── danger_full_access.md
│       ├── read_only.md
│       └── workspace_write.md
└── realtime/
    ├── realtime_start.md
    └── realtime_end.md
```

### 4.2 关键类型关系图

```
┌─────────────────────────────────────────────────────────────────────┐
│                           通信顶层类型                               │
├─────────────────────────────────────────────────────────────────────┤
│  Submission ────────► Event                                         │
│  (用户请求)            (代理响应)                                    │
│       │                    │                                        │
│       ▼                    ▼                                        │
│  Op (操作)           EventMsg (事件)                                │
└─────────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌───────────────┐   ┌─────────────────┐   ┌─────────────────┐
│   用户输入     │   │    沙箱/权限     │   │    模型相关      │
├───────────────┤   ├─────────────────┤   ├─────────────────┤
│ UserInput     │   │ SandboxPolicy   │   │ ModelInfo       │
│ TurnItem      │   │ FileSystemSandbox│  │ ReasoningEffort │
│ TextElement   │   │ NetworkSandbox  │   │ CollaborationMode│
└───────────────┘   │ AskForApproval  │   │ DeveloperInstr  │
                    │ ReviewDecision  │   └─────────────────┘
                    └─────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌───────────────┐   ┌─────────────────┐   ┌─────────────────┐
│   MCP 集成     │   │    工具相关      │   │    会话管理      │
├───────────────┤   ├─────────────────┤   ├─────────────────┤
│ Tool          │   │ ResponseItem    │   │ ThreadId        │
│ Resource      │   │ DynamicToolSpec │   │ SessionMeta     │
│ CallToolResult│   │ UpdatePlanArgs  │   │ TurnContextItem │
└───────────────┘   └─────────────────┘   └─────────────────┘
```

### 4.3 核心常量

```rust
// 用户指令标签
pub const USER_INSTRUCTIONS_OPEN_TAG: &str = "<user_instructions>";
pub const USER_INSTRUCTIONS_CLOSE_TAG: &str = "</user_instructions>";
pub const ENVIRONMENT_CONTEXT_OPEN_TAG: &str = "<environment_context>";
pub const APPS_INSTRUCTIONS_OPEN_TAG: &str = "<apps_instructions>";
pub const SKILLS_INSTRUCTIONS_OPEN_TAG: &str = "<skills_instructions>";
pub const COLLABORATION_MODE_OPEN_TAG: &str = "<collaboration_mode>";
pub const REALTIME_CONVERSATION_OPEN_TAG: &str = "<realtime_conversation>";
pub const USER_MESSAGE_BEGIN: &str = "## My request for Codex:";

// Token 计算基准
const BASELINE_TOKENS: i64 = 12000;  // 系统提示和工具开销

// 用户输入限制
pub const MAX_USER_INPUT_TEXT_CHARS: usize = 1 << 20;  // 1MB
```

---

## 依赖与外部交互

### 5.1 外部依赖

```toml
[dependencies]
# 内部 crates
codex-execpolicy = { workspace = true }      # 执行策略
codex-git = { workspace = true }             # Git 操作
codex-utils-absolute-path = { workspace = true }  # 绝对路径工具
codex-utils-image = { workspace = true }     # 图像处理

# 序列化/反序列化
serde = { workspace = true, features = ["derive"] }
serde_json = { workspace = true }
serde_with = { workspace = true, features = ["macros", "base64"] }
schemars = { workspace = true }              # JSON Schema 生成
ts-rs = { workspace = true, features = ["uuid-impl", "serde-json-impl"] }  # TypeScript 类型生成

# ICU 本地化
icu_decimal = { workspace = true }           # 数字格式化
icu_locale_core = { workspace = true }
icu_provider = { workspace = true, features = ["sync"] }
sys-locale = { workspace = true }            # 系统区域检测

# 工具
strum = { workspace = true }                 # 枚举工具
strum_macros = { workspace = true }
tracing = { workspace = true }               # 日志追踪
uuid = { workspace = true, features = ["serde", "v7", "v4"] }
```

### 5.2 消费者 crates

| Crate | 用途 |
|-------|------|
| `codex-core` | 核心逻辑，大量使用 protocol 类型 |
| `codex-tui` | 终端 UI，处理 EventMsg 显示 |
| `codex-app-server` | App Server，协议转换 |
| `codex-app-server-client` | App Server 客户端 |
| `codex-backend-client` | 后端客户端，使用 ModelInfo 等 |
| `codex-shell-escalation` | Shell 权限提升，使用 EscalationPermissions |
| `codex-windows-sandbox-rs` | Windows 沙箱，使用 SandboxPolicy |
| `codex-shell-command` | Shell 命令，使用 ParsedCommand |

### 5.3 协议版本兼容性

- **v1 格式**：使用 `task_started`/`task_complete` 等旧名称
- **v2 格式**：使用 `turn_started`/`turn_complete` 等新名称
- **兼容处理**：通过 `#[serde(alias = "...")]` 支持双向兼容

---

## 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 沙箱策略复杂性

**风险**：`FileSystemSandboxPolicy` 和 `SandboxPolicy` 双轨并行，转换逻辑复杂

```rust
// 转换可能失败的情况
pub fn to_legacy_sandbox_policy(...) -> io::Result<SandboxPolicy> {
    // 非工作区写入会返回错误
    if !workspace_root_writable && (!writable_roots.is_empty() || tmpdir_writable) {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "filesystem writes outside the workspace root...",
        ));
    }
}
```

**缓解**：
- 充分的单元测试覆盖（protocol.rs 中有 100+ 测试）
- 语义签名比较确保转换正确性

#### 6.1.2 枚举扩展兼容性

**风险**：`#[non_exhaustive]` 标记的 Op 枚举在跨 crate 匹配时需要处理 `_`

**建议**：
- 新增 Op 变体时确保消费者 crate 正确处理
- 考虑使用 `Op::kind()` 进行字符串匹配而非枚举匹配

#### 6.1.3 路径解析安全性

**风险**：符号链接可能导致路径逃逸

**缓解措施**：
```rust
// 保留原始路径以便下游沙箱检测符号链接
let raw_carveout_path = if preserve_raw_carveout_paths {
    if entry.path.as_path().starts_with(root.as_path()) {
        Some(entry.path.clone())
    } else { ... }
};
```

### 6.2 边界情况

#### 6.2.1 Token 计算边界

```rust
// 当上下文窗口小于基准值时
pub fn percent_of_context_window_remaining(&self, context_window: i64) -> i64 {
    if context_window <= BASELINE_TOKENS {
        return 0;  // 直接返回 0，可能误导用户
    }
    // ...
}
```

#### 6.2.2 审批决策默认值

```rust
impl Default for ReviewDecision {
    fn default() -> Self {
        ReviewDecision::Denied  // 默认拒绝，安全但可能意外
    }
}
```

#### 6.2.3 特殊路径 Unknown 处理

```rust
FileSystemSpecialPath::Unknown { path, subpath } => {
    // 旧版本运行时忽略，新版本处理
    // 需要确保配置向前兼容
}
```

### 6.3 改进建议

#### 6.3.1 类型安全改进

**现状**：许多字段使用 `Option<String>` 和 `Option<PathBuf>`

**建议**：
```rust
// 使用 Newtype 模式增强类型安全
pub struct ThreadName(String);
pub struct ModelSlug(String);

// 使用 NonEmptyVec 确保非空
pub struct NonEmptyVec<T>(Vec<T>);
```

#### 6.3.2 文档改进

**现状**：复杂类型（如 `SandboxPolicy`）的行为文档分散

**建议**：
- 为每个策略变体添加使用示例
- 添加更多 `doc = include_str!(...)` 内联文档

#### 6.3.3 测试覆盖

**现状**：已有良好测试覆盖，但某些边界情况可加强

**建议**：
```rust
// 添加模糊测试
#[cfg(fuzzing)]
mod fuzz_tests {
    use super::*;
    
    fuzz_target!(|data: &[u8]| {
        // 测试 FileSystemSandboxPolicy 的解析鲁棒性
    });
}
```

#### 6.3.4 性能优化

**现状**：`get_writable_roots_with_cwd` 等函数在每次调用时重新计算

**建议**：
```rust
pub struct CachedSandboxPolicy {
    policy: FileSystemSandboxPolicy,
    cwd: AbsolutePathBuf,
    // 缓存计算结果
    cached_writable_roots: Vec<WritableRoot>,
    cached_readable_roots: Vec<AbsolutePathBuf>,
}
```

#### 6.3.5 错误处理改进

**现状**：某些转换使用 `io::Error` 作为通用错误类型

**建议**：
```rust
#[derive(Debug, thiserror::Error)]
pub enum PolicyConversionError {
    #[error("non-workspace writes not supported: {0}")]
    NonWorkspaceWrite(PathBuf),
    #[error("invalid path: {0}")]
    InvalidPath(String),
}
```

### 6.4 技术债务追踪

| 位置 | 描述 | 优先级 |
|------|------|--------|
| `protocol.rs:572` | `OnFailure` 策略已弃用，待移除 | 低 |
| `protocol.rs:1774` | `model_context_window` 应为非 Option | 中 |
| `models.rs:300-306` | `end_turn` 字段不应直接使用 | 低 |
| `config_types.rs:325-333` | `PairProgramming`/`Execute` 隐藏变体待清理 | 低 |

---

## 总结

`codex-protocol` crate 是 Codex 生态系统的**基石**，其设计遵循以下原则：

1. **单一职责**：仅定义类型，不包含业务逻辑
2. **向后兼容**：通过 serde 特性确保版本兼容
3. **类型安全**：大量使用枚举和强类型
4. **跨平台**：支持 JSON/TypeScript 互操作
5. **最小依赖**：保持轻量，减少依赖风险

该 crate 的稳定性对整个 Codex 项目至关重要，任何修改都需要谨慎评估对下游消费者的影响。
