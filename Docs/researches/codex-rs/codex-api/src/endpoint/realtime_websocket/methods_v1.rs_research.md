# methods_v1.rs 研究文档

## 场景与职责

`methods_v1.rs` 实现了 OpenAI Realtime API V1 协议（内部代号 "Quicksilver"）的消息构造逻辑。这是 Codex 早期使用的实时语音协议版本，具有固定的配置参数和简化的功能集。

该模块的主要场景：
- 向后兼容旧版 Realtime API 部署
- 支持传统的语音对话模式（仅 Conversational，无 Transcription）

## 功能点目的

### 1. 对话项创建
- **目的**：构造用户文本输入消息
- **特点**：使用 `content.type: "text"`（而非 V2 的 `"input_text"`）

### 2. Handoff 追加消息
- **目的**：将 Codex 执行结果返回给 Realtime 会话
- **特点**：使用专门的 `conversation.handoff.append` 消息类型

### 3. 会话更新配置
- **目的**：配置 Realtime 会话参数
- **特点**：
  - Session Type: `quicksilver`
  - 固定使用 `fathom` 语音
  - 固定 24kHz 采样率
  - 无 noise reduction 配置
  - 无 turn detection 配置
  - 不支持 tools

### 4. WebSocket Intent
- **目的**：标识协议版本
- **返回值**：`"quicksilver"`（作为 URL query 参数）

## 具体技术实现

### 消息构造详解

#### 1. 对话项创建（conversation_item_create_message）

```rust
pub(super) fn conversation_item_create_message(text: String) -> RealtimeOutboundMessage {
    RealtimeOutboundMessage::ConversationItemCreate {
        item: ConversationItemPayload::Message(ConversationMessageItem {
            r#type: ConversationItemType::Message,
            role: ConversationRole::User,
            content: vec![ConversationItemContent {
                r#type: ConversationContentType::Text,  // V1 使用 "text"
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
    "content": [{"type": "text", "text": "用户输入"}]
  }
}
```

#### 2. Handoff 追加（conversation_handoff_append_message）

```rust
pub(super) fn conversation_handoff_append_message(
    handoff_id: String,
    output_text: String,
) -> RealtimeOutboundMessage {
    RealtimeOutboundMessage::ConversationHandoffAppend {
        handoff_id,
        output_text,
    }
}
```

**生成的 JSON 示例**：
```json
{
  "type": "conversation.handoff.append",
  "handoff_id": "handoff_123",
  "output_text": "\"Agent Final Message\":\n\n执行结果"
}
```

#### 3. 会话更新（session_update_session）

```rust
pub(super) fn session_update_session(instructions: String) -> SessionUpdateSession {
    SessionUpdateSession {
        r#type: SessionType::Quicksilver,
        instructions: Some(instructions),
        output_modalities: None,  // V1 不指定，使用服务端默认
        audio: SessionAudio {
            input: SessionAudioInput {
                format: SessionAudioFormat {
                    r#type: AudioFormatType::AudioPcm,
                    rate: REALTIME_AUDIO_SAMPLE_RATE,  // 24_000
                },
                noise_reduction: None,  // V1 不支持
                turn_detection: None,   // V1 不支持
            },
            output: Some(SessionAudioOutput {
                format: None,  // 使用服务端默认
                voice: SessionAudioVoice::Fathom,  // 固定使用 fathom
            }),
        },
        tools: None,       // V1 不支持 tools
        tool_choice: None, // V1 不支持 tool_choice
    }
}
```

**生成的 JSON 示例**：
```json
{
  "type": "session.update",
  "session": {
    "type": "quicksilver",
    "instructions": "系统提示词",
    "audio": {
      "input": {
        "format": {"type": "audio/pcm", "rate": 24000}
      },
      "output": {
        "voice": "fathom"
      }
    }
  }
}
```

### 常量定义

```rust
pub(super) const REALTIME_AUDIO_SAMPLE_RATE: u32 = 24_000;
```

该采样率被 V1 和 V2 共享（通过 `methods_common.rs` re-export）。

## 关键代码路径与文件引用

### 模块位置
```
codex-rs/codex-api/src/endpoint/realtime_websocket/
├── methods.rs           # 主模块，通过 methods_common 间接使用
├── methods_common.rs    # 导入并代理本模块的函数
├── methods_v1.rs        # 本文件
├── methods_v2.rs        # V2 实现
└── protocol.rs          # 共享类型定义
```

### 类型依赖
本模块依赖 `protocol.rs` 中定义的以下类型：
- `RealtimeOutboundMessage` - 出站消息枚举
- `ConversationItemPayload` - 对话项载荷
- `ConversationMessageItem` - 消息项结构
- `ConversationItemType` - 项类型枚举
- `ConversationRole` - 角色枚举
- `ConversationItemContent` - 内容项
- `ConversationContentType` - 内容类型
- `SessionUpdateSession` - 会话更新结构
- `SessionType` - 会话类型枚举
- `SessionAudio` / `SessionAudioInput` / `SessionAudioOutput` - 音频配置
- `SessionAudioFormat` / `AudioFormatType` - 音频格式
- `SessionAudioVoice` - 语音枚举

### 调用链
```
methods.rs:RealtimeWebsocketWriter::send_conversation_item_create()
└── methods_common.rs:conversation_item_create_message()
    └── methods_v1.rs:conversation_item_create_message() [如果是 V1]
```

## 依赖与外部交互

### 与 V2 的差异对比

| 特性 | V1 (methods_v1.rs) | V2 (methods_v2.rs) |
|------|-------------------|-------------------|
| Session Type | `quicksilver` | `realtime` / `transcription` |
| Content Type | `text` | `input_text` |
| Output Modalities | 不指定 | 显式指定 `["audio"]` |
| Voice | 固定 `fathom` | 可配置（`marin` 等） |
| Noise Reduction | 无 | `near_field` |
| Turn Detection | 无 | `server_vad` |
| Tools | 无 | `codex` function tool |
| Tool Choice | 无 | `auto` |
| Output Format | 不指定 | 显式 `audio/pcm` @ 24kHz |

### 协议版本识别

通过 `websocket_intent()` 返回 `"quicksilver"`，在 URL 中体现为：
```
wss://api.openai.com/v1/realtime?intent=quicksilver&model=gpt-4o-realtime
```

## 风险、边界与改进建议

### 风险分析

1. **功能受限**
   - V1 不支持 Transcription 模式，强制使用 Conversational
   - 无 noise reduction，可能影响语音质量
   - 无 tools 支持，无法使用 Handoff 的 function call 机制

2. **硬编码配置**
   - 语音固定为 `fathom`，无法切换
   - 输出格式由服务端决定，客户端无法控制

3. **维护负担**
   - 需要同时维护 V1 和 V2 两套逻辑
   - 新增功能需要评估是否支持 V1

### 边界情况

1. **空 Instructions**
   - 如果传入空字符串，`instructions: Some("")` 会被序列化
   - 服务端可能将其视为有效指令（空提示词）

2. **长文本输入**
   - 无长度限制检查，超长文本可能导致服务端拒绝

3. **Handoff ID 格式**
   - 不对 `handoff_id` 格式进行验证，依赖服务端检查

### 改进建议

1. **废弃计划**
   - 考虑标记 V1 为 deprecated，引导用户迁移到 V2
   - 添加编译时警告或运行时日志

2. **配置验证**
   ```rust
   pub(super) fn session_update_session(instructions: String) -> SessionUpdateSession {
       if instructions.is_empty() {
           tracing::warn!("Empty instructions provided for V1 session");
       }
       // ...
   }
   ```

3. **文档完善**
   - 添加更多内联文档说明 V1 的限制
   - 链接到官方 API 文档

4. **测试覆盖**
   - 当前测试主要在 `methods.rs` 的 `#[cfg(test)]` 模块
   - 建议为本模块添加单元测试，验证 JSON 输出格式
