# ThreadRealtimeItemAddedNotification.json 研究文档

## 场景与职责

`ThreadRealtimeItemAddedNotification` 是 Codex App-Server Protocol v2 中的实验性服务器推送通知，用于在实时对话（Realtime Conversation）中向客户端推送后端生成的非音频项目（Item）。

**核心场景：**
1. **实时消息接收** - 接收 AI 助手在实时对话中生成的文本消息
2. **功能调用通知** - 通知客户端有新的工具调用（function call）需要处理
3. **对话状态更新** - 通知对话项目的创建（如用户消息确认、助手消息开始）
4. **多模态内容** - 接收文本、结构化数据等非音频内容

**典型使用流程：**
```
// 实时对话中
Server (从后端实时服务接收事件)
  -> 解析为 Item
  -> ThreadRealtimeItemAddedNotification { threadId, item }
  -> Client

// 客户端处理
Client -> 解析 item.type -> 渲染到 UI
```

**实验性状态：**
- 标记为 `EXPERIMENTAL`
- 需要启用 `realtime_conversation` 功能标志

## 功能点目的

### 1. 通知结构设计

```json
{
  "threadId": "thread-uuid-string",
  "item": {
    "type": "message",
    "role": "assistant",
    "content": [{ "type": "text", "text": "hi" }]
  }
}
```

**设计意图：**
- **通用容器**：`item` 使用 `JsonValue` 类型，可容纳任意后端事件
- **透传设计**：直接转发后端实时服务的 `conversation.item.added` 事件
- **非音频分离**：音频数据通过独立的 `outputAudio/delta` 通知传输

### 2. Item 内容类型

根据 OpenAI Realtime API，`item` 可能包含：

| Item 类型 | 说明 |
|-----------|------|
| `message` | 文本消息（用户或助手） |
| `function_call` | 工具调用请求 |
| `function_call_output` | 工具调用结果 |

**示例 Item 结构：**
```json
{
  "type": "message",
  "id": "msg_123",
  "role": "assistant",
  "content": [
    { "type": "text", "text": "Hello!" }
  ]
}
```

### 3. 与 ThreadRealtimeOutputAudioDeltaNotification 的关系

| 特性 | ItemAddedNotification | OutputAudioDeltaNotification |
|------|----------------------|------------------------------|
| 内容类型 | 结构化数据（JSON） | 音频数据（Base64） |
| 传输方式 | 完整对象 | 增量流式 |
| 用途 | 文本、工具调用 | 语音输出 |
| 处理 | 解析并渲染 | 解码并播放 |

## 具体技术实现

### 1. Rust 源码定义

**文件路径：** `codex-rs/app-server-protocol/src/protocol/v2.rs:3776-3783`

```rust
/// EXPERIMENTAL - raw non-audio thread realtime item emitted by the backend.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadRealtimeItemAddedNotification {
    pub thread_id: String,
    pub item: JsonValue,
}
```

**关键属性：**
- `pub item: JsonValue` - 使用 `serde_json::Value` 存储任意 JSON 数据
- 不限制 Item 的具体结构，保持与后端协议的灵活性

### 2. 服务器通知注册

**文件路径：** `codex-rs/app-server-protocol/src/protocol/common.rs:923-924`

```rust
server_notification_definitions! {
    // ...
    #[experimental("thread/realtime/itemAdded")]
    ThreadRealtimeItemAdded => "thread/realtime/itemAdded" (v2::ThreadRealtimeItemAddedNotification),
    // ...
}
```

**Wire 格式：**
```json
{
  "method": "thread/realtime/itemAdded",
  "params": {
    "threadId": "thread-uuid",
    "item": { /* 任意 Item 对象 */ }
  }
}
```

### 3. 服务器端发送逻辑

**文件路径：** `codex-rs/app-server/src/bespoke_event_handling.rs`

服务器从 WebSocket 接收后端事件，解析后转发：

```rust
// 从测试用例中看到的典型场景
// realtime_conversation.rs:175-181
let item_added = read_notification::<ThreadRealtimeItemAddedNotification>(
    &mut mcp,
    "thread/realtime/itemAdded",
).await?;
assert_eq!(item_added.thread_id, output_audio.thread_id);
assert_eq!(item_added.item["type"], json!("message"));
```

**后端事件映射：**
```
Backend Event (Realtime API)
  "type": "conversation.item.added"
  "item": { ... }
         |
         v
ThreadRealtimeItemAddedNotification
  "threadId": <thread-id>
  "item": <item-as-json>
```

### 4. TypeScript 类型定义

**文件路径：** `codex-rs/app-server-protocol/schema/typescript/v2/ThreadRealtimeItemAddedNotification.ts`

```typescript
import type { JsonValue } from "../serde_json/JsonValue";

/**
 * EXPERIMENTAL - raw non-audio thread realtime item emitted by the backend.
 */
export type ThreadRealtimeItemAddedNotification = { 
  threadId: string, 
  item: JsonValue, 
};
```

**客户端使用示例：**
```typescript
function handleItemAdded(notification: ThreadRealtimeItemAddedNotification) {
  const { item } = notification;
  
  switch (item.type) {
    case 'message':
      renderMessage(item);
      break;
    case 'function_call':
      handleFunctionCall(item);
      break;
    // ...
  }
}
```

## 关键代码路径与文件引用

### 协议定义
| 文件 | 位置 | 说明 |
|------|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 3776-3783 | Rust 结构体定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 923-924 | 通知注册 |

### 服务器实现
| 文件 | 位置 | 说明 |
|------|------|------|
| `codex-rs/app-server/src/bespoke_event_handling.rs` | - | 实时事件处理 |

### 生成的 Schema/类型
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/schema/json/v2/ThreadRealtimeItemAddedNotification.json` | JSON Schema（本文件） |
| `codex-rs/app-server-protocol/schema/typescript/v2/ThreadRealtimeItemAddedNotification.ts` | TypeScript 类型 |

### 测试
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/realtime_conversation.rs` | 集成测试（175-181 行） |

## 依赖与外部交互

### 1. 上游依赖

```
ThreadRealtimeItemAddedNotification
  └── OpenAI Realtime API
       ├── conversation.item.added 事件
       ├── message items
       ├── function_call items
       └── function_call_output items
```

### 2. 下游消费者

```
ThreadRealtimeItemAddedNotification
  ├── VSCode Extension
  │    ├── 渲染助手消息
  │    ├── 显示工具调用
  │    └── 更新对话历史
  ├── TUI Client
  │    └── 文本模式下的消息显示
  └── 其他客户端
       └── 自定义 Item 处理
```

### 3. 数据流

```
┌─────────────────────────────────────────────────────────────────┐
│                     OpenAI Realtime API                         │
│                     (WebSocket Backend)                         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ conversation.item.added
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        App Server                               │
│  ┌─────────────────┐    ┌──────────────────┐    ┌────────────┐ │
│  │ WebSocket       │───▶│ Parse item       │───▶│ Forward to │ │
│  │ Receiver        │    │ Extract type     │    │ clients    │ │
│  └─────────────────┘    └──────────────────┘    └────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ ThreadRealtimeItemAddedNotification
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Client                                  │
│  ┌─────────────────┐    ┌──────────────────┐    ┌────────────┐ │
│  │ Parse item.type │───▶│ Route to handler │───▶│ Update UI  │ │
│  │ (message/       │    │ (message/func)   │    │            │ │
│  │  function_call) │    │                  │    │            │ │
│  └─────────────────┘    └──────────────────┘    └────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### 4. 相关协议方法

| 方法/通知 | 方向 | 说明 |
|-----------|------|------|
| `thread/realtime/start` | Client → Server | 启动实时对话 |
| `thread/realtime/appendText` | Client → Server | 发送文本输入 |
| `thread/realtime/itemAdded` | Server → Client | 接收项目通知（本通知） |
| `thread/realtime/outputAudio/delta` | Server → Client | 接收音频流 |

## 风险、边界与改进建议

### 1. 已知风险

**风险 1：Item 结构的不确定性**
- **描述**：`item` 是 `JsonValue`，结构由后端协议决定
- **影响**：
  - 客户端需要处理未知的 Item 类型
  - 类型安全依赖运行时检查
  - 后端协议变更可能破坏客户端
- **缓解**：客户端应实现健壮的错误处理和未知类型回退

**风险 2：大 Item 的传输**
- **描述**：某些 Item（如长文本、大量工具调用参数）可能很大
- **影响**：
  - WebSocket 消息大小限制
  - JSON 解析性能
- **缓解**：当前设计假设 Item 大小可控

**风险 3：顺序保证**
- **描述**：Item 和音频增量可能交错到达
- **影响**：客户端需要正确排序以保持一致性
- **缓解**：依赖 WebSocket 的 FIFO 保证

### 2. 边界情况

| 场景 | 行为 |
|------|------|
| 未知 Item 类型 | 客户端应忽略或显示警告 |
| 无效 JSON | 服务器解析错误，发送 ErrorNotification |
| 空 Item | 技术上可能，但后端不应发送 |
| 重复 Item ID | 客户端应去重或幂等处理 |

### 3. 改进建议

**建议 1：添加 Item 类型枚举**
```rust
pub struct ThreadRealtimeItemAddedNotification {
    pub thread_id: String,
    pub item_type: RealtimeItemType, // 新增：类型提示
    pub item: JsonValue,
}

pub enum RealtimeItemType {
    Message,
    FunctionCall,
    FunctionCallOutput,
    Unknown,
}
```

**建议 2：添加 Item ID**
```rust
pub struct ThreadRealtimeItemAddedNotification {
    pub thread_id: String,
    pub item_id: String, // 新增：用于去重和追踪
    pub item: JsonValue,
}
```

**建议 3：添加时间戳**
```rust
pub struct ThreadRealtimeItemAddedNotification {
    pub thread_id: String,
    pub created_at: i64, // 新增：服务器时间戳
    pub item: JsonValue,
}
```

**建议 4：结构化 Item 类型（替代 JsonValue）**
```rust
pub struct ThreadRealtimeItemAddedNotification {
    pub thread_id: String,
    pub item: RealtimeItem, // 使用枚举替代 JsonValue
}

pub enum RealtimeItem {
    Message(RealtimeMessage),
    FunctionCall(RealtimeFunctionCall),
    // ...
}
```
- 提供类型安全
- 更好的 IDE 支持
- 明确的协议契约

### 4. 测试缺口

| 缺口 | 优先级 | 说明 |
|------|--------|------|
| 各种 Item 类型覆盖 | 高 | 验证所有后端 Item 类型的处理 |
| 大 Item 性能 | 中 | 验证大 JSON 的解析性能 |
| 乱序到达 | 中 | 验证 Item 和音频的交错处理 |
| 未知类型容错 | 中 | 验证客户端对未知 Item 的健壮性 |
