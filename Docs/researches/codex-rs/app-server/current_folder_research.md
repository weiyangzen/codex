# DIR `codex-rs/app-server` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/app-server`
- 目标类型：`DIR`
- 研究日期：2026-03-19
- 关联协议目录：`codex-rs/app-server-protocol`
- 关联调用方目录：`codex-rs/cli`、`codex-rs/app-server-client`、`codex-rs/exec`、`codex-rs/tui_app_server`

## 场景与职责

`codex-rs/app-server` 是 Codex 的“结构化会话服务层”，定位是把 core 线程/turn 执行能力以 JSON-RPC 2.0 暴露给外部或本进程客户端。

核心职责可归纳为 5 类：

1. 多传输接入与连接生命周期管理
- 支持 `stdio://`（默认）和 `ws://IP:PORT` 两种传输，统一转成 `TransportEvent` 事件流交给处理器（`src/lib.rs:343`, `src/transport.rs:129`, `src/transport.rs:264`, `src/transport.rs:333`）。

2. 协议握手门禁与能力开关
- 每连接必须先 `initialize`，否则拒绝请求；按连接记录 `experimental_api_enabled` 与通知 opt-out 列表（`src/message_processor.rs:497`, `src/message_processor.rs:512`, `src/message_processor.rs:608`, `src/message_processor.rs:616`）。

3. 业务 RPC 分发
- `MessageProcessor` 先拦截 config/fs/external-agent 这类“本地 API”，其余委托给 `CodexMessageProcessor` 处理 thread/turn/review/plugins/mcp/command_exec 等主业务（`src/message_processor.rs:629`, `src/message_processor.rs:689`, `src/message_processor.rs:761`, `src/codex_message_processor.rs:612`）。

4. 事件桥接与状态语义化
- 将 core 的 `EventMsg` 翻译成 app-server v2 typed notifications（如 `turn/started`、`item/*`、`turn/completed`、`thread/status/changed`），并维护中断、回滚、审批等请求-事件闭环（`src/bespoke_event_handling.rs:252`, `src/bespoke_event_handling.rs:269`, `src/bespoke_event_handling.rs:1698`, `src/bespoke_event_handling.rs:1727`）。

5. 本进程嵌入运行时
- `in_process` 模块在不走进程边界的情况下复用同一处理链路，服务 `exec`/TUI 等面板场景（`src/in_process.rs:1`, `src/in_process.rs:349`, `src/in_process.rs:371`）。

## 功能点目的

按用户可见能力与内部支撑拆分如下：

1. thread/turn 生命周期 API
- 目标：让客户端以 thread 为单位管理会话、以 turn 为单位驱动推理与工具执行。
- 代表接口：`thread/start|resume|fork|list|read|archive|unarchive|rollback|unsubscribe`、`turn/start|steer|interrupt`（`src/codex_message_processor.rs:629`, `src/codex_message_processor.rs:689`, `src/codex_message_processor.rs:697`, `src/codex_message_processor.rs:732`）。

2. 审批与交互回调 API
- 目标：把 core 在执行过程中产生的“需用户决策”点以 server request 下发给客户端，并将客户端回复反哺 core。
- 覆盖审批类型：命令执行、文件改动、permissions、request_user_input、MCP elicitation、dynamic tool call（`src/bespoke_event_handling.rs:452`, `src/bespoke_event_handling.rs:536`, `src/bespoke_event_handling.rs:672`, `src/bespoke_event_handling.rs:736`, `src/bespoke_event_handling.rs:796`, `src/bespoke_event_handling.rs:844`）。

3. 命令执行与流式输出 API
- 目标：提供线程外的一次性命令执行 (`command/exec`) 及 PTY/stdin/output 流式控制能力。
- 关键能力：`command/exec/write|resize|terminate`、输出 delta 通知、超时/取消、跨平台沙箱差异处理（`src/codex_message_processor.rs:857`, `src/command_exec.rs:142`, `src/command_exec.rs:307`, `src/command_exec.rs:355`, `src/command_exec.rs:565`）。

4. 配置与文件系统 API
- 目标：让 GUI/IDE 客户端通过 app-server 进行配置读取/写入与受控 FS 操作，减少各端重复实现。
- config 支持：read、单 key 写入、batch 写入、requirements 读取；可触发线程热重载用户配置（`src/config_api.rs:99`, `src/config_api.rs:119`, `src/config_api.rs:134`, `src/config_api.rs:106`, `src/config_api.rs:152`）。
- fs 支持：read/write file、mkdir、metadata、read dir、remove、copy（`src/fs_api.rs:43`, `src/fs_api.rs:57`, `src/fs_api.rs:106`, `src/fs_api.rs:127`, `src/fs_api.rs:144`）。

5. 插件/技能/MCP/模型发现 API
- 目标：为客户端提供可渲染的生态与能力目录（skills/plugins/apps/models/mcp status）。
- 代表接口：`skills/list`、`plugin/list|read|install|uninstall`、`model/list`、`mcpServerStatus/list`、`mcpServer/oauth/login`（`src/codex_message_processor.rs:705`, `src/codex_message_processor.rs:709`, `src/codex_message_processor.rs:724`, `src/codex_message_processor.rs:772`, `src/codex_message_processor.rs:800`, `src/codex_message_processor.rs:807`）。

6. 模糊文件搜索（实验）
- 目标：提供低延迟文件模糊搜索与会话式增量更新，适配 IDE 快速跳转/补全交互。
- 关键点：固定上限 `MATCH_LIMIT=50`，线程数受 CPU 与 `MAX_THREADS=12` 限制，会话支持 query 更新与完成事件（`src/fuzzy_file_search.rs:18`, `src/fuzzy_file_search.rs:19`, `src/fuzzy_file_search.rs:21`, `src/fuzzy_file_search.rs:118`, `src/fuzzy_file_search.rs:192`, `src/fuzzy_file_search.rs:212`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 启动与主循环

1. 入口
- CLI 子命令 `codex app-server` 最终调用 `run_main_with_transport(...)`（`codex-rs/cli/src/main.rs:646`, `src/main.rs:36`, `src/lib.rs:343`）。

2. 双任务架构
- 处理环（processor task）：消费 `TransportEvent`，维护连接 session，调用 `MessageProcessor`。
- 出站环（outbound task）：消费 `OutgoingEnvelope`，按连接路由输出。
- 两环通过 `OutboundControlEvent` 协调连接开闭、全量断连（`src/lib.rs:101`, `src/lib.rs:343`, `src/lib.rs:567`, `src/lib.rs:606`）。

3. 优雅重启/退出
- websocket 模式支持信号触发 graceful drain：等待 running assistant turns 结束，再断连重启。
- stdio 模式则更接近单连接会话，连接关闭即退出（`src/lib.rs:169`, `src/lib.rs:383`, `src/lib.rs:649`）。

### 2) 传输层实现与背压策略

1. 传输抽象
- `AppServerTransport::{Stdio, WebSocket}`，`TransportEvent::{ConnectionOpened, ConnectionClosed, IncomingMessage}`（`src/transport.rs:129`, `src/transport.rs:187`）。

2. websocket 安全与健康探针
- 同端口提供 `/readyz` `/healthz`。
- 对含 `Origin` 的请求统一拒绝 `403`，降低被浏览器跨域滥用风险（`src/transport.rs:92`, `src/transport.rs:108`, `src/transport.rs:344`）。

3. 背压控制
- 全链路使用有界 channel（默认 `CHANNEL_CAPACITY=128`）（`src/transport.rs:56`）。
- 入站队列满时：
  - 若是 request，则优先回 `OVERLOADED_ERROR_CODE` + `"Server overloaded; retry later."`。
  - 若是 response/notification/error，则等待入队而非直接丢弃（`src/transport.rs:531`, `src/transport.rs:538`, `src/transport.rs:546`）。
- 出站到慢 websocket 连接：`try_send` 满则主动断开慢连接，避免拖垮全局（`src/transport.rs:641`）。

4. 通知过滤
- 外部客户端默认丢弃 legacy `codex/event/*` 通知，仅保留 typed app-server notification。
- 按连接的 `opted_out_notification_methods` 做 method 级过滤（`src/transport.rs:584`, `src/transport.rs:603`, `src/transport.rs:684`）。

### 3) 请求处理链

1. `MessageProcessor`
- 负责 JSON 反序列化为 `ClientRequest`、initialize 门禁、实验特性门禁、基础 API 分流（config/fs/external-agent）
（`src/message_processor.rs:276`, `src/message_processor.rs:497`, `src/message_processor.rs:616`, `src/message_processor.rs:629`, `src/message_processor.rs:689`）。

2. `CodexMessageProcessor`
- 负责大多数业务 API 分发（thread/turn/review/model/plugin/mcp/auth/command_exec/fuzzy_search/feedback）。
- `process_request` 巨型 match 是核心控制面（`src/codex_message_processor.rs:612` 起）。

3. 初始化状态同步
- websocket 路径中，initialize 后会先下发 connection-scoped initialize notifications（如 config warnings），再标记 outbound initialized，避免时序错乱（`src/lib.rs:765`, `src/message_processor.rs:420`）。

### 4) 事件语义化桥接

`apply_bespoke_event_handling(...)` 是将 core event 还原为 app-server API 语义的关键翻译层（`src/bespoke_event_handling.rs:252`）。

典型桥接：

1. Turn 生命周期
- `EventMsg::TurnStarted` -> `turn/started`。
- `EventMsg::TurnComplete` -> `turn/completed`（成功/失败由 `TurnSummary` 决定）。
- `EventMsg::TurnAborted` -> 先响应挂起 interrupt request，再发 `turn/completed(status=interrupted)`（`src/bespoke_event_handling.rs:269`, `src/bespoke_event_handling.rs:294`, `src/bespoke_event_handling.rs:1698`, `src/bespoke_event_handling.rs:1904`）。

2. 工具/命令/补丁 item
- 将 `ExecCommand*`、`PatchApply*`、`DynamicToolCall*`、MCP 工具事件映射成 `item/started` 与 `item/completed`。
- 对 `ExecCommandOutputDelta` 根据是否 file_change 场景，分发到 `fileChangeOutputDelta` 或 `commandExecution/outputDelta`（`src/bespoke_event_handling.rs:1496`, `src/bespoke_event_handling.rs:1543`, `src/bespoke_event_handling.rs:1583`, `src/bespoke_event_handling.rs:1638`）。

3. 审批请求闭环
- 事件触发 server request，下游客户端响应后回提 core `Op::*`；若遇 turn 状态切换导致请求失效，会识别 `turnTransition` 语义并安全退出（`src/server_request_error.rs:3`, `src/server_request_error.rs:5`）。

4. 线程回滚闭环
- `ThreadRolledBack` 到达后读取 rollout + 元数据重建 `ThreadRollbackResponse`，并补齐 thread name/status（`src/bespoke_event_handling.rs:1727`）。

### 5) 状态管理数据结构

1. `ThreadStateManager`（连接-线程订阅关系）
- 维护 live connections、每线程订阅连接集合、每连接订阅线程集合。
- 同时持有 `ThreadState`（中断队列、回滚挂起、turn summary、listener 控制）
（`src/thread_state.rs:141`, `src/thread_state.rs:264`, `src/thread_state.rs:316`）。

2. `ThreadWatchManager`（线程状态机）
- 将 runtime facts 归约为 `ThreadStatus::{NotLoaded, Idle, Active, SystemError}`。
- 同步发布 `thread/status/changed` 并维护 running turn 数量 watch channel（用于 graceful drain）
（`src/thread_status.rs:21`, `src/thread_status.rs:146`, `src/thread_status.rs:192`, `src/thread_status.rs:279`）。

### 6) 本地 API 关键实现

1. 配置 API（`ConfigApi`）
- 封装 `ConfigService`，提供 read/write/batchWrite/configRequirementsRead。
- `batch_write(reload_user_config=true)` 时会对所有已加载线程投递 `Op::ReloadUserConfig`。
- 写配置后会发插件开关 telemetry，并触发 plugin/skill 缓存清理（调用点在 `MessageProcessor`）
（`src/config_api.rs:57`, `src/config_api.rs:99`, `src/config_api.rs:134`, `src/config_api.rs:152`, `src/message_processor.rs:789`）。

2. 文件系统 API（`FsApi`）
- 通过 `codex_environment::ExecutorFileSystem` 统一文件操作实现。
- file 内容通过 base64 收发；`InvalidInput` 映射到 INVALID_REQUEST，其他错误映射 INTERNAL（`src/fs_api.rs:30`, `src/fs_api.rs:43`, `src/fs_api.rs:57`, `src/fs_api.rs:170`）。

3. 命令执行（`CommandExecManager`）
- 会话 key = `(connection_id, process_id)`，支持 client-provided processId 或自动生成。
- streaming 依赖 client processId；Windows restricted token 对 streaming 有限制。
- stdout/stderr 可流式推送 base64 delta，也可聚合后一次响应；支持超时、取消、PTY resize 与连接关闭清理（`src/command_exec.rs:47`, `src/command_exec.rs:142`, `src/command_exec.rs:177`, `src/command_exec.rs:307`, `src/command_exec.rs:565`, `src/command_exec.rs:656`）。

4. 模糊文件搜索
- 支持一次性搜索与 session 化增量更新；基于 `codex-file-search` + `spawn_blocking` 实现（`src/fuzzy_file_search.rs:21`, `src/fuzzy_file_search.rs:118`）。

### 7) 协议与命令约定

1. 协议定义来源
- `app-server-protocol` 使用 `client_request_definitions!` 宏定义 method <-> params/response 对应关系。
- 例如 `ThreadStart => "thread/start"`，并支持 experimental 字段/方法分层门禁（`codex-rs/app-server-protocol/src/protocol/common.rs:80`, `codex-rs/app-server-protocol/src/protocol/common.rs:205`）。

2. v2 参数类型
- `ThreadStartParams`、`TurnStartParams`、`CommandExecParams`、`FsReadFileParams` 等在 v2 中定义并导出 TS/JSON schema（`codex-rs/app-server-protocol/src/protocol/v2.rs:799`, `codex-rs/app-server-protocol/src/protocol/v2.rs:2122`, `codex-rs/app-server-protocol/src/protocol/v2.rs:2289`, `codex-rs/app-server-protocol/src/protocol/v2.rs:2454`, `codex-rs/app-server-protocol/src/protocol/v2.rs:3828`）。

3. 文档化命令
- README 提供 `generate-ts`、`generate-json-schema` 以及完整 API/事件/审批示例（`README.md:48`, `README.md:124`, `README.md:796`, `README.md:924`）。

## 关键代码路径与文件引用

### 启动与传输

1. `codex-rs/app-server/src/main.rs:26-44`
- CLI 入口，解析 `--listen` 并调用 `run_main_with_transport`。

2. `codex-rs/app-server/src/lib.rs:343-560`
- app-server 主调度：构建 transport/outbound/processor 任务与 config/otel 初始化。

3. `codex-rs/app-server/src/transport.rs:129-205`
- 传输与连接状态基础类型。

4. `codex-rs/app-server/src/transport.rs:264-331`
- stdio 连接读写循环。

5. `codex-rs/app-server/src/transport.rs:333-456`
- websocket acceptor 与连接处理。

6. `codex-rs/app-server/src/transport.rs:531-582`
- 入站消息背压与 overload 错误。

7. `codex-rs/app-server/src/transport.rs:684-707`
- 出站 envelope 路由（单播/广播）。

### 请求分发

1. `codex-rs/app-server/src/message_processor.rs:276-383`
- 原始 JSON-RPC 请求处理与 tracing context 绑定。

2. `codex-rs/app-server/src/message_processor.rs:497-774`
- initialize 门禁、experimental 门禁、分流到 Config/FS/Codex 处理器。

3. `codex-rs/app-server/src/codex_message_processor.rs:612-904`
- 核心业务 API 分发总入口。

4. `codex-rs/app-server/src/codex_message_processor.rs:1824-2114`
- `thread_start` 异步任务化执行（配置推导、listener 附着、响应+通知）。

5. `codex-rs/app-server/src/codex_message_processor.rs:5928-6110`
- `turn_start` 与 `turn_steer`。

6. `codex-rs/app-server/src/codex_message_processor.rs:6488-6542`
- `review_start`。

### 事件桥接与状态

1. `codex-rs/app-server/src/bespoke_event_handling.rs:252-1834`
- 核心 EventMsg -> app-server notification/server-request 翻译。

2. `codex-rs/app-server/src/thread_state.rs:141-359`
- 线程订阅与 listener 状态管理。

3. `codex-rs/app-server/src/thread_status.rs:21-278`
- thread status 跟踪与通知发布。

4. `codex-rs/app-server/src/outgoing_message.rs:81-606`
- outgoing envelope、pending callback、请求上下文与响应回传。

### 本地能力 API

1. `codex-rs/app-server/src/config_api.rs:57-170`
- config 读写与 requirements 映射。

2. `codex-rs/app-server/src/fs_api.rs:30-178`
- FS API 实现。

3. `codex-rs/app-server/src/command_exec.rs:47-693`
- command/exec 会话、流式输出、控制命令与错误映射。

4. `codex-rs/app-server/src/fuzzy_file_search.rs:18-244`
- 模糊搜索与 session reporter。

### 测试与文档

1. `codex-rs/app-server/tests/suite/v2/mod.rs:1-49`
- v2 集成测试矩阵总入口（包含 websocket、thread/turn、plugins、fs、config、审批等）。

2. `codex-rs/app-server/tests/common/lib.rs:1-39`
- 公共测试工具导出。

3. `codex-rs/app-server/README.md:20-1408`
- 协议说明、API/事件/审批、实验特性约定。

## 依赖与外部交互

### 1) 内部依赖关系（调用方/被调用方）

1. 调用方
- `codex-rs/cli`：`codex app-server` 子命令直接启动该服务（`codex-rs/cli/src/main.rs:646`）。
- `codex-rs/app-server-client`：封装 in-process 与 remote websocket 客户端（`codex-rs/app-server-client/src/lib.rs:1`, `codex-rs/app-server-client/src/remote.rs:112`）。
- `codex-rs/exec`、`codex-rs/tui_app_server`：通过 app-server-client 消费事件与请求接口（在全仓调用检索中可见）。

2. 被调用方
- `codex-core`：线程管理、配置、认证、plugins、mcp、review、工具执行核心能力（`Cargo.toml` workspace 依赖）。
- `codex-app-server-protocol`：RPC 类型、通知类型、schema 生成。
- `codex-environment`：FS 抽象实现。
- `codex-utils-pty`：PTY/进程控制。
- `codex-file-search`：模糊文件搜索。

### 2) 外部交互面

1. 网络
- websocket 监听与健康探针（axum）。
- 上游模型/认证网络访问由 core/backend-client 等间接完成。

2. 文件系统
- rollout/session 文件读写、配置文件读写、线程元数据（sqlite）更新。
- fs API 可直接读写绝对路径。

3. 进程执行
- `command/exec` 与 thread shell command 触发本机进程执行；在不同 sandbox 策略下行为不同。

4. 认证
- 支持 API Key、ChatGPT 登录、外部 tokens 刷新桥接（`ChatgptAuthTokensRefresh` server request）
（`src/message_processor.rs:84`, `src/message_processor.rs:512`）。

### 3) 配置、测试、脚本、文档联动

1. 配置
- `run_main_with_transport` 通过 `ConfigBuilder` + cloud requirements 预加载，失败时可回退默认配置并发 config warnings（`src/lib.rs:392`, `src/lib.rs:433`, `src/lib.rs:468`）。

2. 测试
- 单元测试散布在 `src/*.rs`。
- 集成测试统一入口 `tests/all.rs` + `tests/suite/v2/*`。

3. 文档
- `app-server/README.md` 是外部集成方的主要契约文档。

4. 调试/工具
- `src/bin/notify_capture.rs`、`src/bin/test_notify_capture.rs` 作为通知捕获辅助二进制。
- `codex-rs/app-server-test-client` 提供 websocket 端到端测试客户端与命令脚本。

## 风险、边界与改进建议

### 风险

1. 超大文件耦合风险
- `codex_message_processor.rs`（~9k 行）与 `bespoke_event_handling.rs`（~3.8k 行）职责面极广，变更冲突与回归概率高。

2. 协议双轨风险
- 代码仍维护 legacy `codex/event/*` 与 typed v2 notification 并存（外部丢弃、in-process保留），长期存在语义漂移风险（`src/transport.rs:588`, `src/in_process.rs:155`）。

3. 背压行为复杂性
- 不同消息类型在队列满时策略不同（request 立即 overload、response/notification 尝试等待或丢弃），若客户端未按建议重试，可能表现为随机失败。

4. 审批链路挂起风险
- 若客户端未及时回复 server request，turn 可能被阻塞；虽然存在 turnTransition 取消机制，但调用方仍需严格处理所有 request。

### 边界

1. app-server 本身不定义业务模型逻辑
- 主要做协议转换、状态桥接与生命周期编排，真正推理/工具执行由 `codex-core` 完成。

2. v2 是主演进面
- 目录中仍有兼容处理（legacy notifications、v1 局部结构），但新增能力主要沿 v2 协议推进。

3. 传输边界
- websocket 目前文档明确为 experimental/unsupported，不应作为稳定生产承诺（`README.md:31`, `README.md:44`）。

### 改进建议

1. 模块拆分优先级
- 先把 `CodexMessageProcessor::process_request` 按业务域拆成子处理器（thread、turn、plugins、mcp、account、ops tools），降低单文件认知负担。

2. 事件翻译器分层
- 将 `bespoke_event_handling` 拆为“审批事件翻译”“turn/item 翻译”“realtime 翻译”“协作子代理翻译”，并建立事件覆盖矩阵，避免新增 `EventMsg` 时漏翻译。

3. 背压可观测性增强
- 增加 per-connection 队列水位与 drop/disconnect 指标，便于外部客户端定位“慢连接被踢”问题。

4. 契约一致性自动校验
- 以 `README API 列表` vs `ClientRequest 枚举` 做自动对账，减少文档和实现漂移。

5. 审批请求超时策略显式化
- 目前多数审批依赖客户端主动回复；可考虑引入可配置超时与默认决策，避免长时间悬挂 turn。
