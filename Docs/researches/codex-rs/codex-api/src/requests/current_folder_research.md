# DIR `codex-rs/codex-api/src/requests` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/codex-api/src/requests`
- 目标类型：`DIR`
- 研究日期：`2026-03-20`
- 所属 crate：`codex-api`
- 目录文件：`mod.rs`、`headers.rs`、`responses.rs`

## 场景与职责

`codex-api/src/requests` 是 `codex-api` 中“请求组装辅助层”的薄模块，职责集中在两件事：

1. 统一构建 Responses API 的会话相关 header（`session_id`、`x-openai-subagent`）以及安全插入逻辑。
2. 在特定 provider（Azure Responses）场景下，把 `ResponseItem` 中默认不序列化的 `id` 回填到请求 JSON，保证历史 item 可追踪。

该目录本身不做网络 I/O，不直接发请求。它被 `ResponsesClient` 调用，随后由 `EndpointSession` 交给 `codex-client` 传输层执行（`codex-rs/codex-api/src/endpoint/responses.rs:69-149`，`codex-rs/codex-api/src/endpoint/session.rs:46-138`）。

边界上，本目录不负责：

- 认证头注入（`auth.rs` 负责，`codex-rs/codex-api/src/auth.rs:17-32`）。
- 重试/超时/SSE 解析（`EndpointSession` + `sse/responses.rs`，`codex-rs/codex-api/src/endpoint/session.rs:95-137`，`codex-rs/codex-api/src/sse/responses.rs:57-106`）。
- 业务策略（例如是否启用压缩、何时设置 store，由 `core` 构造请求时决定，`codex-rs/core/src/client.rs:682-773`）。

## 功能点目的

### 1) `mod.rs`：导出边界

- `headers` 仅 crate 内可见（`pub(crate)`），避免外部误用内部细节。
- `responses` 公开导出，主要为了 `Compression` 这类 endpoint 选项类型被上层使用（`codex-rs/codex-api/src/requests/mod.rs:1-2`，`codex-rs/codex-api/src/endpoint/responses.rs:31-38`）。

### 2) `headers.rs`：会话与子代理 header 规范化

- `build_conversation_headers(conversation_id)`：把会话 id 转为 `session_id` header（`codex-rs/codex-api/src/requests/headers.rs:5-11`）。
- `subagent_header(source)`：把 `SessionSource::SubAgent` 映射到 wire 字符串：
  - `Review -> review`
  - `Compact -> compact`
  - `MemoryConsolidation -> memory_consolidation`
  - `ThreadSpawn -> collab_spawn`
  - `Other(label) -> label`
  （`codex-rs/codex-api/src/requests/headers.rs:13-27`，协议枚举定义在 `codex-rs/protocol/src/protocol.rs:2269-2296`）。
- `insert_header`：对 header 名和值做 parse 校验，非法值静默丢弃而不是 panic（`codex-rs/codex-api/src/requests/headers.rs:30-36`）。

### 3) `responses.rs`：压缩选项与 Azure item-id 兼容

- `Compression { None, Zstd }`：是 `codex-api` 层对传输压缩枚举的轻量封装，后续映射到 `codex_client::RequestCompression`（`codex-rs/codex-api/src/requests/responses.rs:4-9`，`codex-rs/codex-api/src/endpoint/responses.rs:122-125`）。
- `attach_item_ids(payload_json, original_items)`：遍历 JSON `input` 和原始 `ResponseItem`，把可识别 item 的 `id` 回填到 JSON 对象（`codex-rs/codex-api/src/requests/responses.rs:11-36`）。

其目的来自协议现实：`ResponseItem` 多个变体的 `id` 字段默认 `skip_serializing`，直接 `serde_json::to_value` 会丢失 id（`codex-rs/protocol/src/models.rs:295-420`）。该函数只在 Azure + `request.store=true` 时启用（`codex-rs/codex-api/src/endpoint/responses.rs:84-86`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. 关键流程

#### A1. HTTP Responses 请求构造链路

1. `core` 侧构建 `ResponsesApiRequest` 与 `ResponsesOptions`：
   - `store` 基于 provider 是否 Azure 决定。
   - `compression` 基于 feature + auth 类型 + provider 决定。
   （`codex-rs/core/src/client.rs:682-773`，`codex-rs/core/src/client.rs:969-977`）
2. `ResponsesClient::stream_request` 序列化请求体（`codex-rs/codex-api/src/endpoint/responses.rs:82-83`）。
3. 若 `store && is_azure_responses_endpoint`，调用 `attach_item_ids` 回填 `input[*].id`（`codex-rs/codex-api/src/endpoint/responses.rs:84-86`）。
4. 组装 headers：
   - `x-client-request-id`（来自 `conversation_id`）
   - `session_id`（`build_conversation_headers`）
   - `x-openai-subagent`（`subagent_header`）
   （`codex-rs/codex-api/src/endpoint/responses.rs:88-95`）
5. `stream()` 把 `Compression` 映射到 transport 层 `RequestCompression`，并设置 `Accept: text/event-stream`（`codex-rs/codex-api/src/endpoint/responses.rs:122-140`）。
6. `EndpointSession::stream_with` 执行请求并注入认证（`codex-rs/codex-api/src/endpoint/session.rs:123-134`，`codex-rs/codex-api/src/auth.rs:17-32`）。
7. `spawn_response_stream` 从响应头提取 `x-codex-turn-state` 等元数据并进入 SSE 事件流（`codex-rs/codex-api/src/sse/responses.rs:63-105`）。

#### A2. 压缩链路

- `requests::responses::Compression` -> `codex_client::RequestCompression`（`codex-rs/codex-api/src/endpoint/responses.rs:122-125`）。
- 传输层执行 zstd 压缩并写入 `Content-Encoding: zstd`（`codex-rs/codex-client/src/transport.rs:63-104`）。
- 压缩能力由 core feature `EnableRequestCompression` 开关进入 `ModelClient`（`codex-rs/core/src/features.rs:143-144`，`codex-rs/core/src/codex.rs:1817-1824`）。

#### A3. 子代理来源映射链路

- 协议来源：`SessionSource::SubAgent(SubAgentSource::...)`（`codex-rs/protocol/src/protocol.rs:2269-2296`）。
- API 映射：`subagent_header()` 产出 wire header 字符串（`codex-rs/codex-api/src/requests/headers.rs:13-27`）。
- 核验测试：
  - `codex-api` 侧 header + Azure id 回填：`codex-rs/codex-api/tests/clients.rs:287-360`
  - `core` 侧端到端 header 透传：`codex-rs/core/tests/responses_headers.rs:26-136`、`138-200`

### B. 关键数据结构

1. `ResponsesApiRequest`：请求主体，含 `input: Vec<ResponseItem>`、`store`、`stream`、`prompt_cache_key` 等（`codex-rs/codex-api/src/common.rs:153-171`）。
2. `ResponseItem`：多变体输入项，多个 `id` 字段为 `skip_serializing`（`codex-rs/protocol/src/models.rs:295-420`）。
3. `ResponsesOptions`：transport 侧选项（`conversation_id/session_source/extra_headers/compression/turn_state`）（`codex-rs/codex-api/src/endpoint/responses.rs:31-38`）。
4. `Compression`：requests 层枚举（`codex-rs/codex-api/src/requests/responses.rs:4-9`）。

### C. 协议与 header 约定

1. `session_id`：会话关联 id，来自 `conversation_id`，用于后端会话归因。
2. `x-client-request-id`：同样取 `conversation_id`，用于请求链路追踪。
3. `x-openai-subagent`：标注当前请求来源子代理类型（review/compact/memory/collab_spawn/custom label）。
4. `Content-Encoding: zstd`：仅当 compression 启用时写入。

相关代码：
- `codex-rs/codex-api/src/requests/headers.rs:5-36`
- `codex-rs/codex-api/src/endpoint/responses.rs:88-140`
- `codex-rs/codex-client/src/transport.rs:63-104`

### D. 可复现实验/排查命令

1. 定位调用链：
   - `rg -n "build_conversation_headers|subagent_header|attach_item_ids|Compression" codex-rs`
2. 查看协议对象定义：
   - `rg -n "enum SessionSource|enum SubAgentSource|enum ResponseItem" codex-rs/protocol/src`
3. 运行相关测试：
   - `cargo test -p codex-api --test clients`
   - `cargo test -p codex-core --test responses_headers`
   - `cargo test -p codex-core --test request_compression`

## 关键代码路径与文件引用

### 1) 目标目录内

1. `codex-rs/codex-api/src/requests/mod.rs`
2. `codex-rs/codex-api/src/requests/headers.rs`
3. `codex-rs/codex-api/src/requests/responses.rs`

### 2) 直接调用方（上游）

1. `codex-rs/codex-api/src/endpoint/responses.rs`：requests 模块的直接消费方。
2. `codex-rs/core/src/client.rs`：构造 `ResponsesOptions`/`ResponsesApiRequest`，决定 `conversation_id`、`session_source`、`compression`、`store`。
3. `codex-rs/core/src/codex.rs`：把 `EnableRequestCompression` feature 注入 `ModelClient`。

### 3) 被调用方与依赖上下文

1. `codex-rs/codex-api/src/endpoint/session.rs`：执行请求、重试、telemetry。
2. `codex-rs/codex-api/src/auth.rs`：认证头注入。
3. `codex-rs/codex-api/src/provider.rs`：Azure endpoint 判定与 URL 组装。
4. `codex-rs/codex-client/src/request.rs`、`codex-rs/codex-client/src/transport.rs`：请求压缩落地。
5. `codex-rs/protocol/src/models.rs`、`codex-rs/protocol/src/protocol.rs`：`ResponseItem` 与 `SessionSource` 协议定义。

### 4) 测试路径

1. `codex-rs/codex-api/tests/clients.rs`：验证 path/auth/retry/Azure item-id+header。
2. `codex-rs/core/tests/responses_headers.rs`：验证 `x-openai-subagent` 透传。
3. `codex-rs/core/tests/suite/request_compression.rs`：验证 zstd 压缩策略。
4. `codex-rs/core/src/client_tests.rs`：验证 `SessionSource::Other` label 映射一致性。

### 5) 配置、脚本、文档

1. 文档：`codex-rs/codex-api/README.md`（定义 `ResponsesOptions` 是 header/transport 选项入口）。
2. 配置：`EnableRequestCompression` feature（`codex-rs/core/src/features.rs:143-144`）+ `ModelClient` 注入（`codex-rs/core/src/codex.rs:1817-1824`）。
3. 脚本：`codex-api/src/requests` 无专属运维脚本；本次流程使用仓库脚本 `.ops/generate_daily_research_todo.sh` 更新研究待办。

## 依赖与外部交互

### 1) 内部依赖

- `codex-protocol`：提供 `ResponseItem`、`SessionSource/SubAgentSource`。
- `codex-client`：负责实际 HTTP/SSE 传输与 zstd 压缩。
- `codex-api::provider`：用于 Azure endpoint 检测，决定是否执行 item-id 回填。

### 2) 外部交互

- 外部 API：OpenAI/Codex/Azure Responses endpoint（HTTP POST `/responses`）。
- 外部可见 header：`session_id`、`x-client-request-id`、`x-openai-subagent`、`content-encoding`。
- 对后端行为的影响：
  - `session_id` 与 `x-client-request-id` 影响会话归因和请求追踪。
  - `x-openai-subagent` 影响来源标记与统计维度。
  - Azure 场景下 `input[*].id` 回填影响历史项关联能力。

## 风险、边界与改进建议

### 风险与边界

1. `insert_header` 失败静默丢弃：当 `conversation_id` 或 `SubAgentSource::Other(label)` 含非法 header 字符时，请求不会报错但 header 缺失，排障成本高（`codex-rs/codex-api/src/requests/headers.rs:30-36`）。
2. `attach_item_ids` 使用 `zip`：当 `payload_json.input` 与 `original_items` 长度不一致时，多余元素不会处理，也无告警（`codex-rs/codex-api/src/requests/responses.rs:19`）。
3. 子代理映射逻辑在 `core` 和 `codex-api` 各有一份：当前字符串一致，但长期存在漂移风险（`codex-rs/core/src/client.rs:453-470` vs `codex-rs/codex-api/src/requests/headers.rs:13-27`）。
4. Azure id 回填只覆盖部分 `ResponseItem` 变体；新增含 id 变体时若忘记补充，会出现行为回退。

### 改进建议

1. 在 `insert_header` 增加 `trace!/debug!`（至少在解析失败时记录 header 名），提升线上可观测性。
2. 在 `attach_item_ids` 中增加长度不一致监控日志（或 debug assert in test），尽早暴露序列化漂移。
3. 把 subagent 映射提取为共享函数（例如放在 `codex-protocol` 或 `codex-api` 公共 helper），避免双实现。
4. 为 `attach_item_ids` 增加更细粒度单元测试：
   - 空 id 跳过
   - 非对象 JSON 项跳过
   - 长度不一致
   - 新增 `ResponseItem` 变体回归
5. 在 `codex-api/README.md` 增补 `session_id/x-client-request-id/x-openai-subagent` 的语义说明，降低调用方误用概率。
