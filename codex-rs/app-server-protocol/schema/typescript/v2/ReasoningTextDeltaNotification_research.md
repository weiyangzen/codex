# ReasoningTextDeltaNotification 研究文档

## 1. 场景与职责

`ReasoningTextDeltaNotification` 是 Codex app-server-protocol v2 协议中的服务器通知类型，用于向客户端流式传输 AI 推理过程中的文本增量更新。当 AI 模型进行推理（reasoning）并产生中间思考内容时，服务器通过此通知将增量文本推送给客户端，实现实时的推理过程可视化。

### 使用场景
- **实时推理展示**：在 AI 进行复杂推理时，向用户展示模型的思考过程
- **流式内容更新**：支持增量更新，避免一次性传输大量文本
- **多内容块支持**：通过 `contentIndex` 支持多个推理内容块的管理

## 2. 功能点目的

该类型的核心目的是：
1. **透明度**：让用户了解 AI 的推理过程，提高可解释性
2. **实时反馈**：在长时间推理过程中提供即时视觉反馈
3. **增量传输**：优化网络传输，只发送新增的文本片段（delta）

### 与相关类型的区别
- `ReasoningSummaryTextDeltaNotification`：用于推理摘要的增量更新
- `ReasoningSummaryPartAddedNotification`：当新的推理部分被添加时通知
- `ReasoningTextDeltaNotification`：用于实际推理内容的增量更新

## 3. 具体技术实现

### TypeScript 类型定义
```typescript
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
| `threadId` | `string` | 所属线程的唯一标识符 |
| `turnId` | `string` | 所属回合的唯一标识符 |
| `itemId` | `string` | 具体推理项的唯一标识符 |
| `delta` | `string` | 新增的文本内容片段 |
| `contentIndex` | `number` | 内容块的索引（对应 Rust 中的 `i64`） |

### Rust 源实现
```rust
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

## 4. 关键代码路径与文件引用

### 协议定义
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 4875-4885)
- **TypeScript 文件**: `codex-rs/app-server-protocol/schema/typescript/v2/ReasoningTextDeltaNotification.ts`

### 通知注册
- **通知类型**: `codex-rs/app-server-protocol/src/protocol/common.rs` (行 913)
  ```rust
  ReasoningTextDelta => "item/reasoning/textDelta" (v2::ReasoningTextDeltaNotification)
  ```

### 使用位置
- **事件处理**: `codex-rs/app-server/src/bespoke_event_handling.rs` (行 1278)
  - 构造并发送 `ReasoningTextDeltaNotification`
- **TUI 处理**: `codex-rs/tui_app_server/src/chatwidget.rs` (行 5867)
  - 处理接收到的推理文本增量通知
- **适配器**: `codex-rs/tui_app_server/src/app/app_server_adapter.rs` (行 474, 746)
  - 将通知转换为应用内部事件

### JSON Schema
- `codex-rs/app-server-protocol/schema/json/ServerNotification.json`
- `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`
- `codex-rs/app-server-protocol/schema/json/v2/ReasoningTextDeltaNotification.json`

## 5. 依赖与外部交互

### 导入依赖
- 无直接导入的类型（所有字段为基础类型）

### 被依赖类型
- `ServerNotification` (`codex-rs/app-server-protocol/schema/typescript/ServerNotification.ts`)
  - 将 `ReasoningTextDeltaNotification` 作为联合类型的变体之一

### 相关枚举
- `ServerNotification::ReasoningTextDelta` - 在 `common.rs` 中定义的通知变体

## 6. 风险、边界与改进建议

### 潜在风险
1. **内容索引溢出**：`contentIndex` 使用 `i64` 类型，在极端情况下可能出现索引管理问题
2. **增量顺序**：如果通知乱序到达，客户端需要正确处理增量拼接
3. **内存累积**：长时间推理可能产生大量增量通知，需要合理的缓冲区管理

### 边界情况
- **空 delta**：`delta` 字段可能为空字符串，客户端应优雅处理
- **负索引**：虽然 `contentIndex` 类型为 `i64`，但实际应为非负数
- **并发内容块**：多个 `contentIndex` 可能同时更新，客户端需分别管理

### 改进建议
1. **添加序列号**：考虑添加序列号字段以帮助客户端检测乱序或丢失的通知
2. **压缩支持**：对于大量小增量，考虑批量发送或压缩
3. **心跳机制**：长时间无增量时发送心跳，帮助客户端检测连接状态
4. **类型优化**：`contentIndex` 可考虑使用 `u32` 或 `usize` 类型，更符合索引语义

### 相关测试
- 测试文件：`codex-rs/app-server/tests/suite/v2/` 中可能包含相关集成测试
- TUI 测试：`codex-rs/tui_app_server/src/chatwidget.rs` 中的处理逻辑需要测试覆盖
