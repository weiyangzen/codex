# ThreadRealtimeOutputAudioDeltaNotification.json 研究文档

## 场景与职责

`ThreadRealtimeOutputAudioDeltaNotification` 是 Codex App-Server Protocol v2 中的实验性服务器推送通知，用于在实时对话（Realtime Conversation）中向客户端流式传输 AI 助手的语音输出音频数据。

**核心场景：**
1. **语音输出流式传输** - 实时接收 AI 助手的语音回复，实现低延迟播放
2. **增量音频处理** - 客户端可以边接收边解码播放，无需等待完整音频
3. **多轨道音频** - 支持多声道音频输出
4. **同步播放** - 与文本输出（ItemAddedNotification）同步，实现音画同步

**典型使用流程：**
```
Server (从后端实时服务接收音频增量)
  -> ThreadRealtimeOutputAudioDeltaNotification { 
       threadId, 
       audio: { data, sampleRate, numChannels, ... } 
     }
  -> Client
  -> 解码 Base64 数据
  -> 播放音频
```

**实验性状态：**
- 标记为 `EXPERIMENTAL`
- 需要启用 `realtime_conversation` 功能标志

## 功能点目的

### 1. 通知结构设计

```json
{
  "threadId": "thread-uuid-string",
  "audio": {
    "data": "AQIDBAUG...",          // Base64 编码的音频数据
    "sampleRate": 24000,            // 采样率（Hz）
    "numChannels": 1,               // 声道数
    "samplesPerChannel": 512,       // 每声道采样数（可选）
    "itemId": "item-uuid-or-null"   // 关联的 Item ID（可选）
  }
}
```

**设计意图：**
- **增量传输**：音频数据分块传输，降低延迟
- **自描述格式**：包含完整的音频格式信息，无需额外协商
- **关联追踪**：`itemId` 可关联到对应的文本 Item

### 2. ThreadRealtimeAudioChunk 结构

```rust
pub struct ThreadRealtimeAudioChunk {
    pub data: String,              // Base64 编码的 PCM 或压缩音频
    pub sample_rate: u32,          // 采样率（如 24000 Hz）
    pub num_channels: u16,         // 声道数（通常为 1）
    pub samples_per_channel: Option<u32>, // 每声道采样数
    pub item_id: Option<String>,   // 关联的 Item ID
}
```

**音频格式：**
- **编码**：通常为 PCM 16-bit 或 Opus
- **采样率**：常见 24000 Hz（OpenAI 默认）
- **声道**：通常为单声道（1）

### 3. 与 ThreadRealtimeItemAddedNotification 的关系

| 特性 | OutputAudioDeltaNotification | ItemAddedNotification |
|------|------------------------------|----------------------|
| 内容 | 音频数据（Base64） | 结构化数据（JSON） |
| 传输 | 增量流式 | 完整对象 |
| 用途 | 语音播放 | 文本显示、工具调用 |
| 关联 | 通过 `itemId` 关联 | 作为主体 |

**典型序列：**
```
ItemAddedNotification (message item with text)
    |
    v
OutputAudioDeltaNotification (audio for the message)
    |
    v
OutputAudioDeltaNotification (more audio...)
    |
    v
[Audio complete]
```

## 具体技术实现

### 1. Rust 源码定义

**文件路径：** `codex-rs/app-server-protocol/src/protocol/v2.rs:3785-3792`

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

**ThreadRealtimeAudioChunk 定义（v2.rs:3659-3684）：**

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadRealtimeAudioChunk {
    pub data: String,
    pub sample_rate: u32,
    pub num_channels: u16,
    pub samples_per_channel: Option<u32>,
    pub item_id: Option<String>,
}

// Core 类型的转换实现
impl From<CoreRealtimeAudioFrame> for ThreadRealtimeAudioChunk {
    fn from(value: CoreRealtimeAudioFrame) -> Self {
        Self {
            data: value.data,
            sample_rate: value.sample_rate,
            num_channels: value.num_channels,
            samples_per_channel: value.samples_per_channel,
            item_id: value.item_id,
        }
    }
}
```

### 2. 服务器通知注册

**文件路径：** `codex-rs/app-server-protocol/src/protocol/common.rs:925-926`

```rust
server_notification_definitions! {
    // ...
    #[experimental("thread/realtime/outputAudio/delta")]
    ThreadRealtimeOutputAudioDelta => "thread/realtime/outputAudio/delta" (v2::ThreadRealtimeOutputAudioDeltaNotification),
    // ...
}
```

**Wire 格式：**
```json
{
  "method": "thread/realtime/outputAudio/delta",
  "params": {
    "threadId": "thread-uuid",
    "audio": {
      "data": "AQID",
      "sampleRate": 24000,
      "numChannels": 1,
      "samplesPerChannel": 512,
      "itemId": null
    }
  }
}
```

### 3. 服务器端发送逻辑

**文件路径：** `codex-rs/app-server/src/bespoke_event_handling.rs`

服务器从 WebSocket 接收后端音频事件，转换后转发：

```rust
// 从测试用例中看到的典型场景
// realtime_conversation.rs:165-173
let output_audio = read_notification::<ThreadRealtimeOutputAudioDeltaNotification>(
    &mut mcp,
    "thread/realtime/outputAudio/delta",
).await?;
assert_eq!(output_audio.audio.data, "AQID");
assert_eq!(output_audio.audio.sample_rate, 24_000);
assert_eq!(output_audio.audio.num_channels, 1);
assert_eq!(output_audio.audio.samples_per_channel, Some(512));
```

**后端事件映射：**
```
Backend Event (Realtime API)
  "type": "response.output_audio.delta"
  "delta": "AQID..."
  "sample_rate": 24000
  "channels": 1
  "samples_per_channel": 512
         |
         v
ThreadRealtimeOutputAudioDeltaNotification
  "threadId": <thread-id>
  "audio": {
    "data": "AQID...",
    "sampleRate": 24000,
    "numChannels": 1,
    "samplesPerChannel": 512,
    "itemId": null
  }
```

### 4. TypeScript 类型定义

**文件路径：** `codex-rs/app-server-protocol/schema/typescript/v2/ThreadRealtimeOutputAudioDeltaNotification.ts`

```typescript
import type { ThreadRealtimeAudioChunk } from "./ThreadRealtimeAudioChunk";

/**
 * EXPERIMENTAL - streamed output audio emitted by thread realtime.
 */
export type ThreadRealtimeOutputAudioDeltaNotification = { 
  threadId: string, 
  audio: ThreadRealtimeAudioChunk, 
};
```

**ThreadRealtimeAudioChunk.ts：**
```typescript
export type ThreadRealtimeAudioChunk = {
  data: string,
  sampleRate: number,
  numChannels: number,
  samplesPerChannel: number | null,
  itemId: string | null,
};
```

## 关键代码路径与文件引用

### 协议定义
| 文件 | 位置 | 说明 |
|------|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 3785-3792 | Notification 结构体 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 3659-3703 | AudioChunk 结构体 + 转换 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 925-926 | 通知注册 |

### 服务器实现
| 文件 | 位置 | 说明 |
|------|------|------|
| `codex-rs/app-server/src/bespoke_event_handling.rs` | - | 实时事件处理 |

### Core 协议依赖
| 文件 | 说明 |
|------|------|
| `codex_protocol::protocol::RealtimeAudioFrame` | Core 音频帧类型 |

### 生成的 Schema/类型
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/schema/json/v2/ThreadRealtimeOutputAudioDeltaNotification.json` | JSON Schema（本文件） |
| `codex-rs/app-server-protocol/schema/typescript/v2/ThreadRealtimeOutputAudioDeltaNotification.ts` | TypeScript 类型 |
| `codex-rs/app-server-protocol/schema/typescript/v2/ThreadRealtimeAudioChunk.ts` | AudioChunk 类型 |

### 测试
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/realtime_conversation.rs` | 集成测试（165-173 行） |

## 依赖与外部交互

### 1. 上游依赖

```
ThreadRealtimeOutputAudioDeltaNotification
  └── OpenAI Realtime API
       ├── response.output_audio.delta 事件
       ├── PCM/Opus 音频数据
       └── 24kHz 采样率
```

### 2. 下游消费者

```
ThreadRealtimeOutputAudioDeltaNotification
  ├── VSCode Extension
  │    ├── Web Audio API 解码
  │    ├── 音频缓冲区管理
  │    └── 播放调度
  ├── TUI Client
  │    └── 外部播放器集成
  └── 其他客户端
       └── 自定义音频处理
```

### 3. 音频数据流

```
┌─────────────────────────────────────────────────────────────────┐
│                     OpenAI Realtime API                         │
│                     (WebSocket Backend)                         │
│                                                                 │
│  response.output_audio.delta                                    │
│  { delta: "AQID...", sample_rate: 24000, ... }                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        App Server                               │
│  ┌─────────────────┐    ┌──────────────────┐    ┌────────────┐ │
│  │ Receive delta   │───▶│ Convert to       │───▶│ Forward to │ │
│  │ from backend    │    │ AudioChunk       │    │ clients    │ │
│  └─────────────────┘    └──────────────────┘    └────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ ThreadRealtimeOutputAudioDeltaNotification
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Client                                  │
│  ┌─────────────────┐    ┌──────────────────┐    ┌────────────┐ │
│  │ Base64 decode   │───▶│ AudioContext     │───▶│ Play       │ │
│  │ to PCM/Opus     │    │ decode & buffer  │    │ audio      │ │
│  └─────────────────┘    └──────────────────┘    └────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### 4. 相关协议方法

| 方法/通知 | 方向 | 说明 |
|-----------|------|------|
| `thread/realtime/start` | Client → Server | 启动实时对话 |
| `thread/realtime/appendAudio` | Client → Server | 发送输入音频 |
| `thread/realtime/outputAudio/delta` | Server → Client | 接收输出音频（本通知） |
| `thread/realtime/itemAdded` | Server → Client | 接收文本/工具调用 |

## 风险、边界与改进建议

### 1. 已知风险

**风险 1：音频延迟和抖动**
- **描述**：网络波动可能导致音频包延迟或乱序
- **影响**：播放卡顿、音画不同步
- **缓解**：
  - 客户端实现抖动缓冲区（jitter buffer）
  - 自适应播放调度

**风险 2：Base64 编码开销**
- **描述**：音频数据通过 Base64 编码，增加 33% 大小
- **影响**：
  - 带宽浪费
  - 编解码 CPU 开销
- **缓解**：当前 WebSocket 文本帧限制，未来可考虑二进制帧

**风险 3：内存管理**
- **描述**：连续的音频增量可能累积大量内存
- **影响**：长时间对话的内存压力
- **缓解**：客户端应及时释放已播放的音频数据

### 2. 边界情况

| 场景 | 行为 |
|------|------|
| 音频数据损坏 | 客户端解码失败，应跳过或静音 |
| 采样率变化 | 理论上不应发生，客户端应重新初始化 |
| 空数据块 | 忽略或作为结束信号 |
| 高频增量 | 客户端应实现反压（backpressure）机制 |

### 3. 改进建议

**建议 1：支持二进制传输**
```rust
// 使用 WebSocket 二进制帧替代 Base64
pub struct ThreadRealtimeOutputAudioDeltaNotification {
    pub thread_id: String,
    pub audio: ThreadRealtimeAudioChunk,
}

// 音频数据作为二进制附件
pub struct ThreadRealtimeAudioChunk {
    // data 字段移除，改为二进制帧
    pub sample_rate: u32,
    pub num_channels: u16,
    pub samples_per_channel: u32,
    pub item_id: Option<String>,
}
```
- 减少 33% 带宽
- 降低 CPU 开销

**建议 2：添加序列号**
```rust
pub struct ThreadRealtimeOutputAudioDeltaNotification {
    pub thread_id: String,
    pub sequence: u64, // 新增：序列号用于检测丢包和乱序
    pub audio: ThreadRealtimeAudioChunk,
}
```

**建议 3：添加时间戳**
```rust
pub struct ThreadRealtimeOutputAudioDeltaNotification {
    pub thread_id: String,
    pub timestamp_ms: u64, // 新增：服务器生成时间
    pub audio: ThreadRealtimeAudioChunk,
}
```
- 帮助客户端测量延迟
- 支持音画同步

**建议 4：音频格式协商**
```rust
pub struct ThreadRealtimeAudioChunk {
    pub data: String,
    pub encoding: AudioEncoding, // 新增：明确编码格式
    pub sample_rate: u32,
    pub num_channels: u16,
    pub samples_per_channel: Option<u32>,
    pub item_id: Option<String>,
}

pub enum AudioEncoding {
    Pcm16,
    Opus,
    // ...
}
```

**建议 5：添加结束标记**
```rust
pub struct ThreadRealtimeOutputAudioDeltaNotification {
    pub thread_id: String,
    pub audio: ThreadRealtimeAudioChunk,
    pub is_final: bool, // 新增：是否为最后一块
}
```

### 4. 测试缺口

| 缺口 | 优先级 | 说明 |
|------|--------|------|
| 音频质量测试 | 高 | 验证解码后音频质量 |
| 延迟基准测试 | 高 | 测量端到端延迟 |
| 网络抖动模拟 | 中 | 验证抖动缓冲区效果 |
| 长时间播放 | 中 | 验证内存稳定性 |
| 多声道音频 | 低 | 验证立体声处理 |
