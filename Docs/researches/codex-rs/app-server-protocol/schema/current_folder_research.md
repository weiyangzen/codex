# DIR `codex-rs/app-server-protocol/schema` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/app-server-protocol/schema`
- 研究日期：2026-03-19
- 研究结论：该目录是 `codex-app-server-protocol` 的“协议快照发布面”，由 Rust 协议类型自动生成并作为稳定产物 vendoring 到仓库，服务于测试校验、CLI 导出、SDK 代码生成与跨端协议对齐。

## 场景与职责

`schema/` 目录承担的是“协议产物层”职责，不是手写业务逻辑层。

1. 对外协议快照（TS + JSON Schema）
- TypeScript 导出入口文件：`codex-rs/app-server-protocol/schema/typescript/index.ts:1-77`，统一 re-export 根类型并暴露 `v2` 命名空间。
- v2 TypeScript 聚合：`codex-rs/app-server-protocol/schema/typescript/v2/index.ts:1-120`（文件很长，实际覆盖 300+ 类型）。
- JSON Schema bundle（混合根 + v2 命名空间）：`codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.schemas.json:1-120`。
- JSON Schema bundle（flatten 后 v2 友好格式）：`codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json:1-120`。

2. 兼容层快照
- `json/v1` 仅保留 initialize 相关兼容 schema（`InitializeParams/InitializeResponse`），例如：
  - `codex-rs/app-server-protocol/schema/json/v1/InitializeParams.json:1-67`
  - `codex-rs/app-server-protocol/schema/json/v1/InitializeResponse.json:1-23`

3. 作为“可回归的协议基线”
- `tests/schema_fixtures.rs` 会将该目录视为 golden fixtures，对比“当前代码重新生成结果”与“仓库已提交结果”是否一致，防止协议漂移（`codex-rs/app-server-protocol/tests/schema_fixtures.rs:11-143`）。

4. 目录规模（当前仓库状态）
- `schema/json` 共 187 个文件，其中 `json/v2` 150 个。
- `schema/typescript` 共 408 个文件，其中 `typescript/v2` 332 个。

## 功能点目的

1. 给客户端提供强类型消费入口
- TS 客户端可直接使用 `schema/typescript/**`，从 `index.ts` 一次性导入协议类型（`.../typescript/index.ts:3-77`）。

2. 给代码生成工具提供 JSON Schema
- mixed bundle：保留根定义 + `definitions.v2`，利于内部语义完整表达。
- flat v2 bundle：为 datamodel-code-generator 等只遍历一层 definitions 的工具准备（设计说明见 `codex-rs/app-server-protocol/src/export.rs:1029-1088`）。

3. 区分稳定面与实验面
- 默认生成稳定协议；实验字段/方法会被过滤。
- 对应产品文档说明在 `codex-rs/app-server/README.md:1354-1459`。

4. 保障跨平台稳定比较
- fixture 对比阶段会做 JSON 规范化、数组稳定排序、TS 换行标准化和头部忽略，降低 Windows/Unix 差异导致的伪 diff（`codex-rs/app-server-protocol/src/schema_fixtures.rs:120-204`）。

5. 把“协议定义代码”与“产物目录”严格绑定
- 修改协议类型后，必须通过固定命令重生产物并由测试强制校验。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 生成入口与命令链路

1. 仓库命令入口
- `just write-app-server-schema` -> `cargo run -p codex-app-server-protocol --bin write_schema_fixtures -- "$@"`（`justfile:81-83`）。

2. 二进制入口
- `write_schema_fixtures` 支持：`--schema-root`、`--prettier`、`--experimental`（`codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs:6-41`）。

3. 调用库层
- `write_schema_fixtures_with_options()` 会清空 `schema/typescript` 和 `schema/json` 后重建（`.../schema_fixtures.rs:86-117`）。
- TS 由 `generate_ts_with_options()` 生成，JSON 由 `generate_json_with_experimental()` 生成（`.../schema_fixtures.rs:98-107`）。

### 2) 类型来源与导出机制

1. 协议类型源
- `protocol/common.rs` 用宏统一定义 `ClientRequest`、`ServerRequest`、`ServerNotification` 及其 schema 导出函数（`.../protocol/common.rs:81-203`, `543-693`, `640-721`）。
- v2 类型普遍通过 `#[serde(rename_all = "camelCase")]` + `#[ts(export_to = "v2/")]` 对齐 wire 与 TS 产物（示例：`.../protocol/v2.rs:135-171`, `3472-3512`）。

2. 实验能力标注与检测
- 请求方法级/字段级实验信息从 `ClientRequest` 宏展开中导出为：
  - `EXPERIMENTAL_CLIENT_METHODS`
  - `EXPERIMENTAL_CLIENT_METHOD_PARAM_TYPES`
  - `EXPERIMENTAL_CLIENT_METHOD_RESPONSE_TYPES`
  （`.../protocol/common.rs:150-164`）。
- `inspect_params: true` 用于“方法稳定但 params 内部分字段实验”的场景（如 `thread/start`）（`.../protocol/common.rs:213-218`, `351-355`）。

3. 典型实验字段样例
- `ThreadStartParams.mock_experimental_field` 用于验证实验过滤链路（`.../protocol/v2.rs:2454-2508`）。
- 服务端审批请求中实验字段：`additional_permissions`、`skill_metadata`（`.../protocol/v2.rs:5022-5065`）。

### 3) TS 生成关键过程

1. 基础导出
- `ClientRequest/Notification/ServerRequest/Notification` + 对应 response 类型一并导出（`.../export.rs:114-120`）。

2. 稳定面过滤
- 非 experimental 模式会执行：
  - `filter_client_request_ts`：移除实验方法 union arms；
  - `filter_experimental_type_fields_ts`：移除实验字段；
  - 删除实验类型文件。
  （`.../export.rs:246-256`, `294-398`, `576-597`）。

3. 索引与头部
- 自动生成 `index.ts` 与 `v2/index.ts`（`.../export.rs:1945-1997`）。
- 自动补充 `// GENERATED CODE!` 头（`.../export.rs:1888-1908`）。

### 4) JSON 生成关键过程

1. 单文件 + bundle 双写
- 先写各 schema，再构建：
  - `codex_app_server_protocol.schemas.json`
  - `codex_app_server_protocol.v2.schemas.json`
  （`.../export.rs:195-237`）。

2. mixed bundle 构建
- `build_schema_bundle()` 将定义按 namespace 聚合，重写 `$ref` 以匹配 namespaced definitions（`.../export.rs:946-1027`）。

3. flat v2 bundle 构建
- `build_flat_v2_schema()` 将 `definitions.v2` 拉平，并补齐 shared root dependencies，最后强校验不再含 `#/definitions/v2/` 引用（`.../export.rs:1029-1088`）。

4. 稳定面过滤
- 过滤实验字段/实验方法，并移除实验类型定义和文件（`.../export.rs:400-406`, `545-553`, `616-652`）。

5. v1 收敛策略
- JSON 侧仅允许 v1 initialize 相关定义进入最终产物（`JSON_V1_ALLOWLIST` + retain 逻辑，`.../export.rs:39-40`, `222-224`, `1278-1323`）。

### 5) 测试与一致性保障

1. fixture 对比测试
- TS：内存生成树 vs `schema/typescript`。
- JSON：临时目录生成 vs `schema/json`。
- 不一致时直接提示运行 `just write-app-server-schema`（`.../tests/schema_fixtures.rs:67-101`）。

2. 生成器单测
- 覆盖实验字段/方法过滤、flat v2 bundle 引用完整性、index 去除 EventMsg、可选可空约束等（`.../export.rs:2042-2819`）。

### 6) 运行时协议协商与 schema 的对应关系

1. 连接级 experimentalApi 协商
- `initialize` 解析 capability，并保存到 session（`codex-rs/app-server/src/message_processor.rs:527-545`）。
- 未开启 experimentalApi 时，请求命中实验能力将直接报错（`.../message_processor.rs:616-625`）。

2. 出站字段清洗
- 对 `ServerRequest::CommandExecutionRequestApproval`，若连接未开启实验能力，会调用 `strip_experimental_fields()` 去掉实验字段（`codex-rs/app-server/src/transport.rs:660-679`；对应实现 `.../protocol/v2.rs:5081-5088`）。

3. 文档契约
- README 明确 stable/experimental 生成与运行时 opt-in 语义（`codex-rs/app-server/README.md:1354-1459`）。

## 关键代码路径与文件引用

### A. 目标目录（产物）
- `codex-rs/app-server-protocol/schema/typescript/index.ts:1-77`
- `codex-rs/app-server-protocol/schema/typescript/v2/index.ts:1-120`
- `codex-rs/app-server-protocol/schema/typescript/serde_json/JsonValue.ts:1-5`
- `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.schemas.json:1-120`
- `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json:1-120`
- `codex-rs/app-server-protocol/schema/json/v1/InitializeParams.json:1-67`
- `codex-rs/app-server-protocol/schema/json/v1/InitializeResponse.json:1-23`

### B. 生成与过滤（被调用方）
- `codex-rs/app-server-protocol/src/schema_fixtures.rs:23-109`
- `codex-rs/app-server-protocol/src/export.rs:82-244`
- `codex-rs/app-server-protocol/src/export.rs:246-406`
- `codex-rs/app-server-protocol/src/export.rs:545-652`
- `codex-rs/app-server-protocol/src/export.rs:946-1088`
- `codex-rs/app-server-protocol/src/export.rs:1278-1323`
- `codex-rs/app-server-protocol/src/export.rs:1888-2026`

### C. 协议类型源（上游定义）
- `codex-rs/app-server-protocol/src/protocol/common.rs:81-203`
- `codex-rs/app-server-protocol/src/protocol/common.rs:205-541`
- `codex-rs/app-server-protocol/src/protocol/common.rs:640-945`
- `codex-rs/app-server-protocol/src/protocol/v2.rs:2450-2538`
- `codex-rs/app-server-protocol/src/protocol/v2.rs:5022-5088`
- `codex-rs/app-server-protocol/src/protocol/v2.rs:5170-5205`

### D. 调用方/工具链
- `justfile:81-83`
- `codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs:6-41`
- `codex-rs/app-server-protocol/src/bin/export.rs:5-34`
- `codex-rs/cli/src/main.rs:353-390`
- `codex-rs/cli/src/main.rs:655-681`
- `codex-rs/app-server/README.md:48-55`

### E. 测试与校验
- `codex-rs/app-server-protocol/tests/schema_fixtures.rs:11-143`
- `codex-rs/app-server-protocol/src/export.rs:2029-2819`
- `codex-rs/app-server-protocol/src/schema_fixtures.rs:333-356`

### F. 运行时协商（上下文依赖）
- `codex-rs/app-server/src/message_processor.rs:156-163`
- `codex-rs/app-server/src/message_processor.rs:527-545`
- `codex-rs/app-server/src/message_processor.rs:616-625`
- `codex-rs/app-server/src/transport.rs:660-679`

## 依赖与外部交互

1. 依赖关系（crate 级）
- schema 生成核心依赖：`schemars`（JSON Schema）、`ts-rs`（TS 导出）、`serde/serde_json`（序列化）与 `codex-experimental-api-macros`（实验标注）见 `codex-rs/app-server-protocol/Cargo.toml:14-36`。
- dev 依赖 `codex-utils-cargo-bin` 支撑 Bazel runfiles 下 fixture 定位（`.../Cargo.toml:38-43`，测试代码 `.../tests/schema_fixtures.rs:107-133`）。

2. 外部命令/工具
- `just write-app-server-schema`（仓库规范入口）。
- `codex app-server generate-ts` / `generate-json-schema`（面向客户端工具链，`codex-rs/app-server/README.md:48-55`）。
- 可选 `prettier` 用于格式化生成 TS（`.../bin/write_schema_fixtures.rs:13-15`, `.../export.rs:165-179`）。

3. 与 app-server 运行时交互
- schema 反映了 initialize capability（尤其 `experimentalApi`）的协商协议；运行时以同一套 `ClientRequest`/`ServerRequest` 类型判定和清洗字段（`.../message_processor.rs:527-545`, `616-625`; `.../transport.rs:660-679`）。

4. 与文档/维护流程交互
- 维护者流程明确要求：改协议 -> 重新生成 schema -> 跑协议测试（`codex-rs/app-server/README.md:1447-1459`）。

## 风险、边界与改进建议

### 风险

1. 产物目录体量大，review 成本高
- 数百文件变更时，人审容易遗漏真正语义变化（尤其批量 rename/ref 变化）。

2. 实验过滤链路分散
- 过滤逻辑跨 `common.rs` 宏常量、`export.rs` 过滤函数、`app-server` 运行时字段剥离（`strip_experimental_fields`）三处，维护时需同步理解。

3. Mixed/Flat 双 bundle 增加一致性复杂度
- 若 `$ref` 重写或依赖闭包收集出错，可能出现 codegen silently degraded（例如回退到 Any）的隐患。

4. 平台差异导致伪差异风险仍然存在
- 已做规范化，但生成工具链升级（ts-rs/schemars/serde）仍可能产生大规模非语义 diff。

### 边界

1. `schema/` 目录是生成产物，不应手工编辑。
2. 真正协议语义在 `src/protocol/**` 和 `src/export.rs`。
3. 运行时是否接受/过滤实验能力不由 `schema/` 决定，而由 app-server request/transport 逻辑决定。

### 改进建议

1. 增加 schema 变更摘要工具
- 在 `write_schema_fixtures` 后输出“方法新增/删除、字段新增/删除”的结构化摘要，降低审查负担。

2. 建立“稳定面 contract test”白名单
- 对关键方法（`initialize`、`thread/start`、`turn/start` 等）生成最小快照集合，避免大文件 diff 淹没核心变更。

3. 将实验字段剥离策略统一抽象
- 当前仅对 `CommandExecutionRequestApprovalParams` 做了运行时出站剥离（`.../v2.rs:5081-5088`）；可抽象通用 outbound experimental scrub 层，减少硬编码。

4. 在 README 增补“schema 目录结构图 + bundle 适用场景”
- 明确 mixed bundle 与 flat v2 bundle 的消费差异，帮助 SDK/外部集成方避免误用。
