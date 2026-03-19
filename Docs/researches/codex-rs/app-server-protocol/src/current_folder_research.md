# DIR `codex-rs/app-server-protocol/src` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/app-server-protocol/src`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 目录文件总览：`13` 个 Rust 源文件（含 `bin/`）、约 `16,340` 行代码
- 相关上游目录：`codex-rs/app-server`、`codex-rs/app-server-client`、`codex-rs/exec`、`codex-rs/tui_app_server`、`codex-rs/debug-client`、`codex-rs/app-server-test-client`

## 场景与职责

`codex-rs/app-server-protocol/src` 是 Codex app-server 生态的协议单一事实源（single source of truth）。它同时承担“协议建模层 + 工件导出层 + 历史重建层”三类职责：

1. 协议建模层
- 定义 JSON-RPC 消息信封（`JSONRPCMessage/Request/Response/Error`、`RequestId`）与 app-server 的 typed request/response/notification。
- 将 v1 兼容面与 v2 主线 API 放在同一 crate 中统一导出，避免多端协议漂移。

2. 工件导出层
- 从 Rust 类型自动导出 TypeScript 类型与 JSON Schema（包括主 bundle 和 v2 flatten bundle）。
- 提供稳定化逻辑（experimental 字段/方法过滤、JSON canonicalize、TS header/index 生成）支撑文档、测试和外部 SDK 消费。

3. 历史重建层
- 将持久化 rollout 事件回放为 `Turn/ThreadItem` 结构，用于 `thread/read` / `thread/resume` / `thread/fork` 等场景的历史展示一致性。

这使它不仅是“类型定义目录”，更是 app-server 运行时、CLI 工具链、文档与测试基线的耦合中心。

## 功能点目的

### 1) 对外门面与 re-export（`lib.rs`）
- 位置：`codex-rs/app-server-protocol/src/lib.rs:1-47`
- 目的：把 `experimental_api`、`export`、`jsonrpc_lite`、`protocol::{common,v1,v2,thread_history}` 与 `schema_fixtures` 统一 re-export 给调用方。
- 效果：上游只依赖 `codex_app_server_protocol::*` 即可访问协议类型、导出 API 和 schema fixture API。

### 2) experimental API 能力门控基础设施（`experimental_api.rs`）
- 位置：`codex-rs/app-server-protocol/src/experimental_api.rs:5-31`
- 目的：通过 `ExperimentalApi` trait + `ExperimentalField` 注册表表达“方法级/字段级/嵌套级”实验能力。
- 补充能力：为 `Option/Vec/HashMap/BTreeMap` 实现递归原因传播（`34-54`），统一错误文案 `<reason> requires experimentalApi capability`（`30-31`）。

### 3) JSON-RPC 轻量信封（`jsonrpc_lite.rs`）
- 位置：`codex-rs/app-server-protocol/src/jsonrpc_lite.rs:12-86`
- 目的：提供 app-server 传输层统一消息 envelope，支持 string/integer 两种 `RequestId`（`14-20`）。
- 特点：采用“轻 JSON-RPC 2.0”策略（注释说明可不严格依赖 `jsonrpc` 字段），同时保留 trace 字段（`JSONRPCRequest.trace`，`47-58`）。

### 4) 协议总线与方法注册（`protocol/common.rs`）
- 位置：`codex-rs/app-server-protocol/src/protocol/common.rs`
- 目的：通过宏统一定义：
  - `ClientRequest`（`client_request_definitions!`，`205` 起）
  - `ServerRequest` / `ServerRequestPayload`（`server_request_definitions!`，`732` 起；payload 在宏实现 `560-630`）
  - `ServerNotification`（`server_notification_definitions!`，`874` 起）
  - `ClientNotification`（`client_notification_definitions!`，`943` 起）
- 额外职责：
  - 生成 schema/TS 导出 helper（宏内自动导出 params/response/notification schema）
  - 维护 experimental 方法清单与 `inspect_params` 逻辑（`47-56`, `133-151`）
  - 承载 v1 兼容方法、v2 新方法和 experimental 方法并存。

### 5) v1 兼容模型（`protocol/v1.rs`）
- 位置：`codex-rs/app-server-protocol/src/protocol/v1.rs`
- 目的：保留 initialize 和历史兼容接口形状，保障老客户端迁移窗口。
- 典型类型：
  - `InitializeParams/InitializeCapabilities/InitializeResponse`（`28`, `45`, `57`）
  - 旧会话查询与审批结构（如 `GetConversationSummaryParams`、`ExecCommandApprovalParams`）。

### 6) v2 主线协议（`protocol/v2.rs`）
- 位置：`codex-rs/app-server-protocol/src/protocol/v2.rs`
- 目的：定义所有活跃 API（config/account/thread/turn/fs/plugin/skills/review/realtime/approval/MCP 等）。
- 关键机制：
  - `v2_enum_from_core!` 宏把 core 枚举桥接为 API camelCase 枚举（`102` 起）。
  - 大量 `From<core_type>` / `into_core` 转换，维持协议层与 core 层边界。
- 典型对象：
  - `CommandExecParams`（`2289`）
  - `ThreadStartParams`（`2454`）
  - `TurnStartParams`（`3828`）
  - `ThreadItem`（`4121`）
  - `CommandExecutionRequestApprovalParams`（`5022`）
  - `McpServerElicitationRequestParams`（`5170`）

### 7) 历史重建与事件归约（`protocol/thread_history.rs`）
- 位置：`codex-rs/app-server-protocol/src/protocol/thread_history.rs`
- 目的：把 `RolloutItem/EventMsg` 归约为最终 `Vec<Turn>`：
  - 构建入口 `build_turns_from_rollout_items`（`64`）
  - 状态机 `ThreadHistoryBuilder`（`72`）
  - patch/tool/collab/review/error/rollback 等事件的逐类处理（`193-916`）
- 附加能力：`convert_patch_changes`（`1029`）用于稳定化 file change 输出。

### 8) schema/TS 导出与过滤（`export.rs` + `schema_fixtures.rs` + `bin/*`）
- `export.rs`
  - TS 导出入口：`generate_ts_with_options`（`105`）
  - JSON 导出入口：`generate_json_with_experimental`（`195`）
  - experimental 过滤：`filter_experimental_*`（`246-545`）
  - schema bundle 组装：`build_schema_bundle`（`946`）
  - v2 flatten bundle：`build_flat_v2_schema`（`1041`）
- `schema_fixtures.rs`
  - fixture 写入入口：`write_schema_fixtures_with_options`（`87`）
  - JSON/TS 归一化比较逻辑（canonicalize + CRLF 归一）
- `bin/export.rs`、`bin/write_schema_fixtures.rs`
  - 为 CLI/脚本提供独立可执行入口（`25-33`, `29`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. 协议分层与路由构建

1. 数据分层
- 传输层：`jsonrpc_lite.rs` 的 `JSONRPCMessage` 及子类型。
- 业务层：`common.rs` 的 `ClientRequest/ServerRequest/ServerNotification`。
- 版本层：`v1.rs`（兼容）+ `v2.rs`（主线）。

2. 路由生成方式
- `common.rs` 使用宏定义 method->params/response 的映射，减少手写 enum / schema 导出重复代码。
- 宏同时生成：
  - `id()`/`method()` 等 helper（`ClientRequest::method` 在 `120`）
  - schema 导出函数（client/server param/response/notification）
  - experimental 方法元数据数组。

3. Server request 双形态
- `ServerRequest` 用于 on-wire 序列化。
- `ServerRequestPayload` 用于 app-server 内部先构造 payload，后绑定 request id（`request_with_id`，`587-591`）。

### B. 初始化与 experimental 门控链路

1. 协议侧
- `v1::InitializeCapabilities` 定义 `experimental_api` 与 `opt_out_notification_methods`（`v1.rs:45-52`）。
- `ExperimentalApi` 能在 request 值上动态返回触发原因。

2. 运行时侧（调用方 `app-server`）
- `message_processor` 初始化分支中记录连接状态：
  - `session.experimental_api_enabled`、`session.opted_out_notification_methods`（`message_processor.rs:533-545`）
- 非 initialize 请求若命中 experimental 且能力未开启，返回：
  - `experimental_required_message(reason)`（`message_processor.rs:617-622`）

3. `inspect_params` 设计
- 对“方法稳定、字段实验性”的场景（如 `thread/start`），`common.rs` 通过 `inspect_params: true` 将校验下放到 params 内部字段（`47-56`, `213` 附近）。

### C. v2 模型实现细节

1. core-to-API 桥接
- `v2_enum_from_core!` 统一生成 serde/ts-rs 注解与 `From`/`to_core`，降低同类枚举重复实现成本。

2. 参数语义兼容
- `service_tier` 使用双层 `Option<Option<T>>`（配合 `serde_helpers::{deserialize,serialize}_double_option`）保留“未传 vs 显式 null”语义。
- 见 `ThreadStartParams` 与 `TurnStartParams` 的 `service_tier` 字段（`v2.rs:2458-2466`, `3845-3853`）。

3. 审批与权限模型
- `CommandExecutionRequestApprovalParams` 承载 command、network、additionalPermissions、availableDecisions 等复合审批信息（`5022` 起）。
- `strip_experimental_fields()` 当前为硬编码剥离策略（`5078-5085`），用于向未启用 experimental 客户端降级。

4. MCP elicitation schema 建模
- `McpElicitationSchema` 系列类型（`5194` 起）实现了对 MCP 表单 schema 的结构化映射，并区分单选/多选/legacy enum 变体。

5. ThreadItem 归一化
- `ThreadItem` 把 user/agent/reasoning/command/file/mcp/dynamic/collab/web/image/review/compaction 项统一成可序列化 union（`4121` 起），并有 `id()` 快速索引（`4252-4271`）。

### D. 历史重建状态机（thread_history）

1. 处理策略
- `ThreadHistoryBuilder::handle_event` 针对可持久化 `EventMsg` 做显式 match 分发（`118-181`）。
- 对 turn 生命周期、item started/completed、tool begin/end、error、rollback 都有独立 reducer。

2. turn 完整性规则
- `finish_current_turn` 会丢弃“非显式开启 + 无 item + 非 compaction”空 turn（`930-936`）。
- rollback 会截断 turn 列表并重置 item 序号（`916-928`）。

3. upsert 语义
- `upsert_turn_item` 使用 item id 做覆盖更新（`1088-1097`），保证 started/completed 两阶段事件不会重复追加。

### E. schema 生成与稳定化流程

1. 命令入口
- `just write-app-server-schema`（根 `justfile:82-83`）
- 二进制：`write_schema_fixtures --experimental`（`bin/write_schema_fixtures.rs`）
- CLI 子命令：`codex app-server generate-ts` / `generate-json-schema` / `generate-internal-json-schema`（`cli/src/main.rs:655-681`）

2. 导出流程
- TS：导出所有类型 -> 过滤 experimental -> 生成 index -> 补 header -> 可选 prettier。
- JSON：导出 envelope + params/responses -> bundle -> 过滤 experimental -> 生成 flat v2 bundle。

3. 稳定化关键点
- `filter_client_request_ts_contents` 精确删除 experimental method union arm。
- `filter_experimental_type_fields_ts_contents` 删除 experimental 字段并回收无用 type import。
- `build_flat_v2_schema` 解决 codegen 工具对嵌套 `definitions.v2` 的兼容问题。

### F. 测试与回归覆盖

1. 单元/集成分布
- `experimental_api.rs`：derive + nested 传播测试（4 个）
- `common.rs`：序列化、方法名、experimental reason 等（32 个）
- `v2.rs`：参数/通知 round-trip、core 映射、experimental gating、MCP schema（66 个）
- `thread_history.rs`：复杂事件编排与回放边界（24 个）
- `export.rs`：schema bundle/experimental 过滤/TS 过滤（9 个）
- `schema_fixtures.rs` + `tests/schema_fixtures.rs`：工件一致性（4 个）

2. fixture 一致性机制
- `tests/schema_fixtures.rs` 用 `similar::TextDiff` 对比仓内 fixture 与实时生成输出，不一致则提示运行 `just write-app-server-schema`。

## 关键代码路径与文件引用

### 目录内核心入口

1. `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/lib.rs:1`
- crate 级模块与 re-export 门面。

2. `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs:205`
- `client_request_definitions!` 的方法注册总表（v2 主线 + v1 兼容 + experimental）。

3. `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs:560`
- `ServerRequestPayload` 与 `request_with_id` 内部请求构造器。

4. `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs:874`
- `ServerNotification` 方法映射总表。

5. `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:2289`
- `command/exec` 请求模型（流式与 buffered 双模式）。

6. `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:2454`
- `thread/start` 参数模型（包含 experimental 字段与能力门控字段）。

7. `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:3828`
- `turn/start` 参数模型。

8. `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:4121`
- `ThreadItem` 统一 item union。

9. `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:5022`
- 命令审批请求参数（含 additional permissions / available decisions）。

10. `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:5170`
- MCP elicitation 请求参数。

11. `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/thread_history.rs:64`
- rollout -> turn 重建入口。

12. `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/export.rs:105`
- TS 导出主入口。

13. `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/export.rs:195`
- JSON 导出主入口。

14. `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/export.rs:946`
- schema bundle 构建。

15. `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/export.rs:1041`
- v2 flatten bundle 构建。

16. `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/schema_fixtures.rs:87`
- fixture 写入入口（TS+JSON 一次生成）。

17. `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/bin/export.rs:25`
- CLI 可执行导出入口。

18. `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs:29`
- schema fixture 生成可执行入口。

### 关键上下游调用点

1. `/home/sansha/Github/codex/codex-rs/app-server/src/message_processor.rs:533`
- 初始化时写入 `experimental_api_enabled` 与 notification opt-out。

2. `/home/sansha/Github/codex/codex-rs/app-server/src/message_processor.rs:617`
- experimental 请求拒绝路径（`experimental_required_message`）。

3. `/home/sansha/Github/codex/codex-rs/app-server/src/codex_message_processor.rs:612`
- app-server 主请求分发入口（消费 `ClientRequest`）。

4. `/home/sansha/Github/codex/codex-rs/app-server/src/outgoing_message.rs:10`
- server notification/request 的统一出站封装。

5. `/home/sansha/Github/codex/codex-rs/app-server-client/src/lib.rs:31`
- in-process 客户端统一依赖协议类型。

6. `/home/sansha/Github/codex/codex-rs/app-server-client/src/remote.rs:24`
- remote websocket 客户端 JSON-RPC + typed 协议解码。

7. `/home/sansha/Github/codex/codex-rs/exec/src/lib.rs:21`
- `codex exec` 通过协议类型发起 thread/turn/review 请求并消费 server request/notification。

8. `/home/sansha/Github/codex/codex-rs/tui_app_server/src/app.rs:51`
- TUI app-server 前端对协议对象的深度消费。

9. `/home/sansha/Github/codex/codex-rs/debug-client/src/client.rs:17`
- debug 客户端手工调试请求/响应。

10. `/home/sansha/Github/codex/codex-rs/app-server-test-client/src/lib.rs:28`
- 端到端测试客户端依赖协议类型进行脚本化测试。

### 文档与脚本路径

1. `/home/sansha/Github/codex/justfile:82`
- `write-app-server-schema` 自动化入口。

2. `/home/sansha/Github/codex/codex-rs/cli/src/main.rs:655`
- `codex app-server generate-ts/json-schema/internal-json-schema` 子命令。

3. `/home/sansha/Github/codex/codex-rs/app-server/README.md:1414`
- 维护者指南明确要求在 `app-server-protocol/src/protocol/v2.rs` 做 experimental 标注并回写 schema。

4. `/home/sansha/Github/codex/codex-rs/docs/codex_mcp_interface.md:11`
- 对外文档将协议定义路径指向 `app-server-protocol/src/protocol/{common,v1,v2}.rs`。

## 依赖与外部交互

### 1) crate 依赖结构

1. 核心序列化与 schema
- `serde`, `serde_json`, `schemars`, `ts-rs`, `serde_with`

2. 协议桥接与共享类型
- `codex-protocol`（大量 core 类型转换源）
- `rmcp`（MCP elicitation/action 模型桥接）
- `codex-utils-absolute-path`（绝对路径类型）

3. experimental 元编程
- `codex-experimental-api-macros`
- `inventory`

4. 工具与执行
- `clap`（bin 参数）
- `anyhow`, `thiserror`, `tracing`

依赖声明位于：`/home/sansha/Github/codex/codex-rs/app-server-protocol/Cargo.toml:1-43`。

### 2) 构建与测试系统交互

1. Cargo workspace
- workspace 声明路径依赖：`/home/sansha/Github/codex/codex-rs/Cargo.toml:95`

2. Bazel
- `BUILD.bazel` 把 `schema/**` 作为测试数据引入（`/home/sansha/Github/codex/codex-rs/app-server-protocol/BUILD.bazel:6`），保证 fixture 测试在 Bazel 下可访问。

3. fixture 测试资源定位
- `tests/schema_fixtures.rs` 使用 `codex_utils_cargo_bin::find_resource!` 定位 `schema/typescript/index.ts` 与 `schema/json/*.json`，规避 Bazel runfiles 差异（`110-125`）。

### 3) 外部协议消费面

1. app-server 运行时
- 入站解析：`ClientRequest`
- 出站事件：`ServerNotification`
- 回调请求：`ServerRequest`

2. 客户端生态
- in-process + remote 客户端共享同一协议对象，确保 exec/TUI/debug-client/app-server-test-client 行为一致。

3. 文档与生态工具
- app-server README 与 MCP interface 文档以本目录类型为“权威定义来源”。

## 风险、边界与改进建议

### 风险

1. 体量集中风险
- `v2.rs`（7,922 行）和 `common.rs`（1,719 行）是高频修改点，易产生冲突和隐性回归。

2. 双版本并存复杂度
- v1 兼容接口与 v2 主线共存增加了 schema 维护和路由认知成本，特别是 method rename/弃用过程。

3. experimental 过滤链路分散
- experimental 过滤同时存在于 request runtime gate（app-server）和 schema/TS 生成阶段（protocol crate），若两处规则漂移，会出现“运行时不可用但 schema 可见”或反向问题。

4. schema 工件漂移
- 修改协议但未更新 fixture 会导致 CI 失败；反过来如果仅更新 fixture 而忽视运行时逻辑，也可能产生“工件正确、行为不一致”。

5. history 重建的事件覆盖边界
- `thread_history.rs` 显式列举 event 处理，如果 core 新增可持久化事件但未同步处理，历史展示可能信息缺失或状态不准。

### 边界

1. 协议层不负责业务执行
- 本目录主要定义 wire shape、转换和导出，不做 thread/turn 真正执行；执行逻辑在 `app-server` 与 `core`。

2. JSON-RPC envelope 与业务模型分离
- `jsonrpc_lite.rs` 仅关心 envelope；method 语义在 `common.rs`/`v2.rs`。

3. 兼容优先策略
- 多处兼容字段与 alias（如 legacy enum/guardian snake_case alias）体现“对旧客户端宽进”，但增加维护负担。

### 改进建议

1. 按领域拆分 `v2.rs`
- 建议拆分为 `v2/{config,account,thread,turn,item,approval,mcp,filesystem,plugin}.rs`，保留 `mod v2` 聚合导出，降低单文件改动冲突。

2. 抽象 experimental 剥离规则
- `CommandExecutionRequestApprovalParams::strip_experimental_fields` 目前硬编码字段清空，建议统一用 trait/metadata 驱动（与 `ExperimentalField` 注册表对齐）。

3. 增强“协议变更摘要”自动化
- 在 schema 生成或 CI 中增加 method/字段差异报告（新增/删除/重命名），提升 review 可见性。

4. 为 thread_history 增加“事件覆盖断言”
- 结合 core 的持久化事件列表做编译期/测试期对齐检查，避免新事件漏接。

5. 对外文档与协议类型自动联动
- 可考虑从 `common.rs` method registry 自动生成一份 machine-readable method index，减少 README 手工维护成本。
