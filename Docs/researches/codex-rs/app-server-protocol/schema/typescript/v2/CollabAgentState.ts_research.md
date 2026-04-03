# CollabAgentState 类型研究文档

## 1. 场景与职责

### 1.1 使用场景

`CollabAgentState` 用于表示协作代理（Collaborative Agent）的状态信息，是多代理协作系统的核心类型。主要应用场景包括：

- **多代理协作**：当主代理通过 `spawnAgent` 工具创建子代理时，跟踪子代理的执行状态
- **代理状态监控**：在 `CollabAgentToolCall` 中报告被调用代理的当前状态
- **异步等待**：`wait` 工具调用时，轮询检查目标代理是否完成
- **状态可视化**：在 TUI 中显示协作代理的运行状态

### 1.2 核心职责

- **状态聚合**：将核心层的 `AgentStatus` 转换为 v2 API 友好的结构
- **消息传递**：在代理完成或出错时，传递最终消息或错误信息
- **状态映射**：提供从 `CoreAgentStatus` 到 `CollabAgentState` 的转换实现

### 1.3 状态生命周期

```
pendingInit → running → [interrupted] → completed/errored/shutdown
                    ↓
               notFound
```

---

## 2. 功能点目的

### 2.1 设计目标

| 目标 | 说明 |
|------|------|
| 状态标准化 | 统一多代理场景下的状态表示 |
| 信息完整性 | 同时包含状态码和可选的消息文本 |
| 类型转换 | 无缝桥接核心协议层和 v2 API 层 |

### 2.2 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `status` | `CollabAgentStatus` | 代理状态枚举（必填） |
| `message` | `string \| null` | 状态相关消息，如完成时的最终回复或错误信息 |

### 2.3 状态与消息的对应关系

| `status` | `message` 内容 | 说明 |
|----------|----------------|------|
| `pendingInit` | `null` | 等待初始化 |
| `running` | `null` | 正在运行 |
| `interrupted` | `null` | 被中断 |
| `completed` | 最终助手消息 | 成功完成 |
| `errored` | 错误信息 | 执行出错 |
| `shutdown` | `null` | 已关闭 |
| `notFound` | `null` | 代理未找到 |

---

## 3. 具体技术实现

### 3.1 TypeScript 类型定义

```typescript
import type { CollabAgentStatus } from "./CollabAgentStatus";

export type CollabAgentState = {
    status: CollabAgentStatus;
    message: string | null;
};
```

### 3.2 Rust 源类型定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs (L4548-L4554)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct CollabAgentState {
    pub status: CollabAgentStatus,
    pub message: Option<String>,
}
```

### 3.3 核心协议层定义

```rust
// codex-rs/protocol/src/protocol.rs (L1522-L1538)
pub enum AgentStatus {
    /// Agent is waiting for initialization.
    #[default]
    PendingInit,
    /// Agent is currently running.
    Running,
    /// Agent's current turn was interrupted and it may receive more input.
    Interrupted,
    /// Agent is done. Contains the final assistant message.
    Completed(Option<String>),
    /// Agent encountered an error.
    Errored(String),
    /// Agent has been shutdown.
    Shutdown,
    /// Agent is not found.
    NotFound,
}
```

### 3.4 类型转换实现

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs (L4556-L4589)
impl From<CoreAgentStatus> for CollabAgentState {
    fn from(value: CoreAgentStatus) -> Self {
        match value {
            CoreAgentStatus::PendingInit => Self {
                status: CollabAgentStatus::PendingInit,
                message: None,
            },
            CoreAgentStatus::Running => Self {
                status: CollabAgentStatus::Running,
                message: None,
            },
            CoreAgentStatus::Interrupted => Self {
                status: CollabAgentStatus::Interrupted,
                message: None,
            },
            CoreAgentStatus::Completed(message) => Self {
                status: CollabAgentStatus::Completed,
                message,
            },
            CoreAgentStatus::Errored(message) => Self {
                status: CollabAgentStatus::Errored,
                message: Some(message),
            },
            CoreAgentStatus::Shutdown => Self {
                status: CollabAgentStatus::Shutdown,
                message: None,
            },
            CoreAgentStatus::NotFound => Self {
                status: CollabAgentStatus::NotFound,
                message: None,
            },
        }
    }
}
```

### 3.5 状态派生逻辑

```rust
// codex-rs/core/src/agent/status.rs
pub(crate) fn agent_status_from_event(msg: &EventMsg) -> Option<AgentStatus> {
    match msg {
        EventMsg::TurnStarted(_) => Some(AgentStatus::Running),
        EventMsg::TurnComplete(ev) => Some(AgentStatus::Completed(ev.last_agent_message.clone())),
        EventMsg::TurnAborted(ev) => match ev.reason {
            codex_protocol::protocol::TurnAbortReason::Interrupted => {
                Some(AgentStatus::Interrupted)
            }
            _ => Some(AgentStatus::Errored(format!("{:?}", ev.reason))),
        },
        EventMsg::Error(ev) => Some(AgentStatus::Errored(ev.message.clone())),
        EventMsg::ShutdownComplete => Some(AgentStatus::Shutdown),
        _ => None,
    }
}

pub(crate) fn is_final(status: &AgentStatus) -> bool {
    !matches!(
        status,
        AgentStatus::PendingInit | AgentStatus::Running | AgentStatus::Interrupted
    )
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 类型定义位置

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/protocol/src/protocol.rs` (L1522-L1538) | 核心 `AgentStatus` 定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (L4538-L4554) | `CollabAgentStatus` 和 `CollabAgentState` 定义 |
| `codex-rs/core/src/agent/status.rs` | 状态派生逻辑 |

### 4.2 使用位置

| 文件路径 | 使用场景 |
|----------|----------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (L4229) | `CollabAgentToolCall` 的 `agents_states` 字段 |
| `codex-rs/core/src/tools/handlers/multi_agents/` | 多代理工具处理器 |
| `codex-rs/tui/src/multi_agents.rs` | TUI 多代理状态显示 |
| `codex-rs/tui_app_server/src/multi_agents.rs` | App Server 多代理适配 |

### 4.3 多代理工具实现

| 文件路径 | 工具 |
|----------|------|
| `codex-rs/core/src/tools/handlers/multi_agents/spawn.rs` | `spawnAgent` |
| `codex-rs/core/src/tools/handlers/multi_agents/resume_agent.rs` | `resumeAgent` |
| `codex-rs/core/src/tools/handlers/multi_agents/close_agent.rs` | `closeAgent` |
| `codex-rs/core/src/tools/handlers/multi_agents/wait.rs` | `wait` |

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| 依赖项 | 说明 |
|--------|------|
| `CollabAgentStatus` | 状态枚举类型 |
| `CoreAgentStatus` | 核心协议层状态 |
| `EventMsg` | 事件消息类型 |

### 5.2 数据流

```
┌─────────────────────────────────────────────────────────────┐
│                    CollabAgentToolCall                      │
├─────────────────────────────────────────────────────────────┤
│  id: String                                                 │
│  tool: CollabAgentTool                                      │
│  status: CollabAgentToolCallStatus                          │
│  sender_thread_id: String                                   │
│  receiver_thread_ids: Vec<String>                           │
│  prompt: Option<String>                                     │
│  model: Option<String>                                      │
│  reasoning_effort: Option<ReasoningEffort>                  │
│  agents_states: HashMap<String, CollabAgentState> ← 本类型  │
└─────────────────────────────────────────────────────────────┘
```

### 5.3 状态转换流程

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Core Agent  │────→│  EventMsg    │────→│ AgentStatus  │
│  (执行逻辑)   │     │  (事件流)     │     │  (核心状态)   │
└──────────────┘     └──────────────┘     └──────┬───────┘
                                                  │
                                                  │ From trait
                                                  ▼
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Client     │←────│  ThreadItem  │←────│CollabAgentState│
│  (UI 显示)    │     │  (API 响应)   │     │   (v2 API)    │
└──────────────┘     └──────────────┘     └──────────────┘
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 严重程度 | 说明 |
|------|----------|------|
| 消息字段不一致 | 中 | `Completed` 和 `Errored` 的消息来源不同，可能导致处理逻辑分散 |
| 状态派生复杂性 | 中 | 状态从事件派生，事件丢失或乱序可能导致状态错误 |
| 并发状态更新 | 低 | 多线程环境下状态更新需要同步 |

### 6.2 边界条件

- **空消息处理**：`Completed(None)` 和 `Errored("")` 需要客户端妥善处理
- **状态超时**：长时间处于 `Running` 状态可能需要超时机制
- **重复完成**：防止同一代理多次报告 `Completed` 状态

### 6.3 改进建议

1. **添加时间戳**
   ```rust
   pub struct CollabAgentState {
       pub status: CollabAgentStatus,
       pub message: Option<String>,
       pub updated_at: i64,  // Unix 时间戳
   }
   ```

2. **添加进度信息**
   ```rust
   pub struct CollabAgentState {
       pub status: CollabAgentStatus,
       pub message: Option<String>,
       pub progress: Option<AgentProgress>,  // 执行进度百分比或步骤
   }
   ```

3. **统一消息处理**
   ```rust
   // 考虑将消息统一为结构化类型
   pub enum AgentMessage {
       Success(String),
       Error { code: String, message: String },
       None,
   }
   ```

4. **添加状态历史**
   ```rust
   pub struct CollabAgentState {
       pub current: AgentStatusSnapshot,
       pub history: Vec<AgentStatusSnapshot>,  // 状态变更历史
   }
   ```

5. **TypeScript 类型增强**
   ```typescript
   // 添加类型守卫函数
   export function isFinalState(state: CollabAgentState): boolean {
       return ["completed", "errored", "shutdown", "notFound"].includes(state.status);
   }
   
   export function hasMessage(state: CollabAgentState): state is { status: CollabAgentStatus; message: string } {
       return state.message !== null;
   }
   ```

---

## 附录：相关类型速查

```typescript
// CollabAgentStatus.ts
export type CollabAgentStatus = "pendingInit" | "running" | "interrupted" | "completed" | "errored" | "shutdown" | "notFound";

// CollabAgentToolCallStatus.ts
export type CollabAgentToolCallStatus = "inProgress" | "completed" | "failed";

// CollabAgentTool.ts
export type CollabAgentTool = "spawnAgent" | "sendInput" | "resumeAgent" | "wait" | "closeAgent";
```
