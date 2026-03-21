# codex-rs/protocol 研究文档

## 概述

`codex-protocol` 是 Codex CLI 的协议类型定义 crate，负责定义 `codex-core` 与 `codex-tui` 之间的内部通信协议，以及与 `codex app-server` 交互的外部协议类型。该 crate 设计为最小依赖，不包含业务逻辑，仅提供类型定义和序列化支持。

---

## 场景与职责

### 核心职责

1. **协议类型定义**: 定义 Codex 会话中所有核心数据结构，包括请求（Submission/Op）和响应（Event/EventMsg）
2. **跨 crate 通信**: 作为 `codex-core`、`codex-tui`、`app-server` 之间的共享类型契约
3. **序列化支持**: 提供 JSON Schema 和 TypeScript 类型生成（通过 `schemars` 和 `ts-rs`）
4. **沙箱策略定义**: 定义文件系统和网络沙箱策略的核心类型
5. **MCP 协议适配**: 定义与 Model Context Protocol (MCP) 交互的类型

### 使用场景

- **TUI 与 Core 通信**: TUI 通过 Submission 发送用户操作，接收 Event 流更新
- **App Server API**: 为外部客户端提供类型安全的协议接口
- **持久化存储**: RolloutItem、SessionMeta 等类型用于会话历史持久化
- **沙箱执行**: SandboxPolicy、FileSystemSandboxPolicy 用于权限控制

---

## 功能点目的

### 1. 核心协议类型 (protocol.rs)

#### Submission Queue (SQ) / Event Queue (EQ) 模式

```rust
// 用户请求封装
pub struct Submission {
    pub id: String,
    pub op: Op,
    pub trace: Option<W3cTraceContext>,
}

// 代理事件封装
pub struct Event {
    pub id: String,
    pub msg: EventMsg,
}
```

**设计意图**: 使用异步队列模式解耦用户输入和代理响应，支持流式处理和取消操作。

#### Op 枚举 - 用户操作类型

| 操作类型 | 用途 |
|---------|------|
| `Interrupt` | 中断当前任务 |
| `UserTurn` | 用户新一轮输入（推荐方式） |
| `UserInput` | 传统用户输入（向后兼容） |
| `ExecApproval` | 批准命令执行 |
| `PatchApproval` | 批准代码补丁 |
| `RealtimeConversationStart` | 启动实时语音对话 |
| `ListMcpTools` | 列出 MCP 工具 |
| `Compact` | 请求上下文压缩 |
| `Review` | 请求代码审查 |

#### EventMsg 枚举 - 代理事件类型

| 事件类型 | 用途 |
|---------|------|
| `TurnStarted/TurnComplete` | 回合生命周期 |
| `AgentMessage` | 代理文本输出 |
| `AgentReasoning` | 推理过程展示 |
| `ExecCommandBegin/End` | 命令执行生命周期 |
| `ExecApprovalRequest` | 请求用户批准 |
| `TokenCount` | Token 使用统计 |
| `McpToolCallBegin/End` | MCP 工具调用 |
| `CollabAgentSpawnBegin/End` | 协作代理生命周期 |

### 2. 沙箱策略系统

#### SandboxPolicy (protocol.rs)

```rust
pub enum SandboxPolicy {
    DangerFullAccess,           // 完全访问（危险）
    ReadOnly { access, network_access },  // 只读
    ExternalSandbox { network_access },   // 外部沙箱
    WorkspaceWrite { ... },     // 工作区写入（最常用）
}
```

#### FileSystemSandboxPolicy (permissions.rs)

更细粒度的文件系统权限控制：

```rust
pub struct FileSystemSandboxPolicy {
    pub kind: FileSystemSandboxKind,  // Restricted/Unrestricted/ExternalSandbox
    pub entries: Vec<FileSystemSandboxEntry>,
}

pub struct FileSystemSandboxEntry {
    pub path: FileSystemPath,         // 路径或特殊标记
    pub access: FileSystemAccessMode, // Read/Write/None
}
```

**特殊路径标记**:
- `:root` - 文件系统根
- `:minimal` - 最小平台默认路径
- `:cwd` - 当前工作目录
- `:project_roots` - 项目根目录
- `:tmpdir` - 临时目录
- `:slash_tmp` - /tmp 目录

### 3. 模型相关类型 (openai_models.rs, models.rs)

#### ModelInfo

```rust
pub struct ModelInfo {
    pub slug: String,
    pub display_name: String,
    pub supported_reasoning_levels: Vec<ReasoningEffortPreset>,
    pub shell_type: ConfigShellToolType,
    pub truncation_policy: TruncationPolicyConfig,
    pub input_modalities: Vec<InputModality>,
    // ...
}
```

#### ReasoningEffort

支持多级推理努力度：`None` < `Minimal` < `Low` < `Medium` < `High` < `XHigh`

### 4. MCP 协议适配 (mcp.rs)

定义与 Model Context Protocol 服务器交互的类型：

```rust
pub struct Tool {
    pub name: String,
    pub input_schema: serde_json::Value,
    pub annotations: Option<serde_json::Value>,
    // ...
}

pub struct CallToolResult {
    pub content: Vec<serde_json::Value>,
    pub is_error: Option<bool>,
    // ...
}
```

### 5. 协作模式 (config_types.rs)

```rust
pub struct CollaborationMode {
    pub mode: ModeKind,      // Plan / Default
    pub settings: Settings,
}

pub struct Settings {
    pub model: String,
    pub reasoning_effort: Option<ReasoningEffort>,
    pub developer_instructions: Option<String>,
}
```

---

## 具体技术实现

### 关键数据结构

#### ThreadId (thread_id.rs)

使用 UUID v7 的线程标识符，支持时间排序：

```rust
pub struct ThreadId {
    uuid: Uuid,  // UUID v7 (时间排序)
}
```

#### TokenUsage (protocol.rs)

Token 使用统计，支持缓存计算：

```rust
pub struct TokenUsage {
    pub input_tokens: i64,
    pub cached_input_tokens: i64,
    pub output_tokens: i64,
    pub reasoning_output_tokens: i64,
    pub total_tokens: i64,
}
```

#### TurnItem (items.rs)

回合内项目的统一表示：

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

### 关键流程

#### 1. 沙箱权限解析流程

```
FileSystemSandboxPolicy::resolve_access_with_cwd(path, cwd)
  ↓
resolve_candidate_path(path, cwd)  // 解析为绝对路径
  ↓
resolved_entries_with_cwd(cwd)     // 获取解析后的条目
  ↓
max_by_key(resolved_entry_precedence)  // 选择最具体的匹配
```

**优先级规则**: 路径越具体优先级越高，同级别按 `None > Write > Read` 排序。

#### 2. 开发者指令生成 (models.rs)

```rust
DeveloperInstructions::from_policy(
    sandbox_policy,
    approval_policy,
    exec_policy,
    cwd,
    ...
)
```

根据沙箱策略和批准策略生成给模型的系统指令，包括：
- 沙箱模式说明
- 网络访问状态
- 批准策略指导
- 可写根目录列表

#### 3. FunctionCallOutputPayload 序列化

支持两种输出格式：

```rust
pub enum FunctionCallOutputBody {
    Text(String),                    // 纯文本输出
    ContentItems(Vec<FunctionCallOutputContentItem>),  // 结构化内容
}
```

序列化时自动选择格式：纯文本直接序列化为字符串，内容项序列化为数组。

### 协议常量

```rust
// 用户指令标签
pub const USER_INSTRUCTIONS_OPEN_TAG: &str = "<user_instructions>";
pub const USER_INSTRUCTIONS_CLOSE_TAG: &str = "</user_instructions>";

// 环境上下文标签
pub const ENVIRONMENT_CONTEXT_OPEN_TAG: &str = "<environment_context>";

// 实时对话标签
pub const REALTIME_CONVERSATION_OPEN_TAG: &str = "<realtime_conversation>";

// 协作模式标签
pub const COLLABORATION_MODE_OPEN_TAG: &str = "<collaboration_mode>";
```

---

## 关键代码路径与文件引用

### 文件结构

```
codex-rs/protocol/
├── Cargo.toml           # 依赖定义
├── BUILD.bazel          # Bazel 构建配置
├── README.md            # 模块说明
└── src/
    ├── lib.rs           # 模块导出
    ├── protocol.rs      # 核心协议类型 (~4000 行)
    ├── models.rs        # 模型相关类型 (~2000 行)
    ├── permissions.rs   # 沙箱权限系统 (~1000 行)
    ├── items.rs         # TurnItem 定义 (~300 行)
    ├── config_types.rs  # 配置类型 (~560 行)
    ├── approvals.rs     # 批准请求类型 (~320 行)
    ├── openai_models.rs # OpenAI 模型元数据 (~776 行)
    ├── mcp.rs           # MCP 协议适配 (~328 行)
    ├── user_input.rs    # 用户输入类型 (~109 行)
    ├── thread_id.rs     # 线程 ID 类型 (~103 行)
    ├── dynamic_tools.rs # 动态工具 (~131 行)
    ├── message_history.rs # 消息历史 (~11 行)
    ├── memory_citation.rs # 记忆引用 (~20 行)
    ├── plan_tool.rs     # 计划工具 (~29 行)
    ├── account.rs       # 账户类型 (~21 行)
    ├── parse_command.rs # 命令解析 (~31 行)
    ├── num_format.rs    # 数字格式化 (~103 行)
    ├── custom_prompts.rs # 自定义提示 (~20 行)
    ├── request_permissions.rs # 权限请求 (~74 行)
    └── request_user_input.rs  # 用户输入请求 (~55 行)
```

### 关键类型引用图

```
protocol.rs
├── Submission → Op
├── Event → EventMsg
├── SandboxPolicy → ReadOnlyAccess
├── TokenUsage
└── SessionMeta → ThreadId

models.rs
├── ResponseItem → ContentItem
├── ResponseInputItem
├── DeveloperInstructions → SandboxMode
├── FunctionCallOutputPayload
└── ShellToolCallParams

permissions.rs
├── FileSystemSandboxPolicy
├── FileSystemSandboxEntry
├── FileSystemPath → FileSystemSpecialPath
└── FileSystemAccessMode

items.rs
└── TurnItem → UserMessageItem/AgentMessageItem/...
```

---

## 依赖与外部交互

### 内部依赖

| Crate | 用途 |
|-------|------|
| `codex-execpolicy` | 执行策略类型 |
| `codex-git` | GhostCommit 类型 |
| `codex-utils-absolute-path` | AbsolutePathBuf |
| `codex-utils-image` | 图像处理 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `serde` | 序列化/反序列化 |
| `schemars` | JSON Schema 生成 |
| `ts-rs` | TypeScript 类型生成 |
| `uuid` | UUID v7 生成 |
| `strum` | 枚举工具 |
| `icu_decimal` | 本地化数字格式化 |

### 下游使用者

根据 Cargo.toml 依赖分析，以下 crate 依赖 `codex-protocol`:

- `codex-core` - 核心逻辑
- `codex-tui` - 终端 UI
- `app-server` - 应用服务器
- `app-server-client` - 应用服务器客户端
- `backend-client` - 后端客户端
- `shell-escalation` - Shell 权限提升
- `shell-command` - Shell 命令执行
- `exec` - 执行引擎
- `mcp-server` - MCP 服务器
- `feedback` - 反馈系统
- `state` - 状态管理
- `hooks` - 钩子系统

---

## 风险、边界与改进建议

### 已知风险

1. **向后兼容性**: `EventMsg` 和 `Op` 枚举的变体变更会影响所有下游 crate
   - 缓解: 使用 `#[non_exhaustive]` 和 `#[serde(default)]`

2. **序列化兼容性**: TypeScript 客户端依赖生成的类型定义
   - 缓解: `ts-rs` 生成确保类型同步

3. **沙箱策略复杂性**: `FileSystemSandboxPolicy` 与 `SandboxPolicy` 的双层设计容易混淆
   - 风险: 权限计算不一致可能导致安全漏洞

### 边界情况

1. **路径解析**: `resolve_candidate_path` 对相对路径的处理依赖于 cwd 的有效性
2. **Token 计算**: `BASELINE_TOKENS` 常数 (12000) 需要随模型更新调整
3. **MCP 适配**: `from_mcp_value` 转换可能丢失部分字段

### 改进建议

1. **类型安全**: 考虑使用 newtype 模式包装原始字符串 ID（如 `SubmissionId`、`TurnId`）

2. **文档**: 增加更多架构层面的文档，说明各类型之间的关系

3. **测试**: 增加跨 crate 的协议兼容性测试

4. **沙箱策略**: 考虑统一 `SandboxPolicy` 和 `FileSystemSandboxPolicy`，减少概念重复

5. **性能**: `TokenUsage::percent_of_context_window_remaining` 中的浮点运算可考虑优化

6. **国际化**: `num_format.rs` 中的数字格式化依赖系统 locale，可能需要更明确的控制

---

## 测试覆盖

主要测试位于各模块的 `#[cfg(test)]` 部分：

- `protocol.rs`: ~1000 行测试代码，覆盖沙箱策略、Token 计算、事件转换
- `models.rs`: ~900 行测试代码，覆盖模型指令生成、序列化
- `permissions.rs`: 集成在 `protocol.rs` 测试中
- `mcp.rs`: 资源大小反序列化测试
- `dynamic_tools.rs`: 动态工具规范反序列化测试
- `config_types.rs`: 协作模式掩码应用测试

---

## 总结

`codex-protocol` 是 Codex 系统的类型契约层，其设计原则是：

1. **最小依赖**: 避免业务逻辑，专注类型定义
2. **序列化优先**: 所有类型都支持 JSON 和 TypeScript 生成
3. **向后兼容**: 使用 serde 的默认值和别名机制
4. **安全敏感**: 沙箱策略类型需要仔细审查

理解该 crate 是理解整个 Codex 系统数据流的基础。
