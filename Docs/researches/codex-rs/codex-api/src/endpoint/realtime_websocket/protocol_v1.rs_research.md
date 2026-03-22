# protocol_v1.rs 研究文档

## 场景与职责

`protocol_v1.rs` 实现了 OpenAI Realtime API V1 协议（内部代号 "Quicksilver"）的事件解析逻辑。它负责将服务器发送的 JSON 消息解析为 `RealtimeEvent` 枚举，供上层应用处理。

该模块是协议解析的分支之一，与 `protocol_v2.rs` 并列，由 `protocol.rs` 中的 `parse_realtime_event()` 函数根据 `RealtimeEventParser` 选择调用。

## 功能点目的

### 1. V1 协议事件解析
- **目的**：解析 Quicksilver 协议定义的所有服务器事件
- **覆盖事件类型**：
  - `session.updated` - 会话更新确认
  - `conversation.output_audio.delta` - 输出音频增量
  - `conversation.input_transcript.delta` - 输入转录增量
  - `conversation.output_transcript.delta` - 输出转录增量
  - `conversation.item.added` - 对话项添加
  - `conversation.item.done` - 对话项完成
  - `conversation.handoff.requested` - Handoff 请求
  - `error` - 错误事件

### 2. 音频数据解析
- **目的**：从音频增量事件提取 Base64 编码的 PCM 数据及元数据
- **包括**：采样率、通道数、每通道采样数

### 3. Handoff 事件解析
- **目的**：识别需要委托给 Codex 执行的任务请求
- **V1 特有**：使用专门的 `handoff.requested` 事件类型

## 具体技术实现

### 主解析函数

```rust
pub(super) fn parse_realtime_event_v1(payload: &str) -> Option<RealtimeEvent> {
    // 1. 通用解析，获取 JSON Value 和消息类型
    let (parsed, message_type) = parse_realtime_payload(payload, "realtime v1")?;
    
    // 2. 根据消息类型分发到具体解析逻辑
    match message_type.as_str() {
        "session.updated" => parse_session_updated_event(&parsed),
        "conversation.output_audio.delta" => parse_audio_delta(&parsed),
        "conversation.input_transcript.delta" => parse_input_transcript(&parsed),
        "conversation.output_transcript.delta" => parse_output_transcript(&parsed),
        "conversation.item.added" => parse_item_added(&parsed),
        "conversation.item.done" => parse_item_done(&parsed),
        "conversation.handoff.requested" => parse_handoff_requested(&parsed),
        "error" => parse_error_event(&parsed),
        _ => {
            debug!("unsupported realtime v1 event type: {message_type}");
            None
        }
    }
}
```

### 事件解析详解

#### 1. Session Updated

```rust
"session.updated" => parse_session_updated_event(&parsed)
```

使用 `protocol_common.rs` 中的共享函数，解析：
```json
{
  "type": "session.updated",
  "session": {
    "id": "sess_123",
    "instructions": "系统提示词"
  }
}
```

#### 2. 音频增量解析

```rust
"conversation.output_audio.delta" => {
    // 提取 Base64 音频数据
    let data = parsed
        .get("delta")
        .and_then(Value::as_str)
        .or_else(|| parsed.get("data").and_then(Value::as_str))  // 兼容 "data" 别名
        .map(str::to_string)?;
    
    // 提取采样率
    let sample_rate = parsed
        .get("sample_rate")
        .and_then(Value::as_u64)
        .and_then(|value| u32::try_from(value).ok())?;
    
    // 提取通道数（支持 "channels" 和 "num_channels" 两种字段名）
    let num_channels = parsed
        .get("channels")
        .or_else(|| parsed.get("num_channels"))
        .and_then(Value::as_u64)
        .and_then(|value| u16::try_from(value).ok())?;
    
    Some(RealtimeEvent::AudioOut(RealtimeAudioFrame {
        data,
        sample_rate,
        num_channels,
        samples_per_channel: parsed
            .get("samples_per_channel")
            .and_then(Value::as_u64)
            .and_then(|value| u32::try_from(value).ok()),
        item_id: None,  // V1 无 item_id
    }))
}
```

**字段兼容性处理**：
- `delta` / `data`：优先 `delta`，回退 `data`
- `channels` / `num_channels`：优先 `channels`，回退 `num_channels`

#### 3. 转录增量解析

```rust
"conversation.input_transcript.delta" => {
    parse_transcript_delta_event(&parsed, "delta").map(RealtimeEvent::InputTranscriptDelta)
}
"conversation.output_transcript.delta" => {
    parse_transcript_delta_event(&parsed, "delta").map(RealtimeEvent::OutputTranscriptDelta)
}
```

使用 `protocol_common.rs` 中的共享函数。

#### 4. 对话项添加

```rust
"conversation.item.added" => {
    parsed
        .get("item")
        .cloned()  // 克隆整个 item 对象
        .map(RealtimeEvent::ConversationItemAdded)
}
```

**特点**：保留原始 JSON `Value`，不做结构化解析。

#### 5. 对话项完成

```rust
"conversation.item.done" => {
    parsed
        .get("item")
        .and_then(Value::as_object)
        .and_then(|item| item.get("id"))
        .and_then(Value::as_str)
        .map(str::to_string)
        .map(|item_id| RealtimeEvent::ConversationItemDone { item_id })
}
```

#### 6. Handoff 请求（V1 特有）

```rust
"conversation.handoff.requested" => {
    let handoff_id = parsed
        .get("handoff_id")
        .and_then(Value::as_str)
        .map(str::to_string)?;
    let item_id = parsed
        .get("item_id")
        .and_then(Value::as_str)
        .map(str::to_string)?;
    let input_transcript = parsed
        .get("input_transcript")
        .and_then(Value::as_str)
        .map(str::to_string)?;
    
    Some(RealtimeEvent::HandoffRequested(RealtimeHandoffRequested {
        handoff_id,
        item_id,
        input_transcript,
        active_transcript: Vec::new(),  // V1 在 methods.rs 中填充
    }))
}
```

**与 V2 的区别**：
- V1：专门的 `handoff.requested` 事件
- V2：通过 `conversation.item.done` 中的 `function_call` 检测

#### 7. 错误事件

```rust
"error" => parse_error_event(&parsed)
```

使用 `protocol_common.rs` 中的共享函数。

## 关键代码路径与文件引用

### 模块依赖

```
protocol_v1.rs
├── protocol_common.rs    # parse_realtime_payload, parse_session_updated_event, 
│                         # parse_transcript_delta_event, parse_error_event
└── protocol.rs           # parse_realtime_event() 调用本模块
```

### 导入结构

```rust
use crate::endpoint::realtime_websocket::protocol_common::parse_error_event;
use crate::endpoint::realtime_websocket::protocol_common::parse_realtime_payload;
use crate::endpoint::realtime_websocket::protocol_common::parse_session_updated_event;
use crate::endpoint::realtime_websocket::protocol_common::parse_transcript_delta_event;
use codex_protocol::protocol::RealtimeAudioFrame;
use codex_protocol::protocol::RealtimeEvent;
use codex_protocol::protocol::RealtimeHandoffRequested;
use serde_json::Value;
use tracing::debug;
```

### 调用链

```
methods.rs:RealtimeWebsocketEvents::next_event()
├── protocol.rs:parse_realtime_event(parser = V1)
│   └── protocol_v1.rs:parse_realtime_event_v1()
│       ├── protocol_common.rs:parse_realtime_payload()
│       ├── protocol_common.rs:parse_session_updated_event()
│       ├── protocol_common.rs:parse_transcript_delta_event()
│       └── protocol_common.rs:parse_error_event()
└── methods.rs:update_active_transcript()
```

## 依赖与外部交互

### 与 protocol_v2.rs 的差异

| 特性 | V1 (protocol_v1.rs) | V2 (protocol_v2.rs) |
|------|---------------------|---------------------|
| Handoff 检测 | `handoff.requested` 事件 | `conversation.item.done` 中的 `function_call` |
| 音频事件 | `conversation.output_audio.delta` | `response.output_audio.delta` / `response.audio.delta` |
| 输入转录 | `conversation.input_transcript.delta` | `conversation.item.input_audio_transcription.delta` |
| 输出转录 | `conversation.output_transcript.delta` | `response.output_text.delta` / `response.output_audio_transcript.delta` |
| Speech Started | 无 | `input_audio_buffer.speech_started` |
| Response Cancelled | 无 | `response.cancelled` |
| Response Created | 无 | `response.created` |
| Response Done | 无 | `response.done` |

### 与 methods.rs 的协作

V1 的 `HandoffRequested` 事件需要特殊处理：

```rust
// methods.rs
async fn update_active_transcript(&self, event: &mut RealtimeEvent) {
    match event {
        RealtimeEvent::HandoffRequested(handoff) => {
            if self.event_parser == RealtimeEventParser::V1 {
                // V1：将积累的转录附加到 handoff 事件
                handoff.active_transcript = std::mem::take(&mut active_transcript.entries);
            }
        }
        // ...
    }
}
```

**原因**：V1 的 `handoff.requested` 事件不包含历史上下文，需要客户端附加。

## 风险、边界与改进建议

### 风险分析

1. **字段名兼容性**
   - 音频数据支持 `delta`/`data` 两种字段名
   - 通道数支持 `channels`/`num_channels` 两种字段名
   - 这种兼容性可能隐藏服务端的不一致

2. **数值溢出**
   - `u64` 转 `u32`/`u16` 使用 `try_from`，溢出时返回 `None`
   - 极端值可能导致事件被静默丢弃

3. **缺少的事件类型**
   - V1 不支持 `speech_started`、`response.cancelled` 等事件
   - 上层应用需要处理这种差异

### 边界情况

1. **音频数据缺失**
   ```json
   {"type": "conversation.output_audio.delta", "sample_rate": 24000, "channels": 1}
   ```
   - 缺少 `delta` 字段，返回 `None`

2. **采样率为 0**
   ```json
   {"type": "conversation.output_audio.delta", "delta": "AQID", "sample_rate": 0}
   ```
   - 解析成功，但可能导致后续音频处理错误

3. **Handoff 字段缺失**
   ```json
   {"type": "conversation.handoff.requested", "handoff_id": "123"}
   ```
   - 缺少 `item_id` 或 `input_transcript`，返回 `None`

4. **Item 完成无 ID**
   ```json
   {"type": "conversation.item.done", "item": {"type": "message"}}
   ```
   - 缺少 `item.id`，返回 `None`

### 改进建议

1. **更严格的验证**
   ```rust
   fn parse_audio_delta(parsed: &Value) -> Option<RealtimeEvent> {
       let data = /* ... */?;
       let sample_rate = /* ... */?;
       let num_channels = /* ... */?;
       
       // 验证采样率合理性
       if sample_rate == 0 || sample_rate > 192_000 {
           debug!("invalid sample_rate: {sample_rate}");
           return None;
       }
       
       // 验证通道数合理性
       if num_channels == 0 || num_channels > 16 {
           debug!("invalid num_channels: {num_channels}");
           return None;
       }
       
       Some(RealtimeEvent::AudioOut(/* ... */))
   }
   ```

2. **更详细的日志**
   ```rust
   _ => {
       debug!("unsupported realtime v1 event type: {message_type}, payload: {payload:.200}");
       None
   }
   ```

3. **字段存在性检查**
   ```rust
   "conversation.handoff.requested" => {
       let handoff_id = parsed.get("handoff_id").and_then(Value::as_str)?;
       let item_id = parsed.get("item_id").and_then(Value::as_str)?;
       let input_transcript = parsed.get("input_transcript").and_then(Value::as_str)?;
       
       // 检查空字符串
       if handoff_id.is_empty() || item_id.is_empty() {
           debug!("empty handoff_id or item_id");
           return None;
       }
       
       // ...
   }
   ```

4. **测试覆盖**
   ```rust
   #[cfg(test)]
   mod tests {
       use super::*;
       
       #[test]
       fn test_parse_audio_delta_with_data_alias() {
           let payload = r#"{"type": "conversation.output_audio.delta", "data": "AQID", "sample_rate": 24000, "channels": 1}"#;
           let event = parse_realtime_event_v1(payload).unwrap();
           match event {
               RealtimeEvent::AudioOut(frame) => {
                   assert_eq!(frame.data, "AQID");
               }
               _ => panic!("expected AudioOut"),
           }
       }
       
       #[test]
       fn test_parse_handoff_requested() {
           let payload = r#"{"type": "conversation.handoff.requested", "handoff_id": "h1", "item_id": "i1", "input_transcript": "test"}"#;
           let event = parse_realtime_event_v1(payload).unwrap();
           match event {
               RealtimeEvent::HandoffRequested(h) => {
                   assert_eq!(h.handoff_id, "h1");
                   assert_eq!(h.item_id, "i1");
                   assert_eq!(h.input_transcript, "test");
               }
               _ => panic!("expected HandoffRequested"),
           }
       }
   }
   ```

5. **废弃警告**
   ```rust
   //! V1 Protocol Parser (Quicksilver)
   //! 
   //! ⚠️ DEPRECATED: V1 protocol is deprecated. Please migrate to V2 (Realtime API).
   ```
