# DIR `codex-rs/app-server-test-client/scripts` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/app-server-test-client/scripts`
- 目录内容：当前仅 1 个脚本 `live_elicitation_hold.sh`
- 研究范围：脚本本体 + 直接调用链（test-client 命令）+ 协议层 + app-server 处理 + core 超时暂停机制 + 现有测试与运维入口

## 场景与职责

该目录承担的是“外部 helper 脚本层”的职责，不是通用脚本集合。

核心场景：`codex-app-server-test-client live-elicitation-timeout-pause` 需要验证“当命令执行期间存在外部 elicitation 时，unified exec 的 yield timeout 计时会暂停”。

`live_elicitation_hold.sh` 在这个场景中扮演最小可控实验体：

1. 对指定 thread 调用 `thread-increment-elicitation`，把 out-of-band pause counter +1。
2. 休眠 `ELICITATION_HOLD_SECONDS`（默认 15s），制造一个明确超过 10s 超时窗口的阻塞段。
3. 再调用 `thread-decrement-elicitation` 恢复计数。
4. 用 `trap` 兜底，确保异常退出时也会尝试回滚计数，避免线程长期处于 paused 状态。

对应代码：
- 脚本逻辑：`codex-rs/app-server-test-client/scripts/live_elicitation_hold.sh:1-46`
- 入口命令说明：`codex-rs/app-server-test-client/src/lib.rs:253-269`
- live harness 主流程：`codex-rs/app-server-test-client/src/lib.rs:1165-1318`

## 功能点目的

### 1) 验证外部暂停机制在真实链路可用

不是只测 unit 级布尔开关，而是通过“模型发起 exec_command -> shell 脚本 -> websocket RPC -> core timeout 机制”整链路证明行为生效。

### 2) 提供可重复、可观测的回归锚点

脚本输出固定 marker：
- `[elicitation-hold] increment ...`
- `[elicitation-hold] sleeping ...`
- `[elicitation-hold] decrement ...`
- `[elicitation-hold] done`

test-client 在流式事件里聚合输出并检查 `done` marker，以此确认 helper 脚本完整执行（`src/lib.rs:1253-1281`, `1502-1509`, `1700-1737`）。

### 3) 把“协议实验能力”封装成简单 CLI 能力

脚本自身不懂 JSON-RPC，仅通过 `APP_SERVER_TEST_CLIENT_BIN --url ... thread-increment/decrement-elicitation` 调用，降低脚本复杂度，同时复用现有握手与请求封装（`src/lib.rs:1137-1163`, `1623-1647`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. 脚本实现细节

文件：`codex-rs/app-server-test-client/scripts/live_elicitation_hold.sh`

关键点：
1. `set -eu`：未定义变量和命令失败立即退出（`line 2`）。
2. `require_env APP_SERVER_URL / APP_SERVER_TEST_CLIENT_BIN`（`line 12-13`）。
3. thread id 来源优先级：`CODEX_THREAD_ID` -> `THREAD_ID`（`line 15`）；缺失直接失败（`line 16-18`）。
4. `ELICITATION_HOLD_SECONDS` 默认 15（`line 21`）。
5. `incremented` 状态位 + `trap cleanup EXIT INT TERM HUP`，防止只加不减（`line 22-31`）。
6. 正常路径：increment -> sleep -> decrement -> done（`line 33-46`）。

补充：脚本无需可执行位（当前是 `-rw-rw-r--`），因为调用方固定 `sh <script_path>` 执行。

### B. 调用方：live harness 如何使用脚本

`live_elicitation_timeout_pause(...)` 关键流程（`src/lib.rs:1165-1318`）：

1. 前置约束：
- 禁止 Windows（要求 POSIX shell，`1174-1176`）。
- `--hold-seconds > 10`（`1177-1179`），保证显著超过 unified exec 默认短 yield 窗口。

2. endpoint 决策：
- `--codex-bin` 启临时后台 app-server；
- 或使用 `--url`；
- 都不传默认 `ws://127.0.0.1:4222`（`1181-1192`）。

3. script 路径：
- 默认 `CARGO_MANIFEST_DIR/scripts/live_elicitation_hold.sh`（`1194-1198`）；
- 文件不存在则失败（`1199-1201`）。

4. 生成给模型的“严格命令提示词”：
- 通过 `format!` 组装环境变量 + `sh script` 命令（`1221-1227`）。
- prompt 明确要求仅执行一次 `exec_command`、命令不能改写（`1228-1230`）。

5. 发起 turn：
- `approval_policy=Never`
- `sandbox_policy=DangerFullAccess`
- `effort=High`
- `cwd=workspace`
  （`1233-1243`）

6. 流式消费并验收：
- 校验 turn completed、command execution completed、helper done marker、执行耗时足够长、helper 完成前无异常 item（`1250-1295`）。

7. 二次兜底清理：
- 无论 validation 成败，额外再调一次 `thread/decrement_elicitation`（`1300-1309`）。

### C. 协议与数据结构

#### 1) app-server-protocol 方法注册

- `thread/increment_elicitation` 与 `thread/decrement_elicitation` 在 common method 表中声明为 `#[experimental(...)]`（`app-server-protocol/src/protocol/common.rs:237-253`）。

#### 2) v2 参数与返回

- `ThreadIncrementElicitationParams { thread_id: String }`
- `ThreadIncrementElicitationResponse { count: u64, paused: bool }`
- `ThreadDecrementElicitationParams { thread_id: String }`
- `ThreadDecrementElicitationResponse { count: u64, paused: bool }`

定义位置：`app-server-protocol/src/protocol/v2.rs:2742-2780`。

#### 3) test-client 请求封装

`CodexClient` 封装了 typed 请求：
- `thread_increment_elicitation(...)`（`src/lib.rs:1623-1634`）
- `thread_decrement_elicitation(...)`（`src/lib.rs:1636-1647`）

统一走 `send_request -> write_request -> wait_for_response`：
- 写请求时补充 trace context（`1802-1811`）
- 响应/通知/服务端 request 分流处理（`1813-1839`）

### D. 被调用方：app-server 与 core 的暂停机制

#### 1) app-server 分发与处理

- `ClientRequest::ThreadIncrementElicitation` / `ThreadDecrementElicitation` 分发（`app-server/src/codex_message_processor.rs:653-659`）。
- handler 内加载 thread，更新计数，返回 `{count, paused}`（`2217-2288`）。
- decrement 在 count=0 时返回 invalid request（来自 core）。

#### 2) core 计数与 pause state

`CodexThread` 内维护 `out_of_band_elicitation_count: Mutex<u64>`（`core/src/codex_thread.rs:46-50`）：
- increment：0->1 时 `set_out_of_band_elicitation_pause_state(true)`（`166-179`）。
- decrement：减到 0 时 `set_out_of_band_elicitation_pause_state(false)`；若已为 0 则报错（`182-199`）。

pause state 通过 watch channel 暴露：
- `subscribe_out_of_band_elicitation_pause_state`（`core/src/codex.rs:1257-1259`）。

#### 3) unified exec 对 pause 的消费

`collect_output_until_deadline` 接收 pause receiver（`process_manager.rs:228-239, 645-653`），在 paused 期间调用 `extend_deadlines_while_paused`：
- 持续等待 pause 解除；
- 将暂停时长加回 `deadline/post_exit_deadline`（`734-757`）。

这就是脚本 sleep 15s 仍可通过的根因。

### E. 命令与运维入口

- 快速启动方式：`just app-server-test-client ...`（`justfile:22-24`）。
- test-client README 记录了启动 app-server 与线程重连调试流程（`app-server-test-client/README.md:8-58`）。
- live harness 可直接命令化：
  - `cargo run -p codex-app-server-test-client -- live-elicitation-timeout-pause ...`
  - 或 `just app-server-test-client live-elicitation-timeout-pause ...`

## 关键代码路径与文件引用

按“脚本 -> 客户端 -> 协议 -> 服务端 -> core”链路：

1. `codex-rs/app-server-test-client/scripts/live_elicitation_hold.sh:1-46`
2. `codex-rs/app-server-test-client/src/lib.rs:241-269`（CLI 子命令）
3. `codex-rs/app-server-test-client/src/lib.rs:395-420`（命令分发）
4. `codex-rs/app-server-test-client/src/lib.rs:1137-1163`（直接 increment/decrement 命令）
5. `codex-rs/app-server-test-client/src/lib.rs:1165-1318`（live harness 主流程）
6. `codex-rs/app-server-test-client/src/lib.rs:1367-1381,1677-1770`（流式状态观测字段与逻辑）
7. `codex-rs/app-server-protocol/src/protocol/common.rs:237-253`（RPC 方法表）
8. `codex-rs/app-server-protocol/src/protocol/v2.rs:2742-2780`（参数/返回结构）
9. `codex-rs/app-server/src/codex_message_processor.rs:653-659,2217-2288`（服务端 handler）
10. `codex-rs/core/src/codex_thread.rs:46-50,166-199`（计数与 pause 状态切换）
11. `codex-rs/core/src/unified_exec/process_manager.rs:228-239,645-757`（timeout 暂停实现）
12. `codex-rs/core/src/unified_exec/mod_tests.rs:236-266`（pause 阻断 yield timeout 的测试）

## 依赖与外部交互

### 1) 脚本运行时依赖

- POSIX shell：`/bin/sh`。
- `APP_SERVER_TEST_CLIENT_BIN`：必须是可执行 test-client 二进制。
- `APP_SERVER_URL`：websocket 地址（例如 `ws://127.0.0.1:4222`）。
- `CODEX_THREAD_ID`（或 `THREAD_ID`）目标线程 ID。
- 可选 `ELICITATION_HOLD_SECONDS`。

### 2) 网络与协议

- 脚本本身不直接发 websocket；通过 test-client 调用 `thread/increment_elicitation` / `thread/decrement_elicitation` JSON-RPC。
- app-server 端按 thread_id 定位会话并修改 out-of-band 计数。

### 3) 配置与追踪

- test-client 支持 `--config key=value` 覆盖并初始化 tracing（`src/lib.rs:2088-2164` 附近逻辑）。
- 请求会注入 W3C trace context（`src/lib.rs:1802-1807`），用于 Datadog 追踪串联。

### 4) 构建与分发约束

- `BUILD.bazel` 当前仅声明 crate（`app-server-test-client/BUILD.bazel:1-5`），脚本通过运行时文件路径引用，不通过 Bazel runfiles 显式声明。
- harness 默认路径依赖 `CARGO_MANIFEST_DIR`（`src/lib.rs:1194-1198`），对非 Cargo 运行环境可移植性有限。

## 风险、边界与改进建议

### 风险与边界

1. 平台边界：仅 POSIX；Windows 直接拒绝（`1174-1176`）。
2. 路径边界：默认脚本路径依赖源码目录结构；打包/安装后若无同路径文件将失败。
3. 计数一致性风险：
- 脚本有 trap 清理；
- harness 也做额外 decrement；
- 但仍可能出现“外部并发修改计数导致清理次数不匹配”的诊断复杂度。
4. 可观测性边界：当前成功判定依赖日志 marker 文本匹配，属于“弱结构化信号”。
5. 安全边界：harness 固定 `DangerFullAccess + AskForApproval::Never`，仅适用于受控验证环境，不应作为常规执行模板。

### 改进建议

1. 为 `live-elicitation-timeout-pause` 增加专门 README 段落，给出标准命令、失败症状和排查步骤。
2. 在 app-server 或 test-client 增加结构化状态查询（例如 `thread/read` 扩展 pause counter），减少对输出 marker 的依赖。
3. 为该脚本链路补充端到端自动化测试（目前 core 有 pause 机制测试，但脚本+RPC+harness 端到端回归点还不显式）。
4. 若要支持 Bazel 运行该 harness，考虑把脚本纳入 `compile_data/test data` 并用 runfiles 解析路径。
5. 将脚本中的 `eval` 变量读取替换为更严格模式（可读性与安全性更好），例如 `case` / 明确变量名分支。

