# DIR `codex-rs/app-server-protocol/src/protocol` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 文件规模：7 个 Rust 文件，约 12,587 行（`v2.rs` 7,922 行、`thread_history.rs` 2,648 行、`common.rs` 1,719 行）

## 场景与职责

`codex-rs/app-server-protocol/src/protocol` 是 app-server 协议核心定义层，承担三类职责：

1. 协议路由与方法注册中心
- `common.rs` 用宏统一声明 `ClientRequest / ServerRequest / ServerNotification / ClientNotification`，把 method 字符串、params、response 绑定到强类型（`common.rs:205`, `common.rs:732`, `common.rs:874`, `common.rs:943`）。

2. 版本化协议模型
- `v1.rs` 保留兼容接口（initialize 与旧 API）。
- `v2.rs` 承载活跃 API 面（thread/turn/config/fs/skills/plugins/review/realtime/approval/mcp 等）。

3. 历史回放与 Item 归约
- `thread_history.rs` 把 rollout `EventMsg` 回放成 `Turn + ThreadItem`，为 `thread/read` / `thread/resume` / `thread/fork` 提供可展示历史（`thread_history.rs:64`, `thread_history.rs:72`）。

该目录不是“纯类型声明”，而是 app-server 运行时协议行为的主事实源，且直接影响 schema 导出、客户端反序列化、事件回放一致性。

## 功能点目的

### 1) 协议主干（`common.rs`）
- 通过宏减少重复代码，同时自动生成：
  - request/notification 枚举
  - `id()`/`method()` helper
  - schema 导出入口
  - experimental 方法元信息
- 关键方法映射示例：
  - `thread/read`（`common.rs:291`）
  - `turn/start`（`common.rs:351`）
  - `command/exec/outputDelta` 通知（`common.rs:901`）
- 兼容 JSON-RPC envelope 与 typed server request 的互转：`TryFrom<JSONRPCRequest> for ServerRequest`（`common.rs:724`）。

### 2) v1 兼容层（`v1.rs`）
- 目标是保留老客户端可用性，尤其 initialize、旧会话查询与旧审批结构。
- `InitializeCapabilities` 在 v1 已支持 `experimentalApi` 与 `optOutNotificationMethods`，为 v2 扩展留出协商入口。

### 3) v2 主线模型（`v2.rs`）
- 目标是将 app-server 运行时能力完整暴露到协议层，并与 core 类型做桥接。
- 高价值对象：
  - `Config` / `ConfigReadParams`（`v2.rs:692`, `v2.rs:799`）
  - `SandboxPolicy`（`v2.rs:1275`）
  - `CommandExecParams`（`v2.rs:2289`）
  - `ThreadStartParams` / `ThreadResumeParams` / `ThreadReadParams`（`v2.rs:2454`, `v2.rs:2558`, `v2.rs:3048`）
  - `TurnStartParams`（`v2.rs:3828`）
  - `UserInput` / `ThreadItem`（`v2.rs:4045`, `v2.rs:4121`）
  - `CommandExecutionRequestApprovalParams`（`v2.rs:5022`）
  - `McpServerElicitationRequestParams`（`v2.rs:5170`）
- 包含大量 core <-> protocol 转换，确保协议层稳定且与执行层解耦。

### 4) 历史归约器（`thread_history.rs`）
- `ThreadHistoryBuilder` 作为事件 reducer，逐类处理 message/tool/approval/error/rollback。
- 关键点：
  - 支持 late completion 归属正确 turn（`handle_exec_command_end`，`thread_history.rs:354`）
  - rollback 直接裁剪 turns 并重置 item index（`thread_history.rs:916`）
  - 通过 upsert 语义避免 started/completed item 重复（`thread_history.rs:1088`）
  - patch 变更统一转换并排序（`thread_history.rs:1029`）

### 5) 辅助模块
- `serde_helpers.rs`：`Option<Option<T>>` 的序列化/反序列化辅助。
- `mappers.rs`：v1 `ExecOneOffCommandParams` 到 v2 `CommandExecParams` 的桥接。
- `mod.rs`：protocol 子模块导出边界。

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. 请求处理主流程（协议 -> 运行时）

1. 连接接入后，`app-server` 先解析 JSONRPC 请求，再反序列化到 `ClientRequest`。
- 初始化与 experimental gate 在 `message_processor.rs` 处理（`message_processor.rs:512`, `message_processor.rs:616`）。
- 若 request 含实验性方法/字段且连接未开启 `experimentalApi`，返回 `experimental_required_message(reason)`（`message_processor.rs:621`）。

2. 非 config/fs 请求转发给 `CodexMessageProcessor` 做业务分发。
- v2 method 分支集中在 `codex_message_processor.rs` 的 `match ClientRequest`（`codex_message_processor.rs:612` 起，thread/turn/mcp/plugins 等均在此）。

3. 业务事件转为通知/请求
- `bespoke_event_handling.rs` 把 core `EventMsg` 映射为 `ServerNotification` / `ServerRequestPayload`。
- 典型：MCP elicitation 事件转 `McpServerElicitationRequestParams` 并走 server request 往客户端请求回包（`bespoke_event_handling.rs:773`）。

### B. 历史回放流程（rollout -> turn items）

1. 从 rollout 读取 `RolloutItem` 列表。
2. 调用 `build_turns_from_rollout_items` 归约（`thread_history.rs:64`）。
3. `ThreadHistoryBuilder::handle_event` 分流处理 EventMsg（`thread_history.rs:118`）。
4. 通过 `upsert_turn_item` 用 item id 覆盖更新，确保 begin/end/delta 事件整合。
5. `finish_current_turn` 在空 turn 过滤条件下落盘（`thread_history.rs:930`）。

该流程在 thread rollback 响应组装时被 app-server 直接调用（`bespoke_event_handling.rs:1753`）。

### C. 协议数据结构设计要点

1. 三态字段语义
- 多处使用 `Option<Option<T>>` + serde helper 保留：未传 / 显式 null / 具体值 三态（如 `service_tier`、metadata patch 字段）。

2. 统一 Item union
- `ThreadItem` 把 user message、agent message、reasoning、command execution、file change、mcp tool、dynamic tool、collab 等都统一为可持久化展示结构（`v2.rs:4121`）。

3. 实验能力最小侵入
- 方法级：在 `common.rs` 方法声明上 `#[experimental("method")`。
- 字段级：在 v2 类型字段上 `#[experimental("method.field")`，并依赖 `inspect_params` 触发。

4. 兼容层转换
- `impl From<CoreTurnItem> for ThreadItem`（`v2.rs:4366`）让 core item 可直接映射为协议 item，减少上游重复映射代码。

### D. 协议与 schema 产物生成命令

1. CLI 导出命令
- `codex app-server generate-ts --out DIR`
- `codex app-server generate-json-schema --out DIR`
- 入口在 `cli/src/main.rs:664`, `cli/src/main.rs:675`。

2. 仓库标准命令
- `just write-app-server-schema`（`justfile:82-83`）
- 调用 `codex-app-server-protocol` 的 `write_schema_fixtures` 二进制。

3. 导出实现链路
- `generate_ts_with_options`（`export.rs:105`）
- `generate_json_with_experimental`（`export.rs:195`）
- experimental 过滤（`export.rs:246`）
- v2 flat bundle 组装（`export.rs:1041`）

### E. 测试与验证实现

- `common.rs`：32 个测试（请求/通知序列化、experimental reason）。
- `v2.rs`：66 个测试（round-trip、core 映射、兼容别名、权限/schema 约束）。
- `thread_history.rs`：24 个测试（turn 边界、late event、rollback、collab、error 语义）。
- `tests/schema_fixtures.rs`：2 个 fixture 一致性测试，保障 vendored schema 不漂移。

## 关键代码路径与文件引用

### 目录内部

1. 协议注册与宏展开
- `codex-rs/app-server-protocol/src/protocol/common.rs:205`
- `codex-rs/app-server-protocol/src/protocol/common.rs:732`
- `codex-rs/app-server-protocol/src/protocol/common.rs:874`

2. v2 主模型
- `codex-rs/app-server-protocol/src/protocol/v2.rs:692`
- `codex-rs/app-server-protocol/src/protocol/v2.rs:1275`
- `codex-rs/app-server-protocol/src/protocol/v2.rs:2289`
- `codex-rs/app-server-protocol/src/protocol/v2.rs:2454`
- `codex-rs/app-server-protocol/src/protocol/v2.rs:3828`
- `codex-rs/app-server-protocol/src/protocol/v2.rs:4121`
- `codex-rs/app-server-protocol/src/protocol/v2.rs:5022`
- `codex-rs/app-server-protocol/src/protocol/v2.rs:5170`

3. 历史回放
- `codex-rs/app-server-protocol/src/protocol/thread_history.rs:64`
- `codex-rs/app-server-protocol/src/protocol/thread_history.rs:118`
- `codex-rs/app-server-protocol/src/protocol/thread_history.rs:354`
- `codex-rs/app-server-protocol/src/protocol/thread_history.rs:916`
- `codex-rs/app-server-protocol/src/protocol/thread_history.rs:1029`

4. 辅助
- `codex-rs/app-server-protocol/src/protocol/serde_helpers.rs:1`
- `codex-rs/app-server-protocol/src/protocol/mappers.rs:1`

### 上下游关键调用路径（调用方 / 被调用方）

1. app-server 请求入口
- `codex-rs/app-server/src/message_processor.rs:276`
- `codex-rs/app-server/src/message_processor.rs:616`
- `codex-rs/app-server/src/codex_message_processor.rs:612`

2. core 事件 -> 协议通知/请求
- `codex-rs/app-server/src/bespoke_event_handling.rs:58`
- `codex-rs/app-server/src/bespoke_event_handling.rs:773`
- `codex-rs/app-server/src/bespoke_event_handling.rs:1753`

3. 远端客户端解码
- `codex-rs/app-server-client/src/remote.rs:291`
- `codex-rs/app-server-client/src/remote.rs:760`

4. schema 工具链
- `codex-rs/app-server-protocol/src/export.rs:105`
- `codex-rs/app-server-protocol/src/export.rs:195`
- `codex-rs/app-server-protocol/src/schema_fixtures.rs:87`
- `codex-rs/cli/src/main.rs:664`
- `justfile:82`

5. 协议文档入口
- `codex-rs/app-server/README.md:50`
- `codex-rs/app-server/README.md:126`
- `codex-rs/app-server/README.md:131`
- `codex-rs/app-server/README.md:1347`
- `codex-rs/app-server-client/README.md:23`

## 依赖与外部交互

### 1) 直接依赖（被调用方）

来自 `codex-rs/app-server-protocol/Cargo.toml`：

- `codex-protocol`：核心领域模型/事件类型来源（大部分 `From<Core*>` 桥接依赖它）。
- `codex-experimental-api-macros` + `inventory`：experimental 字段注册与推导。
- `serde` / `serde_json` / `serde_with`：wire 编解码与三态字段支持。
- `schemars` / `ts-rs`：JSON Schema 与 TypeScript 产物导出。
- `rmcp`：MCP elicitation/action 类型对接。
- `uuid`：thread_history 的本地 turn id 生成（v7）。

### 2) 主要调用方

- `codex-rs/app-server`：服务端请求分发、事件转通知、审批交互。
- `codex-rs/app-server-client`：in-process/remote 客户端 typed 协议消费。
- `codex-rs/tui_app_server`：UI 层对 `ServerRequest/ServerNotification` 逐项处理。
- `codex-rs/cli`：`app-server generate-*` 命令触发 schema 导出。

### 3) 配置与脚本交互

- 配置协商：通过 initialize capabilities 控制 `experimentalApi` 与 notification opt-out。
- 脚本命令：`just write-app-server-schema` 触发 schema fixture 重生成。
- 测试脚本依赖：`tests/schema_fixtures.rs` 校验 vendored schema 与实时生成是否一致。

### 4) 文档交互

- `app-server/README.md` 明确 method 契约与示例 payload，协议定义变更后需要同步该文档。

## 风险、边界与改进建议

### 风险与边界

1. 单文件过大带来的变更风险
- `v2.rs` 近 8k 行，跨域模型高度集中，评审与回归成本高，容易出现无意耦合。

2. 宏注册中心可读性门槛高
- `common.rs` 通过宏同时生成枚举、导出和 experimental 元数据，改动 method 时需理解宏副作用，否则可能出现 schema/TS 导出遗漏感知。

3. 历史回放的“有损边界”
- 历史重建依赖可持久化事件集，未持久化事件不会回放；虽然有 `persist_extended_history` 机制，但旧 rollout 仍有历史损失边界。

4. experimental 字段剥离策略存在维护成本
- `strip_experimental_fields` 目前是手工字段白名单式剥离（`v2.rs:5082`），新增字段后若遗漏会造成兼容行为偏差。

5. 多端契约一致性压力
- 协议被 app-server、app-server-client、tui_app_server、文档与 schema fixtures 同时消费，任何字段 rename/可空语义调整都可能引发跨组件回归。

### 改进建议

1. 结构化拆分 `v2.rs`
- 按领域拆为 `config.rs`、`thread.rs`、`turn.rs`、`approval.rs`、`mcp.rs`、`plugin.rs` 等，保留 `mod v2` 汇总导出，降低单点冲突与阅读负担。

2. 提升协议注册可视化
- 在 CI 产出 method inventory（method -> params/response type -> experimental reason）报告，帮助快速审查协议变更。

3. 统一 experimental 剥离策略
- 把 server->client payload 的实验字段剥离改为自动化（基于 `ExperimentalField` 注册表），减少手写同步成本。

4. 强化回放完整性观测
- 对 `thread_history` 中“unknown turn id item dropped”这类 warn 增加指标打点，便于发现线上回放缺口。

5. 变更门禁建议
- 对 `protocol/` 变更执行最小门禁：
  - `cargo test -p codex-app-server-protocol`
  - `just write-app-server-schema`（若协议形状变更）
  - 文档同步检查（`app-server/README.md` 的方法/字段示例）。
