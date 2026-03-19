# DIR `codex-rs/app-server/tests/common` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/app-server/tests/common`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 对应 crate：`app_test_support`（`codex-rs/app-server/tests/common/Cargo.toml`）
- 上层主要调用方：`codex-rs/app-server/tests/suite/**/*.rs`
- 下层主要依赖：`codex-app-server` 二进制、`codex-app-server-protocol`、`codex-core`、`core_test_support::responses`

## 场景与职责

`codex-rs/app-server/tests/common` 是 `codex-app-server` 集成测试的“测试基础设施层”。它不直接断言业务行为，而是为测试套件提供可复用的以下能力：

1. 启动与驱动真实 app-server 进程
- `McpProcess` 通过 `codex_utils_cargo_bin::cargo_bin("codex-app-server")` 启动被测二进制，并以 JSON-RPC 行协议驱动（`mcp_process.rs:107-166`）。
- 支持初始化握手、发送 typed request、读取 response/error/notification/request，以及消息缓冲与选择性匹配（`mcp_process.rs:183-214`, `974-1133`）。

2. 构造可控的模型端行为
- 用 wiremock 提供 `/v1/responses` 的 SSE 顺序响应（`mock_model_server.rs`），支撑 turn/tool 审批、中断、动态工具、realtime 等场景。
- `responses.rs` 提供 tool-call 级别的 SSE 片段生成（`shell_command`、`exec_command`、`request_user_input`、`request_permissions`、`apply_patch`）。

3. 构造运行时状态夹具（fixture）
- 生成 `config.toml`、`auth.json`、`models_cache.json`、`sessions/.../rollout-*.jsonl`，让测试在本地临时目录中直接复现 server 启动与恢复路径。

4. 收敛测试样板代码
- `lib.rs` 对外统一 re-export 常用 helper（`McpProcess`、`write_chatgpt_auth`、`create_fake_rollout` 等），使 `suite` 层测试聚焦业务断言而不是搭建细节（`lib.rs:10-44`）。

## 功能点目的

按模块拆解该目录的功能目的：

1. `mcp_process.rs`
- 目的：把“启动真实进程 + JSON-RPC 双向消息驱动 + 异步时序处理”标准化。
- 提供近 70 个 `send_*_request` 方法覆盖 app-server 主要 RPC（thread/turn/account/plugin/config/fs/realtime/command_exec/fuzzy search 等，见 `mcp_process.rs:257-888`）。
- 提供 `interrupt_turn_and_wait_for_aborted` 处理长运行 turn 的确定性清理，降低 nextest `LEAK` 波动（`632-679`）。

2. `mock_model_server.rs`
- 目的：为 `/responses` 提供按调用序列或固定文本的可预测 SSE。
- `create_mock_responses_server_sequence` 带 `.expect(num_calls)`，用于严格请求次数断言。
- `create_mock_responses_server_sequence_unchecked` 取消次数约束，适合存在竞态/额外重试的场景。

3. `responses.rs`
- 目的：快速合成“模型发起工具调用”的 SSE 数据包。
- 示例：
  - `create_shell_command_sse_response` 生成 `shell_command` 函数调用项。
  - `create_request_user_input_sse_response` / `create_request_permissions_sse_response` 驱动 server request 往返场景。
  - `create_apply_patch_sse_response` 走 heredoc 形式的 patch tool call。

4. `rollout.rs`
- 目的：写入最小可恢复的 rollout JSONL，覆盖 `thread/list|read|resume|fork` 历史读取路径。
- 关键输出路径规则：`CODEX_HOME/sessions/YYYY/MM/DD/rollout-<ts>-<thread>.jsonl`（`rollout_path`, `14-22`）。
- 会写入 `session_meta` + `response_item(user)` + `event_msg(user_message)` 三行最小集合。

5. `auth_fixtures.rs`
- 目的：在测试中构造 ChatGPT 登录态，无需真实 OAuth。
- 通过 `ChatGptAuthFixture` + `ChatGptIdTokenClaims` 构造 claim，序列化伪 JWT，再调用 `codex_core::auth::save_auth` 写入 `auth.json`（`145-168`）。

6. `models_cache.rs`
- 目的：提前写入 `models_cache.json`，避免 `ModelsManager` 在测试中走外网刷新。
- 使用 `all_model_presets()` 转 `ModelInfo`，并填充 `fetched_at/client_version/models` 字段。

7. `config.rs`
- 目的：生成带 mock provider 的 `config.toml`，统一特性开关、provider、压缩阈值等参数注入。
- 典型用于 compaction / windowsSandbox / requires_openai_auth 路径。

8. `analytics_server.rs`
- 目的：启动本地采集端点 `/codex/analytics-events/events` 并返回 200，用于 plugin install/uninstall 事件上报测试。

9. `lib.rs`
- 目的：对以上模块的 API 统一出口，并提供 `to_response<T>` 把 JSONRPCResponse 的 `result` 解码为 typed response（`43-47`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) `McpProcess` 的进程与协议驱动模型

1. 进程启动
- `new_with_env` 会：
  - 定位 `codex-app-server` 可执行文件。
  - 绑定 stdin/stdout/stderr 管道。
  - 设定 `CODEX_HOME`、`RUST_LOG`，并显式移除 `CODEX_INTERNAL_ORIGINATOR_OVERRIDE_ENV_VAR`（除非测试通过 `env_overrides` 再注入）。
- stderr 被转发到测试 stderr，便于失败时定位（`146-153`）。

2. 初始化握手
- `initialize*` 发送 `initialize` 请求并校验回包 `id`。
- 成功后自动发送 `ClientNotification::Initialized`，这与 README 的“initialize -> initialized”握手要求一致。

3. 请求发送模型
- `next_request_id: AtomicI64` 自增生成 request id（`909-918`）。
- 所有 typed `send_*` 先 `serde_json::to_value(params)` 再调用 `send_request(method, params)`。
- 覆盖的方法字符串与协议定义基本一一对应，例：
  - `thread/start`, `turn/start`, `command/exec`, `config/read`, `fs/readFile`, `plugin/install`, `app/list`, `model/list`。
  - 也兼容 v1/遗留：`getAuthStatus`, `getConversationSummary`, `fuzzyFileSearch`。

4. 流读取与消息缓冲
- `read_stream_until_message(predicate)` 会持续读 stdout，每次命中 predicate 即返回；未命中则压入 `pending_messages`。
- 后续读取先扫描缓冲（`take_pending_message`），避免并发通知打乱测试流程。
- 这让测试可先读取 response，再补读 notification/request，而不丢消息。

5. 明确清理策略
- Drop 时同步执行：关闭 stdin -> 短暂等待 -> `start_kill` -> `try_wait` 轮询，减少 child 进程残留导致的 flaky（`1149-1190`）。

### 2) SSE 模拟链路（`responses.rs` + `mock_model_server.rs` + `core_test_support::responses`）

1. 数据格式
- 底层由 `core_test_support::responses::sse(...)` 生成 `event: ...\ndata: ...\n\n` 的 SSE 文本。
- `ev_response_created / ev_function_call / ev_assistant_message / ev_completed` 组合成一轮模型输出。

2. 顺序响应
- `create_mock_responses_server_sequence` 内部 responder 用 `AtomicUsize` 计数，按请求序号返回第 N 条 SSE。
- 越界会 panic（用于尽早暴露“请求次数比预期多”）。

3. 工具调用构造
- `create_shell_command_sse_response` 会把 `Vec<String>` 命令通过 `shlex::try_join` 转 shell-safe 字符串，再放进 tool-call 参数 JSON。
- `create_exec_command_sse_response` 根据平台选择 `/bin/sh -c echo hi` 或 `cmd.exe /d /c echo hi`。
- `create_request_user_input_sse_response` 和 `create_request_permissions_sse_response` 分别驱动 `item/tool/requestUserInput` 与 `item/permissions/requestApproval` 相关 server request 测试。

### 3) Fixture 文件的协议契约

1. `config.toml`（`config.rs`）
- 输出关键字段：`model`、`approval_policy`、`sandbox_mode`、`compact_prompt`、`model_auto_compact_token_limit`、`model_provider`。
- 输出 `[model_providers.<id>]` 块，固定 `wire_api="responses"`、重试为 0，并按 `requires_openai_auth` 决定是否写入认证要求。

2. `auth.json`（`auth_fixtures.rs`）
- 通过 `AuthDotJson` 写入，`auth_mode = Chatgpt`，并携带 token + claims（email/plan/account/user）。
- claim 被编码进伪 JWT payload 的 `https://api.openai.com/auth` 命名空间。

3. `models_cache.json`（`models_cache.rs`）
- 字段：`fetched_at`、`etag`、`client_version`、`models`。
- 与 `codex_core::models_manager::MODEL_CACHE_FILE` 读取格式一致。

4. rollout JSONL（`rollout.rs`）
- 第一行必须含 `session_meta`，并填充 `SessionMetaLine { meta, git }`。
- 文件名与目录层级遵循 core rollout scanner 约定（`sessions/YYYY/MM/DD/rollout-...`）。
- `create_fake_rollout_with_source` 额外支持指定 `SessionSource`，用于 `thread/list` 的 source 过滤测试。

### 4) 调用侧（`tests/suite`）真实组合模式

1. 高频用法
- 从全套件统计看，最常见是：
  - `send_thread_start_request`（93 次）
  - `send_turn_start_request`（89 次）
  - `read_stream_until_response_message`（365 次）
  - `read_stream_until_notification_message`（153 次）
- 说明 `McpProcess` 已成为 app-server 集成测试的主驱动抽象。

2. 典型场景映射
- `v2/turn_start.rs`：使用 sequence SSE + tool SSE helper 验证 turn/item 生命周期与审批闭环。
- `v2/thread_list.rs`：使用 rollout helpers 构造历史会话，验证分页、过滤、排序、archived。
- `v2/account.rs`：使用 `write_chatgpt_auth` + `write_models_cache` 验证 `account/read` 与 token 登录。
- `v2/compaction.rs`：使用 `write_mock_responses_config_toml` 注入 compact 参数并验证 context compaction item。
- `v2/request_user_input.rs` / `v2/request_permissions.rs`：使用对应 SSE helper 验证 `serverRequest/resolved` 先于 `turn/completed`。
- `v2/plugin_install.rs`：使用 `start_analytics_events_server` 验证埋点上报。

### 5) 协议对齐关系（`app-server-protocol`）

- `mcp_process.rs` 中 method 字符串与 `app-server-protocol/src/protocol/common.rs` 的 `client_request_definitions!` 对齐。
- 关键注意点：
  - v2 命名大多是资源化路径（如 `thread/start`, `config/read`）。
  - 仍保留部分 legacy 方法（`getAuthStatus`, `getConversationSummary`, `fuzzyFileSearch`）用于兼容/回归测试。

### 6) 命令与执行约定

常用本地执行路径：

1. 编译/运行被测服务
- 由 `McpProcess` 内部调用 `cargo_bin("codex-app-server")` 解析绝对路径并启动进程。

2. 模型 mock
- 通过 wiremock 接收 `POST .../responses`（及部分场景 `/responses/compact`, `/models`）。

3. Websocket 模拟
- realtime 场景依赖 `core_test_support::responses::start_websocket_server`，以队列化 request->event 方式回放后端行为。

## 关键代码路径与文件引用

### 目录内核心文件

1. `codex-rs/app-server/tests/common/lib.rs`
- re-export 门面与 `to_response`。

2. `codex-rs/app-server/tests/common/mcp_process.rs`
- `McpProcess` 定义与完整 JSON-RPC 发送/读取框架。
- 关键区段：
  - 启动与 env 覆盖：`98-166`
  - initialize 握手：`168-249`
  - request API facade：`252-888`
  - 流读取/缓冲：`974-1133`
  - 资源清理 Drop：`1149-1190`

3. `codex-rs/app-server/tests/common/mock_model_server.rs`
- 顺序/重复 SSE mock server。

4. `codex-rs/app-server/tests/common/responses.rs`
- tool-call SSE 构造器集合。

5. `codex-rs/app-server/tests/common/config.rs`
- mock provider 配置写入器。

6. `codex-rs/app-server/tests/common/rollout.rs`
- rollout 目录布局与 JSONL fixture。

7. `codex-rs/app-server/tests/common/auth_fixtures.rs`
- ChatGPT auth fixture 与 JWT claims 编码。

8. `codex-rs/app-server/tests/common/models_cache.rs`
- models cache fixture。

9. `codex-rs/app-server/tests/common/analytics_server.rs`
- analytics mock endpoint。

### 上游调用路径（测试侧）

1. 聚合入口
- `codex-rs/app-server/tests/all.rs`
- `codex-rs/app-server/tests/suite/mod.rs`
- `codex-rs/app-server/tests/suite/v2/mod.rs`

2. 代表性调用文件
- `codex-rs/app-server/tests/suite/auth.rs`
- `codex-rs/app-server/tests/suite/conversation_summary.rs`
- `codex-rs/app-server/tests/suite/fuzzy_file_search.rs`
- `codex-rs/app-server/tests/suite/v2/turn_start.rs`
- `codex-rs/app-server/tests/suite/v2/thread_resume.rs`
- `codex-rs/app-server/tests/suite/v2/thread_list.rs`
- `codex-rs/app-server/tests/suite/v2/account.rs`
- `codex-rs/app-server/tests/suite/v2/config_rpc.rs`
- `codex-rs/app-server/tests/suite/v2/command_exec.rs`
- `codex-rs/app-server/tests/suite/v2/fs.rs`
- `codex-rs/app-server/tests/suite/v2/request_user_input.rs`
- `codex-rs/app-server/tests/suite/v2/request_permissions.rs`
- `codex-rs/app-server/tests/suite/v2/plugin_install.rs`
- `codex-rs/app-server/tests/suite/v2/windows_sandbox_setup.rs`

### 下游被调用路径（实现/协议）

1. 被测服务
- `codex-rs/app-server/src/message_processor.rs`
- `codex-rs/app-server/src/codex_message_processor.rs`

2. 协议定义
- `codex-rs/app-server-protocol/src/protocol/common.rs`
- `codex-rs/app-server-protocol/src/protocol/v1.rs`
- `codex-rs/app-server-protocol/src/protocol/v2.rs`

3. core 侧格式消费者
- `codex-rs/core/src/models_manager/manager.rs`（`models_cache.json`）
- `codex-rs/core/src/auth.rs` / `auth/storage.rs`（`auth.json`）
- `codex-rs/core/src/rollout/list.rs` / `rollout/recorder.rs`（rollout 文件布局与 session_meta）

4. 公共测试支持库
- `codex-rs/core/tests/common/responses.rs`（SSE 与 wiremock/websocket helper）

## 依赖与外部交互

### 1) Rust 依赖关系

1. 本目录 crate 定义
- crate 名：`app_test_support`（未加 `codex-` 前缀，属于测试支持例外）。
- `codex-rs/Cargo.toml` 通过 workspace dependency 映射到 `app-server/tests/common`。
- `codex-app-server` 在 `dev-dependencies` 中依赖 `app_test_support`。

2. 关键依赖
- 协议与核心：`codex-app-server-protocol`, `codex-core`, `codex-protocol`
- 测试基础：`core_test_support`, `wiremock`, `tokio`, `serde_json`
- 进程定位：`codex-utils-cargo-bin`

### 2) 与外部系统交互

1. 子进程
- 启动真实 `codex-app-server` 二进制，读写 stdin/stdout JSON-RPC。

2. 网络
- 主要是本地 loopback mock：
  - wiremock HTTP (`/responses`, `/models`, analytics 等)
  - websocket mock（realtime）
- 通常不依赖公网；但部分 suite 场景会显式 `skip_if_no_network!`。

3. 文件系统
- 在 `TempDir` 下写 `config.toml/auth.json/models_cache.json/sessions/.../rollout-*.jsonl`。
- 回归测试通过这些文件验证 app-server 与 core 的持久化读取路径。

### 3) 与脚本/文档/构建系统交互

1. 文档契约
- `codex-rs/app-server/README.md` 描述 initialize 握手、thread/turn、command/exec、fs/config、server request 生命周期。

2. 协议契约
- `app-server-protocol/common.rs` 的 method <-> params/response 定义，决定 `mcp_process.rs` 的 request facade 可用范围。

3. 构建
- Cargo：`codex-rs/app-server/Cargo.toml` 的 dev-dependency 注入。
- Bazel：`tests/common/BUILD.bazel` 通过 `codex_rust_crate` 暴露 `common` crate。

## 风险、边界与改进建议

1. 风险：`mcp_process.rs` 体量与职责过大
- 当前约 1191 行，混合了启动、协议、缓冲、清理、所有 RPC facade。
- 建议：拆为 `process_runtime`、`rpc_client`、`stream_matcher` 三层，降低维护复杂度。

2. 风险：部分 helper 与 suite 内部存在重复
- 如多个测试文件仍自写 `create_config_toml(...)`，与 `write_mock_responses_config_toml` 功能部分重叠。
- 建议：统一参数化配置 builder，减少格式漂移（尤其 `requires_openai_auth`、provider 字段）。

3. 风险：顺序 mock 的 panic 失败模式较硬
- `SeqResponder` 超出预设调用次数会直接 panic，定位虽快，但在并发/重试路径下可能造成误判。
- 建议：增加可选“宽松模式 + 请求日志输出”，默认严格、必要时可切换。

4. 风险：消息读取依赖超时与谓词匹配
- 异步场景中错误 method/时序可能导致超时而非结构化错误。
- 建议：统一封装带上下文的等待器（包含 pending 缓冲摘要与最近 N 条消息）。

5. 边界：该目录只服务集成测试，不提供生产 API
- `app_test_support` 是测试时 crate，设计上可以偏重可观测性与易用性，不要求稳定 public API。

6. 边界：兼容层方法仍存在
- `getAuthStatus/getConversationSummary/fuzzyFileSearch` 属于 legacy/过渡面，但测试仍覆盖。
- 建议：在文档中明确“保留原因 + 计划退役路径”，避免后续误删。

7. 改进：将 method 覆盖自动化
- 可增加脚本对比 `mcp_process.rs` 的 `send_request("...")` 与 `app-server-protocol` 的 method 清单，自动提示遗漏或陈旧 facade。

8. 改进：为 `rollout` fixture 增加校验器
- 在写入后可选运行最小 schema/字段检查，提前发现字段漂移（如 `SessionMeta` 新字段导致读路径行为变化）。
