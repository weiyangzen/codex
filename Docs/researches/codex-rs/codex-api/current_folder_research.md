# DIR `codex-rs/codex-api` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/codex-api`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 关联 crate：`codex-api`（Bazel crate_name: `codex_api`）

## 场景与职责

`codex-api` 是 Codex Rust 工作区中的“API 线协议适配层”。它位于：

1. 上游业务层（`codex-core`）
2. 下游传输层（`codex-client`）

之间，职责是把业务层的“模型调用意图”转成具体 HTTP/SSE/WebSocket 请求，并将流式/错误语义映射回统一事件模型。

它覆盖 4 条核心调用链：

1. Responses HTTP + SSE（`POST /responses`）
2. Responses WebSocket（`/responses`，双向事件）
3. Realtime WebSocket（`/v1/realtime`，含 v1/v2 parser）
4. Unary 端点（`/responses/compact`、`/memories/trace_summarize`、`/models`）

核心边界：

1. `codex-api` 负责 wire-level 细节（URL/header/retry/流解析/error mapping）。
2. `codex-core` 负责会话编排、401 恢复、重试预算与业务决策。
3. `codex-client` 只做通用 transport/retry，不感知 OpenAI/Codex 协议语义。

对应实现入口：`codex-rs/codex-api/README.md:3-10`，`codex-rs/codex-api/src/lib.rs:1-49`。

## 功能点目的

1. 统一 Provider 抽象
- 目的：把 base_url、query 参数、默认 headers、retry 策略、stream idle timeout 收敛到一个实体，避免调用方重复拼装。
- 实现：`Provider` + `RetryConfig`（`codex-rs/codex-api/src/provider.rs:16-104`）。

2. 统一认证注入
- 目的：将 bearer token 与可选 account id 以统一规则注入请求头。
- 实现：`AuthProvider` trait + `add_auth_headers*`（`codex-rs/codex-api/src/auth.rs:10-31`）。

3. 统一请求/事件数据模型
- 目的：给上游提供稳定模型（`ResponsesApiRequest`、`ResponseEvent`、`ResponseStream`），屏蔽 wire 细节。
- 实现：`common.rs`（`codex-rs/codex-api/src/common.rs:24-271`）。

4. Responses SSE 事件解析与错误分级
- 目的：将 `response.*` 事件转换成 typed `ResponseEvent`，并识别可重试/不可重试错误（context window、quota、invalid_prompt 等）。
- 实现：`process_responses_event` + `process_sse`（`codex-rs/codex-api/src/sse/responses.rs:236-431`）。

5. Responses WebSocket 流转发
- 目的：在 WebSocket 下复用同一事件语义，支持连接复用、wrapped error 映射、rate-limit event 透传。
- 实现：`run_websocket_response_stream`（`codex-rs/codex-api/src/endpoint/responses_websocket.rs:533-647`）。

6. Realtime v1/v2 协议兼容
- 目的：同一客户端在 v1/quicksilver 与 v2/realtime/transcription 间切换，且保持统一 `RealtimeEvent` 输出。
- 实现：`methods.rs` + `protocol_v1.rs` + `protocol_v2.rs`（`codex-rs/codex-api/src/endpoint/realtime_websocket/methods.rs:443-607`，`.../protocol_v1.rs:11-85`，`.../protocol_v2.rs:19-187`）。

7. Rate-limit 统一解析
- 目的：统一从 HTTP headers 与 websocket `codex.rate_limits` payload 解析 `RateLimitSnapshot`。
- 实现：`rate_limits.rs`（`codex-rs/codex-api/src/rate_limits.rs:22-258`）。

8. Telemetry 钩子注入
- 目的：请求级、SSE poll、WebSocket poll 三类 telemetry 统一挂接，便于 `codex-core/codex-otel` 汇总。
- 实现：`run_with_request_telemetry` + `SseTelemetry` + `WebsocketTelemetry`（`codex-rs/codex-api/src/telemetry.rs:18-97`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. 关键流程

1. Responses HTTP/SSE 流程
- `ResponsesClient::stream_request` 组装 body + headers（conversation/subagent/compression）。
- Azure 且 `store=true` 时执行 `attach_item_ids`，把 input item id 带上。
- `EndpointSession::stream_with` 通过 `run_with_request_telemetry` 发起 streaming HTTP。
- `spawn_response_stream` 先发 header-derived 事件（ServerModel/RateLimits/ModelsEtag/ServerReasoningIncluded），再进入 `process_sse`。
- 代码：`codex-rs/codex-api/src/endpoint/responses.rs:69-148`，`codex-rs/codex-api/src/endpoint/session.rs:112-140`，`codex-rs/codex-api/src/sse/responses.rs:57-107,357-431`。

2. Responses WebSocket 流程
- `ResponsesWebsocketClient::connect`：URL 转换 + header merge + auth 注入 + TLS connector（支持 custom CA）。
- 连接后缓存 `x-codex-turn-state`、`x-models-etag`、`x-reasoning-included`、`openai-model`。
- `ResponsesWebsocketConnection::stream_request` 发送 `response.create`，循环读取文本帧，复用 `process_responses_event` 逻辑。
- 代码：`codex-rs/codex-api/src/endpoint/responses_websocket.rs:299-420,533-647`。

3. Realtime WebSocket 流程
- `RealtimeWebsocketClient::connect`：把 API URL 规范化到 `/v1/realtime` 并补 query（v1 加 `intent=quicksilver`，可附 `model`）。
- 建连后立即发送 `session.update`。
- writer 支持 `input_audio_buffer.append` / `conversation.item.create` / `response.create` / handoff output。
- events 侧通过 parser（V1 或 RealtimeV2）转换事件，并维护 active transcript（用于 v1 handoff 回填）。
- 代码：`codex-rs/codex-api/src/endpoint/realtime_websocket/methods.rs:452-507,547-607,350-423`。

4. Unary 端点流程
- Compact：`POST /responses/compact`，返回 `Vec<ResponseItem>`。
- Memories：`POST /memories/trace_summarize`，请求字段 `raw_memories` 在 wire 上重命名为 `traces`。
- Models：`GET /models?client_version=...`，读取 body 中 models 与响应头 ETag。
- 代码：`codex-rs/codex-api/src/endpoint/compact.rs:32-58`，`.../memories.rs:32-57`，`.../models.rs:31-70`。

### B. 关键数据结构

1. 请求模型
- `ResponsesApiRequest`：model/instructions/input/tools/parallel_tool_calls/reasoning/text 等（`codex-rs/codex-api/src/common.rs:154-171`）。
- `ResponseCreateWsRequest`：websocket 版 `response.create` 载荷（`.../common.rs:197-220`）。
- `CompactionInput` / `MemorySummarizeInput`（`.../common.rs:24-44`）。

2. 输出/事件模型
- `ResponseEvent`：涵盖 `Created`、`OutputItemDone`、`OutputTextDelta`、`Reasoning*Delta`、`Completed`、`RateLimits`、`ServerModel` 等（`.../common.rs:66-96`）。
- `ResponseStream`：`mpsc::Receiver<Result<ResponseEvent, ApiError>>` 包装成 `futures::Stream`（`.../common.rs:271-280`）。

3. 错误模型
- `ApiError`：Transport、Api(status+message)、Stream、Retryable(delay)、ContextWindowExceeded、QuotaExceeded、InvalidRequest、ServerOverloaded 等（`codex-rs/codex-api/src/error.rs:8-31`）。

4. Realtime 协议模型
- `RealtimeSessionConfig`（instructions/model/session_id/parser/mode）。
- `RealtimeOutboundMessage`（`session.update`、`response.create`、`conversation.item.create` 等）。
- 代码：`codex-rs/codex-api/src/endpoint/realtime_websocket/protocol.rs:24-47`。

### C. 协议与 wire 细节

1. HTTP 端点
- `/responses`
- `/responses/compact`
- `/memories/trace_summarize`
- `/models`

2. Responses 相关 header
- `session_id`（conversation 头）
- `x-openai-subagent`
- `x-client-request-id`
- `x-codex-turn-state`
- `x-models-etag`
- `x-reasoning-included`
- `openai-model`

对应代码：`codex-rs/codex-api/src/requests/headers.rs:5-33`，`codex-rs/codex-api/src/endpoint/responses.rs:92-95`，`codex-rs/codex-api/src/endpoint/responses_websocket.rs:155-159`。

3. Realtime URL 规则
- `http/https` 自动转 `ws/wss`。
- 空路径补 `/v1/realtime`。
- v1 自动追加 `intent=quicksilver`。
- 保留并合并 provider query params。
- 代码：`codex-rs/codex-api/src/endpoint/realtime_websocket/methods.rs:547-598`。

4. rate limit 协议
- 头部族：`x-codex-*` + `x-<limit>-primary-used-percent` 等。
- 事件：`{"type":"codex.rate_limits", ...}`。
- 代码：`codex-rs/codex-api/src/rate_limits.rs:27-92,130-154`。

### D. 命令/测试执行面（目录相关）

目录级验证命令来自 crate 常规测试：

1. `cargo test -p codex-api`
2. 关键测试覆盖：
- client 请求头/路径/重试：`codex-rs/codex-api/tests/clients.rs:199-354`
- SSE end-to-end：`codex-rs/codex-api/tests/sse_end_to_end.rs:95-170`
- models 集成：`codex-rs/codex-api/tests/models_integration.rs:50-130`
- realtime websocket e2e：`codex-rs/codex-api/tests/realtime_websocket_e2e.rs:74-459`

## 关键代码路径与文件引用

### 目录内（目标目录）

1. crate 出口与职责收敛
- `codex-rs/codex-api/src/lib.rs:1-49`
- `codex-rs/codex-api/README.md:1-37`

2. 基础层
- `codex-rs/codex-api/src/provider.rs:16-166`
- `codex-rs/codex-api/src/auth.rs:10-31`
- `codex-rs/codex-api/src/error.rs:8-35`
- `codex-rs/codex-api/src/telemetry.rs:18-97`

3. 请求与模型
- `codex-rs/codex-api/src/common.rs:24-280`
- `codex-rs/codex-api/src/requests/headers.rs:5-33`
- `codex-rs/codex-api/src/requests/responses.rs:5-36`

4. endpoint 实现
- `codex-rs/codex-api/src/endpoint/session.rs:17-140`
- `codex-rs/codex-api/src/endpoint/responses.rs:26-148`
- `codex-rs/codex-api/src/endpoint/responses_websocket.rs:162-647`
- `codex-rs/codex-api/src/endpoint/compact.rs:15-63`
- `codex-rs/codex-api/src/endpoint/memories.rs:15-64`
- `codex-rs/codex-api/src/endpoint/models.rs:14-70`

5. SSE 与 rate limits
- `codex-rs/codex-api/src/sse/responses.rs:32-431`
- `codex-rs/codex-api/src/rate_limits.rs:22-258`

6. Realtime 子系统
- `codex-rs/codex-api/src/endpoint/realtime_websocket/methods.rs:190-607`
- `codex-rs/codex-api/src/endpoint/realtime_websocket/protocol.rs:12-216`
- `codex-rs/codex-api/src/endpoint/realtime_websocket/protocol_v1.rs:11-85`
- `codex-rs/codex-api/src/endpoint/realtime_websocket/protocol_v2.rs:19-187`
- `codex-rs/codex-api/src/endpoint/realtime_websocket/methods_v1.rs:18-76`
- `codex-rs/codex-api/src/endpoint/realtime_websocket/methods_v2.rs:35-133`

7. 测试路径
- `codex-rs/codex-api/tests/clients.rs:199-354`
- `codex-rs/codex-api/tests/sse_end_to_end.rs:95-170`
- `codex-rs/codex-api/tests/models_integration.rs:50-130`
- `codex-rs/codex-api/tests/realtime_websocket_e2e.rs:74-459`

### 调用方（上游）

1. `codex-core` 主调用
- `codex-rs/core/src/client.rs:39-62,366-438,986-1200,1381-1405`
- `codex-rs/core/src/model_provider_info.rs:107-129,166-193,215-238`
- `codex-rs/core/src/codex.rs:6267-6316`（stream retry budget + ws fallback）

2. `codex-core` realtime 编排
- `codex-rs/core/src/realtime_conversation.rs:159-181,447-497`

3. `codex-otel` 对事件/错误类型依赖
- `codex-rs/otel/src/events/session_telemetry.rs:31-32,572-710`

### 被调用方（下游）

1. 通用 transport/retry
- `codex-rs/codex-client/src/transport.rs:27-173`
- `codex-rs/codex-client/src/retry.rs:9-74`
- `codex-rs/codex-client/README.md:3-8`

2. 协议类型来源
- `codex-protocol`（`ResponseItem`、`RealtimeEvent`、`RateLimitSnapshot` 等通过 `codex-api` 使用并再导出）

### 配置/文档/脚本上下文

1. workspace 注册
- `codex-rs/Cargo.toml:67-68,86-103`

2. 上游配置映射到 `Provider`
- `codex-rs/core/src/model_provider_info.rs:107-129,166-193,215-238`
- 关键配置字段：`request_max_retries`、`stream_max_retries`、`stream_idle_timeout_ms`、`websocket_connect_timeout_ms`、`supports_websockets`。

3. realtime 配置来源
- `codex-rs/core/src/config/mod.rs:499-518,1404-1419`

4. 目录自身脚本现状
- `codex-rs/codex-api` 下无独立 scripts；测试与构建依赖 workspace 命令和 crate 测试。

## 依赖与外部交互

### 内部依赖关系

1. 上游调用链
- `codex-core` 是主调用方（流式对话、models 拉取、compaction、memory summarize、realtime）。
- `codex-otel` 依赖 `codex-api` 的事件/错误类型用于 telemetry 统计。

2. 下游依赖链
- `codex-client`：`HttpTransport`、`ReqwestTransport`、`run_with_retry`、`RequestCompression`。
- `codex-protocol`：跨层共享结构（`ResponseItem`、`RealtimeEvent`、`RateLimitSnapshot`）。

3. 传输依赖
- HTTP: `reqwest`（通过 `codex-client`）
- SSE: `eventsource-stream`
- WebSocket: `tokio-tungstenite` + `tungstenite`（responses ws / realtime ws）
- URL 与 header：`url`、`http`

### 外部交互（网络/协议）

1. 外部 API 端点
- `POST /responses`
- `POST /responses/compact`
- `POST /memories/trace_summarize`
- `GET /models`
- `WS /responses`
- `WS /v1/realtime`

2. 认证与身份
- `Authorization: Bearer <token>`
- `ChatGPT-Account-ID`（可选）

3. 可观测与路由粘性头
- `x-codex-turn-state`
- `x-models-etag`
- `openai-model`
- `x-reasoning-included`
- `x-codex-turn-metadata`（由上游通过 client metadata 或 header 注入）

4. TLS/证书策略
- WebSocket 连接与 HTTP 一致支持 custom CA（`maybe_build_rustls_client_config_with_custom_ca`）。

### 配置与测试联动

1. Provider 配置会直接影响 `codex-api` 行为
- retry 次数、stream idle timeout、websocket connect timeout、是否允许 websocket。

2. 上游重试预算与降级逻辑在 `codex-core`
- `codex-api` 返回 error 语义，是否重试/何时 fallback 到 HTTP 由 `core` 决定。

3. 测试层覆盖策略
- 单测：解析器、header 映射、URL 规范化。
- 端到端：mock websocket server + fixture SSE 验证。

## 风险、边界与改进建议

### 风险

1. 大文件维护风险
- `sse/responses.rs`（1059 行）和 `realtime_websocket/methods.rs`（1872 行）承担多重职责（协议解析、状态机、测试），回归面较大。

2. 双流路径一致性风险
- 同一语义在 HTTP/SSE 与 Responses WebSocket 各有一套执行循环，需要持续保持事件映射一致（如 `response.failed`、`codex.rate_limits`、ServerModel）。

3. wrapped websocket error 兼容风险
- responses websocket 依赖 `{"type":"error", "status":...}` 包装格式；若后端变更字段名会导致降级成 generic stream error。

4. query 参数拼接风险
- `Provider::url_for_path` 目前直接 `format!("{k}={v}")`，未显式 URL encode；若 value 含特殊字符可能产生歧义。

### 边界

1. 不负责业务层重试决策
- 401 刷新、stream 重连预算、WebSocket->HTTP fallback 在 `codex-core`，不在 `codex-api`。

2. 不负责模型策略与 prompt 构造
- `codex-api` 只接收已构造 payload，不决定工具策略、记忆策略、turn 生命周期。

3. 不负责最终 telemetry 存储
- 仅暴露 telemetry hook；指标落地在 `codex-otel`。

### 改进建议

1. 拆分超大模块
- 把 `sse/responses.rs` 按“event decode / error mapping / stream loop / tests”拆分。
- 把 `realtime_websocket/methods.rs` 按“connection pump / writer / events parser adapter / url builder / tests”拆分。

2. 统一 HTTP 与 WS 的事件断言夹具
- 提取共享测试向量，保证 `process_responses_event` 在两条传输路径下行为一致。

3. 强化 URL 构建安全性
- `Provider::url_for_path` 改为 `url::Url` + query_pairs_mut，避免手工拼接 query。

4. 为 wrapped error 增加弹性解析
- 兼容 `status_code/status`、`error.code/type` 的更多排列，减少协议轻微变更导致的误分类。

5. 建立目录级 README 的“协议契约快照”
- 当前 README 偏概述，建议补充 header/endpoint/event type 的稳定契约表，降低后续维护成本。
