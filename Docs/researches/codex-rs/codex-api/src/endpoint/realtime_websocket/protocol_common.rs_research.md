# protocol_common.rs 研究文档

## 场景与职责

`protocol_common.rs` 是 Realtime WebSocket 协议解析的共享工具模块，提供 V1 和 V2 协议解析器共同使用的基础函数。它负责：
- 通用的 JSON 载荷解析和验证
- 共享事件类型的解析（如 session.updated、error）
- 转录增量事件的通用解析逻辑

该模块的设计目标是避免 V1 和 V2 解析器中的代码重复，同时提供一致的日志记录和错误处理方式。

## 功能点目的

### 1. 通用载荷解析
- **目的**：提取 JSON 中的 `type` 字段，验证基本格式
- **函数**：`parse_realtime_payload()`

### 2. Session Updated 事件解析
- **目的**：解析会话更新确认事件
- **函数**：`parse_session_updated_event()`

### 3. 转录增量解析
- **目的**：解析输入/输出转录文本增量
- **函数**：`parse_transcript_delta_event()`

### 4. 错误事件解析
- **目的**：解析服务器返回的错误信息
- **函数**：`parse_error_event()`

## 具体技术实现

### 1. 通用载荷解析

```rust
pub(super) fn parse_realtime_payload(payload: &str, parser_name: &str) -> Option<(Value, String)> {
    // 1. 解析 JSON
    let parsed: Value = match serde_json::from_str(payload) {
        Ok(message) => message,
        Err(err) => {
            debug!("failed to parse {parser_name} event: {err}, data: {payload}");
            return None;
        }
    };

    // 2. 提取 type 字段
    let message_type = match parsed.get("type").and_then(Value::as_str) {
        Some(message_type) => message_type.to_string(),
        None => {
            debug!("received {parser_name} event without type field: {payload}");
            return None;
        }
    };

    Some((parsed, message_type))
}
```

**设计要点**：
- 返回 `(Value, String)` 元组，包含解析后的 JSON 和消息类型
- 使用 `debug!` 级别日志，避免正常解析失败时产生过多日志
- `parser_name` 参数用于区分 V1/V2 的日志来源

**使用示例**：
```rust
// protocol_v1.rs
pub(super) fn parse_realtime_event_v1(payload: &str) -> Option<RealtimeEvent> {
    let (parsed, message_type) = parse_realtime_payload(payload, "realtime v1")?;
    match message_type.as_str() {
        "session.updated" => parse_session_updated_event(&parsed),
        // ...
    }
}
```

### 2. Session Updated 事件解析

```rust
pub(super) fn parse_session_updated_event(parsed: &Value) -> Option<RealtimeEvent> {
    // 提取 session.id
    let session_id = parsed
        .get("session")
        .and_then(Value::as_object)
        .and_then(|session| session.get("id"))
        .and_then(Value::as_str)
        .map(str::to_string)?;
    
    // 提取 session.instructions（可选）
    let instructions = parsed
        .get("session")
        .and_then(Value::as_object)
        .and_then(|session| session.get("instructions"))
        .and_then(Value::as_str)
        .map(str::to_string);
    
    Some(RealtimeEvent::SessionUpdated {
        session_id,
        instructions,
    })
}
```

**字段提取策略**：
- `session_id`：必需字段，使用 `?` 提前返回
- `instructions`：可选字段，使用 `Option` 包装

**生成的 RealtimeEvent**：
```rust
RealtimeEvent::SessionUpdated {
    session_id: "sess_123".to_string(),
    instructions: Some("系统提示词".to_string()),
}
```

### 3. 转录增量解析

```rust
pub(super) fn parse_transcript_delta_event(
    parsed: &Value,
    field: &str,  // 字段名参数化，支持 "delta" 或 "transcript"
) -> Option<RealtimeTranscriptDelta> {
    parsed
        .get(field)
        .and_then(Value::as_str)
        .map(str::to_string)
        .map(|delta| RealtimeTranscriptDelta { delta })
}
```

**设计意图**：
- V1 和 V2 的转录增量字段名可能不同（`delta` vs `transcript`）
- 通过参数化避免代码重复

**使用场景**：
```rust
// V1: conversation.input_transcript.delta
"conversation.input_transcript.delta" => {
    parse_transcript_delta_event(&parsed, "delta").map(RealtimeEvent::InputTranscriptDelta)
}

// V2: conversation.item.input_audio_transcription.completed
"conversation.item.input_audio_transcription.completed" => {
    parse_transcript_delta_event(&parsed, "transcript").map(RealtimeEvent::InputTranscriptDelta)
}
```

### 4. 错误事件解析

```rust
pub(super) fn parse_error_event(parsed: &Value) -> Option<RealtimeEvent> {
    // 尝试多种错误信息位置
    parsed
        .get("message")
        .and_then(Value::as_str)
        .map(str::to_string)
        .or_else(|| {
            parsed
                .get("error")
                .and_then(Value::as_object)
                .and_then(|error| error.get("message"))
                .and_then(Value::as_str)
                .map(str::to_string)
        })
        .or_else(|| parsed.get("error").map(ToString::to_string))
        .map(RealtimeEvent::Error)
}
```

**错误格式兼容性**：
- 格式 1：`{"type": "error", "message": "..."}`
- 格式 2：`{"type": "error", "error": {"message": "..."}}`
- 格式 3：`{"type": "error", "error": "..."}`（任意类型）

**回退策略**：
- 优先尝试扁平的 `message` 字段
- 其次尝试嵌套的 `error.message`
- 最后尝试将整个 `error` 值转为字符串

## 关键代码路径与文件引用

### 模块依赖

```
protocol_common.rs
├── protocol_v1.rs    # 使用 parse_realtime_payload, parse_session_updated_event, parse_transcript_delta_event, parse_error_event
└── protocol_v2.rs    # 同上
```

### 导入依赖

```rust
use codex_protocol::protocol::RealtimeEvent;
use codex_protocol::protocol::RealtimeTranscriptDelta;
use serde_json::Value;
use tracing::debug;
```

### 调用关系图

```
protocol_v1.rs:parse_realtime_event_v1()
├── protocol_common.rs:parse_realtime_payload()          # 所有事件
├── protocol_common.rs:parse_session_updated_event()     # session.updated
├── protocol_common.rs:parse_transcript_delta_event()    # input/output_transcript.delta
└── protocol_common.rs:parse_error_event()               # error

protocol_v2.rs:parse_realtime_event_v2()
├── protocol_common.rs:parse_realtime_payload()          # 所有事件
├── protocol_common.rs:parse_session_updated_event()     # session.updated
├── protocol_common.rs:parse_transcript_delta_event()    # input_audio_transcription.delta/completed, output_text.delta
└── protocol_common.rs:parse_error_event()               # error
```

## 依赖与外部交互

### 与 protocol_v1/v2 的关系

| 函数 | V1 使用 | V2 使用 | 说明 |
|------|---------|---------|------|
| `parse_realtime_payload` | ✓ | ✓ | 所有事件入口 |
| `parse_session_updated_event` | ✓ | ✓ | session.updated |
| `parse_transcript_delta_event` | ✓ | ✓ | 多种转录事件 |
| `parse_error_event` | ✓ | ✓ | error 事件 |

### 与 codex_protocol 的关系

使用 `codex_protocol::protocol` 中的类型：
- `RealtimeEvent`：解析结果类型
- `RealtimeTranscriptDelta`：转录增量类型

### 日志记录

使用 `tracing::debug` 级别记录：
- JSON 解析失败
- 缺少 type 字段

**注意**：不记录解析成功的情况，避免日志过多。

## 风险、边界与改进建议

### 风险分析

1. **日志级别选择**
   - 使用 `debug!` 级别，生产环境可能看不到解析失败
   - 建议：解析失败可能影响功能，考虑使用 `warn!`

2. **错误信息丢失**
   - `parse_error_event` 只提取 message，丢失其他字段（如 `code`, `param`）
   - 可能不利于问题排查

3. **空字符串处理**
   - `parse_transcript_delta_event` 接受空字符串作为有效 delta
   - 可能导致无意义的空转录事件

### 边界情况

1. **JSON 对象过大**
   - `parse_realtime_payload` 将整个 payload 解析为 `Value`
   - 超大 payload 可能导致内存问题

2. **Type 字段非字符串**
   ```json
   {"type": 123, "session": {"id": "sess_1"}}
   ```
   - `Value::as_str()` 返回 `None`，记录 "without type field" 日志
   - 实际有 type 字段，但类型错误

3. **Session 字段缺失**
   ```json
   {"type": "session.updated"}
   ```
   - `parse_session_updated_event` 返回 `None`
   - 没有错误日志，静默失败

4. **嵌套路径不存在**
   ```json
   {"type": "error", "error": null}
   ```
   - `parse_error_event` 尝试 `error.message` 失败
   - 回退到 `error.to_string()`，结果为 `"null"`

### 改进建议

1. **增强日志**
   ```rust
   pub(super) fn parse_realtime_payload(payload: &str, parser_name: &str) -> Option<(Value, String)> {
       let parsed: Value = match serde_json::from_str(payload) {
           Ok(message) => message,
           Err(err) => {
               // 提升为 warn，并限制 payload 长度
               let truncated = if payload.len() > 200 {
                   format!("{}...", &payload[..200])
               } else {
                   payload.to_string()
               };
               warn!("failed to parse {parser_name} event: {err}, data: {truncated}");
               return None;
           }
       };
       // ...
   }
   ```

2. **更详细的错误解析**
   ```rust
   #[derive(Debug)]
   pub struct RealtimeError {
       pub message: String,
       pub code: Option<String>,
       pub param: Option<String>,
       pub event_type: Option<String>,
   }
   
   pub(super) fn parse_error_event_detailed(parsed: &Value) -> Option<RealtimeError> {
       // 提取更多字段
   }
   ```

3. **空值过滤**
   ```rust
   pub(super) fn parse_transcript_delta_event(
       parsed: &Value,
       field: &str,
   ) -> Option<RealtimeTranscriptDelta> {
       let delta = parsed
           .get(field)
           .and_then(Value::as_str)
           .map(str::to_string)?;
       
       // 过滤空字符串
       if delta.is_empty() {
           return None;
       }
       
       Some(RealtimeTranscriptDelta { delta })
   }
   ```

4. **字段类型验证**
   ```rust
   pub(super) fn parse_session_updated_event(parsed: &Value) -> Option<RealtimeEvent> {
       let session = parsed.get("session").and_then(Value::as_object)?;
       
       // 验证 session 是对象
       let session_id = session.get("id")
           .and_then(|v| {
               if let Some(s) = v.as_str() {
                   Some(s.to_string())
               } else {
                   debug!("session.id is not a string: {:?}", v);
                   None
               }
           })?;
       // ...
   }
   ```

5. **添加单元测试**
   ```rust
   #[cfg(test)]
   mod tests {
       use super::*;
       use serde_json::json;
       
       #[test]
       fn test_parse_realtime_payload_valid() {
           let payload = r#"{"type": "test", "data": 123}"#;
           let (value, msg_type) = parse_realtime_payload(payload, "test").unwrap();
           assert_eq!(msg_type, "test");
           assert_eq!(value["data"], 123);
       }
       
       #[test]
       fn test_parse_realtime_payload_invalid_json() {
           let payload = "not json";
           assert!(parse_realtime_payload(payload, "test").is_none());
       }
       
       #[test]
       fn test_parse_session_updated_event() {
           let parsed = json!({
               "session": {
                   "id": "sess_123",
                   "instructions": "test"
               }
           });
           let event = parse_session_updated_event(&parsed).unwrap();
           match event {
               RealtimeEvent::SessionUpdated { session_id, instructions } => {
                   assert_eq!(session_id, "sess_123");
                   assert_eq!(instructions, Some("test".to_string()));
               }
               _ => panic!("wrong event type"),
           }
       }
   }
   ```
