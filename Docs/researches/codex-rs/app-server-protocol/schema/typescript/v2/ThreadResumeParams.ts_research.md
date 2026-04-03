# ThreadResumeParams Research

## TypeScript Schema

```typescript
/**
 * There are three ways to resume a thread:
 * 1. By thread_id: load the thread from disk by thread_id and resume it.
 * 2. By history: instantiate the thread from memory and resume it.
 * 3. By path: load the thread from disk by path and resume it.
 *
 * The precedence is: history > path > thread_id.
 * If using history or path, the thread_id param will be ignored.
 *
 * Prefer using thread_id whenever possible.
 */
export type ThreadResumeParams = {
    threadId: string, 
    /**
     * [UNSTABLE] FOR CODEX CLOUD - DO NOT USE.
     * If specified, the thread will be resumed with the provided history
     * instead of loaded from disk.
     */
    history?: Array<ResponseItem> | null, 
    /**
     * [UNSTABLE] Specify the rollout path to resume from.
     * If specified, the thread_id param will be ignored.
     */
    path?: string | null, 
    /**
     * Configuration overrides for the resumed thread, if any.
     */
    model?: string | null, 
    modelProvider?: string | null, 
    serviceTier?: ServiceTier | null | null, 
    cwd?: string | null, 
    approvalPolicy?: AskForApproval | null, 
    /**
     * Override where approval requests are routed for review on this thread
     * and subsequent turns.
     */
    approvalsReviewer?: ApprovalsReviewer | null, 
    sandbox?: SandboxMode | null, 
    config?: { [key in string]?: JsonValue } | null, 
    baseInstructions?: string | null, 
    developerInstructions?: string | null, 
    personality?: Personality | null, 
    /**
     * If true, persist additional rollout EventMsg variants required to
     * reconstruct a richer thread history on subsequent resume/fork/read.
     */
    persistExtendedHistory: boolean
};
```

## 场景与职责

`ThreadResumeParams` 是 `thread/resume` RPC 方法的请求参数类型，用于恢复之前创建的线程。该类型支持三种不同的恢复方式，并提供丰富的配置覆盖选项。

### 使用场景

1. **会话恢复**: 用户重新打开之前关闭的对话，恢复上下文
2. **历史加载**: 从磁盘加载持久化的线程历史记录
3. **内存恢复**: 从内存中的历史数据直接恢复（Codex Cloud 场景）
4. **路径恢复**: 从指定的文件路径加载线程数据
5. **配置调整**: 在恢复时修改线程的配置参数

### 职责

- 支持三种恢复方式（thread_id、history、path），按优先级自动选择
- 提供丰富的配置覆盖选项，允许在恢复时调整线程行为
- 支持实验性功能（如 `persistExtendedHistory`）
- 为 Codex Cloud 提供专门的内存恢复能力

## 功能点目的

### 核心功能

1. **多模式恢复**: 支持从 ID、历史数据或文件路径恢复线程
2. **配置覆盖**: 允许在恢复时覆盖原始线程的配置
3. **灵活性**: 适应不同的部署场景（本地、云端）
4. **向后兼容**: 优先使用 thread_id，确保与现有代码兼容

### 恢复方式优先级

```
history > path > thread_id
```

- 如果提供了 `history`，则使用内存中的历史数据恢复
- 否则如果提供了 `path`，则从指定路径加载
- 否则使用 `threadId` 从默认位置加载

### 设计考量

- `threadId` 是必填字段，作为默认恢复标识
- `history` 和 `path` 标记为 `[UNSTABLE]`，主要用于 Codex Cloud
- 所有配置字段都是可选的，允许部分覆盖
- `persistExtendedHistory` 为实验性功能，控制历史记录的详细程度

## 具体技术实现

### 数据结构

```rust
#[derive(
    Serialize, Deserialize, Debug, Default, Clone, PartialEq, JsonSchema, TS, ExperimentalApi,
)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
/// There are three ways to resume a thread:
/// 1. By thread_id: load the thread from disk by thread_id and resume it.
/// 2. By history: instantiate the thread from memory and resume it.
/// 3. By path: load the thread from disk by path and resume it.
///
/// The precedence is: history > path > thread_id.
/// If using history or path, the thread_id param will be ignored.
///
/// Prefer using thread_id whenever possible.
pub struct ThreadResumeParams {
    pub thread_id: String,

    /// [UNSTABLE] FOR CODEX CLOUD - DO NOT USE.
    /// If specified, the thread will be resumed with the provided history
    /// instead of loaded from disk.
    #[experimental("thread/resume.history")]
    #[ts(optional = nullable)]
    pub history: Option<Vec<ResponseItem>>,

    /// [UNSTABLE] Specify the rollout path to resume from.
    /// If specified, the thread_id param will be ignored.
    #[experimental("thread/resume.path")]
    #[ts(optional = nullable)]
    pub path: Option<PathBuf>,

    /// Configuration overrides for the resumed thread, if any.
    #[ts(optional = nullable)]
    pub model: Option<String>,
    #[ts(optional = nullable)]
    pub model_provider: Option<String>,
    #[serde(
        default,
        deserialize_with = "super::serde_helpers::deserialize_double_option",
        serialize_with = "super::serde_helpers::serialize_double_option",
        skip_serializing_if = "Option::is_none"
    )]
    #[ts(optional = nullable)]
    pub service_tier: Option<Option<ServiceTier>>,
    #[ts(optional = nullable)]
    pub cwd: Option<String>,
    #[experimental(nested)]
    #[ts(optional = nullable)]
    pub approval_policy: Option<AskForApproval>,
    /// Override where approval requests are routed for review on this thread
    /// and subsequent turns.
    #[ts(optional = nullable)]
    pub approvals_reviewer: Option<ApprovalsReviewer>,
    #[ts(optional = nullable)]
    pub sandbox: Option<SandboxMode>,
    #[ts(optional = nullable)]
    pub config: Option<HashMap<String, serde_json::Value>>,
    #[ts(optional = nullable)]
    pub base_instructions: Option<String>,
    #[ts(optional = nullable)]
    pub developer_instructions: Option<String>,
    #[ts(optional = nullable)]
    pub personality: Option<Personality>,
    /// If true, persist additional rollout EventMsg variants required to
    /// reconstruct a richer thread history on subsequent resume/fork/read.
    #[experimental("thread/resume.persistFullHistory")]
    #[serde(default)]
    pub persist_extended_history: bool,
}
```

### 字段说明

#### 恢复标识字段

| 字段 | 类型 | 说明 | 实验性 |
|------|------|------|--------|
| `threadId` | `string` | 线程唯一标识符（必填） | 否 |
| `history` | `Array<ResponseItem> \| null` | 内存中的历史数据 | `thread/resume.history` |
| `path` | `string \| null` | 线程数据文件路径 | `thread/resume.path` |

#### 配置覆盖字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `model` | `string \| null` | 覆盖模型名称 |
| `modelProvider` | `string \| null` | 覆盖模型提供商 |
| `serviceTier` | `ServiceTier \| null \| null` | 覆盖服务层级 |
| `cwd` | `string \| null` | 覆盖工作目录 |
| `approvalPolicy` | `AskForApproval \| null` | 覆盖审批策略 |
| `approvalsReviewer` | `ApprovalsReviewer \| null` | 覆盖审批审核者 |
| `sandbox` | `SandboxMode \| null` | 覆盖沙盒模式 |
| `config` | `object \| null` | 额外的配置覆盖 |
| `baseInstructions` | `string \| null` | 覆盖基础指令 |
| `developerInstructions` | `string \| null` | 覆盖开发者指令 |
| `personality` | `Personality \| null` | 覆盖人格设置 |

#### 实验性字段

| 字段 | 类型 | 说明 | 实验性 |
|------|------|------|--------|
| `persistExtendedHistory` | `boolean` | 持久化扩展历史记录 | `thread/resume.persistFullHistory` |

### 相关类型

#### ServiceTier

```typescript
export type ServiceTier = "default" | "flex";
```

#### AskForApproval

```typescript
export type AskForApproval = 
    | { type: "unlessTrusted" }
    | { type: "onFailure" }
    | { type: "onRequest" }
    | { type: "granular", sandboxApproval: boolean, rules: boolean, skillApproval: boolean, requestPermissions: boolean, mcpElicitations: boolean }
    | { type: "never" };
```

#### ApprovalsReviewer

```typescript
export type ApprovalsReviewer = "user" | "guardianSubagent";
```

#### SandboxMode

```typescript
export type SandboxMode = "readOnly" | "workspaceWrite" | "dangerFullAccess";
```

#### Personality

```typescript
export type Personality = "balanced" | "creative" | "precise";
```

## 关键代码路径与文件引用

### 协议定义

- **Rust 定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 2544-2611)
- **TypeScript 生成**: `codex-rs/app-server-protocol/schema/typescript/v2/ThreadResumeParams.ts`
- **JSON Schema**: `codex-rs/app-server-protocol/schema/json/v2/ThreadResumeParams.json`

### 相关协议类型

| 类型 | 说明 |
|------|------|
| `ThreadResumeResponse` | 恢复请求的响应 |
| `ThreadStartParams` | 创建新线程的参数（类似结构） |
| `ThreadForkParams` | 分叉线程的参数 |

### 实现代码

- **消息处理**: `codex-rs/app-server/src/message_processor/thread.rs`
  - 处理 `thread/resume` 请求
  - 根据优先级选择恢复方式
  - 应用配置覆盖

- **状态管理**: `codex-rs/core/src/state/` 或 `codex-rs/state/src/`
  - 线程数据的持久化和加载

### 测试代码

- **集成测试**: `codex-rs/app-server/tests/suite/v2/thread_resume.rs`
  - 测试不同恢复方式
  - 验证配置覆盖行为

## 依赖与外部交互

### 内部依赖

| 依赖项 | 用途 |
|--------|------|
| `serde` | 序列化/反序列化 |
| `ts-rs` | TypeScript 类型生成 |
| `schemars` | JSON Schema 生成 |
| `codex_experimental_api_macros` | 实验性 API 标记 |
| `ResponseItem` | 历史数据项类型 |

### 外部交互

1. **磁盘 I/O**: 从磁盘加载线程历史记录
2. **状态管理**: 与线程状态存储交互
3. **配置合并**: 将覆盖配置与原始配置合并
4. **模型管理**: 验证和加载指定的模型

### 恢复流程

```
thread/resume Request
    │
    ▼
Parse ThreadResumeParams
    │
    ▼
Select Resume Method
    ├──► history provided? ──► Load from memory
    ├──► path provided? ─────► Load from path
    └──► default ────────────► Load by thread_id
    │
    ▼
Load Thread Data
    │
    ▼
Apply Config Overrides
    │
    ▼
ThreadResumeResponse
```

## 风险、边界与改进建议

### 潜在风险

1. **数据一致性**: 从内存恢复时，历史数据可能与磁盘数据不一致
2. **配置冲突**: 覆盖配置可能与原始配置产生冲突
3. **路径安全**: `path` 字段需要验证，防止目录遍历攻击
4. **内存占用**: `history` 字段可能包含大量数据，导致内存问题

### 边界情况

| 场景 | 处理 |
|------|------|
| `threadId` 不存在 | 返回错误 |
| `history` 为空数组 | 创建空线程 |
| `path` 不存在 | 返回错误 |
| 多个恢复方式同时提供 | 按优先级选择（history > path > thread_id） |
| 无效的模型名称 | 返回错误或使用默认模型 |
| 无效的沙盒模式 | 返回错误 |

### 改进建议

1. **原子性**: 确保恢复操作的原子性，避免部分成功状态
2. **验证增强**: 增强对 `path` 和 `history` 的验证
3. **冲突检测**: 检测配置覆盖中的潜在冲突
4. **增量更新**: 支持部分配置覆盖，而非全量替换
5. **审计日志**: 记录恢复操作和配置变更
6. **回滚机制**: 支持恢复失败时的回滚

### 实验性功能

| 功能 | 标记 | 说明 |
|------|------|------|
| `history` | `thread/resume.history` | 内存恢复，仅限 Codex Cloud |
| `path` | `thread/resume.path` | 路径恢复，不稳定 |
| `persistExtendedHistory` | `thread/resume.persistFullHistory` | 扩展历史持久化 |

- 实验性功能可能在将来版本中变更或移除
- 生产环境使用前需要评估稳定性

### 性能考量

- **磁盘 I/O**: 从磁盘加载大型线程可能较慢
- **内存使用**: `history` 字段可能占用大量内存
- **序列化开销**: 大型历史记录的序列化/反序列化开销

### 相关类型

- `ThreadResumeResponse`: 恢复响应
- `ThreadStartParams`: 创建线程参数
- `ThreadForkParams`: 分叉线程参数
- `Thread`: 线程类型
