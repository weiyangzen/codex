# codex-rs/codex-experimental-api-macros 目录研究

## 研究范围
- 目标目录：`codex-rs/codex-experimental-api-macros`
- 目标对象：`src/lib.rs`（proc-macro 派生实现）
- 上下文依赖（调用方/被调用方/配置/测试/脚本/文档）覆盖：
  - 调用方：`codex-rs/app-server-protocol/src/protocol/common.rs`、`codex-rs/app-server-protocol/src/protocol/v2.rs`、`codex-rs/app-server-protocol/src/experimental_api.rs`（测试）
  - 被调用方：`syn`、`quote`、`proc_macro2`
  - 运行时消费链路：`codex-rs/app-server/src/message_processor.rs`、`codex-rs/app-server/src/transport.rs`、`codex-rs/app-server-protocol/src/export.rs`
  - 配置与能力开关：`InitializeCapabilities.experimental_api`、`GenerateTsOptions.experimental_api`、`SchemaFixtureOptions.experimental_api`
  - 测试：`app-server-protocol` 与 `app-server` 的 experimental gate/过滤测试
  - 脚本与命令：`just write-app-server-schema`、`codex app-server generate-ts --experimental`、`codex app-server generate-json-schema --experimental`
  - 文档：`codex-rs/app-server/README.md` 的 Experimental API 章节

## 场景与职责
`codex-experimental-api-macros` 是一个专用过程宏 crate，核心职责是把协议类型上的 `#[experimental(...)]` 标注编译成统一可执行逻辑，服务于两类场景：

1. 运行时请求门控（app-server 入站校验）
- 对客户端请求，自动计算是否命中 experimental 字段/方法/枚举变体。
- 未开启 `capabilities.experimentalApi` 时拒绝请求，并返回稳定错误文案。

2. 协议工件导出（TS/JSON schema 过滤）
- 自动收集 experimental 字段清单到全局注册表（`inventory`），用于 stable schema 生成时剔除字段。

该 crate 不承载业务语义（不关心 thread/turn 等具体 API），只负责“标注 -> 检测逻辑/元数据注册”的编译期生成。

## 功能点目的
### 1) `#[derive(ExperimentalApi)]` 统一生成
- 为结构体/枚举自动实现 `ExperimentalApi::experimental_reason(&self) -> Option<&'static str>`。
- 目标是让调用侧不需要手写每个类型的 experimental 判定逻辑。

### 2) 字段级标注：`#[experimental("reason")]`
- 在 struct 字段或 enum variant 上标注稳定 reason id（如 `thread/start.mockExperimentalField`）。
- 派生实现返回首个命中的 reason，用于拒绝消息和报错。

### 3) 嵌套冒泡：`#[experimental(nested)]`
- 当字段本身不是 experimental，但其内部类型可能是（例如 `Option<AskForApproval>`），通过 nested 递归检查子类型 `ExperimentalApi`。
- 目标是让“容器类型”可以透传内部实验性原因。

### 4) 字段注册：`inventory::submit!`
- 对 `#[experimental("...")]` 字段，额外生成 `ExperimentalField { type_name, field_name, reason }` 注册代码。
- 供导出阶段统一过滤 TS/JSON 中的 experimental 字段。

### 5) presence 语义
对“字段是否算被使用”有固定规则，避免把 `None`/空集合误判为启用：
- `Option<T>`：`Some(...)` 且内部值“存在”才触发；`None` 不触发。
- `Vec`/`HashMap`/`BTreeMap`：非空触发。
- `bool`：`true` 触发。
- 其他类型：只要字段存在即触发（等价恒 `true`）。

## 具体技术实现（关键流程/数据结构/协议/命令）
### A. 宏入口与 AST 分发
文件：`codex-rs/codex-experimental-api-macros/src/lib.rs`

- `derive_experimental_api` 解析 `DeriveInput` 后按数据类型分发：
  - `Data::Struct` -> `derive_for_struct`
  - `Data::Enum` -> `derive_for_enum`
  - `Data::Union` -> 直接编译错误（不支持 union）

这保证调用方只需写 `#[derive(ExperimentalApi)]`，不需要区分 struct/enum 的手工实现差异。

### B. Struct 派生展开
`derive_for_struct` 同时生成三类产物：

1. `experimental_reason` 检查链
- Named fields：按字段顺序生成 `if` 检查，命中即 `return Some(reason)`。
- Tuple fields：按索引生成检查。
- `#[experimental(nested)]` 字段会调用 `ExperimentalApi::experimental_reason(&self.field)` 递归。

2. `EXPERIMENTAL_FIELDS` 常量
- 在类型 `impl` 中注入 `pub(crate) const EXPERIMENTAL_FIELDS: &'static [ExperimentalField]`。
- 该常量在当前仓库未直接读取，但与注册列表语义保持一致，作为类型级静态元数据。

3. `inventory::submit!` 注册
- 每个 experimental 字段都会注册一条 `ExperimentalField`。
- 注册内容包含：`type_name`（Rust 类型名字符串）、`field_name`（当前实现转换为 camelCase）、`reason`。

### C. Enum 派生展开
`derive_for_enum` 为每个 variant 生成 `match` arm：
- variant 有 `#[experimental("...")]` -> `Some(reason)`
- 否则 `None`

注意：当前 enum 派生只看 variant 属性，不检查 variant 负载字段的 nested 标注。

### D. 属性解析与 presence 计算
关键函数：
- `experimental_reason_attr`：只识别 `#[experimental("...")]`（`LitStr`）
- `experimental_nested_attr`：只识别 `#[experimental(nested)]`
- `presence_expr_for_access/presence_expr_for_ref`：生成 presence 表达式

presence 规则示例：
- `Option<Option<bool>>`：仅当 `Some(Some(true))` 才触发
- `Option<Vec<T>>`：仅当 `Some(vec)` 且 `!vec.is_empty()` 才触发
- `bool`：`true` 触发

### E. 与 app-server-protocol / app-server 的端到端链路
1. 类型标注与派生（协议层）
- `app-server-protocol/src/protocol/v2.rs` 在 `ThreadStartParams`、`Config`、`TurnStartParams`、`CommandExecutionRequestApprovalParams` 等类型使用 `derive(ExperimentalApi)` 与 `#[experimental(...)]`。
- `app-server-protocol/src/protocol/common.rs`：
  - `client_request_definitions!` 用 `inspect_params: true` 在“方法稳定、字段实验性”时下探 params。
  - `ServerNotification` 直接 `derive(ExperimentalApi)`，支持通知级 experimental 原因提取。

2. 运行时门控（请求）
- `app-server/src/message_processor.rs`：若 `codex_request.experimental_reason().is_some()` 且会话未开启 `experimental_api_enabled`，返回 `<reason> requires experimentalApi capability`。

3. 运行时兼容（出站请求字段剥离）
- `app-server/src/transport.rs`：对 `CommandExecutionRequestApproval`，当连接未启用 experimental 时调用 `strip_experimental_fields()` 删除实验字段，避免向稳定客户端暴露不兼容字段。

4. 生成阶段过滤（schema/ts）
- `app-server-protocol/src/export.rs` 调用 `experimental_fields()`（`inventory` 收集）并在 stable 导出中：
  - 过滤 `ClientRequest.ts` 的实验方法 arm
  - 按 `ExperimentalField` 删除 type 的实验字段
  - 删除实验方法关联的 Params/Response 类型文件与 schema 定义

### F. 关键数据结构与协议约定
1. `ExperimentalApi` trait（`app-server-protocol/src/experimental_api.rs`）
- 统一接口：`experimental_reason(&self)`
- 已为 `Option<T>`、`Vec<T>`、`HashMap<K,V>`、`BTreeMap<K,V>` 提供容器实现，配合 nested 使用。

2. `ExperimentalField`
- 字段：`type_name`、`field_name`、`reason`
- 语义约定：reason 推荐 `<method>` 或 `<method>.<field>`。

3. 运行时协商字段
- `InitializeCapabilities.experimental_api`（客户端初始化时协商）
- `GenerateTsOptions.experimental_api`/`SchemaFixtureOptions.experimental_api`（导出时决定是否保留实验面）

### G. 维护命令（与该宏行为直接相关）
- 协议验证：`cargo test -p codex-app-server-protocol`
- app-server 端到端 gate：`cargo test -p codex-app-server`
- 生成稳定 schema：`just write-app-server-schema`
- 生成含实验 schema：`just write-app-server-schema --experimental`

## 关键代码路径与文件引用
### 目标目录
- `codex-rs/codex-experimental-api-macros/src/lib.rs`
  - 宏入口与完整展开逻辑（结构体、枚举、属性解析、presence 判定）
- `codex-rs/codex-experimental-api-macros/Cargo.toml`
  - `proc-macro = true`，依赖 `syn/quote/proc-macro2`
- `codex-rs/codex-experimental-api-macros/BUILD.bazel`
  - Bazel 中声明为 proc-macro crate

### 直接调用方
- `codex-rs/app-server-protocol/src/protocol/common.rs`
  - `use codex_experimental_api_macros::ExperimentalApi;`
  - `ServerNotification` 派生与 `ClientRequest` experimental reason 汇总
- `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - 大量协议类型字段/枚举 experimental 标注与 nested 冒泡
- `codex-rs/app-server-protocol/src/experimental_api.rs`
  - trait 与容器实现、inventory 集合、宏行为单元测试

### 运行时消费方
- `codex-rs/app-server/src/message_processor.rs`
  - 请求入站 experimental 拒绝逻辑
- `codex-rs/app-server/src/transport.rs`
  - 出站请求 experimental 字段剥离逻辑

### 工件生成与脚本链路
- `codex-rs/app-server-protocol/src/export.rs`
  - 基于 `experimental_fields()` 的 TS/JSON 过滤
- `codex-rs/app-server-protocol/src/schema_fixtures.rs`
  - fixture 生成入口，受 `experimental_api` 选项控制
- `codex-rs/app-server-protocol/src/bin/export.rs`
- `codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs`

### 文档
- `codex-rs/app-server/README.md`
  - Experimental API opt-in、错误文案、`#[experimental(nested)]` 维护指引

## 依赖与外部交互
### crate 依赖
- `syn`：解析 derive 输入 AST 与属性参数。
- `quote`：生成 token。
- `proc_macro2`：span/token 辅助。

### 与工作区的构建交互
- 在 `codex-rs/Cargo.toml` 中注册为 workspace member 与 workspace dependency，当前主要由 `codex-app-server-protocol` 依赖。
- Bazel 通过 `codex_rust_crate(proc_macro = True)` 暴露给工作区编译图。

### 与运行时模块的交互
- 宏本身仅编译期运行；运行时行为由生成代码注入到 `app-server-protocol` 类型内。
- 与 `inventory` 的交互属于“链接期全局注册”：每个带 `#[experimental("...")]` 字段在最终二进制里有静态注册项。

### 配置/协议交互
- 与客户端协商字段：`initialize.params.capabilities.experimentalApi`。
- 与 schema 导出选项：CLI `--experimental`，映射到 `GenerateTsOptions.experimental_api` / `SchemaFixtureOptions.experimental_api`。

## 风险、边界与改进建议
### 风险与边界
1. 字段名转换策略过于简化
- 宏使用 `snake_to_camel` 推导 `field_name`，未读取 `serde(rename)` / `serde(rename_all)` / `ts(rename)`。
- 在 snake_case wire payload（例如 config 类请求）或显式 rename 场景中，可能导致“注册字段名”与实际导出字段名不一致，进而影响 stable 过滤精度。

2. 类型名冲突风险
- `type_name` 仅用裸类型名（无模块路径），在不同模块同名类型时可能冲突；`export.rs` 当前通过 `definition_matches_type` 做部分缓解，但 TS 文件级过滤仍可能有歧义。

3. 属性解析对误用容错偏静默
- `#[experimental(...)]` 解析失败时多数路径表现为忽略（`ok()`），编译期缺少更强约束，容易出现“写了标注但未生效”。

4. enum 支持边界
- enum 只支持 variant 级 experimental，不支持“variant 内字段 nested 递归”语义；如果未来需要更细粒度变体字段门控，当前模型不够用。

5. presence 语义是约定而非显式 schema
- 非 `Option/Vec/Map/bool` 字段默认恒 `true`，对于“空字符串/零值也应视为未使用”的业务场景不适配。

6. 出站兼容仍有硬编码
- `CommandExecutionRequestApprovalParams::strip_experimental_fields()` 目前手动列字段，未复用宏/注册表做自动剥离，后续新增字段时有漏改风险。

### 改进建议
1. 字段名来源改为真实序列化名
- 在宏内解析 `serde`/`ts` rename 元信息，至少支持：
  - `#[serde(rename = "...")]`
  - 类型级 `rename_all`
- 避免当前 camelCase 推断带来的误删/漏删。

2. `ExperimentalField` 增加类型限定信息
- 可增加 `module_path` 或完整 type path，降低同名类型冲突。

3. 对非法标注给出显式编译错误
- 例如 `#[experimental(foo)]`（foo 非 nested）时直接报错，而非静默忽略。

4. 扩展 enum 能力
- 支持 variant payload 字段级检查（或显式禁止并报更清晰错误），避免使用者误判行为。

5. 把出站字段剥离通用化
- 在 app-server 出站链路引入“按 `ExperimentalField` + capability 自动剥离”机制，替代单类型硬编码。

6. 补充回归测试矩阵
- 增加包含 `serde(rename)`、`rename_all=snake_case`、同名类型的过滤测试，确保宏元数据与导出过滤一致。

## 结论
`codex-experimental-api-macros` 是 app-server experimental 生命周期中的核心编译期组件：
- 向上连接协议类型标注（`#[experimental(...)]`/`#[experimental(nested)]`）。
- 向下驱动运行时门控（入站拒绝）与导出过滤（stable TS/JSON）。

它当前实现简洁且已覆盖主要场景，但在“字段真实命名一致性、同名类型去歧义、出站自动剥离通用化”方面还有工程化增强空间。EOF
