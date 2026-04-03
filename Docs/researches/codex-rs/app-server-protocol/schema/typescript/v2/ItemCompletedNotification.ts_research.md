# ItemCompletedNotification 研究文档

## 1. 场景与职责

`ItemCompletedNotification` 是 App-Server Protocol v2 中的通知类型，用于在对话线程中的某个项目（Item）完成时向客户端发送通知。该类型是线程事件通知系统的核心组成部分，支持实时同步对话状态。

**主要使用场景：**
- 消息发送完成通知
- 工具调用完成通知
- 文件操作完成通知
- 客户端更新UI状态

## 2. 功能点目的

该类型的核心目的是通知客户端线程中的某个项目已完成处理：

1. **项目定位**：通过 `threadId` 和 `turnId` 确定项目所属的线程和回合
2. **项目内容**：通过 `item` 字段提供完整的项目信息

这个设计使得客户端能够：
- 实时了解对话线程的状态变化
- 获取已完成项目的完整信息
- 更新UI以反映最新状态
- 触发后续操作（如自动滚动、声音提示等）

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
export type ItemCompletedNotification = { 
  item: ThreadItem, 
  threadId: string, 
  turnId: string, 
};
```

### Rust 源定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ItemCompletedNotification {
    pub item: ThreadItem,
    pub thread_id: String,
    pub turn_id: String,
}
```

### 关键字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `item` | `ThreadItem` | 完成的项目完整信息 |
| `threadId` | `string` | 线程ID，标识项目所属的会话线程 |
| `turnId` | `string` | 回合ID，标识项目所属的具体回合 |

### 特性注解

- `#[serde(rename_all = "camelCase")]`：字段序列化为 camelCase 格式
- `#[ts(export_to = "v2/")]`：TypeScript 类型导出到 `v2/` 目录
- 支持 JSON Schema 生成

## 4. 关键代码路径与文件引用

### Rust 源文件

- **主定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs` 第 4811-4818 行

### 相关通知类型

- `ItemStartedNotification`：项目开始通知（第 4768-4775 行）
- `ItemGuardianApprovalReviewStartedNotification`：Guardian 审核开始通知（第 4777-4792 行）
- `ItemGuardianApprovalReviewCompletedNotification`：Guardian 审核完成通知（第 4794-4809 行）
- `TurnCompletedNotification`：回合完成通知（第 4695-4700 行）

### 依赖类型

- `ThreadItem`：线程项目类型，包含消息、工具调用等

## 5. 依赖与外部交互

### 导入类型

| 类型 | 来源 | 说明 |
|------|------|------|
| `ThreadItem` | 同文件定义 | 线程项目联合类型 |

### 序列化行为

- 使用 `serde` 进行 JSON 序列化/反序列化
- 字段名自动转换为 camelCase
- TypeScript 中表示为对象类型

## 6. 风险、边界与改进建议

### 潜在风险

1. **通知顺序**：网络延迟可能导致通知乱序到达
2. **重复通知**：重连后可能收到重复的通知
3. **数据一致性**：`item` 的完整传输可能导致大数据量
4. **时序问题**：完成通知可能在相关操作后延迟到达

### 边界情况

- 项目完成时客户端离线，重连后的状态同步
- 大量项目同时完成时的通知风暴
- 项目内容过大时的传输问题
- 并发修改时的数据一致性

### 改进建议

1. **添加时间戳**：
   - 添加 `completedAt` 字段用于排序和调试
   - 添加 `sequence` 字段用于检测丢失的通知

2. **增量更新**：
   - 支持仅发送变更部分
   - 添加版本号支持乐观锁

3. **批处理**：
   - 支持批量项目完成通知
   - 添加节流机制防止通知风暴

4. **可靠性增强**：
   - 实现确认机制
   - 支持重传策略
   - 添加幂等性保证

### 与相关通知的对比

| 通知类型 | 触发时机 | 用途 |
|----------|----------|------|
| `ItemStartedNotification` | 项目开始时 | 显示加载状态 |
| `ItemCompletedNotification` | 项目完成时 | 显示最终结果 |
| `ItemGuardianApprovalReviewStartedNotification` | Guardian 审核开始时 | 显示审核中状态 |
| `ItemGuardianApprovalReviewCompletedNotification` | Guardian 审核完成时 | 显示审核结果 |

### 使用建议

- 客户端应监听此通知以实时更新UI
- 考虑实现通知队列处理乱序到达
- 对于大项目，考虑实现增量加载策略
