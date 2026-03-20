# DIR `codex-rs/codex-api/src/endpoint` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/codex-api/src/endpoint`
- 目标类型：`DIR`
- 研究日期：`2026-03-20`
- 关联 crate：`codex-api`
- 上游主要调用方：`codex-rs/core/src/client.rs`、`codex-rs/core/src/models_manager/manager.rs`、`codex-rs/core/src/realtime_conversation.rs`

## 场景与职责

`endpoint` 目录是 `codex-api` 的“端点适配层”：

1. 把上层的 typed 输入（例如 `ResponsesApiRequest`、`CompactionInput`、`MemorySummarizeInput`）映射到具体 API 路径与传输协议（HTTP/SSE/WebSocket）。
2. 复用统一的会话执行器 `EndpointSession`（认证头注入、provider 配置、retry + request telemetry）。
3. 负责将后端流式事件转换为统一事件流（`ResponseStream`、`RealtimeEvent`）。
4. 提供 endpoint 级能力分层：
   - `responses.rs`：Responses HTTP + SSE
   - `responses_websocket.rs`：Responses WebSocket
   - `realtime_websocket/*`：Realtime 会话（v1/v2）
   - `compact.rs`：历史压缩
   - `memories.rs`：trace summarize
   - `models.rs`：远端模型目录
5. 对上层隐藏 wire 细节（URL 拼接、header 约定、协议版本差异、事件容错解析）。

边界上，本目录**不负责**：

1. 业务策略（例如 websocket 失败后是否会话级降级，交由 `core::ModelClient`）。
2. 认证刷新（401 后 token recovery 在 `core` 层）。
3. UI/交互语义（TUI/App-server 仅消费 `core` 事件）。

## 功能点目的

### 1) `EndpointSession`：统一请求执行骨架

目的：减少每个 endpoint 重复处理“构造请求 + 注入认证 + 重试 + telemetry”的样板代码。

- `execute/execute_with`：用于 unary HTTP。
- `stream_with`：用于 SSE 类流式 HTTP。
- 依赖 `Provider` 的 retry 策略，统一调用 `run_with_request_telemetry`。

### 2) `ResponsesClient`（HTTP）

目的：通过 `POST /responses` 获取 SSE 事件流。

- 处理会话头：`session_id`、`x-client-request-id`、`x-openai-subagent`。
- 处理 Azure 兼容：当 `request.store=true` 且 provider 为 Azure 时，调用 `attach_item_ids` 保留输入 item id。
- 设置 `Accept: text/event-stream` 并可切换压缩（`None`/`Zstd`）。

### 3) `ResponsesWebsocketClient/Connection`

目的：通过 WebSocket 承载 Responses 请求，支持连接复用与流式响应。

- 连接阶段读取 server header 元数据：
  - `x-codex-turn-state`
  - `x-models-etag`
  - `x-reasoning-included`
  - `openai-model`
- 请求阶段发送 `response.create`（`ResponsesWsRequest`），解析文本帧到 `ResponseEvent`。
- 对 wrapped websocket error 做专门映射（包括 `websocket_connection_limit_reached` => `ApiError::Retryable`）。

### 4) `realtime_websocket`（会话型语音/转录）

目的：封装 realtime v1/v2 协议差异，向上暴露一致 API。

- `RealtimeWebsocketClient::connect` 建连后自动发送 `session.update`。
- `RealtimeWebsocketWriter` 负责发音频、用户文本、handoff 输出、`response.create`。
- `RealtimeWebsocketEvents` 负责消费并解析事件，维护 active transcript 聚合状态。
- 支持 `RealtimeEventParser::{V1, RealtimeV2}` 与 `RealtimeSessionMode::{Conversational, Transcription}`。

### 5) `CompactClient`

目的：调用 `POST /responses/compact`，返回新的 `Vec<ResponseItem>` 历史。

### 6) `MemoriesClient`

目的：调用 `POST /memories/trace_summarize`，返回 `Vec<MemorySummarizeOutput>`。

- 输入结构 `MemorySummarizeInput.raw_memories` 在 wire 上重命名为 `traces`，保持兼容。

### 7) `ModelsClient`

目的：调用 `GET /models?client_version=...`，返回模型列表与可选 `ETag`。

- `core` 用该 `ETag` 做模型缓存刷新判定。

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. 关键流程

#### A1. Responses HTTP + SSE 流程

1. `ResponsesClient::stream_request` 序列化 `ResponsesApiRequest`。
2. 根据上下文拼装 headers（conversation/subagent/额外头）。
3. `EndpointSession::stream_with` 发起 HTTP stream。
4. `spawn_response_stream` 先发 header-derived 事件（`ServerModel`、`RateLimits`、`ModelsEtag`、`ServerReasoningIncluded`）。
5. `process_sse` 循环按 idle timeout 轮询、解析 `ResponsesStreamEvent`，经 `process_responses_event` 变为 `ResponseEvent`。
6. 收到 `response.completed` 正常结束；若断流未完成，返回 `stream closed before response.completed`。

#### A2. Responses WebSocket 流程

1. `ResponsesWebsocketClient::connect`：
   - 通过 `Provider::websocket_url_for_path("responses")` 构造 ws URL。
   - 合并 provider/extra/default headers。
   - 注入认证头。
2. `connect_websocket`：使用 `connect_async_tls_with_config`，并通过 `maybe_build_rustls_client_config_with_custom_ca` 支持自定义 CA。
3. `ResponsesWebsocketConnection::stream_request`：
   - 序列化请求体并发送。
   - 循环读取文本帧；优先解析 wrapped error，再解析 `ResponsesStreamEvent`。
   - `codex.rate_limits` 走 `parse_rate_limit_event`。
   - 转为 `ResponseEvent` 并在 `Completed` 时结束。

#### A3. Realtime WebSocket 流程

1. `websocket_url_from_api_url` 规范化 URL：
   - 自动将 `http/https` 转 `ws/wss`。
   - 自动补 `/v1/realtime` 路径。
   - 追加 `model` 与 provider query params。
   - v1 添加 `intent=quicksilver`，v2 不添加 intent。
2. 建连后自动发送 `session.update`（由 `methods_common + methods_v1/v2` 生成 payload）。
3. 写路径：`send_audio_frame` / `send_conversation_item_create` / `send_conversation_handoff_append` / `send_response_create`。
4. 读路径：`next_event` 从 ws pump 取帧，调用 `parse_realtime_event`（分发到 v1/v2 parser）。
5. transcript 聚合：连续 delta 同角色拼接；v1 handoff 时回填 `active_transcript`。

#### A4. Unary 端点流程

- `compact_input`：`CompactionInput` -> JSON -> `POST /responses/compact` -> `output: Vec<ResponseItem>`。
- `summarize_input`：`MemorySummarizeInput` -> JSON -> `POST /memories/trace_summarize` -> `output: Vec<MemorySummarizeOutput>`。
- `list_models`：`GET /models?client_version=...` -> `ModelsResponse.models + ETag`。

### B. 关键数据结构

1. 公共请求与事件（来自 `common.rs`）：
   - `ResponsesApiRequest`
   - `ResponseCreateWsRequest`
   - `ResponsesWsRequest`
   - `ResponseEvent` / `ResponseStream`
2. Endpoint 专属：
   - `ResponsesOptions`
   - `RealtimeSessionConfig`
   - `RealtimeOutboundMessage`（内部序列化体）
3. 错误模型：`ApiError`（`Transport`/`Stream`/`Retryable`/`InvalidRequest`/`ServerOverloaded` 等）。

### C. 协议与头部约定

1. 路径约定：
   - `POST /responses`
   - `POST /responses/compact`
   - `POST /memories/trace_summarize`
   - `GET /models`
   - `WS /responses`
   - `WS /v1/realtime`
2. 常用头部：
   - `Authorization`、`ChatGPT-Account-ID`
   - `session_id`、`x-client-request-id`
   - `x-openai-subagent`
   - `x-codex-turn-state`
   - `X-Models-Etag`
   - `x-reasoning-included`
   - `openai-model`
3. 特殊事件：`codex.rate_limits`。

### D. 调研/验证命令

1. 快速定位模块与调用方：
   - `rg --files codex-rs/codex-api/src/endpoint`
   - `rg -n "ResponsesClient|ResponsesWebsocketClient|RealtimeWebsocketClient|ModelsClient|MemoriesClient|CompactClient" codex-rs -S`
2. 关键测试：
   - `cargo test -p codex-api`
   - `cargo test -p codex-core --test responses_headers`
   - `cargo test -p codex-core --test models_etag_responses`
3. 模拟脚本：
   - `scripts/mock_responses_websocket_server.py`（本地模拟 `/v1/responses` websocket）。

## 关键代码路径与文件引用

### 1) endpoint 目录内

1. 目录导出：`codex-rs/codex-api/src/endpoint/mod.rs`
2. 通用执行器：`codex-rs/codex-api/src/endpoint/session.rs`
3. Responses HTTP：`codex-rs/codex-api/src/endpoint/responses.rs`
4. Responses WebSocket：`codex-rs/codex-api/src/endpoint/responses_websocket.rs`
5. Realtime 汇总导出：`codex-rs/codex-api/src/endpoint/realtime_websocket/mod.rs`
6. Realtime 连接与收发：`codex-rs/codex-api/src/endpoint/realtime_websocket/methods.rs`
7. Realtime 协议模型：`codex-rs/codex-api/src/endpoint/realtime_websocket/protocol.rs`
8. Realtime v1/v2 适配：
   - `codex-rs/codex-api/src/endpoint/realtime_websocket/methods_v1.rs`
   - `codex-rs/codex-api/src/endpoint/realtime_websocket/methods_v2.rs`
   - `codex-rs/codex-api/src/endpoint/realtime_websocket/protocol_v1.rs`
   - `codex-rs/codex-api/src/endpoint/realtime_websocket/protocol_v2.rs`
9. unary endpoints：
   - `codex-rs/codex-api/src/endpoint/compact.rs`
   - `codex-rs/codex-api/src/endpoint/memories.rs`
   - `codex-rs/codex-api/src/endpoint/models.rs`

### 2) endpoint 的直接上下文依赖（被调用方）

1. 请求模型/事件模型：`codex-rs/codex-api/src/common.rs`
2. provider 与 URL/retry：`codex-rs/codex-api/src/provider.rs`
3. 认证：`codex-rs/codex-api/src/auth.rs`
4. 请求头 helper：`codex-rs/codex-api/src/requests/headers.rs`
5. Azure item-id 兼容：`codex-rs/codex-api/src/requests/responses.rs`
6. SSE 解析：`codex-rs/codex-api/src/sse/responses.rs`
7. 限额解析：`codex-rs/codex-api/src/rate_limits.rs`
8. telemetry glue：`codex-rs/codex-api/src/telemetry.rs`

### 3) 主要调用方（上游）

1. 统一入口：`codex-rs/core/src/client.rs`
   - stream 路由（ws/http fallback）
   - compact、memory summarize、responses websocket prewarm
   - turn-state/header/client metadata 处理
2. 远端模型刷新：`codex-rs/core/src/models_manager/manager.rs`
   - 调用 `ModelsClient::list_models`
3. 实时会话编排：`codex-rs/core/src/realtime_conversation.rs`
   - 调用 `RealtimeWebsocketClient` 并消费 `RealtimeEvent`
4. 错误桥接：`codex-rs/core/src/api_bridge.rs`
   - `ApiError -> CodexErr` 映射

### 4) 测试与文档/脚本

1. crate 级测试：
   - `codex-rs/codex-api/tests/clients.rs`
   - `codex-rs/codex-api/tests/sse_end_to_end.rs`
   - `codex-rs/codex-api/tests/models_integration.rs`
   - `codex-rs/codex-api/tests/realtime_websocket_e2e.rs`
2. core 集成测试（验证 endpoint 契约）：
   - `codex-rs/core/tests/responses_headers.rs`
   - `codex-rs/core/tests/suite/agent_websocket.rs`
   - `codex-rs/core/tests/suite/models_etag_responses.rs`
   - `codex-rs/core/tests/common/responses.rs`
3. 文档与说明：
   - `codex-rs/codex-api/README.md`
   - `docs/config.md`（custom CA、realtime 相关配置说明）
4. 辅助脚本：
   - `scripts/mock_responses_websocket_server.py`

## 依赖与外部交互

### 1) 内部 crate 依赖

1. `codex-client`：HTTP/stream transport、retry policy、transport error、custom CA TLS builder。
2. `codex-protocol`：`ResponseItem`、`RealtimeEvent`、`ModelInfo` 等共享协议类型。
3. `codex-utils-rustls-provider`：确保 rustls crypto provider 初始化。

### 2) 外部库/协议依赖

1. `tokio-tungstenite` / `tungstenite`：WebSocket 连接与帧处理。
2. `eventsource-stream`：SSE 帧解析。
3. `serde/serde_json`：请求与事件序列化/反序列化。
4. `http`：HeaderMap/状态码。
5. `url`：URL 规范化与 query 拼接。

### 3) 网络交互模型

1. HTTP 请求：通过 `Provider.base_url + path + query_params` 构建。
2. WebSocket：
   - Responses 使用 `/responses`。
   - Realtime 使用 `/v1/realtime`（自动规范路径/协议）。
3. TLS/证书：遵循 `CODEX_CA_CERTIFICATE` / `SSL_CERT_FILE`（通过 shared custom CA path）。

### 4) 配置与行为耦合

1. `ModelProviderInfo.supports_websockets` 决定 `core` 是否优先走 Responses WS。
2. `Provider.retry` 与 `stream_idle_timeout` 控制 endpoint 重试和流超时。
3. realtime 版本/模式由 `core.config.realtime` 决定，并映射到 `RealtimeEventParser`/`RealtimeSessionMode`。

## 风险、边界与改进建议

### 风险与边界

1. **双 websocket pump 实现重复**：`responses_websocket.rs` 与 `realtime_websocket/methods.rs` 都维护了类似 `WsStream + command channel + read loop`，长期易产生修复漂移。
2. **协议容错偏“静默忽略”**：多个 parser 对未知/无法解析事件只 `debug + continue`，在后端协议变更时可能造成“功能悄然退化”。
3. **header 语义散落**：`x-codex-turn-state`、`openai-model`、`x-models-etag` 在 SSE 与 WS 两条路径分别处理，维护成本高。
4. **incremental websocket 请求依赖上轮状态**：`core` 依赖 `response_id + items_added` 计算 delta，若事件顺序或 item 提取异常，可能导致回退成全量请求或行为不一致。
5. **realtime v1/v2 差异扩展风险**：v2 handoff/tool 语义在多个文件分散（methods/protocol/parser），未来新增事件类型时改动面较大。
6. **`responses_websocket.rs` 模块规模偏大**（800+ 行）：连接、错误映射、流处理、测试集中在单文件，阅读与回归成本高。

### 改进建议

1. **抽取共享 websocket pump 组件**：把 `WsStream` 命令/读写泵封装为可复用内部模块，减少 Responses/Realtime 两套维护。
2. **统一 header 元数据适配层**：将 `ServerModel/ModelsEtag/ServerReasoningIncluded/turn-state` 提取为共享 helper，保持 SSE/WS 一致行为。
3. **提升协议演进可观测性**：对“未知 type”增加可采样计数器或 warn 级别阈值日志，避免 silent drop。
4. **拆分大文件**：优先把 `responses_websocket.rs` 的 error 映射、连接逻辑、stream loop 拆到子模块。
5. **补强兼容性测试矩阵**：增加“同一语义在 SSE/WS 输出一致”的契约测试，特别是 `ServerModel`/`RateLimits`/`Completed` 终止语义。
6. **文档同步**：在 `codex-rs/codex-api/README.md` 增补 Responses WS 与 Realtime 的 header/event 约定摘要，降低调用方误用成本。
