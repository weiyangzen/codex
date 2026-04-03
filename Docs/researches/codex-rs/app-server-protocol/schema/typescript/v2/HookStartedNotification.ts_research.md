# HookStartedNotification.ts Research Document

## 场景与职责

`HookStartedNotification` 是 Codex App-Server Protocol v2 中用于通知客户端 Hook 开始执行的服务器推送消息。当特定事件触发配置的 Hook 处理器时，服务器会发送此通知，使客户端能够实时了解 Hook 执行的开始状态。

在 Codex 的事件驱动架构中，Hook 系统允许在关键事件点（如会话开始、用户提交提示）插入自定义逻辑。`HookStartedNotification` 是 Hook 生命周期中的第一个通知，标志着 Hook 执行实例的创建和启动。

## 功能点目的

该通知的主要目的是：

1. **实时状态同步**：让客户端及时了解 Hook 执行的开始
2. **UI 反馈**：支持客户端展示 Hook 执行进度（如加载指示器）
3. **执行追踪**：提供 Hook 运行的初始状态快照，用于后续追踪
4. **关联上下文**：通过 `threadId` 和 `turnId` 将 Hook 与特定上下文关联

## 具体技术实现

### 数据结构定义

```typescript
export type HookStartedNotification = { 
  threadId: string, 
  turnId: string | null, 
  run: HookRunSummary, 
};
```

### 关键字段说明

| 字段 | 类型 | 说明 |
|---|---|---|
| `threadId` | `string` | 关联的线程唯一标识符 |
| `turnId` | `string \| null` | 关联的对话轮次标识符。对于 `"turn"` 作用域的 Hook，此字段有值；对于 `"thread"` 作用域的 Hook，可能为 null |
| `run` | `HookRunSummary` | Hook 运行实例的完整描述，包含状态、配置、输出等信息 |

### 通知时机

```
事件触发（如 userPromptSubmit）
         │
         ▼
Hook 运行实例创建
         │
         ▼
发送 HookStartedNotification
         │
         ▼
Hook 处理器执行
```

## 关键代码路径与文件引用

- **TypeScript 源文件**: `codex-rs/app-server-protocol/schema/typescript/v2/HookStartedNotification.ts`
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs`

### 依赖导入

```typescript
import type { HookRunSummary } from "./HookRunSummary";
```

### Rust 对应定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct HookStartedNotification {
    pub thread_id: String,
    pub turn_id: Option<String>,
    pub run: HookRunSummary,
}
```

### 在 v2.rs 中的位置

位于 "Server Notifications" 部分，与 `HookCompletedNotification` 成对出现：

```rust
// === Server Notifications ===
// Thread/Turn lifecycle notifications and item progress events

pub struct TurnStartedNotification { ... }

pub struct HookStartedNotification {  // <-- 这里
    pub thread_id: String,
    pub turn_id: Option<String>,
    pub run: HookRunSummary,
}

pub struct TurnCompletedNotification { ... }

pub struct HookCompletedNotification { ... }
```

## 依赖与外部交互

### 相关类型

```
HookStartedNotification
├── threadId: string
├── turnId: string | null
└── run: HookRunSummary
    ├── id: string
    ├── eventName: HookEventName
    ├── handlerType: HookHandlerType
    ├── executionMode: HookExecutionMode
    ├── scope: HookScope
    ├── sourcePath: string
    ├── displayOrder: bigint
    ├── status: HookRunStatus (值为 "running")
    ├── statusMessage: string | null
    ├── startedAt: bigint
    ├── completedAt: bigint | null (值为 null)
    ├── durationMs: bigint | null (值为 null)
    └── entries: HookOutputEntry[]
```

### 与 HookCompletedNotification 的关系

| 通知 | 发送时机 | `run.status` | `run.completedAt` | `run.durationMs` |
|---|---|---|---|---|
| `HookStartedNotification` | Hook 开始执行时 | `"running"` | `null` | `null` |
| `HookCompletedNotification` | Hook 执行完成时 | `"completed"`/`"failed"`/`"blocked"`/`"stopped"` | 有值 | 有值 |

### 客户端处理流程

```typescript
// 伪代码示例
function handleHookStartedNotification(notification: HookStartedNotification) {
  const { threadId, turnId, run } = notification;
  
  // 1. 定位对应的线程和轮次
  const thread = findThread(threadId);
  const turn = turnId ? thread.findTurn(turnId) : null;
  
  // 2. 创建或更新 Hook 执行状态
  const hookRun = {
    id: run.id,
    status: run.status,  // "running"
    eventName: run.eventName,
    handlerType: run.handlerType,
    startedAt: run.startedAt,
    entries: run.entries,
    // ...
  };
  
  // 3. 更新 UI（如显示加载指示器）
  ui.showHookRunning(hookRun);
}
```

## 风险、边界与改进建议

### 潜在风险

1. **通知丢失**：如果客户端在 Hook 开始后才订阅，可能收不到此通知
2. **状态不一致**：客户端收到通知后，如果连接断开，可能错过后续更新
3. **快速完成**：对于执行极快的 Hook，`HookStartedNotification` 和 `HookCompletedNotification` 可能几乎同时到达

### 边界情况

1. **重复通知**：确保同一 Hook 运行实例不会发送多个 `HookStartedNotification`
2. **并发 Hook**：多个 Hook 同时启动时，通知的顺序应与 `displayOrder` 一致
3. **连接恢复**：客户端重连后，如何获取正在运行的 Hook 状态

### 改进建议

1. **添加序列号**：为通知添加序列号，便于客户端检测丢失或乱序
2. **批量通知**：对于同时启动的多个 Hook，考虑批量发送通知
3. **初始状态同步**：客户端连接时，服务器应主动推送当前正在运行的 Hook 列表
4. **心跳机制**：对于长时间运行的 Hook，考虑添加进度心跳通知
5. **取消通知**：添加 `HookCancelledNotification`，用于通知 Hook 被取消（而非正常完成）

### 与 Turn 生命周期的关系

```
TurnStartedNotification
         │
         ▼
HookStartedNotification (可能多个，按 displayOrder)
         │
         ▼
ItemStartedNotification / ItemCompletedNotification
         │
         ▼
HookCompletedNotification (对应每个 HookStartedNotification)
         │
         ▼
TurnCompletedNotification
```

### 注意事项

- 此文件是自动生成的，**不应手动修改**
- 生成工具：[ts-rs](https://github.com/Aleph-Alpha/ts-rs)
- 客户端应准备好处理 `turnId` 为 null 的情况（Thread 作用域的 Hook）
- 通知中的 `run.status` 应该始终为 `"running"`，客户端可以依赖此断言
