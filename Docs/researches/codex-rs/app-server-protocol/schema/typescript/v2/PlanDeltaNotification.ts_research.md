# PlanDeltaNotification 研究文档

## 场景与职责

`PlanDeltaNotification` 是一个实验性通知类型，用于流式传输计划项（Plan Item）的增量更新。它允许服务器在计划执行过程中实时向客户端推送计划的文本变化。

## 功能点目的

该类型的核心功能是：
1. **流式计划更新**: 支持计划内容的实时流式传输
2. **增量同步**: 只传输变化的部分（delta），减少带宽使用
3. **实时反馈**: 让用户能够实时看到 Agent 计划的生成过程

## 具体技术实现

### 数据结构

```typescript
/**
 * EXPERIMENTAL - proposed plan streaming deltas for plan items. Clients should
 * not assume concatenated deltas match the completed plan item content.
 */
export type PlanDeltaNotification = { 
  threadId: string, 
  turnId: string, 
  itemId: string, 
  delta: string 
};
```

### Rust 源码定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PlanDeltaNotification {
    pub thread_id: String,
    pub turn_id: String,
    pub item_id: String,
    pub delta: String,
}
```

### 字段详解

| 字段 | 类型 | 说明 |
|-----|------|------|
| `threadId` | `string` | 关联的线程 ID |
| `turnId` | `string` | 关联的回合 ID |
| `itemId` | `string` | 计划项的唯一标识 |
| `delta` | `string` | 计划内容的增量文本 |

### 重要说明

文档注释中明确警告：
> "Clients should not assume concatenated deltas match the completed plan item content."

这意味着：
1. 增量的拼接结果**不一定**等于最终计划内容
2. 服务器可能在传输过程中修改或重新生成计划
3. 客户端应该将此通知仅用于展示目的，不应依赖其准确性

### 使用场景

作为服务器通知发送：

```rust
server_notification_definitions! {
    /// EXPERIMENTAL - proposed plan streaming deltas for plan items.
    PlanDelta => "item/plan/delta" (v2::PlanDeltaNotification),
}
```

### 相关类型

- `TurnPlanUpdatedNotification`: 计划更新完成时的通知
- `TurnPlanStep`: 计划步骤的定义

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 类型定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/PlanDeltaNotification.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 服务器通知定义，行 899 |

## 依赖与外部交互

### 依赖类型
- `TurnPlanUpdatedNotification`: 相关的计划更新通知
- `TurnPlanStep`: 计划步骤类型

### 协议集成
- 属于 App-Server Protocol v2 API
- 是服务器向客户端发送的通知
- 方法名: `item/plan/delta`
- 标记为 **EXPERIMENTAL**（实验性）

### UI 集成
- 用于实时显示计划生成进度
- 可以与 `TurnPlanUpdatedNotification` 配合使用

## 风险、边界与改进建议

### 潜在风险
1. **实验性不稳定**: 作为实验性功能，API 可能随时变化
2. **数据不一致**: 增量拼接结果可能与最终内容不一致
3. **乱序到达**: 网络延迟可能导致增量通知乱序到达

### 边界情况
1. **空增量**: `delta` 可能为空字符串
2. **大量增量**: 复杂计划可能产生大量增量通知
3. **并发修改**: 计划可能在增量传输期间被修改

### 改进建议
1. 添加 `sequenceNumber` 字段帮助客户端排序
2. 添加 `isComplete` 标志指示增量传输完成
3. 考虑添加 `timestamp` 字段用于调试
4. 考虑支持二进制增量（用于大型计划）
5. 添加 `encoding` 字段支持不同的编码方式
6. 考虑添加校验和或哈希值验证增量完整性
