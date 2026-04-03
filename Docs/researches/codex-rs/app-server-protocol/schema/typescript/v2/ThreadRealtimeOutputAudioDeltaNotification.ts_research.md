# ThreadRealtimeOutputAudioDeltaNotification Research

## TypeScript Schema

```typescript
/**
 * EXPERIMENTAL - streamed output audio emitted by thread realtime.
 */
export type ThreadRealtimeOutputAudioDeltaNotification = { 
    threadId: string, 
    audio: ThreadRealtimeAudioChunk, 
};
```

## 场景与职责

`ThreadRealtimeOutputAudioDeltaNotification` 是实时语音对话功能中的通知类型，用于从后端向客户端流式传输 AI 生成的音频输出。该类型是 **实验性功能（EXPERIMENTAL）** 的一部分。

### 使用场景

1. **AI 语音输出**: 后端将 AI 生成的语音数据流式传输给客户端
2. **实时播放**: 客户端接收音频块并实时播放，实现低延迟语音交互
3. **增量传输**: 支持小块音频的增量传输，减少等待时间

### 职责

- 封装 AI 生成的音频输出数据块
- 通过 `threadId` 关联到特定的线程
- 使用 `ThreadRealtimeAudioChunk` 提供标准化的音频数据格式
- 作为服务器向客户端推送的音频流通知

## 功能点目的

### 核心功能

1. **音频流式传输**: 将 AI 生成的音频分块传输给客户端
2. **低延迟播放**: 支持客户端边接收边播放，减少整体延迟
3. **增量更新**: 音频数据以增量方式发送，无需等待完整音频生成

### 设计考量

- 音频数据使用 `ThreadRealtimeAudioChunk` 封装，包含 Base64 编码的 PCM 数据和格式元数据
- 增量传输模式允许客户端在音频生成过程中就开始播放
- 与 `ThreadRealtimeItemAddedNotification` 分离，专门处理音频数据流

## 具体技术实现

### 数据结构

```rust
/// EXPERIMENTAL - streamed output audio emitted by thread realtime.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadRealtimeOutputAudioDeltaNotification {
    pub thread_id: String,
    pub audio: ThreadRealtimeAudioChunk,
}
```

### 嵌套类型

#### ThreadRealtimeAudioChunk

```typescript
export type ThreadRealtimeAudioChunk = { 
    data: string,           // Base64 编码的 PCM 音频数据
    sampleRate: number,     // 采样率（Hz），通常为 24000
    numChannels: number,    // 声道数，通常为 1（单声道）
    samplesPerChannel: number | null,  // 每声道采样数
    itemId: string | null,  // 关联的对话项 ID
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | `string` | 关联的线程唯一标识符 |
| `audio` | `ThreadRealtimeAudioChunk` | 音频数据块，包含编码数据和格式信息 |

### 协议使用

| 协议方法 | 方向 | 用途 |
|---------|------|------|
| `thread/realtime/start` 后续通知 | Server → Client | 实时会话中 AI 语音输出的流式传输 |

### 音频数据流

```
AI 语音生成 ──► PCM 编码 ──► Base64 ──► ThreadRealtimeAudioChunk
                                            │
    ┌───────────────────────────────────────┘
    ▼
ThreadRealtimeOutputAudioDeltaNotification
    │
    ▼
WebSocket ──► Client ──► Base64 解码 ──► PCM 解码 ──► 音频播放
```

## 关键代码路径与文件引用

### 协议定义

- **Rust 定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 3785-3792)
- **TypeScript 生成**: `codex-rs/app-server-protocol/schema/typescript/v2/ThreadRealtimeOutputAudioDeltaNotification.ts`
- **JSON Schema**: `codex-rs/app-server-protocol/schema/json/v2/ThreadRealtimeOutputAudioDeltaNotification.json`

### 相关协议类型

- `ThreadRealtimeAudioChunk`: 音频数据块类型
- `ThreadRealtimeStartedNotification`: 实时会话启动通知
- `ThreadRealtimeItemAddedNotification`: 非音频项通知
- `ThreadRealtimeAppendAudioParams`: 客户端音频输入参数

### 实现代码

- **事件处理**: `codex-rs/app-server/src/bespoke_event_handling.rs`
  - 处理音频输出事件，将 `CoreRealtimeAudioFrame` 转换为 `ThreadRealtimeAudioChunk`
  - 构造 `ThreadRealtimeOutputAudioDeltaNotification` 并发送给客户端

### 测试代码

- **集成测试**: `codex-rs/app-server/tests/suite/v2/realtime_conversation.rs`
  - 测试音频数据的发送和接收
  - 验证音频块字段值

### 核心类型

- **CoreRealtimeAudioFrame**: `codex_protocol::protocol::RealtimeAudioFrame`
  - 内部核心库使用的音频帧类型
  - 与 `ThreadRealtimeAudioChunk` 双向转换

## 依赖与外部交互

### 内部依赖

| 依赖项 | 用途 |
|--------|------|
| `serde` | 序列化/反序列化 |
| `ts-rs` | TypeScript 类型生成 |
| `schemars` | JSON Schema 生成 |
| `ThreadRealtimeAudioChunk` | 音频数据封装 |

### 外部交互

1. **音频生成**: 后端从 Realtime API 接收音频数据
2. **格式转换**: 将 `CoreRealtimeAudioFrame` 转换为 `ThreadRealtimeAudioChunk`
3. **通知构造**: 创建 `ThreadRealtimeOutputAudioDeltaNotification` 并发送
4. **客户端接收**: 客户端解码音频数据并播放

### 数据流

```
Realtime API (AI 语音)
    │
    ▼
Backend ──► CoreRealtimeAudioFrame
    │
    ▼
Convert ──► ThreadRealtimeAudioChunk
    │
    ▼
ThreadRealtimeOutputAudioDeltaNotification
    │
    ▼
WebSocket/SSE
    │
    ▼
Client ──► 解码 ──► 音频缓冲区 ──► 扬声器
```

## 风险、边界与改进建议

### 潜在风险

1. **延迟敏感**: 音频传输对延迟要求极高，网络抖动会导致播放卡顿
2. **带宽消耗**: 24kHz 单声道 16-bit PCM 约 48KB/s，Base64 编码后约 64KB/s
3. **同步问题**: 音频块需要按顺序播放，丢包或乱序会影响体验
4. **缓冲区管理**: 客户端需要合理管理音频缓冲区，平衡延迟和流畅度

### 边界情况

| 场景 | 处理 |
|------|------|
| `audio.data` 为空 | 可能表示静音帧或心跳包 |
| `audio.itemId` 为 `null` | 音频未关联到特定对话项 |
| 采样率不匹配 | 客户端应进行重采样或报错 |
| 音频块乱序到达 | 需要序列号或时间戳进行排序 |
| 网络中断 | 需要重连机制和缓冲区恢复 |

### 改进建议

1. **序列号**: 添加序列号字段，便于检测丢包和乱序
2. **时间戳**: 添加时间戳信息，支持更精确的同步
3. **压缩**: 考虑使用 Opus 等压缩格式减少带宽
4. **自适应缓冲**: 根据网络状况动态调整缓冲区大小
5. **错误恢复**: 实现丢包隐藏（PLC）算法，提升弱网体验
6. **二进制传输**: 考虑使用二进制 WebSocket 帧直接传输 PCM 数据

### 性能考量

- **编码开销**: Base64 编解码增加 CPU 负担
- **内存使用**: 音频缓冲区需要合理大小，避免内存溢出
- **播放延迟**: 建议音频块大小控制在 20-100ms 之间
- **累积延迟**: 需要监控和补偿累积的播放延迟

### 实验性状态

- 该类型标记为 **EXPERIMENTAL**，API 可能在将来版本中变更
- 需要启用 `realtime_conversation` 功能标志才能使用
- 生产环境使用前需要充分测试

### 相关类型

- `ThreadRealtimeAudioChunk`: 音频数据块定义
- `ThreadRealtimeStartedNotification`: 会话启动通知
- `ThreadRealtimeErrorNotification`: 错误通知
- `ThreadRealtimeClosedNotification`: 会话关闭通知
