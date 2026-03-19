# DIR `codex-rs/app-server-test-client/src` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/app-server-test-client/src`
- 目录文件：`lib.rs`（主实现，2197 行）、`main.rs`（入口，极薄封装）
- 关联上游：`codex-rs/cli`（debug 子命令调用）、`codex-rs/app-server-protocol`（JSON-RPC 类型与方法定义）、`codex-rs/app-server`（服务端实现）
- 关联文档：`codex-rs/app-server-test-client/README.md`、`codex-rs/app-server/README.md`

## 场景与职责

`codex-app-server-test-client` 的定位是“协议级调试/验收客户端”，职责不是终端产品 UI，而是把 app-server 的关键交互链路（初始化、thread/turn、审批回调、登录、模型/线程查询、out-of-band elicitation）快速跑通并可观测化。

核心职责：

- 作为手动联调入口：通过命令行一键触发 `thread/start`、`turn/start`、`thread/resume`、`watch` 等场景（`codex-rs/app-server-test-client/src/lib.rs:149`, `codex-rs/app-server-test-client/src/lib.rs:273`）。
- 作为协议样例客户端：严格执行 `initialize -> initialized` 握手，再进入 request/response + notification 流程（`codex-rs/app-server-test-client/src/lib.rs:1516`）。
- 作为审批回调处理方：接收 server request 并返回命令审批/文件变更审批决策（`codex-rs/app-server-test-client/src/lib.rs:1885`, `codex-rs/app-server-test-client/src/lib.rs:1904`, `codex-rs/app-server-test-client/src/lib.rs:1983`）。
- 作为活体验证 harness：验证“out-of-band elicitation 暂停 unified exec 超时计时”的端到端行为（`codex-rs/app-server-test-client/src/lib.rs:1165`）。

## 功能点目的

按命令族划分：

- 生命周期与消息流：
  - `serve`：后台拉起 `codex app-server --listen ...`，日志落 `/tmp/codex-app-server-test-client/app-server.log`（`lib.rs:508`）。
  - `watch`：完成初始化后持续打印入站 JSON-RPC（`lib.rs:855`）。
  - `send-message/send-message-v2/resume-message-v2/send-follow-up-v2/thread-resume`：覆盖新线程、续接线程、同线程多 turn、纯跟随流等常见调试路径（`lib.rs:628`, `lib.rs:666`, `lib.rs:798`, `lib.rs:983`, `lib.rs:834`）。

- 审批场景：
  - `trigger-cmd-approval`：构造会触发 `item/commandExecution/requestApproval` 的 turn（`lib.rs:866`）。
  - `trigger-patch-approval`：构造会触发 `item/fileChange/requestApproval` 的 turn（`lib.rs:893`）。
  - `no-trigger-cmd-approval`：反向验证“不应触发审批”的分支（`lib.rs:920`）。
  - `trigger-zsh-fork-multi-cmd-approval`：验证多次审批回调与“第 N 次拒绝”逻辑（`lib.rs:692`）。

- 账号与目录查询：
  - `test-login`、`get-account-rate-limits`、`model-list`、`thread-list`（`lib.rs:1031`, `lib.rs:1062`, `lib.rs:1080`, `lib.rs:1093`）。

- timeout pause 专项：
  - `thread-increment-elicitation` / `thread-decrement-elicitation`：直接调用实验方法操作线程级计数（`lib.rs:1137`, `lib.rs:1151`）。
  - `live-elicitation-timeout-pause`：自动化串联脚本、turn、通知流并做断言（`lib.rs:1165`）。

- 调用方补充：
  - `codex-rs/cli` 的 `debug app-server send-message-v2` 复用本 crate 的 `send_message_v2(...)`（`codex-rs/cli/src/main.rs:184`, `codex-rs/cli/src/main.rs:497`）。
  - `just app-server-test-client` 先编译 `codex-cli`，再运行该客户端（`justfile:22`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 入口与命令分发

- `main.rs` 只做单线程 Tokio runtime 初始化并调用 `run()`（`codex-rs/app-server-test-client/src/main.rs:4`）。
- `run()` 解析 `clap` 参数、解析 `--dynamic-tools`，再 `match CliCommand` 分发（`lib.rs:273`, `lib.rs:1333`）。
- `--dynamic-tools` 仅允许用于 v2 thread/start 链路；非相关命令会被拒绝（`lib.rs:1321`）。

### 2) 传输模型：stdio + websocket 双栈

- `Endpoint`：
  - `SpawnCodex(PathBuf)`：通过子进程启动 `codex app-server` 并走 stdin/stdout JSONL。
  - `ConnectWs(String)`：连接已有 websocket app-server（`lib.rs:425`）。
- `resolve_endpoint` 与 `resolve_shared_websocket_url` 负责参数约束（如 `--codex-bin` 与 `--url` 互斥、某些命令必须复用共享 ws server）（`lib.rs:435`, `lib.rs:448`）。
- `connect_websocket` 内置 10 秒重试窗口，失败时给出明确修复提示（`lib.rs:1459`）。

### 3) serve 模式与后台进程管理

- `serve(...)` 使用 `nohup sh -c ...` 后台拉起服务，stdout/stderr 双写到日志文件（`lib.rs:508`）。
- 命令串里采用 `tail -f /dev/null | ... codex app-server`，保证上游 stdin 持续可读，避免标准输入提前 EOF。
- 可选 `--kill` 会先通过 `lsof` 找端口监听进程，先 `SIGTERM` 再 `SIGKILL`（`lib.rs:555`）。

### 4) CodexClient 结构与 JSON-RPC 循环

- `CodexClient` 维护：
  - transport（stdio/ws）；
  - `pending_notifications` 缓冲；
  - 审批统计与 command item 观测状态（`lib.rs:1367`）。
- `initialize_with_experimental_api` 发送 `initialize`（带 `clientInfo` 与 `capabilities`），随后补发 `initialized` notification 完成握手（`lib.rs:1516`）。
- 默认 capability 会 opt-out 高频 delta（`NOTIFICATIONS_TO_OPT_OUT`），减少噪声（`lib.rs:90`）。这与 app-server 文档中的 `optOutNotificationMethods` 机制一致（`codex-rs/app-server/README.md:80`）。

请求/响应处理管线：

- `send_request`：打 span -> `write_request` -> `wait_for_response`（`lib.rs:1780`, `lib.rs:1813`）。
- `write_request`：将 typed `ClientRequest` 转 `JSONRPCRequest`，注入 W3C trace context，再序列化发送（`lib.rs:1798`）。
- `wait_for_response`：
  - 命中目标 request_id 的 response/error 即返回；
  - notification 暂存队列；
  - server request 立即处理（审批回包）（`lib.rs:1813`, `lib.rs:1885`）。

### 5) turn 流式观测与断言状态

`stream_turn` 是最关键的“事件消费 + 测试状态采样器”（`lib.rs:1677`）：

- 实时打印 `thread/started`、`turn/started`、agent delta、command output delta；
- 在 `item/started` / `item/completed` 记录 command execution 状态与聚合输出；
- 在 `turn/completed` 记录最终 `TurnStatus`、错误信息并退出循环；
- 维护 `helper_done_seen / turn_completed_before_helper_done / unexpected_items_before_helper_done` 等字段，用于 live elicitation 场景完整性校验。

### 6) 审批回调处理

- `handle_server_request` 仅处理两类 server request：
  - `item/commandExecution/requestApproval`
  - `item/fileChange/requestApproval`
  其他类型直接报错（`lib.rs:1885`）。
- 命令审批：
  - 采集 reason、cwd、available decisions、skill metadata 等上下文并打印；
  - 根据 `CommandApprovalBehavior` 决策 Accept/Cancel（支持第 N 次拒绝）；
  - 回写 `CommandExecutionRequestApprovalResponse`（`lib.rs:1904`）。
- 文件变更审批：默认 Accept 并回写（`lib.rs:1983`）。

与协议定义对应关系：

- client method 映射：`thread/start`、`thread/resume`、`turn/start`、`thread/increment_elicitation`、`thread/decrement_elicitation`（`codex-rs/app-server-protocol/src/protocol/common.rs:214`, `:219`, `:242`, `:250`, `:351`）。
- server request 映射：`item/commandExecution/requestApproval`、`item/fileChange/requestApproval`（`common.rs:736`, `:743`）。
- 审批参数结构与可裁剪实验字段（`strip_experimental_fields`）在 v2 协议层定义（`codex-rs/app-server-protocol/src/protocol/v2.rs:5022`, `:5082`, `:5108`）。

### 7) live elicitation timeout pause harness

`live_elicitation_timeout_pause(...)`（`lib.rs:1165`）主流程：

1. 校验运行环境（非 Windows，`hold_seconds > 10`）。
2. 解析 endpoint；若给了 `--codex-bin` 且没给 `--url`，会临时起一个 background ws app-server。
3. 定位 helper 脚本（默认 `scripts/live_elicitation_hold.sh`）。
4. 启线程并发起 turn，prompt 强制模型仅调用一次 `exec_command` 执行脚本命令。
5. 消费 `stream_turn`，并基于 elapsed/status/output markers 做断言：
   - turn 应完成；
   - command execution 应完成；
   - 输出必须含 `[elicitation-hold] done`；
   - turn 不得在 helper 完成前结束；
   - 总耗时需足以证明 timeout 被暂停。
6. 无论验证结果如何，都会 best-effort 调一次 decrement 做清理。

脚本侧关键动作：

- 读取 `APP_SERVER_URL`、`APP_SERVER_TEST_CLIENT_BIN`、`CODEX_THREAD_ID`；
- 先 increment，sleep，后 decrement；
- 用 `trap` 保证异常退出时兜底 decrement（`codex-rs/app-server-test-client/scripts/live_elicitation_hold.sh:12`, `:31`, `:33`, `:41`）。

服务端对应实现：

- `thread_increment_elicitation` / `thread_decrement_elicitation` 在 `codex_message_processor` 中更新线程 out-of-band 计数并返回 `{count, paused}`（`codex-rs/app-server/src/codex_message_processor.rs:2217`, `:2252`）。
- 协议结构定义在 `v2.rs`（`codex-rs/app-server-protocol/src/protocol/v2.rs:2746`, `:2755`, `:2766`, `:2775`）。

### 8) tracing 与可观测性

- `with_client(...)` 统一做 tracing 初始化、命令级 span 包装、执行后 summary 输出（`lib.rs:1115`）。
- `TestClientTracing::initialize` 解析 CLI config overrides，加载 `codex_core::Config`，并尝试挂载 OTEL tracing layer（`lib.rs:2088`）。
- trace summary 从 `traceparent` 提取 trace_id，输出 `go/trace/<trace_id>`（`lib.rs:2146`）。

## 关键代码路径与文件引用

主路径：

1. `codex-rs/app-server-test-client/src/main.rs:4`
2. `codex-rs/app-server-test-client/src/lib.rs:273`（`run` 命令入口）
3. `codex-rs/app-server-test-client/src/lib.rs:425`（endpoint 抽象）
4. `codex-rs/app-server-test-client/src/lib.rs:508`（后台启动）
5. `codex-rs/app-server-test-client/src/lib.rs:1367`（`CodexClient` 核心状态）
6. `codex-rs/app-server-test-client/src/lib.rs:1516`（初始化握手）
7. `codex-rs/app-server-test-client/src/lib.rs:1677`（turn 流式消费）
8. `codex-rs/app-server-test-client/src/lib.rs:1813`（response 等待与 server request 夹带处理）
9. `codex-rs/app-server-test-client/src/lib.rs:1885`（server request 分发）
10. `codex-rs/app-server-test-client/src/lib.rs:1165`（live elicitation harness）
11. `codex-rs/app-server-test-client/src/lib.rs:2088`（tracing 初始化）

上下文文件：

1. `codex-rs/app-server-test-client/README.md:8`（quickstart）
2. `justfile:22`（`just app-server-test-client`）
3. `codex-rs/cli/src/main.rs:184`、`codex-rs/cli/src/main.rs:497`（CLI debug 调用入口）
4. `codex-rs/app-server-protocol/src/protocol/common.rs:214`、`:736`（方法与审批 request 映射）
5. `codex-rs/app-server-protocol/src/protocol/v2.rs:2558`、`:5022`（resume 与审批参数结构）
6. `codex-rs/app-server/src/codex_message_processor.rs:2217`（elicitation 计数服务端实现）
7. `codex-rs/app-server/src/transport.rs:1082`（实验字段裁剪测试）
8. `codex-rs/app-server/tests/suite/v2/thread_read.rs:344`（`thread/resume` 线协议字段断言）

## 依赖与外部交互

### Rust 依赖（crate 级）

- 协议与核心：`codex-app-server-protocol`、`codex-core`、`codex-protocol`（`codex-rs/app-server-test-client/Cargo.toml:13-17`）。
- 传输与编解码：`tungstenite`、`url`、`serde_json`、`uuid`（`Cargo.toml:19`, `:23-25`）。
- CLI 与可观测性：`clap`、`tracing`、`tracing-subscriber`、`codex-otel`（`Cargo.toml:12`, `:15`, `:21-22`）。

### 进程/系统命令交互

- 启动后台服务：`nohup` + `sh -c`（`lib.rs:533`）。
- 端口清理：`lsof`、`kill`（`lib.rs:562`, `:584`, `:611`）。
- 脚本执行：`sh` + 环境变量注入（`lib.rs:1220`）。

### 网络与文件系统

- websocket 连接默认 `ws://127.0.0.1:4222`（`lib.rs:445`）。
- runtime 日志目录：`/tmp/codex-app-server-test-client/`（`lib.rs:509`）。
- helper 脚本默认路径：`$CARGO_MANIFEST_DIR/scripts/live_elicitation_hold.sh`（`lib.rs:1192`）。

### 测试与文档上下文

- 该目录本身无独立测试文件（目录下仅 `lib.rs/main.rs`）。
- 相关行为由 app-server 测试侧覆盖部分协议契约：
  - `thread/resume` 线协议字段断言（`thread_read.rs:344`）；
  - 审批 request 实验字段按 capability 裁剪测试（`transport.rs:1082`, `:1149`）。
- app-server README 对初始化、thread/turn 生命周期和 notification opt-out 有明确契约，test-client 实现与其一致（`codex-rs/app-server/README.md:69`, `:70`, `:72`, `:80`）。

## 风险、边界与改进建议

### 风险与边界

- 文件过大：`lib.rs` 2197 行，命令定义、传输层、协议循环、harness、tracing 全耦合，长期维护成本高。
- 自动化回归不足：当前更多依赖手工命令联调；本 crate 自身无测试目录，行为变更易在重构时回归。
- websocket 路径本身属于实验/不支持通道，`live-elicitation-timeout-pause` 强依赖 ws，存在环境敏感性（`codex-rs/app-server/README.md:27`）。
- 外部命令依赖显式但脆弱：`lsof`/`kill` 在精简环境可能缺失。
- 高权限测试路径：harness 使用 `DangerFullAccess` + `AskForApproval::Never`，仅应在受控环境执行（`lib.rs:1241`）。

### 改进建议

1. 结构拆分：将 `lib.rs` 至少拆成 `cli.rs`、`transport.rs`、`rpc_client.rs`、`approval_handlers.rs`、`live_harness.rs`、`tracing.rs`。
2. 增加最小自动化：为 `parse_dynamic_tools_arg`、`resolve_endpoint`、`shell_quote`、审批决策策略添加单测；为 `wait_for_response`/`next_notification` 增加模拟消息序列测试。
3. 提升 ready 检测：`serve` 后增加可选 `readyz` 轮询，减少“启动后立刻连不上”的短暂抖动。
4. 强化能力门控：把实验 API 相关命令统一显式要求 `--experimental-api`，并在错误提示里回显建议命令。
5. 提升可观测输出分层：支持 `--quiet` / `--json` 输出模式，便于脚本化消费；当前 `> / <` pretty print 对机器处理不友好。
6. live harness 稳定性：将 helper marker（`[elicitation-hold] ...`）抽成常量并集中校验，避免文案改动引入误报。

