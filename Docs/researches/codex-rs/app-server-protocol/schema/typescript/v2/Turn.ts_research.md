# Turn 类型研究报告

## 场景与职责

`Turn` 是 Codex 对话系统的核心概念，表示用户与 AI 之间的一次完整交互回合。它封装了回合的标识、状态、包含的项目以及可能的错误信息，是线程历史管理和状态追踪的基础单元。

**核心使用场景：**

1. **对话历史管理**：记录和展示用户与 AI 的完整交互历史
2. **状态追踪**：监控回合的执行状态（进行中、已完成、已中断、失败）
3. **错误处理**：当回合执行失败时，提供详细的错误信息
4. **上下文恢复**：通过 `thread/resume` 或 `thread/fork` 恢复对话上下文
5. **流式更新**：在回合执行过程中实时更新项目列表

**典型生命周期：**
```
TurnStart -> InProgress -> [Completed | Interrupted | Failed]
```

## 功能点目的

该类型的设计目的包括：

1. **回合标识**：通过唯一 ID 标识每个回合
2. **状态管理**：明确回合的执行状态和最终结果
3. **项目聚合**：包含回合中产生的所有项目（消息、工具调用等）
4. **错误传播**：当回合失败时，提供可操作的错误信息
5. **懒加载优化**：非恢复场景下 `items` 为空，优化性能

**字段设计意图：**

| 字段 | 目的 |
|------|------|
| `id` | 唯一标识回合，用于引用和状态追踪 |
| `items` | 回合中的项目列表（消息、工具调用结果等） |
| `status` | 回合执行状态（Completed/Interrupted/Failed/InProgress） |
| `error` | 失败时的错误详情，`null` 表示无错误 |

## 具体技术实现

### 数据结构定义

**TypeScript 定义（生成代码）：**
```typescript
import type { ThreadItem } from "./ThreadItem";
import type { TurnError } from "./TurnError";
import type { TurnStatus } from "./TurnStatus";

export type Turn = { 
  id: string, 
  /**
   * Only populated on a `thread/resume` or `thread/fork` response.
   * For all other responses and notifications returning a Turn,
   * the items field will be an empty list.
   */
  items: Array<ThreadItem>, 
  status: TurnStatus, 
  /**
   * Only populated when the Turn's status is failed.
   */
  error: TurnError | null, 
};
```

**Rust 源定义：**
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct Turn {
    pub id: String,
    /// Only populated on a `thread/resume` or `thread/fork` response.
    /// For all other responses and notifications returning a Turn,
    /// the items field will be an empty list.
    pub items: Vec<ThreadItem>,
    pub status: TurnStatus,
    /// Only populated when the Turn's status is failed.
    pub error: Option<TurnError>,
}
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `String` / `string` | 回合的唯一标识符 |
| `items` | `Vec<ThreadItem>` / `Array<ThreadItem>` | 回合中的项目列表，通常仅在恢复时填充 |
| `status` | `TurnStatus` | 回合状态：Completed、Interrupted、Failed、InProgress |
| `error` | `Option<TurnError>` / `TurnError \| null` | 错误详情，仅在 Failed 状态时非空 |

### 关联类型

| 类型 | 关系 | 说明 |
|------|------|------|
| `ThreadItem` | 子元素 | 回合中的项目（消息、工具调用等） |
| `TurnStatus` | 状态枚举 | 回合可能的状态值 |
| `TurnError` | 错误详情 | 失败时的错误信息 |
| `TurnStartParams` | 请求参数 | 启动新回合的参数 |
| `TurnStartResponse` | 响应 | 包含新创建的 `Turn` |

### 状态流转

```
                    ┌─────────────┐
                    │   TurnStart  │
                    └──────┬──────┘
                           │
                           ▼
                    ┌─────────────┐
         ┌─────────│  InProgress  │─────────┐
         │         └──────┬──────┘         │
         │                │                │
         ▼                ▼                ▼
   ┌─────────┐      ┌──────────┐     ┌─────────┐
   │Completed│      │Interrupted│     │ Failed  │
   └─────────┘      └──────────┘     └────┬────┘
                                          │
                                          ▼
                                    ┌───────────┐
                                    │  TurnError │
                                    └───────────┘
```

## 关键代码路径与文件引用

### 定义文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 3580-3592) | Rust 结构体定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/Turn.ts` | TypeScript 类型定义（自动生成） |
| `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json` | JSON Schema 定义 |

### 关联类型定义

| 类型 | 文件路径 | 行号 |
|------|----------|------|
| `TurnStatus` | `v2.rs` | 3812-3820 |
| `TurnError` | `v2.rs` | 3632-3641 |

### 使用位置

| 文件路径 | 用途 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | `TurnStartResponse`、`ThreadResumeResponse` 等包含 `Turn` |
| `codex-rs/app-server-protocol/src/protocol/thread_history.rs` | 线程历史中的回合管理 |
| `codex-rs/tui_app_server/src/app/app_server_adapter.rs` | TUI 适配器处理回合事件 |
| `codex-rs/core/src/context_manager/history.rs` | 上下文管理器处理回合历史 |

### 响应类型中的使用

```rust
// TurnStartResponse
pub struct TurnStartResponse {
    pub thread_id: String,
    pub turn: Turn,
}

// ThreadResumeResponse
pub struct ThreadResumeResponse {
    pub thread: Thread,
    pub turns: Vec<Turn>, // 恢复时的历史回合
}
```

## 依赖与外部交互

### 内部依赖

```
Turn
  ├── ThreadItem
  │     ├── UserMessage
  │     ├── AgentMessage
  │     ├── CommandExecution
  │     └── ...
  ├── TurnStatus (enum)
  ├── TurnError
  ├── serde (Serialize, Deserialize)
  ├── schemars (JsonSchema)
  └── ts_rs (TS)
```

### 外部交互

| 交互方 | 交互方式 | 说明 |
|--------|----------|------|
| 用户 | 发起回合 | 通过 `turn/start` 请求 |
| AI 模型 | 处理回合 | 生成响应和工具调用 |
| 客户端 UI | 展示 | 渲染回合的项目和状态 |
| 通知系统 | 状态更新 | `turn/completed`、`turn/interrupted` 等通知 |

### 序列化示例

**进行中的回合：**
```json
{
  "id": "turn_abc123",
  "items": [],
  "status": "inProgress",
  "error": null
}
```

**已完成的回合（恢复时）：**
```json
{
  "id": "turn_def456",
  "items": [
    {
      "type": "userMessage",
      "id": "item_1",
      "content": "Hello!"
    },
    {
      "type": "agentMessage", 
      "id": "item_2",
      "content": "Hi there!"
    }
  ],
  "status": "completed",
  "error": null
}
```

**失败的回合：**
```json
{
  "id": "turn_ghi789",
  "items": [],
  "status": "failed",
  "error": {
    "message": "Model API error: rate limit exceeded",
    "codexErrorInfo": {
      "errorCode": "rate_limit_exceeded",
      "retryable": true
    },
    "additionalDetails": "Please try again in 60 seconds"
  }
}
```

## 风险、边界与改进建议

### 潜在风险

1. **items 大小**：恢复时 `items` 可能很大，影响性能和内存使用
2. **状态不一致**：`status` 为 `Failed` 但 `error` 为 `null`，或反之
3. **并发修改**：回合状态可能在多个地方被修改，导致竞态条件
4. **历史累积**：长期对话的回合历史可能无限增长

### 边界情况

| 场景 | 当前行为 | 潜在问题 |
|------|----------|----------|
| 空 items | 允许 | 正常，特别是非恢复场景 |
| Failed 但 error 为 null | 允许 | 语义不一致 |
| Completed 但有 error | 允许 | 语义不一致 |
| 超长回合 | 无限制 | 内存和性能问题 |

### 改进建议

1. **添加状态验证**：
   ```rust
   impl Turn {
       pub fn validate(&self) -> Result<(), ValidationError> {
           match self.status {
               TurnStatus::Failed if self.error.is_none() => {
                   return Err(ValidationError::MissingErrorForFailedTurn);
               }
               TurnStatus::Completed | TurnStatus::Interrupted 
                   if self.error.is_some() => {
                   return Err(ValidationError::UnexpectedErrorForNonFailedTurn);
               }
               _ => {}
           }
           Ok(())
       }
   }
   ```

2. **添加项目数量限制**：
   ```rust
   pub struct Turn {
       pub id: String,
       #[serde(deserialize_with = "limit_items")]
       pub items: Vec<ThreadItem>,
       pub status: TurnStatus,
       pub error: Option<TurnError>,
   }
   
   const MAX_ITEMS_PER_TURN: usize = 1000;
   ```

3. **添加元数据字段**：
   ```rust
   pub struct Turn {
       pub id: String,
       pub items: Vec<ThreadItem>,
       pub status: TurnStatus,
       pub error: Option<TurnError>,
       #[serde(skip_serializing_if = "Option::is_none")]
       pub metadata: Option<TurnMetadata>,
   }
   
   pub struct TurnMetadata {
       pub started_at: i64,
       pub completed_at: Option<i64>,
       pub model: String,
       pub token_usage: Option<TokenUsageBreakdown>,
   }
   ```

4. **支持回合分组**：
   ```rust
   pub struct Turn {
       pub id: String,
       pub items: Vec<ThreadItem>,
       pub status: TurnStatus,
       pub error: Option<TurnError>,
       #[serde(skip_serializing_if = "Option::is_none")]
       pub parent_turn_id: Option<String>, // 支持子回合/分支
   }
   ```

5. **添加回合摘要**：
   ```rust
   pub struct Turn {
       pub id: String,
       pub items: Vec<ThreadItem>,
       pub status: TurnStatus,
       pub error: Option<TurnError>,
       #[serde(skip_serializing_if = "Option::is_none")]
       pub summary: Option<String>, // AI 生成的回合摘要
   }
   ```

6. **支持部分加载**：
   ```rust
   pub struct Turn {
       pub id: String,
       pub items: Vec<ThreadItem>,
       pub status: TurnStatus,
       pub error: Option<TurnError>,
       #[serde(default)]
       pub items_truncated: bool, // 表示 items 是否被截断
       #[serde(skip_serializing_if = "Option::is_none")]
       pub total_item_count: Option<usize>,
   }
   ```

7. **添加版本控制**：
   ```rust
   pub struct Turn {
       pub id: String,
       pub items: Vec<ThreadItem>,
       pub status: TurnStatus,
       pub error: Option<TurnError>,
       #[serde(default = "default_turn_version")]
       pub version: u32,
   }
   ```

### 性能考虑

1. **懒加载**：当前设计在非恢复场景下 `items` 为空，这是良好的性能优化
2. **分页加载**：考虑支持回合历史的分页加载
3. **增量更新**：考虑支持回合项目的增量更新而非完整替换

### 与 Thread 的关系

```rust
pub struct Thread {
    pub id: String,
    pub name: String,
    pub status: ThreadStatus,
    // 注意：Thread 不直接包含 turns，而是通过 API 按需获取
}
```

回合属于线程，但采用分离存储模式，线程元数据与回合历史分开管理。
