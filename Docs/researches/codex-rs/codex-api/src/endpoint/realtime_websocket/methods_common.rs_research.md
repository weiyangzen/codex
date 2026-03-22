# methods_common.rs 研究文档

## 场景与职责

`methods_common.rs` 是 Realtime WebSocket 方法层的版本适配器，负责在 V1 和 V2 协议版本之间进行方法调度的中间层。它实现了**策略模式（Strategy Pattern）**，根据 `RealtimeEventParser` 的选择，将调用分派到对应版本的实现。

该模块的核心职责是：
- 提供统一的方法接口，隐藏版本差异
- 处理跨版本共用的常量定义
- 实现版本特定的行为归一化（如 V1 强制使用 Conversational 模式）

## 功能点目的

### 1. 版本无关的方法代理
- **目的**：为上层提供统一的 API，无需关心底层协议版本
- **功能**：根据 `RealtimeEventParser` 枚举值，动态选择 V1 或 V2 的实现

### 2. 常量定义
- **目的**：集中管理跨版本共享的常量
- **当前常量**：
  - `REALTIME_AUDIO_SAMPLE_RATE: u32 = 24_000` - 音频采样率
  - `AGENT_FINAL_MESSAGE_PREFIX` - Handoff 消息前缀标记

### 3. 会话模式归一化
- **目的**：处理 V1 和 V2 在会话模式上的差异
- **功能**：V1 强制返回 `Conversational` 模式（不支持 Transcription）

## 具体技术实现

### 方法代理实现

```rust
pub(super) fn conversation_item_create_message(
    event_parser: RealtimeEventParser,
    text: String,
) -> RealtimeOutboundMessage {
    match event_parser {
        RealtimeEventParser::V1 => v1_conversation_item_create_message(text),
        RealtimeEventParser::RealtimeV2 => v2_conversation_item_create_message(text),
    }
}
```

所有代理方法遵循相同模式：
1. 接收 `event_parser` 作为第一个参数
2. 使用 `match` 分派到对应版本
3. 返回统一类型的结果

### 代理方法列表

| 方法名 | V1 实现 | V2 实现 | 说明 |
|--------|---------|---------|------|
| `normalized_session_mode` | 强制返回 `Conversational` | 原样返回 | V1 不支持 Transcription |
| `conversation_item_create_message` | `methods_v1::conversation_item_create_message` | `methods_v2::conversation_item_create_message` | 文本消息构造 |
| `conversation_handoff_append_message` | `methods_v1::conversation_handoff_append_message` | `methods_v2::conversation_handoff_append_message` | Handoff 响应构造 |
| `session_update_session` | `methods_v1::session_update_session` | `methods_v2::session_update_session` | 会话配置构造 |
| `websocket_intent` | 返回 `"quicksilver"` | 返回 `None` | URL query 参数 |

### Handoff 消息前缀处理

```rust
const AGENT_FINAL_MESSAGE_PREFIX: &str = "\"Agent Final Message\":\n\n";

pub(super) fn conversation_handoff_append_message(
    event_parser: RealtimeEventParser,
    handoff_id: String,
    output_text: String,
) -> RealtimeOutboundMessage {
    let output_text = format!("{AGENT_FINAL_MESSAGE_PREFIX}{output_text}");
    // ... 版本分派
}
```

**设计意图**：
- 在输出文本前添加特定前缀，用于标识这是 Agent 的最终消息
- 该前缀在 V1 和 V2 中保持一致，确保服务端能正确识别

## 关键代码路径与文件引用

### 模块依赖图
```
methods_common.rs
├── methods_v1.rs      # V1 协议具体实现
├── methods_v2.rs      # V2 协议具体实现
└── protocol.rs        # RealtimeEventParser, RealtimeOutboundMessage 等类型
```

### 导入结构
```rust
// 版本实现导入（使用别名避免命名冲突）
use crate::endpoint::realtime_websocket::methods_v1::conversation_handoff_append_message as v1_conversation_handoff_append_message;
use crate::endpoint::realtime_websocket::methods_v1::conversation_item_create_message as v1_conversation_item_create_message;
use crate::endpoint::realtime_websocket::methods_v1::session_update_session as v1_session_update_session;
use crate::endpoint::realtime_websocket::methods_v1::websocket_intent as v1_websocket_intent;
use crate::endpoint::realtime_websocket::methods_v2::conversation_handoff_append_message as v2_conversation_handoff_append_message;
use crate::endpoint::realtime_websocket::methods_v2::conversation_item_create_message as v2_conversation_item_create_message;
use crate::endpoint::realtime_websocket::methods_v2::session_update_session as v2_session_update_session;
use crate::endpoint::realtime_websocket::methods_v2::websocket_intent as v2_websocket_intent;

// 协议类型导入
use crate::endpoint::realtime_websocket::protocol::RealtimeEventParser;
use crate::endpoint::realtime_websocket::protocol::RealtimeOutboundMessage;
use crate::endpoint::realtime_websocket::protocol::RealtimeSessionMode;
use crate::endpoint::realtime_websocket::protocol::SessionUpdateSession;
```

### 调用方
- `methods.rs` - 通过 `use` 导入这些函数，用于构建 WebSocket 消息

## 依赖与外部交互

### 与 methods.rs 的交互
`methods.rs` 通过以下方式使用本模块：
```rust
use crate::endpoint::realtime_websocket::methods_common::conversation_handoff_append_message;
use crate::endpoint::realtime_websocket::methods_common::conversation_item_create_message;
use crate::endpoint::realtime_websocket::methods_common::normalized_session_mode;
use crate::endpoint::realtime_websocket::methods_common::session_update_session;
use crate::endpoint::realtime_websocket::methods_common::websocket_intent;
```

### 版本差异处理

| 特性 | V1 (Quicksilver) | V2 (Realtime) |
|------|------------------|---------------|
| Session Type | `quicksilver` | `realtime` / `transcription` |
| Intent Query | `quicksilver` | 无 |
| 音频输出 | 固定配置 | 可配置（采样率、声音） |
| Tools | 不支持 | 支持 `codex` tool |
| Turn Detection | 固定 | 可配置（ServerVAD） |
| Noise Reduction | 无 | Near-field |

## 风险、边界与改进建议

### 风险分析

1. **硬编码常量**
   - `AGENT_FINAL_MESSAGE_PREFIX` 是魔术字符串，如果服务端修改前缀，需要同步更新
   - 建议：考虑从配置读取或版本协商

2. **版本判断扩散**
   - 每个方法都需要 `match event_parser`，新增方法容易遗漏
   - 建议：考虑使用 trait 抽象（`ProtocolV1`, `ProtocolV2`）

3. **V1 模式强制转换**
   - `normalized_session_mode`  silently 忽略 V1 的 Transcription 请求
   - 调用方可能不知道模式被修改了

### 边界情况

1. **未知的 EventParser 变体**
   - 如果新增 `RealtimeEventParser` 变体但未更新本模块，编译会报错（exhaustive match）
   - 这是 Rust 的类型安全特性，强制处理所有情况

2. **空字符串处理**
   - `conversation_handoff_append_message` 对空 `output_text` 仍会添加前缀
   - 结果：`"Agent Final Message":\n\n`（只有前缀）

### 改进建议

1. **架构优化**
   ```rust
   // 建议：使用 trait 替代函数分派
   trait ProtocolVersion {
       fn conversation_item_create(&self, text: String) -> RealtimeOutboundMessage;
       fn session_update(&self, instructions: String, mode: RealtimeSessionMode) -> SessionUpdateSession;
       // ...
   }
   
   struct V1Protocol;
   struct V2Protocol;
   
   impl ProtocolVersion for V1Protocol { ... }
   impl ProtocolVersion for V2Protocol { ... }
   ```

2. **配置化前缀**
   ```rust
   // 建议：允许从外部配置前缀
   pub struct HandoffConfig {
       pub final_message_prefix: String,
   }
   ```

3. **模式转换警告**
   ```rust
   pub(super) fn normalized_session_mode(...) -> RealtimeSessionMode {
       match event_parser {
           RealtimeEventParser::V1 => {
               if session_mode != RealtimeSessionMode::Conversational {
                   tracing::warn!("V1 protocol forces Conversational mode, ignoring {:?}", session_mode);
               }
               RealtimeSessionMode::Conversational
           }
           RealtimeEventParser::RealtimeV2 => session_mode,
       }
   }
   ```

4. **文档强化**
   - 添加更多内联文档说明版本差异
   - 为每个代理方法添加示例代码
