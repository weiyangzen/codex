# DIR `codex-rs/app-server/tests/suite` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/app-server/tests/suite`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 关联 crate：`codex-app-server`（被测）、`app_test_support`（测试驱动）
- 规模概览：`53` 个 Rust/脚本文件、约 `25,584` 行；测试函数 `272`（根目录 `18`，`v2/` `254`）

## 场景与职责

`codex-rs/app-server/tests/suite` 是 `codex-app-server` 的主集成测试域，定位不是“函数级单元测试”，而是“进程级协议验证”。

它承担 4 类职责：

1. 对外 JSON-RPC 契约回归
- 从客户端视角覆盖 `initialize`、`thread/*`、`turn/*`、`command/exec*`、`fs/*`、`plugin/*`、`app/list`、`skills/list`、`review/start`、`thread/realtime/*` 等接口。
- 入口由 `codex-rs/app-server/tests/all.rs` 聚合到 `suite/mod.rs` 与 `suite/v2/mod.rs`。

2. 真实子进程行为验证
- 通过 `app_test_support::McpProcess` 启动真实 `codex-app-server` 二进制，走 stdin/stdout JSONL（或 ws）而不是直接调内部函数。
- 验证响应/通知/反向请求（server request）三类消息的时序和 payload。

3. 高风险行为的集成保障
- 覆盖并发与竞态场景：running turn interrupt、unsubscribe/close、resume in-flight、websocket 多连接 request-id 隔离、SIGINT/SIGTERM 优雅退出。
- 覆盖工具审批闭环：`commandExecutionRequestApproval`、`tool/requestUserInput`、`requestPermissions`、`mcpServerElicitationRequest`。

4. 生态与外部边界验证
- 覆盖插件市场、connectors(apps)、实时会话、auth/token refresh、analytics 上报、Git 元数据、文件系统绝对路径约束、DotSlash shell 工件拉取。

## 功能点目的

### 1) 根目录模块（非 v2 子目录）

1. `auth.rs`（5 tests）
- 验证 `getAuthStatus` 与 `account/login/start(apiKey)` 组合行为。
- 覆盖 provider 是否要求 OpenAI auth、`include_token` omitted 行为、forced login method 拒绝逻辑。

2. `conversation_summary.rs`（2 tests）
- 验证 `getConversationSummary` 可通过 `thread_id` 或相对 rollout path 解析并读取历史。

3. `fuzzy_file_search.rs`（11 tests）
- 验证一次性搜索和会话式搜索（start/update/stop）全流程。
- 重点覆盖：排序与分数、取消 token、并发会话隔离、session completed 后 update 语义。

### 2) v2 核心矩阵（`suite/v2`）

1. 会话与线程生命周期
- `initialize.rs`（clientInfo name、invalid header value、opt-out notification）
- `thread_start.rs`、`thread_resume.rs`、`thread_fork.rs`、`thread_read.rs`、`thread_list.rs`、`thread_loaded_list.rs`
- `thread_archive.rs`、`thread_unarchive.rs`、`thread_unsubscribe.rs`、`thread_rollback.rs`
- `thread_name_websocket.rs`、`thread_metadata_update.rs`、`thread_status.rs`

2. 回合与审批
- `turn_start.rs`（20 tests，最大文件，覆盖输入限制、collaboration mode/personality override、approval 分支、spawn agent item 元数据、processId 通知）
- `turn_steer.rs`、`turn_interrupt.rs`
- `request_user_input.rs`、`request_permissions.rs`
- `plan_item.rs`、`review.rs`

3. 执行与系统 API
- `command_exec.rs`（streaming/buffered、env merge/unset、timeout/output cap 冲突、TTY resize、connection-scoped processId）
- `thread_shell_command.rs`
- `fs.rs`（绝对路径强约束、base64、copy 目录/软链/特殊文件边界）
- `config_rpc.rs`（effective+layers+origins、value write/batch write、version conflict）

4. 生态能力（Skills/Apps/Plugins）
- `skills_list.rs`（per-cwd extra roots、forceReload 缓存语义、skills changed 通知）
- `app_list.rs`（connector 能力、thread feature 覆盖、分页、force refetch patch 更新）
- `plugin_list.rs`、`plugin_read.rs`、`plugin_install.rs`、`plugin_uninstall.rs`

5. 实验与传输层
- `experimental_api.rs`、`experimental_feature_list.rs`、`collaboration_mode_list.rs`
- `connection_handling_websocket.rs`、`connection_handling_websocket_unix.rs`
- `realtime_conversation.rs`（v2 realtime 通知桥接）
- `windows_sandbox_setup.rs`

### 3) 平台与脚本专用

1. `turn_start_zsh_fork.rs`
- 专门验证 zsh fork 执行链与审批分支。
- 显式说明首跑依赖 DotSlash 与网络。

2. `suite/bash`、`suite/zsh`
- DotSlash 描述文件，拉取 `codex-shell-tool-mcp` 发布工件里的 shell fork 可执行文件。

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. 调用方 -> 被调用方主链路

1. 调用方（测试）
- Cargo 集成测试入口：`codex-rs/app-server/tests/all.rs`。
- 模块注册：`codex-rs/app-server/tests/suite/mod.rs`、`.../suite/v2/mod.rs`。

2. 传输驱动层（`McpProcess`）
- `codex-rs/app-server/tests/common/mcp_process.rs` 提供 typed RPC 封装：`send_thread_start_request`、`send_turn_start_request`、`send_command_exec_request`、`send_config_read_request` 等。
- 握手流程：`initialize` request -> `initialized` notification。
- 读取策略：`read_stream_until_*` + `pending_messages` 缓冲队列，解决通知与响应乱序/并发。

3. 被调用方（app-server）
- `app-server/src/message_processor.rs` 负责 initialize gate、experimental capability gate、FS/Config/ExternalAgent 分流。
- 其余请求委托到 `app-server/src/codex_message_processor.rs`，再调用 `codex-core` 的 `ThreadManager/AuthManager/PluginsManager` 等。

### B. 协议与数据结构

1. 协议方法定义源
- `codex-rs/app-server-protocol/src/protocol/common.rs` 使用宏统一定义 `ClientRequest`、`ServerRequestPayload`、`ServerNotification`。
- `ThreadStart => "thread/start"`、`TurnStart => "turn/start"`、`OneOffCommandExec => "command/exec"`、`ConfigRead => "config/read"`、`FsReadFile => "fs/readFile"` 等在同一处声明。

2. v2 参数与响应类型
- `codex-rs/app-server-protocol/src/protocol/v2.rs` 定义 `ThreadStartParams`、`TurnStartParams`、`CommandExecParams`、`Plugin*`、`App*`、`Realtime*` 等结构与 serde/TS 导出规则。

3. server request 闭环模型
- 模型先触发 tool call，app-server 对客户端发 `ServerRequest`（例如权限审批/用户输入/MCP elicitation）。
- 客户端通过 JSON-RPC response 回填结果。
- app-server 发 `serverRequest/resolved` 通知，再推进 turn 完成（多个测试都断言 resolved 先于 `turn/completed`）。

### C. fixture/mocking 机制

1. 配置与状态
- `tests/common/config.rs`：按 feature/provider/requires_openai_auth 写 `config.toml`。
- `tests/common/rollout.rs`：生成最小 rollout JSONL，支持 `SessionMeta/git_info/text_elements`。
- `tests/common/models_cache.rs`：写 `models_cache.json`，避免模型目录请求依赖外网。
- `tests/common/auth_fixtures.rs`：构造 ChatGPT token claim 并写入 `auth.json`。

2. 上游模拟
- `tests/common/mock_model_server.rs`：按序返回 SSE 或重复 assistant 响应。
- `tests/common/responses.rs`：快速构造 `shell_command`、`exec_command`、`apply_patch`、`request_user_input`、`request_permissions` SSE。
- 多个 `v2` 文件直接用 `wiremock::MockServer` 或本地 axum/rmcp server 模拟 connectors/plugin remote sync/realtime backend。

### D. 关键命令与执行模式

1. 进程模式
- `McpProcess` 使用 `codex_utils_cargo_bin::cargo_bin("codex-app-server")` 启动真实服务。
- websocket 专项用例直接 `--listen ws://127.0.0.1:0` 起子进程并从 stderr 解析绑定地址。

2. 常见测试内命令
- Git 场景：`git init/checkout/rev-parse`（thread resume/list metadata 相关）。
- shell/PTY 场景：`sh -lc ...`、`sleep`、zsh fork。
- Unix 信号场景：`kill -INT/-TERM <pid>` 验证 graceful restart drain 行为。

### E. 配置策略（测试内）

1. 大部分测试强制最小可控配置：
- `model = "mock-model"`
- `approval_policy = "never"` 或 `"untrusted"`
- `sandbox_mode = "read-only"|"danger-full-access"`
- provider 指向本地 wiremock `.../v1`。

2. 功能开关按场景精确开启
- 例如 `request_permissions_tool`、`plugins`、`connectors`、`sqlite`、`personality`、`shell_zsh_fork`。
- `experimentalApi` 通常在 initialize capabilities 中显式声明。

## 关键代码路径与文件引用

### 入口与组织
- `codex-rs/app-server/tests/all.rs`
- `codex-rs/app-server/tests/suite/mod.rs`
- `codex-rs/app-server/tests/suite/v2/mod.rs`

### 测试驱动与基建
- `codex-rs/app-server/tests/common/mcp_process.rs`
- `codex-rs/app-server/tests/common/config.rs`
- `codex-rs/app-server/tests/common/mock_model_server.rs`
- `codex-rs/app-server/tests/common/responses.rs`
- `codex-rs/app-server/tests/common/rollout.rs`
- `codex-rs/app-server/tests/common/auth_fixtures.rs`
- `codex-rs/app-server/tests/common/models_cache.rs`

### 高复杂度场景文件
- `codex-rs/app-server/tests/suite/v2/turn_start.rs`（~2585 行）
- `codex-rs/app-server/tests/suite/v2/thread_resume.rs`（~1950 行）
- `codex-rs/app-server/tests/suite/v2/thread_list.rs`（~1429 行）
- `codex-rs/app-server/tests/suite/v2/app_list.rs`（~1428 行）
- `codex-rs/app-server/tests/suite/v2/account.rs`（~1277 行）
- `codex-rs/app-server/tests/suite/v2/plugin_list.rs`（~956 行）
- `codex-rs/app-server/tests/suite/v2/command_exec.rs`（~886 行）

### 传输与协议上下文
- `codex-rs/app-server/src/lib.rs`
- `codex-rs/app-server/src/message_processor.rs`
- `codex-rs/app-server/src/codex_message_processor.rs`
- `codex-rs/app-server/src/transport.rs`
- `codex-rs/app-server-protocol/src/protocol/common.rs`
- `codex-rs/app-server-protocol/src/protocol/v2.rs`
- `codex-rs/app-server/README.md`

### 脚本与平台工件
- `codex-rs/app-server/tests/suite/bash`
- `codex-rs/app-server/tests/suite/zsh`
- `codex-rs/app-server/tests/suite/v2/turn_start_zsh_fork.rs`

## 依赖与外部交互

### 1) 依赖

1. 内部 crate
- `app_test_support`（测试驱动库）
- `codex-app-server-protocol`
- `codex-core` / `codex-protocol`
- `core_test_support`

2. 第三方关键依赖
- `wiremock`（HTTP mock）
- `tokio` / `tokio-tungstenite`（并发与 ws）
- `reqwest`（health endpoint 校验）
- `rmcp` + `axum`（apps/mcp server 模拟）
- `pretty_assertions`（结构化 diff）

### 2) 外部交互面

1. 子进程与系统
- 启动 `codex-app-server` 二进制、写入 stdin JSON、读取 stdout/stderr。
- 部分场景触发 `git`、shell、kill signal。

2. 文件系统
- 大量使用 `TempDir`，动态创建 `CODEX_HOME`、`config.toml`、`auth.json`、`models_cache.json`、rollout 文件树。
- `fs/*` 用例明确验证“仅接受绝对路径”。

3. 网络
- 常规依赖本地 mock（wiremock/本地 ws server）。
- 部分用例用 `skip_if_no_network!`，在无网环境自动跳过（如 compaction/output_schema/turn_start 多场景、realtime、zsh fork）。
- `bash/zsh` DotSlash 首次需要从 GitHub Release 拉工件。

4. 文档/协议同步
- 测试行为与 `app-server/README.md` 的 API 语义强相关（initialize gate、thread/turn 事件、command/exec、realtime、websocket health/origin policy）。

## 风险、边界与改进建议

1. 风险：超大测试文件导致维护成本高
- `turn_start.rs`、`thread_resume.rs`、`thread_list.rs`、`app_list.rs` 单文件覆盖过多语义。
- 建议：按子能力拆分（输入大小校验、审批闭环、人格/协作模式、spawn-agent 元数据、stream order）。

2. 风险：`McpProcess` 单体职责过重
- 同时管理进程、协议封装、读取匹配、消息缓冲、drop 清理。
- 建议：拆分为 `ProcessHarness + RpcClient + StreamAsserter`，降低新增 API 时的认知负担。

3. 风险：异步时序容易 flaky
- 多处 timeout+轮询模式（尤其 notifications 竞争 response）。
- 建议：引入统一事件等待 DSL（带失败时完整 buffered 消息转储），减少重复样板与误判。

4. 边界：平台/网络条件影响覆盖稳定性
- `#[cfg(unix)]`、`#[cfg(not(windows))]`、`skip_if_no_network!` 使部分路径在不同环境不执行。
- 建议：在 CI 中显式维护多维矩阵（linux/mac + online/offline + ws/stdio）并输出覆盖差异报告。

5. 风险：真实外部协议变化引发脆弱回归
- plugins/connectors/realtime 用例依赖较复杂 mock 协议与 header 语义。
- 建议：抽象可复用 fixture builders（当前已部分存在），并增加“协议契约快照”检查，避免复制粘贴型 drift。

6. 边界：脚本工件可用性
- `suite/bash`、`suite/zsh` 依赖 dotslash + release 工件可访问。
- 建议：增加本地缓存命中提示和失败降级说明，避免开发者误判为功能回归。

7. 建议：增加“RPC -> 测试文件”自动映射产物
- 可由 `common.rs` 方法定义与 `suite/**/*.rs` 请求发送函数自动生成矩阵。
- 价值：快速发现新接口缺少回归、减少人工盘点成本。
