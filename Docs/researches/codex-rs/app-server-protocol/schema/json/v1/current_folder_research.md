# codex-rs/app-server-protocol/schema/json/v1 研究

## 场景与职责

`codex-rs/app-server-protocol/schema/json/v1` 是 app-server 协议 JSON Schema 的“兼容层目录”，当前仅保留两个初始化相关 schema：

- `InitializeParams.json`
- `InitializeResponse.json`

这两个文件用于描述每个连接的握手契约（`initialize` 请求与响应），是所有后续 API 调用（尤其 v2 方法）之前的前置协商步骤。运行时约束是：

- 未初始化时调用其他方法会返回 `Not initialized`。
- 同一连接重复初始化会返回 `Already initialized`。

对应逻辑在 `codex-rs/app-server/src/message_processor.rs:512-613`。

目录职责边界非常清晰：

- 它不是完整 v1 API 集合。
- 它是“v1 命名空间下允许继续对外暴露的最小子集”。
- 完整协议 schema 仍由根目录 bundle 提供（`codex_app_server_protocol.schemas.json` 与 `codex_app_server_protocol.v2.schemas.json`）。

## 功能点目的

### 1. 建立连接级能力协商入口

`InitializeParams.json` 描述客户端在握手时声明身份与能力：

- `clientInfo`（必填）：`name/version` 必填，`title` 可空。
- `capabilities`（可空）：
  - `experimentalApi: boolean`（默认 `false`）
  - `optOutNotificationMethods: string[] | null`

见 `codex-rs/app-server-protocol/schema/json/v1/InitializeParams.json:1-67`。

### 2. 返回服务器运行时身份信息

`InitializeResponse.json` 描述服务端返回：

- `userAgent`
- `platformFamily`
- `platformOs`

均为必填，见 `codex-rs/app-server-protocol/schema/json/v1/InitializeResponse.json:1-23`。

### 3. 为实验能力和通知过滤提供协商输入

这两个字段直接驱动运行时行为：

- `experimentalApi` 控制实验方法/字段能否访问。
- `optOutNotificationMethods` 控制连接级通知抑制（精确匹配）。

见：

- `codex-rs/app-server/src/message_processor.rs:533-545,616-625`
- `codex-rs/app-server/src/transport.rs:583-611`
- `codex-rs/app-server/README.md:80,804`

## 具体技术实现（关键流程/数据结构/协议/命令）

### 一、数据结构来源（Rust 类型 -> JSON Schema）

`v1` 目录中的两个 schema 由 Rust 类型生成，不是手写：

- `InitializeParams` / `InitializeCapabilities` / `InitializeResponse` 定义于
  `codex-rs/app-server-protocol/src/protocol/v1.rs:28-65`
- 通过 `serde(rename_all = "camelCase")` 映射为 wire 字段名。

其中：

- `InitializeParams.capabilities` 是 `Option<InitializeCapabilities>`，因此 schema 侧表现为可空引用（`anyOf: [ref, null]`）。
- `InitializeCapabilities.experimental_api` 带 `#[serde(default)]`，对应 schema 里 default=false。

### 二、生成流程（schema 导出主链路）

导出主入口：

1. `generate_json_with_experimental(...)` 收集各类 schema（请求/响应/通知）
   - `codex-rs/app-server-protocol/src/export.rs:195-221`
2. 针对 `in_v1_dir` 项执行 allowlist 保留：
   - `schemas.retain(|schema| !schema.in_v1_dir || JSON_V1_ALLOWLIST.contains(...))`
   - `codex-rs/app-server-protocol/src/export.rs:223`
3. 写出 bundle：
   - `codex_app_server_protocol.schemas.json`
   - `codex_app_server_protocol.v2.schemas.json`
   - `codex-rs/app-server-protocol/src/export.rs:229-237`

关键限制常量：

- `JSON_V1_ALLOWLIST = ["InitializeParams", "InitializeResponse"]`
- `codex-rs/app-server-protocol/src/export.rs:41`

在单文件写出阶段：

- `write_json_schema_with_return(...)` 通过 `split_namespace("v1::Type")` 决定输出路径 `json/v1/Type.json`。
- `include_in_json_codegen` 仅允许 v1 命名空间中的 allowlist 类型真正落盘。
- `codex-rs/app-server-protocol/src/export.rs:1278-1323`

这解释了为何 `schema/json/v1` 当前只有两个文件。

### 三、运行时协议流程（initialize 握手）

请求侧（客户端）：

- `ClientRequest::Initialize` 是 `ClientRequest` 联合类型中的首个请求变体。
- `codex-rs/app-server-protocol/src/protocol/common.rs:205-208`

服务端处理（app-server）：

1. 收到 `initialize`：验证是否重复初始化。
2. 解析 `capabilities`，写入连接会话状态：
   - `experimental_api_enabled`
   - `opted_out_notification_methods`
3. 设置 originator / user-agent 后缀，构造 `InitializeResponse` 返回。
4. 标记连接为 initialized。

见 `codex-rs/app-server/src/message_processor.rs:512-603`。

初始化后行为：

- 若请求包含实验能力但连接未开启 `experimentalApi`，返回错误：
  `"<descriptor> requires experimentalApi capability"`
- 见 `codex-rs/app-server/src/message_processor.rs:616-625` 与文档 `codex-rs/app-server/README.md:1400`

通知过滤：

- 传输层按 `opted_out_notification_methods` 精确匹配 method 并跳过发送。
- `codex-rs/app-server/src/transport.rs:583-611`

### 四、调用与被调用关系

上游（谁构造/发送 InitializeParams）：

- in-process client 参数组装：`codex-rs/app-server-client/src/lib.rs:228-247`
- remote websocket client 参数组装：`codex-rs/app-server-client/src/remote.rs:66-85`
- debug client 也显式发送 initialize：`codex-rs/debug-client/src/client.rs:94-113`

中游（谁消费）：

- app-server 消费 `ClientRequest::Initialize` 并返回 `InitializeResponse`：
  `codex-rs/app-server/src/message_processor.rs:512-590`

下游（谁使用协商结果）：

- 连接状态中的实验开关用于后续请求 gate：`message_processor.rs:616-625`
- 连接状态中的 opt-out 方法用于 outbound 过滤：`transport.rs:597-609`
- in-process runtime 会将会话态同步到 outbound state：
  `codex-rs/app-server/src/in_process.rs:439-453`

### 五、相关命令与脚本

生成/刷新 schema fixtures：

- `just write-app-server-schema`
- `just write-app-server-schema --experimental`
- recipe 在 `justfile:82-83`
- 实际入口二进制：
  `codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs:1-41`

按 README 导出到任意目录（运行时命令）：

- `codex app-server generate-json-schema --out DIR`
- `codex app-server generate-ts --out DIR`
- 见 `codex-rs/app-server/README.md:44-53`

## 关键代码路径与文件引用

### 目标目录与文件

- `codex-rs/app-server-protocol/schema/json/v1/InitializeParams.json`
- `codex-rs/app-server-protocol/schema/json/v1/InitializeResponse.json`

### 协议类型定义

- `codex-rs/app-server-protocol/src/protocol/v1.rs:28-65`
- `codex-rs/app-server-protocol/src/protocol/common.rs:205-208`

### schema 导出与 v1 裁剪

- `codex-rs/app-server-protocol/src/export.rs:41`
- `codex-rs/app-server-protocol/src/export.rs:195-223`
- `codex-rs/app-server-protocol/src/export.rs:1278-1323`

### 运行时消费与行为

- `codex-rs/app-server/src/message_processor.rs:512-625`
- `codex-rs/app-server/src/transport.rs:583-611`
- `codex-rs/app-server/src/in_process.rs:349-367`
- `codex-rs/app-server/src/in_process.rs:439-453`

### 测试与夹具

- 协议序列化测试：
  - `codex-rs/app-server-protocol/src/protocol/common.rs:995-1079`
- schema fixture 一致性测试：
  - `codex-rs/app-server-protocol/tests/schema_fixtures.rs:11-143`
- app-server 初始化行为测试：
  - `codex-rs/app-server/tests/suite/v2/initialize.rs:29-194`
- Bazel 将 schema 作为测试资源：
  - `codex-rs/app-server-protocol/BUILD.bazel:6`

### 文档

- 初始化与能力协商：`codex-rs/app-server/README.md:67-123`
- 通知 opt-out：`codex-rs/app-server/README.md:804-833`
- 实验 API opt-in：`codex-rs/app-server/README.md:1369-1413`
- 维护者 regenerate 指南：`codex-rs/app-server/README.md:1450-1455`

## 依赖与外部交互

### 内部 crate 依赖

- `codex-app-server-protocol`：提供类型和 schema 导出。
- `codex-app-server`：消费 `InitializeParams`，产出 `InitializeResponse`。
- `codex-app-server-client` / `debug-client` / `app-server-test-client`：发起 initialize。

### 协议/标准

- JSON-RPC 2.0（wire envelope）
- JSON Schema draft-07（`$schema` 字段）

### 外部行为接口

- `clientInfo.name` 参与 originator / user-agent 行为链路（用于上游识别与日志归因语义，README 有明确说明）。
- `platformFamily` / `platformOs` 暴露运行目标平台信息（`std::env::consts`）。

### 构建与工具链交互

- `just write-app-server-schema` 调用 `codex-app-server-protocol` 的写夹具二进制。
- 测试通过 fixture 比对防止 schema 漂移（包括 `json/v1` 文件集合变化）。

## 风险、边界与改进建议

### 风险与边界

1. v1 保留策略为硬编码字符串 allowlist
- `JSON_V1_ALLOWLIST` 采用字面量列表，新增/迁移时容易出现“类型已定义但未导出到 v1 目录”的人为遗漏。

2. v1 目录语义容易被误读为“完整 v1 协议”
- 实际仅含 initialize 两个 schema，其他历史 v1 方法已不在该目录单文件暴露；消费者若按目录推断完整 API 会踩坑。

3. `optOutNotificationMethods` 为精确匹配
- 无通配符/前缀能力，客户端若写错 method 字符串会静默无效（README 标注 unknown 会忽略）。

4. 实验能力开关当前按连接维度管理
- 代码中已有 TODO 指出多客户端共享线程时可能产生体验不一致。

### 改进建议

1. 增加“v1 目录文件集”专门回归测试
- 在 `app-server-protocol` 增加断言：`schema/json/v1` 文件集合恒为 `{InitializeParams.json, InitializeResponse.json}`，提高重构安全性。

2. 在 schema 根目录增加简短 `README` 或 manifest
- 明确 `json/v1` 是兼容层最小集，避免外部消费者误判目录语义。

3. 将 allowlist 提升为带注释的结构化配置
- 例如为每个条目标注“保留原因/兼容方”，降低后续维护成本。

4. 在 `InitializeParams.json` 增补兼容提示（描述层）
- 对 `capabilities` 的默认语义（省略等价于 `experimentalApi=false`）可在 schema 描述中直接体现，减少多端实现歧义。

