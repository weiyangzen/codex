# PlanDeltaNotification.json 研究文档

## 场景与职责

`PlanDeltaNotification.json` 是 Codex 应用服务器协议 v2 的 JSON Schema 定义文件，用于描述计划增量通知的结构。

该通知用于向客户端流式传输计划项（Plan Item）的增量更新，支持实时显示 AI 生成的执行计划。这是一个实验性功能，用于改进长任务的可观察性和用户体验。

## 功能点目的

1. **流式计划展示**: 实时展示 AI 正在生成的执行计划
2. **渐进式内容**: 支持计划内容的增量更新，而非等待完整生成
3. **用户反馈**: 让用户提前看到 AI 的思考过程和计划步骤
4. **实验性功能**: 探索计划生成的流式展示模式

## 具体技术实现

### 数据结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "description": "EXPERIMENTAL - proposed plan streaming deltas for plan items. Clients should not assume concatenated deltas match the completed plan item content.",
  "properties": {
    "delta": { "type": "string" },
    "itemId": { "type": "string" },
    "threadId": { "type": "string" },
    "turnId": { "type": "string" }
  },
  "required": ["delta", "itemId", "threadId", "turnId"],
  "title": "PlanDeltaNotification",
  "type": "object"
}
```

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `delta` | string | 是 | 计划内容的增量文本片段 |
| `itemId` | string | 是 | 计划项的唯一标识符 |
| `threadId` | string | 是 | 所属线程 ID |
| `turnId` | string | 是 | 所属回合 ID |

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs:4845
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS, ExperimentalApi)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PlanDeltaNotification {
    pub delta: String,
    pub item_id: String,
    pub thread_id: String,
    pub turn_id: String,
}
```

### 通知注册

```rust
// common.rs 行 899
/// EXPERIMENTAL - proposed plan streaming deltas for plan items.
PlanDelta => "item/plan/delta" (v2::PlanDeltaNotification)
```

### 相关线程项类型

```rust
// ThreadItem 枚举中的 Plan 变体 (v2.rs 行 897-921)
{
  "description": "EXPERIMENTAL - proposed plan item content. The completed plan item is authoritative and may not match the concatenation of `PlanDelta` text.",
  "properties": {
    "id": { "type": "string" },
    "text": { "type": "string" },
    "type": { "enum": ["plan"], "type": "string" }
  },
  "required": ["id", "text", "type"],
  "title": "PlanThreadItem",
  "type": "object"
}
```

## 关键代码路径与文件引用

### 协议定义
- **Rust 结构体**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 4845-4854)
- **JSON Schema**: `codex-rs/app-server-protocol/schema/json/v2/PlanDeltaNotification.json`
- **通知注册**: `codex-rs/app-server-protocol/src/protocol/common.rs` (行 899)
- **实验性标记**: 结构体使用 `#[experimental("item/plan/delta")]` 标记

### 发送方
- **计划生成器**: 在 AI 生成计划时发送增量更新
- **流式响应处理器**: 处理 OpenAI API 的流式响应

### 接收方
- **客户端 UI**: 实时展示计划生成进度
- **计划渲染器**: 将增量内容合并显示

## 依赖与外部交互

### 上游依赖
1. **计划工具**: `codex_protocol::plan_tool` 模块
2. **流式 API**: OpenAI Responses API 的流式输出
3. **SSE 通知通道**: 服务器发送事件通知机制

### 下游使用方
1. **计划展示 UI**: 实时渲染计划内容
2. **进度指示器**: 显示计划生成状态

### 重要注意事项

根据 Schema 描述：
> "Clients should not assume concatenated deltas match the completed plan item content."

这意味着：
1. 增量内容的简单拼接可能不等于最终计划内容
2. 最终计划内容以 `PlanThreadItem` 的 `text` 字段为准
3. 增量通知仅用于展示目的，不应作为持久化数据

## 风险、边界与改进建议

### 潜在风险
1. **内容不一致**: 增量拼接与最终内容可能不一致
2. **消息丢失**: 网络问题可能导致部分增量丢失
3. **性能影响**: 高频增量更新可能影响客户端性能
4. **实验性稳定性**: 作为实验性功能，API 可能变更

### 边界情况
1. **空增量**: `delta` 字段可能为空字符串
2. **乱序到达**: 增量通知可能乱序到达
3. **重复通知**: 同一 `itemId` 可能收到重复增量
4. **未完成计划**: 计划生成可能中断，无最终内容

### 改进建议

#### 1. 添加序列号
```json
{
  "delta": "...",
  "itemId": "...",
  "threadId": "...",
  "turnId": "...",
  "sequence": 5,
  "totalSequences": null
}
```

#### 2. 添加增量类型
```json
{
  "delta": "...",
  "deltaType": "text", // 或 "step", "title", "summary"
  "itemId": "...",
  "threadId": "...",
  "turnId": "..."
}
```

#### 3. 添加时间戳
```json
{
  "delta": "...",
  "timestamp": 1712345678,
  "itemId": "...",
  "threadId": "...",
  "turnId": "..."
}
```

#### 4. 添加完成标记
```json
{
  "delta": "",
  "isComplete": true,
  "finalText": "完整的计划内容",
  "itemId": "...",
  "threadId": "...",
  "turnId": "..."
}
```

### 最佳实践
1. **仅用于展示**: 将增量内容仅用于实时展示，不持久化
2. **使用最终内容**: 以 `PlanThreadItem.text` 作为权威内容
3. **防抖渲染**: 实现防抖机制避免过于频繁的 UI 更新
4. **错误恢复**: 处理增量丢失或乱序的情况
5. **功能开关**: 作为实验性功能，提供开关控制

### 相关通知
- `TurnPlanUpdatedNotification` - 计划更新通知
- `ItemStartedNotification` - 计划项开始
- `ItemCompletedNotification` - 计划项完成
- `PlanThreadItem` - 最终的计划线程项

### 实验性状态
该功能标记为 `EXPERIMENTAL`，意味着：
1. API 可能在将来版本中变更
2. 功能可能不稳定或存在已知问题
3. 客户端应实现优雅降级
4. 生产环境使用需谨慎
