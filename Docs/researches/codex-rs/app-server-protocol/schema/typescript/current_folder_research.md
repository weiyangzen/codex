# DIR `codex-rs/app-server-protocol/schema/typescript` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript`
- 研究日期：2026-03-19
- 目录现状（当前仓库快照）：
  - `typescript/` 根层 `.ts`：75
  - `typescript/v2/`：332
  - `typescript/serde_json/`：1
  - 总计：408 个 TypeScript 产物文件
  - 大文件主要集中在聚合 union 与索引：`v2/index.ts`、`ClientRequest.ts`、`ServerNotification.ts`

## 场景与职责

该目录是 `codex-app-server-protocol` 的 TypeScript 协议发布面（vendored fixtures），核心职责是把 Rust 协议类型稳定导出为 TS 类型系统可消费的契约文件，而不是业务逻辑代码。

1. 协议发布职责（面向客户端）
- 通过根索引导出核心类型并暴露 `v2` 命名空间：`codex-rs/app-server-protocol/schema/typescript/index.ts:1-77`。
- `ClientRequest`/`ServerRequest`/`ServerNotification` 作为 JSON-RPC 双向通信骨架，承载 method-tagged union：
  - `.../schema/typescript/ClientRequest.ts:61-64`
  - `.../schema/typescript/ServerRequest.ts:15-18`
  - `.../schema/typescript/ServerNotification.ts:56-59`

2. 仓库内回归基线职责（fixture）
- `tests/schema_fixtures.rs` 将本目录作为 golden fixtures，与“当前代码内存生成树”逐文件集合 + 内容比较，防协议漂移：`codex-rs/app-server-protocol/tests/schema_fixtures.rs:11-105`。

3. 与运行时 experimental 协商保持一致职责
- 目录默认是稳定面（非 experimental），对应 app-server 初始化 capability 协商与运行时字段剥离策略：
  - 初始化能力写入：`codex-rs/app-server/src/message_processor.rs:533-545`
  - 未 opt-in 拒绝实验请求：`.../message_processor.rs:616-625`
  - 服务端请求 payload 出站剥离实验字段：`codex-rs/app-server/src/transport.rs:660-681`

## 功能点目的

1. 为 TS 客户端提供“一次导入”的类型入口
- `index.ts` 自动 re-export 各类型，避免消费侧逐文件 import：`.../schema/typescript/index.ts:3-77`。

2. 对 JSON-RPC method contract 做类型约束
- `ClientRequest` 与 `ServerRequest` 以 `method` 字段区分变体，实现请求路由与 params 形状强绑定：
  - `.../ClientRequest.ts:64`
  - `.../ServerRequest.ts:18`

3. 将 v2 主线协议与根层兼容类型分层
- v2 类型集中在 `typescript/v2`，根层同时保留少量兼容/共用类型（如 `Initialize*`、`RequestId`、`serde_json/JsonValue`）：
  - `.../serde_json/JsonValue.ts:5`
  - `.../v2/ThreadStartParams.ts:11-23`

4. 让 stable/experimental 两套协议面可切换导出
- 生成默认过滤实验方法/字段；`--experimental` 保留全量输出：
  - 文档约束：`codex-rs/app-server/README.md:1356-1365`
  - 过滤实现：`codex-rs/app-server-protocol/src/export.rs:246-256`

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 上游定义 -> TS 产物的主流程

1. 协议类型源头（被调用方）
- `client_request_definitions!` 宏定义 `ClientRequest`，并同时生成 response/schema 导出辅助函数：`codex-rs/app-server-protocol/src/protocol/common.rs:81-203`。
- 宏内产出 experimental 元数据常量（方法、参数类型、响应类型），供后续过滤链路使用：`.../common.rs:150-164`。
- v2 结构体普遍使用 `#[serde(rename_all = "camelCase")]` + `#[ts(export_to = "v2/")]`，确保 wire 命名与 TS 文件布局一致（例：`ThreadStartParams`）：`codex-rs/app-server-protocol/src/protocol/v2.rs:2452-2508`。

2. TS 导出入口
- `generate_ts_with_options` 依次导出四个总线类型及其依赖，再按配置执行过滤、索引、头部、Prettier：`codex-rs/app-server-protocol/src/export.rs:105-182`。
- 关键调用顺序：
  - `ClientRequest::export_all_to` / `ServerRequest::export_all_to`：`.../export.rs:114-120`
  - `filter_experimental_ts`（stable 默认开启）：`.../export.rs:122-124,246-256`
  - `generate_index_ts`（根 + v2）：`.../export.rs:126-129,1947-1997`
  - `prepend_header_if_missing` 并行补 `// GENERATED CODE!`：`.../export.rs:131-163,1897-1903`

3. 稳定面过滤算法（TS）
- 方法级过滤：从 `ClientRequest.ts` type alias union 中删除 experimental method arms：`.../export.rs:294-331`。
- 字段级过滤：按 `type_name -> experimental_field_names` 对每个 TS 文件去字段并裁剪无用 import：`.../export.rs:334-398`。
- 类型文件级删除：删除 experimental params/response 产物：`.../export.rs:576-597`。

### 2) fixture 写盘与命令链（调用方/脚本/配置）

1. 仓库脚本入口（调用方）
- `just write-app-server-schema`：`justfile:81-83`。

2. 可执行入口（脚本化命令）
- `write_schema_fixtures` 二进制支持参数：`--schema-root`、`--prettier`、`--experimental`：`codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs:6-20`。
- `export` 二进制可直接输出 TS+JSON 到任意目录：`codex-rs/app-server-protocol/src/bin/export.rs:5-34`。

3. 目录清理与重建策略（配置影响）
- `write_schema_fixtures_with_options` 先清空 `schema/typescript` 与 `schema/json`，再分别生成，避免陈旧文件残留：`codex-rs/app-server-protocol/src/schema_fixtures.rs:87-109`。
- `SchemaFixtureOptions.experimental_api` 决定稳定面/实验面输出：`.../schema_fixtures.rs:23-26,101-103`。

4. CLI 用户入口（文档化调用方）
- `codex app-server generate-ts --out DIR [--experimental]` 在 CLI 中调用同一导出函数：`codex-rs/cli/src/main.rs:655-668`。
- README 明确此命令是官方 schema 导出路径：`codex-rs/app-server/README.md:48-55,1356-1365`。

### 3) 测试校验与协议一致性

1. fixture 集合/内容严格比对
- TS fixture 测试：`typescript_schema_fixtures_match_generated`：`codex-rs/app-server-protocol/tests/schema_fixtures.rs:11-21`。
- 差异报错会明确提示执行 `just write-app-server-schema`：`.../tests/schema_fixtures.rs:75-100`。

2. 导出器单测覆盖关键约束
- TS 中禁止 `| undefined` 与可选可空越界（只允许 `*Params` 等例外）：`codex-rs/app-server-protocol/src/export.rs:2042-2260`。
- 稳定面应去除实验方法/字段/类型与 `EventMsg` 索引导出：`.../export.rs:2052-2076,2029-2025`。
- `--experimental` 应保留实验项：`.../export.rs:2274-2307`。

### 4) 关键数据结构与协议形态

1. method-tagged union
- `ClientRequest`/`ServerRequest`/`ServerNotification` 使用 `{ "method": ..., params: ... }` 判别联合：
  - `.../schema/typescript/ClientRequest.ts:64`
  - `.../schema/typescript/ServerRequest.ts:18`
  - `.../schema/typescript/ServerNotification.ts:56`

2. v2 请求参数的 nullable optional 约定
- 常见模式为 `field?: T | null`（来自 `#[ts(optional = nullable)]`），如：
  - `ThreadStartParams`：`.../schema/typescript/v2/ThreadStartParams.ts:11-23`
  - `AppsListParams`：`.../schema/typescript/v2/AppsListParams.ts:8-24`

3. JSON 值桥接
- `serde_json::Value` 在 TS 中被展开为递归联合 `JsonValue`：`.../schema/typescript/serde_json/JsonValue.ts:5`。

## 关键代码路径与文件引用

### A. 目标目录与代表产物
- `codex-rs/app-server-protocol/schema/typescript/index.ts:1-77`
- `codex-rs/app-server-protocol/schema/typescript/ClientRequest.ts:1-64`
- `codex-rs/app-server-protocol/schema/typescript/ServerRequest.ts:1-18`
- `codex-rs/app-server-protocol/schema/typescript/ServerNotification.ts:1-59`
- `codex-rs/app-server-protocol/schema/typescript/serde_json/JsonValue.ts:1-5`
- `codex-rs/app-server-protocol/schema/typescript/v2/ThreadStartParams.ts:1-23`
- `codex-rs/app-server-protocol/schema/typescript/v2/CommandExecutionRequestApprovalParams.ts:1-62`
- `codex-rs/app-server-protocol/schema/typescript/v2/index.ts:1`

### B. 生成实现（被调用方）
- `codex-rs/app-server-protocol/src/export.rs:105-182`
- `codex-rs/app-server-protocol/src/export.rs:246-331`
- `codex-rs/app-server-protocol/src/export.rs:334-398`
- `codex-rs/app-server-protocol/src/export.rs:1947-2027`
- `codex-rs/app-server-protocol/src/schema_fixtures.rs:53-76`
- `codex-rs/app-server-protocol/src/schema_fixtures.rs:87-109`
- `codex-rs/app-server-protocol/src/schema_fixtures.rs:120-204`

### C. 协议来源与 experimental 元数据
- `codex-rs/app-server-protocol/src/protocol/common.rs:81-203`
- `codex-rs/app-server-protocol/src/protocol/common.rs:205-240`
- `codex-rs/app-server-protocol/src/protocol/v2.rs:2450-2508`
- `codex-rs/app-server-protocol/src/protocol/v2.rs:5019-5088`

### D. 调用方/命令/文档
- `justfile:81-83`
- `codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs:6-42`
- `codex-rs/app-server-protocol/src/bin/export.rs:5-34`
- `codex-rs/cli/src/main.rs:655-678`
- `codex-rs/app-server/README.md:48-55`
- `codex-rs/app-server/README.md:1354-1459`

### E. 测试与构建打包
- `codex-rs/app-server-protocol/tests/schema_fixtures.rs:11-143`
- `codex-rs/app-server-protocol/src/export.rs:2042-2307`
- `codex-rs/app-server-protocol/BUILD.bazel:3-7`

### F. 运行时协商与出站清洗（上下游一致性）
- `codex-rs/app-server/src/message_processor.rs:533-545`
- `codex-rs/app-server/src/message_processor.rs:616-625`
- `codex-rs/app-server/src/transport.rs:660-681`

## 依赖与外部交互

1. Rust 依赖
- TS 导出依赖 `ts-rs`；JSON/结构体映射依赖 `serde`、`serde_json`、`schemars`，定义在 `codex-rs/app-server-protocol/Cargo.toml`。

2. 可选外部工具
- `prettier` 可通过 CLI 参数传入，用于格式化生成 TS：
  - 参数定义：`codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs:13-15`
  - 调用点：`codex-rs/app-server-protocol/src/export.rs:165-179`

3. 构建系统交互
- Bazel 将 `schema/**` 注入该 crate 测试数据，保证测试在 runfiles 环境可读：`codex-rs/app-server-protocol/BUILD.bazel:3-7`。

4. 与 app-server 协议协商交互
- 运行时是否允许实验请求由 `initialize.capabilities.experimentalApi` 决定，生成侧 stable/experimental 导出策略需与之一致：
  - `codex-rs/app-server/src/message_processor.rs:533-545,616-625`
  - `codex-rs/app-server/README.md:1370-1406`

5. 文档与维护流程交互
- README 明确维护流程：改协议后需重生成 fixtures 并跑协议测试：`codex-rs/app-server/README.md:1447-1459`。

## 风险、边界与改进建议

### 风险

1. 产物规模较大，PR 可读性差
- 408 个 TS 文件，单次变更容易出现大量噪音 diff，人工审查 method/字段语义变化成本高。

2. 过滤策略是“文本后处理”，存在脆弱点
- `ClientRequest.ts` 与 type/interface 字段过滤依赖字符串解析（split/property parse/import prune），若未来 ts-rs 输出风格变化，可能误删或漏删：`codex-rs/app-server-protocol/src/export.rs:308-398`。

3. 运行时与生成时 experimental 逻辑分散
- 生成过滤、请求拒绝、出站字段清洗分散在多个模块；新增实验字段时有同步遗漏风险。

4. 出站 experimental 清洗尚为局部硬编码
- `strip_experimental_fields()` 当前仅显式清除 `additional_permissions` 与 `skill_metadata`，注释中也提示需要通用化：`codex-rs/app-server-protocol/src/protocol/v2.rs:5082-5087`。

### 边界

1. 本目录是生成产物，默认不手工编辑。
2. 协议语义源头在 `src/protocol/**` 与 `src/export.rs`，不是 `schema/typescript` 本身。
3. 是否能在运行时调用实验能力，不由此目录决定，而由连接初始化能力协商决定。

### 改进建议

1. 增加“语义级 schema diff”输出
- 在 `write_schema_fixtures` 后自动生成 method/field 级变更摘要，降低大规模文件 diff 审阅成本。

2. 给 TS 过滤器加结构化测试夹具
- 针对 `filter_client_request_ts_contents`、`filter_experimental_type_fields_ts_contents` 增加更多 ts-rs 输出变体样本，降低格式漂移风险。

3. 统一 experimental 出站剥离机制
- 从单个 payload 的手工字段清理，演进到通用 trait/visitor 级别的自动剥离，以减少未来新增字段遗漏。

4. 在 README 增补 TypeScript 目录结构与消费建议
- 明确根层 vs `v2/` vs `serde_json/` 的定位、稳定面默认行为、`--experimental` 使用边界，减少第三方消费误用。
