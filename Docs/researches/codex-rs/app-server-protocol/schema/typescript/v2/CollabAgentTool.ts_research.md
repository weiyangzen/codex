# CollabAgentTool 类型研究文档

## 1. 场景与职责

### 1.1 使用场景

`CollabAgentTool` 定义了多代理协作系统中可用的工具类型，是 Codex 多代理功能的核心组成部分。主要应用场景包括：

- **代理生命周期管理**：通过 `spawnAgent` 创建新代理，`closeAgent` 关闭代理
- **代理间通信**：通过 `sendInput` 向代理发送输入，`resumeAgent` 恢复中断的代理
- **同步等待**：通过 `wait` 工具阻塞当前代理直到目标代理完成
- **协作任务编排**：主代理协调多个子代理完成复杂任务

### 1.2 核心职责

- **工具标准化**：为多代理协作提供统一的工具词汇表
- **操作原子化**：每个工具代表一个原子的协作操作
- **生命周期管理**：覆盖代理从创建到销毁的完整生命周期

### 1.3 典型使用流程

```
主代理
  ├── spawnAgent("子代理A", "任务描述") ──→ 创建子代理A
  ├── spawnAgent("子代理B", "任务描述") ──→ 创建子代理B
  ├── wait("子代理A") ←─────────────────── 等待A完成
  ├── sendInput("子代理B", "A的结果") ────→ 向B发送A的结果
  ├── wait("子代理B") ←─────────────────── 等待B完成
  └── closeAgent("子代理A") ──────────────→ 关闭子代理A
      closeAgent("子代理B") ──────────────→ 关闭子代理B
```

---

## 2. 功能点目的

### 2.1 设计目标

| 目标 | 说明 |
|------|------|
| 协作原语 | 提供构建复杂多代理工作流的基本操作 |
| 清晰语义 | 每个工具名称明确表达其功能 |
| 可组合性 | 工具可以组合使用，构建复杂的协作模式 |

### 2.2 工具详解

| 工具 | 说明 | 使用场景 |
|------|------|----------|
| `spawnAgent` | 创建新的子代理 | 启动并行任务、创建专门代理处理特定子任务 |
| `sendInput` | 向代理发送输入 | 向运行中的代理提供额外上下文或用户输入 |
| `resumeAgent` | 恢复中断的代理 | 在代理被中断后继续执行 |
| `wait` | 等待代理完成 | 同步等待子代理结果，实现顺序依赖 |
| `closeAgent` | 关闭代理 | 清理资源、终止不再需要的代理 |

### 2.3 工具分类

| 类别 | 工具 | 说明 |
|------|------|------|
| 生命周期 | `spawnAgent`, `closeAgent` | 管理代理的创建和销毁 |
| 通信 | `sendInput` | 代理间消息传递 |
| 控制流 | `resumeAgent`, `wait` | 控制代理执行流程 |

---

## 3. 具体技术实现

### 3.1 TypeScript 类型定义

```typescript
export type CollabAgentTool = "spawnAgent" | "sendInput" | "resumeAgent" | "wait" | "closeAgent";
```

### 3.2 Rust 源类型定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs (L4452-L4461)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum CollabAgentTool {
    SpawnAgent,
    SendInput,
    ResumeAgent,
    Wait,
    CloseAgent,
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
    tool: CollabAgentTool,  // ← 本类型
    /// Current status of the collab tool call.
    status: CollabAgentToolCallStatus,
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

### 3.4 工具实现位置

| 工具 | 实现文件 |
|------|----------|
| `spawnAgent` | `codex-rs/core/src/tools/handlers/multi_agents/spawn.rs` |
| `sendInput` | `codex-rs/core/src/tools/handlers/multi_agents/send_input.rs` |
| `resumeAgent` | `codex-rs/core/src/tools/handlers/multi_agents/resume_agent.rs` |
| `wait` | `codex-rs/core/src/tools/handlers/multi_agents/wait.rs` |
| `closeAgent` | `codex-rs/core/src/tools/handlers/multi_agents/close_agent.rs` |

### 3.5 工具参数结构（内部实现）

```rust
// spawnAgent 工具参数示例
pub struct SpawnAgentArgs {
    pub prompt: String,
    pub model: Option<String>,
    pub reasoning_effort: Option<ReasoningEffort>,
}

// wait 工具参数示例
pub struct WaitArgs {
    pub agent_id: String,
    pub timeout_ms: Option<u64>,
}

// sendInput 工具参数示例
pub struct SendInputArgs {
    pub agent_id: String,
    pub input: String,
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 类型定义位置

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (L4452-L4461) | `CollabAgentTool` 定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/CollabAgentTool.ts` | 生成的 TypeScript 类型 |

### 4.2 使用位置

| 文件路径 | 使用场景 |
|----------|----------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (L4214) | `CollabAgentToolCall` 的 `tool` 字段 |
| `codex-rs/core/src/tools/handlers/multi_agents/` | 各工具的具体实现 |
| `codex-rs/core/src/tools/handlers/agent_jobs.rs` | 代理作业管理 |

### 4.3 相关测试

| 文件路径 | 测试内容 |
|----------|----------|
| `codex-rs/core/src/tools/handlers/multi_agents_tests.rs` | 多代理工具单元测试 |
| `codex-rs/core/src/tools/handlers/multi_agents/spawn.rs` | spawn 工具测试 |

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| 依赖项 | 说明 |
|--------|------|
| `CollabAgentToolCallStatus` | 工具调用状态 |
| `CollabAgentState` | 代理状态 |
| `ReasoningEffort` | 推理努力程度配置 |

### 5.2 数据流

```
┌─────────────────────────────────────────────────────────────┐
│                    CollabAgentToolCall                      │
├─────────────────────────────────────────────────────────────┤
│  id: String                                                 │
│  tool: CollabAgentTool           ← 本类型（工具类型）        │
│  status: CollabAgentToolCallStatus                          │
│  sender_thread_id: String                                   │
│  receiver_thread_ids: Vec<String>                           │
│  prompt: Option<String>                                     │
│  model: Option<String>                                      │
│  reasoning_effort: Option<ReasoningEffort>                  │
│  agents_states: HashMap<String, CollabAgentState>           │
└─────────────────────────────────────────────────────────────┘
```

### 5.3 工具调用流程

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│   Agent A   │────→│ LLM decides  │────→│ Tool Call    │
│  (主代理)    │     │ to use tool  │     │ CollabAgent  │
│             │     │              │     │ Tool::Spawn  │
└─────────────┘     └──────────────┘     └──────┬───────┘
                                                │
                                                ▼
┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│   Agent B   │←────│  Core Tool   │←────│ Tool Handler │
│  (子代理)    │     │  Executor    │     │ (spawn.rs)   │
│  [新创建]    │     │              │     │              │
└─────────────┘     └──────────────┘     └──────────────┘
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 严重程度 | 说明 |
|------|----------|------|
| 工具权限 | 高 | 需要确保代理只能操作其有权访问的其他代理 |
| 循环依赖 | 中 | 代理A等待代理B，代理B等待代理A可能导致死锁 |
| 资源泄漏 | 中 | 未正确关闭的代理可能持续占用资源 |

### 6.2 边界条件

- **代理ID不存在**：`sendInput`、`resumeAgent`、`wait`、`closeAgent` 操作不存在的代理时应返回 `notFound` 状态
- **重复关闭**：对同一代理多次调用 `closeAgent` 应幂等处理
- **自我操作**：代理不应能够关闭自己或向自己发送输入（需要验证）

### 6.3 改进建议

1. **添加工具参数类型到协议**
   ```typescript
   export type CollabAgentToolParams = 
       | { tool: "spawnAgent"; prompt: string; model?: string; }
       | { tool: "sendInput"; agentId: string; input: string; }
       | { tool: "resumeAgent"; agentId: string; }
       | { tool: "wait"; agentId: string; timeoutMs?: number; }
       | { tool: "closeAgent"; agentId: string; };
   ```

2. **添加批量操作**
   ```rust
   pub enum CollabAgentTool {
       // ... 现有工具
       SpawnAgents,  // 批量创建
       WaitAll,      // 等待多个代理
       CloseAgents,  // 批量关闭
   }
   ```

3. **添加超时控制**
   ```rust
   pub enum CollabAgentTool {
       // ...
       WaitWithTimeout {
           agent_id: String,
           timeout_ms: u64,
           on_timeout: WaitTimeoutAction,  // Fail / Continue
       },
   }
   ```

4. **TypeScript 类型增强**
   ```typescript
   export const CollabAgentTool = {
       SpawnAgent: "spawnAgent",
       SendInput: "sendInput",
       ResumeAgent: "resumeAgent",
       Wait: "wait",
       CloseAgent: "closeAgent",
   } as const;
   
   export type CollabAgentTool = typeof CollabAgentTool[keyof typeof CollabAgentTool];
   
   // 添加工具分类
   export const LIFECYCLE_TOOLS: CollabAgentTool[] = ["spawnAgent", "closeAgent"];
   export const COMMUNICATION_TOOLS: CollabAgentTool[] = ["sendInput"];
   export const CONTROL_FLOW_TOOLS: CollabAgentTool[] = ["resumeAgent", "wait"];
   ```

5. **添加工具元数据**
   ```rust
   impl CollabAgentTool {
       pub fn requires_target_agent(&self) -> bool {
           matches!(self, Self::SendInput | Self::ResumeAgent | Self::Wait | Self::CloseAgent)
       }
       
       pub fn is_blocking(&self) -> bool {
           matches!(self, Self::Wait)
       }
       
       pub fn description(&self) -> &'static str {
           match self {
               Self::SpawnAgent => "Create a new sub-agent",
               Self::SendInput => "Send input to a running agent",
               // ...
           }
       }
   }
   ```

---

## 附录：相关类型速查

```typescript
// CollabAgentToolCallStatus.ts
export type CollabAgentToolCallStatus = "inProgress" | "completed" | "failed";

// CollabAgentStatus.ts
export type CollabAgentStatus = "pendingInit" | "running" | "interrupted" | "completed" | "errored" | "shutdown" | "notFound";

// CollabAgentState.ts
export type CollabAgentState = {
    status: CollabAgentStatus;
    message: string | null;
};
```
