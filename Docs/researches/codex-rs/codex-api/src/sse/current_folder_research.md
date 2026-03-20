# codex-rs/codex-api/src/sse 研究报告

## 场景与职责

`codex-rs/codex-api/src/sse` 是 Responses HTTP 流式返回在 Rust 侧的“协议解码 + 事件归一化”层。它的职责不是发请求，而是把上游 `ByteStream`/SSE 文本流转成内部统一事件 `ResponseEvent`，并把 HTTP 响应头中携带的模型/限流/turn state 元数据提前注入事件流。

该目录当前只有两个文件：
- `mod.rs`：导出边界，向外暴露 `stream_from_fixture`、`spawn_response_stream`、`process_sse`（`codex-rs/codex-api/src/sse/mod.rs:1-5`）。
- `responses.rs`：完整实现（SSE 解码、事件映射、错误语义、测试）。

它在整体链路中的位置：
1. `core::ModelClientSession::stream_responses_api` 构造请求。
2. `codex_api::ResponsesClient::stream_request` 发起 HTTP POST `/responses`，拿到 `StreamResponse`。
3. `spawn_response_stream` 启动后台任务处理 SSE，并通过 channel 向上游持续吐 `ResponseEvent`。
4. `core` 层消费这些事件，更新 UI、token、限流、模型路由、会话状态。

关键入口见：
- `codex-rs/codex-api/src/endpoint/responses.rs:69-150`
- `codex-rs/core/src/client.rs:998-1078`
- `codex-rs/core/src/codex.rs:7184-7204`

## 功能点目的

### 1) Fixture 回放能力（离线/集成测试）
`stream_from_fixture` 从磁盘读取 `.sse`/文本 fixture，包装成 `ReaderStream` 后复用 `process_sse`，返回 `ResponseStream`（`codex-rs/codex-api/src/sse/responses.rs:32-55`）。

目的：
- 支持 CLI/core/exec 离线集成测试，不依赖真实网络。
- 通过 `CODEX_RS_SSE_FIXTURE` 切换到本地流（`codex-rs/core/src/flags.rs:3-6`，`codex-rs/core/src/client.rs:1008-1016`）。

### 2) HTTP 响应头元数据转事件
`spawn_response_stream` 在开始读取 body 前，先解析并发送：
- `ServerModel`（`openai-model`）
- `RateLimits`（`parse_all_rate_limits`）
- `ModelsEtag`（`X-Models-Etag`）
- `ServerReasoningIncluded(true)`（`x-reasoning-included`）
- 写入 `turn_state`（`x-codex-turn-state`）

见 `codex-rs/codex-api/src/sse/responses.rs:57-106`。

目的：
- 把“响应头语义”提升到统一事件层，让 core 无需直接读 HeaderMap。
- 保障 turn sticky routing token 在同一 turn 内可回放。

### 3) Responses 事件类型映射
`process_responses_event` 按 `type` 把 JSON 映射到内部枚举（`codex-rs/codex-api/src/sse/responses.rs:236-355`）：
- `response.output_item.done` -> `OutputItemDone`
- `response.output_item.added` -> `OutputItemAdded`
- `response.output_text.delta` -> `OutputTextDelta`
- `response.reasoning_summary_text.delta` -> `ReasoningSummaryDelta`
- `response.reasoning_text.delta` -> `ReasoningContentDelta`
- `response.reasoning_summary_part.added` -> `ReasoningSummaryPartAdded`
- `response.created` -> `Created`
- `response.completed` -> `Completed { response_id, token_usage }`
- `response.failed` / `response.incomplete` -> `ApiError`

目的：
- 收敛 OpenAI Responses 流协议到 `ResponseEvent` 领域模型（定义在 `codex-rs/codex-api/src/common.rs:66-95`）。

### 4) 错误分类与重试语义
`response.failed` 解析到细粒度错误：
- `context_length_exceeded` -> `ContextWindowExceeded`
- `insufficient_quota` -> `QuotaExceeded`
- `usage_not_included` -> `UsageNotIncluded`
- `invalid_prompt` -> `InvalidRequest`
- `server_is_overloaded`/`slow_down` -> `ServerOverloaded`
- 其他 -> `Retryable { message, delay }`

`delay` 会从错误文案正则提取 `try again in ...`（支持 `ms/s/seconds`）
（`codex-rs/codex-api/src/sse/responses.rs:274-299`, `436-489`）。

目的：
- 为上游恢复策略和用户提示提供稳定错误语义，而不是裸字符串。

### 5) SSE 生命周期管控
`process_sse` 的退出条件：
- 收到 `response.completed` 立即 return。
- 流结束但未 completed -> `stream closed before response.completed`。
- 空闲超时 -> `idle timeout waiting for SSE`。
- 事件解析失败仅跳过，不终止流。

见 `codex-rs/codex-api/src/sse/responses.rs:357-434`。

目的：
- 强化“completed 是完成信号”的协议约束，避免 silent success。

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. 关键流程（HTTP SSE）

1. `ResponsesClient::stream_request` 序列化请求并发起 `POST /responses`，强制 `Accept: text/event-stream`。
   - `codex-rs/codex-api/src/endpoint/responses.rs:69-150`
2. 得到 `StreamResponse` 后调用 `spawn_response_stream`。
   - `codex-rs/codex-api/src/endpoint/responses.rs:144-149`
3. `spawn_response_stream` 先发 header 衍生事件，再调用 `process_sse` 消费 body。
   - `codex-rs/codex-api/src/sse/responses.rs:57-103`
4. `process_sse`：`eventsource_stream` 解码 -> JSON 反序列化 `ResponsesStreamEvent` -> `process_responses_event`。
   - `codex-rs/codex-api/src/sse/responses.rs:357-433`
5. core 用 `map_response_stream` 把 api error 映射到 `CodexErr`，并累计 `items_added` 给 websocket 增量请求复用。
   - `codex-rs/core/src/client.rs:1405-1485`

### B. 关键流程（WebSocket 复用同一事件映射）
WebSocket 路径不在本目录，但与 `sse/responses.rs` 强耦合：
- `responses_websocket.rs` 直接复用 `ResponsesStreamEvent` + `process_responses_event`。
- 仅额外处理 `codex.rate_limits` 与 wrapped websocket error。

见：
- `codex-rs/codex-api/src/endpoint/responses_websocket.rs:9-10`
- `codex-rs/codex-api/src/endpoint/responses_websocket.rs:533-635`
- `codex-rs/codex-api/src/rate_limits.rs:130-160`

### C. 数据结构

1. `ResponseEvent`（统一消费事件）
- 包含 `Created/OutputItem*/Delta*/Completed/RateLimits/ModelsEtag/ServerModel/...`
- `codex-rs/codex-api/src/common.rs:66-95`

2. `ResponsesStreamEvent`（线协议中间态）
- 字段：`kind/headers/response/item/delta/summary_index/content_index`
- `response_model()` 支持优先读 `response.headers`，回退顶层 `headers`。
- `codex-rs/codex-api/src/sse/responses.rs:164-221`

3. `ResponseCompletedUsage -> TokenUsage`
- 将 `input_tokens_details.cached_tokens` 与 `output_tokens_details.reasoning_tokens` 映射到统一 token usage。
- `codex-rs/codex-api/src/sse/responses.rs:126-151`

4. 通道模型
- 统一用 `mpsc::channel(1600)` 传递 `Result<ResponseEvent, ApiError>`。
- `codex-rs/codex-api/src/sse/responses.rs:47`, `86`

### D. 协议细节

1. SSE 事件样式
- `event: response.output_item.done`
- `data: {json}`

fixture 样例见：
- `codex-rs/core/tests/cli_responses_fixture.sse:1-8`
- `codex-rs/exec/tests/fixtures/cli_responses_fixture.sse:1-8`

2. 关键响应头
- `openai-model`
- `x-reasoning-included`
- `x-models-etag` / `X-Models-Etag`
- `x-codex-turn-state`

解析点见：
- `codex-rs/codex-api/src/sse/responses.rs:28-29`, `63-85`
- `codex-rs/codex-api/src/endpoint/responses_websocket.rs:155-158`, `386-404`

### E. 相关命令（研发/验证/维护）

1. 运行 codex-api SSE 相关测试：
```bash
cargo test -p codex-api sse_end_to_end
cargo test -p codex-api --lib sse::responses
```

2. 使用 fixture 驱动 CLI 回归（测试中同款用法）：
```bash
CODEX_RS_SSE_FIXTURE=<fixture_path> codex exec ...
```
参考：`codex-rs/core/tests/suite/cli_stream.rs:299-330`。

3. 研究任务管理脚本（本次交付流程相关）：
```bash
bash .ops/generate_daily_research_todo.sh
```
脚本逻辑见 `.ops/generate_daily_research_todo.sh:1-42`。

## 关键代码路径与文件引用

### 目录本体
- `codex-rs/codex-api/src/sse/mod.rs:1-5`
- `codex-rs/codex-api/src/sse/responses.rs:32-106`（入口/封装）
- `codex-rs/codex-api/src/sse/responses.rs:236-355`（事件映射）
- `codex-rs/codex-api/src/sse/responses.rs:357-434`（SSE 状态机）
- `codex-rs/codex-api/src/sse/responses.rs:436-489`（retry-after 解析）
- `codex-rs/codex-api/src/sse/responses.rs:491-1059`（单测覆盖）

### 上游调用方
- `codex-rs/codex-api/src/endpoint/responses.rs:12`, `69-150`
- `codex-rs/core/src/client.rs:998-1078`（HTTP path）
- `codex-rs/core/src/client.rs:1008-1016`（fixture path）

### 同构实现/并行 transport（WebSocket）
- `codex-rs/codex-api/src/endpoint/responses_websocket.rs:9-10`（复用 parser）
- `codex-rs/codex-api/src/endpoint/responses_websocket.rs:533-649`（ws 事件循环）
- `codex-rs/codex-api/src/endpoint/responses_websocket.rs:608-613`（`codex.rate_limits` 特例）

### 下游消费方
- `codex-rs/core/src/client.rs:1405-1485`（map_response_stream）
- `codex-rs/core/src/codex.rs:7184-7304`（主事件分发）
- `codex-rs/core/src/codex.rs:3291-3330`（ServerModel mismatch warning）
- `codex-rs/core/src/codex.rs:3667-3677`, `3702-3705`（限流/reasoning 状态落库）

### 配置与开关
- `codex-rs/core/src/flags.rs:3-6`（`CODEX_RS_SSE_FIXTURE`）
- `codex-rs/core/src/model_provider_info.rs:112-114`, `228-233`（`stream_idle_timeout_ms`）
- `codex-rs/codex-api/src/provider.rs:49`（Provider.stream_idle_timeout）

### 测试/夹具/文档性代码
- `codex-rs/codex-api/tests/sse_end_to_end.rs:94-170`
- `codex-rs/core/tests/common/streaming_sse.rs:42-157`
- `codex-rs/core/tests/suite/cli_stream.rs:299-330`
- `codex-rs/exec/tests/suite/server_error_exit.rs:7-31`
- `codex-rs/codex-client/src/sse.rs:9-47`（更底层泛化 SSE helper，对比参考）

## 依赖与外部交互

### 代码依赖

1. `codex-client`
- 输入流类型 `ByteStream`、`StreamResponse`、`TransportError`。
- `codex-rs/codex-api/src/sse/responses.rs:6-8`

2. `codex-protocol`
- 反序列化 `ResponseItem` 与 `TokenUsage`。
- `codex-rs/codex-api/src/sse/responses.rs:9-10`

3. `eventsource-stream` + `tokio-util::ReaderStream`
- SSE 解码与 fixture bytes 流模拟。
- `codex-rs/codex-api/src/sse/responses.rs:11`, `24`

4. telemetry 抽象
- `SseTelemetry::on_sse_poll` 在每次 `timeout + next()` 轮询后回调。
- `codex-rs/codex-api/src/telemetry.rs:18-32`
- 调用点：`codex-rs/codex-api/src/sse/responses.rs:368-372`

### 外部协议交互

1. HTTP Responses API
- 通过 `Accept: text/event-stream` 进入流模式。
- `codex-rs/codex-api/src/endpoint/responses.rs:135-138`

2. 服务端头字段
- 限流、模型、turn_state、reasoning-included 由响应头驱动客户端状态。
- `codex-rs/codex-api/src/sse/responses.rs:63-85`

3. 事件协议
- 依赖 `type` 字段分发；未知事件仅 trace，不报错。
- `codex-rs/codex-api/src/sse/responses.rs:349-351`

### 测试与脚本外部交互

1. fixture 文件生态
- core/exec 使用相同 SSE fixture 模式，确保 CLI 行为可回放。

2. 研究流程脚本
- `.ops/generate_daily_research_todo.sh` 读取 `blueprint_checklist.md` 生成当天 TODO（用于本任务第 6 步）。
- `.ops/generate_daily_research_todo.sh:15-39`

## 风险、边界与改进建议

### 风险与边界

1. `response.failed` 处理是“延迟抛错”
当前逻辑在 `process_responses_event` 遇到 failed 时只缓存 `response_error`，直到流结束 (`Ok(None)`) 才真正向上游发送错误（`codex-rs/codex-api/src/sse/responses.rs:274-299,380-385` 的组合行为）。
- 风险：若服务端 failed 后继续发其他帧，可能导致调用方看到混合语义。

2. 未知事件被静默忽略
仅 `trace!`，无指标与计数（`codex-rs/codex-api/src/sse/responses.rs:349-351`）。
- 风险：服务端新增事件时，客户端可能“看起来正常”但功能缺失。

3. JSON 解析失败仅跳过
`Failed to parse SSE event` 后继续（`codex-rs/codex-api/src/sse/responses.rs:397-402`）。
- 风险：若持续出现坏帧，会长期空转直到 timeout/close，定位成本较高。

4. fixture 读取按“行 -> 强制 `\n\n`”重建流
`stream_from_fixture` 对每行追加双换行（`codex-rs/codex-api/src/sse/responses.rs:39-43`）。
- 边界：对包含多行 `data:` 的复杂 SSE fixture 可能不够精确。

5. Header 名大小写策略不完全统一
- SSE HTTP 路径读取 `X-Models-Etag`（大写 X）但 http::HeaderMap 通常大小写不敏感，实践可用。
- WebSocket 路径常量为小写 `x-models-etag`。
- 建议统一常量来源，降低维护误差。

### 改进建议

1. 明确 failed 的终止策略（高优先级）
可考虑在收到 `response.failed` 时立即发 Err 并 return，或引入显式策略开关，避免 delayed failure 语义歧义。

2. 增加“未知事件/解析失败”指标（高优先级）
在 telemetry 中加入计数，至少上报 event kind 和次数，帮助线上发现协议漂移。

3. 抽取 HTTP/WS 共享流处理骨架（中优先级）
当前 `process_sse` 与 `run_websocket_response_stream` 在 model 去重、completed 终止、error 传播逻辑上高度相似，可进一步抽象降低分叉风险。

4. fixture parser 增强（中优先级）
让 `stream_from_fixture` 支持保留原始块边界，或直接读取原始 bytes，避免“逐行拼接”带来的语义差异。

5. 统一头字段常量定义（低到中优先级）
`openai-model/x-models-etag/x-reasoning-included/x-codex-turn-state` 建议集中到共享常量模块，减少 transport 间漂移。
