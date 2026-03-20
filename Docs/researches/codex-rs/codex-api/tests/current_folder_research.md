# DIR `codex-rs/codex-api/tests` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/codex-api/tests`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 目录文件：`clients.rs`、`sse_end_to_end.rs`、`models_integration.rs`、`realtime_websocket_e2e.rs`

## 场景与职责

`codex-rs/codex-api/tests` 是 `codex-api` crate 的集成测试目录，职责不是验证单个私有函数，而是从 crate 公共 API 出发，验证“请求构建 + 传输抽象 + 协议解析”的端到端行为是否符合上游 `codex-core` 依赖的契约。

该目录覆盖四类关键场景：

1. Responses HTTP 流式请求行为（路径、鉴权头、重试、Azure 兼容逻辑）。
2. SSE 事件流解析行为（`response.output_item.done` 和 `response.completed` 的事件落地）。
3. Models API 的真实 HTTP 集成行为（`GET /models`、响应体解析、路径拼接）。
4. Realtime websocket 会话行为（首包 `session.update`、音频帧发送、事件解析、断开/未知事件、v2 handoff 解析）。

它在代码层的定位是“公开 client 行为回归线”，与 `src/` 内的单元测试形成互补：

- `src/endpoint/*.rs` 单测偏局部函数正确性。
- `tests/*.rs` 偏跨模块组合正确性（`Provider`、`EndpointSession`、`AuthProvider`、SSE/Realtime parser、transport trait 的组合）。

## 功能点目的

### 1. `clients.rs`：验证 ResponsesClient 的请求构造契约

对应测试点：

1. `responses_client_uses_responses_path`（`clients.rs:198`）
- 目的：确保 `ResponsesClient::stream()` 发往 `/responses`，防止路径回归。

2. `streaming_client_adds_auth_headers`（`clients.rs:214`）
- 目的：验证 `AuthProvider` 的 `bearer_token/account_id` 能被注入到 `Authorization` 与 `ChatGPT-Account-ID`，同时 `Accept: text/event-stream` 被正确设置。

3. `streaming_client_retries_on_transport_error`（`clients.rs:250`）
- 目的：验证 `Provider.retry.max_attempts` 能驱动 stream 重试，并通过 flaky transport 证明第一次网络失败后会重试成功。

4. `azure_default_store_attaches_ids_and_headers`（`clients.rs:287`）
- 目的：验证 Azure 端点下 `store=true` 时 `attach_item_ids` 生效，且 conversation/subagent/extra headers 都被正确拼装。

### 2. `sse_end_to_end.rs`：验证 SSE 到 ResponseEvent 的最小闭环

对应测试点：

1. `responses_stream_parses_items_and_completed_end_to_end`（`sse_end_to_end.rs:94`）
- 目的：从字节流喂入 SSE 文本，验证最终事件序列包含 2 个 `OutputItemDone` + 1 个 `Completed`，并且 `Completed.response_id` 正确。
- 价值：保障 `ResponsesClient -> spawn_response_stream -> process_sse -> process_responses_event` 主链路没有协议断层。

### 3. `models_integration.rs`：验证 ModelsClient 真实 HTTP 调用行为

对应测试点：

1. `models_client_hits_models_endpoint`（`models_integration.rs:49`）
- 目的：使用 `wiremock` 启动真实 HTTP server，验证：
  - 请求方法是 `GET`。
  - 路径是 `/api/codex/models`（base_url 拼接生效）。
  - response body 被正确解析为 `Vec<ModelInfo>`。

### 4. `realtime_websocket_e2e.rs`：验证 realtime websocket 会话状态机

对应测试点：

1. `realtime_ws_e2e_session_create_and_event_flow`（`realtime_websocket_e2e.rs:73`）
- 目的：验证 connect 后客户端先发 `session.update`，随后可以发 `input_audio_buffer.append`，并解析服务端音频 delta 为 `RealtimeEvent::AudioOut`。

2. `realtime_ws_e2e_send_while_next_event_waits`（`realtime_websocket_e2e.rs:198`）
- 目的：验证 `send_audio_frame` 不会被并发 `next_event` 阻塞，保障读写并发可用性。

3. `realtime_ws_e2e_disconnected_emitted_once`（`realtime_websocket_e2e.rs:283`）
- 目的：验证 websocket close 后 `next_event()` 返回 `None` 并保持幂等。

4. `realtime_ws_e2e_ignores_unknown_text_events`（`realtime_websocket_e2e.rs:325`）
- 目的：验证 parser 对不支持事件类型（如 `response.created`）采取忽略策略，而不会打断后续可识别事件。

5. `realtime_ws_e2e_realtime_v2_parser_emits_handoff_requested`（`realtime_websocket_e2e.rs:395`）
- 目的：验证 v2 parser 能把 `conversation.item.done` 中 `function_call(name=codex)` 提取为 `RealtimeEvent::HandoffRequested`，并解析 `arguments` 中 prompt。

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. 关键流程

1. Responses stream 请求流程（由 `clients.rs` 间接覆盖）
- `ResponsesClient::stream_request`（`src/endpoint/responses.rs:69`）序列化 `ResponsesApiRequest`。
- Azure + `store=true` 时调用 `attach_item_ids`（`src/endpoint/responses.rs:85`，`src/requests/responses.rs:11`）。
- 会话头构建：`build_conversation_headers` + `subagent_header`（`src/endpoint/responses.rs:92-94`，`src/requests/headers.rs:5,13`）。
- 通过 `EndpointSession::stream_with` 执行请求（`src/endpoint/session.rs:112`），底层由 `run_with_request_telemetry` + `run_with_retry` 驱动重试（`src/telemetry.rs:68`，`codex-client/src/retry.rs:49`）。

2. SSE 解析流程（由 `sse_end_to_end.rs` 间接覆盖）
- `spawn_response_stream`（`src/sse/responses.rs:57`）先发 header-derived 事件（model/rate_limits/etag/reasoning）。
- `process_sse`（`src/sse/responses.rs:357`）对 eventsource 帧做 JSON 反序列化。
- `process_responses_event`（`src/sse/responses.rs:236`）将 `response.output_item.done`、`response.completed` 等映射到 `ResponseEvent`。

3. models 请求流程（由 `models_integration.rs` 覆盖）
- `ModelsClient::list_models`（`src/endpoint/models.rs:40`）走 `GET /models`。
- `append_client_version_query`（`src/endpoint/models.rs:35`）附加 `client_version` query。
- 解析 `ModelsResponse` 并返回 `(models, etag)`。

4. realtime websocket 流程（由 `realtime_websocket_e2e.rs` 覆盖）
- `RealtimeWebsocketClient::connect`（`src/endpoint/realtime_websocket/methods.rs:452`）构造 ws URL、合并 headers、完成握手。
- 建连后立即发送 `session.update`。
- `RealtimeWebsocketEvents::next_event`（`methods.rs:350`）循环读取文本帧，调用 `parse_realtime_event`（`protocol.rs:215`）。
- V1/V2 parser 分派：`protocol_v1.rs:11` 与 `protocol_v2.rs:19`。

### B. 关键数据结构

1. 测试桩 transport
- `RecordingTransport`（`clients.rs:60`）：记录请求对象，便于断言 header/body/path。
- `FlakyTransport`（`clients.rs:140`）：人工制造首次网络失败，验证重试。
- `FixtureSseTransport`（`sse_end_to_end.rs:23`）：把预构造 SSE 文本作为字节流返回。

2. API 输入/输出模型
- `ResponsesApiRequest`（`src/common.rs:154`）：Responses 请求体。
- `ResponsesOptions`（`src/endpoint/responses.rs:32`）：conversation/session headers、compression、turn_state。
- `ResponseEvent`（`src/common.rs:66`）：流式事件统一抽象。
- `RealtimeSessionConfig`（`src/endpoint/realtime_websocket/protocol.rs:24`）：realtime 建连参数。

3. Provider/Retry
- `Provider`（`src/provider.rs:43`）包含 base_url、query、headers、retry、idle_timeout。
- `RetryConfig::to_policy`（`src/provider.rs:25`）映射到 `codex-client::RetryPolicy`。

### C. 协议与命令

1. 关键协议路径
- Responses: `POST /responses`。
- Models: `GET /models?client_version=...`。
- Realtime WS: 通常规范化到 `/v1/realtime`（`methods.rs:547,599`）。

2. 关键头部/字段
- 认证：`Authorization`、`ChatGPT-Account-ID`。
- 会话：`session_id`、`x-openai-subagent`、`x-client-request-id`。
- SSE：`Accept: text/event-stream`。

3. 目录常用验证命令
- `cargo test -p codex-api --test clients`
- `cargo test -p codex-api --test sse_end_to_end`
- `cargo test -p codex-api --test models_integration`
- `cargo test -p codex-api --test realtime_websocket_e2e`
- 全集成：`cargo test -p codex-api`

## 关键代码路径与文件引用

### 1) 目标目录（被研究对象）

1. `/home/sansha/Github/codex/codex-rs/codex-api/tests/clients.rs`
2. `/home/sansha/Github/codex/codex-rs/codex-api/tests/sse_end_to_end.rs`
3. `/home/sansha/Github/codex/codex-rs/codex-api/tests/models_integration.rs`
4. `/home/sansha/Github/codex/codex-rs/codex-api/tests/realtime_websocket_e2e.rs`

### 2) 被调用实现（测试依赖的核心模块）

1. Responses client 与 session
- `/home/sansha/Github/codex/codex-rs/codex-api/src/endpoint/responses.rs`
- `/home/sansha/Github/codex/codex-rs/codex-api/src/endpoint/session.rs`
- `/home/sansha/Github/codex/codex-rs/codex-api/src/requests/headers.rs`
- `/home/sansha/Github/codex/codex-rs/codex-api/src/requests/responses.rs`

2. SSE 解析
- `/home/sansha/Github/codex/codex-rs/codex-api/src/sse/responses.rs`
- `/home/sansha/Github/codex/codex-rs/codex-api/src/common.rs`

3. Models client
- `/home/sansha/Github/codex/codex-rs/codex-api/src/endpoint/models.rs`

4. Realtime websocket
- `/home/sansha/Github/codex/codex-rs/codex-api/src/endpoint/realtime_websocket/methods.rs`
- `/home/sansha/Github/codex/codex-rs/codex-api/src/endpoint/realtime_websocket/methods_common.rs`
- `/home/sansha/Github/codex/codex-rs/codex-api/src/endpoint/realtime_websocket/protocol.rs`
- `/home/sansha/Github/codex/codex-rs/codex-api/src/endpoint/realtime_websocket/protocol_v1.rs`
- `/home/sansha/Github/codex/codex-rs/codex-api/src/endpoint/realtime_websocket/protocol_v2.rs`

### 3) 调用方上下文（谁依赖这些契约）

1. Responses 主调用
- `/home/sansha/Github/codex/codex-rs/core/src/client.rs:1039`
- `/home/sansha/Github/codex/codex-rs/core/src/client.rs:1049`
- `/home/sansha/Github/codex/codex-rs/core/src/client.rs:755`

2. fixture 模式调用
- `/home/sansha/Github/codex/codex-rs/core/src/client.rs:1010`

3. Realtime 主调用
- `/home/sansha/Github/codex/codex-rs/core/src/realtime_conversation.rs:173`

4. Models 拉取调用
- `/home/sansha/Github/codex/codex-rs/core/src/models_manager/manager.rs:449`
- `/home/sansha/Github/codex/codex-rs/core/src/models_manager/manager.rs:455`

### 4) 配置、文档、脚本

1. crate 文档
- `/home/sansha/Github/codex/codex-rs/codex-api/README.md`

2. crate 依赖与测试依赖
- `/home/sansha/Github/codex/codex-rs/codex-api/Cargo.toml`

3. Bazel 入口
- `/home/sansha/Github/codex/codex-rs/codex-api/BUILD.bazel`

4. 研究流程脚本
- `/home/sansha/Github/codex/.ops/generate_daily_research_todo.sh`

5. 进度清单
- `/home/sansha/Github/codex/Docs/researches/blueprint_checklist.md:188`

## 依赖与外部交互

### 1. 内部代码依赖

1. `codex-client`
- 提供 `HttpTransport` trait、`ReqwestTransport`、`StreamResponse`、`TransportError`、`RetryPolicy` 与 `run_with_retry`。
- 测试通过 mock transport 和真实 reqwest transport 两种方式覆盖。

2. `codex-protocol`
- 提供 `ResponseItem`、`RealtimeEvent`、`ModelInfo` 等 wire/domain 共享结构。
- `models_integration.rs` 使用完整 `ModelInfo` 构造，防止模型 schema 漏字段引起反序列化回归。

3. `tokio` / `futures` / `tokio-tungstenite`
- 异步运行时与 websocket 客户端/服务端实现。
- realtime e2e 通过本地 `TcpListener` + `accept_async` 形成闭环。

4. `wiremock`
- `models_integration.rs` 的 HTTP server mock，验证真实 URL/method/body 交互。

### 2. 外部协议交互

1. HTTP
- `models_integration.rs` 真实发起 HTTP 请求到本地 mock server。

2. WebSocket
- `realtime_websocket_e2e.rs` 真实建立 websocket 握手，交换 JSON 文本帧。

3. SSE
- `clients.rs` 与 `sse_end_to_end.rs` 通过 `StreamResponse.bytes` 模拟 SSE 字节流，触发真实 parser。

### 3. 配置与环境边界

1. 测试普遍使用自建 `Provider`：
- `base_url` 指向 `example.com` 或本地 mock server。
- `retry.max_attempts` 在用例里显式设置，避免隐式行为。

2. Auth 由本地 `AuthProvider` stub 提供：
- `NoAuth`、`StaticAuth`、`DummyAuth`，不依赖真实凭据或环境变量。

3. 目录没有独立脚本；执行依赖 workspace 的 `cargo test -p codex-api` 流程。

## 风险、边界与改进建议

### 风险与边界

1. Responses 覆盖偏“正向路径”
- `sse_end_to_end.rs` 仅验证成功流，没有覆盖 `response.failed`、idle timeout、stream 提前关闭等失败语义；这些更多在 `src/sse/responses.rs` 单测。

2. `clients.rs` 对 header 行为覆盖有限
- 已覆盖 `Authorization`、`ChatGPT-Account-ID`、`Accept`、`session_id`、`x-openai-subagent`，但尚未覆盖 `x-client-request-id`、`x-codex-turn-state`、compression=Zstd 分支。

3. realtime e2e 未覆盖 TLS 与复杂 query/header 合并
- 用例全是本地 `ws://`，没有覆盖 `wss`、custom CA、provider/default/extra header precedence。

4. models 集成测试未断言 `client_version` query
- 当前只断言 path，不断言 query；query 行为在 `src/endpoint/models.rs` 单测覆盖，但目录级集成测试未闭环验证。

5. 并发压力覆盖不足
- realtime 的并发验证仅 1 个 `send_audio_frame` 与 1 次 `next_event` 的 join，未覆盖连续高频音频帧下的 channel/backpressure 行为。

### 改进建议

1. 在 `tests/` 增加 Responses 失败流用例
- 目标：覆盖 `response.failed -> ApiError::{ContextWindowExceeded,Retryable,...}` 的目录级行为，减少仅依赖模块单测的风险。

2. 给 `models_integration.rs` 增加 query 断言
- 目标：在 `received_requests()[0].url.query()` 断言 `client_version=...`，与 `ModelsClient::append_client_version_query` 形成双层保障。

3. 为 `clients.rs` 增加 compression 与额外头冲突场景
- 目标：覆盖 `Compression::Zstd` 分支，以及 provider/default/extra headers 冲突时的最终优先级。

4. 扩展 realtime e2e 到 session_mode 与 URL 规范化边界
- 目标：补 `RealtimeSessionMode::Transcription`、`/v1` -> `/v1/realtime`、query params 合并、`x-session-id` 头校验。

5. 新增“跨 transport 行为对齐”测试
- 目标：对比 Responses HTTP(SSE) 与 Responses WebSocket 在 `ResponseEvent` 序列上的一致性，避免未来语义漂移。
