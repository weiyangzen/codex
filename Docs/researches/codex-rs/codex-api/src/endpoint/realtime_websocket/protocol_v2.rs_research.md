# protocol_v2.rs 研究文档

## 场景与职责

`protocol_v2.rs` 实现了 OpenAI Realtime API V2 标准协议的事件解析逻辑。它是 Codex 当前推荐使用的协议版本，支持更完整的事件类型和更灵活的 Handoff 机制（通过 function call 而非专用事件）。

该模块与 `protocol_v1.rs` 并列，由 `protocol.rs` 中的 `parse_realtime_event()` 函数根据 `RealtimeEventParser::RealtimeV2` 选择调用。

## 功能点目的

### 1. V2 协议事件解析
- **目的**：解析标准 Realtime API 的所有服务器事件
- **覆盖事件类型**：
  - `session.updated` - 会话更新确认
  - `response.output_audio.delta` / `response.audio.delta` - 输出音频增量
  - `conversation.item.input_audio_transcription.delta` / `.completed` - 输入转录
  - `response.output_text.delta` / `response.output_audio_transcript.delta` - 输出转录
  - `input_audio_buffer.speech_started` - 检测到语音开始
  - `conversation.item.added` / `conversation.item.done` - 对话项生命周期
  - `response.created` / `response.done` / `response.cancelled` - 响应生命周期
  - `error` - 错误事件

### 2. Handoff 检测（Function Call 机制）
- **目的**：识别模型调用 `codex` tool 的请求
- **机制**：
  - 从 `conversation.item.done` 中检测 `type: "function_call"` 且 `name: "codex"`
  - 从 `response.done` 的 `output` 数组中检测 function call

### 3. 音频数据解析
- **目的**：提取音频增量及元数据
- **特点**：支持默认采样率（24kHz）和通道数（1）

### 4. 参数提取
- **目的**：从 function call arguments 中提取用户输入
- **支持字段**：`input_transcript`, `input`, `text`, `prompt`, `query`

## 具体技术实现

### 主解析函数

```rust
pub(super) fn parse_realtime_event_v2(payload: &str) -> Option<RealtimeEvent> {
    let (parsed, message_type) = parse_realtime_payload(payload, "realtime v2")?;

    match message_type.as_str() {
        "session.updated" => parse_session_updated_event(&parsed),
        "response.output_audio.delta" | "response.audio.delta" => {
            parse_output_audio_delta_event(&parsed)
        }
        "conversation.item.input_audio_transcription.delta" => {
            parse_transcript_delta_event(&parsed, "delta").map(RealtimeEvent::InputTranscriptDelta)
        }
        "conversation.item.input_audio_transcription.completed" => {
            parse_transcript_delta_event(&parsed, "transcript")
                .map(RealtimeEvent::InputTranscriptDelta)
        }
        "response.output_text.delta" | "response.output_audio_transcript.delta" => {
            parse_transcript_delta_event(&parsed, "delta").map(RealtimeEvent::OutputTranscriptDelta)
        }
        "input_audio_buffer.speech_started" => parse_speech_started(&parsed),
        "conversation.item.added" => parse_item_added(&parsed),
        "conversation.item.done" => parse_conversation_item_done_event(&parsed),
        "response.created" => Some(RealtimeEvent::ConversationItemAdded(parsed)),
        "response.done" => parse_response_done_event(parsed),
        "response.cancelled" => parse_response_cancelled(&parsed),
        "error" => parse_error_event(&parsed),
        _ => {
            debug!("unsupported realtime v2 event type: {message_type}");
            None
        }
    }
}
```

### 核心解析函数详解

#### 1. 音频增量解析

```rust
fn parse_output_audio_delta_event(parsed: &Value) -> Option<RealtimeEvent> {
    let data = parsed.get("delta").and_then(Value::as_str).map(str::to_string)?;
    
    // 使用默认值：24kHz 采样率，1 通道
    let sample_rate = parsed
        .get("sample_rate")
        .and_then(Value::as_u64)
        .and_then(|value| u32::try_from(value).ok())
        .unwrap_or(DEFAULT_AUDIO_SAMPLE_RATE);  // 24_000
    
    let num_channels = parsed
        .get("channels")
        .or_else(|| parsed.get("num_channels"))
        .and_then(Value::as_u64)
        .and_then(|value| u16::try_from(value).ok())
        .unwrap_or(DEFAULT_AUDIO_CHANNELS);  // 1
    
    Some(RealtimeEvent::AudioOut(RealtimeAudioFrame {
        data,
        sample_rate,
        num_channels,
        samples_per_channel: parsed
            .get("samples_per_channel")
            .and_then(Value::as_u64)
            .and_then(|value| u32::try_from(value).ok()),
        item_id: parsed  // V2 支持 item_id
            .get("item_id")
            .and_then(Value::as_str)
            .map(str::to_string),
    }))
}
```

**与 V1 的区别**：
- 支持默认值（V1 要求显式指定）
- 支持 `item_id` 字段（V1 无此字段）

#### 2. 语音开始检测

```rust
"input_audio_buffer.speech_started" => Some(RealtimeEvent::InputAudioSpeechStarted(
    RealtimeInputAudioSpeechStarted {
        item_id: parsed
            .get("item_id")
            .and_then(Value::as_str)
            .map(str::to_string),
    }
))
```

**用途**：UI 可以显示"正在听取..."状态。

#### 3. Conversation Item Done 解析（含 Handoff 检测）

```rust
fn parse_conversation_item_done_event(parsed: &Value) -> Option<RealtimeEvent> {
    let item = parsed.get("item")?.as_object()?;
    
    // 首先检查是否是 Handoff function call
    if let Some(handoff) = parse_handoff_requested_event(item) {
        return Some(handoff);
    }

    // 否则返回普通的 item done 事件
    item.get("id")
        .and_then(Value::as_str)
        .map(str::to_string)
        .map(|item_id| RealtimeEvent::ConversationItemDone { item_id })
}
```

#### 4. Handoff 检测核心逻辑

```rust
fn parse_handoff_requested_event(item: &JsonMap<String, Value>) -> Option<RealtimeEvent> {
    // 验证是 codex function call
    let item_type = item.get("type").and_then(Value::as_str);
    let item_name = item.get("name").and_then(Value::as_str);
    if item_type != Some("function_call") || item_name != Some(CODEX_TOOL_NAME) {
        return None;
    }

    // 提取 call_id（支持 call_id 和 id 两种字段）
    let call_id = item
        .get("call_id")
        .and_then(Value::as_str)
        .or_else(|| item.get("id").and_then(Value::as_str))?;
    
    // 提取 item_id（默认使用 call_id）
    let item_id = item
        .get("id")
        .and_then(Value::as_str)
        .unwrap_or(call_id)
        .to_string();
    
    // 提取 arguments
    let arguments = item.get("arguments").and_then(Value::as_str).unwrap_or("");

    Some(RealtimeEvent::HandoffRequested(RealtimeHandoffRequested {
        handoff_id: call_id.to_string(),
        item_id,
        input_transcript: extract_input_transcript(arguments),
        active_transcript: Vec::new(),  // V2 由服务端提供上下文
    }))
}
```

#### 5. Response Done 解析（含 Handoff 检测）

```rust
fn parse_response_done_event(parsed: Value) -> Option<RealtimeEvent> {
    // 首先检查是否是 Handoff
    if let Some(handoff) = parse_response_done_handoff_requested_event(&parsed) {
        return Some(handoff);
    }

    // 否则返回 ConversationItemAdded
    Some(RealtimeEvent::ConversationItemAdded(parsed))
}

fn parse_response_done_handoff_requested_event(parsed: &Value) -> Option<RealtimeEvent> {
    // 在 response.output 数组中查找 codex function call
    let item = parsed
        .get("response")
        .and_then(Value::as_object)
        .and_then(|response| response.get("output"))
        .and_then(Value::as_array)?
        .iter()
        .find(|item| {
            item.get("type").and_then(Value::as_str) == Some("function_call")
                && item.get("name").and_then(Value::as_str) == Some(CODEX_TOOL_NAME)
        })?
        .as_object()?;

    parse_handoff_requested_event(item)
}
```

**设计意图**：
- Handoff 可能出现在 `conversation.item.done` 或 `response.done` 中
- 两者都需要检测，确保不遗漏

#### 6. 输入转录提取

```rust
fn extract_input_transcript(arguments: &str) -> String {
    if arguments.is_empty() {
        return String::new();
    }

    // 尝试解析为 JSON
    if let Ok(arguments_json) = serde_json::from_str::<Value>(arguments)
        && let Some(arguments_object) = arguments_json.as_object()
    {
        // 按优先级尝试多个字段名
        for key in TOOL_ARGUMENT_KEYS {
            if let Some(value) = arguments_object.get(key).and_then(Value::as_str) {
                let trimmed = value.trim();
                if !trimmed.is_empty() {
                    return trimmed.to_string();
                }
            }
        }
    }

    // 回退：返回原始 arguments
    arguments.to_string()
}

const TOOL_ARGUMENT_KEYS: [&str; 5] = ["input_transcript", "input", "text", "prompt", "query"];
```

**字段优先级**：
1. `input_transcript` - 最具体的字段名
2. `input` - 通用输入
3. `text` - 文本内容
4. `prompt` - 提示词
5. `query` - 查询

**设计意图**：兼容不同版本的 tool schema 或不同的使用方式。

#### 7. Response Cancelled 解析

```rust
"response.cancelled" => Some(RealtimeEvent::ResponseCancelled(
    RealtimeResponseCancelled {
        response_id: parsed
            .get("response")
            .and_then(Value::as_object)
            .and_then(|response| response.get("id"))
            .and_then(Value::as_str)
            .map(str::to_string)
            .or_else(|| {
                // 回退到 response_id 字段
                parsed
                    .get("response_id")
                    .and_then(Value::as_str)
                    .map(str::to_string)
            }),
    }
))
```

## 关键代码路径与文件引用

### 模块依赖

```
protocol_v2.rs
├── protocol_common.rs    # 共享解析函数
└── protocol.rs           # 入口分发
```

### 常量定义

```rust
const CODEX_TOOL_NAME: &str = "codex";
const DEFAULT_AUDIO_SAMPLE_RATE: u32 = 24_000;
const DEFAULT_AUDIO_CHANNELS: u16 = 1;
const TOOL_ARGUMENT_KEYS: [&str; 5] = ["input_transcript", "input", "text", "prompt", "query"];
```

### 调用链

```
methods.rs:next_event()
├── protocol.rs:parse_realtime_event(parser = RealtimeV2)
│   └── protocol_v2.rs:parse_realtime_event_v2()
│       ├── parse_output_audio_delta_event()
│       ├── parse_conversation_item_done_event()
│       │   └── parse_handoff_requested_event()
│       ├── parse_response_done_event()
│       │   └── parse_response_done_handoff_requested_event()
│       │       └── parse_handoff_requested_event()
│       └── extract_input_transcript()
└── update_active_transcript()
```

## 依赖与外部交互

### 与 V1 的详细对比

| 事件类型 | V1 | V2 |
|----------|-----|-----|
| 音频增量 | `conversation.output_audio.delta` | `response.output_audio.delta` / `response.audio.delta` |
| 输入转录 | `conversation.input_transcript.delta` | `conversation.item.input_audio_transcription.delta` / `.completed` |
| 输出转录 | `conversation.output_transcript.delta` | `response.output_text.delta` / `response.output_audio_transcript.delta` |
| 语音开始 | ❌ | `input_audio_buffer.speech_started` |
| 响应取消 | ❌ | `response.cancelled` |
| 响应完成 | ❌ | `response.done` |
| Handoff | `conversation.handoff.requested` | `conversation.item.done` / `response.done` 中的 function call |

### Handoff 机制差异

**V1**：
```json
{
  "type": "conversation.handoff.requested",
  "handoff_id": "...",
  "item_id": "...",
  "input_transcript": "..."
}
```

**V2**：
```json
{
  "type": "conversation.item.done",
  "item": {
    "type": "function_call",
    "name": "codex",
    "call_id": "...",
    "arguments": "{\"prompt\": \"...\"}"
  }
}
```

**V2 的优势**：
- 符合 OpenAI 标准 function calling 流程
- 支持更复杂的参数传递
- 模型可以主动决定是否调用

## 风险、边界与改进建议

### 风险分析

1. **Function Call 检测依赖字段名**
   - 硬编码 `name == "codex"`
   - 如果服务端修改 tool 名称，检测会失效

2. **Arguments 解析容错过宽**
   - `extract_input_transcript` 尝试 5 个不同字段名
   - 可能导致意外的字段被提取

3. **Response Done Handoff 检测顺序**
   - 优先检查 Handoff，然后返回 `ConversationItemAdded`
   - 如果 response 同时包含 function call 和其他输出，其他输出被忽略

### 边界情况

1. **Arguments 非 JSON**
   ```json
   {"type": "function_call", "name": "codex", "arguments": "plain text"}
   ```
   - JSON 解析失败，返回 `"plain text"` 作为 transcript

2. **Arguments 空对象**
   ```json
   {"arguments": "{}"}
   ```
   - 所有字段查找失败，返回 `"{}"`

3. **Item ID 缺失**
   ```json
   {"type": "function_call", "name": "codex", "call_id": "c1"}
   ```
   - 使用 `call_id` 作为 `item_id`

4. **Call ID 缺失**
   ```json
   {"type": "function_call", "name": "codex", "id": "i1"}
   ```
   - 尝试 `call_id` 失败，尝试 `id` 成功

### 改进建议

1. **Tool 名称配置化**
   ```rust
   pub struct V2ParserConfig {
       pub codex_tool_name: String,
   }
   ```

2. **Arguments 字段严格匹配**
   ```rust
   // 使用第一个非空字段，但记录警告
   fn extract_input_transcript(arguments: &str, event_type: &str) -> String {
       // ...
       let mut found_key = None;
       for key in TOOL_ARGUMENT_KEYS {
           if let Some(value) = arguments_object.get(key).and_then(Value::as_str) {
               if !value.trim().is_empty() {
                   if found_key.is_some() {
                       warn!("multiple non-empty keys in arguments: {:?}", TOOL_ARGUMENT_KEYS);
                   }
                   found_key = Some((key, value));
               }
           }
       }
       // ...
   }
   ```

3. **Response Done 完整解析**
   ```rust
   fn parse_response_done_event(parsed: Value) -> Option<RealtimeEvent> {
       // 检查 Handoff
       if let Some(handoff) = parse_response_done_handoff_requested_event(&parsed) {
           return Some(handoff);
       }
       
       // 提取 response 信息
       let response = parsed.get("response").and_then(Value::as_object)?;
       let response_id = response.get("id").and_then(Value::as_str)?;
       let status = response.get("status").and_then(Value::as_str);
       
       // 根据 status 返回不同事件
       match status {
           Some("completed") => /* ... */,
           Some("cancelled") => /* ... */,
           Some("failed") => /* ... */,
           _ => /* ... */,
       }
   }
   ```

4. **更严格的类型验证**
   ```rust
   fn parse_handoff_requested_event(item: &JsonMap<String, Value>) -> Option<RealtimeEvent> {
       // 验证 type 字段
       let item_type = item.get("type").and_then(Value::as_str)?;
       if item_type != "function_call" {
           return None;
       }
       
       // 验证 name 字段
       let item_name = item.get("name").and_then(Value::as_str)?;
       if item_name != CODEX_TOOL_NAME {
           return None;
       }
       
       // 验证 call_id 存在
       let call_id = item
           .get("call_id")
           .and_then(Value::as_str)
           .or_else(|| item.get("id").and_then(Value::as_str))?;
       
       if call_id.is_empty() {
           debug!("empty call_id in codex function call");
           return None;
       }
       
       // ...
   }
   ```

5. **添加 metrics**
   ```rust
   fn parse_realtime_event_v2(payload: &str) -> Option<RealtimeEvent> {
       let (parsed, message_type) = parse_realtime_payload(payload, "realtime v2")?;
       
       // 记录事件类型分布
       metrics::counter!("realtime_v2_events", "type" => message_type.clone()).increment(1);
       
       match message_type.as_str() {
           // ...
       }
   }
   ```
