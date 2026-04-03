# ReasoningTextDeltaNotification.json 研究文档

## 场景与职责

`ReasoningTextDeltaNotification` 是 Codex App-Server Protocol v2 API 中的服务器通知类型，用于向客户端流式传输推理内容的文本增量更新。与 `ReasoningSummaryTextDeltaNotification` 不同，该通知传输的是原始推理内容（reasoning_text）而非摘要（summary_text），用于展示 AI 模型的完整思维过程。

## 功能点目的

1. **原始推理流式传输**: 实时推送 AI 模型的原始推理内容
2. **思维链可视化**: 支持展示模型的完整思考过程（Chain of Thought）
3. **多内容块支持**: 通过 `contentIndex` 支持同一推理项的多个内容块
4. **与摘要分离**: 区分原始推理内容和摘要内容，支持不同展示策略

## 具体技术实现

### 数据结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ReasoningTextDeltaNotification {
    pub thread_id: String,
    pub turn_id: String,
    pub item_id: String,
    pub content_index: i64,
    pub delta: String,
}
```

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `threadId` | string | 是 | 所属线程 ID |
| `turnId` | string | 是 | 所属回合 ID |
| `itemId` | string | 是 | 推理项的唯一标识符 |
| `contentIndex` | integer (int64) | 是 | 目标内容块的索引 |
| `delta` | string | 是 | 新增的文本内容 |

### JSON Schema 结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "properties": {
    "contentIndex": { "format": "int64", "type": "integer" },
    "delta": { "type": "string" },
    "itemId": { "type": "string" },
    "threadId": { "type": "string" },
    "turnId": { "type": "string" }
  },
  "required": ["contentIndex", "delta", "itemId", "threadId", "turnId"],
  "title": "ReasoningTextDeltaNotification",
  "type": "object"
}
```

### 与 ReasoningSummaryTextDeltaNotification 的区别

| 特性 | ReasoningTextDeltaNotification | ReasoningSummaryTextDeltaNotification |
|------|-------------------------------|--------------------------------------|
| 内容类型 | 原始推理内容（reasoning_text） | 推理摘要（summary_text） |
| 索引字段 | `contentIndex` | `summaryIndex` |
| 用途 | 展示完整思维过程 | 展示思维过程摘要 |
| 数据量 | 通常较大 | 通常较小 |
| 用户可见性 | 可配置（可能隐藏） | 通常可见 |

## 关键代码路径与文件引用

### 源文件位置
- **Rust 结构定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - `ReasoningTextDeltaNotification`: 第 4878 行附近

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ReasoningTextDeltaNotification {
    pub thread_id: String,
    pub turn_id: String,
    pub item_id: String,
    pub content_index: i64,
    pub delta: String,
}
```

### Schema 生成
- **生成工具**: `codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs`
- **生成函数**: `export_server_notification_schemas()` 在 `common.rs` 中定义

### 使用位置
- **ServerNotification 定义**: `codex-rs/app-server-protocol/src/protocol/common.rs` 第 913 行
```rust
ReasoningTextDelta => "item/reasoning/textDelta" (v2::ReasoningTextDeltaNotification),
```

### 关联数据结构
在 `RawResponseItemCompletedNotification` 中定义的推理内容类型：

**ReasoningItemContent** (Tagged Union):
- `reasoning_text`: 推理文本内容
- `text`: 普通文本内容

```rust
pub enum ReasoningItemContent {
    ReasoningText { text: String },
    Text { text: String },
}
```

## 依赖与外部交互

### 内部依赖
1. **schemars**: JSON Schema 生成
2. **ts_rs**: TypeScript 类型生成
3. **serde**: 序列化/反序列化

### 外部交互
1. **AI 模型**: 从模型获取推理内容的流式输出
2. **客户端 UI**: 驱动推理内容的实时渲染

### 数据流
```
AI Model (streaming reasoning content)
  -> Codex Core
    -> ReasoningTextDeltaNotification
      -> Client UI (append delta to content[contentIndex])
```

### 通知序列示例
```
ItemStartedNotification (type: reasoning)
  -> ReasoningTextDeltaNotification (contentIndex: 0, delta: "Let me")
  -> ReasoningTextDeltaNotification (contentIndex: 0, delta: " think")
  -> ReasoningTextDeltaNotification (contentIndex: 0, delta: " about")
  -> ...
  -> ReasoningSummaryPartAddedNotification (summaryIndex: 0)
  -> ReasoningSummaryTextDeltaNotification (summaryIndex: 0, delta: "Analyzing")
  -> ...
ItemCompletedNotification
```

## 风险、边界与改进建议

### 风险点
1. **数据量大**: 原始推理内容可能比摘要大得多，产生大量通知
2. **隐私问题**: 原始推理可能包含敏感信息或内部思考
3. **性能影响**: 大量推理内容可能影响客户端渲染性能
4. **存储成本**: 原始推理内容的持久化存储成本较高

### 边界情况
1. **加密内容**: 某些推理内容可能被加密（`encrypted_content` 字段）
2. **空推理**: 某些模型可能不产生推理内容
3. **多内容块**: 复杂推理可能产生多个内容块（contentIndex 递增）

### 改进建议
1. **可配置传输**: 允许客户端选择是否接收原始推理内容：
   ```rust
   // 在 ThreadStartParams 中添加
   pub struct ThreadStartParams {
       // ... existing fields
       pub include_reasoning_content: bool,  // 是否包含原始推理
       pub include_reasoning_summary: bool,  // 是否包含推理摘要
   }
   ```

2. **分层展示**: 支持原始推理和摘要的关联展示：
   ```rust
   pub struct ReasoningTextDeltaNotification {
       // ... existing fields
       pub summary_index: Option<i64>,  // 关联的摘要索引
   }
   ```

3. **截断控制**: 对过长的推理内容实施截断：
   ```rust
   pub struct ReasoningTextDeltaNotification {
       // ... existing fields
       pub is_truncated: bool,  // 是否被截断
       pub total_length: Option<u64>,  // 原始总长度
   }
   ```

4. **延迟加载**: 支持按需获取历史推理内容

5. **压缩传输**: 对推理内容启用更高效的压缩算法
