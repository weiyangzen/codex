# DIR `codex-rs/app-server/tests` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/app-server/tests`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 关联 crate：`codex-app-server`（被测）、`app_test_support`（测试支持库）
- 文件规模概览：`67` 个文件（其中 `suite/v2` 为 `49` 个），`suite` 下测试用例约 `272` 个（`v2` 约 `254`）

## 场景与职责

`codex-rs/app-server/tests` 是 `codex-app-server` 的集成测试主目录，职责不是做纯单元校验，而是以“真实进程 + JSON-RPC 流 + mock 上游服务”的方式验证 app-server 对外契约。

该目录承担四个核心角色：

1. 端到端协议验证
- 通过 `tests/common/mcp_process.rs` 启动真实 `codex-app-server` 子进程，发送 JSON-RPC 请求、读取响应/通知/反向请求。
- 覆盖 `initialize` 门禁、thread/turn 生命周期、工具调用审批、流式事件与错误语义。

2. v2 API 回归矩阵
- `tests/suite/v2/mod.rs` 汇总几乎全部 v2 接口场景（thread/turn/fs/config/plugins/apps/model/realtime/websocket 等）。
- 高密度文件如 `turn_start.rs`、`thread_resume.rs`、`thread_list.rs` 负责关键行为回归。

3. 测试基建封装
- `tests/common/*` 提供 mock responses SSE 生成器、配置/rollout/auth fixture、模型缓存 fixture、MCP 子进程驱动器。
- 减少每个测试文件重复搭建 wiremock、临时目录、协议序列化逻辑。

4. 跨边界行为验证
- 验证 app-server 与下游/外部边界：文件系统、shell/PTY、Git 元数据、plugins/apps 远程目录、websocket 健康探针、信号优雅退出。

## 功能点目的

按功能域梳理测试意图如下：

1. 连接与会话治理
- `initialize`、重复初始化、防未初始化请求、per-connection opt-out 通知过滤。
- websocket 下多连接隔离与同 request-id 路由独立性。

2. 线程生命周期
- `thread/start|resume|fork|read|list|loaded/list|archive|unarchive|unsubscribe|rollback|metadata/update|name/set|status`。
- 验证持久化 rollout、状态迁移、订阅关系、运行中线程恢复与异常态修复。

3. 回合生命周期与输入输出语义
- `turn/start|steer|interrupt` 的参数边界、输入长度限制、collaboration/personality 覆盖、输出 schema、生效时机。
- 验证 `item/started`/`item/completed`/`turn/completed` 的顺序和内容。

4. 审批与交互闭环
- `request_user_input`、`request_permissions`、命令审批、文件改动审批回合闭环。
- 重点校验 server request -> client response -> `serverRequest/resolved` -> turn 完成的顺序。

5. 工具与执行面
- `command/exec`（buffered 与 streaming、PTY resize、processId 作用域、env 覆盖、超时策略冲突）。
- `thread/shellCommand`（独立 turn 与复用活跃 turn 两模式）。

6. 本地 API 与生态能力
- `fs/*` 绝对路径约束、base64 读写、复制递归/特殊文件边界。
- `config/read|value/write|batchWrite` 与 layer/origin 一致性。
- `plugin/*`、`skills/list`、`app/list`、`model/list`、`experimentalFeature/list`、`collaborationMode/list`。

7. 实验能力与实时通道
- `experimentalApi` capability 门禁。
- `thread/realtime/*` 的 websocket 事件桥接和错误关闭语义。
- `windowsSandbox/setupStart`、Unix websocket 信号优雅退出路径。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 测试装配结构

- 集成测试单入口：`tests/all.rs`（`mod suite;`）。
- 模块树：`tests/suite/mod.rs` -> `auth`、`conversation_summary`、`fuzzy_file_search`、`v2/*`。
- 设计目的：将 Cargo 的单测试二进制模式与可维护的多模块目录结合。

### 2) 进程级测试驱动（`McpProcess`）

`tests/common/mcp_process.rs` 是整个目录最关键基建（约 1191 行）：

1. 启动策略
- 用 `codex_utils_cargo_bin::cargo_bin("codex-app-server")` 找到被测二进制并启动。
- 固定注入 `CODEX_HOME`，支持按测试覆盖/移除子进程环境变量（`new_with_env`）。

2. 协议握手
- `initialize_with_client_info` / `initialize_with_capabilities` 发送初始化请求。
- 收到初始化响应后主动发 `initialized` notification，模拟真实客户端握手。

3. 请求 API 封装
- 提供大量 `send_*_request` 方法，与 v2 RPC 方法一一对应（如 `send_thread_start_request`、`send_config_read_request`、`send_command_exec_request`）。
- 把测试关注点从 JSON 细节转为 typed params/response。

4. 流读取与缓冲
- `read_stream_until_*` 系列方法可按 request_id/method/谓词阻塞读取。
- 未匹配消息进 `pending_messages` 缓冲，避免并发通知导致断言顺序脆弱。

5. 稳定性与清理
- `Drop` 中执行“关闭 stdin -> 短暂等待 -> start_kill -> try_wait 轮询”的有界清理，降低子进程泄漏导致的 flaky。

### 3) Mock 与 Fixture 体系

1. Responses SSE 构造（`tests/common/responses.rs`）
- 构造 `shell_command`、`exec_command`、`request_user_input`、`request_permissions`、`apply_patch`、最终 assistant message 的 SSE 响应。
- 用于模拟模型返回 tool call 与最终消息，驱动审批和回合分支。

2. 模型服务 mock（`tests/common/mock_model_server.rs`）
- `create_mock_responses_server_sequence`：按调用次序返回预设 SSE，且可约束调用次数。
- `create_mock_responses_server_sequence_unchecked`：不约束调用次数，适合并发/竞态测试。

3. 配置 fixture（`tests/common/config.rs`）
- 动态写入 `config.toml`：feature flags、provider、`requires_openai_auth`、`model_auto_compact_token_limit` 等。

4. rollout fixture（`tests/common/rollout.rs`）
- 按 `CODEX_HOME/sessions/YYYY/MM/DD/rollout-*.jsonl` 生成最小可恢复会话。
- 可注入 `SessionMeta`、`git_info`、`text_elements`，用于 `thread/read|resume|list` 历史场景。

5. 认证与模型缓存 fixture
- `auth_fixtures.rs`：构造 ChatGPT token claims/JWT 并写入 `auth.json`。
- `models_cache.rs`：生成 `models_cache.json`，避免测试触发真实网络拉模型列表。

### 4) v2 关键流程样例

1. `turn_start` 主链路（`tests/suite/v2/turn_start.rs`）
- 校验 originator header、输入上限、text_elements 透传、协作模式覆盖、人格覆盖、审批决策、spawn agent item 元数据、命令 execution item 的 process_id。
- 同时断言 response + notifications 的时序和 payload。

2. `thread_resume` 复杂恢复（`tests/suite/v2/thread_resume.rs`）
- 覆盖未物化线程拒绝、rollout 历史恢复、运行中线程重连、审批请求重放、git metadata 偏好、mtime/updated_at 语义。
- 强依赖 rollout fixture + wiremock 请求计数稳定判定。

3. `command_exec` 执行面（`tests/suite/v2/command_exec.rs`）
- 流式/非流式双模式、processId 作用域、写入/resize/terminate、参数冲突报错。
- websocket 路径同测，验证传输层一致性。

4. `app_list`/`plugin_list` 生态集成
- `app_list.rs` 用本地 axum/rmcp mock server 模拟 connectors 与延迟更新通知。
- `plugin_list.rs` 验证 marketplace 解析、安装/启用状态、home/workspace 配置合并、remote sync/featured plugin 行为。

5. transport 行为
- `connection_handling_websocket.rs`：握手隔离、health endpoint、Origin 拒绝。
- `connection_handling_websocket_unix.rs`：SIGINT/SIGTERM 优雅退出与二次信号强制退出。

### 5) shell/平台特定支撑

- `tests/suite/zsh` 与 `tests/suite/bash` 是 dotslash 描述文件，会按平台下载预构建 shell fork 工件。
- `turn_start_zsh_fork.rs` 在 `#![cfg(not(windows))]` 下覆盖 zsh-fork 执行/审批分支，首次运行依赖 `dotslash` 与网络下载。

### 6) 协议与实现映射（调用方/被调用方）

测试调用方链路：

1. 测试代码（`tests/suite/**/*.rs`）
2. `app_test_support::McpProcess`（构造 JSON-RPC）
3. `codex-app-server` 进程（`app-server/src/lib.rs` + `message_processor.rs`）
4. 业务分发到 `app-server/src/codex_message_processor.rs`
5. 最终调用 `codex-core` ThreadManager/AuthManager/插件管理等能力

协议定义来源：
- `app-server-protocol/src/protocol/common.rs`（`ClientRequest` 宏定义 method<->params/response）
- `app-server-protocol/src/protocol/v2.rs`（`ThreadStartParams`、`TurnStartParams`、`CommandExecParams` 等）

### 7) 常见测试命令/执行方式

目录内行为对应命令（研究中观察到）：

- 启动 app-server 子进程：`cargo_bin("codex-app-server")`
- 通过 wiremock 挂载模型 SSE：`POST .../responses`
- websocket 端到端：`codex-app-server --listen ws://127.0.0.1:0`
- 日常跑法（由仓库约定）：`cargo test -p codex-app-server`

## 关键代码路径与文件引用

### A. 测试入口与组织
- `codex-rs/app-server/tests/all.rs`
- `codex-rs/app-server/tests/suite/mod.rs`
- `codex-rs/app-server/tests/suite/v2/mod.rs`

### B. 公共测试基建（被多数用例复用）
- `codex-rs/app-server/tests/common/lib.rs`
- `codex-rs/app-server/tests/common/mcp_process.rs`
- `codex-rs/app-server/tests/common/mock_model_server.rs`
- `codex-rs/app-server/tests/common/responses.rs`
- `codex-rs/app-server/tests/common/config.rs`
- `codex-rs/app-server/tests/common/rollout.rs`
- `codex-rs/app-server/tests/common/auth_fixtures.rs`
- `codex-rs/app-server/tests/common/models_cache.rs`

### C. 高频/高复杂度测试文件
- `codex-rs/app-server/tests/suite/v2/turn_start.rs`
- `codex-rs/app-server/tests/suite/v2/thread_resume.rs`
- `codex-rs/app-server/tests/suite/v2/thread_list.rs`
- `codex-rs/app-server/tests/suite/v2/app_list.rs`
- `codex-rs/app-server/tests/suite/v2/account.rs`
- `codex-rs/app-server/tests/suite/v2/command_exec.rs`
- `codex-rs/app-server/tests/suite/v2/plugin_list.rs`
- `codex-rs/app-server/tests/suite/v2/config_rpc.rs`

### D. 传输与平台特化
- `codex-rs/app-server/tests/suite/v2/connection_handling_websocket.rs`
- `codex-rs/app-server/tests/suite/v2/connection_handling_websocket_unix.rs`
- `codex-rs/app-server/tests/suite/v2/turn_start_zsh_fork.rs`
- `codex-rs/app-server/tests/suite/zsh`
- `codex-rs/app-server/tests/suite/bash`

### E. 关键被测实现（上下文依赖）
- `codex-rs/app-server/src/lib.rs`
- `codex-rs/app-server/src/message_processor.rs`
- `codex-rs/app-server/src/codex_message_processor.rs`
- `codex-rs/app-server/src/transport.rs`
- `codex-rs/app-server/src/thread_state.rs`
- `codex-rs/app-server/src/command_exec.rs`
- `codex-rs/app-server/src/fs_api.rs`
- `codex-rs/app-server/src/config_api.rs`

### F. 协议与文档
- `codex-rs/app-server-protocol/src/protocol/common.rs`
- `codex-rs/app-server-protocol/src/protocol/v2.rs`
- `codex-rs/app-server/README.md`

## 依赖与外部交互

1. Rust 依赖层
- 测试主要依赖：`wiremock`、`tokio`、`reqwest`、`tokio-tungstenite`、`rmcp`、`pretty_assertions`、`tempfile`。
- 内部依赖：`app_test_support`、`codex-app-server-protocol`、`codex-core`、`core_test_support`。

2. 进程与系统交互
- 直接启动 `codex-app-server` 子进程，读写 stdin/stdout JSONL。
- 部分用例调用系统命令（如 `git`）构造真实仓库状态。
- `command_exec`/`thread_shell_command` 用例涉及 shell 和 PTY。

3. 网络交互
- 测试主要走本地 mock server；部分用例通过 `skip_if_no_network!` 在无网环境跳过。
- zsh/bash dotslash 工件首次拉取需要外网。

4. 文件系统与状态存储
- 大量使用 `TempDir` 作为 `CODEX_HOME`，动态写入 `config.toml`、`auth.json`、`models_cache.json`、rollout jsonl。
- 覆盖路径合法性（必须绝对路径）与归档/反归档文件移动行为。

5. 脚本与文档协作
- 研究流程依赖 `Docs/researches/blueprint_checklist.md` 勾选状态。
- `.ops/generate_daily_research_todo.sh` 基于 checklist 生成每日 todo 快照。

## 风险、边界与改进建议

1. 风险：测试文件过大、职责过密
- `turn_start.rs`（~2585 行）、`thread_resume.rs`（~1950 行）维护成本高，review 粒度粗。
- 建议：按子场景拆分（输入校验/审批/协作模式/人格/通知时序）到更多文件，降低回归影响面。

2. 风险：`McpProcess` 单体过重
- 当前集成了进程启动、协议发送、读取缓冲、断言辅助和清理逻辑，接口多且耦合高。
- 建议：拆分为 `transport client`、`request facade`、`stream matcher` 三层，保持可测试性和复用清晰度。

3. 风险：基于 timeout 的异步断言容易引入偶发 flaky
- 多处使用固定超时 + 轮询，CI 负载变化时可能不稳定。
- 建议：引入统一的事件等待工具（带上下文日志与稳定窗口），减少散落 timeout 参数。

4. 边界：外部依赖导致结果不完全可复现
- dotslash 与网络可用性、平台差异（Unix/Windows）会改变用例实际执行路径。
- 建议：将“需网络/需 shell 工件”的前置条件集中在测试文档中，并提供本地缓存策略说明。

5. 边界：协议覆盖面广但方法级覆盖清单缺少自动化可视化
- 当前主要靠 `mod.rs` 与人工检索判断覆盖度。
- 建议：增加一个自动生成的“RPC 方法 -> 用例文件”映射报告（可由 `rg`/脚本生成并在 CI artifact 输出）。

6. 改进：为测试矩阵增加分层标签
- 建议引入轻量标签约定（例如 smoke/regression/slow/network/websocket），便于本地快速回归与 CI 分层并行。

