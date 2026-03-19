# codex-rs/app-server-protocol 目录研究

## 研究范围
- 目标目录：`codex-rs/app-server-protocol`
- 关联上下文（调用方/被调用方/配置/测试/脚本/文档）覆盖：
  - `codex-rs/app-server`
  - `codex-rs/app-server-client`
  - `codex-rs/tui_app_server`
  - `codex-rs/exec`
  - `codex-rs/exec-server`
  - `codex-rs/cli`
  - `codex-rs/docs/codex_mcp_interface.md`
  - `codex-rs/app-server/README.md`
  - 根目录 `justfile`

## 场景与职责
`codex-app-server-protocol` 是 Codex Rust 体系中“应用层协议契约”所在 crate，处于“业务运行时（app-server/core）”与“客户端（TUI/exec/远程 websocket 客户端）”之间，负责统一以下能力：

- 定义 JSON-RPC 消息信封与请求/响应/通知类型。
- 维护 v2 主线 API 与 v1 兼容 API 的共存边界。
- 用单一 Rust 类型源生成 TypeScript 类型与 JSON Schema（供客户端集成、文档、测试基线使用）。
- 通过 experimental API 标注机制实现“字段级/方法级”能力门控。
- 提供历史事件重建逻辑（将 rollout/event 还原为可读的 thread/turn/item 结构）。

在运行时链路中的定位：

- 入站：客户端发送 JSON-RPC -> app-server 反序列化到 `ClientRequest`。
- 出站：app-server 发送 `ServerNotification`/`ServerRequest` 给客户端。
- tooling：CLI/just 命令基于该 crate 导出 schema 与 TS 定义。

## 功能点目的
### 1) 协议主模型与兼容层
- `protocol/v2.rs`：承载当前活跃 API（线程、回合、审批、文件系统、模型、账号、插件、实时会话等）。
- `protocol/v1.rs`：保留初始化与少量兼容接口（如 `getConversationSummary`/`getAuthStatus` 等历史面向）。
- `protocol/common.rs`：把 v1/v2 组装为统一的 `ClientRequest`、`ServerRequest`、`ServerNotification`、`ClientNotification` 联合体，并定义 method wire 名称。

目的：在不破坏旧客户端的前提下，以 v2 作为持续演进主干。

### 2) JSON-RPC 轻量信封
- `jsonrpc_lite.rs` 提供 `JSONRPCMessage/Request/Notification/Response/Error` 与 `RequestId`。
- 说明“并非严格要求 jsonrpc 字段存在”，但仍以 2.0 结构组织。

目的：统一传输消息形状，兼容 stdio/websocket 等 transport。

### 3) Experimental API 门控
- `experimental_api.rs` 定义 trait `ExperimentalApi` + `ExperimentalField` 注册表（`inventory`）。
- `common.rs` 宏展开中将 experimental 原因提取到方法/参数层。
- app-server 在 `message_processor` 中根据连接初始化能力 `experimentalApi` 进行拒绝或放行。

目的：允许快速迭代新字段/新方法，同时对未声明支持的客户端保持稳定契约。

### 4) 生成与分发 schema/类型
- `export.rs`/`schema_fixtures.rs` 提供：
  - TypeScript 导出（`ts-rs` + index 聚合 + 可选 prettier）
  - JSON Schema 导出（全量 bundle、v2 flatten bundle）
  - 过滤 experimental 字段/方法
- `src/bin/export.rs` 与 `src/bin/write_schema_fixtures.rs` 提供可执行入口。

目的：把“协议代码”直接变为“可分发工件”，避免手写 TS/Schema 漂移。

### 5) 历史重建
- `protocol/thread_history.rs` 将 persisted rollout 事件转换为 `Vec<Turn>`。

目的：`thread/read`、resume/fork 后的历史可视化和状态还原保持一致。

## 具体技术实现（关键流程/数据结构/协议/命令）
### A. 初始化与能力协商流程
1. 客户端发送 `initialize`（`v1::InitializeParams`，含 `clientInfo` 与 `capabilities`）。
2. app-server `message_processor` 内部处理初始化：
   - 连接状态 `initialized` 置位。
   - 记录 `experimental_api_enabled` 与 `opt_out_notification_methods`。
3. 后续请求若未初始化则直接返回 `Not initialized`。
4. 客户端发送 `initialized` 通知（`ClientNotification::Initialized`）。

实现要点：
- `common.rs` 中 `ClientRequest::Initialize` 是唯一“初始化前允许”的请求。
- 初始化能力按“连接级”生效（当前行为），对共享线程多客户端场景有已知语义复杂性（源码 TODO 已标注）。

### B. 请求反序列化与分发流程
1. 传输层 JSON -> `JSONRPCRequest`。
2. 反序列化为 `ClientRequest`（基于 `method` 标签）。
3. `message_processor` 先处理配置/文件系统/初始化等入口逻辑。
4. 其余请求委派给 `codex_message_processor`，按 `match ClientRequest` 路由到具体 handler。

实现要点：
- `common.rs` 的宏 `client_request_definitions!` 同时生成：
  - 枚举定义
  - method 提取方法
  - response/schema 导出器
  - experimental 方法清单

### C. Experimental 门控流程
1. `#[experimental("...")]` 可标注在方法、枚举 variant、字段。
2. `codex-experimental-api-macros` 生成 `ExperimentalApi` 派生逻辑。
3. `ClientRequest::experimental_reason()` 在 `common.rs` 汇总。
4. app-server 校验：若连接未开启 `capabilities.experimentalApi` 且请求命中 experimental，则返回：
   - `<descriptor> requires experimentalApi capability`

实现要点：
- `inspect_params: true` 用于“方法稳定、但某些 params 字段实验性”的场景（如 thread start/resume/fork 等）。
- 对集合/嵌套结构，`Option/Vec/HashMap/BTreeMap` 都有递归 experimental reason 提取实现。

### D. Schema/TS 生成流程
关键入口：
- `just write-app-server-schema`
- `cargo run -p codex-app-server-protocol --bin write_schema_fixtures -- [--experimental]`
- `codex app-server generate-ts`
- `codex app-server generate-json-schema`

主要步骤：
1. 清空 `schema/typescript` 与 `schema/json`。
2. 导出 `ClientRequest/ServerNotification/...` 与关联 params/response。
3. 若非 experimental 模式，过滤 experimental 方法/字段与类型文件。
4. 生成 index.ts 聚合文件。
5. JSON 输出包含总 bundle 与 v2 flatten bundle。

实现要点：
- `schema_fixtures.rs` 对 JSON 做 canonicalize（键排序、可排序数组排序）以减少跨平台噪音 diff。
- TypeScript 比较时移除统一 header 并规范换行，保证 fixture 测试稳定。

### E. 线程历史重建流程
1. 输入 `RolloutItem` 序列。
2. `ThreadHistoryBuilder` 按事件类型增量构建 `Turn` 与 `ThreadItem`。
3. 处理 turn 生命周期、item start/completed、tool call、patch、command、review、compaction 等事件。
4. 输出稳定的 `Vec<Turn>` 用于读取/恢复展示。

实现要点：
- 对旧流/不完整事件做兼容处理（隐式 turn、fallback）。
- 只处理持久化策略允许的事件子集，未知/无关事件忽略。

### F. 核心数据结构与协议设计
- 信封层：`RequestId` 支持 `string|integer`；`JSONRPCMessage` 为 untagged union。
- 请求/通知：serde `tag = "method"` + `content = "params"`，wire 名统一 camelCase 或显式 `serde(rename)`。
- v2 设计约束（从类型与注释可见）：
  - 方法名采用 `<resource>/<method>` 风格，resource 多为单数。
  - 对外边界倾向使用字符串 ID。
  - 可选字段与 TS 可选语义通过 `#[ts(optional = nullable)]` 协同。

## 关键代码路径与文件引用
### 目录内（app-server-protocol）
- `codex-rs/app-server-protocol/src/lib.rs`
  - crate re-export 汇总，向外提供协议类型与生成 API。
- `codex-rs/app-server-protocol/src/jsonrpc_lite.rs`
  - JSON-RPC 轻量模型。
- `codex-rs/app-server-protocol/src/protocol/common.rs`
  - 方法总线（`ClientRequest/ServerRequest/ServerNotification/ClientNotification`）与宏生成框架。
- `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - v2 协议主定义（体量最大，所有核心业务对象）。
- `codex-rs/app-server-protocol/src/protocol/v1.rs`
  - v1 兼容类型。
- `codex-rs/app-server-protocol/src/protocol/thread_history.rs`
  - rollout->turn 重建逻辑。
- `codex-rs/app-server-protocol/src/experimental_api.rs`
  - experimental trait、字段注册、错误文案。
- `codex-rs/app-server-protocol/src/export.rs`
  - TS/JSON schema 导出与过滤。
- `codex-rs/app-server-protocol/src/schema_fixtures.rs`
  - fixture 生成、读取、规范化。
- `codex-rs/app-server-protocol/tests/schema_fixtures.rs`
  - 生成结果与仓内 fixture 一致性测试。

### 主要调用方与被调用方
- 调用方：
  - `codex-rs/app-server/src/message_processor.rs`
  - `codex-rs/app-server/src/codex_message_processor.rs`
  - `codex-rs/app-server-client/src/{lib.rs,remote.rs}`
  - `codex-rs/exec/src/lib.rs`
  - `codex-rs/cli/src/main.rs`
- 文档/协议消费者：
  - `codex-rs/app-server/README.md`
  - `codex-rs/docs/codex_mcp_interface.md`
  - `codex-rs/exec-server/README.md`

### 关键 method 映射样例（来自 common.rs）
- `thread/start`, `thread/resume`, `thread/fork`, `thread/read`, `thread/list`
- `turn/start`, `turn/steer`, `turn/interrupt`
- `item/commandExecution/requestApproval`, `item/fileChange/requestApproval`, `item/tool/call`
- `app/list`, `skills/config/write`, `config/read`, `config/value/write`
- 通知：`thread/started`, `turn/completed`, `item/agentMessage/delta`, `app/list/updated` 等

## 依赖与外部交互
### Rust 依赖（核心）
- 序列化与 schema：`serde`, `serde_json`, `schemars`, `ts-rs`
- experimental 元编程：`codex-experimental-api-macros`, `inventory`
- 共享核心协议模型：`codex-protocol`
- CLI 与工具：`clap`, `anyhow`

### 运行时交互
- 与 `app-server`：
  - 入站请求解析、初始化能力协商、experimental 校验、业务分发。
- 与 `app-server-client`：
  - in-process 与 remote websocket 都复用本协议类型。
- 与 `exec`/`tui_app_server`：
  - 直接构造 `ClientRequest::*` 并消费 `ServerNotification::*`。

### 构建/测试/脚本交互
- `justfile`：`write-app-server-schema` 调用本 crate 的 `write_schema_fixtures` 二进制。
- `cargo test -p codex-app-server-protocol`：校验 schema fixture 与当前类型定义一致。
- Bazel：`BUILD.bazel` 为该 crate 声明 `schema/**` 测试数据。

### 文档协同
- `app-server/README.md` 详细描述握手、能力协商、experimental 开关、method 行为。
- `docs/codex_mcp_interface.md` 对外描述 MCP 接口形状并引用该目录类型定义。

## 风险、边界与改进建议
### 风险与边界
- 大文件维护风险：`v2.rs`（~270k+）与 `common.rs`（~60k+）体量大，评审与回归难度高。
- 双栈长期共存复杂度：v1 兼容接口与 v2 并存，容易产生行为/文档漂移。
- experimental 语义边界：当前按连接协商，跨客户端共享线程时可能出现“能力视图不一致”。
- schema 漂移风险：若改类型未同步 regenerate fixture，会在 CI/测试中失败。
- Wire rename 一致性风险：`serde(rename)` 与 `ts(rename)` 若不同步，会导致 TS 与 Rust 契约分叉。

### 改进建议
- 拆分 `v2.rs`：按领域（thread/turn/account/config/tooling/realtime）模块化，降低冲突面。
- 为 method 映射建立自动清单文档：从 `common.rs` 自动导出 method 索引到 docs，避免人工维护遗漏。
- 强化 experimental 回归：增加“同一请求在 experimental on/off 下”行为差异测试样例。
- 增加 schema 变更守卫：在 PR CI 中显示“变更了哪些 method/字段”的摘要报告，提升评审可读性。
- 在 app-server README 中补充“连接级 experimental 与多客户端共享线程”的行为说明，减少集成方误解。

## 结论
`codex-rs/app-server-protocol` 是 Codex app-server 体系的协议单一事实源（Single Source of Truth）：
- 它不仅定义消息类型，也承担 schema/TS 工件生产、experimental 生命周期管理、历史重建语义固化。
- 其设计直接影响 app-server、app-server-client、exec、tui、MCP 文档与外部集成稳定性。
- 该目录的工程关键点不在“单次功能实现”，而在“协议兼容性 + 工件一致性 + 多端协同演进”。
