# ReasoningSummaryTextDeltaNotification.json 研究文档

## 场景与职责

`ReasoningSummaryTextDeltaNotification` 是 Codex App-Server Protocol v2 API 中的服务器通知类型，用于向客户端流式传输推理摘要文本的增量更新。该通知支持实时显示 AI 模型思维过程的摘要内容，与 `ReasoningSummaryPartAddedNotification` 配合使用构建完整的推理摘要。

## 功能点目的

1. **流式摘要更新**: 实时推送推理摘要的文本增量，支持打字机效果
2. **思维过程可视化**: 允许用户实时查看 AI 的思维摘要
3. **增量渲染优化**: 通过 delta 机制减少数据传输量
4. **多部分支持**: 通过 `summaryIndex` 支持同一推理项的多部分摘要

## 具体技术实现

### 数据结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ReasoningSummaryTextDeltaNotification {
    pub thread_id: String,
    pub turn_id: String,
    pub item_id: String,
    pub summary_index: i64,
    pub delta: String,
}
```

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `threadId` | string | 是 | 所属线程 ID |
| `turnId` | string | 是 | 所属回合 ID |
| `itemId` | string | 是 | 推理项的唯一标识符 |
| `summaryIndex` | integer (int64) | 是 | 目标摘要部分的索引 |
| `delta` | string | 是 | 新增的文本内容 |

### JSON Schema 结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "properties": {
    "delta": { "type": "string" },
    "itemId": { "type": "string" },
    "summaryIndex": { "format": "int64", "type": "integer" },
    "threadId": { "type": "string" },
    "turnId": { "type": "string" }
  },
  "required": ["delta", "itemId", "summaryIndex", "threadId", "turnId"],
  "title": "ReasoningSummaryTextDeltaNotification",
  "type": "object"
}
```

## 关键代码路径与文件引用

### 源文件位置
- **Rust 结构定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - `ReasoningSummaryTextDeltaNotification`: 第 4855 行附近

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ReasoningSummaryTextDeltaNotification {
    pub thread_id: String,
    pub turn_id: String,
    pub item_id: String,
    pub summary_index: i64,
    pub delta: String,
}
```

### Schema 生成
- **生成工具**: `codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs`
- **生成函数**: `export_server_notification_schemas()` 在 `common.rs` 中定义

### 使用位置
- **ServerNotification 定义**: `codex-rs/app-server-protocol/src/protocol/common.rs` 第 911 行
```rust
ReasoningSummaryTextDelta => "item/reasoning/summaryTextDelta" (v2::ReasoningSummaryTextDeltaNotification),
```

### 相关通知类型
- `ReasoningSummaryPartAddedNotification`: 新摘要部分添加通知
- `ReasoningTextDeltaNotification`: 推理文本（非摘要）增量通知
- `AgentMessageDeltaNotification`: 助手消息增量通知

## 依赖与外部交互

### 内部依赖
1. **schemars**: JSON Schema 生成
2. **ts_rs**: TypeScript 类型生成
3. **serde**: 序列化/反序列化

### 外部交互
1. **AI 模型**: 从模型获取推理摘要的流式输出
2. **客户端 UI**: 驱动推理摘要的实时渲染

### 数据流
```
AI Model (streaming reasoning summary)
  -> Codex Core
    -> ReasoningSummaryTextDeltaNotification
      -> Client UI (append delta to summary[summaryIndex])
```

### 客户端处理逻辑
```typescript
// 伪代码示例
const summaries: Map<string, string[]> = new Map();

onReasoningSummaryTextDelta(notification) {
  const { itemId, summaryIndex, delta } = notification;
  if (!summaries.has(itemId)) {
    summaries.set(itemId, []);
  }
  const itemSummaries = summaries.get(itemId);
  if (!itemSummaries[summaryIndex]) {
    itemSummaries[summaryIndex] = '';
  }
  itemSummaries[summaryIndex] += delta;
  renderSummary(itemId, summaryIndex, itemSummaries[summaryIndex]);
}
```

## 风险、边界与改进建议

### 风险点
1. **高频通知**: 流式生成时可能产生大量通知，对网络和客户端造成压力
2. **乱序到达**: 网络延迟可能导致 delta 通知乱序到达
3. **重复内容**: 重连后可能收到重复的 delta
4. **大 delta**: 某些模型的单次输出可能很大

### 边界情况
1. **空 delta**: `delta` 为空字符串（可能用于心跳或同步）
2. **Unicode 截断**: delta 可能在多字节字符中间截断
3. **索引跳跃**: `summaryIndex` 可能不连续（如 0, 0, 0, 2, 2...）

### 改进建议
1. **添加序列号**: 支持乱序处理和重复检测：
   ```rust
   pub struct ReasoningSummaryTextDeltaNotification {
       // ... existing fields
       pub sequence: u64,  // 单调递增序列号
   }
   ```

2. **添加完成标记**: 标识某部分摘要已完成：
   ```rust
   pub struct ReasoningSummaryTextDeltaNotification {
       // ... existing fields
       pub is_final: bool,  // 该部分是否已完成
   }
   ```

3. **批量 delta**: 减少高频小通知：
   ```rust
   pub struct ReasoningSummaryTextDeltaNotification {
       pub thread_id: String,
       pub turn_id: String,
       pub item_id: String,
       pub summary_index: i64,
       pub deltas: Vec<String>,  // 批量 deltas
   }
   ```

4. **添加字符编码信息**: 处理多字节字符边界：
   ```rust
   pub struct ReasoningSummaryTextDeltaNotification {
       // ... existing fields
       pub byte_offset: u64,  // 字节偏移量
       pub char_offset: u64,  // 字符偏移量
   }
   ```

5. **压缩选项**: 对大量小 delta 启用压缩
