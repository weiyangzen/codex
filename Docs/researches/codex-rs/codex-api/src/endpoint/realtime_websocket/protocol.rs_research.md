# protocol.rs 研究文档

## 场景与职责

`protocol.rs` 定义了 Realtime WebSocket API 的协议类型和数据结构。它是整个实时语音功能的基础类型层，负责：
- 定义出站消息（客户端→服务器）的序列化格式
- 定义会话配置、音频格式、工具配置等核心数据结构
- 提供事件解析的入口函数，根据协议版本分发到具体解析器

该模块是连接 `codex-protocol` crate（共享协议）和具体协议实现（v1/v2）的桥梁。

## 功能点目的

### 1. 协议版本枚举
- **目的**：区分 V1 (Quicksilver) 和 V2 (Realtime) 协议
- **类型**：`RealtimeEventParser`

### 2. 会话模式枚举
- **目的**：区分 Conversational（语音对话）和 Transcription（纯转录）模式
- **类型**：`RealtimeSessionMode`

### 3. 会话配置结构
- **目的**：封装建立会话所需的所有参数
- **类型**：`RealtimeSessionConfig`

### 4. 出站消息枚举
- **目的**：定义客户端可以发送的所有消息类型
- **类型**：`RealtimeOutboundMessage`

### 5. 会话配置详细结构
- **目的**：定义 `session.update` 消息的完整结构
- **包括**：音频配置、工具配置、turn detection 等

### 6. 事件解析入口
- **目的**：根据协议版本选择正确的解析器
- **函数**：`parse_realtime_event()`

## 具体技术实现

### 核心类型定义

#### 1. 协议版本选择

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RealtimeEventParser {
    V1,
    RealtimeV2,
}
```

**使用场景**：
- 连接建立时指定，决定使用哪种协议格式
- 事件解析时选择对应的解析函数

#### 2. 会话模式

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RealtimeSessionMode {
    Conversational,
    Transcription,
}
```

**差异**：
- `Conversational`：完整语音对话，包含输入/输出音频、tools
- `Transcription`：仅语音转文本，无输出音频、无 tools

#### 3. 会话配置

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RealtimeSessionConfig {
    pub instructions: String,           // 系统提示词
    pub model: Option<String>,          // 模型名称（如 gpt-4o-realtime）
    pub session_id: Option<String>,     // 会话 ID（用于追踪）
    pub event_parser: RealtimeEventParser,  // 协议版本
    pub session_mode: RealtimeSessionMode,  // 会话模式
}
```

#### 4. 出站消息枚举

```rust
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type")]
pub(super) enum RealtimeOutboundMessage {
    #[serde(rename = "input_audio_buffer.append")]
    InputAudioBufferAppend { audio: String },  // Base64 编码的 PCM 音频

    #[serde(rename = "conversation.handoff.append")]
    ConversationHandoffAppend {  // V1 Handoff 响应
        handoff_id: String,
        output_text: String,
    },

    #[serde(rename = "response.create")]
    ResponseCreate,  // 触发模型生成响应

    #[serde(rename = "session.update")]
    SessionUpdate { session: SessionUpdateSession },  // 更新会话配置

    #[serde(rename = "conversation.item.create")]
    ConversationItemCreate { item: ConversationItemPayload },  // 创建对话项
}
```

**序列化示例**：
```rust
let msg = RealtimeOutboundMessage::InputAudioBufferAppend {
    audio: "AQIDBA==".to_string(),
};
// 序列化为：
// {"type": "input_audio_buffer.append", "audio": "AQIDBA=="}
```

### 会话配置详细结构

#### SessionUpdateSession

```rust
#[derive(Debug, Clone, Serialize)]
pub(super) struct SessionUpdateSession {
    #[serde(rename = "type")]
    pub(super) r#type: SessionType,  // quicksilver / realtime / transcription
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(super) instructions: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(super) output_modalities: Option<Vec<String>>,  // ["audio"]
    pub(super) audio: SessionAudio,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(super) tools: Option<Vec<SessionFunctionTool>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(super) tool_choice: Option<String>,  // "auto", "none", 或特定 tool
}
```

#### 音频配置层次

```rust
SessionAudio {
    input: SessionAudioInput {
        format: SessionAudioFormat {
            r#type: AudioFormatType::AudioPcm,  // "audio/pcm"
            rate: u32,  // 24000
        },
        noise_reduction: Option<SessionNoiseReduction>,
        turn_detection: Option<SessionTurnDetection>,
    },
    output: Option<SessionAudioOutput> {
        format: Option<SessionAudioOutputFormat>,
        voice: SessionAudioVoice,  // "fathom", "marin"
    },
}
```

#### 工具配置

```rust
#[derive(Debug, Clone, Serialize)]
pub(super) struct SessionFunctionTool {
    #[serde(rename = "type")]
    pub(super) r#type: SessionToolType,  // "function"
    pub(super) name: String,
    pub(super) description: String,
    pub(super) parameters: Value,  // JSON Schema
}
```

### 对话项类型

```rust
#[derive(Debug, Clone, Serialize)]
#[serde(untagged)]  // 无标签联合，根据内容自动选择变体
pub(super) enum ConversationItemPayload {
    Message(ConversationMessageItem),
    FunctionCallOutput(ConversationFunctionCallOutputItem),
}

#[derive(Debug, Clone, Serialize)]
pub(super) struct ConversationMessageItem {
    #[serde(rename = "type")]
    pub(super) r#type: ConversationItemType,  // "message"
    pub(super) role: ConversationRole,  // "user"
    pub(super) content: Vec<ConversationItemContent>,
}

#[derive(Debug, Clone, Serialize)]
pub(super) struct ConversationFunctionCallOutputItem {
    #[serde(rename = "type")]
    pub(super) r#type: ConversationItemType,  // "function_call_output"
    pub(super) call_id: String,
    pub(super) output: String,
}
```

### 事件解析入口

```rust
pub(super) fn parse_realtime_event(
    payload: &str,
    event_parser: RealtimeEventParser,
) -> Option<RealtimeEvent> {
    match event_parser {
        RealtimeEventParser::V1 => parse_realtime_event_v1(payload),
        RealtimeEventParser::RealtimeV2 => parse_realtime_event_v2(payload),
    }
}
```

**设计意图**：
- 统一的事件解析入口
- 根据连接时指定的协议版本分发到具体解析器
- 返回 `Option<RealtimeEvent>`，解析失败时返回 `None`（不中断流程）

## 关键代码路径与文件引用

### 模块依赖

```
protocol.rs
├── protocol_common.rs   # parse_realtime_payload, parse_session_updated_event, etc.
├── protocol_v1.rs       # parse_realtime_event_v1
└── protocol_v2.rs       # parse_realtime_event_v2
```

### 外部类型导入

```rust
pub use codex_protocol::protocol::RealtimeAudioFrame;
pub use codex_protocol::protocol::RealtimeEvent;
pub use codex_protocol::protocol::RealtimeHandoffRequested;
pub use codex_protocol::protocol::RealtimeTranscriptDelta;
pub use codex_protocol::protocol::RealtimeTranscriptEntry;
```

这些类型在 `codex-rs/protocol/src/protocol.rs` 中定义，被本模块重导出。

### 调用关系

```
methods.rs:RealtimeWebsocketEvents::next_event()
├── protocol.rs:parse_realtime_event()
│   ├── protocol_v1.rs:parse_realtime_event_v1()
│   │   └── protocol_common.rs:parse_realtime_payload()
│   └── protocol_v2.rs:parse_realtime_event_v2()
│       └── protocol_common.rs:parse_realtime_payload()
└── methods.rs:update_active_transcript()
```

## 依赖与外部交互

### 与 codex_protocol 的关系

| 类型 | 来源 | 用途 |
|------|------|------|
| `RealtimeAudioFrame` | `codex_protocol` | 音频数据（输入/输出） |
| `RealtimeEvent` | `codex_protocol` | 事件枚举（服务器→客户端） |
| `RealtimeHandoffRequested` | `codex_protocol` | Handoff 事件数据 |
| `RealtimeTranscriptDelta` | `codex_protocol` | 转录增量 |
| `RealtimeTranscriptEntry` | `codex_protocol` | 转录条目 |

### 序列化特性

所有出站消息类型都派生 `Serialize`：
```rust
#[derive(Debug, Clone, Serialize)]
```

使用 `serde` 的属性进行字段控制：
- `#[serde(tag = "type")]`：枚举的 type 字段标签
- `#[serde(rename = "...")]`：字段/变体重命名
- `#[serde(rename_all = "snake_case")]`：自动蛇形命名转换
- `#[serde(untagged)]`：无标签联合序列化
- `#[serde(skip_serializing_if = "Option::is_none")]`：Option 为 None 时不序列化

### 与 methods 模块的交互

`methods.rs` 使用本模块定义的类型：
- `RealtimeOutboundMessage`：构建发送消息
- `SessionUpdateSession`：构建会话更新
- `RealtimeSessionConfig`：连接配置
- `parse_realtime_event()`：解析接收事件

## 风险、边界与改进建议

### 风险分析

1. **类型一致性**
   - `RealtimeEvent` 在 `codex_protocol` 定义，但解析逻辑在 `protocol_v1/v2.rs`
   - 如果 `codex_protocol` 修改了 `RealtimeEvent`，需要同步更新解析器

2. **序列化兼容性**
   - `skip_serializing_if = "Option::is_none"` 可能导致服务端收到缺失字段
   - 需要确保服务端正确处理可选字段

3. **无标签联合风险**
   - `ConversationItemPayload` 使用 `#[serde(untagged)]`
   - 序列化顺序依赖，如果两个变体结构相似可能导致错误匹配

### 边界情况

1. **空内容向量**
   ```rust
   ConversationMessageItem {
       content: vec![],  // 空向量
   }
   ```
   序列化为 `"content": []`，服务端可能拒绝

2. **非常大的音频数据**
   - `InputAudioBufferAppend.audio` 是 `String`（Base64）
   - 大音频块可能导致内存分配失败

3. **非法 JSON Schema**
   - `SessionFunctionTool.parameters` 是 `Value`
   - 不验证是否为有效的 JSON Schema

### 改进建议

1. **类型验证**
   ```rust
   impl ConversationMessageItem {
       pub fn validate(&self) -> Result<(), ValidationError> {
           if self.content.is_empty() {
               return Err(ValidationError::EmptyContent);
           }
           Ok(())
       }
   }
   ```

2. **音频数据封装**
   ```rust
   // 使用新类型模式确保 Base64 编码
   pub struct Base64Audio(String);
   
   impl Base64Audio {
       pub fn from_pcm(pcm: &[i16]) -> Self {
           Self(BASE64_STANDARD.encode(pcm))
       }
   }
   ```

3. **JSON Schema 验证**
   ```rust
   pub struct SessionFunctionTool {
       // ...
       parameters: JsonSchema,  // 使用 jsonschema crate 验证
   }
   ```

4. **文档完善**
   ```rust
   /// Session configuration for Realtime API.
   ///
   /// # Example
   /// ```
   /// let config = RealtimeSessionConfig {
   ///     instructions: "You are a helpful assistant.".to_string(),
   ///     model: Some("gpt-4o-realtime-preview".to_string()),
   ///     session_id: Some("sess_123".to_string()),
   ///     event_parser: RealtimeEventParser::RealtimeV2,
   ///     session_mode: RealtimeSessionMode::Conversational,
   /// };
   /// ```
   pub struct RealtimeSessionConfig { ... }
   ```

5. **协议版本协商**
   ```rust
   // 考虑添加自动版本检测
   pub async fn detect_protocol_version(url: &str) -> Result<RealtimeEventParser, Error> {
       // 尝试 V2，失败后回退到 V1
   }
   ```
