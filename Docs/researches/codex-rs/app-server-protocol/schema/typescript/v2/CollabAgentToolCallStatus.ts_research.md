# CollabAgentToolCallStatus 类型研究文档

## 1. 场景与职责

### 1.1 使用场景

`CollabAgentToolCallStatus` 用于表示协作代理工具调用的执行状态，是 `CollabAgentToolCall` 线程项的核心字段。主要应用场景包括：

- **工具调用跟踪**：跟踪 `spawnAgent`、`wait`、`sendInput` 等协作工具的执行进度
- **UI 状态显示**：在 TUI/CLI 中显示工具调用的当前状态（进行中、已完成、失败）
- **流程控制**：根据工具调用状态决定后续操作（如等待完成后继续）
- **错误处理**：识别失败的工具调用并采取恢复措施

### 1.2 核心职责

- **执行状态表达**：简洁地表达工具调用的三种可能状态
- **与通用状态区分**：专门用于工具调用，与 `CollabAgentStatus`（代理状态）区分
- **序列化兼容**：支持 JSON 序列化和 TypeScript 类型生成

### 1.3 状态语义

| 状态 | 语义 | 用户可见性 |
|------|------|-----------|
| `inProgress` | 工具调用正在执行中 | 显示进度指示器 |
| `completed` | 工具调用成功完成 | 显示成功状态 |
| `failed` | 工具调用执行失败 | 显示错误信息和重试选项 |

---

## 2. 功能点目的

### 2.1 设计目标

| 目标 | 说明 |
|------|------|
| 简洁性 | 三种状态覆盖所有可能的工具调用结果 |
| 明确性 | 状态名称清晰表达执行结果 |
| 一致性 | 与其他工具调用状态（如 `McpToolCallStatus`、`DynamicToolCallStatus`）保持一致 |

### 2.2 状态转换

```
         ┌─────────────┐
    ┌───→│ inProgress  │←──┐
    │    └──────┬──────┘   │
    │           │          │
 complete    failed    (retry)
    │           │          │
    ▼           ▼          │
┌────────┐  ┌────────┐     │
│completed│  │ failed │─────┘
└────────┘  └────────┘
```

### 2.3 与相关类型的对比

| 类型 | 用途 | 状态值 |
|------|------|--------|
| `CollabAgentToolCallStatus` | 协作代理工具调用 | `inProgress`, `completed`, `failed` |
| `CollabAgentStatus` | 代理生命周期 | `pendingInit`, `running`, `interrupted`, `completed`, `errored`, `shutdown`, `notFound` |
| `McpToolCallStatus` | MCP 工具调用 | `inProgress`, `completed`, `failed` |
| `DynamicToolCallStatus` | 动态工具调用 | `inProgress`, `completed`, `failed` |
| `PatchApplyStatus` | 补丁应用 | `inProgress`, `completed`, `failed`, `declined` |

---

## 3. 具体技术实现

### 3.1 TypeScript 类型定义

```typescript
export type CollabAgentToolCallStatus = "inProgress" | "completed" | "failed";
```

### 3.2 Rust 源类型定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs (L4526-L4533)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum CollabAgentToolCallStatus {
    InProgress,
    Completed,
    Failed,
}
```

### 3.3 在 ThreadItem 中的使用

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs (L4208-L4230)
#[serde(rename_all = "camelCase")]
#[ts(rename_all = "camelCase")]
CollabAgentToolCall {
    /// Unique identifier for this collab tool call.
    id: String,
    /// Name of the collab tool that was invoked.
    tool: CollabAgentTool,
    /// Current status of the collab tool call.
    status: CollabAgentToolCallStatus,  // ← 本类型
    /// Thread ID of the agent issuing the collab request.
    sender_thread_id: String,
    /// Thread ID of the receiving agent, when applicable.
    receiver_thread_ids: Vec<String>,
    /// Prompt text sent as part of the collab tool call.
    prompt: Option<String>,
    /// Model requested for the spawned agent.
    model: Option<String>,
    /// Reasoning effort requested for the spawned agent.
    reasoning_effort: Option<ReasoningEffort>,
    /// Last known status of the target agents.
    agents_states: HashMap<String, CollabAgentState>,
}
```

### 3.4 与其他工具调用状态的对比实现

```rust
// MCP 工具调用状态 (L4511-L4515)
pub enum McpToolCallStatus {
    InProgress,
    Completed,
    Failed,
}

// 动态工具调用状态 (L4520-L4524)
pub enum DynamicToolCallStatus {
    InProgress,
    Completed,
    Failed,
}

// 补丁应用状态 (L4485-L4490) - 多一个 declined 状态
pub enum PatchApplyStatus {
    InProgress,
    Completed,
    Failed,
    Declined,  // 用户拒绝应用补丁
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 类型定义位置

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (L4526-L4533) | `CollabAgentToolCallStatus` 定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/CollabAgentToolCallStatus.ts` | 生成的 TypeScript 类型 |

### 4.2 使用位置

| 文件路径 | 使用场景 |
|----------|----------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (L4216) | `CollabAgentToolCall` 的 `status` 字段 |
| `codex-rs/core/src/tools/handlers/multi_agents/` | 多代理工具状态更新 |

### 4.3 相关类型定义

| 文件路径 | 相关类型 |
|----------|----------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (L4508-L4515) | `McpToolCallStatus` |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (L4517-L4524) | `DynamicToolCallStatus` |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (L4485-L4490) | `PatchApplyStatus` |

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| 依赖项 | 说明 |
|--------|------|
| `CollabAgentTool` | 被调用的工具类型 |
| `CollabAgentToolCall` | 包含本状态的线程项 |

### 5.2 数据流

```
┌─────────────────────────────────────────────────────────────┐
│                    CollabAgentToolCall                      │
├─────────────────────────────────────────────────────────────┤
│  id: String                                                 │
│  tool: CollabAgentTool                                      │
│  status: CollabAgentToolCallStatus   ← 本类型               │
│  sender_thread_id: String                                   │
│  receiver_thread_ids: Vec<String>                           │
│  prompt: Option<String>                                     │
│  model: Option<String>                                      │
│  reasoning_effort: Option<ReasoningEffort>                  │
│  agents_states: HashMap<String, CollabAgentState>           │
└─────────────────────────────────────────────────────────────┘
```

### 5.3 状态更新流程

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│ Tool Call   │────→│   Handler    │────→│   Status     │
│   Started   │     │  Execution   │     │  inProgress  │
└─────────────┘     └──────────────┘     └──────────────┘
                                                │
                    ┌──────────────┐            │
                    │   Success    │←───────────┤
                    │   / Failed   │            │
                    └──────┬───────┘            │
                           │                    │
                    ┌──────┴───────┐            │
                    ▼              ▼            │
              ┌────────┐     ┌────────┐         │
              │completed│     │ failed │←────────┘
              └────────┘     └────────┘
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 严重程度 | 说明 |
|------|----------|------|
| 状态粒度不足 | 中 | 仅有三种状态，无法区分"等待中"、"执行中"等细分状态 |
| 无错误详情 | 中 | `failed` 状态不携带错误信息，需通过其他字段获取 |
| 与代理状态混淆 | 低 | 开发者可能混淆 `CollabAgentToolCallStatus` 和 `CollabAgentStatus` |

### 6.2 边界条件

- **状态转换验证**：`completed` 和 `failed` 为终止状态，不应再转换
- **重复完成**：同一工具调用不应多次报告 `completed`
- **取消操作**：当前无 `cancelled` 状态，取消操作可能直接标记为 `failed`

### 6.3 改进建议

1. **添加细分状态**
   ```rust
   pub enum CollabAgentToolCallStatus {
       Pending,       // 等待执行
       InProgress,    // 执行中
       Waiting,       // 等待外部事件（如 wait 工具）
       Completed,
       Failed,
       Cancelled,     // 被取消
   }
   ```

2. **添加错误信息字段**
   ```rust
   pub enum CollabAgentToolCallStatus {
       InProgress,
       Completed,
       Failed {
           error_code: String,
           error_message: String,
           retryable: bool,
       },
   }
   ```

3. **TypeScript 类型增强**
   ```typescript
   export const CollabAgentToolCallStatus = {
       InProgress: "inProgress",
       Completed: "completed",
       Failed: "failed",
   } as const;
   
   export type CollabAgentToolCallStatus = typeof CollabAgentToolCallStatus[keyof typeof CollabAgentToolCallStatus];
   
   // 类型守卫
   export function isTerminalStatus(status: CollabAgentToolCallStatus): boolean {
       return status === "completed" || status === "failed";
   }
   ```

4. **统一工具调用状态**
   ```rust
   // 考虑统一所有工具调用状态
   pub enum ToolCallStatus {
       InProgress,
       Completed,
       Failed,
   }
   
   type McpToolCallStatus = ToolCallStatus;
   type DynamicToolCallStatus = ToolCallStatus;
   type CollabAgentToolCallStatus = ToolCallStatus;
   ```

5. **添加进度信息**
   ```rust
   pub struct CollabAgentToolCall {
       // ... 现有字段
       pub progress: Option<ToolCallProgress>,
   }
   
   pub struct ToolCallProgress {
       pub percent: Option<u8>,  // 0-100
       pub message: Option<String>,
       pub updated_at: i64,
   }
   ```

---

## 附录：相关类型速查

```typescript
// CollabAgentTool.ts
export type CollabAgentTool = "spawnAgent" | "sendInput" | "resumeAgent" | "wait" | "closeAgent";

// CollabAgentStatus.ts
export type CollabAgentStatus = "pendingInit" | "running" | "interrupted" | "completed" | "errored" | "shutdown" | "notFound";

// McpToolCallStatus.ts (类似)
export type McpToolCallStatus = "inProgress" | "completed" | "failed";

// DynamicToolCallStatus.ts (类似)
export type DynamicToolCallStatus = "inProgress" | "completed" | "failed";
```
