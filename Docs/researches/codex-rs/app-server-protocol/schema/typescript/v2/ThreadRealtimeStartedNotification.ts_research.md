# ThreadRealtimeStartedNotification Research

## TypeScript Schema

```typescript
/**
 * EXPERIMENTAL - emitted when thread realtime startup is accepted.
 */
export type ThreadRealtimeStartedNotification = { 
    threadId: string, 
    sessionId: string | null, 
    version: RealtimeConversationVersion, 
};
```

## 场景与职责

`ThreadRealtimeStartedNotification` 是实时语音对话功能中的通知类型，用于通知客户端实时会话已成功启动。该类型是 **实验性功能（EXPERIMENTAL）** 的一部分。

### 使用场景

1. **会话启动确认**: 客户端调用 `thread/realtime/start` 后，服务器确认会话启动成功
2. **会话标识**: 提供 `sessionId` 用于跟踪和管理实时会话
3. **版本协商**: 告知客户端使用的实时对话协议版本

### 职责

- 确认实时会话已成功启动并准备好接收/发送数据
- 通过 `threadId` 关联到特定的线程
- 提供可选的 `sessionId` 用于会话跟踪
- 声明使用的实时对话协议版本，确保兼容性

## 功能点目的

### 核心功能

1. **启动确认**: 告知客户端实时会话已就绪，可以开始音频传输
2. **会话管理**: 提供会话标识符，支持多会话管理和跟踪
3. **版本控制**: 明确协议版本，便于客户端适配不同版本的行为

### 设计考量

- `sessionId` 为可选（`null`），支持无会话标识的简单场景
- `version` 使用枚举类型 `RealtimeConversationVersion`，当前支持 `"v1"` 和 `"v2"`
- 通知在服务器接受启动请求后立即发送，表示可以开始音频流传输

## 具体技术实现

### 数据结构

```rust
/// EXPERIMENTAL - emitted when thread realtime startup is accepted.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadRealtimeStartedNotification {
    pub thread_id: String,
    pub session_id: Option<String>,
    pub version: RealtimeConversationVersion,
}
```

### 嵌套类型

#### RealtimeConversationVersion

```typescript
export type RealtimeConversationVersion = "v1" | "v2";
```

- `"v1"`: 原始实时对话协议版本
- `"v2"`: 更新的实时对话协议版本，可能包含新功能或改进

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | `string` | 关联的线程唯一标识符 |
| `sessionId` | `string \| null` | 实时会话的唯一标识符，用于会话跟踪和管理 |
| `version` | `RealtimeConversationVersion` | 实时对话协议版本，值为 `"v1"` 或 `"v2"` |

### 协议使用

| 协议方法 | 方向 | 用途 |
|---------|------|------|
| `thread/realtime/start` 响应通知 | Server → Client | 确认实时会话启动成功 |

### 会话生命周期

```
Client                              Server
  │                                    │
  │──► thread/realtime/start ─────────►│
  │   {threadId, prompt, sessionId?}   │
  │                                    │
  │◄── ThreadRealtimeStartedNotification
  │    {threadId, sessionId, version}  │
  │                                    │
  │◄── ThreadRealtimeOutputAudioDeltaNotification (音频流)
  │◄── ThreadRealtimeItemAddedNotification (非音频项)
  │                                    │
  │──► thread/realtime/appendAudio ───►│
  │                                    │
  │──► thread/realtime/stop ──────────►│
  │                                    │
  │◄── ThreadRealtimeClosedNotification
```

## 关键代码路径与文件引用

### 协议定义

- **Rust 定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 3766-3774)
- **TypeScript 生成**: `codex-rs/app-server-protocol/schema/typescript/v2/ThreadRealtimeStartedNotification.ts`
- **JSON Schema**: `codex-rs/app-server-protocol/schema/json/v2/ThreadRealtimeStartedNotification.json`

### 相关协议类型

| 类型 | 说明 |
|------|------|
| `ThreadRealtimeStartParams` | 启动实时会话的请求参数 |
| `ThreadRealtimeStartResponse` | 启动请求的响应（空） |
| `ThreadRealtimeStartedNotification` | 会话启动成功通知（本文档） |
| `ThreadRealtimeOutputAudioDeltaNotification` | 音频输出通知 |
| `ThreadRealtimeItemAddedNotification` | 非音频项通知 |
| `ThreadRealtimeErrorNotification` | 错误通知 |
| `ThreadRealtimeClosedNotification` | 关闭通知 |

### 实现代码

- **会话管理**: `codex-rs/app-server/src/bespoke_event_handling.rs`
  - 处理 `thread/realtime/start` 请求
  - 建立与 Realtime API 的连接
  - 发送 `ThreadRealtimeStartedNotification` 通知

### 核心类型

- **RealtimeConversationVersion**: `codex_protocol::protocol::RealtimeConversationVersion`
  - 实时对话协议版本枚举
  - 定义在 `codex-rs/protocol/src/protocol/mod.rs`

## 依赖与外部交互

### 内部依赖

| 依赖项 | 用途 |
|--------|------|
| `serde` | 序列化/反序列化 |
| `ts-rs` | TypeScript 类型生成 |
| `schemars` | JSON Schema 生成 |
| `RealtimeConversationVersion` | 协议版本枚举 |

### 外部交互

1. **启动请求**: 客户端调用 `thread/realtime/start` 发起启动请求
2. **后端连接**: 服务器与 OpenAI Realtime API 建立 WebSocket 连接
3. **启动确认**: 连接成功后，服务器发送 `ThreadRealtimeStartedNotification`
4. **数据传输**: 客户端收到通知后开始音频数据的双向传输

### 数据流

```
Client Request
    │
    ▼
thread/realtime/start
    │
    ▼
Server ──► Validate Request
    │
    ▼
Connect to Realtime API
    │
    ▼
ThreadRealtimeStartedNotification
    │
    ▼
Client ──► Start Audio Streaming
```

## 风险、边界与改进建议

### 潜在风险

1. **连接失败**: Realtime API 连接可能失败，需要错误处理
2. **版本不兼容**: 客户端可能不支持服务器返回的协议版本
3. **会话冲突**: 同一线程可能不支持多个并发实时会话
4. **资源泄漏**: 会话未正确关闭可能导致资源泄漏

### 边界情况

| 场景 | 处理 |
|------|------|
| `sessionId` 为 `null` | 有效，表示无会话标识的简单模式 |
| 未知版本 | 客户端应报错或拒绝连接 |
| 重复启动 | 服务器应拒绝或关闭现有会话 |
| 线程不存在 | 服务器应返回错误 |

### 改进建议

1. **错误详情**: 在启动失败时提供更详细的错误信息
2. **能力协商**: 在启动阶段协商支持的音频格式和功能
3. **心跳机制**: 添加会话保活心跳，检测连接状态
4. **超时控制**: 添加启动超时，避免无限等待
5. **会话元数据**: 添加更多会话元数据（如支持的模型、最大时长等）

### 版本管理

| 版本 | 特性 |
|------|------|
| `v1` | 基础实时对话功能 |
| `v2` | 可能包含改进的音频格式、新功能等 |

- 客户端应根据 `version` 调整行为
- 未来版本应保持向后兼容或提供迁移路径

### 实验性状态

- 该类型标记为 **EXPERIMENTAL**，API 可能在将来版本中变更
- 需要启用 `realtime_conversation` 功能标志才能使用
- 生产环境使用前需要充分测试

### 相关类型

- `ThreadRealtimeStartParams`: 启动请求参数
- `ThreadRealtimeOutputAudioDeltaNotification`: 音频输出通知
- `ThreadRealtimeItemAddedNotification`: 非音频项通知
- `ThreadRealtimeErrorNotification`: 错误通知
- `ThreadRealtimeClosedNotification`: 关闭通知
