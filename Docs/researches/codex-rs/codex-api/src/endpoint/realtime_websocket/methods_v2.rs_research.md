# methods_v2.rs 研究文档

## 场景与职责

`methods_v2.rs` 实现了 OpenAI Realtime API V2 协议（标准 Realtime API）的消息构造逻辑。这是 Codex 当前推荐使用的实时语音协议版本，支持更灵活的配置和更丰富的功能集，包括两种会话模式（Conversational 和 Transcription）以及完整的工具调用支持。

该模块的主要场景：
- 标准 Realtime API 对话（语音输入/输出）
- 纯转录模式（仅语音转文本，无语音输出）
- 支持 Handoff 到 Codex Agent 的复杂工作流

## 功能点目的

### 1. 对话项创建
- **目的**：构造用户文本输入消息
- **特点**：使用 `content.type: "input_text"`（与 V1 的 `"text"` 区分）

### 2. Handoff 功能调用输出
- **目的**：将 Codex 执行结果作为 function call output 返回
- **特点**：使用 `conversation.item.create`  with `type: "function_call_output"`
- **机制**：与 V1 的 `conversation.handoff.append` 不同，V2 使用标准 function call 流程

### 3. 会话更新配置（双模式）
- **Conversational 模式**：完整语音对话，包含输入/输出、tools、turn detection
- **Transcription 模式**：仅语音转录，无输出音频、无 tools、无 instructions

### 4. WebSocket Intent
- **目的**：V2 不需要 intent query 参数
- **返回值**：`None`

## 具体技术实现

### 常量定义

```rust
const REALTIME_V2_OUTPUT_MODALITY_AUDIO: &str = "audio";
const REALTIME_V2_TOOL_CHOICE: &str = "auto";
const REALTIME_V2_CODEX_TOOL_NAME: &str = "codex";
const REALTIME_V2_CODEX_TOOL_DESCRIPTION: &str = "Delegate a request to Codex and return the final result to the user...";
```

### 消息构造详解

#### 1. 对话项创建（conversation_item_create_message）

```rust
pub(super) fn conversation_item_create_message(text: String) -> RealtimeOutboundMessage {
    RealtimeOutboundMessage::ConversationItemCreate {
        item: ConversationItemPayload::Message(ConversationMessageItem {
            r#type: ConversationItemType::Message,
            role: ConversationRole::User,
            content: vec![ConversationItemContent {
                r#type: ConversationContentType::InputText,  // V2 使用 "input_text"
                text,
            }],
        }),
    }
}
```

**生成的 JSON 示例**：
```json
{
  "type": "conversation.item.create",
  "item": {
    "type": "message",
    "role": "user",
    "content": [{"type": "input_text", "text": "用户输入"}]
  }
}
```

**与 V1 的区别**：V1 使用 `"text"`，V2 使用 `"input_text"` 更明确地表示输入类型。

#### 2. Handoff 功能调用输出（conversation_handoff_append_message）

```rust
pub(super) fn conversation_handoff_append_message(
    handoff_id: String,
    output_text: String,
) -> RealtimeOutboundMessage {
    RealtimeOutboundMessage::ConversationItemCreate {
        item: ConversationItemPayload::FunctionCallOutput(ConversationFunctionCallOutputItem {
            r#type: ConversationItemType::FunctionCallOutput,
            call_id: handoff_id,  // 使用 handoff_id 作为 call_id
            output: output_text,
        }),
    }
}
```

**生成的 JSON 示例**：
```json
{
  "type": "conversation.item.create",
  "item": {
    "type": "function_call_output",
    "call_id": "call_123",
    "output": "\"Agent Final Message\":\n\n执行结果"
  }
}
```

**与 V1 的区别**：
- V1: 使用专门的 `conversation.handoff.append` 消息类型
- V2: 使用标准的 function call output 机制，更符合 OpenAI API 规范

#### 3. 会话更新（session_update_session）- Conversational 模式

```rust
RealtimeSessionMode::Conversational => SessionUpdateSession {
    r#type: SessionType::Realtime,
    instructions: Some(instructions),
    output_modalities: Some(vec![REALTIME_V2_OUTPUT_MODALITY_AUDIO.to_string()]),
    audio: SessionAudio {
        input: SessionAudioInput {
            format: SessionAudioFormat {
                r#type: AudioFormatType::AudioPcm,
                rate: REALTIME_AUDIO_SAMPLE_RATE,  // 24_000
            },
            noise_reduction: Some(SessionNoiseReduction {
                r#type: NoiseReductionType::NearField,
            }),
            turn_detection: Some(SessionTurnDetection {
                r#type: TurnDetectionType::ServerVad,
                interrupt_response: true,
                create_response: true,
            }),
        },
        output: Some(SessionAudioOutput {
            format: Some(SessionAudioOutputFormat {
                r#type: AudioFormatType::AudioPcm,
                rate: REALTIME_AUDIO_SAMPLE_RATE,
            }),
            voice: SessionAudioVoice::Marin,  // V2 默认使用 marin
        }),
    },
    tools: Some(vec![SessionFunctionTool {
        r#type: SessionToolType::Function,
        name: REALTIME_V2_CODEX_TOOL_NAME.to_string(),
        description: REALTIME_V2_CODEX_TOOL_DESCRIPTION.to_string(),
        parameters: json!({
            "type": "object",
            "properties": {
                "prompt": {
                    "type": "string",
                    "description": "The user request to delegate to Codex."
                }
            },
            "required": ["prompt"],
            "additionalProperties": false
        }),
    }]),
    tool_choice: Some(REALTIME_V2_TOOL_CHOICE.to_string()),
}
```

**生成的 JSON 示例**：
```json
{
  "type": "session.update",
  "session": {
    "type": "realtime",
    "instructions": "系统提示词",
    "output_modalities": ["audio"],
    "audio": {
      "input": {
        "format": {"type": "audio/pcm", "rate": 24000},
        "noise_reduction": {"type": "near_field"},
        "turn_detection": {
          "type": "server_vad",
          "interrupt_response": true,
          "create_response": true
        }
      },
      "output": {
        "format": {"type": "audio/pcm", "rate": 24000},
        "voice": "marin"
      }
    },
    "tools": [{
      "type": "function",
      "name": "codex",
      "description": "Delegate a request to Codex...",
      "parameters": {
        "type": "object",
        "properties": {
          "prompt": {"type": "string", "description": "The user request to delegate to Codex."}
        },
        "required": ["prompt"],
        "additionalProperties": false
      }
    }],
    "tool_choice": "auto"
  }
}
```

#### 4. 会话更新（session_update_session）- Transcription 模式

```rust
RealtimeSessionMode::Transcription => SessionUpdateSession {
    r#type: SessionType::Transcription,
    instructions: None,  // 转录模式不需要 instructions
    output_modalities: None,
    audio: SessionAudio {
        input: SessionAudioInput {
            format: SessionAudioFormat {
                r#type: AudioFormatType::AudioPcm,
                rate: REALTIME_AUDIO_SAMPLE_RATE,
            },
            noise_reduction: None,
            turn_detection: None,
        },
        output: None,  // 转录模式无输出音频
    },
    tools: None,
    tool_choice: None,
}
```

**生成的 JSON 示例**：
```json
{
  "type": "session.update",
  "session": {
    "type": "transcription",
    "audio": {
      "input": {
        "format": {"type": "audio/pcm", "rate": 24000}
      }
    }
  }
}
```

### Codex Tool 定义

V2 在 Conversational 模式下自动注册一个 `codex` tool，用于 Handoff：

```rust
SessionFunctionTool {
    r#type: SessionToolType::Function,
    name: "codex",
    description: "Delegate a request to Codex and return the final result to the user...",
    parameters: json!({
        "type": "object",
        "properties": {
            "prompt": {
                "type": "string",
                "description": "The user request to delegate to Codex."
            }
        },
        "required": ["prompt"],
        "additionalProperties": false
    }),
}
```

**设计意图**：
- 允许模型主动决定何时将任务委托给 Codex
- `prompt` 参数包含用户请求的完整文本
- 使用 `additionalProperties: false` 严格限制参数

## 关键代码路径与文件引用

### 模块依赖
```
methods_v2.rs
├── methods_common.rs    # 通过代理调用本模块
│   └── methods.rs       # 最终使用方
└── protocol.rs          # 类型定义
```

### 类型依赖
本模块使用 `protocol.rs` 中的类型，与 V1 相同，额外使用：
- `ConversationFunctionCallOutputItem` - function call output 项
- `SessionNoiseReduction` / `NoiseReductionType` - 降噪配置
- `SessionTurnDetection` / `TurnDetectionType` - 语音活动检测
- `SessionAudioOutputFormat` - 输出音频格式
- `SessionFunctionTool` / `SessionToolType` - 工具定义

### 调用链
```
methods.rs:RealtimeWebsocketWriter::send_session_update()
└── methods_common.rs:session_update_session()
    └── methods_v2.rs:session_update_session() [如果是 V2]
```

## 依赖与外部交互

### 与 V1 的详细对比

| 特性 | V1 | V2 Conversational | V2 Transcription |
|------|-----|-------------------|------------------|
| Session Type | `quicksilver` | `realtime` | `transcription` |
| Intent | `quicksilver` | 无 | 无 |
| Instructions | 支持 | 支持 | 无 |
| Output Modalities | 默认 | `["audio"]` | 无 |
| Input Format | PCM 24kHz | PCM 24kHz + near_field NR | PCM 24kHz |
| Turn Detection | 无 | ServerVAD | 无 |
| Output Format | 默认 | PCM 24kHz | 无 |
| Voice | `fathom` | `marin` | 无 |
| Tools | 无 | `codex` function | 无 |
| Tool Choice | 无 | `auto` | 无 |
| Handoff 机制 | `handoff.append` | function call output | 无 |

### 协议交互流程

**Conversational + Handoff 完整流程**：

1. **会话初始化**
   ```
   Client → Server: session.update (with codex tool)
   Server → Client: session.updated
   ```

2. **用户语音输入**
   ```
   Client → Server: input_audio_buffer.append (PCM audio)
   Server → Client: conversation.item.input_audio_transcription.delta
   ```

3. **模型决定 Handoff**
   ```
   Server → Client: conversation.item.done (type: function_call, name: codex)
   Client 解析为: RealtimeEvent::HandoffRequested
   ```

4. **Codex 执行**
   ```
   Client 执行 Codex 任务，获得结果
   ```

5. **返回结果**
   ```
   Client → Server: conversation.item.create (type: function_call_output)
   Server → Client: response.done
   ```

## 风险、边界与改进建议

### 风险分析

1. **Tool 定义硬编码**
   - `codex` tool 的参数结构固定，无法灵活扩展
   - 如果需要传递额外上下文（如 cwd、sandbox 配置），需要修改 schema

2. **Session Mode 切换**
   - 连接建立后无法切换模式（Conversational ↔ Transcription）
   - 需要重新建立连接

3. **Voice 选择有限**
   - 当前仅支持 `marin`，但协议支持更多声音
   - 建议：允许从配置读取 voice 选择

### 边界情况

1. **空 Instructions（Conversational 模式）**
   - 如果传入空字符串，`instructions: Some("")` 会被序列化
   - 可能导致模型行为不可预测

2. **Tool 调用冲突**
   - 如果用户同时配置了其他 tools，可能与 `codex` tool 产生冲突
   - `tool_choice: "auto"` 让模型决定，但可能不是用户预期

3. **Transcription 模式误用**
   - 如果在 Transcription 模式下发送 function_call_output，服务端可能报错

### 改进建议

1. **配置化参数**
   ```rust
   pub struct V2SessionConfig {
       pub voice: SessionAudioVoice,
       pub noise_reduction: Option<NoiseReductionType>,
       pub turn_detection: Option<TurnDetectionConfig>,
       pub codex_tool: Option<CodexToolConfig>,
   }
   ```

2. **Tool Schema 扩展**
   ```rust
   // 允许传递更多上下文
   parameters: json!({
       "properties": {
           "prompt": {"type": "string"},
           "context": {
               "type": "object",
               "properties": {
                   "cwd": {"type": "string"},
                   "sandbox_policy": {"type": "string"}
               }
           }
       }
   })
   ```

3. **输入验证**
   ```rust
   pub(super) fn session_update_session(...) -> SessionUpdateSession {
       if matches!(session_mode, RealtimeSessionMode::Conversational) {
           if instructions.is_empty() {
               tracing::warn!("Empty instructions in conversational mode");
           }
       }
       // ...
   }
   ```

4. **文档和示例**
   - 添加完整的 Handoff 流程文档
   - 提供不同模式的配置示例
