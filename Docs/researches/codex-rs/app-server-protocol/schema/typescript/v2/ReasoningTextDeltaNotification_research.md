# ReasoningTextDeltaNotification 研究文档

## 场景与职责

`ReasoningTextDeltaNotification` 是 Codex app-server-protocol v2 协议中的服务器通知类型，用于向客户端流式传输 AI 推理过程中的文本增量更新。当 AI 模型进行推理（reasoning）并产生中间思考内容时，服务器通过此通知将增量文本推送给客户端，实现实时的推理过程可视化。

在 Codex 的流式响应体系中，`ReasoningTextDeltaNotification` 承担以下职责：
1. **推理可视化**：向用户展示 AI 的推理过程
2. **增量传输**：通过增量更新减少网络传输量
3. **实时反馈**：提供低延迟的推理内容更新
4. **内容索引**：支持多段推理内容的正确排序

## 功能点目的

### 核心功能
- **增量推送**：每次只发送新增的推理文本片段（delta）
- **上下文关联**：通过 `threadId`, `turnId`, `itemId` 关联到具体的对话上下文
- **内容排序**：通过 `contentIndex` 支持多段推理内容的索引
- **流式体验**：配合其他 delta 通知实现完整的流式交互

### 设计意图
- **与 ReasoningSummary 区分**：专门用于实际推理内容，而非摘要
- **增量效率**：避免重复传输完整内容，减少带宽消耗
- **可组合性**：可以与其他通知（如 `AgentMessageDeltaNotification`）组合使用

## 具体技术实现

### 数据结构定义

**TypeScript 定义**（`ReasoningTextDeltaNotification.ts`）：
```typescript
export type ReasoningTextDeltaNotification = { 
  threadId: string, 
  turnId: string, 
  itemId: string, 
  delta: string, 
  contentIndex: number, 
};
```

**Rust 定义**（`v2.rs` 行 4878-4885）：
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

### 关键字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | `string` | 所属线程的唯一标识符 |
| `turnId` | `string` | 所属回合的唯一标识符 |
| `itemId` | `string` | 推理项的唯一标识符 |
| `delta` | `string` | 新增的推理文本片段 |
| `contentIndex` | `number` | 内容索引，用于排序多段推理内容 |

### 通知流程

```
AI 模型生成推理内容
  ↓
bespoke_event_handling.rs 行 1278
  ↓
构造 ReasoningTextDeltaNotification
  ↓
ServerNotification::ReasoningTextDelta
  ↓
序列化为 JSON
  ↓
通过 WebSocket 推送给客户端
  ↓
客户端 UI 更新显示
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs` 行 4878-4885
- **TypeScript 生成**：`codex-rs/app-server-protocol/schema/typescript/v2/ReasoningTextDeltaNotification.ts`
- **JSON Schema**：`codex-rs/app-server-protocol/schema/json/ServerNotification.json`

### 使用位置
- **ServerNotification 定义**：`common.rs` 行 913 - 注册为服务器通知
- **事件处理器**：`bespoke_event_handling.rs` 行 1278 - 构造并发送通知
- **TypeScript 联合类型**：`ServerNotification.ts` - 作为联合类型的变体

### 相关类型
- `ReasoningSummaryTextDeltaNotification`：推理摘要的增量通知（行 4855-4862）
- `ReasoningSummaryPartAddedNotification`：推理摘要部分添加通知（行 4867-4873）
- `AgentMessageDeltaNotification`：代理消息的增量通知（行 4833-4838）

### 相关通知对比

| 通知类型 | 用途 | 内容 |
|----------|------|------|
| `ReasoningTextDeltaNotification` | 实际推理内容 | 原始推理文本 |
| `ReasoningSummaryTextDeltaNotification` | 推理摘要 | 摘要文本 |
| `ReasoningSummaryPartAddedNotification` | 摘要部分添加 | 索引信息 |

## 依赖与外部交互

### 依赖项
- `serde`：序列化/反序列化支持
- `schemars`：JSON Schema 生成
- `ts-rs`：TypeScript 类型生成

### 上游依赖
- `CoreAgentMessageContent`（核心协议）：提供推理内容来源

### 下游使用
- `ServerNotification`：作为服务器通知的变体之一
- 客户端 UI：接收并展示推理内容

### 协议集成
- 通知方法名：`item/reasoning/textDelta`（`common.rs` 行 913）
- 方向：Server → Client
- 传输方式：WebSocket JSON-RPC 通知

## 风险、边界与改进建议

### 潜在风险
1. **乱序到达**：网络延迟可能导致增量通知乱序到达
2. **重复内容**：重连后可能收到重复的 delta
3. **大量小消息**：频繁的小增量可能导致消息过多
4. **客户端处理压力**：快速连续的 delta 更新可能造成 UI 卡顿

### 边界情况
1. **空 delta**：`delta` 为空字符串时的处理
2. **负索引**：`contentIndex` 为负数时的处理
3. **超大 delta**：单条 delta 过大的内存处理
4. **并发推理**：多个推理项同时更新的情况

### 改进建议
1. **可靠性增强**：
   - 添加序列号或版本号检测乱序和重复
   - 实现客户端去重机制
   - 添加确认机制确保关键 delta 送达

2. **性能优化**：
   - 实现 delta 合并，减少消息数量
   - 添加节流（throttling）和防抖（debouncing）
   - 支持批量 delta 传输

3. **功能扩展**：
   ```rust
   pub struct ReasoningTextDeltaNotification {
       // 现有字段...
       /// Delta 的序列号，用于排序和去重
       pub sequence: u64,
       /// 是否为最后一条 delta
       pub is_final: bool,
       /// 推理阶段（如 "planning", "analyzing", "concluding"）
       pub stage: Option<String>,
   }
   ```

4. **压缩支持**：
   - 对大量重复的 delta 考虑压缩传输
   - 使用 diff 算法减少传输量

5. **可观测性**：
   - 添加推理耗时统计
   - 记录 delta 数量和大小指标
   - 支持推理回放功能

6. **客户端优化**：
   - 提供虚拟列表优化大量推理内容的渲染
   - 支持推理内容的折叠/展开
   - 添加推理进度指示器
