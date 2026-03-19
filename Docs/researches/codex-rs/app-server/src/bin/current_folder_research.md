# DIR `codex-rs/app-server/src/bin` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/app-server/src/bin`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 关联 crate：`codex-app-server`

## 场景与职责

`codex-rs/app-server/src/bin` 不是 app-server 的主服务入口目录，而是“测试辅助二进制”目录，核心职责是为通知链路测试提供一个可执行、可落盘的 payload 捕获器。

该目录当前包含两个二进制源码：

1. `notify_capture.rs`
- 被显式注册为 `codex-app-server-test-notify-capture`，用于 app-server v2 初始化/turn 测试中捕获 `notify` 最终 JSON 参数。
- 位置：`codex-rs/app-server/Cargo.toml:11-13`、`codex-rs/app-server/src/bin/notify_capture.rs:1-44`。

2. `test_notify_capture.rs`
- 也是可编译 bin（Cargo 自动发现 `src/bin/*.rs`），目标名为 `test_notify_capture`。
- 当前仓库内未检索到调用方（测试与脚本均未引用），但会出现在 `cargo metadata` 的目标列表中。
- 位置：`codex-rs/app-server/src/bin/test_notify_capture.rs:1-23`。

因此，此目录承担的是“测试验证支撑职责”，不是“生产运行职责”。真正的 app-server 入口仍为：
- `codex-rs/app-server/src/main.rs:1-44`
- `codex-rs/app-server/Cargo.toml:7-9`

## 功能点目的

1. 验证 `initialize.clientInfo.name` 是否贯通到 turn 完成通知 payload
- v2 测试 `turn_start_notify_payload_includes_initialize_client_name` 会：
  - 把 `notify = [<capture_bin>, <notify_file>]` 写入临时 `config.toml`；
  - 发起 `initialize(clientInfo.name = "xcode")`；
  - 触发一次 `turn/start`；
  - 最终读取 `notify_file`，断言 JSON 中 `client == "xcode"`。
- 位置：`codex-rs/app-server/tests/suite/v2/initialize.rs:200-272`。

2. 提供对 legacy notify hook 的黑盒落盘观察点
- core 的 hooks 机制会在 `AfterAgent` 事件触发时执行 `notify` 命令，并把 JSON 作为最后一个 argv 参数追加。
- 捕获器二进制只做“参数接收 + 原子写文件”，不参与协议转换。
- 位置：
  - `codex-rs/core/src/config/mod.rs:308-328`
  - `codex-rs/hooks/src/registry.rs:40-46`
  - `codex-rs/hooks/src/legacy_notify.rs:46-69`

3. 隔离测试环境中的副作用
- 捕获器把 payload 写到测试临时目录 (`TempDir`) 下文件，避免依赖桌面通知程序（如 `notify-send`）或系统级通知服务。
- 位置：`codex-rs/app-server/tests/suite/v2/initialize.rs:203-221`。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 端到端关键流程（调用链）

`initialize + turn/start` 到 `notify_capture` 落盘的链路如下：

1. 测试写入 config
- `notify = ["<bin>", "<notify_file>"]`
- `codex-rs/app-server/tests/suite/v2/initialize.rs:212-221, 284-315`

2. app-server 记录客户端身份
- `initialize` 时将 `clientInfo.name` 写入 `session.app_server_client_name`
- `codex-rs/app-server/src/message_processor.rs:546-553`

3. turn/start 前把 client name 注入 thread session 设置
- `CodexMessageProcessor::turn_start` -> `set_app_server_client_name`
- `codex-rs/app-server/src/codex_message_processor.rs:5928-5947, 6037-6048`

4. core 在 AfterAgent 钩子生成 HookPayload
- `client: turn_context.app_server_client_name.clone()`
- `codex-rs/core/src/codex.rs:5802-5817`

5. hooks 把 notify 命令构建为 hook 并追加 JSON 参数后 `spawn`
- `HooksConfig.legacy_notify_argv` -> `notify_hook`
- `codex-rs/hooks/src/registry.rs:18-46`
- `codex-rs/hooks/src/legacy_notify.rs:28-39, 46-69`

6. 捕获器程序接收 argv 并原子写文件
- `notify_capture.rs`：写 `<output>.tmp` 后 `rename` 到目标文件
- `codex-rs/app-server/src/bin/notify_capture.rs:28-41`

### 2) 关键数据结构与线协议

1. 用户配置侧
- `Config.notify: Option<Vec<String>>`，表示外部通知命令 argv（不含 JSON 参数本体）
- `codex-rs/core/src/config/mod.rs:308-328, 1246-1248, 2676`

2. hook payload（内部）
- `HookPayload` + `HookEvent::AfterAgent`
- 包含：`thread_id`、`turn_id`、`input_messages`、`last_assistant_message`、`client`
- `codex-rs/hooks/src/types.rs:65-85, 150-154`

3. legacy notify JSON（外部命令末参数）
- `legacy_notify_json` 输出 `type = "agent-turn-complete"`，字段为 kebab-case：
  - `thread-id`
  - `turn-id`
  - `cwd`
  - `client`（可选）
  - `input-messages`
  - `last-assistant-message`
- `codex-rs/hooks/src/legacy_notify.rs:13-25, 28-39`

### 3) 两个 capture 二进制的实现差异

1. `notify_capture.rs`（主用）
- 参数校验：严格要求仅 `output_path + payload` 两个用户参数（多参数报错）
- payload 编码：`to_string_lossy()`，可容忍非 UTF-8 argv
- 落盘策略：`File::create` + `write_all` + `sync_all` + `rename`
- 临时文件命名：`<output_path>.tmp`
- 位置：`codex-rs/app-server/src/bin/notify_capture.rs:12-41`

2. `test_notify_capture.rs`（未被引用）
- 参数校验：仅检查前两个参数存在，不拒绝多余参数
- payload 编码：要求严格 UTF-8（`into_string()`）
- 落盘策略：`std::fs::write` + `rename`，无显式 `sync_all`
- 临时文件命名：`with_extension("json.tmp")`
- 位置：`codex-rs/app-server/src/bin/test_notify_capture.rs:6-20`

### 4) 测试命令与运行方式

1. 测试通过 `cargo_bin("codex-app-server")` 启动 app-server 子进程
- `codex-rs/app-server/tests/common/mcp_process.rs:111-113`

2. 目标用例通过 `cargo_bin("codex-app-server-test-notify-capture")` 解析捕获器路径
- `codex-rs/app-server/tests/suite/v2/initialize.rs:205-208`

3. `tests/all.rs` 聚合 v2 初始化测试模块
- `codex-rs/app-server/tests/all.rs:1-16`
- `codex-rs/app-server/tests/suite/v2/mod.rs:1-17`

补充：`cargo metadata` 显示 `test_notify_capture` 也是 bin target（自动发现），说明其并非纯“无效文件”，而是构建目标的一部分。

## 关键代码路径与文件引用

### A. 目标目录（被研究对象）

1. `codex-rs/app-server/src/bin/notify_capture.rs:1-44`
- 通知 payload 捕获主实现（被测试使用）。

2. `codex-rs/app-server/src/bin/test_notify_capture.rs:1-23`
- 备用/历史风格捕获实现（当前未见调用方）。

### B. 直接调用方与装配点

1. `codex-rs/app-server/Cargo.toml:11-13`
- 显式声明 `codex-app-server-test-notify-capture` -> `notify_capture.rs`。

2. `codex-rs/app-server/tests/suite/v2/initialize.rs:200-221, 267-270`
- 唯一直接引用该 bin 名称并消费输出文件断言 `payload["client"]`。

3. `codex-rs/app-server/tests/common/mcp_process.rs:97-113`
- app-server 测试进程启动器；构成该链路的上游运行容器。

### C. 被调用下游（通知来源）

1. `codex-rs/app-server/src/message_processor.rs:546-553, 763-769`
- 记录并传递 `app_server_client_name`。

2. `codex-rs/app-server/src/codex_message_processor.rs:732-737, 5928-5947`
- `turn/start` 注入 client name 到线程上下文。

3. `codex-rs/core/src/codex_thread.rs:93-100`
- thread 级别设置入口。

4. `codex-rs/core/src/codex.rs:708-717, 1132-1134, 5802-5817`
- session settings 存储与 hook payload 组装。

5. `codex-rs/hooks/src/registry.rs:40-46`
- `notify` 命令转为 `after_agent` hook。

6. `codex-rs/hooks/src/legacy_notify.rs:28-39, 46-69`
- JSON 序列化 + 外部命令 spawn。

### D. 配置、测试、文档、脚本上下文

1. 配置定义
- `codex-rs/core/src/config/mod.rs:308-328, 1246-1248, 2676`

2. 集成测试入口
- `codex-rs/app-server/tests/all.rs:1-16`
- `codex-rs/app-server/tests/suite/v2/mod.rs:1-17`

3. 用户文档（clientInfo 契约）
- `codex-rs/app-server/README.md:78-86, 88-122`

4. 相关脚本现状
- 当前仓库未检索到直接调用 `codex-app-server-test-notify-capture` 的 shell 脚本；该能力主要由 Rust 集成测试通过 `cargo_bin` 驱动。

## 依赖与外部交互

### 1) 目录内二进制自身依赖

1. `notify_capture.rs`
- 依赖：`std::{env, fs, io, path}` + `anyhow`
- 作用：参数解析、文件写入、错误上下文封装

2. `test_notify_capture.rs`
- 依赖：`std::{env, fs, path}` + `anyhow`
- 作用：精简版本参数解析与落盘

### 2) 外部进程/文件系统交互

1. 进程调用方式
- 由 hooks 层 `tokio::process::Command::spawn()` 异步触发，stdin/stdout/stderr 均置空（fire-and-forget）。
- `codex-rs/hooks/src/legacy_notify.rs:61-69`

2. 文件系统交互
- 捕获器写临时文件后 `rename` 覆盖目标文件，避免读到半写入内容。
- `codex-rs/app-server/src/bin/notify_capture.rs:28-41`

3. 与环境变量关系
- 该目录内二进制本身不直接消费环境变量；其运行上下文由 app-server/core/hooks 与测试框架提供。

### 3) 与协议/配置的耦合

1. 与 app-server v2 初始化协议耦合
- 依赖 `initialize.clientInfo.name` 正确进入 session。
- `codex-rs/app-server/src/message_processor.rs:546-553`

2. 与 core notify 配置耦合
- `notify` argv 的最后一个参数必须是 legacy JSON payload（由 hooks 自动追加）。
- `codex-rs/core/src/config/mod.rs:308-328`
- `codex-rs/hooks/src/legacy_notify.rs:57-58`

## 风险、边界与改进建议

### 风险

1. 双实现漂移风险（中）
- `notify_capture.rs` 与 `test_notify_capture.rs` 语义不一致（UTF-8、参数校验、落盘 flush、tmp 命名），后续维护容易误用或误判。

2. 隐式构建目标风险（中）
- `test_notify_capture.rs` 虽无调用方，但会被 Cargo 自动识别为 bin target；若其代码退化，可能影响构建/CI 时长或引入无意失败。

3. 测试链路可观测性边界（低）
- hooks 为 fire-and-forget，若通知进程启动失败仅体现为 hook 失败继续（`FailedContinue`），需要依赖测试层轮询文件存在来观测。

### 边界

1. 非生产服务路径
- 该目录代码不参与 app-server 主流程路由，不影响 RPC 主逻辑性能路径。

2. 职责单一
- 仅负责“接收 payload 参数并落盘”，不解析 JSON 业务语义。

3. 平台语义边界
- 路径与 rename 行为依赖宿主文件系统语义；测试通过同目录临时文件降低跨设备 rename 风险。

### 改进建议

1. 收敛重复实现
- 建议保留一个 capture bin，并删除/合并 `test_notify_capture.rs`；若需保留，至少补充注释说明用途差异与使用方。

2. 显式控制二进制发现
- 可评估在 `Cargo.toml` 设置 `autobins = false`，仅保留显式 `[[bin]]`，避免“未引用 bin”长期漂移。

3. 增加最小回归测试
- 为 capture bin 增加独立单测/集成测（参数数量、非法 UTF-8、原子写行为），把当前“仅被上层间接覆盖”的风险前移。

4. 文档化测试契约
- 在 `app-server/tests` 或 `README` 增加一段“notify capture test harness”说明，写明该 bin 是测试专用，不应被外部集成依赖。
