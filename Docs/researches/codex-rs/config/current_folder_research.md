# DIR `codex-rs/config` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/config`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 关联 crate：`codex-config`

## 场景与职责

`codex-rs/config` 是 Codex Rust 工作区里的“配置基础设施中间层”：

1. 对上提供统一配置抽象
- 向 `codex-core`、`hooks`、`cli` 暴露 `ConfigLayerStack`、`ConfigRequirements*`、`Constrained<T>`、配置诊断与合并工具（`codex-rs/config/src/lib.rs`）。

2. 对下承接多来源“受管约束”（requirements）
- 把 cloud / MDM / system / legacy managed config 等来源的 constraints 归一化为可执行约束模型。
- 记录每个约束字段的来源 (`RequirementSource`)，保证错误可追踪。

3. 提供配置层状态模型
- `ConfigLayerEntry` + `ConfigLayerStack` 负责表示多层配置、顺序验证、有效配置合并、字段来源追踪。

4. 提供配置错误定位与渲染
- 把 TOML 解析/类型校验错误映射到具体文件、行列区间，用于 CLI/TUI/app-server 向用户展示可读错误。

5. 提供 requirements 专项能力
- 包括 apps enablement 约束合并、`rules`（exec policy）TOML 解析与验证、网络约束结构化。

一句话：`codex-config` 不负责“最终业务策略执行”（那在 `codex-core`、`network-proxy`、`execpolicy`），但它定义并承载“配置与受管约束的数据模型 + 约束转换 + 诊断语义”。

## 功能点目的

### 1) `Constrained<T>`：统一运行时约束容器
- 文件：`codex-rs/config/src/constraint.rs`
- 目的：把“值 + 校验器 + 可选归一化器”封装成可复用机制，支持：
  - `allow_any` / `allow_only`
  - `new`（带 validator）
  - `normalized`（先 normalize 再验证）
  - `can_set`（探测，不修改）
- 直接用于 `approval_policy`、`sandbox_policy`、`web_search_mode`、`enforce_residency` 等约束字段。

### 2) requirements TOML 归一化与来源追踪
- 文件：`codex-rs/config/src/config_requirements.rs`
- 目的：把原始 `ConfigRequirementsToml`（可选字段）转换为可执行的 `ConfigRequirements`：
  - allow-list 转为 `Constrained` 校验器；
  - 附带 `RequirementSource`，错误时能指明来源（cloud/system/mdm/legacy）。
- 关键结构：
  - `ConfigRequirementsToml`：输入层；
  - `ConfigRequirementsWithSources`：中间层（值 + 来源）；
  - `ConfigRequirements`：运行时约束层。

### 3) apps 约束的“只读增强”合并语义
- 文件：`config_requirements.rs` 的 `merge_enablement_settings_descending`
- 目的：跨来源合并 `apps.<id>.enabled` 时，保证“任一层禁用 = 最终禁用”，避免低优先级禁用被高优先级误放开。

### 4) requirements `rules` 到 exec policy 的安全转换
- 文件：`codex-rs/config/src/requirements_exec_policy.rs`
- 目的：把 `[rules]` 的 TOML 规则转换到 `codex-execpolicy::Policy`，并限制可用 decision：
  - 禁止 `allow`（仅允许 `prompt`/`forbidden`），防止 requirements 通过 overlay 放松策略。

### 5) 配置层模型、版本与来源追踪
- 文件：`codex-rs/config/src/state.rs`, `fingerprint.rs`, `merge.rs`, `overrides.rs`
- 目的：
  - 管理配置层顺序与合法性；
  - 计算每层稳定版本 (`sha256:<hex>`)；
  - 生成 merged config 的 key->origin 映射；
  - 支持 CLI `-c a.b.c=value` 覆写层生成。

### 6) 诊断与错误展示
- 文件：`codex-rs/config/src/diagnostics.rs`
- 目的：
  - 解析错误定位（span 到行列）；
  - 类型错误定位（`serde_path_to_error` 路径反查 TOML 节点 span）；
  - 生成类似编译器风格的 caret 高亮错误文本。

### 7) cloud requirements loader 抽象
- 文件：`codex-rs/config/src/cloud_requirements.rs`
- 目的：定义一个可 clone 且只执行一次底层 future 的 `CloudRequirementsLoader`，对上游暴露统一接口 `get()`。

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. requirements 合并与约束构造流程

1. 来源按优先顺序灌入 `ConfigRequirementsWithSources`
- 真正加载在 `codex-core/config_loader`：
  - cloud 先合并（`cloud_requirements.get()`）
  - macOS MDM requirements
  - system `requirements.toml`
  - legacy `managed_config.toml` backfill
- 入口：`codex-rs/core/src/config_loader/mod.rs:114-149`。

2. `merge_unset_fields` 只填未设置字段
- `ConfigRequirementsWithSources::merge_unset_fields` 会“先到先得”，后到来源不会覆盖已设置字段。
- 对 `apps` 字段是特例：走 `merge_enablement_settings_descending`，保留禁用优先。
- 代码：`codex-rs/config/src/config_requirements.rs:342-404`。

3. `try_into::<ConfigRequirements>()` 生成运行时约束
- 将 allow-list 转为 `Constrained` validator；典型规则：
  - `allowed_approval_policies` 为空报 `EmptyField`；
  - `allowed_sandbox_modes` 必须包含 `read-only` 才可工作；
  - `allowed_web_search_modes` 会自动把 `disabled` 视作可用值；
  - `enforce_residency` 变为“固定值约束”；
  - `rules` 解析失败包成 `ConstraintError::ExecPolicyParse`。
- 代码：`codex-rs/config/src/config_requirements.rs:492-693`。

### B. ConfigLayerStack 有效配置与来源计算

1. 层顺序验证
- `verify_layer_ordering` 验证：
  - layer precedence 单调；
  - user 层最多一个；
  - project 层从 root -> cwd 有序。
- 代码：`codex-rs/config/src/state.rs:278-331`。

2. 有效配置合并
- `effective_config()` 从低优先级到高优先级执行递归 TOML merge。
- merge 规则：table 递归，其它类型直接覆盖。
- 代码：
  - `state.rs:214-227`
  - `merge.rs:4-16`。

3. 字段来源追踪
- `origins()` 通过 DFS 记录每个叶子路径的来源 layer metadata。
- 版本纹理由 canonical JSON + SHA256 得到（字段顺序稳定）。
- 代码：
  - `state.rs:230-243`
  - `fingerprint.rs:8-65`。

### C. 诊断定位流程

1. 语法错误
- `config_error_from_toml` 用 TOML span 直接映射到 `TextRange`。

2. 类型错误
- `config_error_from_typed_toml<T>` 先做 typed 反序列化；失败时用 `serde_path_to_error` 路径反查 TOML node span。
- 对 `features` table 有专门路径修正，尽量落到具体非法值位置。

3. 层内首错回溯
- `first_layer_config_error` 逐层读取实际文件，定位第一个真实文件错误，而不是仅返回 merged 后的抽象错误。

4. 终端展示
- `format_config_error` 输出 `path:line:col` + 行文本 + `^^^^` 高亮。

代码：`codex-rs/config/src/diagnostics.rs:91-257,301-397`。

### D. requirements exec policy 协议

- TOML 结构：`[rules] prefix_rules=[{ pattern=[{token|any_of}], decision, justification }]`
- 关键校验：
  - `prefix_rules` 不能为空；
  - pattern 不能为空；
  - token/any_of 互斥且不能为空字符串；
  - decision 必填；
  - `allow` 明确禁止。
- 输出：`RequirementsExecPolicy`（包裹 `codex_execpolicy::Policy`），可与文件 `.rules` overlay merge。
- 代码：`codex-rs/config/src/requirements_exec_policy.rs:48-236`。

### E. 与 core 的衔接（关键执行点）

1. config loader
- `codex-core` 复用 `codex-config` 公开类型并负责 IO/平台路径加载。
- `ConfigLayerStack::new(layers, requirements, requirements_toml)` 在 loader 尾部组装。
- 代码：`codex-rs/core/src/config_loader/mod.rs:27-60,114-298`。

2. 运行时约束落地
- `core/config/mod.rs` 从 `config_layer_stack.requirements()` 取约束，应用到：
  - approval/sandbox/web_search
  - mcp servers
  - managed network constraints
- 网络约束接入点：`NetworkProxySpec::from_config_and_constraints(...)`。
- 代码：
  - `codex-rs/core/src/config/mod.rs:2116-2637`
  - `codex-rs/core/src/config/network_proxy_spec.rs:87-282`。

3. requirements API 暴露
- app-server `configRequirements/read` 读取 `ConfigRequirementsToml` 并映射为 v2 API 字段。
- `external-sandbox` 在 API 映射时被过滤（不对客户端暴露）。
- 代码：`codex-rs/app-server/src/config_api.rs:106-237`；文档 `codex-rs/app-server/README.md:184`。

### F. 典型命令

```bash
# 仅验证 codex-config crate
cargo test -p codex-config

# 验证 config loader + requirements 融合行为
cargo test -p codex-core config_loader::tests::load_config_layers_includes_cloud_requirements
cargo test -p codex-core config_loader::tests::requirements_exec_policy_tests

# 查看 app-server requirements 映射行为
cargo test -p codex-app-server config_api
```

## 关键代码路径与文件引用

### 目标目录（`codex-rs/config`）

1. 入口导出
- `codex-rs/config/src/lib.rs`

2. 约束模型
- `codex-rs/config/src/constraint.rs:8-278`
- `codex-rs/config/src/config_requirements.rs:17-1623`

3. exec policy requirements
- `codex-rs/config/src/requirements_exec_policy.rs:1-236`

4. 配置层状态与工具
- `codex-rs/config/src/state.rs:1-331`
- `codex-rs/config/src/fingerprint.rs:1-67`
- `codex-rs/config/src/merge.rs:1-18`
- `codex-rs/config/src/overrides.rs:1-55`

5. 诊断
- `codex-rs/config/src/diagnostics.rs:1-397`

6. cloud loader 抽象
- `codex-rs/config/src/cloud_requirements.rs:1-105`

### 关键调用方与上下文依赖

1. 配置加载主链
- `codex-rs/core/src/config_loader/mod.rs:114-298`
- `codex-rs/core/src/config_loader/layer_io.rs:1-141`
- `codex-rs/core/src/config_loader/macos.rs:1-161`
- 设计文档：`codex-rs/core/src/config_loader/README.md`

2. 运行时策略应用
- `codex-rs/core/src/config/mod.rs:2116-2637`
- `codex-rs/core/src/config/managed_features.rs:1-333`
- `codex-rs/core/src/config/network_proxy_spec.rs:87-316`

3. rules 叠加执行策略
- `codex-rs/core/src/exec_policy.rs:487-534`

4. apps/connectors 约束消费
- `codex-rs/core/src/connectors.rs:620-779`

5. hooks 目录配置消费
- `codex-rs/hooks/src/engine/discovery.rs:17-109`

6. app-server requirements API
- `codex-rs/app-server/src/config_api.rs:106-237`
- `codex-rs/app-server/README.md:184`

7. cloud requirements 生产者
- `codex-rs/cloud-requirements/src/lib.rs:45-739`

### 关键测试路径

1. `codex-config` crate 内单测
- `constraint.rs`（约束容器行为）
- `cloud_requirements.rs`（shared future 只执行一次）
- `config_requirements.rs`（字段合并、来源追踪、rules/network/apps语义）

2. 跨 crate 行为测试
- `codex-rs/core/src/config_loader/tests.rs:385-1739`
  - cloud/mdm/system precedence
  - requirements fail-closed
  - legacy 映射
  - rules 合并
- `codex-rs/core/src/connectors_tests.rs`（apps requirements 禁用覆盖）
- `codex-rs/app-server/src/config_api.rs` 内 tests（requirements API 映射）

## 依赖与外部交互

### 内部 crate 依赖

- `codex-app-server-protocol`
  - 依赖 `ConfigLayerSource`/`ConfigLayerMetadata` 及 precedence 语义。
- `codex-protocol`
  - 依赖 `AskForApproval`、`SandboxPolicy`、`WebSearchMode` 等核心枚举。
- `codex-execpolicy`
  - requirements `[rules]` 的目标执行策略模型。
- `codex-utils-absolute-path`
  - 配置路径解析与 guard。

来源：`codex-rs/config/Cargo.toml`。

### 文件系统与平台路径

- system requirements: Unix `/etc/codex/requirements.toml`，Windows `%ProgramData%/OpenAI/Codex/requirements.toml`（加载逻辑在 `core/config_loader`）。
- legacy managed config: `/etc/codex/managed_config.toml`（Unix）或非 Unix 下 `codex_home/managed_config.toml`。

### 平台管理策略（MDM）

- macOS managed preferences keys：
  - `config_toml_base64`
  - `requirements_toml_base64`
- 读取使用 CoreFoundation `CFPreferencesCopyAppValue`（在 `core/config_loader/macos.rs`）。

### 云端 requirements

- `codex-cloud-requirements` 生成 `CloudRequirementsLoader`，并以 fail-closed 语义参与配置加载。
- `CloudRequirementsLoadErrorCode`：`Auth/Timeout/Parse/RequestFailed/Internal`。

### 对外协议暴露

- app-server v2 `configRequirements/read` 返回 allow-lists、feature pin、residency、network。
- wire type 来自 `codex-rs/app-server-protocol/src/protocol/v2.rs:820-865`。

### 文档与脚本

- 用户文档入口：`docs/config.md`（含 JSON schema 位置说明）。
- loader 设计说明：`codex-rs/core/src/config_loader/README.md`。
- 研究流程脚本：`.ops/generate_daily_research_todo.sh`（基于 `Docs/researches/blueprint_checklist.md` 生成每日 TODO）。

## 风险、边界与改进建议

### 1) 风险

1. `config_requirements.rs` 体量过大（1623 LoC）
- 多职责耦合（类型定义 + merge + normalize + tests），维护与回归成本高。
- 建议拆分：`types.rs` / `merge.rs` / `normalize.rs` / `tests/*`。

2. `RequirementsExecPolicy` 相等性依赖 debug 字符串 fingerprint
- `policy_fingerprint` 使用 `format!("{program}:{rule:?}")`，对 debug 表示形式敏感。
- 建议改为结构化序列化 fingerprint（稳定字段排序 + serde）。

3. `CloudRequirementsLoader` 默认是“单次结果缓存”
- `Shared<BoxFuture<...>>` 的语义是同一 loader 实例只解析一次结果；需要上游替换 loader 才会重新拉取。
- 建议在 `codex-config` 文档中明确生命周期边界，避免调用方误判“会自动实时刷新”。

4. legacy + requirements 双轨并存复杂度
- 目前仍支持 `managed_config.toml` backfill，逻辑跨 `layer_io`、`config_loader`、`config_requirements` 多处。
- 建议补一份“弃用里程碑 + 行为矩阵”文档，减少策略歧义。

### 2) 边界

1. sandbox requirements 的功能边界
- requirements 强制模式集合时必须包含 `read-only`，否则报错；这是运行能力边界而不是纯配置偏好。

2. web search requirements 的兼容边界
- `disabled` 总被允许，`allowed_web_search_modes=[]` 也会退化为仅 `disabled`。

3. apps requirements 的语义边界
- 受管层只在 `enabled=false` 时强约束；不会强制开启。

4. network constraints 的边界
- `managed_allowed_domains_only=true` 时进入“受管 allowlist 严格模式”，用户扩展被抑制。

### 3) 改进建议

1. 拆分大模块并将测试邻接到子模块
- 优先拆 `config_requirements.rs`，保持单文件 < 500 LoC 的维护目标。

2. 为 `ConfigLayerStack` 增补专门单测文件
- 当前多数行为测试位于 `core/config_loader/tests.rs`，`codex-config/state.rs` 本地测试覆盖相对薄。

3. 增加 requirements 行为文档页
- 建议新增 `codex-rs/docs/requirements.md`，明确：来源优先级、字段合并语义、错误示例、API 映射差异。

4. 增强诊断输出上下文
- `format_config_error` 可考虑附加 source layer（若可得），进一步降低用户定位成本。
