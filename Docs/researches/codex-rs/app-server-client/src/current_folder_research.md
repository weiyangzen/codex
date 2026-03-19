# DIR `codex-rs/app-server-client/src` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/app-server-client/src`
- 目标类型：`DIR`
- 研究日期：2026-03-19
- 目录内容：`lib.rs`、`remote.rs`

## 场景与职责

`codex-rs/app-server-client/src` 是 `codex-app-server-client` crate 的核心实现层，职责是给上层（`exec`、`tui_app_server`）提供统一的 app-server 客户端门面，并屏蔽“进程内运行”与“远程 websocket 连接”两种传输形态的差异。

该目录的边界非常清晰：

1. `lib.rs`
- 实现 in-process 客户端 `InProcessAppServerClient`。
- 定义跨传输统一抽象：`AppServerClient`、`AppServerRequestHandle`、`AppServerEvent`。
- 提供 typed request 错误分层 `TypedRequestError`。
- 在同文件内包含了当前 crate 的主要测试（含 in-process 与 remote 行为测试）。

2. `remote.rs`
- 实现 remote websocket 客户端 `RemoteAppServerClient`。
- 负责连接生命周期（连接、initialize/initialized 握手、读写循环、断连事件、关闭流程）。
- 将 JSON-RPC 文本帧与 typed 协议对象做互转。

3. 在架构中的位置
- 上游调用方：
  - `codex-rs/exec`（仅 in-process 路径，直接依赖 `InProcessAppServerClient`）。
  - `codex-rs/tui_app_server`（既支持 in-process，也支持 remote，主要依赖统一枚举 `AppServerClient`）。
- 下游被调用方：
  - `codex-rs/app-server/src/in_process.rs`（进程内 runtime 低层 handle）。
  - `codex-rs/app-server-protocol`（`ClientRequest` / `ServerRequest` / `RequestId` / JSON-RPC 类型定义）。

## 功能点目的

1. 统一 API，减少上层分支复杂度
- `AppServerClient` 与 `AppServerRequestHandle` 将 in-process/remote 的 request、notify、server-request 响应、事件消费统一成相同方法签名（`request_typed`/`next_event`/`shutdown` 等），让 TUI 会话层按单一接口编排。

2. 保持 app-server 协议语义一致
- 即使 in-process 路径不经过 socket，仍沿用 JSON-RPC 结果 envelope（成功 `result` / 失败 `error`），避免出现“同一 RPC 在本地和远端语义不同”的问题。

3. 明确启动身份与能力协商
- `InProcessClientStartArgs` / `RemoteAppServerConnectArgs` 都显式传入：
  - `client_name`、`client_version`
  - `experimental_api`
  - `opt_out_notification_methods`
- 这与 app-server 的 initialize 契约一致，确保连接粒度能力协商可控。

4. 背压下的可观测与可恢复
- 事件队列有界，拥塞时通过 `Lagged { skipped }` 显式告知上层。
- 对必须送达的终态事件（例如 turn 完成、断连）采用阻塞发送策略，降低“调用方永远等不到终态”风险。
- 当 `ServerRequest` 因队列拥塞无法投递时，立即回写错误（`-32001`）而不是静默丢弃，避免审批/用户输入流挂死。

5. 受控关闭
- in-process 与 remote 都实现“有限等待 graceful shutdown + 超时 abort”的收敛策略（默认超时 5 秒），避免后台任务泄漏。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) in-process 客户端主流程（`lib.rs`）

1. 启动
- `InProcessAppServerClient::start`：
  - 归一化 `channel_capacity.max(1)`。
  - 先构建共享 `AuthManager` + `ThreadManager`（迁移期保留对上层的 escape hatch）。
  - 调用 `codex_app_server::in_process::start(...)` 获取底层 handle。
  - 启动 worker：`tokio::select!` 同时处理 command 通道与 runtime 事件通道。

2. command 模型（`ClientCommand`）
- `Request`：为避免 worker 被长请求阻塞，request 发送与等待在 detached task 中进行。
- `Notify` / `ResolveServerRequest` / `RejectServerRequest`：直接经底层 sender 写入。
- `Shutdown`：请求 runtime shutdown，响应后退出 worker。

3. 事件背压策略
- 普通事件优先 `try_send`；队列满时累加 `skipped_events` 并发出 warning。
- 若被丢弃事件是 `ServerRequest`，立即调用 `fail_server_request` 回写 `-32001`。
- `event_requires_delivery` 识别“必须送达”事件：
  - typed: `ServerNotification::TurnCompleted`
  - legacy: `task_complete` / `turn_aborted` / `shutdown_complete`
- 对必须送达事件改用 `send().await`，即使拥塞也不丢。

4. typed request 错误分层
- `request_typed<T>` 先发 `request` 获取 `Result<JsonValue, JSONRPCErrorError>`，再做反序列化。
- 错误拆分为：
  - `Transport`（通道/worker 层）
  - `Server`（JSON-RPC error）
  - `Deserialize`（响应类型与调用方预期不匹配）

5. 关闭流程
- `shutdown(self)` 会先 drop caller 的 `event_rx`，避免 worker 卡在 must-deliver 发送。
- 再发 `Shutdown` command，等待 oneshot 结果（带 5s timeout）。
- 若 worker 超时仍未退出，执行 abort。

### 2) remote 客户端主流程（`remote.rs`）

1. 连接与初始化
- `RemoteAppServerClient::connect`：
  - URL 解析校验（`url::Url::parse`）。
  - `CONNECT_TIMEOUT=10s` 包裹 `connect_async`。
  - 调用 `initialize_remote_connection`：
    - 发 `initialize` request（固定 id: `"initialize"`）。
    - 等待对应 response/error（`INITIALIZE_TIMEOUT=10s`）。
    - 成功后发送 `initialized` notification。
  - 握手期间接收到的 notification/server request 先缓存到 `pending_events`，连接建立后优先回放。

2. 请求路由
- `pending_requests: HashMap<RequestId, oneshot::Sender<...>>` 维护 in-flight 请求。
- 发请求前先检查是否重复 request id；重复则立刻返回 `InvalidInput`，不发到服务端。
- 收到 JSON-RPC response/error 后按 id 反查 waiter 并回传。

3. 收包与事件转换
- websocket text frame 解析为 `JSONRPCMessage`。
- `Notification` -> `AppServerEvent::ServerNotification` 或 `LegacyNotification`。
- `Request` -> `ServerRequest::try_from`：
  - 可识别则投递 `AppServerEvent::ServerRequest`。
  - 不可识别则即刻回 `-32601 unsupported remote app-server request`。
- Close/transport error/invalid JSON 都转换为 `AppServerEvent::Disconnected { message }`。

4. remote 背压策略（`deliver_event`）
- 逻辑与 in-process 同构：队列满时给 `Lagged`。
- must-deliver 事件（含 `Disconnected`）使用阻塞发送。
- 若拥塞丢弃的是 `ServerRequest`，通过 `reject_if_server_request_dropped` 回 `-32001`。

5. 关闭流程
- 先发 `RemoteClientCommand::Shutdown`，尝试 `stream.close(None)`。
- 等待 command/worker 完成（均有 `SHUTDOWN_TIMEOUT` 限制）；超时 abort worker。

### 3) 关键数据结构

1. 统一事件模型 `AppServerEvent`
- `Lagged { skipped }`
- `ServerNotification(...)`
- `LegacyNotification(...)`
- `ServerRequest(...)`
- `Disconnected { message }`（remote 专有来源，但在统一层可被上游一致处理）

2. 统一客户端抽象
- `AppServerClient::{InProcess, Remote}`
- `AppServerRequestHandle::{InProcess, Remote}`
- 使 TUI 的会话层只关心语义，不关心底层 transport。

3. 命令通道模型
- in-process: `ClientCommand`
- remote: `RemoteClientCommand`
- 两者都通过 `mpsc + oneshot` 实现“异步提交 + 单次响应”。

### 4) 协议要点（与 app-server-protocol 对齐）

1. Client/Server 结构
- `ClientRequest` / `ServerRequest` / `ServerNotification` 定义于 `app-server-protocol` 宏展开产物。
- JSON-RPC 消息体为 `JSONRPCMessage::{Request, Notification, Response, Error}`。

2. initialize 协商
- 使用 v1 `InitializeParams`，`capabilities` 中含：
  - `experimental_api`（是否启用实验 API）
  - `opt_out_notification_methods`（精确方法名过滤）
- remote 路径严格执行 initialize/initialized 顺序。

### 5) 相关命令（研究与验证）

1. 目录/调用链检索
- `rg --files codex-rs/app-server-client/src`
- `rg -n "codex_app_server_client|InProcessAppServerClient|RemoteAppServerClient" codex-rs -S`

2. 代码阅读
- `nl -ba ... | sed -n 'start,endp'`

3. 单 crate 测试（建议）
- `cargo test -p codex-app-server-client`

## 关键代码路径与文件引用

### 目录内核心路径

1. in-process 启动与 worker
- `/home/sansha/Github/codex/codex-rs/app-server-client/src/lib.rs:332`

2. 事件必达判定（in-process）
- `/home/sansha/Github/codex/codex-rs/app-server-client/src/lib.rs:95`

3. typed request 错误分层
- `/home/sansha/Github/codex/codex-rs/app-server-client/src/lib.rs:546`

4. in-process 关闭收敛
- `/home/sansha/Github/codex/codex-rs/app-server-client/src/lib.rs:661`

5. 统一抽象 `AppServerClient`/`AppServerRequestHandle`
- `/home/sansha/Github/codex/codex-rs/app-server-client/src/lib.rs:742`
- `/home/sansha/Github/codex/codex-rs/app-server-client/src/lib.rs:761`

6. remote 连接与握手入口
- `/home/sansha/Github/codex/codex-rs/app-server-client/src/remote.rs:124`
- `/home/sansha/Github/codex/codex-rs/app-server-client/src/remote.rs:636`

7. remote 事件投递与背压
- `/home/sansha/Github/codex/codex-rs/app-server-client/src/remote.rs:766`
- `/home/sansha/Github/codex/codex-rs/app-server-client/src/remote.rs:830`
- `/home/sansha/Github/codex/codex-rs/app-server-client/src/remote.rs:852`

8. crate 内测试集合（in-process + remote）
- `/home/sansha/Github/codex/codex-rs/app-server-client/src/lib.rs:844`

### 调用方（上游）

1. exec 构建 in-process 启动参数
- `/home/sansha/Github/codex/codex-rs/exec/src/lib.rs:432`

2. exec 事件循环消费 `InProcessServerEvent`
- `/home/sansha/Github/codex/codex-rs/exec/src/lib.rs:744`

3. TUI 远程连接入口
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/lib.rs:339`

4. TUI 嵌入式启动入口
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/lib.rs:403`

5. TUI 会话层按统一 `AppServerClient` 调用 typed RPC
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/app_server_session.rs:143`

6. TUI 事件适配层消费 `AppServerEvent`
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/app/app_server_adapter.rs:119`

### 被调用方（下游）

1. app-server in-process 低层 runtime（本 crate 的直接后端）
- `/home/sansha/Github/codex/codex-rs/app-server/src/in_process.rs:34`
- `/home/sansha/Github/codex/codex-rs/app-server/src/in_process.rs:256`

2. app-server-protocol 协议定义
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs:81`
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs:543`
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs:662`
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v1.rs:26`
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/jsonrpc_lite.rs:35`

## 依赖与外部交互

### 1) 代码依赖

1. crate 级依赖（`codex-rs/app-server-client/Cargo.toml`）
- 内部：`codex-app-server`、`codex-app-server-protocol`、`codex-core`、`codex-protocol`、`codex-feedback`、`codex-arg0`
- 运行时/传输：`tokio`、`futures`、`tokio-tungstenite`、`url`
- 序列化：`serde`、`serde_json`、`toml`

2. 构建系统
- Cargo 与 Bazel 双轨：`Cargo.toml` + `BUILD.bazel`（`codex_rust_crate(name = "app-server-client")`）。

### 2) 外部交互面

1. in-process 模式
- 不经过网络 socket，直接与 app-server runtime 的内存队列交互。
- 仍保留 JSON-RPC 结果 envelope 作为响应契约。

2. remote 模式
- 通过 websocket 文本帧与远端 app-server 交换 JSON-RPC。
- 需要显式 `initialize` -> `initialized` 握手。

3. 与配置的关联
- 调用方将 `Config`、`loader_overrides`、`cloud_requirements`、`startup_warnings` 透传到 `InProcessClientStartArgs`。
- `session_source` 在 `exec` 和 `tui` 中分别显式设定（`Exec` / `Cli`），影响 thread metadata。
- `enable_codex_api_key_env` 由调用方决定（`exec=true`、`tui=false`）。

### 3) 测试、脚本、文档上下文

1. 测试
- 当前目录源码测试集中在 `lib.rs`，覆盖：
  - in-process typed 请求、session source、生存期与 shared manager 行为
  - remote 握手、request id 冲突、notification、server request 回路、断连
  - 背压 `Lagged` 与终态必达判定

2. 脚本
- 本目录无专有脚本。
- 研究流程相关脚本在仓库根 `.ops/`（例如本次要求的 `generate_daily_research_todo.sh`），属于文档生产流程，不参与运行时逻辑。

3. 文档
- crate 说明：`/home/sansha/Github/codex/codex-rs/app-server-client/README.md`
- 协议总览：`/home/sansha/Github/codex/codex-rs/app-server/README.md`

## 风险、边界与改进建议

1. 风险：`lib.rs` 体量过大（1570 行）
- 现状：生产代码与大量测试共处同一文件，维护与审阅成本较高。
- 建议：按责任拆分为 `in_process_client.rs`、`unified_client.rs`、`tests/remote.rs` 等模块，降低认知负担。

2. 风险：legacy + typed 双事件并存带来分支复杂度
- 现状：`AppServerEvent` 同时支持 `ServerNotification` 与 `LegacyNotification`，上游适配层需要双通道处理。
- 建议：定义明确淘汰窗口，逐步收缩 legacy 分支；在 TUI/exec 增加“已覆盖的 typed 事件清单”回归测试。

3. 风险：背压策略是“丢事件 + Lagged 提示”
- 现状：在高负载下会丢非必达事件，依赖上层可容忍性。
- 建议：
  - 对关键但非终态的事件分级（例如可选二级缓冲或优先级队列）。
  - 增加指标埋点（lagged 次数、最大 skipped 值）支持容量调优。

4. 风险：remote 握手前缓存事件的时序复杂度
- 现状：`initialize_remote_connection` 会缓存握手期间到达的 notification/request 并回放。
- 建议：补充更多边界测试（握手期间大量事件、握手失败后的缓存清理、不同 request id 类型混合）。

5. 边界：request id 唯一性由调用方负责
- 现状：remote 在 in-flight 阶段发现重复 id 会报错，但无法阻止调用方重复使用策略失误。
- 建议：在统一层提供可选 request id 生成器或 debug 断言辅助，减少业务层误用。

6. 边界：断连语义只在 remote 显式事件化
- 现状：`AppServerEvent::Disconnected` 主要来自 remote；in-process 断开通常体现为 channel 关闭。
- 建议：统一故障语义（例如引入统一“transport degraded/closed”事件），降低上游处理分叉。
