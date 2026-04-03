# ThreadRealtimeAudioChunk 研究文档

## 场景与职责

`ThreadRealtimeAudioChunk` 是 App-Server Protocol v2 API 中用于实时语音对话（Realtime Conversation）的音频数据块类型。该类型封装了音频数据的元信息和实际的 PCM 音频数据（Base64 编码）。

在 Codex 实时语音对话架构中，该类型用于：
- 客户端向服务器发送音频输入（用户语音）
- 服务器向客户端发送音频输出（AI 语音回复）
- 支持双向实时音频流传输

**注意**：此类型标记为 **EXPERIMENTAL**，属于实验性功能，API 可能会在未来版本中变更。

## 功能点目的

### 核心功能
1. **音频数据传输**：承载 Base64 编码的 PCM 音频数据
2. **音频格式描述**：提供采样率、通道数等必要的音频参数
3. **流式处理支持**：支持分块传输，实现低延迟实时对话
4. **帧定位**：通过 `itemId` 关联到特定的对话项目

### 设计考量
- **实时性**：设计为流式分块传输，支持边录边传
- **兼容性**：支持可变采样率和通道配置
- **精确性**：`samplesPerChannel` 提供精确的样本计数，用于音频同步

## 具体技术实现

### Rust 结构定义

```rust
/// EXPERIMENTAL - thread realtime audio chunk.
#[derive(Serialize, Deserialize, Debug, Default, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadRealtimeAudioChunk {
    pub data: String,
    pub sample_rate: u32,
    pub num_channels: u16,
    pub samples_per_channel: Option<u32>,
    pub item_id: Option<String>,
}
```

### TypeScript 类型定义

```typescript
interface ThreadRealtimeAudioChunk {
  data: string;              // Base64 编码的 PCM 音频数据
  sampleRate: number;        // 采样率（如 24000 Hz）
  numChannels: number;       // 通道数（如 1 表示单声道）
  samplesPerChannel: number | null;  // 每通道样本数
  itemId: string | null;     // 关联的对话项目 ID
}
```

### 字段说明

| 字段名 | 类型 | 必填 | 说明 |
|--------|------|------|------|
| `data` | `string` | 是 | Base64 编码的 PCM 音频数据 |
| `sampleRate` | `number` | 是 | 音频采样率（Hz），常用值：24000 |
| `numChannels` | `number` | 是 | 音频通道数，常用值：1（单声道） |
| `samplesPerChannel` | `number \| null` | 否 | 每通道的样本数，用于精确计算时长 |
| `itemId` | `string \| null` | 否 | 关联的对话项目 ID，用于音频与文本同步 |

### 与 Core 类型的转换

该类型实现了与 `CoreRealtimeAudioFrame`（来自 `codex_protocol`）的双向转换：

```rust
// Core → v2 (3667-3683行)
impl From<CoreRealtimeAudioFrame> for ThreadRealtimeAudioChunk {
    fn from(value: CoreRealtimeAudioFrame) -> Self {
        let CoreRealtimeAudioFrame {
            data,
            sample_rate,
            num_channels,
            samples_per_channel,
            item_id,
        } = value;
        Self {
            data,
            sample_rate,
            num_channels,
            samples_per_channel,
            item_id,
        }
    }
}

// v2 → Core (3686-3702行)
impl From<ThreadRealtimeAudioChunk> for CoreRealtimeAudioFrame {
    fn from(value: ThreadRealtimeAudioChunk) -> Self {
        // ... 反向转换
    }
}
```

### 使用场景

#### 1. 输入音频（客户端 → 服务器）
```rust
ThreadRealtimeAppendAudioParams {
    thread_id: started.thread_id.clone(),
    audio: ThreadRealtimeAudioChunk {
        data: "BQYH".to_string(),  // Base64 编码的 PCM 数据
        sample_rate: 24_000,
        num_channels: 1,
        samples_per_channel: Some(480),
        item_id: None,
    },
}
```

#### 2. 输出音频（服务器 → 客户端）
通过 `ThreadRealtimeOutputAudioDeltaNotification` 推送：
```rust
ThreadRealtimeOutputAudioDeltaNotification {
    thread_id: String,
    audio: ThreadRealtimeAudioChunk,
}
```

## 关键代码路径与文件引用

### 定义位置
- **文件**：`codex-rs/app-server-protocol/src/protocol/v2.rs`
- **行号**：3655-3702

### 核心协议定义
- **文件**：`codex-rs/protocol/src/protocol.rs`
- **行号**：137-145
- **类型**：`RealtimeAudioFrame`（Core 类型）

```rust
pub struct RealtimeAudioFrame {
    pub data: String,
    pub sample_rate: u32,
    pub num_channels: u16,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub samples_per_channel: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub item_id: Option<String>,
}
```

### 相关类型
- `ThreadRealtimeAppendAudioParams`（3705-3714行）：发送音频输入的参数
- `ThreadRealtimeOutputAudioDeltaNotification`（3785-3792行）：接收音频输出的通知
- `ThreadRealtimeStartedNotification`（3766-3774行）：实时会话开始通知

### 使用场景
- **API 方法**：
  - `thread/realtime/appendAudio`：发送音频输入
  - `thread/realtime/outputAudio/delta` 通知：接收音频输出

### 测试文件
- **文件**：`codex-rs/app-server/tests/suite/v2/realtime_conversation.rs`
- **测试用例**：`realtime_conversation_streams_v2_notifications`
- **测试数据示例**：
  ```rust
  audio: ThreadRealtimeAudioChunk {
      data: "BQYH".to_string(),
      sample_rate: 24_000,
      num_channels: 1,
      samples_per_channel: Some(480),
      item_id: None,
  }
  ```

### WebSocket 协议映射
实时音频数据通过 WebSocket 传输，映射到以下事件类型：
- 输入：`input_audio_buffer.append` → `ThreadRealtimeAudioChunk`
- 输出：`response.output_audio.delta` → `ThreadRealtimeAudioChunk`

## 依赖与外部交互

### 依赖关系
- `serde`：序列化/反序列化
- `schemars`：JSON Schema 生成
- `ts-rs`：TypeScript 类型生成
- `codex_protocol::protocol::RealtimeAudioFrame`：核心协议类型

### 音频处理流程

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  麦克风输入  │ → │ PCM 编码    │ → │ Base64 编码 │
└─────────────┘     └─────────────┘     └──────┬──────┘
                                               │
                                               ↓
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  扬声器输出  │ ← │ PCM 解码    │ ← │ Base64 解码 │
└─────────────┘     └─────────────┘     └──────┬──────┘
                                               ↑
                                         ThreadRealtimeAudioChunk
```

### 外部系统交互
- **WebSocket 服务器**：通过 WebSocket 连接传输音频数据
- **OpenAI Realtime API**：后端可能转发到 OpenAI 的实时语音 API
- **音频设备**：客户端负责麦克风输入和扬声器输出

### 配置依赖
实时对话功能需要特定的配置：
```toml
[realtime]
version = "v2"
type = "conversational"

[features]
realtime_conversation = true
```

## 风险、边界与改进建议

### 实验性状态警告
⚠️ **此类型标记为 EXPERIMENTAL**：
- API 可能在未来的版本中发生破坏性变更
- 不建议在生产环境中依赖此功能
- 需要显式启用 feature flag 才能使用

### 已知限制
1. **Feature Flag 控制**：需要 `realtime_conversation` feature 启用，否则会报错：
   ```
   "thread {id} does not support realtime conversation"
   ```

2. **音频格式限制**：
   - 仅支持 PCM 格式
   - 推荐采样率：24000 Hz
   - 推荐通道数：1（单声道）

3. **网络依赖**：需要稳定的 WebSocket 连接，网络中断会导致实时会话终止

### 边界情况
- **空音频数据**：`data` 为空字符串时的行为未定义
- **不匹配的采样率**：客户端和服务器采样率不匹配可能导致音频失真
- **大音频块**：过大的 Base64 数据可能影响传输效率

### 安全风险
- **Base64 开销**：音频数据 Base64 编码后体积增加约 33%
- **数据隐私**：音频数据通过 WebSocket 传输，需要确保连接安全（WSS）

### 改进建议
1. **压缩支持**：考虑添加 Opus 等压缩格式支持，减少传输带宽
2. **流控机制**：添加背压机制，防止音频数据堆积
3. **格式协商**：支持客户端和服务器协商最佳音频格式
4. **错误恢复**：添加音频数据丢失时的恢复机制
5. **稳定化**：考虑将此类型从实验状态提升为稳定 API

### 调试建议
- 检查 `sampleRate` 和 `numChannels` 是否匹配预期值
- 验证 `data` 的 Base64 编码是否正确
- 使用 `samplesPerChannel` 计算音频时长：
  ```
  duration_ms = (samplesPerChannel / sampleRate) * 1000
  ```
