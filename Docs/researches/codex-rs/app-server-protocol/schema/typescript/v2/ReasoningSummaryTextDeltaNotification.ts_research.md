# ReasoningSummaryTextDeltaNotification.ts 研究文档

## 场景与职责

`ReasoningSummaryTextDeltaNotification.ts` 定义了推理摘要文本增量通知的数据结构，用于在服务器向客户端流式传输推理摘要的文本内容时使用。这是 Codex 实时推理展示功能的核心组件，支持逐字显示模型的推理过程摘要。

## 功能点目的

该类型用于：
1. **流式文本传输**：以增量方式传输推理摘要文本
2. **实时 UI 更新**：支持客户端实时显示推理过程
3. **带宽优化**：相比完整传输，增量传输减少数据量
4. **用户体验**：提供类似打字机效果的推理展示

## 具体技术实现

### 数据结构定义

```typescript
export type ReasoningSummaryTextDeltaNotification = { 
  threadId: string,      // 所属线程ID
  turnId: string,        // 所属回合ID
  itemId: string,        // 响应项ID
  delta: string,         // 文本增量内容
  summaryIndex: number,  // 对应的摘要部分索引
};
```

### 字段详解

| 字段 | 类型 | 说明 |
|------|------|------|
| threadId | string | 标识此推理文本所属的对话线程 |
| turnId | string | 标识此推理文本所属的具体回合 |
| itemId | string | 关联的响应项标识符 |
| delta | string | 新增的文本内容片段 |
| summaryIndex | number | 此增量对应的摘要部分索引 |

### Rust 协议定义

在 `codex-rs/app-server-protocol/src/protocol/v2.rs` 和 `common.rs` 中：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ReasoningSummaryTextDeltaNotification {
    pub thread_id: String,
    pub turn_id: String,
    pub item_id: String,
    pub delta: String,
    pub summary_index: usize,
}
```

### 事件序列

```
1. ReasoningSummaryPartAddedNotification
   { threadId, turnId, itemId, summaryIndex: 0 }
   
2. ReasoningSummaryTextDeltaNotification
   { threadId, turnId, itemId, delta: "Let me", summaryIndex: 0 }
   
3. ReasoningSummaryTextDeltaNotification
   { threadId, turnId, itemId, delta: " analyze", summaryIndex: 0 }
   
4. ReasoningSummaryTextDeltaNotification
   { threadId, turnId, itemId, delta: " this...", summaryIndex: 0 }
```

### 服务端发送逻辑

在 `codex-rs/app-server/src/bespoke_event_handling.rs` 中，当从 OpenAI API 接收到推理摘要增量时：

```rust
fn handle_reasoning_summary_delta(
    &mut self,
    thread_id: ThreadId,
    turn_id: TurnId,
    item_id: String,
    delta: String,
    summary_index: usize,
) {
    let notification = ReasoningSummaryTextDeltaNotification {
        thread_id: thread_id.to_string(),
        turn_id: turn_id.to_string(),
        item_id,
        delta,
        summary_index,
    };
    self.send_server_notification(notification.into());
}
```

### 客户端处理

在 `codex-rs/tui_app_server/src/app/app_server_adapter.rs` 中：

```rust
// 接收增量并追加到对应的推理摘要部分
match notification {
    ReasoningSummaryTextDeltaNotification { delta, summary_index, .. } => {
        self.append_to_reasoning_summary(summary_index, &delta);
    }
}
```

## 关键代码路径与文件引用

### TypeScript 类型定义
- 文件：`codex-rs/app-server-protocol/schema/typescript/v2/ReasoningSummaryTextDeltaNotification.ts`

### Rust 协议定义
- V2 协议：`codex-rs/app-server-protocol/src/protocol/v2.rs`
- 通用协议：`codex-rs/app-server-protocol/src/protocol/common.rs`

### 服务端实现
- 事件处理：`codex-rs/app-server/src/bespoke_event_handling.rs`

### 客户端消费
- TUI 适配器：`codex-rs/tui_app_server/src/app/app_server_adapter.rs`

### 父类型引用
- ServerNotification：`codex-rs/app-server-protocol/schema/typescript/ServerNotification.ts`

## 依赖与外部交互

### 上游依赖
- OpenAI Responses API：提供 reasoning.summary 增量流
- SSE 流处理：通过 Server-Sent Events 接收推理数据

### 下游消费
- TUI 实时推理展示：逐字显示推理过程
- IDE 扩展：在编辑器中展示推理摘要

### 与相关通知的协作

```
ReasoningSummaryPartAddedNotification
    ↓ 创建摘要部分
ReasoningSummaryTextDeltaNotification (多个)
    ↓ 累积文本
最终形成完整的推理摘要
```

## 风险、边界与改进建议

### 边界情况
1. **空增量**：delta 可能为空字符串（心跳或格式需要）
2. **乱序到达**：理论上应按顺序到达，但网络可能导致乱序
3. **索引越界**：summaryIndex 可能引用不存在的部分

### 潜在风险
1. **高频更新**：大量小增量可能导致 UI 频繁重绘
2. **内存累积**：长时间累积增量可能消耗大量内存
3. **编码问题**：delta 字符串的编码处理

### 改进建议
1. **节流机制**：客户端对高频更新进行节流
2. **批量合并**：服务端考虑合并小增量减少通知次数
3. **完整回退**：提供获取完整推理摘要的备用机制
4. **压缩传输**：对重复文本使用引用或压缩
5. **取消支持**：允许用户停止接收推理更新
