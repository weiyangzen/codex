# DIR `codex-rs/app-server-client` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/app-server-client`
- 目标类型：`DIR`
- 研究日期：2026-03-19
- 关联调用方：`codex-rs/exec`、`codex-rs/tui_app_server`
- 关联被调用方：`codex-rs/app-server`（`in_process`）、`codex-rs/app-server-protocol`

## 场景与职责

`codex-app-server-client` 是 app-server 的“客户端门面层（facade）”。它的核心定位不是新增协议，而是把同一套 app-server JSON-RPC 语义以两种传输形态统一暴露给上层：

1. In-process（进程内）模式
- 面向 `codex-exec` 与默认 TUI 的嵌入式运行路径。
- 封装 `codex_app_server::in_process`，把底层 `InProcessClientHandle` 提升为 async request/notify/event API。

2. Remote（websocket）模式
- 面向 TUI 的 `--remote ws://...` 连接路径。
- 负责 websocket 生命周期、`initialize/initialized` 握手、JSON-RPC request/response 路由、断连与背压信号。

3. 统一抽象层
- 通过 `AppServerClient` / `AppServerRequestHandle` / `AppServerEvent` 把 in-process 与 remote 行为收敛到同一接口，调用方可以在会话层无感切换。

## 功能点目的

1. 启动与身份注入
- `InProcessClientStartArgs` 明确要求调用方传入 `session_source`、`client_name`、`client_version`、capabilities，确保线程元数据与调用来源一致（避免把策略硬编码进库）。

2. 请求/通知发送与类型化响应
- 同时提供 `request`（返回 JSON-RPC envelope）与 `request_typed<T>`（解码为具体响应类型）。
- `TypedRequestError` 将错误分层为 Transport / Server / Deserialize，减少调用方误判。

3. ServerRequest 闭环
- 提供 `resolve_server_request` 与 `reject_server_request`，支持审批、elicitation、request_user_input 等反向请求闭环。

4. 事件流与背压保护
- 事件队列有界；消费者落后时投递 `Lagged`。
- 对必须送达事件（如 `turn/completed`、legacy `task_complete/turn_aborted/shutdown_complete`、remote 的 `Disconnected`）采取“阻塞发送”策略，避免调用方永远等不到终态。

5. 可控关闭
- `shutdown()` 使用 5 秒超时，优先 graceful，超时后 abort worker，防止调用方泄露后台任务。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) in-process 路径

1. 启动流程
- `InProcessAppServerClient::start`：
  - 归一化 `channel_capacity>=1`。
  - 构建共享 `AuthManager` + `ThreadManager`（临时迁移期 escape hatch）。
  - 调用 `codex_app_server::in_process::start` 拉起嵌入 runtime。
  - 启动 worker task，在 `command_rx` 与 `handle.next_event()` 间 `tokio::select!`。

2. 指令面（`ClientCommand`）
- `Request`：拆到 detached task 执行，避免 worker 因等待请求响应而停止 drain event。
- `Notify` / `ResolveServerRequest` / `RejectServerRequest`：同步发送到 runtime sender。
- `Shutdown`：触发底层 shutdown，回传结果后退出循环。

3. 事件面与背压
- 正常事件走 `try_send`，队列满时计数 `skipped_events` 并上报 warning。
- 若被丢弃的是 `ServerRequest`，立即回写 `-32001` 错误，避免审批流悬挂。
- 对必须送达事件，改为 `send().await`，即使拥塞也不丢终态信号。

4. 请求类型化
- `request_typed<T>` 先拿 method 名（`request_method_name`），再分层映射错误：
  - mpsc/oneshot 通道异常 -> `Transport`
  - JSON-RPC `error` -> `Server`
  - `serde_json::from_value` 失败 -> `Deserialize`

### 2) remote websocket 路径

1. 连接与握手
- `RemoteAppServerClient::connect`：
  - URL 解析校验。
  - `CONNECT_TIMEOUT=10s` 包裹 `connect_async`。
  - 调用 `initialize_remote_connection` 发起 `initialize`，等待响应（`INITIALIZE_TIMEOUT=10s`），随后发送 `initialized`。
  - 握手期间收到的通知/服务端请求会暂存到 `pending_events`，连接成功后优先回放。

2. worker 双向路由
- 下行（调用方->服务器）：`RemoteClientCommand`（Request/Notify/Resolve/Reject/Shutdown）。
- 上行（服务器->调用方）：解析 websocket text frame 为 `JSONRPCMessage`，按 Response/Error/Notification/Request 分派。

3. 请求 ID 一致性
- `pending_requests: HashMap<RequestId, oneshot::Sender<...>>` 追踪 in-flight 请求。
- 若新请求 ID 与 in-flight 冲突，直接向调用方返回 `InvalidInput`，防止响应错配。

4. 服务端请求处理
- 能转换为 `ServerRequest` 的请求进入事件流。
- 不支持的方法立即回 `-32601`（`unsupported remote app-server request ...`）。

5. remote 背压与断连
- 复用 `deliver_event` 机制：有界队列 + `Lagged` 标记 + must-deliver。
- 如果因拥塞丢弃 `ServerRequest`，立即反向回写 `-32001 remote app-server event queue is full`。
- 连接关闭/传输错误/JSON 解析失败都转换为 `AppServerEvent::Disconnected { message }`。

### 3) 统一接口层

- `AppServerClient` 与 `AppServerRequestHandle` 使用 enum 分派，把 in-process/remote 实例对齐到同一调用面：
  - `request(_typed)`
  - `notify`
  - `resolve_server_request` / `reject_server_request`
  - `next_event`
  - `shutdown`

### 4) 协议与命令语义

1. 协议来源
- 请求/通知/服务端请求定义由 `app-server-protocol` 的宏体系生成（`ClientRequest` / `ClientNotification` / `ServerRequest` / `ServerNotification`）。

2. 初始化协商
- `initialize.params.capabilities` 包含：
  - `experimentalApi`
  - `optOutNotificationMethods`
- app-server 文档要求：每连接必须 `initialize` 后才能执行其他方法，并发送 `initialized` 通知。

3. 传输边界
- in-process 虽是 typed 请求，但响应仍保持 JSON-RPC result envelope，保证与 stdio/ws 语义一致。

## 关键代码路径与文件引用

### 目录内核心实现

1. `codex-rs/app-server-client/src/lib.rs:172`
- `InProcessClientStartArgs`：启动参数与 capabilities 构建。

2. `codex-rs/app-server-client/src/lib.rs:338`
- `InProcessAppServerClient::start`：worker、命令通道、事件通道、背压逻辑主入口。

3. `codex-rs/app-server-client/src/lib.rs:95`
- in-process `event_requires_delivery`：终态事件保序/保送达。

4. `codex-rs/app-server-client/src/lib.rs:546`
- in-process `request_typed<T>`：分层错误封装。

5. `codex-rs/app-server-client/src/lib.rs:661`
- in-process `shutdown`：drop `event_rx` + bounded graceful + abort fallback。

6. `codex-rs/app-server-client/src/remote.rs:125`
- `RemoteAppServerClient::connect`：连接、握手、worker 初始化。

7. `codex-rs/app-server-client/src/remote.rs:636`
- `initialize_remote_connection`：握手阶段消息处理与 pending_events 收集。

8. `codex-rs/app-server-client/src/remote.rs:766`
- `deliver_event`：remote 背压/lagged/必达策略。

9. `codex-rs/app-server-client/src/remote.rs:830`
- `reject_if_server_request_dropped`：拥塞时避免 server request 无回应。

10. `codex-rs/app-server-client/src/remote.rs:852`
- remote `event_requires_delivery`：含 `Disconnected` 必达语义。

### 调用方路径（上游）

1. `codex-rs/exec/src/lib.rs:432`
- `codex-exec` 构造 `InProcessClientStartArgs`（`session_source=Exec`，`client_name=codex-exec`）。

2. `codex-rs/exec/src/lib.rs:538`
- 启动 in-process client；主循环消费 `InProcessServerEvent`。

3. `codex-rs/exec/src/lib.rs:780`
- 处理 server request；对 lagged 打告警并输出用户可见 warning。

4. `codex-rs/tui_app_server/src/lib.rs:339`
- remote 目标时调用 `RemoteAppServerClient::connect`（`client_name=codex-tui`）。

5. `codex-rs/tui_app_server/src/lib.rs:403`
- embedded 目标时调用 `InProcessAppServerClient::start`。

6. `codex-rs/tui_app_server/src/app/app_server_adapter.rs:126`
- TUI 统一消费 `AppServerEvent`（lagged / disconnected / server request / notifications）。

7. `codex-rs/cli/src/main.rs:1070`
- `--remote` 参数规范化并注入 `tui_app_server::run_main`（仅交互 TUI 支持）。

### 被调用方与协议路径（下游）

1. `codex-rs/app-server/src/in_process.rs:1`
- in-process runtime 语义说明与 `codex-app-server-client` 的职责分层。

2. `codex-rs/app-server/src/in_process.rs:349`
- `start` 返回底层 `InProcessClientHandle`。

3. `codex-rs/app-server-protocol/src/protocol/common.rs:100`
- `ClientRequest` 定义宏展开入口。

4. `codex-rs/app-server-protocol/src/protocol/common.rs:561`
- `ServerRequest` 类型定义与 `TryFrom<JSONRPCRequest>`。

5. `codex-rs/app-server-protocol/src/protocol/common.rs:662`
- `ServerNotification` 定义与转换。

6. `codex-rs/app-server-protocol/src/protocol/v1.rs:28`
- `InitializeParams` / `InitializeCapabilities` 定义。

### 文档与构建辅助

1. `codex-rs/app-server-client/README.md:1`
- 该 crate 的职责、传输模型、启动语义与背压说明。

2. `codex-rs/app-server/README.md:78`
- initialize/initialized 握手契约与 capabilities 语义。

3. `codex-rs/app-server-client/Cargo.toml:1`
- 依赖面（`codex-app-server`、`codex-app-server-protocol`、`tokio-tungstenite` 等）。

4. `codex-rs/app-server-client/BUILD.bazel:1`
- Bazel crate 目标定义。

## 依赖与外部交互

### 1) 内部依赖

1. `codex-app-server`
- 提供 in-process runtime 与事件源。

2. `codex-app-server-protocol`
- 提供所有 RPC 类型（请求、通知、响应、错误、RequestId）。

3. `codex-core` / `codex-feedback` / `codex-protocol` / `codex-arg0`
- 启动嵌入 runtime 所需上下文（配置、thread/auth 管理、启动来源、执行路径）。

### 2) 外部依赖与 I/O

1. `tokio`
- `mpsc` + `oneshot` + timeout + worker task 调度。

2. `tokio-tungstenite`
- remote websocket 传输（连接、收发、关闭帧处理）。

3. `serde/serde_json`
- typed 请求与 JSON-RPC 消息互转（含 method 提取、typed 反序列化）。

4. `url`
- websocket URL 解析与输入校验。

### 3) 测试覆盖（目录内）

测试集中在 `src/lib.rs`，覆盖面较完整：

1. in-process 基线
- typed 请求成功/JSON-RPC 失败。
- `session_source` 注入正确性。
- 极小 channel capacity (`1`) 可用性。

2. 共享 manager 行为
- thread 经 app-server 创建后可被 retained `ThreadManager` 观察到。
- `auth_manager` / `thread_manager` accessor 稳定性。

3. remote 行为
- initialize 握手 + typed 请求 roundtrip。
- duplicate request id 拒绝。
- 通知接收、server request resolve。
- initialize 期间 server request 先到达时的缓存投递。
- unknown server request 自动 `-32601`。
- disconnect 转事件。

4. 背压与收尾
- `Lagged` marker 出流。
- 必达事件判断函数行为。
- shutdown 在 retained manager 场景下及时完成。

## 风险、边界与改进建议

1. 风险：序列化转换函数使用 `panic!`
- `jsonrpc_request_from_client_request` 与 `jsonrpc_notification_from_client_notification` 在转换失败时 `panic!`，理论上会把协议回归问题升级为进程级崩溃。
- 建议：改为 `Result` 返回并在调用路径转为 `IoError::other`，让调用方可恢复。

2. 风险：请求 ID 唯一性约束靠调用方自律
- in-process 与 remote 都依赖“并发 in-flight 请求 ID 不冲突”；remote 显式拦截，in-process 语义也要求唯一。
- 建议：在公共 facade 暴露可选 `RequestIdSequencer` helper，减少调用方重复实现与误用。

3. 边界：背压策略偏保守但可观察性不足
- 现有仅 warning + `Lagged` 事件，缺少结构化 metrics（drop 数、must-deliver 阻塞时长、server-request 被拒计数）。
- 建议：补充 tracing fields/otel counters，便于定位 UI 侧消费瓶颈。

4. 边界：in-process 与 remote 逻辑有重复
- `request/request_typed/notify/resolve/reject/shutdown` 在多处重复，维护成本偏高。
- 建议：抽象共享 helper（例如命令发送 + oneshot 等待模板），降低行为漂移风险。

5. 边界：legacy notification 仍在链路中
- 当前仍需并行处理 typed notification 与 legacy `codex/event/*`，说明迁移未完全结束。
- 建议：在调用方补充分阶段去除计划与兼容层开关，降低长期复杂度。

6. 风险：remote 初始化期间 pending_events 无容量保护
- `pending_events` 是握手阶段内存缓存，若服务端异常大量推送，可能造成瞬时内存压力。
- 建议：增加上限或在握手期对非关键通知做限流/丢弃策略。

7. 边界：关闭序列竞态可进一步测试化
- 代码已通过 drop receiver + timeout 处理常见竞态，但缺少针对“must-deliver 阻塞 + 同时 shutdown”更激进场景的专门测试。
- 建议：新增压力测试/loom 风格并发测试，验证无死锁与无泄露。
