# ReasoningTextDeltaNotification 研究文档

## 场景与职责

`ReasoningTextDeltaNotification` 是 Codex App Server Protocol v2 中用于流式传输模型推理过程文本增量更新的通知类型。当模型进行推理（reasoning）时，服务器通过此通知将推理内容的增量片段发送给客户端，实现实时的推理过程展示。

该类型在支持推理模型的交互中扮演关键角色，使用户能够观察到模型的思考过程，增强交互的透明度和可解释性。

## 功能点目的

1. **流式推理展示**：实时展示模型的推理过程
2. **增量更新**：通过 delta 字段传输文本增量，减少带宽使用
3. **内容索引**：支持多部分推理内容的索引定位
4. **生命周期关联**：通过 threadId、turnId、itemId 关联到具体的对话上下文

## 具体技术实现

### 数据结构

```rust
// Rust 定义 (codex-rs/app-server-protocol/src/protocol/v2.rs)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ReasoningTextDeltaNotification {
    pub thread_id: String,
    pub turn_id: String,
    pub item_id: String,
    pub delta: String,
    #[ts(type = "number")]
    pub content_index: i64,
}
```

```typescript
// TypeScript 生成类型 (schema/typescript/v2/ReasoningTextDeltaNotification.ts)
export type ReasoningTextDeltaNotification = { 
    threadId: string, 
    turnId: string, 
    itemId: string, 
    delta: string, 
    contentIndex: number, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `thread_id` | `String` | 所属线程 ID |
| `turn_id` | `String` | 所属回合 ID |
| `item_id` | `String` | 推理项 ID |
| `delta` | `String` | 推理文本的增量内容 |
| `content_index` | `i64` | 内容部分的索引（支持多部分推理） |

### 相关通知类型

```rust
// 推理摘要文本增量
pub struct ReasoningSummaryTextDeltaNotification {
    pub thread_id: String,
    pub turn_id: String,
    pub item_id: String,
    pub delta: String,
    pub summary_index: i64,
}

// 推理摘要部分添加
pub struct ReasoningSummaryPartAddedNotification {
    pub thread_id: String,
    pub turn_id: String,
    pub item_id: String,
    pub summary_index: i64,
}
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 4875-4885)
- **TypeScript 生成**: `codex-rs/app-server-protocol/schema/typescript/v2/ReasoningTextDeltaNotification.ts`

### 相关类型
- `ReasoningSummaryTextDeltaNotification`: 推理摘要增量
- `ReasoningSummaryPartAddedNotification`: 推理摘要部分添加
- `ThreadItem::Reasoning`: 推理项类型

### 使用场景
- 服务器向客户端发送推理过程更新
- 客户端 UI 实时展示推理内容
- TUI 应用中更新推理面板

## 依赖与外部交互

### 内部依赖
- `serde`: 序列化/反序列化
- `schemars`: JSON Schema 生成
- `ts_rs`: TypeScript 类型生成

### 协议交互

**通知示例**:
```json
{
    "jsonrpc": "2.0",
    "method": "reasoningTextDelta",
    "params": {
        "threadId": "thread-123",
        "turnId": "turn-456",
        "itemId": "item-789",
        "delta": "Let me analyze this step by step...",
        "contentIndex": 0
    }
}
```

### 消息流程

1. 用户发送请求
2. 模型开始推理
3. 服务器发送 `ItemStartedNotification`（包含 `ThreadItem::Reasoning`）
4. 服务器持续发送 `ReasoningTextDeltaNotification`（推理增量）
5. 推理完成，服务器可能发送 `ReasoningSummaryTextDeltaNotification`
6. 服务器发送 `ItemCompletedNotification`

## 风险、边界与改进建议

### 当前限制
1. **无结束标记**：没有明确的通知表示推理内容结束
2. **顺序依赖**：客户端需要按顺序拼接 delta 内容
3. **无时间戳**：不包含时间信息，无法展示推理耗时

### 边界情况
1. **空 delta**：delta 字段可能为空字符串
2. **乱序到达**：网络环境下通知可能乱序到达
3. **大量增量**：长时间推理可能产生大量增量通知

### 改进建议
1. **添加时间戳**：记录推理开始时间和每个增量的时间
2. **添加结束标记**：明确标识推理内容结束
3. **批量发送**：对于快速产生的增量，考虑批量发送
4. **压缩支持**：对于大量文本，考虑压缩传输
5. **添加 token 计数**：统计推理消耗的 token 数量

### 兼容性注意
- 使用 camelCase 命名确保与 TypeScript 惯例一致
- `content_index` 使用 `i64` 类型，TypeScript 映射为 `number`
- 客户端应处理通知乱序的情况

### 与类似类型的对比

| 类型 | 用途 | 区别 |
|------|------|------|
| `ReasoningTextDeltaNotification` | 推理内容增量 | 原始推理内容 |
| `ReasoningSummaryTextDeltaNotification` | 推理摘要增量 | 摘要内容 |
| `AgentMessageDeltaNotification` | 助手消息增量 | 最终输出内容 |
| `PlanDeltaNotification` | 计划增量 | 计划步骤更新 |
