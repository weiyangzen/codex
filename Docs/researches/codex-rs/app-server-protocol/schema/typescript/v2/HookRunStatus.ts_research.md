# HookRunStatus.ts Research Document

## 场景与职责

`HookRunStatus` 是 Codex App-Server Protocol v2 中用于表示 Hook 执行状态的枚举类型。它定义了 Hook 运行实例在其生命周期中可能处于的各种状态，从启动到完成的完整状态流转。

在 Codex 的事件驱动架构中，Hook 系统允许在特定事件（如会话开始、用户提交提示）触发时执行自定义逻辑。`HookRunStatus` 用于追踪每个 Hook 运行的当前状态，使客户端能够实时了解 Hook 执行进度并在 UI 中呈现相应的状态指示。

## 功能点目的

该枚举的主要目的是：

1. **状态追踪**：提供 Hook 执行全生命周期的状态标识
2. **UI 反馈**：支持客户端展示 Hook 执行状态（如加载中、已完成、失败等）
3. **流程控制**：基于状态决定后续操作，如是否继续执行、是否阻断主流程
4. **调试支持**：帮助开发者和用户理解 Hook 执行过程中的问题

## 具体技术实现

### 数据结构定义

```typescript
export type HookRunStatus = "running" | "completed" | "failed" | "blocked" | "stopped";
```

### 关键字段说明

| 值 | 说明 | 状态描述 |
|---|---|---|
| `"running"` | 运行中 | Hook 正在执行中，尚未完成 |
| `"completed"` | 已完成 | Hook 成功执行完成，没有错误 |
| `"failed"` | 失败 | Hook 执行过程中发生错误而终止 |
| `"blocked"` | 被阻断 | Hook 执行被系统策略或前置条件阻断 |
| `"stopped"` | 已停止 | Hook 被用户或系统主动停止 |

### 状态流转图

```
                    ┌───────────┐
                    │  running  │
                    └─────┬─────┘
                          │
          ┌───────────────┼───────────────┐
          │               │               │
          ▼               ▼               ▼
    ┌──────────┐    ┌──────────┐    ┌──────────┐
    │ completed│    │  failed  │    │ stopped  │
    └──────────┘    └──────────┘    └──────────┘
                          ▲
                          │
                    ┌──────────┐
                    │ blocked  │
                    └──────────┘
```

## 关键代码路径与文件引用

- **TypeScript 源文件**: `codex-rs/app-server-protocol/schema/typescript/v2/HookRunStatus.ts`
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs`

在 Rust 中的对应定义（使用宏生成）：

```rust
v2_enum_from_core!(
    pub enum HookRunStatus from CoreHookRunStatus {
        Running, Completed, Failed, Blocked, Stopped
    }
);
```

核心协议定义位于：`codex_protocol::protocol::HookRunStatus`

### 在 HookRunSummary 中的使用

```rust
pub struct HookRunSummary {
    pub id: String,
    pub event_name: HookEventName,
    pub handler_type: HookHandlerType,
    pub execution_mode: HookExecutionMode,
    pub scope: HookScope,
    pub source_path: PathBuf,
    pub display_order: i64,
    pub status: HookRunStatus,  // <-- 这里使用
    pub status_message: Option<String>,
    pub started_at: i64,
    pub completed_at: Option<i64>,
    pub duration_ms: Option<i64>,
    pub entries: Vec<HookOutputEntry>,
}
```

## 依赖与外部交互

### 相关类型

- `HookRunSummary`: 包含 `status` 字段，完整描述一个 Hook 运行实例
- `HookStartedNotification`: 通知客户端 Hook 开始执行，此时状态为 `running`
- `HookCompletedNotification`: 通知客户端 Hook 执行完成，状态为 `completed`、`failed`、`blocked` 或 `stopped`

### 状态与通知的关系

| 状态 | 对应通知 | 说明 |
|---|---|---|
| `running` | `HookStartedNotification` | Hook 开始执行时发送 |
| `completed` | `HookCompletedNotification` | 成功完成时发送 |
| `failed` | `HookCompletedNotification` | 执行失败时发送 |
| `blocked` | `HookCompletedNotification` | 被策略阻断时发送 |
| `stopped` | `HookCompletedNotification` | 被主动停止时发送 |

## 风险、边界与改进建议

### 潜在风险

1. **状态歧义**：`blocked` 和 `stopped` 在某些场景下可能难以区分
2. **并发状态**：在异步执行模式下，状态变更的时机需要精确控制
3. **超时处理**：当前没有明确的 `timeout` 状态，超时可能被归类为 `failed`

### 边界情况

1. **快速完成**：Hook 执行极快完成时，`running` 状态可能几乎不可见
2. **状态回退**：一旦进入终态（`completed`/`failed`/`blocked`/`stopped`），不应再变更
3. **重复通知**：确保状态变更只通知一次，避免客户端收到重复事件

### 改进建议

1. **添加 `pending` 状态**：表示 Hook 已排队等待执行但尚未开始
2. **添加 `timeout` 状态**：明确区分执行超时和其他失败原因
3. **状态原因细化**：为 `blocked` 状态添加更详细的阻断原因分类
4. **时间戳精度**：考虑添加 `status_changed_at` 字段追踪状态变更历史

### 注意事项

- 此文件是自动生成的，**不应手动修改**
- 生成工具：[ts-rs](https://github.com/Aleph-Alpha/ts-rs)
- 状态值使用 camelCase 命名（`running` 而非 `Running`），符合 JSON 约定
