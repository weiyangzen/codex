# DIR `codex-rs/app-server-test-client` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/app-server-test-client`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 代码规模：`src/lib.rs` 约 2197 行（单文件承载全部 CLI 与 JSON-RPC 客户端逻辑）

## 场景与职责

`codex-app-server-test-client` 是一个“协议级调试/验收客户端”，定位不是最终用户产品，而是开发与联调用的测试驱动工具：

1. 作为独立二进制直接验证 `codex app-server` 行为
- 提供 `serve / watch / send-message-v2 / thread-resume / approval 触发` 等命令，覆盖 thread/turn 生命周期、审批回调、登录、模型列表、线程列表、elicitation 暂停等高风险路径（`codex-rs/app-server-test-client/src/lib.rs:149`, `codex-rs/app-server-test-client/src/lib.rs:273`）。

2. 作为 `codex-cli` 内部 debug 子命令的复用库
- `codex-rs/cli` 的 `debug app-server send-message-v2` 直接调用本 crate 的 `send_message_v2(...)`，避免 CLI 侧重复实现协议流程（`codex-rs/cli/src/main.rs:184`, `codex-rs/cli/src/main.rs:497`, `codex-rs/cli/src/main.rs:501`）。

3. 作为 app-server 协议“客户端参考实现”
- 严格走 `initialize -> initialized -> request/notification/response` JSON-RPC 循环，既能作为联调样例，也能复现 server request（审批）双向交互（`codex-rs/app-server-test-client/src/lib.rs:1516`, `codex-rs/app-server-test-client/src/lib.rs:1775`, `codex-rs/app-server-test-client/src/lib.rs:1820`）。

4. 作为实时问题定位工具
- 默认把收发 JSON-RPC pretty-print 到 stdout（前缀 `> / <`），并补充 Datadog trace summary，适合排查“请求发了什么、服务端回了什么、在哪条 trace 上失败”（`codex-rs/app-server-test-client/src/lib.rs:1775`, `codex-rs/app-server-test-client/src/lib.rs:2088`, `codex-rs/app-server-test-client/src/lib.rs:2159`）。

## 功能点目的

按命令族梳理其“为什么存在”：

1. 服务拉起与连接模式验证
- `serve`：后台启动 `codex app-server --listen`，落日志到 `/tmp/codex-app-server-test-client/app-server.log`，支持 `--kill` 清端口占用（`codex-rs/app-server-test-client/src/lib.rs:508`, `codex-rs/app-server-test-client/src/lib.rs:555`）。
- 目的：快速得到可复现的 websocket 端点，降低本地联调成本。

2. 基础协议与线程能力验证
- `send-message` / `send-message-v2` / `resume-message-v2` / `send-follow-up-v2` / `thread-resume` / `watch`（`codex-rs/app-server-test-client/src/lib.rs:628`, `codex-rs/app-server-test-client/src/lib.rs:649`, `codex-rs/app-server-test-client/src/lib.rs:798`, `codex-rs/app-server-test-client/src/lib.rs:983`, `codex-rs/app-server-test-client/src/lib.rs:834`, `codex-rs/app-server-test-client/src/lib.rs:855`）。
- 目的：覆盖 thread 创建、恢复、连续 turn、纯监听等核心路径。

3. 审批链路验证
- `trigger-cmd-approval` / `trigger-patch-approval` / `no-trigger-cmd-approval` / `trigger-zsh-fork-multi-cmd-approval`（`codex-rs/app-server-test-client/src/lib.rs:866`, `codex-rs/app-server-test-client/src/lib.rs:893`, `codex-rs/app-server-test-client/src/lib.rs:920`, `codex-rs/app-server-test-client/src/lib.rs:692`）。
- 目的：验证服务端 `item/commandExecution/requestApproval` 与 `item/fileChange/requestApproval` 回调是否触发、数量是否符合预期、拒绝后 turn 状态是否合理。

4. 账户与系统信息读取
- `test-login`、`get-account-rate-limits`、`model-list`、`thread-list`（`codex-rs/app-server-test-client/src/lib.rs:1031`, `codex-rs/app-server-test-client/src/lib.rs:1062`, `codex-rs/app-server-test-client/src/lib.rs:1080`, `codex-rs/app-server-test-client/src/lib.rs:1093`）。
- 目的：检查账户登录回调、模型元数据、线程分页读取等外围能力。

5. out-of-band elicitation 暂停验证
- `thread-increment-elicitation` / `thread-decrement-elicitation` + `live-elicitation-timeout-pause`（`codex-rs/app-server-test-client/src/lib.rs:1151`, `codex-rs/app-server-test-client/src/lib.rs:1165`）。
- 目的：验证“外部等待期间暂停超时计时”机制是否可靠，避免长时间用户确认或外部辅助流程被统一超时误杀。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 入口与命令分发

- `main.rs` 仅创建单线程 Tokio runtime 并调用 `run()`（`codex-rs/app-server-test-client/src/main.rs:4`）。
- `run()` 解析 `clap` 参数、处理 `--dynamic-tools` JSON，再按 `CliCommand` 分发（`codex-rs/app-server-test-client/src/lib.rs:273`, `codex-rs/app-server-test-client/src/lib.rs:1333`）。
- 端点抽象：
  - `Endpoint::SpawnCodex(PathBuf)`：拉起私有 stdio app-server
  - `Endpoint::ConnectWs(String)`：连接既有 websocket server（`codex-rs/app-server-test-client/src/lib.rs:425`）。

### 2) 两类传输：stdio 与 websocket

`CodexClient` 内部通过 `ClientTransport` 封装两套 IO：

- `spawn_stdio(...)`：`codex app-server` 子进程 + stdin/stdout 管道（`codex-rs/app-server-test-client/src/lib.rs:1408`）。
- `connect_websocket(...)`：`tungstenite::connect` + 10 秒重试窗口（`codex-rs/app-server-test-client/src/lib.rs:1459`）。

读写层统一成：
- `write_payload(...)`：向 stdin 或 websocket 文本帧写 JSON 字符串（`codex-rs/app-server-test-client/src/lib.rs:2025`）。
- `read_payload(...)`：从 stdout 行或 websocket 帧读取，过滤 ping/pong/binary（`codex-rs/app-server-test-client/src/lib.rs:2045`）。

### 3) JSON-RPC 协议闭环

关键实现链路：

1. 发送请求
- `send_request` -> `write_request`：将 typed `ClientRequest` 转 JSON-RPC，并注入当前 span trace context（`codex-rs/app-server-test-client/src/lib.rs:1746`, `codex-rs/app-server-test-client/src/lib.rs:1762`）。

2. 等待响应
- `wait_for_response`：按 request_id 匹配 response/error；notification 暂存到 `pending_notifications`；server request 立即处理（审批回包）（`codex-rs/app-server-test-client/src/lib.rs:1775`）。

3. 处理 server request（双向 RPC）
- `handle_server_request` 当前支持两类请求：
  - `item/commandExecution/requestApproval`
  - `item/fileChange/requestApproval`
  其他类型直接报错（`codex-rs/app-server-test-client/src/lib.rs:1882`）。
- 命令审批决策由 `CommandApprovalBehavior` 驱动，可实现“第 N 次拒绝”测试（`codex-rs/app-server-test-client/src/lib.rs:1385`, `codex-rs/app-server-test-client/src/lib.rs:1904`）。

4. 初始化握手
- 必发 `initialize`，随后发 `initialized` notification 完成握手（`codex-rs/app-server-test-client/src/lib.rs:1516`）。
- capability 里会携带：
  - `experimental_api`
  - `opt_out_notification_methods`（默认屏蔽高频 delta，减少噪音）（`codex-rs/app-server-test-client/src/lib.rs:90`, `codex-rs/app-server-test-client/src/lib.rs:1516`）。

### 4) turn 流式消费与断言状态

`stream_turn` 是核心观测器（`codex-rs/app-server-test-client/src/lib.rs:1677`）：

- 消费 `thread/started`、`turn/started`、`item/*`、`turn/completed`。
- 对 `AgentMessageDelta`、`CommandExecutionOutputDelta` 直接 stdout 流式打印。
- 记录命令执行 status/aggregated_output，支持后续验证。
- 维护辅助状态：
  - `helper_done_seen`
  - `unexpected_items_before_helper_done`
  - `turn_completed_before_helper_done`
  这些字段用于 live elicitation 场景证明“暂停确实生效”（`codex-rs/app-server-test-client/src/lib.rs:1367`, `codex-rs/app-server-test-client/src/lib.rs:1165`）。

### 5) live elicitation harness（脚本 + 命令 +协议）

`live_elicitation_timeout_pause(...)` 关键流程（`codex-rs/app-server-test-client/src/lib.rs:1165`）：

1. 解析 endpoint（可本地拉起临时 websocket app-server）。
2. 构造工具命令：执行 `scripts/live_elicitation_hold.sh`，并注入：
- `APP_SERVER_URL`
- `APP_SERVER_TEST_CLIENT_BIN`
- `ELICITATION_HOLD_SECONDS`
3. 发起 `turn/start`（`approval_policy=Never`, `sandbox_policy=DangerFullAccess`, `effort=High`）。
4. 流式监听并校验：
- turn 最终 `Completed`
- 至少一个 command item `Completed`
- 输出包含 `[elicitation-hold] done`
- 不应在 helper 完成前启动不期望 item
- 总耗时要明显超过 10 秒超时阈值
5. 无论成功失败都尝试 cleanup：调用 `thread/decrement_elicitation`。

脚本 `live_elicitation_hold.sh` 负责外部计数变更（`codex-rs/app-server-test-client/scripts/live_elicitation_hold.sh:4`）：
- 校验 env
- 从 `CODEX_THREAD_ID` 取 thread
- increment -> sleep -> decrement
- trap `EXIT/INT/TERM/HUP` 做兜底回滚（`codex-rs/app-server-test-client/scripts/live_elicitation_hold.sh:31`）。

### 6) dynamic tools 参数解析

- `--dynamic-tools` 支持 inline JSON 或 `@file`（`codex-rs/app-server-test-client/src/lib.rs:1333`）。
- 仅支持 object/array，最终归一成 `Option<Vec<DynamicToolSpec>>`。
- 命令级约束：绝大多数子命令不允许带 dynamic tools，仅 v2 thread/start 链路允许（`codex-rs/app-server-test-client/src/lib.rs:1321`）。

### 7) tracing 与配置读取

- `with_client(...)` 外包一层 tracing 初始化与 summary 打印（`codex-rs/app-server-test-client/src/lib.rs:1115`）。
- `TestClientTracing::initialize(...)` 会解析 `--config key=value` 覆盖，加载 `codex_core::Config`，然后尝试建立 OTEL provider（`codex-rs/app-server-test-client/src/lib.rs:2093`）。
- trace URL 从 W3C `traceparent` 提取 trace_id，格式化为 `go/trace/<trace_id>`（`codex-rs/app-server-test-client/src/lib.rs:2146`）。

## 关键代码路径与文件引用

### A. 目标目录核心文件

1. `codex-rs/app-server-test-client/src/main.rs`
- runtime 入口：`fn main`（第 4 行）

2. `codex-rs/app-server-test-client/src/lib.rs`
- CLI 命令定义：`CliCommand`（149）
- 总分发入口：`run`（273）
- endpoint 选择：`resolve_endpoint`（435）
- 后台服务拉起：`serve`（508）
- 端口清理：`kill_listeners_on_same_port`（555）
- 标准测试流程封装：`with_client`（1115）
- live elicitation 验证：`live_elicitation_timeout_pause`（1165）
- dynamic tools 解析：`parse_dynamic_tools_arg`（1333）
- JSON-RPC 客户端：`CodexClient`（1367）
- 初始化握手：`initialize_with_experimental_api`（1516）
- turn 流式消费：`stream_turn`（1677）
- 命令审批处理：`handle_command_execution_request_approval`（1904）
- 文件改动审批处理：`approve_file_change_request`（1983）
- tracing 初始化：`TestClientTracing`（2088）
- 进程退出收尾：`Drop for CodexClient`（2167）

3. `codex-rs/app-server-test-client/scripts/live_elicitation_hold.sh`
- 外部 elicitation 计数脚本（env 检查、increment/decrement、trap cleanup）

4. `codex-rs/app-server-test-client/README.md`
- quickstart 与手工联调路径（`Quickstart`、`watch`、`thread resume`）

5. `codex-rs/app-server-test-client/Cargo.toml`
- 协议与运行时依赖：`codex-app-server-protocol`、`codex-core`、`codex-otel`、`tungstenite`、`clap`。

6. `codex-rs/app-server-test-client/BUILD.bazel`
- Bazel crate 声明：`codex_rust_crate(name = "app-server-test-client", crate_name = "codex_app_server_test_client")`。

### B. 上下文依赖（调用方/被调用方/协议）

1. 调用方
- `just app-server-test-client`：先 build `codex-cli`，再 run test-client（`justfile:22`）。
- `codex-rs/cli` debug 子命令复用：`run_debug_app_server_command` -> `codex_app_server_test_client::send_message_v2(...)`（`codex-rs/cli/src/main.rs:497`）。

2. 被调用方
- `codex app-server`（stdio 或 websocket）是直接服务端。
- 协议方法定义来自 `app-server-protocol`：
  - `thread/start`（`codex-rs/app-server-protocol/src/protocol/common.rs:214`）
  - `thread/resume`（219）
  - `thread/increment_elicitation`（242）
  - `thread/decrement_elicitation`（250）
  - `thread/list`（283）
  - `turn/start`（351）
  - `model/list`（389）
  - 审批 server request：`item/commandExecution/requestApproval`（736）、`item/fileChange/requestApproval`（743）

3. app-server 实现映射
- initialize 门禁与 capability 生效：`message_processor.rs`（520, 608, 617）
- `thread/start` 与 dynamic tools 处理：`codex_message_processor.rs`（1824, 1946, 1976）
- increment/decrement elicitation 落地：`codex_message_processor.rs`（2217, 2252）

## 依赖与外部交互

### 1) 内部 crate 依赖

- 协议层：`codex-app-server-protocol`（typed request/response/notification）
- 配置与 tracing：`codex-core`、`codex-otel`
- CLI 配置覆盖：`codex-utils-cli`
- 模型参数类型：`codex-protocol`
- 传输与工具：`tungstenite`、`url`、`tokio`、`serde_json`、`uuid`、`clap`
（见 `codex-rs/app-server-test-client/Cargo.toml:13-24`）。

### 2) 外部命令与系统资源

- 进程管理：`nohup`, `sh`, `kill`, `lsof`, `tail -f /dev/null`（用于后台 server 拉起与端口清理，主要偏 POSIX）。
- 文件路径：`/tmp/codex-app-server-test-client/app-server.log`。
- 网络：默认 websocket 地址 `ws://127.0.0.1:4222`。

### 3) 外部用户交互

- `test-login` 会输出浏览器授权 URL，并阻塞等待 `account/login/completed` 通知。
- `watch/thread-resume` 会持续打印 inbound 消息，直到用户中断。

### 4) 文档与脚本交互

- README 提供最短联调路径（先 build `codex`，再 `serve`，再 `model-list`）。
- `scripts/live_elicitation_hold.sh` 作为 e2e harness 的外部 helper，被模型执行命令间接调用。

## 风险、边界与改进建议

1. 风险：单文件过大，维护成本高
- 现状：`src/lib.rs` 约 2197 行，CLI 参数、传输层、协议层、场景测试、trace、cleanup 全混在一处。
- 影响：变更耦合高，review 难度大，回归风险上升。
- 建议：按职责拆分 `commands/*`、`client/*`、`scenarios/live_elicitation.rs`、`tracing.rs`。

2. 风险：平台依赖偏 Unix
- `serve`/`kill_listeners_on_same_port`/`live_elicitation_hold.sh` 强依赖 `sh/lsof/nohup/kill`。
- Windows 下功能覆盖不完整（代码也显式拒绝某些场景）。
- 建议：将端口探测与进程回收迁移为 Rust 跨平台实现，脚本场景提供 `.ps1` 等替代。

3. 风险：审批 server request 支持面有限
- 当前仅实现 command/fileChange 两类 request，收到其他 server request 直接报错（`handle_server_request`）。
- 在协议持续演进（如 permissions/mcp elicitation/dynamic tool call）时，兼容性脆弱。
- 建议：增加可扩展 dispatch（至少“记录并安全忽略”未知 request），并按功能开关逐步支持更多 request 类型。

4. 边界：该工具本质是手工联调客户端，不是自动化测试替代
- 目录内没有 Rust 单测/集成测试文件，更多依赖人工命令路径与日志观察。
- 建议：沉淀可 CI 运行的 smoke tests（例如 websocket + initialize + thread/start + turn/start + completion）并最小化网络依赖。

5. 边界：dynamic tools 与 experimental API 的耦合要求高
- 仅在 experimental 场景可用，且很多命令显式禁止 `--dynamic-tools`。
- 建议：在 CLI 输出中增加更明确的“为什么被拒绝/应该改用哪个命令”提示，并在 README 添加 dynamic tools 示例。

6. 可观测性改进机会
- 已有 trace summary，但命令维度结果汇总仍以 stdout 文本为主。
- 建议：可选输出结构化 JSON report（包含 turn 状态、审批次数、耗时、错误摘要）以便脚本化消费。

7. 协议演进对齐风险
- `app-server-protocol` 在 v2 持续扩展；test-client 如不及时跟随，可能把“新能力未实现”误判为服务端问题。
- 建议：建立轻量 check 清单：当 common.rs/v2.rs 新增 server request 或高优先 client request 时，同步评估 test-client 支持矩阵。
