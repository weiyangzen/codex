# DIR `codex-rs/codex-api/src` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/codex-api/src`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 关联 crate：`codex-api`（crate 名：`codex_api`）
- 目录子模块：`auth/common/error/provider/rate_limits/requests/sse/telemetry/endpoint/*`

## 场景与职责

`codex-rs/codex-api/src` 是 Codex Rust 工作区里“API 线协议实现层”的主体代码目录，定位在：

1. 上游业务编排层：`codex-core`（模型调用、会话状态、401 恢复、fallback 策略）。
2. 下游传输层：`codex-client`（HTTP/stream transport、重试框架、错误基础类型）。

该目录承担的核心职责：

1. 把上游的 typed 请求模型（如 `ResponsesApiRequest`、`CompactionInput`）编码成具体 wire 请求（HTTP/SSE/WS）。
2. 统一注入 provider 级配置（`base_url/query_params/default headers/retry/timeout`）和认证头。
3. 解析流式事件（SSE 与 WebSocket）为统一 `ResponseEvent`/`RealtimeEvent`。
4. 将底层传输错误和 API 错误归一成 `ApiError`，供上层继续策略决策。
5. 提供可观测钩子（request/sse/ws telemetry traits），将采集点暴露给 `codex-core`/`codex-otel`。

边界上，`codex-api` 不负责：

1. 认证刷新逻辑（由 `core` 的 `AuthManager` 处理）。
2. 会话策略（例如 websocket 是否降级、跨 turn 状态管理策略由 `core` 决策）。
3. UI 与业务语义解释（由 `tui`、`core` 处理）。

## 功能点目的

### 1. Provider 与请求构建

目的：把不同模型提供方（OpenAI/Azure/自定义 proxy）的连接配置收敛成统一 `Provider`，避免调用方重复拼 URL/headers/retry。

关键能力：

1. `Provider::url_for_path` 合并 `base_url + path + query_params`。
2. `Provider::websocket_url_for_path` 负责 `http/https -> ws/wss`。
3. `is_azure_responses_wire_base_url` 判定 Azure 兼容端点，影响 `/responses` 的请求行为（如 `store=true` 下保留 item id）。

### 2. 认证头注入

目的：统一认证写法，保证每个 endpoint 都使用一致的头部注入规则。

关键能力：

1. `AuthProvider` trait 暴露 `bearer_token/account_id`。
2. `add_auth_headers_to_header_map` 注入 `Authorization` 与 `ChatGPT-Account-ID`。

### 3. Responses API（HTTP + SSE）

目的：提供稳定的流式 Responses 客户端，将 SSE 消息转换成 typed 事件并保留 server-side 头部信息（模型、rate limits、etag、reasoning included）。

关键能力：

1. `ResponsesClient::stream_request` 组装 headers（conversation/subagent/extra headers）。
2. `spawn_response_stream/process_sse` 解析 `response.*` 事件并输出 `ResponseEvent`。
3. `process_responses_event` 将 `response.failed` 分类为可重试/不可重试错误（context window、quota、invalid request、server overloaded 等）。

### 4. Responses API（WebSocket）

目的：为 `core` 提供响应级别 websocket 传输，支持连接复用、每请求流式输出、wrapped error 解包和 metadata 头部提取。

关键能力：

1. 连接阶段：`ResponsesWebsocketClient::connect`。
2. 请求阶段：`ResponsesWebsocketConnection::stream_request`。
3. 消息泵：`run_websocket_response_stream`（发送 `response.create`，接收 JSON 事件，复用 `process_responses_event`）。
4. 专项错误映射：`websocket_connection_limit_reached` 映射为 `ApiError::Retryable`。

### 5. Realtime WebSocket（V1/V2）

目的：统一实时会话（语音/转录/handoff）协议适配，屏蔽 v1(quicksilver) 与 v2(realtime/transcription) 差异。

关键能力：

1. `RealtimeWebsocketClient` 负责 URL 规范化（补 `/v1/realtime`、intent/model/query 合并）。
2. `RealtimeWebsocketWriter` 发送 audio/text/handoff/session.update。
3. `RealtimeWebsocketEvents` 读取并解析事件，同时聚合 active transcript（v1 handoff 会回填 active_transcript）。
4. `protocol_v1/protocol_v2` 实现事件级兼容解析。

### 6. Unary 端点

目的：为上层提供 compact、memories summarize、models list 的 typed unary 客户端。

关键能力：

1. `CompactClient` -> `POST /responses/compact`。
2. `MemoriesClient` -> `POST /memories/trace_summarize`（`raw_memories` 以 `traces` 上线）。
3. `ModelsClient` -> `GET /models?client_version=...`（读取 ETag）。

### 7. 限额与 telemetry

目的：把 rate-limit 信息和 timing 采集在 API 层标准化，给上游决策与观测系统直接消费。

关键能力：

1. `rate_limits.rs` 支持 header 族与 `codex.rate_limits` 事件解析。
2. `telemetry.rs` 的 `run_with_request_telemetry` 把 retry 每次尝试都发给 telemetry。
3. `SseTelemetry/WebsocketTelemetry` 提供 poll/request 维度的时延与错误采样点。

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. 关键流程

#### 1) HTTP/SSE Responses 流程

1. `ResponsesClient::stream_request` 把 `ResponsesApiRequest` 序列化为 JSON body。
2. 若 `request.store == true` 且 provider 判定为 Azure，会调用 `attach_item_ids` 把已有 item id 带回 payload，保障 Azure 兼容路径的 item 对齐。
3. 通过 `EndpointSession::stream_with` 发起 streaming HTTP（自动注入 auth headers、retry policy、request telemetry）。
4. `spawn_response_stream` 先发 header-derived 事件：
   - `ServerModel`
   - `RateLimits`
   - `ModelsEtag`
   - `ServerReasoningIncluded`
5. `process_sse` 持续解析 SSE 数据帧为 `ResponsesStreamEvent`，再映射到 `ResponseEvent`。
6. 遇到 `response.completed` 结束流；若提前断流则抛出 `stream closed before response.completed`。

#### 2) Responses WebSocket 流程

1. `ResponsesWebsocketClient::connect` 构建 ws URL + 合并 headers（provider < extra < default）+ auth 注入。
2. 使用 `maybe_build_rustls_client_config_with_custom_ca` 支持企业 CA 场景。
3. 握手返回头可设置：
   - `x-codex-turn-state`
   - `x-models-etag`
   - `x-reasoning-included`
   - `openai-model`
4. `stream_request` 会先发上述元数据事件，再进入 `run_websocket_response_stream`。
5. 文本帧解析优先尝试 wrapped error，再尝试 `ResponsesStreamEvent`；其中 `codex.rate_limits` 走专门解析路径。
6. `response.completed` 到达后退出；连接异常转 `ApiError::Stream/Transport/Retryable`。

#### 3) Realtime WebSocket 流程

1. `websocket_url_from_api_url` 规范化路径：
   - 空路径 -> `/v1/realtime`
   - `/v1` -> `/v1/realtime`
   - 自动转换 `http/https` 到 `ws/wss`
2. V1 自动追加 `intent=quicksilver`；V2 不追加 intent。
3. 建连后立即发 `session.update`；session payload 由 `methods_v1` 或 `methods_v2` 生成。
4. Writer 与 Events 分离：
   - Writer：`send_audio_frame/send_conversation_item_create/send_conversation_handoff_append/send_response_create`
   - Events：`next_event` 循环消费并调用 `parse_realtime_event`。
5. transcript 聚合规则：连续同 role 的 delta 拼接；V1 handoff 时注入 `active_transcript`。

#### 4) Unary 端点流程

1. `CompactClient::compact_input`：`CompactionInput` -> JSON -> `/responses/compact` -> `Vec<ResponseItem>`。
2. `MemoriesClient::summarize_input`：`MemorySummarizeInput` -> JSON -> `/memories/trace_summarize` -> `Vec<MemorySummarizeOutput>`。
3. `ModelsClient::list_models`：`GET /models?client_version` -> 解析 `ModelsResponse.models` + header `ETag`。

### B. 关键数据结构

1. 请求模型：
   - `ResponsesApiRequest`
   - `ResponseCreateWsRequest`
   - `CompactionInput`
   - `MemorySummarizeInput`
2. 输出模型：
   - `ResponseEvent`
   - `ResponseStream`
   - `MemorySummarizeOutput`
3. 错误模型：`ApiError`（Transport/Stream/Retryable/QuotaExceeded/...）。
4. Realtime 配置/协议模型：
   - `RealtimeSessionConfig`
   - `RealtimeEventParser`
   - `RealtimeSessionMode`
   - `RealtimeOutboundMessage`

### C. 协议细节

#### 1) HTTP 路径

1. `POST /responses`
2. `POST /responses/compact`
3. `POST /memories/trace_summarize`
4. `GET /models`

#### 2) WebSocket 路径

1. Responses websocket：`/responses`
2. Realtime websocket：`/v1/realtime`（动态拼 query）

#### 3) 关键请求/响应头

1. 认证与会话：`Authorization`、`ChatGPT-Account-ID`、`session_id`、`x-client-request-id`
2. 子代理来源：`x-openai-subagent`
3. turn 粘滞路由：`x-codex-turn-state`
4. 模型/版本：`openai-model`、`x-models-etag`
5. server reasoning 信号：`x-reasoning-included`
6. 流式接收声明：`Accept: text/event-stream`

#### 4) rate limit 协议

1. Header 族：`x-codex-*` + `x-<limit>-primary-used-percent` 等。
2. Event 类型：`codex.rate_limits`。

### D. 研究/验证命令（目录相关）

1. 目录与文件：`rg --files codex-rs/codex-api/src`
2. 调用链检索：`rg -n "codex_api::|codex-api" codex-rs`
3. 单 crate 测试入口：`cargo test -p codex-api`
4. 关键端到端测试：
   - `codex-rs/codex-api/tests/clients.rs`
   - `codex-rs/codex-api/tests/sse_end_to_end.rs`
   - `codex-rs/codex-api/tests/models_integration.rs`
   - `codex-rs/codex-api/tests/realtime_websocket_e2e.rs`

## 关键代码路径与文件引用

### 1) 目录内核心实现

1. crate 出口与公共导出
- `/home/sansha/Github/codex/codex-rs/codex-api/src/lib.rs`

2. 配置/认证/错误/telemetry 基础层
- `/home/sansha/Github/codex/codex-rs/codex-api/src/provider.rs`
- `/home/sansha/Github/codex/codex-rs/codex-api/src/auth.rs`
- `/home/sansha/Github/codex/codex-rs/codex-api/src/error.rs`
- `/home/sansha/Github/codex/codex-rs/codex-api/src/telemetry.rs`
- `/home/sansha/Github/codex/codex-rs/codex-api/src/rate_limits.rs`

3. 请求模型与头构建
- `/home/sansha/Github/codex/codex-rs/codex-api/src/common.rs`
- `/home/sansha/Github/codex/codex-rs/codex-api/src/requests/headers.rs`
- `/home/sansha/Github/codex/codex-rs/codex-api/src/requests/responses.rs`

4. endpoint 层
- `/home/sansha/Github/codex/codex-rs/codex-api/src/endpoint/session.rs`
- `/home/sansha/Github/codex/codex-rs/codex-api/src/endpoint/responses.rs`
- `/home/sansha/Github/codex/codex-rs/codex-api/src/endpoint/responses_websocket.rs`
- `/home/sansha/Github/codex/codex-rs/codex-api/src/endpoint/compact.rs`
- `/home/sansha/Github/codex/codex-rs/codex-api/src/endpoint/memories.rs`
- `/home/sansha/Github/codex/codex-rs/codex-api/src/endpoint/models.rs`

5. Realtime 子系统
- `/home/sansha/Github/codex/codex-rs/codex-api/src/endpoint/realtime_websocket/methods.rs`
- `/home/sansha/Github/codex/codex-rs/codex-api/src/endpoint/realtime_websocket/methods_common.rs`
- `/home/sansha/Github/codex/codex-rs/codex-api/src/endpoint/realtime_websocket/methods_v1.rs`
- `/home/sansha/Github/codex/codex-rs/codex-api/src/endpoint/realtime_websocket/methods_v2.rs`
- `/home/sansha/Github/codex/codex-rs/codex-api/src/endpoint/realtime_websocket/protocol.rs`
- `/home/sansha/Github/codex/codex-rs/codex-api/src/endpoint/realtime_websocket/protocol_common.rs`
- `/home/sansha/Github/codex/codex-rs/codex-api/src/endpoint/realtime_websocket/protocol_v1.rs`
- `/home/sansha/Github/codex/codex-rs/codex-api/src/endpoint/realtime_websocket/protocol_v2.rs`

6. SSE 解析
- `/home/sansha/Github/codex/codex-rs/codex-api/src/sse/responses.rs`

### 2) 主要调用方（上游）

1. Responses/compact/memories/models/websocket 统一编排
- `/home/sansha/Github/codex/codex-rs/core/src/client.rs`

2. Provider 配置投影到 `codex_api::Provider`
- `/home/sansha/Github/codex/codex-rs/core/src/model_provider_info.rs`

3. API 错误桥接到 Core 错误
- `/home/sansha/Github/codex/codex-rs/core/src/api_bridge.rs`

4. realtime 会话管理
- `/home/sansha/Github/codex/codex-rs/core/src/realtime_conversation.rs`

5. models 刷新与 ETag 缓存
- `/home/sansha/Github/codex/codex-rs/core/src/models_manager/manager.rs`

6. telemetry 事件消费 `ApiError/ResponseEvent`
- `/home/sansha/Github/codex/codex-rs/otel/src/events/session_telemetry.rs`

### 3) 主要被调用方（下游/并行依赖）

1. 通用 transport/retry 抽象
- `/home/sansha/Github/codex/codex-rs/codex-client/README.md`

2. 协议模型定义（`ResponseItem/RealtimeEvent/ModelInfo` 等）
- `/home/sansha/Github/codex/codex-rs/protocol`

3. 配置 schema（provider 字段）
- `/home/sansha/Github/codex/codex-rs/core/config.schema.json`

### 4) 测试/文档/脚本路径

1. crate README
- `/home/sansha/Github/codex/codex-rs/codex-api/README.md`

2. 目录外部测试（e2e/集成）
- `/home/sansha/Github/codex/codex-rs/codex-api/tests/clients.rs`
- `/home/sansha/Github/codex/codex-rs/codex-api/tests/sse_end_to_end.rs`
- `/home/sansha/Github/codex/codex-rs/codex-api/tests/models_integration.rs`
- `/home/sansha/Github/codex/codex-rs/codex-api/tests/realtime_websocket_e2e.rs`

3. 关联脚本/命令
- `/home/sansha/Github/codex/justfile`（`fmt/test/fix` 等）
- `/home/sansha/Github/codex/.ops/generate_daily_research_todo.sh`（研究任务日更脚本）

## 依赖与外部交互

### 1) 代码依赖关系

`codex-api` 在 `Cargo.toml` 中的关键依赖：

1. 内部 crate：`codex-client`、`codex-protocol`、`codex-utils-rustls-provider`。
2. 网络与并发：`tokio`、`tokio-tungstenite`、`futures`、`http`、`url`。
3. 序列化与错误：`serde`、`serde_json`、`thiserror`。
4. SSE/解析：`eventsource-stream`、`regex-lite`。

### 2) 与配置系统交互

1. `core` 的 `ModelProviderInfo` 通过 `to_api_provider` 投影为 `codex_api::Provider`。
2. 配置字段直接影响 API 行为：
   - `base_url/query_params/http_headers/env_http_headers`
   - `request_max_retries/stream_idle_timeout_ms/websocket_connect_timeout_ms`
   - `supports_websockets`
3. `wire_api` 目前固定 `responses`，`chat` 已移除。

### 3) 与外部网络交互

1. HTTP(S)：`/responses`、`/responses/compact`、`/memories/trace_summarize`、`/models`。
2. WebSocket：`/responses` 与 `/v1/realtime`。
3. TLS：支持自定义 CA（经 `maybe_build_rustls_client_config_with_custom_ca`）。

### 4) 与上游语义交互

1. `core` 使用 `ResponseEvent` 统一流式消费。
2. `core` 使用 `ApiError` 决策重试、401 恢复、http fallback。
3. `otel` 用 `ResponseEvent`/`ApiError` 统计 API call 与流式指标。

### 5) 文档与测试覆盖关系

1. 文档主入口：`codex-rs/codex-api/README.md`（接口级概览）。
2. 目录内单元测试覆盖：
   - rate limit 解析
   - models/memories/compact path
   - responses websocket wrapped error
   - realtime URL/事件/并发发送
3. 目录外集成测试覆盖：
   - HTTP/SSE 端到端
   - models wiremock
   - realtime websocket E2E

## 风险、边界与改进建议

### 1) 主要风险

1. `realtime_websocket/methods.rs` 体积较大（约 1800+ 行），协议构建、连接、并发 pump、解析测试集中在单文件，维护成本高。
2. `sse/responses.rs` 同时承担解析逻辑和大量测试（1000+ 行），后续新增 event type 时容易引入回归。
3. `Provider::url_for_path` 通过字符串拼 query，未做 URL 编码语义层保证；若 query 值含特殊字符存在编码风险。
4. `parse_rate_limit_for_limit` 默认总会构造 `RateLimitSnapshot`（即使为空），调用方必须额外判断有无实际窗口数据。
5. Responses HTTP 与 Responses WebSocket 都存在 header merge + metadata event 注入逻辑，长期演进可能出现语义漂移。

### 2) 关键边界

1. `codex-api` 只做 wire-level 映射，不做 auth refresh 或业务重试预算（属于 `core`）。
2. realtime v1 与 v2 的兼容策略在 `methods_common/protocol_v*`，上游只依赖统一 `RealtimeEvent`，不能绕过该层直接耦合原始 payload。
3. Azure 特化逻辑当前仅通过 provider 名称/URL 启发式识别，属于协议兼容折中方案，不是强类型 provider 能力协商。

### 3) 改进建议

1. 拆分 `realtime_websocket/methods.rs`：
   - `connect.rs`（URL/header/handshake）
   - `writer.rs`（outbound 命令）
   - `events.rs`（inbound 解析与 transcript 聚合）
   - `pump.rs`（WsStream 命令泵）
2. 拆分 `sse/responses.rs`：
   - `event_mapper.rs`（`ResponsesStreamEvent -> ResponseEvent`）
   - `error_mapper.rs`（`response.failed` 分类）
   - `stream_runner.rs`（timeout/poll/telemetry）
3. 引入 URL builder 统一 query 编码，替代手工 `format!("{k}={v}")`。
4. 将 Responses HTTP 与 WebSocket 的公共事件注入逻辑（`ServerModel/ModelsEtag/ServerReasoningIncluded/turn_state`）抽象共享函数，减少双路径偏差。
5. 对新增 `response.*` 事件类型建立表驱动映射测试模板（当前已有部分 table-driven，可进一步扩展覆盖 unknown/new event 行为）。
