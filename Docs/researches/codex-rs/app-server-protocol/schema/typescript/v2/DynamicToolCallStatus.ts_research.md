# DynamicToolCallStatus.ts Research Document

## 场景与职责

`DynamicToolCallStatus` 是 Codex App-Server Protocol v2 API 中用于表示动态工具调用生命周期状态的枚举类型。它定义了动态工具调用从发起到完成的各个可能状态，是异步工具调用状态管理的核心类型。

在 Codex 的异步架构中，工具调用通常需要一定时间执行（如网络请求、文件操作、复杂计算等），此枚举允许客户端跟踪调用的实时状态，并据此更新 UI 或执行相应逻辑。

## 功能点目的

该类型的主要目的是：

1. **状态追踪**：提供标准化的状态机，用于跟踪动态工具调用的执行进度
2. **UI 反馈**：支持客户端显示工具调用的实时状态（如加载中、已完成、失败）
3. **流程控制**：允许系统根据状态决定下一步操作（如重试、清理资源、继续对话）
4. **与 ThreadItem 集成**：作为 `ThreadItem::DynamicToolCall` 的核心状态字段，参与对话历史的构建

## 具体技术实现

### 数据结构定义

```typescript
// DynamicToolCallStatus.ts
export type DynamicToolCallStatus = "inProgress" | "completed" | "failed";
```

### 关键字段说明

| 状态值 | 说明 |
|--------|------|
| `"inProgress"` | 工具调用正在执行中，尚未完成 |
| `"completed"` | 工具调用已成功完成，结果已可用 |
| `"failed"` | 工具调用执行失败，可能包含错误信息 |

### 状态转换图

```
┌─────────────┐
│   Initial   │
└──────┬──────┘
       │
       ▼
┌─────────────┐     ┌─────────────┐
│ inProgress  │────▶│  completed  │
└──────┬──────┘     └─────────────┘
       │
       ▼
┌─────────────┐
│   failed    │
└─────────────┘
```

状态转换规则：
- 初始状态为 `inProgress`
- 从 `inProgress` 可以转换到 `completed` 或 `failed`
- `completed` 和 `failed` 是终态，不可再转换

### Rust 端对应实现

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum DynamicToolCallStatus {
    InProgress,
    Completed,
    Failed,
}
```

注意：Rust 端使用 PascalCase 命名（`InProgress`, `Completed`, `Failed`），通过 `#[serde(rename_all = "camelCase")]` 自动转换为 camelCase 的字符串形式。

## 关键代码路径与文件引用

- **TypeScript 源文件**: `codex-rs/app-server-protocol/schema/typescript/v2/DynamicToolCallStatus.ts`
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - `DynamicToolCallStatus` 枚举定义（约第 4520-4524 行）
- **使用位置**:
  - `ThreadItem::DynamicToolCall` 中的 `status` 字段
  - `DynamicToolCallParams` 处理逻辑
  - 客户端 UI 状态管理

## 依赖与外部交互

### 相关类型

1. **ThreadItem::DynamicToolCall**: 使用此状态枚举
   ```rust
   DynamicToolCall {
       id: String,
       tool: String,
       arguments: JsonValue,
       status: DynamicToolCallStatus,
       content_items: Option<Vec<DynamicToolCallOutputContentItem>>,
       success: Option<bool>,
       duration_ms: Option<i64>,
   }
   ```

2. **CollabAgentToolCallStatus**: 类似的枚举，用于协作代理工具调用状态
   ```rust
   pub enum CollabAgentToolCallStatus {
       InProgress,
       Completed,
       Failed,
   }
   ```

### 序列化行为

- Rust 序列化为 camelCase 字符串（`"inProgress"`, `"completed"`, `"failed"`）
- TypeScript 端作为字符串字面量联合类型使用
- 支持双向序列化/反序列化

## 风险、边界与改进建议

### 潜在风险

1. **状态同步延迟**: 网络延迟可能导致客户端看到的状态与实际状态不一致
2. **状态丢失**: 如果服务器崩溃或网络中断，正在进行的工具调用状态可能丢失
3. **超时处理**: 当前枚举没有包含超时状态，长时间处于 `inProgress` 可能导致用户体验问题

### 边界情况

1. **重复完成通知**: 服务器可能因重试机制发送多个完成通知，客户端需要幂等处理
2. **状态回退**: 理论上状态不应回退，但客户端应防御性地处理异常状态转换
3. **并发修改**: 同一工具调用的状态可能在多个地方被更新，需要适当的同步机制

### 改进建议

1. **添加取消状态**: 考虑添加 `"cancelled"` 状态，支持用户主动取消正在执行的工具调用
2. **添加超时状态**: 添加 `"timedOut"` 状态，明确区分失败原因
3. **进度报告**: 对于长时间运行的工具，考虑添加进度百分比或阶段信息
4. **状态时间戳**: 记录每个状态转换的时间戳，便于调试和性能分析
5. **重试计数**: 对于失败状态，记录重试次数，支持指数退避策略

### 扩展示例

```typescript
// 建议的扩展版本
type DynamicToolCallStatus = 
  | "inProgress"
  | "completed" 
  | "failed"
  | "cancelled"
  | "timedOut";

interface DynamicToolCallStatusInfo {
  status: DynamicToolCallStatus;
  timestamp: number;  // 状态变更时间戳
  retryCount?: number;  // 重试次数（仅 failed 状态）
  progress?: number;  // 进度百分比 0-100（仅 inProgress 状态）
  stage?: string;  // 当前执行阶段描述（仅 inProgress 状态）
}
```
