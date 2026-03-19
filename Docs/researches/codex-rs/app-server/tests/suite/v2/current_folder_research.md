# codex-rs/app-server/tests/suite/v2 研究

## 场景与职责

`codex-rs/app-server/tests/suite/v2` 是 `codex-app-server` 的 v2 集成测试主战场，目标是以“真实子进程 + JSON-RPC 协议 + mock 上游服务”方式验证 app-server 的外部行为，而不是仅验证内部函数。

- 入口聚合链路：
  - `codex-rs/app-server/tests/all.rs` -> `tests/suite/mod.rs` -> `tests/suite/v2/mod.rs`
- 当前目录规模（2026-03-20 本地统计）：
  - `49` 个 `*.rs` 测试模块
  - `254` 个测试函数（`#[tokio::test]`/`#[test]`）
- 该目录覆盖的核心职责：
  - 连接生命周期与初始化握手（stdio/ws）
  - thread/turn 主流程与通知流
  - 一次性命令执行 `command/exec*`
  - config/fs/plugin/skills/app/account/realtime 等业务 RPC
  - experimental API gating 与 server-request 往返（approval/user-input/elicitation）

该目录在工程中的定位是“协议契约回归层”：对外 method 名、参数形状、错误码、通知时序、并发边界、连接隔离等发生变化时，优先在这里暴露回归。

## 功能点目的

按功能域看，本目录测试目的可分为以下几组：

1. 初始化与连接层
- 文件：`initialize.rs`、`connection_handling_websocket.rs`、`connection_handling_websocket_unix.rs`
- 目的：保证 `initialize`/`initialized` 必要握手、每连接状态隔离、WebSocket 健康探针与 Origin 拒绝策略、请求过载行为等不回退。

2. Thread 生命周期
- 文件：`thread_start.rs`、`thread_resume.rs`、`thread_fork.rs`、`thread_read.rs`、`thread_list.rs`、`thread_loaded_list.rs`、`thread_archive.rs`、`thread_unarchive.rs`、`thread_unsubscribe.rs`、`thread_status.rs`、`thread_metadata_update.rs`、`thread_name_websocket.rs`、`thread_rollback.rs`、`thread_shell_command.rs`
- 目的：覆盖线程创建/恢复/分叉/归档/读取/列举/状态变化的稳定契约，尤其是“运行中线程恢复”“历史可见性”“更新时戳与 mtime”“分页筛选”这类高回归风险点。

3. Turn 与审阅流程
- 文件：`turn_start.rs`、`turn_steer.rs`、`turn_interrupt.rs`、`review.rs`、`plan_item.rs`、`output_schema.rs`、`compaction.rs`
- 目的：保障 turn 启动参数（模型、协作模式、人格、输入元素、大小上限等）、流式通知、审批请求、中断语义、输出 schema 与评审模式行为一致。

4. 一次性命令执行
- 文件：`command_exec.rs`（`#[cfg(unix)]`）
- 目的：保证 `command/exec` 在 buffered/streaming/TTY 模式下行为稳定，且 processId 的连接级隔离、写入/resize/终止协议正确。

5. 配置与文件系统
- 文件：`config_rpc.rs`、`fs.rs`
- 目的：验证配置读写分层、冲突错误映射、热重载触发；验证 fs read/write/copy/remove/metadata 的协议形状与路径合法性约束。

6. 扩展能力与生态
- 文件：`skills_list.rs`、`plugin_list.rs`、`plugin_read.rs`、`plugin_install.rs`、`plugin_uninstall.rs`、`app_list.rs`、`dynamic_tools.rs`、`collaboration_mode_list.rs`、`model_list.rs`、`experimental_feature_list.rs`
- 目的：确保技能/插件/应用枚举与安装状态、远端同步、分页缓存合并、动态工具等行为可回归验证。

7. 账户、限流与实时能力
- 文件：`account.rs`、`rate_limits.rs`、`realtime_conversation.rs`
- 目的：验证认证登录/登出/刷新、账号状态通知、限流读接口、realtime 实验能力和 gating。

8. server request 往返链路
- 文件：`request_permissions.rs`、`request_user_input.rs`、`mcp_server_elicitation.rs`
- 目的：验证 server->client 请求（approval / elicitation / user input）在 app-server 中的请求响应闭环。

9. 平台与实验特性
- 文件：`experimental_api.rs`、`safety_check_downgrade.rs`、`windows_sandbox_setup.rs`、`analytics.rs`
- 目的：覆盖实验特性开关、平台特定能力、遥测与安全降级行为。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 测试驱动方式：真实子进程 + JSON-RPC 报文

核心测试助手位于：
- `codex-rs/app-server/tests/common/mcp_process.rs`
- `codex-rs/app-server/tests/common/lib.rs`

`McpProcess` 通过 `codex_utils_cargo_bin::cargo_bin("codex-app-server")` 拉起真实 `codex-app-server` 子进程，使用 stdin/stdout 按行读写 JSON-RPC。常见固定流程：

1. `McpProcess::new(...)` 或 `new_with_env(...)` 启动服务进程。
2. `initialize()` 发送 `initialize` 请求并自动发送 `initialized` 通知。
3. 调用 `send_*_request(...)` 触发某个 v2 method。
4. 通过 `read_stream_until_response_message` / `read_stream_until_error_message` / `read_stream_until_notification_message` 断言行为。

该文件当前封装了 `65` 个 `send_*` helper，覆盖 thread/turn/command/fs/config/plugin/app/account/realtime 等绝大多数 method 字符串（如 `thread/start`、`turn/start`、`command/exec/write`、`config/batchWrite`、`fs/readFile`）。

### 2) 协议定义与 method 映射

协议中心在：
- `codex-rs/app-server-protocol/src/protocol/common.rs`
- `codex-rs/app-server-protocol/src/protocol/v2.rs`

`common.rs` 使用宏生成 `ClientRequest` / `ServerRequest` / `ServerNotification`。

关键点：
- 线协议 method（例如 `"thread/start"`、`"turn/start"`、`"command/exec"`）在 `ClientRequest` 中显式声明。
- 通过 `inspect_params: true` 处理“方法本身稳定但参数里有实验字段”的 gating（如 `ThreadStart`/`TurnStart`）。
- `server_request_definitions!` 定义 server->client 请求：`item/commandExecution/requestApproval`、`item/fileChange/requestApproval`、`item/tool/requestUserInput`、`mcpServer/elicitation/request`、`item/permissions/requestApproval` 等。
- `server_notification_definitions!` 定义通知流：`thread/started`、`turn/started`、`turn/completed`、`item/*`、`command/exec/outputDelta`、`account/updated`、`app/list/updated` 等。

### 3) 服务端请求分发链

请求分发主链路：

1. `app-server/src/transport.rs` 读取 stdio/ws 消息，形成 `TransportEvent::IncomingMessage`。
2. `app-server/src/lib.rs` 主循环接收并路由事件。
3. `app-server/src/message_processor.rs::handle_client_request` 做初始化状态机与 experimental gating。
4. 基础配置/文件系统路由到 `ConfigApi` / `FsApi`。
5. 其余请求委托 `app-server/src/codex_message_processor.rs::process_request` 分派到 thread/turn/plugin/app/account/realtime/command 等处理器。

### 4) mock 上游与 SSE 流

测试通过 `tests/common/mock_model_server.rs` 与 `tests/common/responses.rs` 构造上游 Responses API 事件，常见手法：

- `create_mock_responses_server_sequence(_unchecked)` 创建 wiremock 服务
- `responses::mount_sse_once(...)` 挂单次 SSE 响应
- 通过 `ev_response_created` / `ev_function_call` / `ev_completed` 等事件组合模拟模型工具调用流

这使 `turn_start.rs`、`thread_resume.rs` 能稳定复现审批请求、工具调用、输出增量和完成事件。

### 5) 重点流程示例

1. `turn/start`（`turn_start.rs`）
- 发送 `TurnStartParams`
- 接收 `turn/started` -> `item/started`/`item/completed`/delta -> `turn/completed`
- 对输入大小上限、text/image 元素、模型覆盖、人格/协作模式、审批请求回放、file change output delta 等进行断言

2. `thread/resume`（`thread_resume.rs`）
- 覆盖未物化线程拒绝、历史恢复、运行中线程重连、审批请求重放、mtime/updated_at 行为、配置覆盖与路径匹配规则

3. `command/exec*`（`command_exec.rs` + `app-server/src/command_exec.rs`）
- `start` 创建 `ConnectionProcessId { connection_id, process_id }`，保证 processId 连接隔离
- `write/resize/terminate` 通过控制通道下发
- 输出使用 `command/exec/outputDelta` base64 分块通知（streaming）或最终 response（buffered）
- 连接关闭时 `connection_closed` 主动终止本连接 process，避免泄漏

4. WebSocket 连接处理（`connection_handling_websocket.rs` + `transport.rs`）
- 同监听器提供 `/readyz`、`/healthz`
- 带 `Origin` 的请求返回 `403`
- 当队列拥塞时返回 `-32001`（overloaded）

## 关键代码路径与文件引用

以下为“测试目录 -> 上下文依赖”的关键路径：

- 测试聚合入口
  - `codex-rs/app-server/tests/all.rs`
  - `codex-rs/app-server/tests/suite/mod.rs`
  - `codex-rs/app-server/tests/suite/v2/mod.rs`

- 测试基础设施
  - `codex-rs/app-server/tests/common/lib.rs`
  - `codex-rs/app-server/tests/common/mcp_process.rs`
  - `codex-rs/app-server/tests/common/config.rs`
  - `codex-rs/app-server/tests/common/mock_model_server.rs`
  - `codex-rs/app-server/tests/common/responses.rs`

- v2 重点测试文件（高密度）
  - `codex-rs/app-server/tests/suite/v2/turn_start.rs`（2585 行，20 tests）
  - `codex-rs/app-server/tests/suite/v2/thread_resume.rs`（1950 行，17 tests）
  - `codex-rs/app-server/tests/suite/v2/thread_list.rs`（1429 行，21 tests）
  - `codex-rs/app-server/tests/suite/v2/app_list.rs`（1428 行，10 tests）
  - `codex-rs/app-server/tests/suite/v2/account.rs`（1277 行，18 tests）
  - `codex-rs/app-server/tests/suite/v2/command_exec.rs`（886 行，13 tests）
  - `codex-rs/app-server/tests/suite/v2/config_rpc.rs`（726 行，10 tests）
  - `codex-rs/app-server/tests/suite/v2/fs.rs`（613 行，10 tests）

- 服务端实现（被调用方）
  - `codex-rs/app-server/src/main.rs`
  - `codex-rs/app-server/src/lib.rs`
  - `codex-rs/app-server/src/transport.rs`
  - `codex-rs/app-server/src/message_processor.rs`
  - `codex-rs/app-server/src/codex_message_processor.rs`
  - `codex-rs/app-server/src/command_exec.rs`
  - `codex-rs/app-server/src/config_api.rs`
  - `codex-rs/app-server/src/fs_api.rs`

- 协议与文档
  - `codex-rs/app-server-protocol/src/protocol/common.rs`
  - `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - `codex-rs/app-server/README.md`

## 依赖与外部交互

### 1) 内部 crate 依赖

`v2` 测试链路直接或间接依赖：

- `codex-app-server`（被测二进制）
- `codex-app-server-protocol`（请求/响应/通知类型）
- `codex-core`（线程管理、认证、配置、执行策略）
- `codex-state`（日志/会话状态）
- `core_test_support`（responses SSE 构造、路径工具）
- `codex_utils_cargo_bin`（测试中定位 workspace 二进制）

### 2) 外部交互面

测试中存在以下外部交互类型：

- 子进程启动：直接拉起 `codex-app-server` 可执行文件
- 网络 mock：wiremock 风格本地 HTTP/SSE 服务模拟模型端
- 文件系统：临时 `CODEX_HOME` 下写入 `config.toml`、rollout、状态文件
- websocket/http：部分测试直接验证 ws listener 与 health endpoint

### 3) 配置交互

`tests/common/config.rs::write_mock_responses_config_toml` 会动态写测试配置，包括：

- `model_provider` 与 `base_url`
- features 开关
- `approval_policy`、`sandbox_mode`
- `model_auto_compact_token_limit` 等

这让测试能覆盖“同一协议在不同配置/feature 下的行为差异”。

## 风险、边界与改进建议

### 风险与边界

1. 单文件体积过大导致维护成本高
- `turn_start.rs`、`thread_resume.rs`、`thread_list.rs`、`app_list.rs`、`account.rs` 已是千行级，阅读与定位回归成本高。

2. 集成测试时序敏感
- 依赖异步通知顺序、子进程销毁、SSE 回放，若清理不彻底易引入偶发 flake（`McpProcess::Drop` 已做同步回收，但复杂并发场景仍有边界）。

3. 协议演进的隐式断层风险
- method 字符串、experimental gating、notification 命名若在实现层改动但测试未同步，可能出现“行为漂移而无显式 schema 断言”。

4. 平台覆盖不完全
- `command_exec.rs` 与部分 websocket unix 行为在 `#[cfg(unix)]` 下执行，Windows 行为更多依赖专门模块与局部验证。

### 改进建议

1. 为超大测试文件做“主题拆分”
- 按子领域拆分 `turn_start.rs`/`thread_resume.rs`，例如输入验证、审批流、并发恢复、输出增量分别成文件，降低改动冲突率。

2. 补“契约矩阵文档”
- 在本目录增加轻量 `README`（method -> 测试文件 -> 关键断言点），便于协议改动时快速定位受影响测试。

3. 强化时序可观测性
- 为关键通知流测试统一封装“期望事件序列 + 超时诊断”工具，失败时输出更结构化上下文，减少排障时间。

4. 持续对齐协议导出产物
- 在 API 变更 PR 中强制检查 `common.rs/v2.rs` 与测试覆盖点是否同时更新，避免仅改实现未改测试用例。

5. 扩展跨平台覆盖策略
- 对非 unix 场景补充等价断言（尤其是 windows sandbox setup 与 command exec 差异行为），降低平台偏差。
