# DIR `codex-rs/app-server/src` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/app-server/src`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 关联 crate：`codex-app-server`
- 关联协议：`codex-rs/app-server-protocol/src/protocol/common.rs`、`codex-rs/app-server-protocol/src/protocol/v2.rs`

## 场景与职责

`codex-rs/app-server/src` 是 Codex App Server 的运行时核心目录，负责把 `codex-core` 的线程/回合执行能力暴露为 JSON-RPC 接口，并保证不同 transport（stdio/websocket/in-process）下行为一致。

该目录承担四层职责：

1. 进程入口与运行时编排
- `main.rs` 解析 `--listen`，调用 `run_main_with_transport`。
- `lib.rs` 组装 transport、processor、outbound router、配置加载、otel/logging、优雅重启逻辑。

2. 协议网关与请求分流
- `message_processor.rs` 处理 `initialize` 门禁、experimental capability 校验、config/fs/external-agent 请求。
- 其余业务请求下沉到 `codex_message_processor.rs`。

3. 业务控制平面
- `codex_message_processor.rs` 处理 thread/turn/review/realtime/plugin/skills/mcp/auth/feedback/command-exec。
- `bespoke_event_handling.rs` 将 core `EventMsg` 翻译为 app-server v2 typed notifications 与 server requests。

4. 状态与传输基础设施
- `transport.rs` 定义 transport 事件、连接生命周期、背压策略、通知过滤。
- `outgoing_message.rs` 统一 outgoing envelope 与 server request 回调管理。
- `thread_state.rs`、`thread_status.rs` 维护线程订阅/状态机。
- `in_process.rs` 提供无进程边界的内嵌 app-server runtime。

## 功能点目的

1. 连接初始化与能力协商
- 每连接必须先 `initialize`，否则拒绝请求（`Not initialized`）；重复初始化拒绝（`Already initialized`）。
- 协商项：`experimentalApi`、`optOutNotificationMethods`、client identity（name/version）用于追踪与 upstream header。

2. thread 生命周期管理
- 提供 `thread/start|resume|fork|list|loaded/list|read|archive|unarchive|unsubscribe|rollback|compact/start|shellCommand|backgroundTerminals/clean|metadata/update|name/set`。
- 目标是把“会话创建、恢复、归档、订阅、状态”从核心执行中解耦为稳定 RPC。

3. turn 生命周期管理
- 提供 `turn/start|steer|interrupt`，并通过事件流回传 `turn/started`、`item/*`、`turn/completed`。
- 支持 per-turn 覆盖（cwd/model/sandbox/approval/collaborationMode/personality 等）。

4. 审批与交互回路
- 将 core 产生的审批/输入请求转换成 server request：文件改动审批、命令执行审批、request_user_input、request_permissions、mcp elicitation、dynamic tool call。
- 客户端响应后再转回 core `Op::*`，形成闭环。

5. 辅助能力 API
- `command/exec` 与 `command/exec/write|resize|terminate`：线程外命令执行与流式 IO。
- `fs/*`：二进制文件读写（base64）、目录与元信息操作。
- `config/*`、`configRequirements/read`、`externalAgentConfig/*`：配置读取/写入/迁移。
- `skills/list`、`plugin/*`、`app/list`、`model/list`、`experimentalFeature/list`、`collaborationMode/list`。
- `mcpServer/*`、`mcpServerStatus/list`、`windowsSandbox/setupStart`、`feedback/upload`、fuzzy file search。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 启动与主循环（`lib.rs`）

关键流程：

1. 解析 transport 并启动接入层
- `stdio`：固定连接 `ConnectionId(0)`，stdin/jsonl 入站 + stdout 出站。
- `websocket`：axum listener，支持 `/readyz` `/healthz` 与 websocket upgrade。

2. 预加载配置与警告
- 使用 `ConfigBuilder` 构建配置；失败时回落默认配置并记录 `ConfigWarningNotification`。
- 启动前还会做 exec policy warning、project config disabled warning、startup_warnings 聚合。

3. 双环路架构
- `processor task`：消费 `TransportEvent`，维护每连接 `ConnectionSessionState`，调用 `MessageProcessor`。
- `outbound task`：消费 `OutgoingEnvelope`，通过 `route_outgoing_envelope` 向目标连接发送。
- 两者通过 `OutboundControlEvent`（Opened/Closed/DisconnectAll）协作连接状态。

4. websocket 优雅重启
- 捕获 signal 后进入 drain：等待 running assistant turns 归零；第二次 signal 强制退出。
- 退出前触发 `DisconnectAll` 并停止 acceptor。

### 2) Transport 与背压（`transport.rs`）

1. 事件模型
- `TransportEvent::{ConnectionOpened, ConnectionClosed, IncomingMessage}`。
- 每连接保留 outbound 过滤状态（initialized、experimental、opt-out methods）。

2. 背压策略
- 入站队列满且消息是 request：立即回 `OVERLOADED_ERROR_CODE(-32001)` + `Server overloaded; retry later.`。
- 入站满但消息是 response/notification/error：阻塞等待入队，避免破坏协议时序。
- websocket 出站队列满：断开慢连接（防止单连接拖垮整体）。

3. 通知过滤
- 非 in-process 连接默认丢弃 legacy `codex/event/*` 通知（仍保留 typed server notifications）。
- 按连接精确 method 名过滤 `optOutNotificationMethods`。

### 3) 网关分层（`message_processor.rs` + `codex_message_processor.rs`）

1. `MessageProcessor`
- 统一请求上下文（trace span + request context registry）。
- 处理 `initialize`、实验能力门禁、config/fs/external-agent 请求。
- 将其余 typed request 委托给 `CodexMessageProcessor`。

2. `CodexMessageProcessor`
- 大型 method dispatch（`ClientRequest` 全量 match）。
- thread/turn 相关请求会把操作提交到 `CodexThread`（`submit_core_op`），并通过监听线程事件完成异步回执。

3. in-process 与 websocket 共享语义
- in-process 调用 `process_client_request`，绕过 JSON 反序列化但复用同一逻辑。
- websocket 场景的 outbound initialized 在 `lib.rs` 中延后设置，确保 initialize 通知顺序正确。

### 4) 线程监听与事件翻译

1. listener 建立
- `ensure_conversation_listener` 会先确保 connection 已订阅 thread，再保证 listener task 在跑。
- listener task 同时处理：`conversation.next_event()` 与 `ThreadListenerCommand`（如 running-thread resume 响应）。

2. 事件翻译
- `bespoke_event_handling.rs` 将 core `EventMsg` 映射为 v2 通知（`turn/started`、`item/started/completed`、`model/rerouted`、`thread/realtime/*` 等）。
- 审批与用户输入请求转换为 server requests；回包后提交对应 `Op`。
- turn 结束时会清理 pending server requests，避免跨 turn 悬挂。

3. 历史与活跃 turn 合并
- thread/resume、thread/read（includeTurns）会从 rollout 构建 turn history；若存在 active turn，执行 merge，避免 UI 丢失正在进行中的 turn。

### 5) 状态数据结构

1. `ThreadStateManager`（`thread_state.rs`）
- 维护：live connections、thread<->connection 订阅关系、每线程 `ThreadState`。
- `ThreadState` 包含：pending interrupts、pending rollback、turn summary、listener command channel、current turn history。

2. `ThreadWatchManager`（`thread_status.rs`）
- 维护 runtime facts（running、等待审批、等待用户输入、system_error）。
- 推导 `ThreadStatus` 并广播 `thread/status/changed`。
- 同步输出 running turn count（给 `lib.rs` 优雅重启 drain 使用）。

3. `OutgoingMessageSender`（`outgoing_message.rs`）
- 管理 server->client request 的 callback 表与 thread 关联。
- 支持按 thread 重放 pending server requests（running thread resume 场景）。
- 维护 request context（用于 tracing 关联与响应清理）。

### 6) 命令与文件/配置接口

1. `command_exec.rs`
- session key = `(connection_id, process_id)`，支持客户端 processId 或服务端生成 id。
- 支持 PTY、stdin 流、stdout/stderr delta、timeout/cancel、resize、terminate。
- Windows sandbox 下限制 streaming/write/resize/terminate（仅 buffered 响应）。

2. `fs_api.rs`
- 统一通过 `ExecutorFileSystem` 抽象访问。
- base64 编解码文件内容，InvalidInput 映射为 `INVALID_REQUEST`，其余映射 `INTERNAL_ERROR`。

3. `config_api.rs`
- 基于 `ConfigService` 提供 read/valueWrite/batchWrite/requirementsRead。
- batchWrite 可触发 `reload_user_config`（给已加载线程发送 `Op::ReloadUserConfig`）。
- 额外发 plugin 启停 telemetry，并在 `MessageProcessor` 层清理 plugin/skills cache。

### 7) 插件/技能/MCP/模型与外部接入

1. skills/plugin/apps
- `skills/list` 支持多 cwd 与 per-cwd 额外 root（要求绝对路径）。
- `plugin/list/read/install/uninstall` 依赖 plugins manager，支持 optional remote sync。
- `apps/list` 并发拉取 accessible/all connectors，支持中间态通知 `app/list/updated`。

2. mcp
- `mcpServer/oauth/login` 对 streamable http transport 执行 oauth，异步发 completed 通知。
- `mcpServerStatus/list` 收集工具/资源/模板/auth 状态并分页返回。
- `mcpServer/refresh` 把刷新请求按 thread 排队，在下次活跃 turn 应用。

3. model/collaboration/feature
- `model/list` 读取 models manager（可 includeHidden）。
- `collaborationMode/list` 与 `experimentalFeature/list` 直接映射运行时配置状态。

## 关键代码路径与文件引用

入口与编排：

- `codex-rs/app-server/src/main.rs`
- `codex-rs/app-server/src/lib.rs`
- `codex-rs/app-server/src/transport.rs`

网关与业务分发：

- `codex-rs/app-server/src/message_processor.rs`
- `codex-rs/app-server/src/codex_message_processor.rs`
- `codex-rs/app-server/src/app_server_tracing.rs`

事件桥接与状态：

- `codex-rs/app-server/src/bespoke_event_handling.rs`
- `codex-rs/app-server/src/thread_state.rs`
- `codex-rs/app-server/src/thread_status.rs`
- `codex-rs/app-server/src/outgoing_message.rs`
- `codex-rs/app-server/src/server_request_error.rs`

辅助 API 模块：

- `codex-rs/app-server/src/command_exec.rs`
- `codex-rs/app-server/src/fs_api.rs`
- `codex-rs/app-server/src/config_api.rs`
- `codex-rs/app-server/src/external_agent_config_api.rs`
- `codex-rs/app-server/src/fuzzy_file_search.rs`
- `codex-rs/app-server/src/dynamic_tools.rs`
- `codex-rs/app-server/src/models.rs`
- `codex-rs/app-server/src/filters.rs`

in-process 嵌入：

- `codex-rs/app-server/src/in_process.rs`

测试相关：

- `codex-rs/app-server/src/message_processor/tracing_tests.rs`
- `codex-rs/app-server/tests/all.rs`
- `codex-rs/app-server/tests/common/lib.rs`
- `codex-rs/app-server/tests/common/mcp_process.rs`
- `codex-rs/app-server/tests/suite/mod.rs`
- `codex-rs/app-server/tests/suite/v2/*.rs`
- `codex-rs/app-server/tests/suite/bash`
- `codex-rs/app-server/tests/suite/zsh`

协议与文档：

- `codex-rs/app-server/README.md`
- `codex-rs/app-server-protocol/src/protocol/common.rs`
- `codex-rs/app-server-protocol/src/protocol/v2.rs`

调用方（上游）：

- `codex-rs/cli/src/main.rs`（`app-server` 子命令）
- `codex-rs/app-server-client/src/lib.rs`（in-process 客户端封装）
- `codex-rs/app-server-client/src/remote.rs`（remote websocket 客户端）
- `codex-rs/exec/src/lib.rs`（in-process runtime 使用）
- `codex-rs/tui_app_server/src/*`（TUI 通过 app-server RPC）

## 依赖与外部交互

1. 核心 Rust 依赖（crate 级）
- 内部：`codex-core`、`codex-protocol`、`codex-state`、`codex-app-server-protocol`、`codex-chatgpt`、`codex-backend-client`、`codex-feedback`、`codex-file-search`、`codex-rmcp-client`。
- 框架/系统：`tokio`、`axum`、`serde_json`、`tracing`、`tokio-tungstenite`。

2. 对外网络交互
- websocket transport（可选，实验）。
- 后端模型请求与账户信息（通过 core/backend-client）。
- connectors/apps 拉取、plugin 远程同步。
- MCP OAuth 登录与状态查询。
- feedback 上传。

3. 文件系统与本地状态
- `CODEX_HOME` 下 rollout/sessions/archived/config/auth/models_cache/state-db。
- fs RPC 可对绝对路径执行读写/删除/复制。
- archive/unarchive 会移动 rollout 文件并标记 sqlite 元数据。

4. 测试与脚本交互
- 集成测试通过 `McpProcess` 启动真实 `codex-app-server` 子进程进行端到端 JSON-RPC 验证。
- `tests/suite/bash` 与 `tests/suite/zsh` 使用 dotslash artifact 覆盖 shell 执行分支。

## 风险、边界与改进建议

1. 单文件复杂度风险（高）
- `codex_message_processor.rs`、`bespoke_event_handling.rs` 文件体量很大，职责密集，维护和审查成本高。
- 建议：按功能域拆分（thread lifecycle、auth/account、plugin/apps、mcp/realtime、search/feedback），并将对应测试迁移到分模块邻近位置。

2. 初始化与连接状态时序复杂（中）
- `initialize`、outbound initialized、connection-scoped config warnings、listener attach 存在细粒度时序依赖。
- 建议：补充时序图文档；对“初始化后首个 thread/turn 请求”添加更明确的集成测试矩阵（stdio/websocket/in-process）。

3. 背压策略可观测性不足（中）
- 目前 overload 与 slow-connection disconnect 已实现，但缺少结构化指标（触发次数/连接维度）。
- 建议：新增 telemetry counters 与 percentile（队列占用、disconnect 原因、overload 比例）。

4. 兼容层长期残留风险（中）
- listener 中仍发送 legacy `codex/event/*`，依赖 in-process 老消费者。
- 建议：明确迁移截止版本，分阶段移除 legacy 通知路径，降低双协议维护成本。

5. thread 状态一致性边界（中）
- `ThreadWatchManager` 状态来自 runtime 事件，`thread/read` 又可读 rollout 与 sqlite，存在短暂不一致窗口（已用 `resolve_thread_status` 缓冲）。
- 建议：在 `thread/read/includeTurns` 与 running-turn 场景增加一致性断言测试，避免 stale inProgress turn 外露。

6. 外部系统失败降级路径较多（中）
- plugin remote sync、connectors 拉取、oauth、rate limits、cloud requirements 等失败会走告警或回退；行为正确但分散。
- 建议：统一错误分类与 `error.data` 结构（可重试/用户动作/后端异常），提升客户端恢复策略可编排性。

7. 安全边界提醒（低-中）
- websocket transport 在 README 中已标注实验/不建议生产；但实际启用成本低。
- 建议：在非 loopback bind 场景输出更强提示，并提供内建 auth/tls 前置校验开关（即使默认关闭）。
