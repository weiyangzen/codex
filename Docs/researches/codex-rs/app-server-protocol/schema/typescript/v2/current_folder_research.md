# DIR `codex-rs/app-server-protocol/schema/typescript/v2` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/v2`
- 研究日期：2026-03-19
- 目录快照：
  - `*.ts` 文件数：332（含 `index.ts`）
  - 总行数：3519（`wc -l`）
  - 最大文件：`index.ts`（333 行）
  - 主要类型前缀分布（粗粒度）：`Thread(50)`、`Mcp(35)`、`Command(19)`、`Turn(15)`、`Plugin(15)`、`Fs(15)`

## 场景与职责

`schema/typescript/v2` 是 app-server v2 协议的“TypeScript 发布面（vendored artifacts）”。它不承载业务执行逻辑，职责是把 Rust 协议类型稳定映射成 TS 契约，供外部客户端/工具链直接消费。

1. 协议契约发布职责
- 每个 v2 Rust 类型（`#[ts(export_to = "v2/")]`）会产出一个同名 `.ts` 文件，形成可按类型粒度引用的契约层。
- 聚合入口由 `v2/index.ts` 统一 re-export，降低消费方导入复杂度：`codex-rs/app-server-protocol/schema/typescript/v2/index.ts:1-333`。

2. 上下游桥接职责
- 上游：承接 `codex-rs/app-server-protocol/src/protocol/v2.rs` 与 `src/protocol/common.rs` 的请求/响应/通知类型定义。
- 下游：被根层 `schema/typescript` 的 envelope 类型（`ClientRequest`、`ServerRequest`、`ServerNotification`）引用：
  - `codex-rs/app-server-protocol/schema/typescript/ClientRequest.ts:7-60`
  - `codex-rs/app-server-protocol/schema/typescript/ServerRequest.ts:7-13`
  - `codex-rs/app-server-protocol/schema/typescript/ServerNotification.ts:6-52`

3. 稳定面与实验面切分职责
- 默认 fixture 为 stable 面，experimental 字段/方法会在导出流程中被过滤。
- `--experimental` 生成时保留完整 experimental 协议面。
- 该切分与运行时 `initialize.capabilities.experimentalApi` 协商保持一致（详见后文“依赖与外部交互”）。

## 功能点目的

1. 为 v2 API 提供强类型请求/响应/通知模型
- 线程生命周期：`ThreadStartParams`、`ThreadResumeParams`、`ThreadForkParams`、`ThreadListParams`、`ThreadStatus` 等。
- Turn 与 Item：`TurnStartParams`、`Turn`、`ThreadItem` 等。
- 审批与工具调用：`CommandExecutionRequestApprovalParams`、`FileChangeRequestApprovalParams`、`ToolRequestUserInputParams`。
- 文件系统与命令执行：`Fs*`、`CommandExec*`。
- 配置与账号：`Config*`、`LoginAccount*`、`GetAccount*`、`RateLimit*`。

2. 保持 wire 形状一致并可直接映射 JSON-RPC
- v2 文件普遍遵循 camelCase wire 字段（但 config 相关保留 snake_case，与 `config.toml` 键一致）。
- 判别联合在 TS 中保留 `type` 或 `method` 标签，方便客户端安全分派。

3. 对“可选/可空”语义进行显式表达
- 请求参数常用 `field?: T | null`（来源于 Rust `Option` + `#[ts(optional = nullable)]`）。
- 非 Params 类型一般不允许“可选且可空”混用（由导出测试约束）。

4. 作为协议回归基线
- `tests/schema_fixtures.rs` 会将 vendored 目录与“实时生成结果”逐文件比对，防止无意协议漂移：`codex-rs/app-server-protocol/tests/schema_fixtures.rs:11-143`。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 生成流程（Rust -> TS）

1. 协议类型定义
- v2 类型集中在 `src/protocol/v2.rs`，通过 `#[ts(export_to = "v2/")]` 导出到本目录。
- 请求/响应/通知总线定义在 `src/protocol/common.rs` 的宏中，统一声明 method 与 params/response 绑定关系：
  - `client_request_definitions!`：`codex-rs/app-server-protocol/src/protocol/common.rs:81-203`
  - `server_request_definitions!`：`codex-rs/app-server-protocol/src/protocol/common.rs:545-703`
  - `server_notification_definitions!`：`codex-rs/app-server-protocol/src/protocol/common.rs:705-777`

2. 导出与过滤
- `generate_ts_with_options` 负责导出、过滤 experimental、生成 index、补头注释、可选 prettier：`codex-rs/app-server-protocol/src/export.rs:105-182`。
- 默认 stable 导出会执行：
  - `filter_client_request_ts`（剔除 experimental method union 臂）：`.../export.rs:294-331`
  - `filter_experimental_type_fields_ts`（按字段剔除）：`.../export.rs:334-398`
  - `remove_generated_type_files`（删除 experimental 类型文件）：`.../export.rs:576-597`
- 目录索引自动生成（根与 `v2/`）：`.../export.rs:1947-2027`。

3. fixture 写盘
- `write_schema_fixtures_with_options` 会先清空 `schema/typescript` 与 `schema/json` 再重建，避免陈旧文件残留：`codex-rs/app-server-protocol/src/schema_fixtures.rs:87-109`。

### 2) 核心数据结构与协议形状

1. Thread/Turn 主模型
- `Thread` 聚合 thread 元信息、状态、可选 turns：`codex-rs/app-server-protocol/src/protocol/v2.rs:3472-3512`。
- `Turn` 承载 `items/status/error`：`.../v2.rs:3580-3592`。
- `ThreadStatus` 使用判别联合 `type`（`notLoaded|idle|systemError|active`）：`.../v2.rs:3022-3035`，对应生成 `ThreadStatus.ts`。

2. 命令执行协议
- `CommandExecParams` 定义了 `tty`、流式 stdin/stdout、超时、输出截断、sandbox_policy 等执行控制面：`.../v2.rs:2286-2360`。
- 该结构在 TS 中成为复杂可选参数对象：`codex-rs/app-server-protocol/schema/typescript/v2/CommandExecParams.ts:1-97`。

3. 审批协议
- `CommandExecutionRequestApprovalParams` 同时覆盖 approvalId、network context、command actions、proposed amendments 等：`.../v2.rs:5019-5079`。
- 其 `additional_permissions`、`skill_metadata`、`available_decisions` 带 experimental 标注。

4. 配置协议（snake_case 特例）
- `Config`/`ProfileV2` 等保留 snake_case 字段以贴合 config key：`.../v2.rs:588-727`。
- 生成后的 `Config.ts` 维持 snake_case（例如 `approval_policy`、`model_reasoning_effort`）：`codex-rs/app-server-protocol/schema/typescript/v2/Config.ts:1-23`。

5. TS 类型细节
- `i64/u64` 在不同场景会映射为 `number` 或 `bigint`（取决于 Rust 侧 `#[ts(type=...)]` 是否覆盖）：
  - `Thread.created_at/updated_at` 被显式指定为 `number`：`.../v2.rs:3484-3488`
  - `Config.model_context_window` 保持 `bigint`：`.../schema/typescript/v2/Config.ts:19`
- 动态 JSON 内容通过 `../serde_json/JsonValue` 递归联合接入，v2 中高频引用。

### 3) 命令/脚本链路

1. 维护命令
- `just write-app-server-schema` -> `cargo run -p codex-app-server-protocol --bin write_schema_fixtures -- "$@"`：`justfile:82-83`。
- CLI 导出命令：
  - `codex app-server generate-ts --out DIR [--experimental]`
  - `codex app-server generate-json-schema --out DIR [--experimental]`
  - 实现：`codex-rs/cli/src/main.rs:655-678`

2. README 约束
- README 明确 stable 默认、`--experimental` 可选，以及维护者新增 experimental 字段/方法时的流程：`codex-rs/app-server/README.md:1347-1459`。

### 4) 测试与一致性保障

1. fixture 一致性测试
- `typescript_schema_fixtures_match_generated`：`codex-rs/app-server-protocol/tests/schema_fixtures.rs:11-21`。

2. 导出器细粒度测试
- 限制 `?: T | null` 仅出现在 Params 等允许场景：`codex-rs/app-server-protocol/src/export.rs:2042-2260`。
- 验证 stable 过滤确实去掉 mock experimental 方法/字段：`.../export.rs:2275-2333`, `2679-2747`。

## 关键代码路径与文件引用

1. 目标目录本体
- `codex-rs/app-server-protocol/schema/typescript/v2/index.ts`
- `codex-rs/app-server-protocol/schema/typescript/v2/Thread.ts`
- `codex-rs/app-server-protocol/schema/typescript/v2/ThreadItem.ts`
- `codex-rs/app-server-protocol/schema/typescript/v2/TurnStartParams.ts`
- `codex-rs/app-server-protocol/schema/typescript/v2/CommandExecParams.ts`
- `codex-rs/app-server-protocol/schema/typescript/v2/CommandExecutionRequestApprovalParams.ts`
- `codex-rs/app-server-protocol/schema/typescript/v2/Config.ts`
- `codex-rs/app-server-protocol/schema/typescript/v2/ConfigReadResponse.ts`
- `codex-rs/app-server-protocol/schema/typescript/v2/ToolRequestUserInputParams.ts`

2. 上游定义（被调用方）
- `codex-rs/app-server-protocol/src/protocol/v2.rs:2286-2360`
- `codex-rs/app-server-protocol/src/protocol/v2.rs:2450-2508`
- `codex-rs/app-server-protocol/src/protocol/v2.rs:3022-3035`
- `codex-rs/app-server-protocol/src/protocol/v2.rs:3472-3512`
- `codex-rs/app-server-protocol/src/protocol/v2.rs:3822-3879`
- `codex-rs/app-server-protocol/src/protocol/v2.rs:5019-5088`
- `codex-rs/app-server-protocol/src/protocol/v2.rs:5690-5714`

3. 生成与过滤链路
- `codex-rs/app-server-protocol/src/export.rs:105-182`
- `codex-rs/app-server-protocol/src/export.rs:246-398`
- `codex-rs/app-server-protocol/src/export.rs:1947-2027`
- `codex-rs/app-server-protocol/src/schema_fixtures.rs:87-109`
- `codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs:6-37`

4. 调用方与协议总线
- `codex-rs/app-server-protocol/schema/typescript/ClientRequest.ts:7-64`
- `codex-rs/app-server-protocol/schema/typescript/ServerRequest.ts:7-18`
- `codex-rs/app-server-protocol/schema/typescript/ServerNotification.ts:6-59`
- `codex-rs/app-server-protocol/src/protocol/common.rs:81-203`
- `codex-rs/app-server-protocol/src/protocol/common.rs:545-703`
- `codex-rs/app-server-protocol/src/protocol/common.rs:705-777`

5. 测试与文档
- `codex-rs/app-server-protocol/tests/schema_fixtures.rs:11-143`
- `codex-rs/app-server-protocol/src/export.rs:2042-2260`
- `codex-rs/app-server-protocol/src/export.rs:2275-2333`
- `codex-rs/app-server/README.md:1347-1459`

## 依赖与外部交互

1. Rust 依赖（生成侧）
- `ts-rs` 负责 TS 导出；`serde`/`schemars`/`serde_json` 负责序列化与 JSON schema 支撑：`codex-rs/app-server-protocol/Cargo.toml:13-39`。

2. 构建系统
- Bazel 将 `schema/**` 作为测试数据打包，确保 runfiles 环境下 fixture 测试可读：`codex-rs/app-server-protocol/BUILD.bazel:1-7`。

3. CLI 与脚本调用方
- CLI 子命令直接调用协议导出函数：`codex-rs/cli/src/main.rs:655-678`。
- 仓库脚本入口：`justfile:82-83`。

4. 与运行时 experimental 协商的外部交互
- 初始化时记录 `experimental_api_enabled`：`codex-rs/app-server/src/message_processor.rs:533-545`。
- 若请求含 experimental reason 且未 opt-in，则拒绝：`.../message_processor.rs:616-625`。
- 某些 server->client payload 出站前还会额外 strip experimental 字段：
  - transport 过滤：`codex-rs/app-server/src/transport.rs:660-681`
  - 当前硬编码 strip 点：`codex-rs/app-server-protocol/src/protocol/v2.rs:5081-5088`

5. 文档与 SDK 交互边界
- README 对生成命令与 opt-in 语义有完整说明：`codex-rs/app-server/README.md:1354-1459`。
- Python SDK 当前主要消费 JSON bundle（`codex_app_server_protocol.v2.schemas.json`），并非直接消费 TS v2 目录：`sdk/python/scripts/update_sdk_artifacts.py:33-41`。

## 风险、边界与改进建议

### 风险

1. 大规模生成文件导致审阅噪音高
- `v2` 目录 332 文件，协议微调经常触发多文件联动 diff，PR 语义审阅成本高。

2. experimental 过滤含文本后处理，存在格式敏感风险
- `filter_client_request_ts_contents` 与字段过滤依赖字符串扫描/剪裁，若 ts-rs 输出样式变化，存在误删或漏删风险：`codex-rs/app-server-protocol/src/export.rs:308-398`。

3. 数值类型跨语言语义不一致风险
- 同为 Rust 整型，TS 可能出现 `number` 与 `bigint` 混用（例如 `Thread` vs `Config`），客户端若未统一处理可能出错。

4. 运行时剥离策略局部硬编码
- `strip_experimental_fields` 目前仅处理少数字段，代码中已标注 TODO，未来扩展时容易漏：`.../v2.rs:5083-5088`。

### 边界

1. 本目录是生成产物，不应手工改业务逻辑。
2. 真正协议语义源头在 `src/protocol/v2.rs` 与 `src/protocol/common.rs`。
3. 是否可使用 experimental 能力最终由运行时连接初始化协商决定，不仅由 schema 文件决定。

### 改进建议

1. 增加“协议语义摘要”产物
- 在 `write-app-server-schema` 后自动生成 method/field 级变更摘要（新增/删除/重命名），降低审阅成本。

2. 强化 TS 过滤器鲁棒性测试
- 为字符串过滤逻辑补充更多 ts-rs 输出变体 fixture，覆盖注释、联合、交叉类型、泛型场景。

3. 统一 experimental 出站剥离机制
- 从 payload 内手工 `strip_*` 迁移到通用 trait/visitor 层，减少漏改风险。

4. 补充消费方指南
- 在 README 增补 `number/bigint`、snake_case config、stable vs experimental 的 TS 客户端实践建议，减少三方接入误解。
