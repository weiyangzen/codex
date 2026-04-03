# CommandExecutionStatus.ts Research Document

## 场景与职责

`CommandExecutionStatus` 是一个枚举类型，用于表示命令执行的生命周期状态。在 Codex 应用服务器协议 v2 中，这个类型用于追踪和报告命令执行的当前状态，是命令执行流程中的核心状态机表示。

该类型在以下场景中发挥关键作用：
- **命令执行状态追踪**：实时监控命令从启动到完成的整个生命周期
- **UI 状态展示**：在 TUI 中显示命令执行的进度和结果
- **审批流程**：处理需要用户审批的命令，标记为 "declined" 状态
- **错误处理**：区分命令失败（failed）和被拒绝（declined）的不同情况
- **历史记录**：在 Thread 历史中持久化命令执行结果

## 功能点目的

1. **生命周期管理**：完整覆盖命令执行的四个阶段：进行中、已完成、失败、被拒绝
2. **审批集成**：专门支持 "declined" 状态，用于用户拒绝执行的场景
3. **状态机完整性**：提供清晰的状态转换路径，避免无效状态
4. **协议一致性**：确保客户端和服务器对命令状态有一致的理解

## 具体技术实现

### 数据结构定义

```typescript
export type CommandExecutionStatus = "inProgress" | "completed" | "failed" | "declined";
```

这是一个 TypeScript 字符串字面量联合类型，由 ts-rs 从 Rust 枚举自动生成。

### 关键字段说明

| 值 | 说明 | 状态含义 |
|---|---|---|
| `"inProgress"` | 命令正在执行中 | 命令已启动但尚未完成 |
| `"completed"` | 命令成功完成 | 命令执行成功，退出码为 0 |
| `"failed"` | 命令执行失败 | 命令执行失败，退出码非 0 或发生错误 |
| `"declined"` | 命令被用户拒绝 | 用户通过审批流程拒绝了命令执行 |

**Rust 源定义**（位于 `codex-rs/protocol/src/protocol.rs`）：

```rust
pub enum ExecCommandStatus {
    Completed,
    Failed,
    Declined,
}
```

注意：核心协议中只有三个状态，`InProgress` 是 v2 API 层添加的用于表示进行中的状态。

在 v2.rs 中的定义（第 4418-4439 行）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum CommandExecutionStatus {
    InProgress,
    Completed,
    Failed,
    Declined,
}

impl From<CoreExecCommandStatus> for CommandExecutionStatus {
    fn from(value: CoreExecCommandStatus) -> Self {
        match value {
            CoreExecCommandStatus::Completed => CommandExecutionStatus::Completed,
            CoreExecCommandStatus::Failed => CommandExecutionStatus::Failed,
            CoreExecCommandStatus::Declined => CommandExecutionStatus::Declined,
        }
    }
}

impl From<&CoreExecCommandStatus> for CommandExecutionStatus {
    fn from(value: &CoreExecCommandStatus) -> Self {
        match value {
            CoreExecCommandStatus::Completed => CommandExecutionStatus::Completed,
            CoreExecCommandStatus::Failed => CommandExecutionStatus::Failed,
            CoreExecCommandStatus::Declined => CommandExecutionStatus::Declined,
        }
    }
}
```

## 关键代码路径与文件引用

- **TypeScript 源文件**: `codex-rs/app-server-protocol/schema/typescript/v2/CommandExecutionStatus.ts`
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (第 4418 行)
- **核心协议定义**: `codex-rs/protocol/src/protocol.rs` (第 2620 行)
- **Exec 模块**: `codex-rs/exec/src/exec_events.rs` (第 146 行)
- **使用位置**:
  - `codex-rs/app-server-protocol/schema/typescript/v2/ThreadItem.ts` - 作为 ThreadItem 的 status 字段
  - `codex-rs/app-server/src/bespoke_event_handling.rs` - 状态转换处理
  - `codex-rs/app-server-protocol/src/protocol/thread_history.rs` - 历史记录序列化
  - `codex-rs/exec/src/event_processor_with_jsonl_output.rs` - 事件处理

## 依赖与外部交互

### 相关类型

- `CommandExecutionSource` - 与状态配合，完整描述命令执行的上下文
- `ThreadItem` - 包含 status 字段，标识线程中命令的状态
- `ExecCommandStatus` (Core) - 核心协议中的原始定义
- `ExecCommandBegin` / `ExecCommandEnd` - 包含状态信息的事件类型

### 状态转换图

```
┌─────────────┐
│   Initial   │
└──────┬──────┘
       │
       ▼
┌─────────────┐     ┌─────────────┐
│ InProgress  │────▶│  Completed  │
└──────┬──────┘     └─────────────┘
       │
       ├───────────▶┌─────────────┐
       │            │    Failed   │
       │            └─────────────┘
       │
       └───────────▶┌─────────────┐
                    │   Declined  │
                    └─────────────┘
```

### 使用示例

在 App Server 中处理审批决策后的状态：

```rust
let status = match review_decision {
    ReviewDecision::Approved => CommandExecutionStatus::InProgress,
    ReviewDecision::ApprovedExecpolicyAmendment { .. } => CommandExecutionStatus::InProgress,
    ReviewDecision::ApprovedForSession => CommandExecutionStatus::InProgress,
    ReviewDecision::NetworkPolicyAmendment { .. } => CommandExecutionStatus::Declined,
    ReviewDecision::Abort => CommandExecutionStatus::Failed,
    ReviewDecision::Denied => CommandExecutionStatus::Failed,
};
```

在测试客户端中等待命令完成：

```rust
if last_command_status != Some(&CommandExecutionStatus::Completed) {
    // 等待命令完成
}
```

## 风险、边界与改进建议

### 潜在风险

1. **状态同步**：InProgress 状态只在 v2 API 层存在，与核心协议的状态需要正确映射
2. **序列化歧义**：camelCase 的 "inProgress" 与 Rust 的 `InProgress` 需要确保正确转换
3. **状态一致性**：在分布式场景下，状态更新可能存在延迟

### 边界情况

1. **并发状态更新**：多个客户端同时查询状态时，可能看到不同的状态快照
2. **状态持久化**：Thread 历史中的状态需要与实时状态保持一致
3. **取消操作**：当前没有 "Cancelled" 状态，取消操作可能被映射为 "Failed" 或 "Declined"

### 改进建议

1. **添加 Cancelled 状态**：明确支持命令被取消的场景，与 Failed/Declined 区分开
2. **状态时间戳**：考虑添加状态变更时间戳，便于追踪和调试
3. **状态原因**：为 Failed/Declined 状态添加原因字段，提供更多上下文
4. **状态转换验证**：在关键路径添加状态转换验证，防止无效的状态变更
5. **文档完善**：添加状态转换的详细文档，特别是审批流程中的状态变化
