# ThreadResumeResponse Research

## TypeScript Schema

```typescript
export type ThreadResumeResponse = { 
    thread: Thread, 
    model: string, 
    modelProvider: string, 
    serviceTier: ServiceTier | null, 
    cwd: string, 
    approvalPolicy: AskForApproval, 
    /**
     * Reviewer currently used for approval requests on this thread.
     */
    approvalsReviewer: ApprovalsReviewer, 
    sandbox: SandboxPolicy, 
    reasoningEffort: ReasoningEffort | null, 
};
```

## 场景与职责

`ThreadResumeResponse` 是 `thread/resume` RPC 方法的响应类型，用于返回恢复后的线程信息和当前配置状态。该类型标记为 **实验性 API（ExperimentalApi）**。

### 使用场景

1. **恢复确认**: 返回成功恢复的线程对象
2. **配置同步**: 告知客户端当前生效的模型、提供商、审批策略等配置
3. **状态获取**: 提供线程的当前工作目录、沙盒策略等运行时信息
4. **UI 更新**: 客户端使用响应数据更新界面显示

### 职责

- 返回恢复后的完整线程对象
- 提供当前生效的配置信息（模型、提供商、服务层级等）
- 返回审批策略和审批审核者设置
- 提供沙盒策略和推理力度配置

## 功能点目的

### 核心功能

1. **线程返回**: 提供恢复后的完整线程对象，包含 ID、状态、历史等
2. **配置报告**: 报告实际生效的配置，包括任何覆盖后的值
3. **策略同步**: 同步审批策略和沙盒策略信息
4. **能力声明**: 告知客户端当前线程支持的功能

### 设计考量

- 与 `ThreadStartResponse` 结构相似，保持一致性
- 所有配置字段都反映实际生效的值（包括覆盖后的值）
- `serviceTier` 和 `reasoningEffort` 为可选，支持不同模型能力
- 标记为 `ExperimentalApi`，允许未来调整

## 具体技术实现

### 数据结构

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS, ExperimentalApi)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadResumeResponse {
    pub thread: Thread,
    pub model: String,
    pub model_provider: String,
    pub service_tier: Option<ServiceTier>,
    pub cwd: PathBuf,
    #[experimental(nested)]
    pub approval_policy: AskForApproval,
    /// Reviewer currently used for approval requests on this thread.
    pub approvals_reviewer: ApprovalsReviewer,
    pub sandbox: SandboxPolicy,
    pub reasoning_effort: Option<ReasoningEffort>,
}
```

### 字段说明

| 字段 | 类型 | 说明 | 实验性 |
|------|------|------|--------|
| `thread` | `Thread` | 恢复后的完整线程对象 | 否 |
| `model` | `string` | 当前使用的模型名称 | 否 |
| `modelProvider` | `string` | 当前使用的模型提供商 | 否 |
| `serviceTier` | `ServiceTier \| null` | 服务层级（如 default/flex） | 否 |
| `cwd` | `string` | 当前工作目录 | 否 |
| `approvalPolicy` | `AskForApproval` | 审批策略配置 | 嵌套实验性 |
| `approvalsReviewer` | `ApprovalsReviewer` | 审批审核者 | 否 |
| `sandbox` | `SandboxPolicy` | 沙盒策略配置 | 否 |
| `reasoningEffort` | `ReasoningEffort \| null` | 推理力度设置 | 否 |

### 嵌套类型

#### Thread

```typescript
export type Thread = {
    id: string,
    preview: string,
    ephemeral: boolean,
    modelProvider: string,
    createdAt: number,
    updatedAt: number,
    status: ThreadStatus,
    path: string | null,
    cwd: string,
    cliVersion: string,
    source: SessionSource,
    agentNickname: string | null,
    agentRole: string | null,
    gitInfo: GitInfo | null,
    name: string | null,
    turns: Array<Turn>,
};
```

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

#### SandboxPolicy

```typescript
export type SandboxPolicy = 
    | { type: "dangerFullAccess" }
    | { type: "readOnly", access?: ReadOnlyAccess, networkAccess: boolean }
    | { type: "externalSandbox", networkAccess?: NetworkAccess }
    | { type: "workspaceWrite", writableRoots: Array<string>, readOnlyAccess?: ReadOnlyAccess, networkAccess: boolean, excludeTmpdirEnvVar: boolean, excludeSlashTmp: boolean };
```

#### ReasoningEffort

```typescript
export type ReasoningEffort = "low" | "medium" | "high";
```

### 与 ThreadStartResponse 的对比

| 字段 | ThreadResumeResponse | ThreadStartResponse | 说明 |
|------|---------------------|---------------------|------|
| `thread` | ✓ | ✓ | 线程对象 |
| `model` | ✓ | ✓ | 模型名称 |
| `modelProvider` | ✓ | ✓ | 模型提供商 |
| `serviceTier` | ✓ | ✓ | 服务层级 |
| `cwd` | ✓ | ✓ | 工作目录 |
| `approvalPolicy` | ✓ | ✓ | 审批策略 |
| `approvalsReviewer` | ✓ | ✓ | 审批审核者 |
| `sandbox` | ✓ | ✓ | 沙盒策略 |
| `reasoningEffort` | ✓ | ✓ | 推理力度 |

两个响应类型结构完全一致，便于客户端统一处理。

## 关键代码路径与文件引用

### 协议定义

- **Rust 定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 2613-2628)
- **TypeScript 生成**: `codex-rs/app-server-protocol/schema/typescript/v2/ThreadResumeResponse.ts`
- **JSON Schema**: `codex-rs/app-server-protocol/schema/json/v2/ThreadResumeResponse.json`

### 相关协议类型

| 类型 | 说明 |
|------|------|
| `ThreadResumeParams` | 恢复请求参数 |
| `ThreadStartResponse` | 创建线程的响应（相同结构） |
| `ThreadForkResponse` | 分叉线程的响应（相同结构） |
| `Thread` | 线程对象类型 |

### 实现代码

- **消息处理**: `codex-rs/app-server/src/message_processor/thread.rs`
  - 构造 `ThreadResumeResponse`
  - 从恢复的线程中提取配置信息

- **线程管理**: `codex-rs/core/src/codex/` 或相关模块
  - 管理线程状态和配置

### 测试代码

- **集成测试**: `codex-rs/app-server/tests/suite/v2/thread_resume.rs`
  - 验证响应结构和字段值
  - 测试配置覆盖后的响应

## 依赖与外部交互

### 内部依赖

| 依赖项 | 用途 |
|--------|------|
| `serde` | 序列化/反序列化 |
| `ts-rs` | TypeScript 类型生成 |
| `schemars` | JSON Schema 生成 |
| `codex_experimental_api_macros` | 实验性 API 标记 |
| `Thread` | 线程类型 |
| `AskForApproval` | 审批策略类型 |
| `ApprovalsReviewer` | 审批审核者类型 |
| `SandboxPolicy` | 沙盒策略类型 |

### 外部交互

1. **状态查询**: 从线程状态中提取当前配置
2. **配置合并**: 反映任何配置覆盖后的最终值
3. **模型验证**: 验证模型和提供商的有效性
4. **客户端同步**: 将线程状态同步给客户端

### 响应构造流程

```
thread/resume Processing
    │
    ▼
Load/Resume Thread
    │
    ▼
Extract Thread Object
    │
    ▼
Gather Configuration
    ├──► Model Info
    ├──► Service Tier
    ├──► Approval Policy
    ├──► Sandbox Policy
    └──► Reasoning Effort
    │
    ▼
Construct ThreadResumeResponse
    │
    ▼
Send Response
```

## 风险、边界与改进建议

### 潜在风险

1. **数据一致性**: 响应中的配置可能与客户端期望不一致（如覆盖未生效）
2. **敏感信息**: `Thread` 对象可能包含敏感信息，需要适当的访问控制
3. **大对象传输**: 包含完整历史记录的 `Thread` 可能很大，影响性能
4. **实验性变更**: 作为实验性 API，未来可能变更，影响客户端兼容性

### 边界情况

| 场景 | 处理 |
|------|------|
| 线程恢复失败 | 返回错误响应，不发送 `ThreadResumeResponse` |
| 配置验证失败 | 返回错误，说明无效的配置值 |
| 模型不可用 | 返回错误或使用默认模型 |
| 历史记录为空 | 正常返回，`thread.turns` 为空数组 |

### 改进建议

1. **分页历史**: 对于大型线程，考虑分页返回历史记录
2. **差异同步**: 只返回相对于客户端已知状态的差异
3. **缓存控制**: 添加缓存控制头，支持客户端缓存
4. **部分响应**: 支持只返回特定字段，减少数据传输
5. **版本标记**: 添加 API 版本标记，便于客户端适配

### 实验性状态

- `ThreadResumeResponse` 标记为 `ExperimentalApi`
- `approvalPolicy` 字段标记为嵌套实验性 (`experimental(nested)`)
- 未来可能调整字段或结构
- 客户端应做好向前兼容处理

### 性能考量

- **序列化开销**: 大型线程对象的序列化开销
- **网络传输**: 完整线程数据可能很大
- **内存使用**: 服务器构造响应时的内存占用

### 相关类型

- `ThreadResumeParams`: 恢复请求参数
- `ThreadStartResponse`: 创建线程响应（相同结构）
- `ThreadForkResponse`: 分叉线程响应（相同结构）
- `Thread`: 线程对象
- `Turn`: 对话轮次
- `ThreadItem`: 线程项
