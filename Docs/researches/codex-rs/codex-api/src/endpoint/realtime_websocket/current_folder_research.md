# DIR `codex-rs/codex-api/src/endpoint/realtime_websocket` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/codex-api/src/endpoint/realtime_websocket`
- 目标类型：`DIR`
- 研究日期：`2026-03-20`
- 关联 crate：`codex-api`
- 上游主调用方：`codex-rs/core/src/realtime_conversation.rs`

## 场景与职责

`realtime_websocket` 是 `codex-api` 中“实时语音/转录会话”的专用传输适配层，负责把 `core` 的会话语义映射到后端 Realtime WebSocket 协议，并把后端事件统一还原成 `codex_protocol::protocol::RealtimeEvent`。

该目录职责可以概括为 4 类：

1. 连接管理：
   - 把 `Provider.base_url` 规范成 `/v1/realtime` 的 `ws/wss` URL。
   - 合并 provider/header/session_id，建立 websocket，自动发送首个 `session.update`。
2. 出站协议编码：
   - 把音频帧、文本输入、handoff 输出、`response.create` 编码成后端要求的 JSON 消息。
   - 对 v1/v2 差异进行统一封装（`methods_common` + `methods_v1` + `methods_v2`）。
3. 入站协议解析：
   - 解析 v1/v2 多种事件类型，输出统一 `RealtimeEvent`。
   - 对 unknown/invalid 文本帧降级忽略，对错误帧转 `ApiError::Stream` 或 `RealtimeEvent::Error`。
4. 会话状态辅助：
   - 在 API 层维护 `active_transcript` 拼接（主要用于 v1 handoff 时把当前上下文拼给上游）。

边界上，它不负责：

1. 上层业务编排（何时触发 `response.create`、何时 `conversation.item.truncate`），这在 `core/src/realtime_conversation.rs`。
2. 认证策略决策（API key 来源、fallback），这在 `core`。
3. UI/协议外提示文案（realtime start/end 提示），这在 `codex-protocol` + `core/context_manager`。

## 功能点目的

### 1) `mod.rs`：模块拼装与公共导出

- 将内部拆分为：
  - 传输与连接：`methods.rs`
  - v1/v2 出站构造：`methods_common.rs` / `methods_v1.rs` / `methods_v2.rs`
  - 协议结构与解析：`protocol.rs` / `protocol_common.rs` / `protocol_v1.rs` / `protocol_v2.rs`
- 对外 re-export：`RealtimeWebsocketClient`、`RealtimeWebsocketConnection`、`RealtimeSessionConfig`、`RealtimeEventParser`、`RealtimeSessionMode`。

### 2) `methods.rs`：连接与并发收发主实现

目的：提供上游可直接调用的统一 API。

- `RealtimeWebsocketClient::connect`：建连 + 发送 `session.update`。
- `RealtimeWebsocketWriter`：
  - `send_audio_frame`
  - `send_conversation_item_create`
  - `send_conversation_handoff_append`
  - `send_response_create`
  - `send_session_update`
- `RealtimeWebsocketEvents::next_event`：持续读帧并输出 `RealtimeEvent`。
- `WsStream`：单独 pump task，实现“命令发送通道 + 入站消息通道”解耦，避免读写互锁。

### 3) `methods_common.rs`：v1/v2 分流总线

目的：在写路径统一入口处，根据 `RealtimeEventParser` 选择具体版本实现。

- 统一处理：
  - `normalized_session_mode`
  - `conversation_item_create_message`
  - `conversation_handoff_append_message`
  - `session_update_session`
  - `websocket_intent`
- 注入固定前缀：handoff 输出被统一包装为 `"Agent Final Message":\n\n...`。

### 4) `methods_v1.rs`：v1 写协议

目的：构造 quicksilver 风格会话。

- `session.update.session.type = quicksilver`
- 文本输入 content type 为 `text`
- handoff 通过 `conversation.handoff.append`
- websocket query 强制 `intent=quicksilver`

### 5) `methods_v2.rs`：v2 写协议

目的：构造 realtime/transcription 双模式会话。

- Conversational：
  - `session.type = realtime`
  - 开启输出模态 `audio`
  - 配置 near-field 降噪 + server_vad turn detection
  - 注册 `codex` function tool（`prompt` 参数）并设置 `tool_choice=auto`
  - 默认输出 voice `marin`
- Transcription：
  - `session.type = transcription`
  - 不发送 instructions / output audio / tools
- v2 不带 `intent` query。

### 6) `protocol.rs`：协议模型与解析入口

- 定义解析器与模式枚举：`RealtimeEventParser::{V1, RealtimeV2}`、`RealtimeSessionMode::{Conversational, Transcription}`。
- 定义出站消息结构：`RealtimeOutboundMessage`、`SessionUpdateSession`、音频/turn detection/tool 等结构。
- `parse_realtime_event(payload, parser)` 分发到 v1/v2 解析器。

### 7) `protocol_common.rs`：解析公共助手

- 统一 JSON 解析 + `type` 字段提取。
- 公共事件字段抽取：`session.updated`、transcript delta、error。

### 8) `protocol_v1.rs` / `protocol_v2.rs`：入站协议差异实现

- v1：解析 `conversation.output_audio.delta`、`conversation.handoff.requested` 等旧事件名。
- v2：兼容 `response.output_audio.delta`/`response.audio.delta`，并从 `function_call(name=codex)` 中提取 handoff。

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. 关键流程

#### A1. 建连流程（`RealtimeWebsocketClient::connect`）

1. `websocket_url_from_api_url(...)`：
   - 解析 `api_url`。
   - 调用 `normalize_realtime_path` 补齐 `/v1/realtime`。
   - `http/https` 转 `ws/wss`。
   - 追加 `intent/model/extra query`（v1 有 `intent`，v2 无）。
2. 构建 `IntoClientRequest`，合并 headers：
   - provider headers
   - extra headers（含可选 `x-session-id`）
   - default headers（仅在前两者缺失时补）
3. 使用 `maybe_build_rustls_client_config_with_custom_ca()` 支持自定义 CA 的 TLS websocket 连接。
4. 建连成功后创建 `WsStream` pump（读写双通道），构造 `RealtimeWebsocketConnection`。
5. 立即发送 `session.update` 初始化后端 session。

#### A2. 出站消息流程（writer）

- API 调用 -> `RealtimeOutboundMessage` -> `serde_json::to_string` -> websocket text frame。
- `close()` 具备幂等性：`AtomicBool is_closed` 防重入。
- 已关闭状态下发送直接返回 `ApiError::Stream("realtime websocket connection is closed")`。

#### A3. 入站消息流程（events）

1. 从 `rx_message` 取下一帧。
2. 文本帧：`parse_realtime_event` -> `update_active_transcript` -> 返回统一 `RealtimeEvent`。
3. close 帧：标记关闭并返回 `None`。
4. binary 帧：转成 `RealtimeEvent::Error("unexpected binary ...")`。
5. 底层读失败：返回 `ApiError::Stream("failed to read websocket message: ...")`。

#### A4. transcript 聚合与 handoff

- `append_transcript_delta` 按 role（`user`/`assistant`）连续拼接增量文本。
- v1 收到 `HandoffRequested` 时，会把累积的 `active_transcript` 移交给事件体。
- v2 不在 API 层填充 `active_transcript`（保持空，交由上游依据 `input_transcript` 处理）。

#### A5. core 侧编排耦合点（调用方）

`core/src/realtime_conversation.rs` 在此目录上层实现业务状态机：

1. 文本输入后（v2）触发 `response.create`，并处理“已有 active response”的冲突延迟发送。
2. 收到 v2 `InputAudioSpeechStarted` 时，根据最近 `AudioOut` 累积时长发 `conversation.item.truncate`。
3. handoff 期间：
   - v1 即时 append 输出。
   - v2 在 turn 完成时发送 function_call_output，再触发 `response.create`。

### B. 关键数据结构

1. `RealtimeSessionConfig`
   - `instructions`
   - `model`
   - `session_id`
   - `event_parser`
   - `session_mode`
2. `RealtimeOutboundMessage`（tagged enum）
   - `input_audio_buffer.append`
   - `conversation.item.create`
   - `conversation.handoff.append`
   - `session.update`
   - `response.create`
3. `RealtimeEvent`（来自 `codex-protocol`）
   - `SessionUpdated`
   - `Input/OutputTranscriptDelta`
   - `AudioOut`
   - `InputAudioSpeechStarted`
   - `ResponseCancelled`
   - `ConversationItemAdded/Done`
   - `HandoffRequested`
   - `Error`
4. `WsStream` + `WsCommand`
   - 把 socket 操作串行化到 pump task，避免外层并发 send/recv 直接竞争。

### C. 协议与事件映射要点

#### C1. v1 入站事件关键映射

- `conversation.output_audio.delta` -> `RealtimeEvent::AudioOut`
- `conversation.input_transcript.delta` -> `InputTranscriptDelta`
- `conversation.output_transcript.delta` -> `OutputTranscriptDelta`
- `conversation.handoff.requested` -> `HandoffRequested`

#### C2. v2 入站事件关键映射

- `response.output_audio.delta` / `response.audio.delta` -> `AudioOut`（缺失音频参数时默认 `24kHz/1ch`）
- `conversation.item.input_audio_transcription.delta|completed` -> `InputTranscriptDelta`
- `response.output_text.delta` / `response.output_audio_transcript.delta` -> `OutputTranscriptDelta`
- `conversation.item.done` 或 `response.done` 中 `function_call(name=codex)` -> `HandoffRequested`
- `response.cancelled` -> `ResponseCancelled`

#### C3. v1/v2 出站差异

- v1 handoff：`conversation.handoff.append`
- v2 handoff：`conversation.item.create` + `function_call_output`
- v2 conversational 含 `codex` function tool；transcription 不含 tool/output/instructions。

### D. 关键命令（调试/验证）

1. 目录与调用链检索：
   - `rg --files codex-rs/codex-api/src/endpoint/realtime_websocket`
   - `rg -n "RealtimeWebsocketClient|RealtimeSessionConfig|RealtimeEventParser" codex-rs -g '!target'`
2. 关键测试：
   - `cargo test -p codex-api --test realtime_websocket_e2e`
   - `cargo test -p codex-api realtime_websocket`
3. 上游联动验证：
   - `cargo test -p codex-core realtime_conversation`

## 关键代码路径与文件引用

### 1) 目标目录内

1. `codex-rs/codex-api/src/endpoint/realtime_websocket/mod.rs`
2. `codex-rs/codex-api/src/endpoint/realtime_websocket/methods.rs`
3. `codex-rs/codex-api/src/endpoint/realtime_websocket/methods_common.rs`
4. `codex-rs/codex-api/src/endpoint/realtime_websocket/methods_v1.rs`
5. `codex-rs/codex-api/src/endpoint/realtime_websocket/methods_v2.rs`
6. `codex-rs/codex-api/src/endpoint/realtime_websocket/protocol.rs`
7. `codex-rs/codex-api/src/endpoint/realtime_websocket/protocol_common.rs`
8. `codex-rs/codex-api/src/endpoint/realtime_websocket/protocol_v1.rs`
9. `codex-rs/codex-api/src/endpoint/realtime_websocket/protocol_v2.rs`

### 2) 直接调用方（上游）

1. `codex-rs/core/src/realtime_conversation.rs`
   - 会话准备：版本/模式/headers/API key
   - 输入任务：文本/音频/handoff 输出发送
   - v2 业务状态机：`response.create` 串行化、truncate、冲突恢复
2. `codex-rs/core/src/codex.rs`
   - 提交分发：`Op::RealtimeConversationStart/Audio/Text/Close`
   - 回灌：`maybe_mirror_event_text_to_realtime` 与 `handoff_complete`

### 3) 被调用方与公共依赖

1. `codex-rs/codex-api/src/provider.rs`（provider URL/header/retry）
2. `codex-rs/codex-api/src/error.rs`（`ApiError`）
3. `codex-rs/codex-client/src/custom_ca.rs`（websocket TLS 自定义 CA）
4. `codex-rs/protocol/src/protocol.rs`（`RealtimeEvent`、`RealtimeAudioFrame` 等共享协议类型）

### 4) 相关测试

1. 目录内大量单元 + 集成式测试：`codex-rs/codex-api/src/endpoint/realtime_websocket/methods.rs`（`#[cfg(test)]`）
2. crate 级 e2e：`codex-rs/codex-api/tests/realtime_websocket_e2e.rs`
3. 上游语义测试：
   - `codex-rs/core/src/realtime_conversation_tests.rs`
   - `codex-rs/core/src/codex_tests.rs`（realtime start/end developer message、dispatch span 等）

### 5) 配置、文档、脚本

1. 配置来源：`codex-rs/core/src/config/mod.rs`
   - `realtime.version`（v1/v2）
   - `realtime.type`（conversational/transcription）
   - `experimental_realtime_ws_base_url`
   - `experimental_realtime_ws_model`
   - `experimental_realtime_ws_backend_prompt`
   - `experimental_realtime_ws_startup_context`
2. realtime start/end 提示文案：
   - `codex-rs/protocol/src/prompts/realtime/realtime_start.md`
   - `codex-rs/protocol/src/prompts/realtime/realtime_end.md`
3. 用户文档：`docs/config.md` 当前仅明确了 `experimental_realtime_start_instructions`，未系统覆盖 websocket v1/v2/session mode 细节。
4. 脚本：仓库内无 realtime_websocket 专属维护脚本；主要依赖 Rust 测试验证。

## 依赖与外部交互

### 1) Rust crate 依赖

1. `tokio` / `futures`：异步任务与 channel、`select!`。
2. `tokio-tungstenite` + `tungstenite`：websocket 建连、帧收发、错误类型。
3. `http`：HeaderMap/HeaderValue。
4. `serde` + `serde_json`：消息编解码。
5. `url`：URL 解析与 query 拼接。
6. `codex-utils-rustls-provider` + `codex-client`：TLS provider 初始化与 custom CA 注入。

### 2) 与后端 Realtime API 的交互面

1. 连接端点：`/v1/realtime`（由 API URL 自动规范）。
2. 出站命令：
   - `session.update`
   - `input_audio_buffer.append`
   - `conversation.item.create`
   - `conversation.handoff.append`（仅 v1）
   - `response.create`（主要 v2 流程用）
3. 入站事件：支持 v1/v2 多版本别名事件，并对未知事件降级忽略。

### 3) 与 core 的契约

1. `connect` 成功后即已完成 `session.update`，上游无需二次初始化。
2. `next_event` 语义：
   - `Ok(Some(event))`：正常事件
   - `Ok(None)`：连接自然结束/close
   - `Err(ApiError::Stream(_))`：传输错误
3. v1/v2 解析差异对上游透明，但 `active_transcript` 在 v1/v2 行为不同（v1 更完整，v2 通常为空）。

## 风险、边界与改进建议

### 1) 结构风险

1. `methods.rs` 体量很大（约 1800+ 行），连接逻辑、协议测试、URL 规则测试都堆在单文件，维护成本高。
2. 协议演进风险：v2 事件别名持续变化时，当前“字符串匹配 + 手工字段抽取”需要持续跟进。

### 2) 行为边界

1. v1 transcription 被强制归一为 conversational（`normalized_session_mode`），这是兼容策略，不是能力等价。
2. v2 handoff transcript 主要依赖 `arguments` 提取（`prompt/input/text/query`），如果后端字段改名，可能退化为原始 JSON 字符串。
3. binary 入站被当作错误事件而非硬失败；若后端未来引入二进制帧协议，需要重新设计。
4. `websocket_url_from_api_url` 会追加 query 参数，若外部反向代理对参数顺序/重复敏感，存在兼容隐患。

### 3) 测试与文档缺口

1. 目录内测试覆盖充分，但“core 状态机 + api 目录”的跨 crate 端到端场景仍主要靠分散测试组合。
2. `docs/config.md` 对 realtime websocket 配置项说明不足（仅部分字段有说明），排障门槛较高。

### 4) 可执行改进建议

1. 拆分 `methods.rs`：
   - `connection.rs`（连接与 URL/header）
   - `writer.rs`（出站命令）
   - `events.rs`（入站消费与 transcript）
   - `tests/*`（按主题分文件）
2. 为 v2 事件解析补充“schema/契约测试样例集”，特别是 `function_call` 提取链路。
3. 在 `docs/config.md` 增加 realtime websocket 配置专章：版本、session type、实验字段及默认行为。
4. 为 URL 规范化逻辑增加更多代理场景测试（path 尾斜杠、已有 query、model/intent 冲突）。

