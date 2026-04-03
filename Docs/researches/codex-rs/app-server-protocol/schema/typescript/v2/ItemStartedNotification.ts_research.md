# ItemStartedNotification 研究文档

## 1. 场景与职责

`ItemStartedNotification` 是 App-Server Protocol v2 中的通知类型，用于在对话线程中的某个项目（Item）开始处理时向客户端发送通知。该类型是线程事件通知系统的基础组成部分，支持实时同步对话状态。

**主要使用场景：**
- 消息开始生成通知
- 工具调用开始执行通知
- 文件操作开始通知
- 客户端显示加载/处理中状态

## 2. 功能点目的

该类型的核心目的是通知客户端线程中的某个项目已开始处理：

1. **项目定位**：通过 `threadId` 和 `turnId` 确定项目所属的线程和回合
2. **项目预览**：通过 `item` 字段提供项目的初始信息

这个设计使得客户端能够：
- 实时了解对话线程中新项目的创建
- 显示加载或处理中状态给用户
- 为后续的项目完成做准备
- 实现流畅的用户体验（如打字机效果）

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
export type ItemStartedNotification = { 
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
pub struct ItemStartedNotification {
    pub item: ThreadItem,
    pub thread_id: String,
    pub turn_id: String,
}
```

### 关键字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `item` | `ThreadItem` | 开始处理的项目信息 |
| `threadId` | `string` | 线程ID，标识项目所属的会话线程 |
| `turnId` | `string` | 回合ID，标识项目所属的具体回合 |

### 特性注解

- `#[serde(rename_all = "camelCase")]`：字段序列化为 camelCase 格式
- `#[ts(export_to = "v2/")]`：TypeScript 类型导出到 `v2/` 目录
- 支持 JSON Schema 生成

## 4. 关键代码路径与文件引用

### Rust 源文件

- **主定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs` 第 4768-4775 行

### 相关通知类型

- `ItemCompletedNotification`：项目完成通知（第 4811-4818 行）
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

1. **通知顺序**：开始通知可能在项目实际开始后才到达
2. **快速完成**：项目可能在开始通知发出前就已经完成
3. **重复通知**：重连后可能收到重复的开始通知
4. **资源消耗**：频繁的开始通知可能影响性能

### 边界情况

- 项目开始后客户端才连接
- 开始通知丢失，直接收到完成通知
- 多个项目同时开始
- 项目开始后长时间没有进展

### 改进建议

1. **添加时间戳**：
   - 添加 `startedAt` 字段记录开始时间
   - 添加 `sequence` 字段用于排序

2. **进度信息**：
   - 添加预计完成时间
   - 支持进度百分比（如果适用）
   - 添加处理阶段信息

3. **可靠性增强**：
   - 实现幂等性处理
   - 支持状态同步查询
   - 添加心跳机制

4. **性能优化**：
   - 批量开始通知
   - 节流机制
   - 增量更新

### 与完成通知的关系

| 通知类型 | 触发时机 | 状态转换 |
|----------|----------|----------|
| `ItemStartedNotification` | 项目开始时 | 无 → 处理中 |
| `ItemCompletedNotification` | 项目完成时 | 处理中 → 已完成 |

### 使用建议

- 客户端应监听此通知以显示加载状态
- 考虑实现超时机制处理长时间无响应的项目
- 对于快速完成的项目，可以跳过中间状态直接显示结果
- 实现优雅的错误处理，应对开始通知丢失的情况
