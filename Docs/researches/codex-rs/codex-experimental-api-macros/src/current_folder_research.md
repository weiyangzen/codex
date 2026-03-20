# DIR 研究：codex-rs/codex-experimental-api-macros/src

## 场景与职责
`codex-rs/codex-experimental-api-macros/src` 当前只有一个核心文件：`lib.rs`，其职责是提供 `#[derive(ExperimentalApi)]` 过程宏，统一把协议类型上的 `#[experimental(...)]` 注解编译成可执行逻辑与元数据注册。

它处于一条“编译期生成 -> 运行时门控/导出过滤”的中间层：

1. 编译期：
- 为结构体/枚举生成 `ExperimentalApi::experimental_reason(&self) -> Option<&'static str>`。
- 为实验字段生成 `inventory::submit!` 注册项，供后续 schema/TS 过滤使用。

2. 运行时消费：
- `app-server` 在处理请求时调用 `experimental_reason()` 判断是否需要 `capabilities.experimentalApi`。
- `app-server-protocol` 在导出 TS/JSON schema 时读取已注册实验字段，剔除稳定通道不应暴露的字段/方法。

因此，该目录的真实责任不是“定义实验能力策略”，而是“把注解转成统一的检测与注册机制”，并保持与协议层命名/导出行为一致。

## 功能点目的
### 1) `#[derive(ExperimentalApi)]` 的统一派生
目标：减少协议类型手写判断逻辑，确保不同类型（struct/enum）行为一致。

核心入口：
- `derive_experimental_api`（`codex-rs/codex-experimental-api-macros/src/lib.rs:16`）
- 对 `Data::Struct` 与 `Data::Enum` 分发到不同展开函数。
- 对 `Data::Union` 直接报编译错误（不支持 union）。

### 2) `#[experimental("reason")]` 的字段/变体门控
目标：给“实验能力触发点”一个稳定 reason id，并由宏返回首个命中的 reason。

行为要点：
- struct 字段标注后，会参与 `experimental_reason` 检测。
- enum 变体标注后，该变体命中即返回 reason。
- reason 作为运行时错误文案与能力协商的关键键值（如 `thread/start.mockExperimentalField`）。

### 3) `#[experimental(nested)]` 的嵌套冒泡
目标：支持“外层字段稳定、内层类型可能实验”的情况（例如 `Option<AskForApproval>`）。

行为：
- 宏为该字段生成递归调用：`ExperimentalApi::experimental_reason(&self.field)`。
- 内层命中时，reason 从内层向上传播。

### 4) 实验字段注册（inventory）
目标：在不硬编码字段列表的情况下，让导出链路知道“哪些字段是实验字段”。

行为：
- 宏为每个实验字段生成 `::inventory::submit!`。
- 注册结构体为 `ExperimentalField { type_name, field_name, reason }`。
- `export.rs` 再基于这些注册项过滤 TS/JSON 的字段。

### 5) presence 语义（字段“被使用”判定）
目标：避免把 `None`、空集合等误判为“使用了实验字段”。

内置规则：
- `Option<T>`：只有 `Some(inner)` 且 inner 也“存在”才命中。
- `Vec`/`HashMap`/`BTreeMap`：非空才命中。
- `bool`：`true` 命中。
- 其他类型：默认视为存在（恒 `true`）。

## 具体技术实现（关键流程/数据结构/协议/命令）
### A. 宏展开主流程（src/lib.rs）
1. AST 解析与分派
- `parse_macro_input!(input as DeriveInput)` 解析输入。
- `derive_for_struct` 处理结构体（`lib.rs:30`）。
- `derive_for_enum` 处理枚举（`lib.rs:160`）。

2. 结构体展开（`derive_for_struct`）
- 遍历字段并分三类收集：
  - `checks`：运行时检测语句。
  - `experimental_fields`：类型内常量 `EXPERIMENTAL_FIELDS` 的条目。
  - `registrations`：`inventory::submit!` 注册语句。
- 生成结果包含：
  - `impl Type { pub(crate) const EXPERIMENTAL_FIELDS: ... }`（`lib.rs:146-149`）。
  - `impl ExperimentalApi for Type { fn experimental_reason(...) }`（`lib.rs:151-155`）。

3. 枚举展开（`derive_for_enum`）
- 对每个 variant 生成 `match` arm。
- 仅检查 variant 上是否有 `#[experimental("...")]`，有则返回 `Some(reason)`，否则 `None`。

### B. 属性解析实现细节
- `experimental_reason_attr`（`lib.rs:199-205`）仅接受 `LitStr` 形式，即 `#[experimental("...")]`。
- `experimental_nested_attr`（`lib.rs:211-218`）仅接受 `Ident` 且必须是 `nested`，即 `#[experimental(nested)]`。

这使两个语义完全分离：
- 字符串参数表示“直接实验门控”。
- `nested` 表示“递归检查子类型”。

### C. presence 判定算法
关键函数：
- `presence_expr_for_access`（`lib.rs:260`）用于 `self.field`。
- `presence_expr_for_ref`（`lib.rs:279`）用于 `Option` 解包后的引用。
- `option_inner` / `is_vec_like` / `is_map_like` / `is_bool` 负责类型分类（`lib.rs:295+`）。

生成表达式示意：
- `Option<T>` -> `self.field.as_ref().is_some_and(...)`
- `Vec/Map` -> `!self.field.is_empty()`
- `bool` -> `self.field`
- 其他 -> `true`

影响：
- 对 `Option<bool>`，仅 `Some(true)` 才触发。
- 对 `Option<Vec<T>>`，仅 `Some(non_empty_vec)` 才触发。
- 对 `Option<CustomStruct>`，只要 `Some(_)` 就触发（因 `CustomStruct` 走默认 `true` 分支）。

### D. 与协议/运行时链路对接
1. trait 与容器实现
- `app-server-protocol/src/experimental_api.rs` 定义 `ExperimentalApi` trait 及 `Option/Vec/HashMap/BTreeMap` 容器实现。
- 这使 `#[experimental(nested)]` 可在容器上自然工作。

2. 入站请求门控
- `app-server/src/message_processor.rs:616-623`：
  - 若 `codex_request.experimental_reason().is_some()` 且会话未启用 `experimental_api_enabled`，返回 `INVALID_REQUEST (-32600)` 与 `"<reason> requires experimentalApi capability"`。

3. 出站请求兼容处理
- `app-server/src/transport.rs:664-678`：
  - 针对 `CommandExecutionRequestApproval`，在未开启实验能力时调用 `strip_experimental_fields()` 移除实验字段。

4. 导出过滤（TS/JSON）
- `app-server-protocol/src/export.rs`：
  - 调 `experimental_fields()` 收集 inventory 注册项。
  - `filter_experimental_type_fields_ts` 按 `(type_name, field_name)` 删除 TS 字段。
  - `filter_experimental_schema` 从 JSON schema 的 properties/required 中删除实验字段。
  - 另结合 `EXPERIMENTAL_CLIENT_METHODS` 删除实验方法与关联类型。

### E. 配置、脚本、命令
1. 运行时能力协商
- `InitializeCapabilities.experimental_api`（`app-server-protocol/src/protocol/v1.rs:45-52`）在 `initialize` 时声明是否启用 experimental API。

2. schema/类型导出开关
- `GenerateTsOptions.experimental_api`（`app-server-protocol/src/export.rs`）。
- `SchemaFixtureOptions.experimental_api`（`app-server-protocol/src/schema_fixtures.rs`）。
- 二进制命令支持 `--experimental`：
  - `app-server-protocol/src/bin/export.rs`
  - `app-server-protocol/src/bin/write_schema_fixtures.rs`

3. 维护命令（README 指南）
- `just write-app-server-schema`
- `just write-app-server-schema --experimental`
- `cargo test -p codex-app-server-protocol`

## 关键代码路径与文件引用
### 目标目录（被研究对象）
- `codex-rs/codex-experimental-api-macros/src/lib.rs`
  - 宏入口：`derive_experimental_api`（第16行）
  - struct 展开：`derive_for_struct`（第30行）
  - enum 展开：`derive_for_enum`（第160行）
  - 属性解析：`experimental_reason_attr` / `experimental_nested_attr`（第199/211行）
  - presence 判定：`presence_expr_for_access` / `presence_expr_for_ref`（第260/279行）

### 直接调用方（宏使用者）
- `codex-rs/app-server-protocol/src/protocol/common.rs`
  - `ServerNotification` 由 `derive(..., ExperimentalApi)` 自动生成门控逻辑。
  - `client_request_definitions!` 通过 `inspect_params: true` 把稳定方法中的字段级实验门控下探到 params。
- `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - 大量协议类型/字段/枚举变体通过 `#[experimental(...)]` + `#[experimental(nested)]` 接入。
- `codex-rs/app-server-protocol/src/experimental_api.rs`
  - 提供 trait 与容器实现，并含宏行为单测。

### 被调用方（宏实现依赖）
- `syn`（AST 解析）
- `quote`（token 生成）
- `proc_macro2`（span/token）

### 运行时与导出消费方
- `codex-rs/app-server/src/message_processor.rs`（入站拒绝）
- `codex-rs/app-server/src/transport.rs`（出站剥离）
- `codex-rs/app-server-protocol/src/export.rs`（TS/JSON 过滤）
- `codex-rs/app-server-protocol/src/schema_fixtures.rs`（fixture 生成）

### 测试路径
- `codex-rs/app-server-protocol/src/experimental_api.rs`（derive 行为单测）
- `codex-rs/app-server-protocol/src/protocol/common.rs`（请求/通知 reason 断言）
- `codex-rs/app-server-protocol/src/protocol/v2.rs`（字段与 nested 冒泡断言）
- `codex-rs/app-server-protocol/src/export.rs`（TS/JSON 过滤断言）
- `codex-rs/app-server/tests/suite/v2/experimental_api.rs`（端到端能力门控测试）
- `codex-rs/app-server/src/transport.rs`（出站字段剥离测试）

### 文档路径
- `codex-rs/app-server/README.md`（客户端 opt-in 与维护者接入指引）

## 依赖与外部交互
### 构建与链接层
- 该 crate 为 `proc-macro = true`（`codex-rs/codex-experimental-api-macros/Cargo.toml`）。
- 作为 workspace member，被 `codex-app-server-protocol` 依赖。
- Bazel 侧声明为 `codex_rust_crate(proc_macro = True)`（`BUILD.bazel`）。

### 与 inventory 的交互
- 宏生成的 `inventory::submit!` 在链接期汇总实验字段。
- `experimental_fields()` 运行时读取汇总结果并用于 schema/TS 过滤。
- 这是一种“编译期注解 -> 链接期注册 -> 运行时读取”的跨阶段数据通道。

### 与协议协商交互
- 客户端通过 `initialize.params.capabilities.experimentalApi` 显式协商。
- 协商结果由 app-server 连接状态持有，并参与请求门控与出站剥离。

### 与导出工具交互
- `export` / `write_schema_fixtures` 可选 `--experimental`。
- 未开启时，会基于宏注册结果删除实验字段/方法，生成稳定 schema。

## 风险、边界与改进建议
### 风险与边界
1. 字段名推导与 serde/ts 重命名可能不一致
- 宏当前用 `snake_to_camel` 推导 `field_name`（`lib.rs:220-242`），不读取 `serde(rename)`、`ts(rename)`、`rename_all`。
- 在非 camelCase 或显式重命名场景，可能导致过滤时字段匹配偏差。

2. `type_name` 使用简单类型名，存在同名类型歧义风险
- 注册时仅记录裸类型名（如 `Config`），若多模块存在同名类型，TS 文件层过滤按文件 stem 匹配可能误中。
- `export.rs` 在 JSON definitions 场景做了 `ends_with("::{type_name}")` 补偿，但 TS 层仍偏弱。

3. 属性误写容错较“静默”
- `#[experimental(...)]` 解析失败路径多是 `ok()` 后忽略，而不是显式编译报错。
- 可能出现“看似标注了但没生效”的隐性问题。

4. enum 仅支持变体级 reason，不检查变体负载内部字段
- 当前 `derive_for_enum` 不处理 variant payload 的 nested/field 标注，能力模型偏粗粒度。

5. presence 规则对“业务空值”不可配置
- 非容器/非 bool 类型默认恒 `true`，例如 `Option<CustomStruct>` 的 `Some(default)` 也算命中。
- 某些业务希望更精细的“已使用”语义时，现实现不足。

6. 出站剥离仍有手工代码
- `CommandExecutionRequestApprovalParams::strip_experimental_fields` 目前手写字段清单，新增实验字段时有漏改风险。

### 改进建议
1. 解析真实 wire 名称
- 在宏侧解析 `serde/ts` rename 元信息，替代简单 `snake_to_camel`。

2. 注册更强类型标识
- 为 `ExperimentalField` 增加命名空间或完整类型路径，降低同名冲突。

3. 强化错误反馈
- 对非法 `#[experimental(...)]` 用法在宏展开时直接报错，而不是忽略。

4. 扩展 enum 递归能力（或明确禁止）
- 支持 variant payload nested 冒泡，或在文档中显式声明“不支持并建议替代写法”。

5. 把出站剥离从手工迁移到统一机制
- 复用 `ExperimentalField`/trait 结果做自动剥离，减少协议演进时的维护负担。

6. 增加“命名一致性”测试
- 在 `export.rs` 增加 `serde(rename)`、`rename_all=snake_case`、同名类型冲突等回归测试，验证宏注册数据与导出过滤的一致性。
