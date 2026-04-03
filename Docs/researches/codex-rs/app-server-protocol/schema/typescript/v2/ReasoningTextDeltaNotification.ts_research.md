# ReasoningTextDeltaNotification 研究文档

## 场景与职责

`ReasoningTextDeltaNotification` 是 Codex App Server Protocol v2 中定义的服务器通知类型，用于向客户端流式传输 AI 模型的推理过程文本增量。该通知在模型进行推理（reasoning）时实时发送，让客户端能够观察到模型的思考过程。

**核心职责：**
- 实时推送模型推理文本的增量更新
- 支持多内容索引（`contentIndex`）的复杂推理场景
- 与 `threadId`、`turnId`、`itemId` 关联，精确定位推理内容所属的对话上下文

**使用场景：**
- TUI（终端用户界面）实时显示模型的推理过程
- IDE 插件展示 AI 的逐步思考过程
- 调试和监控模型行为

## 功能点目的

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | `string` | 所属线程的唯一标识符 |
| `turnId` | `string` | 所属回合（turn）的唯一标识符 |
| `itemId` | `string` | 具体消息项的唯一标识符 |
| `delta` | `string` | 新增的推理文本片段 |
| `contentIndex` | `number` | 内容索引，用于支持多部分推理内容 |

**设计目的：**
1. **流式体验**：通过 `delta` 字段实现逐字/逐句的流式显示，提升用户体验
2. **精准定位**：通过三级 ID（thread/turn/item）确保消息能够准确路由到正确的 UI 组件
3. **多内容支持**：`contentIndex` 支持一个消息项包含多个独立的推理内容块

## 具体技术实现

### TypeScript 定义
```typescript
export type ReasoningTextDeltaNotification = { 
  threadId: string, 
  turnId: string, 
  itemId: string, 
  delta: string, 
  contentIndex: number 
};
```

### Rust 源码定义
位于 `codex-rs/app-server-protocol/src/protocol/v2.rs`：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ReasoningTextDeltaNotification {
    pub thread_id: String,
    pub turn_id: String,
    pub item_id: String,
    pub delta: String,
    pub content_index: i32,
}
```

### 序列化特性
- 使用 `serde(rename_all = "camelCase")` 确保 JSON 字段名为 camelCase 风格
- 使用 `ts-rs` 库自动生成 TypeScript 类型定义
- 使用 `schemars` 生成 JSON Schema 用于验证

## 关键代码路径与文件引用

### 定义位置
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构体定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 服务器通知枚举定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/ReasoningTextDeltaNotification.ts` | 生成的 TypeScript 类型 |
| `codex-rs/app-server-protocol/schema/json/v2/ReasoningTextDeltaNotification.json` | 生成的 JSON Schema |

### 使用位置
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/src/bespoke_event_handling.rs` | 事件处理逻辑 |
| `codex-rs/tui/src/chatwidget.rs` | TUI 组件接收并显示推理内容 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | TUI App Server 的聊天组件 |

### 通知注册
在 `codex-rs/app-server-protocol/src/protocol/common.rs` 中注册为服务器通知：
```rust
server_notification_definitions! {
    // ...
    ReasoningTextDelta => "item/reasoning/textDelta" (v2::ReasoningTextDeltaNotification),
    // ...
}
```

## 依赖与外部交互

### 内部依赖
- `serde`：序列化/反序列化
- `schemars`：JSON Schema 生成
- `ts-rs`：TypeScript 类型生成

### 外部交互
1. **与 OpenAI Responses API 的交互**：
   - 接收来自 OpenAI API 的 reasoning 内容流
   - 将原始流转换为 `ReasoningTextDeltaNotification` 通知

2. **与客户端的交互**：
   - 通过 JSON-RPC 通知机制发送给连接的客户端
   - 客户端（TUI/IDE 插件）接收并渲染推理内容

### 相关类型
- `ReasoningSummaryTextDeltaNotification`：推理摘要的增量通知
- `ReasoningSummaryPartAddedNotification`：推理摘要部分添加通知

## 风险、边界与改进建议

### 潜在风险
1. **性能风险**：高频的增量通知可能导致网络拥塞，特别是在推理内容较长时
2. **顺序问题**：在网络不稳定情况下，增量消息可能乱序到达
3. **内存累积**：客户端如果不及时清理，大量增量消息可能导致内存增长

### 边界情况
1. **空 delta**：模型可能发送空的增量内容，客户端需要正确处理
2. **contentIndex 越界**：客户端应验证 contentIndex 的合理性
3. **并发推理**：多线程场景下，同一 itemId 可能同时产生多个 contentIndex

### 改进建议
1. **批处理优化**：考虑对高频小增量进行批处理，减少网络往返
2. **压缩传输**：对于长推理内容，考虑使用压缩算法减少传输大小
3. **心跳机制**：添加心跳或进度通知，让客户端知道推理仍在进行
4. **取消支持**：支持客户端取消正在进行的推理流，节省资源
5. **历史回放**：考虑支持推理内容的持久化和历史回放功能

### 相关配置
- `model_reasoning_summary`：控制是否生成推理摘要
- `model_reasoning_effort`：控制推理努力程度（low/medium/high）
