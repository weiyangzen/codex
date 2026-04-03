# ThreadRealtimeItemAddedNotification Research

## TypeScript Schema

```typescript
/**
 * EXPERIMENTAL - raw non-audio thread realtime item emitted by the backend.
 */
export type ThreadRealtimeItemAddedNotification = { 
    threadId: string, 
    item: JsonValue, 
};
```

## 场景与职责

`ThreadRealtimeItemAddedNotification` 是实时语音对话功能中的通知类型，用于从后端向客户端传递非音频的原始实时对话项。该类型是 **实验性功能（EXPERIMENTAL）** 的一部分。

### 使用场景

1. **实时对话项传递**: 后端将非音频的实时对话项（如文本消息、工具调用等）发送给客户端
2. **事件流处理**: 作为实时会话事件流的一部分，通知客户端有新的对话项可用
3. **调试与监控**: 提供原始 Responses API 项的访问，用于内部调试和监控

### 职责

- 封装实时对话中产生的非音频项数据
- 通过 `threadId` 关联到特定的线程
- 使用 `JsonValue` 提供灵活的数据结构，支持各种类型的实时对话项
- 作为服务器向客户端推送的通知类型

## 功能点目的

### 核心功能

1. **非音频项传输**: 在实时语音对话中传输文本、工具调用等非音频数据
2. **事件通知**: 作为服务器推送的通知，告知客户端有新的对话项
3. **原始数据暴露**: 提供对底层 Responses API 原始项的访问

### 设计考量

- `item` 使用 `JsonValue` 类型，支持任意 JSON 结构，灵活适应不同的实时对话项类型
- 与音频数据分离，通过专门的 `ThreadRealtimeOutputAudioDeltaNotification` 处理音频
- 通知类型命名遵循 `thread/realtime/*` 命名空间约定

## 具体技术实现

### 数据结构

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

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | `string` | 关联的线程唯一标识符 |
| `item` | `JsonValue` | 原始的非音频实时对话项，可以是任意 JSON 结构 |

### 协议使用

| 协议方法 | 方向 | 用途 |
|---------|------|------|
| `thread/realtime/start` 后续通知 | Server → Client | 实时会话启动后，流式传输非音频对话项 |

### 相关通知类型

实时对话相关的通知类型家族：

| 通知类型 | 说明 |
|---------|------|
| `ThreadRealtimeStartedNotification` | 实时会话启动成功通知 |
| `ThreadRealtimeItemAddedNotification` | 非音频对话项添加通知（本文档） |
| `ThreadRealtimeOutputAudioDeltaNotification` | 音频输出增量通知 |
| `ThreadRealtimeErrorNotification` | 实时会话错误通知 |
| `ThreadRealtimeClosedNotification` | 实时会话关闭通知 |

## 关键代码路径与文件引用

### 协议定义

- **Rust 定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 3776-3783)
- **TypeScript 生成**: `codex-rs/app-server-protocol/schema/typescript/v2/ThreadRealtimeItemAddedNotification.ts`
- **JSON Schema**: `codex-rs/app-server-protocol/schema/json/v2/ThreadRealtimeItemAddedNotification.json`

### 相关协议类型

- `ThreadRealtimeStartedNotification`: 实时会话启动通知
- `ThreadRealtimeOutputAudioDeltaNotification`: 音频输出通知
- `ThreadRealtimeErrorNotification`: 错误通知
- `ThreadRealtimeClosedNotification`: 关闭通知

### 使用场景

- **实时对话实现**: `codex-rs/app-server/src/bespoke_event_handling.rs`
  - 处理实时对话事件，将后端事件转换为通知发送给客户端

### 核心类型

- **JsonValue**: `serde_json::Value`，用于表示任意 JSON 数据
  - 在 TypeScript 中对应 `any` 或 `unknown` 类型

## 依赖与外部交互

### 内部依赖

| 依赖项 | 用途 |
|--------|------|
| `serde` | 序列化/反序列化 |
| `ts-rs` | TypeScript 类型生成 |
| `schemars` | JSON Schema 生成 |
| `serde_json::Value` | 灵活的 JSON 数据表示 |

### 外部交互

1. **服务器推送**: 后端在实时对话过程中检测到新的非音频项时，构造此通知并推送给客户端
2. **客户端处理**: 客户端接收此通知，解析 `item` 字段，根据项类型进行相应处理（如显示文本、处理工具调用等）
3. **事件流集成**: 作为实时会话事件流的一部分，与音频数据并行传输

### 数据流

```
Realtime API ──► Backend Processing ──► ThreadRealtimeItemAddedNotification
                                              │
    ┌─────────────────────────────────────────┘
    ▼
WebSocket/SSE ──► Client ──► UI Rendering
```

## 风险、边界与改进建议

### 潜在风险

1. **类型安全**: `JsonValue` 类型缺乏编译时类型检查，可能导致运行时错误
2. **数据一致性**: 需要确保 `item` 的内容与实时对话协议版本兼容
3. **性能开销**: 频繁的 JSON 序列化/反序列化可能带来性能开销
4. **数据大小**: 大型对话项可能导致消息过大，影响传输性能

### 边界情况

| 场景 | 处理 |
|------|------|
| `item` 为 `null` | 有效但可能表示空项或占位符 |
| `item` 为空对象 `{}` | 有效，客户端应忽略或显示占位符 |
| 不支持的项类型 | 客户端应优雅忽略不认识的项类型 |
| 线程不存在 | 服务器应验证 `threadId` 有效性 |

### 改进建议

1. **类型约束**: 考虑为 `item` 添加更具体的类型约束，使用联合类型代替 `JsonValue`
2. **版本控制**: 在通知中添加协议版本字段，便于未来扩展
3. **批量传输**: 支持多个项批量发送，减少网络往返
4. **压缩**: 对于大型项，考虑使用压缩减少传输大小
5. **类型提示**: 在 `item` 中添加 `type` 字段，便于客户端快速识别项类型

### 实验性状态

- 该类型标记为 **EXPERIMENTAL**，API 可能在将来版本中变更
- 需要启用相应的功能标志才能使用
- 生产环境使用前需要充分测试
- 客户端应做好向前兼容处理，忽略不认识的通知类型

### 相关类型

- `ThreadRealtimeStartedNotification`: 实时会话启动通知
- `ThreadRealtimeOutputAudioDeltaNotification`: 音频输出增量通知
- `ThreadRealtimeErrorNotification`: 错误通知
- `ThreadRealtimeClosedNotification`: 会话关闭通知
