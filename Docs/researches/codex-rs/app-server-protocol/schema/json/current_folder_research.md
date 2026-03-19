# DIR `codex-rs/app-server-protocol/schema/json` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/json`
- 研究日期：2026-03-19
- 目录现状（当前仓库）：
  - 总文件数：`187`
  - `v1/`：`2`（仅 `InitializeParams`、`InitializeResponse`）
  - `v2/`：`150`
  - 根层：JSON-RPC/请求通知/审批相关 schema + 两个 bundle（`codex_app_server_protocol.schemas.json`、`codex_app_server_protocol.v2.schemas.json`）

## 场景与职责

`schema/json` 是 `codex-app-server-protocol` 的“JSON Schema 发布面（vendored fixtures）”，本质是协议代码的可分发快照，不是手写业务逻辑目录。

它在系统中的职责分为四层：

1. 协议契约发布层
- 对外输出 JSON Schema，覆盖 JSON-RPC 信封、Client/Server 请求与通知、v1 初始化兼容对象、v2 主线对象。
- 产物示例：
  - `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.schemas.json`
  - `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`
  - `codex-rs/app-server-protocol/schema/json/ClientRequest.json`
  - `codex-rs/app-server-protocol/schema/json/v2/ThreadStartParams.json`

2. 回归基线层（fixture）
- 该目录作为 golden fixtures 被测试直接对比，保证“协议代码 -> 产物”可重现且无漂移。
- 对比入口：`codex-rs/app-server-protocol/tests/schema_fixtures.rs:23-49`。

3. 多消费者共享输入层
- Rust CLI 子命令可直接生成 schema 到外部目录（工具链场景）。
- Python SDK 生成脚本直接消费 `codex_app_server_protocol.v2.schemas.json` 进行 Pydantic 代码生成。

4. 稳定/实验 API 边界产物层
- 默认产物为稳定面（实验方法与字段会被过滤）。
- 使用 `--experimental` 时可生成包含实验面的完整 schema 产物。

## 功能点目的

1. 为 app-server 客户端提供 machine-readable 协议定义
- 让非 Rust 客户端（尤其 Python）基于 JSON Schema 自动生成强类型模型，避免手写协议层。

2. 维护 v1 兼容最小面 + v2 主线面
- 通过 `JSON_V1_ALLOWLIST` 将 v1 JSON 输出收敛在初始化能力，减少历史接口继续扩散。
- 关键常量：`codex-rs/app-server-protocol/src/export.rs:41`。

3. 提供两种 bundle 以适配不同生成器
- mixed bundle：`codex_app_server_protocol.schemas.json`，保留根 definitions + `definitions.v2` 命名空间。
- flat v2 bundle：`codex_app_server_protocol.v2.schemas.json`，把 v2 flatten 到根 definitions，专门兼容 datamodel-code-generator 一层 definitions 的扫描行为。
- 设计入口：`build_flat_v2_schema`（`codex-rs/app-server-protocol/src/export.rs:1041`）。

4. 通过 fixture 测试确保提交产物与代码一致
- 若文件集或内容不一致，测试会直接提示执行 `just write-app-server-schema`。
- 断言位置：`codex-rs/app-server-protocol/tests/schema_fixtures.rs:67-101`。

5. 控制大文件纳入仓库的治理边界
- 两个 bundle 被显式列入 blob 大文件白名单，说明其“体积大但受控”。
- 白名单：`.github/blob-size-allowlist.txt:6-7`。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 生成流程（从协议类型到 `schema/json`）

1. 命令入口
- `just write-app-server-schema` -> `cargo run -p codex-app-server-protocol --bin write_schema_fixtures -- "$@"`
- 定义：`justfile:81-83`。

2. 二进制入口参数
- `--schema-root`、`--prettier`、`--experimental`。
- 文件：`codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs:6-20`。

3. 目录重建
- `write_schema_fixtures_with_options` 先清空 `schema/typescript` 与 `schema/json`，再分别调用 TS 和 JSON 生成。
- 文件：`codex-rs/app-server-protocol/src/schema_fixtures.rs:87-107`。

4. JSON 输出总入口
- `generate_json_with_experimental(out_dir, experimental_api)`。
- 文件：`codex-rs/app-server-protocol/src/export.rs:195`。

5. 生成内容
- 先写根层信封 schema（`RequestId`、`JSONRPC*`、`ClientRequest`、`ServerRequest`、`ClientNotification`、`ServerNotification`）。
- 再导出 params/response/notification 对象 schema。
- 之后构建：
  - `codex_app_server_protocol.schemas.json`
  - `codex_app_server_protocol.v2.schemas.json`
- 关键代码：`codex-rs/app-server-protocol/src/export.rs:198-235`。

### 2) mixed bundle 与 flat v2 bundle 机制

1. mixed bundle
- `build_schema_bundle` 做 definitions 聚合、命名空间组织和 `$ref` 重写。
- 入口：`codex-rs/app-server-protocol/src/export.rs:946`。
- 关键动作：
  - `rewrite_refs_to_known_namespaces` 修复 root helper 对 namespaced 类型的引用。
  - 文件：`codex-rs/app-server-protocol/src/export.rs:1542`。

2. flat v2 bundle
- `build_flat_v2_schema` 将 `definitions.v2` 拉平到根 definitions。
- 入口：`codex-rs/app-server-protocol/src/export.rs:1041`。
- 保留共享 root 定义：`FLAT_V2_SHARED_DEFINITIONS = ["ClientRequest", "ServerNotification"]`（`export.rs:48`），防止合法请求/通知变体丢失。
- 完整性保障：
  - `ensure_no_ref_prefix(..., "#/definitions/v2/")`
  - `ensure_referenced_definitions_present(...)`
  - 位置：`export.rs:1086-1088`、`1187`。

### 3) 稳定面过滤（experimental off）

1. JSON 文件后处理
- `filter_experimental_json_files` 逐文件读取、过滤实验字段/方法、回写 prettified JSON。
- 文件：`codex-rs/app-server-protocol/src/export.rs:545-553`。

2. 实验方法类型删除
- 通过 `EXPERIMENTAL_CLIENT_METHOD_PARAM_TYPES` + `EXPERIMENTAL_CLIENT_METHOD_RESPONSE_TYPES` 汇总类型名，再删除对应 json 文件。
- 关键函数：`experimental_method_types`（`export.rs:556`）、`remove_generated_type_files`（`export.rs:576`）。
- 方法/类型来源：`codex-rs/app-server-protocol/src/protocol/common.rs:150-160`。

3. v1 输出收敛
- `JSON_V1_ALLOWLIST = ["InitializeParams", "InitializeResponse"]`。
- 过滤点：`codex-rs/app-server-protocol/src/export.rs:223`、`1285`。

### 4) 协议类型来源与数据结构

1. 总线类型来源
- `client_request_definitions!` 宏生成 `ClientRequest` 和导出函数/实验方法清单。
- 宏入口：`codex-rs/app-server-protocol/src/protocol/common.rs:85`。

2. v2 主线示例
- `thread/start`、`thread/resume`、`turn/start` 等 request 方法映射来自 `common.rs`。
- 例如：`ThreadStart`（`common.rs:214`）、`TurnStart`（`common.rs:351`）。

3. 字段命名与 wire 协议
- v2 结构主要使用 camelCase 序列化（`serde(rename_all = "camelCase")`），最终体现在 JSON schema 属性名中。

### 5) 调用方/被调用方/配置/测试/脚本/文档一体链路

1. 调用方（谁触发生成）
- `just write-app-server-schema`（`justfile:81-83`）
- CLI 子命令：
  - `codex app-server generate-ts`
  - `codex app-server generate-json-schema`
- CLI 对应调用：`codex-rs/cli/src/main.rs:655-676`。

2. 被调用方（谁实现生成）
- `write_schema_fixtures_with_options` -> `generate_json_with_experimental`。
- 核心在 `codex-rs/app-server-protocol/src/schema_fixtures.rs` 与 `src/export.rs`。

3. 配置项
- 生成配置：`--experimental`、`--schema-root`、`--prettier`（`write_schema_fixtures.rs:10-19`）。
- 运行时协商配置：`initialize.capabilities.experimentalApi`（文档说明 `app-server/README.md:1408-1452`）。

4. 测试
- fixture 回归：`codex-rs/app-server-protocol/tests/schema_fixtures.rs:11-143`。
- 生成逻辑单测：`src/export.rs` 内含针对 bundle flatten、experimental 过滤等测试（如 `build_flat_v2_schema_keeps_shared_root_schemas_and_dependencies`，`export.rs:2418`）。

5. 脚本
- Python SDK 生成脚本直接读取：
  - `schema_bundle_path()` -> `.../schema/json/codex_app_server_protocol.v2.schemas.json`（`sdk/python/scripts/update_sdk_artifacts.py:33-40`）。
  - `generate_v2_all()` 调 `datamodel_code_generator`（`update_sdk_artifacts.py:412-451`）。
  - `generate_notification_registry()` 读取 `ServerNotification.json`（`update_sdk_artifacts.py:458-505`）。

6. 文档
- app-server 维护说明包含：生成命令、experimental 维护流程、再生 fixture 要求。
- 位置：`codex-rs/app-server/README.md:50-54`、`1360-1365`、`1408-1452`。
- Python SDK README 明确 `generate-types` 流程依赖该 schema：`sdk/python/README.md:69-75`。

## 关键代码路径与文件引用

### A. 目标目录（本次研究对象）
- `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.schemas.json`
- `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`
- `codex-rs/app-server-protocol/schema/json/ClientRequest.json`
- `codex-rs/app-server-protocol/schema/json/ServerNotification.json`
- `codex-rs/app-server-protocol/schema/json/v1/InitializeParams.json`
- `codex-rs/app-server-protocol/schema/json/v1/InitializeResponse.json`
- `codex-rs/app-server-protocol/schema/json/v2/ThreadStartParams.json`

### B. 生成实现（核心被调用方）
- `codex-rs/app-server-protocol/src/schema_fixtures.rs:78-109`
- `codex-rs/app-server-protocol/src/export.rs:195-241`
- `codex-rs/app-server-protocol/src/export.rs:545-553`
- `codex-rs/app-server-protocol/src/export.rs:946-1088`
- `codex-rs/app-server-protocol/src/export.rs:1278-1323`
- `codex-rs/app-server-protocol/src/export.rs:1542-1566`

### C. 协议来源（上游定义）
- `codex-rs/app-server-protocol/src/protocol/common.rs:85-203`
- `codex-rs/app-server-protocol/src/protocol/common.rs:214-432`

### D. 调用方与工具链
- `justfile:81-83`
- `codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs:6-42`
- `codex-rs/cli/src/main.rs:655-676`

### E. 测试与打包
- `codex-rs/app-server-protocol/tests/schema_fixtures.rs:11-143`
- `codex-rs/app-server-protocol/BUILD.bazel:3-7`
- `.github/blob-size-allowlist.txt:6-7`

### F. 外部消费者（Python SDK）
- `sdk/python/scripts/update_sdk_artifacts.py:33-44`
- `sdk/python/scripts/update_sdk_artifacts.py:412-451`
- `sdk/python/scripts/update_sdk_artifacts.py:458-505`
- `sdk/python/tests/test_artifact_workflow_and_binaries.py:44-111`

## 依赖与外部交互

1. Rust 依赖
- schema 生成依赖 `schemars`、`serde_json`、`ts-rs`（定义于 `codex-rs/app-server-protocol/Cargo.toml`）。
- 测试依赖 `codex-utils-cargo-bin` 解决 Bazel runfiles 路径解析（`tests/schema_fixtures.rs:107-133`）。

2. 构建系统交互
- Bazel 为该 crate 注入 `schema/**` 作为测试数据（`BUILD.bazel:6`），保证测试在 runfiles 下可访问 fixtures。

3. CLI/命令行交互
- 面向开发者两类路径：
  - 仓库维护：`just write-app-server-schema`
  - 对外导出：`codex app-server generate-json-schema --out DIR [--experimental]`

4. Python 工具链交互
- `datamodel_code_generator` 基于 `v2.schemas.json` 生成 `sdk/python/src/codex_app_server/generated/v2_all.py`。
- 脚本还从 `ServerNotification.json` 抽取 method->model 映射，生成 `notification_registry.py`。

5. 文档契约交互
- app-server README 把 experimentalApi 协商与 schema 导出流程写成维护规约；schema/json 是该规约的落地产物。

## 风险、边界与改进建议

### 风险

1. 大体量产物 diff 可读性差
- `schema/json` 文件多且 bundle 大，PR 中很难人工识别“语义变更”与“生成器噪音”。

2. 双 bundle 维护复杂度高
- mixed 与 flat v2 的 `$ref` 重写和依赖闭包计算容易引入隐性缺失（尤其 codegen 端才暴露）。

3. experimental 过滤链路跨多处
- 方法/字段标注在 `common.rs`/`v2.rs`，过滤在 `export.rs`，运行时协商在 app-server；链路长，容易漏同步。

4. 外部生成器行为漂移
- `datamodel_code_generator` 或 formatter 行为升级时，可能触发大规模再生变更，影响稳定性。

### 边界

1. 本目录为生成产物，原则上不手工编辑。
2. 默认稳定面不代表“无 v1 内容”，而是保留最小初始化兼容面。
3. `v2.schemas.json` 主要为生成器友好而设计，不等同于完整 mixed 语义视图。

### 改进建议

1. 增加 schema 语义变更摘要
- 在生成后输出“新增/删除 method、字段、definition”的结构化报告，降低审阅成本。

2. 将 flat v2 校验前移为独立测试门禁
- 对 `ensure_referenced_definitions_present` 的失败提供更可读的缺失路径，减少排障时间。

3. 对 Python 生成链路增加契约 smoke test
- 除现有脚本单测外，增加最小 round-trip 序列化测试，验证关键请求/通知模型可正确编码回 camelCase。

4. 引入按域分组的 schema 索引
- 在 `schema/json` 增加自动生成的目录索引（例如 thread/turn/account/config），便于维护者快速定位影响面。
