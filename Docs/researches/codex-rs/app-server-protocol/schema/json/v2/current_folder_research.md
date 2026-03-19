# DIR `codex-rs/app-server-protocol/schema/json/v2` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/json/v2`
- 研究日期：2026-03-19
- 目录现状（当前仓库）：
  - 文件总数：`150`
  - `*Params.json`：`50`
  - `*Response.json`：`53`
  - `*Notification.json`：`47`
  - 按领域粗分：`Thread(40)`、`Turn(10)`、`Fs(14)`、`CommandExec/Terminal(11)`、`Config(11)`、`Account(14)`、`Plugin(8)`、`Skills(5)`、`Mcp(4)`、`Other(33)`

## 场景与职责

`schema/json/v2` 是 app-server v2 协议的“单类型 JSON Schema 落盘层”，它不是手写协议定义目录，而是由 Rust 协议类型自动导出的可发布工件（fixture）。

它在系统中的职责是：

1. 对外提供 v2 每个请求/响应/通知类型的独立 JSON Schema 文件
- 示例：`ThreadStartParams.json`、`TurnStartResponse.json`、`CommandExecOutputDeltaNotification.json`。
- 这些文件反映 wire 层字段名、可空性、枚举值、`oneOf/anyOf` 结构、默认值等约束。

2. 作为仓库内“协议快照基线”
- `codex-rs/app-server-protocol/tests/schema_fixtures.rs` 会把新生成树与仓库中的 `schema/json` 做逐文件集合+内容比对，不一致即失败并提示 `just write-app-server-schema`。

3. 作为 bundle 构建输入的一部分
- 同一次导出会并行产出两份总 bundle：
  - `codex_app_server_protocol.schemas.json`（mixed）
  - `codex_app_server_protocol.v2.schemas.json`（flat v2）
- `schema/json/v2/*.json` 是“单文件粒度视图”；bundle 是“聚合分发视图”。

4. 承接“稳定面默认输出”的过滤结果
- 默认不带 `--experimental` 时，experimental 方法/字段会被裁剪后再落盘到此目录。
- 这使目录内容成为“稳定协议面”主参考，但存在少量边界（见风险章节）。

## 功能点目的

1. 让客户端/工具按类型消费 schema
- 某些集成并不需要整包 bundle，而是按对象文件做局部校验或文档生成（例如只关心 `Thread*` 或 `CommandExec*`）。

2. 保持 v2 协议演进可审计
- 每个类型独立文件的 diff 可直接审阅字段变化，比只看大 bundle 更可读。

3. 为多端语言生态提供稳定中间层
- Rust 类型是源，`schema/json/v2` 是中间分发层，随后被 CLI、SDK 代码生成脚本与测试消费。

4. 支撑 app-server 文档与行为一致性
- `app-server/README.md` 描述的方法与事件（如 `thread/start`、`turn/start`、`command/exec/outputDelta`）在本目录对应到具体 params/response/notification schema。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 生成入口与目录重建

1. 命令入口
- `just write-app-server-schema` -> `cargo run -p codex-app-server-protocol --bin write_schema_fixtures -- "$@"`
- 位置：`justfile:81-83`

2. CLI 二进制参数
- `--schema-root`、`--prettier`、`--experimental`
- 位置：`codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs:6-20`

3. 目录重建策略
- `write_schema_fixtures_with_options` 先清空 `schema/typescript`、`schema/json`，再重新生成。
- 位置：`codex-rs/app-server-protocol/src/schema_fixtures.rs:87-107`

### 2) v2 文件如何落盘到 `schema/json/v2`

1. 统一 JSON 导出入口
- `generate_json_with_experimental(out_dir, experimental_api)`
- 位置：`codex-rs/app-server-protocol/src/export.rs:195-244`

2. 先导出信封与总线，再导出 params/response/notification 类型
- `RequestId/JSONRPC*/ClientRequest/ServerRequest/ClientNotification/ServerNotification`
- 然后 `export_client_param_schemas`、`export_client_response_schemas`、`export_server_param_schemas`、`export_server_response_schemas`、`export_*_notification_schemas`
- 位置：`export.rs:197-221` + `protocol/common.rs:182-201, 611-636, 687-693, 714-720`

3. 关键落盘函数：`write_json_schema_with_return`
- 通过 `split_namespace("v2::Type")` 将文件写到 `out_dir/v2/Type.json`。
- 位置：`export.rs:1278-1323, 1500-1504`

4. v1/v2 目录边界
- `JSON_V1_ALLOWLIST` 仅保留 `InitializeParams/InitializeResponse` 到 `json/v1`。
- v2 类型默认进入 `json/v2`。
- 位置：`export.rs:41, 223, 1284-1286`

### 3) 稳定面过滤（默认不带 `--experimental`）

1. bundle 级过滤
- `filter_experimental_schema`：移除 experimental 字段、裁剪 experimental 方法变体、清理方法相关类型定义。
- 位置：`export.rs:400-406`

2. 文件级过滤
- `filter_experimental_json_files` 对每个 json 文件执行过滤并覆盖写回。
- 位置：`export.rs:545-553`

3. 方法类型删除名单来源
- `EXPERIMENTAL_CLIENT_METHOD_PARAM_TYPES` / `EXPERIMENTAL_CLIENT_METHOD_RESPONSE_TYPES`
- 位置：`protocol/common.rs:155-163`

4. 方法裁剪来源
- `EXPERIMENTAL_CLIENT_METHODS`
- 位置：`protocol/common.rs:150-153`

5. 运行时能力协商对应
- 初始化后若请求命中 experimental 且连接未开启 `capabilities.experimentalApi`，返回 `<descriptor> requires experimentalApi capability`。
- 位置：`app-server/src/message_processor.rs:616-625`、`app-server/README.md:1398-1406`

### 4) 方法映射与 schema 文件命名约定

1. `ClientRequest` 方法映射来自宏
- `client_request_definitions!` 将 `thread/start` -> `v2::ThreadStartParams` / `v2::ThreadStartResponse` 等映射到导出列表。
- 位置：`protocol/common.rs:85-203, 205-541`

2. `ServerNotification` 方法映射
- `server_notification_definitions!` 绑定 method 字符串到 `v2::*Notification` payload。
- 位置：`protocol/common.rs:640-695, 874-941`

3. 目录文件名规则
- 请求：`*Params.json`
- 响应：`*Response.json`
- 通知 payload：`*Notification.json`
- 由导出函数拼接命名，不依赖人工维护。

### 5) mixed bundle 与 flat v2 bundle 的关系（与本目录强相关）

1. `build_schema_bundle`
- 把单文件 schema 聚合到 `definitions`，并处理命名空间与 `$ref` 重写。
- 位置：`export.rs:946-1027`

2. `build_flat_v2_schema`
- 从 mixed bundle 的 `definitions.v2` 拉平到根 definitions。
- 保留 `ClientRequest`、`ServerNotification` 以及其 non-v2 传递依赖，避免丢变体。
- 位置：`export.rs:48, 1041-1088`

3. 完整性防护
- `ensure_no_ref_prefix`、`ensure_referenced_definitions_present`
- 位置：`export.rs:1160-1203`

### 6) 结构特征（从目录样本观察）

1. 单文件 schema 采用 draft-07，普遍包含：
- `$schema`
- `title`
- `type`
- `properties` / `required`
- 本地 `definitions`

2. 大对象（如 `ThreadStartedNotification.json`）会内嵌大量依赖定义，导致单文件体积较大。

3. 目录中存在“文件存在但主联合体默认不引用”的对象
- 例如 `RawResponseItemCompletedNotification.json` 文件存在，但 `ServerNotification.json` 默认稳定面已剔除 `rawResponseItem/completed` 方法变体。
- 相关常量：`EXCLUDED_SERVER_NOTIFICATION_METHODS_FOR_JSON`
- 位置：`export.rs:51, 1339-1345`

## 关键代码路径与文件引用

### 目标目录
- `codex-rs/app-server-protocol/schema/json/v2/*.json`

### 生成主链路
- `codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs:6-42`
- `codex-rs/app-server-protocol/src/schema_fixtures.rs:87-109`
- `codex-rs/app-server-protocol/src/export.rs:195-244`
- `codex-rs/app-server-protocol/src/export.rs:1278-1323`

### 过滤与聚合
- `codex-rs/app-server-protocol/src/export.rs:400-406`
- `codex-rs/app-server-protocol/src/export.rs:545-553`
- `codex-rs/app-server-protocol/src/export.rs:946-1088`
- `codex-rs/app-server-protocol/src/export.rs:1542-1566`

### 方法与类型来源
- `codex-rs/app-server-protocol/src/protocol/common.rs:85-203`
- `codex-rs/app-server-protocol/src/protocol/common.rs:205-541`
- `codex-rs/app-server-protocol/src/protocol/common.rs:640-941`
- `codex-rs/app-server-protocol/src/protocol/v2.rs`（核心类型定义，当前约 7,922 行）

### 调用方 / 被调用方
- 生成调用方：
  - `justfile:81-83`
  - `codex-rs/cli/src/main.rs:655-679`
- 运行时消费方：
  - `codex-rs/app-server/src/message_processor.rs:512-625`
  - `codex-rs/app-server/src/codex_message_processor.rs:612-905`
  - `codex-rs/app-server/src/command_exec.rs:553-612`

### 测试与构建
- `codex-rs/app-server-protocol/tests/schema_fixtures.rs:23-104`
- `codex-rs/app-server-protocol/BUILD.bazel:3-7`
- `codex-rs/app-server/tests/suite/v2/*.rs`（运行时契约验证）

### 文档与脚本
- `codex-rs/app-server/README.md:50-55, 124-185, 1347-1459`
- `sdk/python/scripts/update_sdk_artifacts.py:33-41, 399-455, 458-531`
- `sdk/python/tests/test_artifact_workflow_and_binaries.py:72-150`

## 依赖与外部交互

1. Rust 内部依赖
- `schemars`：Rust 类型 -> JSON Schema
- `serde/serde_json`：序列化与 JSON 处理
- `ts-rs`：并行产出 TS 类型，和 JSON 一起作为 fixture 树

2. 协议类型外部来源
- `v2.rs` 大量类型来自 `codex_protocol` 语义层映射（`From<Core*>`），说明 `schema/json/v2` 并非孤立定义，而是“对 core 协议对象的 app-server 边界投影”。

3. 与 app-server 的运行时交互
- `ClientRequest`/`ServerNotification` 的 wire method 与 payload 由 `common.rs` 和 `v2.rs` 定义并落盘 schema。
- `message_processor` 在初始化时设置 `experimentalApi` 与通知过滤，影响实际可调用/可见面。

4. 与 Python SDK 的交互
- Python 生成器直接读取 `codex_app_server_protocol.v2.schemas.json`（flat bundle）进行 Pydantic 代码生成。
- 虽然它不直接逐个读取 `schema/json/v2/*.json`，但该目录是 bundle 构建输入与人工审阅来源。

5. 构建系统交互
- Bazel 将 `schema/**` 作为测试数据，保证 runfiles 下 fixture 对比稳定可访问。

## 风险、边界与改进建议

### 风险与边界

1. “稳定面”与“文件存在”并非完全等价
- 默认稳定导出会裁剪 experimental 方法/字段，但某些通知 payload 类型文件仍会存在（例如 realtime 通知相关 payload 文件），可能让只看目录的消费者误判可用性。

2. 单文件 schema 存在高重复定义
- 大量 `definitions` 在不同文件重复，体积和审阅噪音都高，手工 diff 成本大。

3. 目录不是唯一消费入口
- 多数自动化消费者（尤其 Python）读取的是 flat bundle，不直接读 `v2/` 单文件，若只更新本目录认知容易忽略 bundle 兼容规则。

4. experimental 过滤实现偏“约定驱动”
- 方法级删除目前依赖 `EXPERIMENTAL_CLIENT_METHODS` 与类型名列表；新增路径若漏标注/漏登记，可能出现稳定面泄露或误删。

5. 大文件治理压力
- 两个 bundle 在仓库内体积较大，虽已在 `.github/blob-size-allowlist.txt` 白名单，但长期仍会放大 PR diff 体积和审查成本。

### 改进建议

1. 为 `schema/json/v2` 增加简短 README/manifest
- 明确“目录文件集合”和“稳定可用方法集合”并不一一对应，推荐消费者以 `ClientRequest/ServerNotification` 联合体为准。

2. 增加“可达性检查”辅助脚本
- 从 `ClientRequest.json` 与 `ServerNotification.json` 出发，计算 `v2/*.json` 可达图并产出报告，区分“存在但未挂载”的类型文件。

3. 强化过滤回归测试
- 在 `app-server-protocol` 增加更直接断言：稳定导出中不应出现特定 experimental method；同时明确哪些 experimental 通知 payload 文件允许保留。

4. 降低重复定义噪音
- 为内部审阅流程补充“结构化对比工具”（按字段变化汇总），减少纯文本 JSON diff 负担。

5. 继续以 v2 为唯一新增面
- 新 API 应继续只加在 `protocol/v2.rs`，并同步 `README` 与 schema fixture，避免目录语义漂移。
