# ReasoningSummaryPartAddedNotification.ts 研究文档

## 场景与职责

`ReasoningSummaryPartAddedNotification.ts` 定义了推理摘要部分添加通知的数据结构，用于在服务器向客户端通知新的推理摘要部分已添加时使用。这是 Codex 流式推理展示功能的一部分，支持实时显示模型的推理过程。

## 功能点目的

该类型用于：
1. **流式推理展示**：在模型生成推理摘要时实时通知客户端
2. **多部分推理支持**：支持分段显示复杂的推理过程
3. **UI 同步**：确保客户端 UI 与服务器推理状态同步
4. **调试可见性**：让用户了解模型的推理步骤

## 具体技术实现

### 数据结构定义

```typescript
export type ReasoningSummaryPartAddedNotification = { 
  threadId: string,      // 所属线程ID
  turnId: string,        // 所属回合ID
  itemId: string,        // 响应项ID
  summaryIndex: number,  // 摘要部分的索引
};
```

### 字段详解

| 字段 | 类型 | 说明 |
|------|------|------|
| threadId | string | 标识此推理摘要所属的对话线程 |
| turnId | string | 标识此推理摘要所属的具体回合 |
| itemId | string | 关联的响应项标识符 |
| summaryIndex | number | 此摘要在推理序列中的索引位置 |

### Rust 协议定义

在 `codex-rs/app-server-protocol/src/protocol/v2.rs` 中：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ReasoningSummaryPartAddedNotification {
    pub thread_id: String,
    pub turn_id: String,
    pub item_id: String,
    pub summary_index: usize,
}
```

### 事件流程

```
模型生成推理内容
    ↓
服务器检测到新的推理摘要部分
    ↓
发送 ReasoningSummaryPartAddedNotification
    ↓
客户端接收通知并更新 UI
    ↓
后续 ReasoningSummaryTextDeltaNotification 发送实际文本
```

### 与相关通知的关系

- `ReasoningSummaryPartAddedNotification`：通知新部分的开始
- `ReasoningSummaryTextDeltaNotification`：发送该部分的文本增量
- `ReasoningTextDeltaNotification`：发送推理内容的原始增量（非摘要）

## 关键代码路径与文件引用

### TypeScript 类型定义
- 文件：`codex-rs/app-server-protocol/schema/typescript/v2/ReasoningSummaryPartAddedNotification.ts`

### Rust 协议定义
- V2 协议：`codex-rs/app-server-protocol/src/protocol/v2.rs`
- 通用协议：`codex-rs/app-server-protocol/src/protocol/common.rs`

### 服务端实现
- 事件处理：`codex-rs/app-server/src/bespoke_event_handling.rs`

### 父类型引用
- ServerNotification：`codex-rs/app-server-protocol/schema/typescript/ServerNotification.ts`

### 相关通知类型
- ReasoningSummaryTextDeltaNotification
- ReasoningTextDeltaNotification

## 依赖与外部交互

### 上游依赖
- OpenAI Responses API：提供推理内容流
- Codex 核心：处理推理事件并生成通知

### 下游消费
- TUI 应用服务器：`codex-rs/tui_app_server/src/app/app_server_adapter.rs`
- 实时推理展示 UI：显示推理过程

### 通知层级
```
ServerNotification
  └── ReasoningSummaryPartAddedNotification
        └── 触发 UI 创建新的推理摘要部分
```

## 风险、边界与改进建议

### 边界情况
1. **索引跳跃**：summaryIndex 可能不连续（如果部分推理被过滤）
2. **并发通知**：多个推理部分可能同时添加
3. **空推理**：某些模型或配置可能不产生推理摘要

### 潜在风险
1. **顺序依赖**：客户端依赖 summaryIndex 的正确顺序
2. **内存增长**：长时间对话可能积累大量推理部分
3. **UI 性能**：频繁的推理更新可能影响 UI 响应性

### 改进建议
1. **批处理**：考虑批量发送多个部分添加通知
2. **超时处理**：添加推理超时的处理机制
3. **部分限制**：限制最大推理部分数量防止滥用
4. **取消支持**：支持用户取消正在进行的推理展示
5. **压缩传输**：对于大量推理数据考虑压缩
