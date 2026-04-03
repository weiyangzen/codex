# ReasoningSummaryPartAddedNotification.json 研究文档

## 场景与职责

`ReasoningSummaryPartAddedNotification` 是 Codex App-Server Protocol v2 API 中的服务器通知类型，用于通知客户端推理摘要的新部分已添加。该通知在 AI 模型生成推理内容时发送，支持流式显示模型的思维过程摘要。

## 功能点目的

1. **推理摘要流式更新**: 实时通知客户端推理摘要的新部分已生成
2. **思维过程可视化**: 支持 UI 展示模型的推理步骤和思维链
3. **增量更新机制**: 通过 `summaryIndex` 支持摘要的增量构建
4. **会话状态同步**: 保持客户端与服务器推理状态一致

## 具体技术实现

### 数据结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ReasoningSummaryPartAddedNotification {
    pub thread_id: String,
    pub turn_id: String,
    pub item_id: String,
    pub summary_index: i64,
}
```

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `threadId` | string | 是 | 所属线程 ID |
| `turnId` | string | 是 | 所属回合 ID |
| `itemId` | string | 是 | 推理项的唯一标识符 |
| `summaryIndex` | integer (int64) | 是 | 新添加摘要部分的索引位置 |

### JSON Schema 结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "properties": {
    "itemId": { "type": "string" },
    "summaryIndex": { "format": "int64", "type": "integer" },
    "threadId": { "type": "string" },
    "turnId": { "type": "string" }
  },
  "required": ["itemId", "summaryIndex", "threadId", "turnId"],
  "title": "ReasoningSummaryPartAddedNotification",
  "type": "object"
}
```

## 关键代码路径与文件引用

### 源文件位置
- **Rust 结构定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - `ReasoningSummaryPartAddedNotification`: 第 4867 行附近

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ReasoningSummaryPartAddedNotification {
    pub thread_id: String,
    pub turn_id: String,
    pub item_id: String,
    pub summary_index: i64,
}
```

### Schema 生成
- **生成工具**: `codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs`
- **生成函数**: `export_server_notification_schemas()` 在 `common.rs` 中定义

### 使用位置
- **ServerNotification 定义**: `codex-rs/app-server-protocol/src/protocol/common.rs` 第 912 行
```rust
ReasoningSummaryPartAdded => "item/reasoning/summaryPartAdded" (v2::ReasoningSummaryPartAddedNotification),
```

### 相关通知类型
- `ReasoningSummaryTextDeltaNotification`: 推理摘要文本增量更新
- `ReasoningTextDeltaNotification`: 推理文本增量更新
- `ItemStartedNotification`: 项开始通知
- `ItemCompletedNotification`: 项完成通知

## 依赖与外部交互

### 内部依赖
1. **schemars**: JSON Schema 生成
2. **ts_rs**: TypeScript 类型生成
3. **serde**: 序列化/反序列化

### 外部交互
1. **AI 模型**: 从模型获取推理摘要生成事件
2. **客户端 UI**: 通知客户端更新推理显示

### 关联数据结构
- **ReasoningItem**: 推理项类型，在 `RawResponseItemCompletedNotification` 中定义
  - `content`: 推理内容数组
  - `summary`: 推理摘要数组
  - `encrypted_content`: 加密内容（如适用）

### 通知序列
典型的推理摘要通知序列：
```
ItemStartedNotification (type: reasoning)
  -> ReasoningSummaryPartAddedNotification (summaryIndex: 0)
  -> ReasoningSummaryTextDeltaNotification (summaryIndex: 0, delta: "...")
  -> ReasoningSummaryPartAddedNotification (summaryIndex: 1)
  -> ReasoningSummaryTextDeltaNotification (summaryIndex: 1, delta: "...")
  -> ...
ItemCompletedNotification
```

## 风险、边界与改进建议

### 风险点
1. **索引越界**: `summaryIndex` 可能超出客户端当前缓存范围
2. **顺序错乱**: 网络延迟可能导致通知到达顺序与生成顺序不一致
3. **高频通知**: 快速生成摘要时可能产生大量通知，影响性能

### 边界情况
1. **空摘要**: 某些推理项可能没有摘要部分
2. **单一部分**: 简单推理可能只有一个摘要部分
3. **并发推理**: 多个推理项同时生成时，需要正确关联 `itemId`

### 改进建议
1. **添加内容预览**: 考虑添加摘要内容的预览或摘要类型：
   ```rust
   pub struct ReasoningSummaryPartAddedNotification {
       // ... existing fields
       pub summary_type: SummaryType,  // e.g., "planning", "analysis", "conclusion"
       pub preview: String,            // 前 N 个字符预览
   }
   ```

2. **添加总数信息**: 帮助客户端预估总长度：
   ```rust
   pub struct ReasoningSummaryPartAddedNotification {
       // ... existing fields
       pub total_parts: Option<i64>,   // 总部分数（如已知）
   }
   ```

3. **批量通知**: 对高频场景支持批量通知：
   ```rust
   pub struct ReasoningSummaryPartsAddedNotification {
       pub thread_id: String,
       pub turn_id: String,
       pub item_id: String,
       pub summary_indices: Vec<i64>,  // 批量索引
   }
   ```

4. **与 ReasoningTextDelta 合并**: 考虑将 PartAdded 和 TextDelta 合并为统一通知
