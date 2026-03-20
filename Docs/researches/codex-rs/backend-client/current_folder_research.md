# DIR `codex-rs/backend-client` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/backend-client`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 关联 crate：`codex-backend-client`

## 场景与职责

`codex-rs/backend-client` 是仓库内用于访问 Codex/ChatGPT 后端“任务与配额相关 REST 接口”的轻量 HTTP 适配层，职责是：

1. 统一路径风格与主机归一化
- 自动把 ChatGPT 主机（`https://chatgpt.com` / `https://chat.openai.com`）归一化为 `.../backend-api`，并据此切换路径风格：
  - Codex API 风格：`/api/codex/...`
  - ChatGPT backend 风格：`/wham/...`
- 关键实现：`PathStyle`、`Client::new`、`PathStyle::from_base_url`。

2. 提供最小但稳定的后端能力面
- 读配额：`get_rate_limits_many` / `get_rate_limits`
- 任务列表：`list_tasks`
- 任务详情：`get_task_details` / `get_task_details_with_body`
- sibling turns：`list_sibling_turns`
- 云端 requirements：`get_config_requirements_file`
- 创建任务：`create_task`

3. 向上游模块输出“可消费的领域模型”
- 对配额接口，输出 `codex_protocol::RateLimitSnapshot`，而不是直接暴露 OpenAPI 原始结构。
- 对任务详情接口，放弃质量较差的生成模型，改用手写结构（`types.rs`）并提供 `CodeTaskDetailsResponseExt` 便捷提取能力。

4. 认证与请求头注入
- 封装 Bearer Token、User-Agent、`ChatGPT-Account-Id` 注入。
- `from_auth` 可直接从 `CodexAuth` 构造客户端，减少调用方重复样板代码。

## 功能点目的

### 1) 双路径兼容：Codex API 与 ChatGPT backend-api
目的：让同一套上层逻辑同时支持企业/内部 Codex 风格地址与 ChatGPT 后端地址，避免调用方分叉。

- 路径选择核心：只要 `base_url` 包含 `/backend-api`，即走 `wham`；否则走 `/api/codex`。
- 典型端点映射：
  - usage：`/api/codex/usage` vs `/wham/usage`
  - tasks list：`/api/codex/tasks/list` vs `/wham/tasks/list`
  - task details：`/api/codex/tasks/{id}` vs `/wham/tasks/{id}`
  - config requirements：`/api/codex/config/requirements` vs `/wham/config/requirements`

### 2) 任务详情可用性增强（手写模型 + 提取 trait）
目的：对后端任务详情中的“多形态内容字段”做稳健解码，给上层直接可用的 diff、消息、prompt、错误文本。

- `CodeTaskDetailsResponseExt` 提供：
  - `unified_diff()`：优先 `current_diff_task_turn`，兜底 `current_assistant_turn`
  - `assistant_text_messages()`：提取 assistant message + worklog 文本
  - `user_text_prompt()`：拼接用户输入
  - `assistant_error_message()`：组合 code/message

### 3) 配额结构映射与计划类型归一
目的：把后端 OpenAPI 的 `double_option` 嵌套结构、窗口秒数、内部 plan 值，转换为协议层稳定结构，供 UI 与 app-server 统一消费。

- `RateLimitStatusPayload` -> `Vec<RateLimitSnapshot>`
- 秒转分钟使用上取整（`(seconds + 59) / 60`）
- plan 映射把 `guest/free_workspace/quorum/k12` 归到 `Unknown`

### 4) 细粒度错误语义（requirements 读取）
目的：让云端 requirements 加载逻辑能区分 401 与其他失败，支持“授权失败恢复/重试策略”。

- 仅 `get_config_requirements_file` 走 `RequestError`（保留 `status`）
- `RequestError::is_unauthorized()` 被 `cloud-requirements` 用于 fail-closed 与 auth 恢复分支

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. 客户端构造与请求头流程

1. 构造流程
- `Client::new(base_url)`
  - 去尾 `/`
  - ChatGPT 域名自动补 `/backend-api`
  - 通过 `codex_client::build_reqwest_client_with_custom_ca` 构造 HTTP client（统一支持自定义 CA）
- `Client::from_auth(base_url, auth)`
  - 读取 token
  - 注入 `get_codex_user_agent()`
  - 若有 account_id 注入 `ChatGPT-Account-Id`

2. headers 组成
- `User-Agent`：优先调用方设置值，否则默认 `codex-cli`
- `Authorization: Bearer ...`：若有 token
- `ChatGPT-Account-Id`：若有 account_id

### B. 通用请求执行与解码

1. `exec_request`
- 发送请求后读取 `status/content-type/body`
- 非 2xx 直接 `bail!`，错误消息包含 method/url/ct/body，便于上层日志定位

2. `exec_request_detailed`
- 与上类似，但失败返回结构化 `RequestError::UnexpectedStatus`，保留 `status`

3. `decode_json<T>`
- 统一 JSON 反序列化与错误封装（包含 url/ct/body）

### C. 业务 API 流程

1. 配额读取
- `get_rate_limits_many`：GET usage -> 反序列化 `RateLimitStatusPayload` -> `rate_limit_snapshots_from_payload`
- `get_rate_limits`：在多 limit 中优先取 `limit_id == codex`，否则取首项

2. 任务列表
- `list_tasks(limit, task_filter, environment_id, cursor)` 按需拼 query

3. 任务详情
- `get_task_details_with_body` 返回 `(parsed, raw_body, content_type)`
- 设计意图：上游可在强类型失败或信息不足时使用 raw body 做兜底解析/报错

4. sibling turns
- `list_sibling_turns(task_id, turn_id)` 返回 `TurnAttemptsSiblingTurnsResponse { sibling_turns: Vec<HashMap<...>> }`

5. requirements 文件
- `get_config_requirements_file` 使用 detailed error；上游据此判断 401

6. 创建任务
- `create_task` 发送 JSON body 到 `/tasks`
- 响应 ID 提取规则：优先 `task.id`，兜底顶层 `id`

### D. 关键数据结构与协议映射

1. OpenAPI 生成模型
- 来自 `codex-backend-openapi-models`，例如：
  - `RateLimitStatusPayload`
  - `ConfigFileResponse`
  - `PaginatedListTaskListItem`
- 其中 rate-limit 字段大量使用 `Option<Option<...>>`（`serde_with::double_option`）

2. 手写任务详情模型（`types.rs`）
- `CodeTaskDetailsResponse` + `Turn/TurnItem/ContentFragment/...`
- `deserialize_vec` 让缺失数组字段自动归一为空 vec，减少上层分支判断
- `ContentFragment` 支持结构化文本片段与纯字符串片段

3. 协议层目标模型
- 配额最终落到 `codex_protocol::protocol::{RateLimitSnapshot, RateLimitWindow, CreditsSnapshot}`
- plan 类型映射到 `codex_protocol::account::PlanType`

### E. 关键命令/端点清单

- `GET {base}/api/codex/usage` / `GET {base}/wham/usage`
- `GET {base}/api/codex/tasks/list` / `GET {base}/wham/tasks/list`
- `GET {base}/api/codex/tasks/{task_id}` / `GET {base}/wham/tasks/{task_id}`
- `GET {base}/api/codex/tasks/{task}/turns/{turn}/sibling_turns` / `GET {base}/wham/tasks/{task}/turns/{turn}/sibling_turns`
- `GET {base}/api/codex/config/requirements` / `GET {base}/wham/config/requirements`
- `POST {base}/api/codex/tasks` / `POST {base}/wham/tasks`

## 关键代码路径与文件引用

### 目录内（目标目录）

1. crate 出口
- `codex-rs/backend-client/src/lib.rs:1-11`
- 暴露 `Client`、`RequestError`、任务详情扩展 trait 与主要数据类型。

2. 客户端核心
- `codex-rs/backend-client/src/client.rs:82-98`：`PathStyle` 判定
- `codex-rs/backend-client/src/client.rs:111-134`：base_url 归一化 + client 构造
- `codex-rs/backend-client/src/client.rs:136-145`：`from_auth`
- `codex-rs/backend-client/src/client.rs:169-189`：请求头构造
- `codex-rs/backend-client/src/client.rs:191-237`：请求执行/详细错误
- `codex-rs/backend-client/src/client.rs:257-393`：对外 API
- `codex-rs/backend-client/src/client.rs:395-494`：rate-limit 映射逻辑
- `codex-rs/backend-client/src/client.rs:497-...`：rate-limit 映射测试

3. 任务详情手写模型
- `codex-rs/backend-client/src/types.rs:16-27`：任务详情顶层
- `codex-rs/backend-client/src/types.rs:49-116`：turn/item/content/error 结构
- `codex-rs/backend-client/src/types.rs:118-258`：文本与 diff 提取逻辑
- `codex-rs/backend-client/src/types.rs:260-305`：`CodeTaskDetailsResponseExt`
- `codex-rs/backend-client/src/types.rs:321-376`：fixture 驱动单测

4. Bazel 数据文件声明
- `codex-rs/backend-client/BUILD.bazel:3-7`
- `compile_data = glob(["tests/fixtures/**"])` 保证 Bazel 编译/测试下 `include_str!` 可访问 fixture。

5. 测试 fixture
- `codex-rs/backend-client/tests/fixtures/task_details_with_diff.json`
- `codex-rs/backend-client/tests/fixtures/task_details_with_error.json`

### 调用方（上游）

1. Cloud tasks 客户端（最重度调用）
- `codex-rs/cloud-tasks-client/src/http.rs:17-18`：依赖 backend client + ext trait
- `codex-rs/cloud-tasks-client/src/http.rs:145-177`：list_tasks
- `codex-rs/cloud-tasks-client/src/http.rs:180-246`：summary（结合 raw body）
- `codex-rs/cloud-tasks-client/src/http.rs:261-313`：messages/task_text
- `codex-rs/cloud-tasks-client/src/http.rs:316-377`：create_task
- `codex-rs/cloud-tasks-client/src/http.rs:399-413`：list_sibling_turns
- `codex-rs/cloud-tasks-client/src/http.rs:427-558`：apply 前读取 diff

2. 云端 requirements
- `codex-rs/cloud-requirements/src/lib.rs:205-244`
- 通过 `get_config_requirements_file` + `RequestError.status/is_unauthorized` 驱动重试与 auth 恢复策略。

3. app-server 账户配额 RPC
- `codex-rs/app-server/src/codex_message_processor.rs:1466-1533`
- `account/rateLimits/read` 通过 backend-client 拉取并回传给 app-server 协议。

4. TUI 配额刷新
- `codex-rs/tui/src/chatwidget.rs:9489-9502`
- 登录后异步刷新配额数据，失败时降级为空列表。

### 被调用方（下游）

1. OpenAPI 模型 crate
- `codex-rs/codex-backend-openapi-models/src/models/mod.rs:1-44`
- `codex-rs/codex-backend-openapi-models/src/models/rate_limit_status_payload.rs:15-84`
- `codex-rs/codex-backend-openapi-models/src/models/code_task_details_response.rs:15-42`

2. 公共 HTTP 基建
- `codex-rs/codex-client/src/custom_ca.rs:179-183`
- `codex-rs/core/src/default_client.rs:123-147`（UA）
- `codex-rs/core/src/auth.rs:253-266`（token/account_id）

### 相关配置、测试、文档、脚本

1. 配置来源
- `chatgpt_base_url`（由 app-server/cloud-tasks 等上层配置注入 backend-client）

2. 测试证据（跨目录）
- `codex-rs/backend-client/src/client.rs` 中 rate-limit 映射单测
- `codex-rs/backend-client/src/types.rs` + fixture 单测
- `codex-rs/app-server/tests/suite/v2/rate_limits.rs:139-145` 校验 `/api/codex/usage` + `chatgpt-account-id` header
- `codex-rs/app-server/tests/suite/v2/thread_start.rs:334-340`、`thread_resume.rs:1425-1431`、`thread_fork.rs:228-234` 校验 `/backend-api/wham/config/requirements` 路径

3. 文档契约
- `codex-rs/app-server/README.md:1241-1260` 描述 `account/rateLimits/read` 与通知语义

4. 脚本/构建
- 本目录无独立脚本；构建侧依赖 Cargo + Bazel (`BUILD.bazel`)。

## 依赖与外部交互

### 内部依赖

1. `codex-backend-openapi-models`
- 提供生成的后端 DTO，backend-client 在其上做“最小手工修正”（任务详情手写 + 配额映射）。

2. `codex-client`
- 提供带自定义 CA 策略的 reqwest client 构建能力；确保企业代理/自签 CA 场景可用。

3. `codex-core`
- `CodexAuth`（token/account_id）
- `get_codex_user_agent`（统一 UA 规范）

4. `codex-protocol`
- 输出统一的 `RateLimitSnapshot` / `PlanType`，供 UI 与 app-server 协议层复用。

### 外部交互

1. HTTP REST（reqwest + rustls）
- 与 ChatGPT/Codex 后端交互，所有接口均为 JSON over HTTPS。

2. 鉴权与身份
- `Authorization: Bearer ...`
- 可选 `ChatGPT-Account-Id`（多 workspace/企业场景关键）

3. 内容类型与错误透传
- 失败信息包含 `status/content-type/body`，便于识别 HTML 错页、网关错误、JSON 结构漂移。

## 风险、边界与改进建议

### 已识别风险

1. 路径风格判定依赖字符串包含关系，策略较脆弱
- 现状：`contains("/backend-api")` 判定 ChatGPT 风格。
- 风险：若出现非标准代理路径或多段前缀，可能误判。
- 建议：抽象成共享 URL/path-style 解析模块（与 `cloud-tasks` 的环境接口路径选择统一）。

2. `list_tasks` 的 `task_filter`/query key 为硬编码字符串
- 风险：后端字段调整时，编译期无保护。
- 建议：对 query 参数建立 typed 参数对象或常量集中定义。

3. 任务详情仍为“半手写半兜底”
- 优点：比生成模型可用。
- 风险：后端字段漂移时，`Vec<HashMap<String, Value>>` 与字符串比较可能静默降级。
- 建议：
  - 为 `turn_status`、`item.type` 建 enum 反序列化并保留 Unknown；
  - 为 `ContentFragment` 增加更多结构类型覆盖；
  - 增加异常 payload fixture（缺字段、错误类型、空数组/null 混合）回归测试。

4. `get_rate_limits` 依赖 `snapshots[0]` 兜底
- 现由调用方保证非空；但函数自身若被单独调用且后端返回空列表会 panic（索引访问）。
- 建议：在 `get_rate_limits` 内显式检查空列表并返回 error，避免隐式前置条件。

5. 失败 body 直接拼入错误字符串
- 优点：定位快。
- 风险：日志可能包含敏感信息或超长内容。
- 建议：统一错误脱敏与长度截断策略（例如限制 body 长度并对 token 模式做 mask）。

6. Header 名大小写/创建方式分散
- 当前使用 `HeaderName::from_bytes(b"ChatGPT-Account-Id")`，不同模块有重复实现。
- 建议：把 `ChatGPT-Account-Id` header 常量统一沉淀到共享模块，减少多处复制。

### 边界说明

1. `backend-client` 不负责：
- 任务 patch 的 git apply（在 `cloud-tasks-client`）
- 云端 requirements 缓存、重试与 auth 恢复策略（在 `cloud-requirements`）
- app-server RPC 协议封装（在 `app-server` / `app-server-protocol`）

2. 本目录没有独立 README 或脚本
- 行为契约主要体现在调用方测试与 app-server README 的 account/rateLimits 文档。

### 优先级建议（可落地）

1. 高优先
- 为 `get_rate_limits` 增加空列表安全返回（避免潜在 panic）。
- 新增 `PathStyle` 单测（ChatGPT 域名补全、`/backend-api` 判定、尾斜杠处理）。

2. 中优先
- 抽取共享的 base_url/path-style 规范化工具，复用到 `cloud-tasks` 的 env 检测路径构造，降低路径分叉风险。

3. 中低优先
- 扩展 `types.rs` fixture：
  - `worklog.parts` 纯字符串/对象混合
  - 空 `content_type`
  - 缺失 `current_*_turn`
  - `error` 仅 code 或仅 message

4. 低优先
- 为 `RequestError` 加入可选 body 截断显示策略，平衡可观测性与安全性。
