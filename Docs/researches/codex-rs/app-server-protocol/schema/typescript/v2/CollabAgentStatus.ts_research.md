# CollabAgentStatus 类型研究文档

## 1. 场景与职责

### 1.1 使用场景

`CollabAgentStatus` 是协作代理（Collaborative Agent）的状态枚举类型，用于表示多代理系统中各个代理的生命周期状态。主要应用场景包括：

- **代理生命周期管理**：跟踪通过 `spawnAgent` 创建的子代理从初始化到终止的完整生命周期
- **协作状态同步**：在 `CollabAgentToolCall` 中报告被调用代理的当前状态
- **等待操作**：`wait` 工具使用此状态判断目标代理是否已完成执行
- **UI 状态显示**：在 TUI/CLI 中显示代理运行状态（运行中、已完成、出错等）

### 1.2 核心职责

- **状态标准化**：为所有协作代理提供统一的状态词汇表
- **生命周期表达**：完整表达代理从创建到终止的所有可能状态
- **与核心层映射**：与核心协议层的 `AgentStatus` 保持一致

### 1.3 状态分类

| 类别 | 状态 | 说明 |
|------|------|------|
| 初始状态 | `pendingInit` | 代理等待初始化 |
| 运行状态 | `running` | 代理正在执行 |
| 中间状态 | `interrupted` | 代理被中断，可能恢复 |
| 终止状态 | `completed` | 代理成功完成 |
| 终止状态 | `errored` | 代理执行出错 |
| 终止状态 | `shutdown` | 代理被关闭 |
| 错误状态 | `notFound` | 代理未找到 |

---

## 2. 功能点目的

### 2.1 设计目标

| 目标 | 说明 |
|------|------|
| 清晰的生命周期 | 状态之间有明确的转换关系，便于理解和调试 |
| 可恢复性支持 | `interrupted` 状态支持代理的暂停和恢复 |
| 错误区分 | 区分执行错误 (`errored`)、未找到 (`notFound`) 和正常关闭 (`shutdown`) |

### 2.2 状态详解

| 状态值 | 核心层对应 | 说明 | 是否终止状态 |
|--------|-----------|------|-------------|
| `pendingInit` | `PendingInit` | 代理已创建但尚未开始初始化 | 否 |
| `running` | `Running` | 代理正在处理 Turn | 否 |
| `interrupted` | `Interrupted` | 当前 Turn 被中断，等待更多输入 | 否 |
| `completed` | `Completed` | 代理成功完成，可能包含最终消息 | 是 |
| `errored` | `Errored` | 代理执行过程中遇到错误 | 是 |
| `shutdown` | `Shutdown` | 代理已被显式关闭 | 是 |
| `notFound` | `NotFound` | 请求的代理 ID 不存在 | 是 |

### 2.3 状态转换规则

```
                    ┌─────────────┐
         ┌─────────→│ pendingInit │←────────┐
         │          └──────┬──────┘         │
         │                 │ spawn          │
         │                 ▼                │
         │          ┌─────────────┐         │
         │    ┌────→│   running   │←────┐   │
         │    │     └──────┬──────┘     │   │
         │    │            │            │   │
         │  resume      complete      error  │
         │    │            │            │   │
         │    │            ▼            ▼   │
         │    │     ┌─────────────┐  ┌────────┐
         │    └─────│ interrupted │  │errored │
         │          └─────────────┘  └────────┘
         │                 │
         │                 ▼
         │          ┌─────────────┐
         └──────────│  completed  │
                    └─────────────┘
                         │
                    ┌────┴────┐
                    ▼         ▼
              ┌────────┐  ┌────────┐
              │shutdown│  │notFound│
              └────────┘  └────────┘
```

---

## 3. 具体技术实现

### 3.1 TypeScript 类型定义

```typescript
export type CollabAgentStatus = "pendingInit" | "running" | "interrupted" | "completed" | "errored" | "shutdown" | "notFound";
```

### 3.2 Rust 源类型定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs (L4535-L4546)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum CollabAgentStatus {
    PendingInit,
    Running,
    Interrupted,
    Completed,
    Errored,
    Shutdown,
    NotFound,
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

### 3.4 与核心层的差异

| 方面 | Core `AgentStatus` | `CollabAgentStatus` |
|------|-------------------|---------------------|
| 变体数据 | `Completed(Option<String>)`, `Errored(String)` | 纯枚举，无数据 |
| 用途 | 核心逻辑状态机 | API 序列化 |
| 组合 | `CollabAgentState` 包含状态和消息 | 仅状态 |

### 3.5 终止状态判断

```rust
// codex-rs/core/src/agent/status.rs
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
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (L4535-L4546) | `CollabAgentStatus` 定义 |
| `codex-rs/core/src/agent/status.rs` | 状态工具函数 |

### 4.2 使用位置

| 文件路径 | 使用场景 |
|----------|----------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (L4551) | `CollabAgentState` 的 `status` 字段 |
| `codex-rs/core/src/agent/mod.rs` | 代理核心逻辑 |
| `codex-rs/core/src/agent/control.rs` | 代理控制（启动、停止等） |
| `codex-rs/core/src/tools/handlers/multi_agents/` | 多代理工具实现 |
| `codex-rs/tui/src/multi_agents.rs` | TUI 多代理显示 |

### 4.3 测试覆盖

| 文件路径 | 测试内容 |
|----------|----------|
| `codex-rs/core/src/agent/control_tests.rs` | 代理控制状态转换测试 |
| `codex-rs/core/src/codex_tests.rs` | 集成测试中的代理状态 |

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| 依赖项 | 说明 |
|--------|------|
| `serde` | 序列化/反序列化 |
| `schemars::JsonSchema` | JSON Schema 生成 |
| `ts_rs::TS` | TypeScript 类型生成 |

### 5.2 与 CollabAgentState 的关系

```typescript
// CollabAgentState.ts
import type { CollabAgentStatus } from "./CollabAgentStatus";

export type CollabAgentState = {
    status: CollabAgentStatus;  // ← 本类型
    message: string | null;
};
```

### 5.3 状态派生链

```
EventMsg::TurnStarted ──→ AgentStatus::Running ──→ CollabAgentStatus::Running
EventMsg::TurnComplete ──→ AgentStatus::Completed ──→ CollabAgentStatus::Completed
EventMsg::TurnAborted ──→ AgentStatus::Interrupted/Errored ──→ ...
EventMsg::Error ──→ AgentStatus::Errored ──→ CollabAgentStatus::Errored
EventMsg::ShutdownComplete ──→ AgentStatus::Shutdown ──→ CollabAgentStatus::Shutdown
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 严重程度 | 说明 |
|------|----------|------|
| 状态数量较多 | 低 | 7 个状态可能增加客户端处理复杂度 |
| 与核心层命名差异 | 低 | Core 使用 `PendingInit`，TS 使用 `pendingInit`，需注意大小写 |
| 无数据载荷 | 中 | 纯枚举无法携带额外上下文，需配合 `CollabAgentState.message` |

### 6.2 边界条件

- **状态组合**：`completed` 状态可能对应 `CollabAgentState.message` 为 `null`（无最终消息）
- **状态恢复**：`interrupted` 状态理论上可恢复到 `running`，但需确保状态一致性
- **并发状态**：多线程环境下状态更新需要同步机制

### 6.3 改进建议

1. **添加状态分组类型**
   ```typescript
   export const CollabAgentStatusGroup = {
       Active: ["pendingInit", "running", "interrupted"],
       Terminal: ["completed", "errored", "shutdown", "notFound"],
   } as const;
   
   export type CollabAgentStatusGroup = keyof typeof CollabAgentStatusGroup;
   ```

2. **TypeScript 类型守卫**
   ```typescript
   export function isTerminalStatus(status: CollabAgentStatus): boolean {
       return ["completed", "errored", "shutdown", "notFound"].includes(status);
   }
   
   export function isActiveStatus(status: CollabAgentStatus): boolean {
       return ["pendingInit", "running", "interrupted"].includes(status);
   }
   ```

3. **添加状态元数据**
   ```rust
   impl CollabAgentStatus {
       pub fn is_terminal(&self) -> bool {
           matches!(self, Self::Completed | Self::Errored | Self::Shutdown | Self::NotFound)
       }
       
       pub fn can_resume(&self) -> bool {
           matches!(self, Self::Interrupted)
       }
       
       pub fn display_name(&self) -> &'static str {
           match self {
               Self::PendingInit => "Pending Initialization",
               Self::Running => "Running",
               // ...
           }
       }
   }
   ```

4. **考虑合并状态**
   - 评估 `shutdown` 和 `completed` 是否可以合并（都是正常终止）
   - 评估 `notFound` 是否应作为错误而非状态

5. **状态转换验证**
   ```rust
   // 添加状态转换验证，防止非法转换
   impl CollabAgentStatus {
       pub fn can_transition_to(&self, next: Self) -> bool {
           match (self, next) {
               (Self::PendingInit, Self::Running) => true,
               (Self::Running, Self::Completed | Self::Errored | Self::Interrupted) => true,
               (Self::Interrupted, Self::Running | Self::Completed | Self::Errored) => true,
               // ...
               _ => false,
           }
       }
   }
   ```

---

## 附录：状态转换矩阵

| 当前状态 ↓ \ 下一状态 → | pendingInit | running | interrupted | completed | errored | shutdown | notFound |
|------------------------|-------------|---------|-------------|-----------|---------|----------|----------|
| pendingInit            | -           | ✓       | -           | -         | ✓       | ✓        | -        |
| running                | -           | -       | ✓           | ✓         | ✓       | ✓        | -        |
| interrupted            | -           | ✓       | -           | ✓         | ✓       | ✓        | -        |
| completed              | -           | -       | -           | -         | -       | -        | -        |
| errored                | -           | -       | -           | -         | -       | -        | -        |
| shutdown               | -           | -       | -           | -         | -       | -        | -        |
| notFound               | -           | -       | -           | -         | -       | -        | -        |

*注：终止状态（completed, errored, shutdown, notFound）不应再转换到其他状态。*
