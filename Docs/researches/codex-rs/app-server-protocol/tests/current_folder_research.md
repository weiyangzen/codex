# codex-rs/app-server-protocol/tests 目录研究

## 场景与职责

`codex-rs/app-server-protocol/tests` 当前只有 1 个集成测试文件：`schema_fixtures.rs`。该目录承担的核心职责不是验证业务逻辑，而是做“协议产物防漂移守卫（drift guard）”：

1. 校验仓库内 vendored schema（`schema/typescript` 与 `schema/json`）是否仍与当前 Rust 协议类型定义一致。
2. 在协议定义发生变更但开发者忘记回写 schema fixture 时，尽早失败并给出统一修复指令（`just write-app-server-schema`）。
3. 通过路径级 diff + 内容级 diff 输出，降低审查 schema 变更成本。

这个职责直接服务于 app-server 协议的稳定性：Rust 类型、TS 导出、JSON Schema 三者必须一致。

## 功能点目的

### 1) TypeScript fixture 一致性校验

入口：`typescript_schema_fixtures_match_generated`（`codex-rs/app-server-protocol/tests/schema_fixtures.rs:12`）。

目的：
- 读取仓库当前 `schema/typescript` 子树。
- 在内存中按当前协议类型重新生成 TS fixture 子树。
- 比较“文件集合 + 文件内容”是否完全一致。

如果不一致，测试直接 panic，并给出 `just write-app-server-schema` 修复建议。

### 2) JSON fixture 一致性校验

入口：`json_schema_fixtures_match_generated`（`.../schema_fixtures.rs:24`）。

目的：
- 读取仓库当前 `schema/json` 子树。
- 在临时目录调用 JSON schema 生成器。
- 与 vendored json fixtures 做同样的集合/内容 diff。

区别点：JSON 路径会真实落盘到 `tempfile::tempdir`，再回读比较。

### 3) Bazel/Cargo 双环境稳定运行

测试为了兼容 Bazel runfiles 与 Cargo 本地运行，明确做了资源定位与根目录一致性校验：

- 通过 `codex_utils_cargo_bin::find_resource!` 定位已知文件，再 `parent().parent()` 推导 schema 根目录（`.../schema_fixtures.rs:107`）。
- 同时用 TS 与 JSON 两个已知文件交叉验证 root 是否一致，防止 runfiles 布局差异导致误判。

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. 测试主流程（目录级）

调用链（简化）：

1. `typescript_schema_fixtures_match_generated`
2. `schema_root` -> `read_tree("typescript")`
3. `generate_typescript_schema_fixture_subtree_for_tests`
4. `assert_schema_trees_match`

以及：

1. `json_schema_fixtures_match_generated`
2. `assert_schema_fixtures_match_generated("json", generate_json_with_experimental)`
3. 临时目录生成 -> `read_tree`
4. `assert_schema_trees_match`

比较逻辑分两层（`.../schema_fixtures.rs:53`）：
- 先比较路径集合（防止漏文件/多文件）。
- 再逐文件比较内容（输出 unified diff，便于定位）。

### B. TS 生成对比为什么是“内存子树”

测试未直接调用“写入磁盘的 TS fixture 生成”，而使用：
- `generate_typescript_schema_fixture_subtree_for_tests`（`codex-rs/app-server-protocol/src/schema_fixtures.rs:53`）

这个函数会：
1. 从 `ClientRequest/ClientNotification/ServerRequest/ServerNotification` 起步收集类型。
2. 通过 `visit_client_response_types` / `visit_server_response_types` 补齐响应类型依赖（定义在 `protocol/common.rs` 宏展开结果，见 `.../common.rs:175,604`）。
3. 对导出树执行 `filter_experimental_ts_tree`，确保稳定 schema 不包含实验字段/方法（`src/export.rs:259`）。
4. 生成 `index.ts` 导出树（`src/export.rs:1966`）。

这样做避免了 IO 干扰，专注比较“当前类型系统 -> 目标 TS 产物”的逻辑一致性。

### C. JSON 生成与规范化比较

JSON 路径使用 `generate_json_with_experimental(out_dir, false)`（`src/export.rs:195`），内部关键步骤：

1. 导出 envelope + client/server params/response/notification schema。
2. `build_schema_bundle` 合并 definitions（`src/export.rs:946`）。
3. `filter_experimental_schema` 删除实验能力（`src/export.rs:400`）。
4. 写出 bundle 文件与 flat-v2 bundle。

测试读取 fixture 时会做规范化（`src/schema_fixtures.rs:120`）：
- JSON：解析后 canonicalize（对象键排序，部分数组按稳定键排序，`...:148`），再 pretty 序列化。
- TS：统一换行，且忽略统一 header（`GENERATED_TS_HEADER`），避免平台换行或 banner 造成假阳性。

### D. 数据结构与差异输出

核心数据结构：
- `BTreeMap<PathBuf, Vec<u8>>`：路径有序，保证 diff 稳定。
- `similar::TextDiff`：输出 unified diff。

失败信息语义：
- 文件集合不一致 -> 列表 diff。
- 文件内容不一致 -> 单文件内容 diff。
- 两者都附带“运行 `just write-app-server-schema`”的恢复指引。

### E. 相关命令与维护路径

- 生成/回写 fixture：
  - `just write-app-server-schema`
  - `just write-app-server-schema --experimental`
  - 对应 just 入口：`justfile:82`
- 协议 CLI 生成出口：
  - `codex app-server generate-ts`
  - `codex app-server generate-json-schema`
  - 调用位置：`codex-rs/cli/src/main.rs:658-675`
- 协议维护文档（实验 API 流程与校验命令）：
  - `codex-rs/app-server/README.md:1450-1458`

## 关键代码路径与文件引用

### 测试入口与断言

- `codex-rs/app-server-protocol/tests/schema_fixtures.rs:12` `typescript_schema_fixtures_match_generated`
- `codex-rs/app-server-protocol/tests/schema_fixtures.rs:24` `json_schema_fixtures_match_generated`
- `codex-rs/app-server-protocol/tests/schema_fixtures.rs:30` `assert_schema_fixtures_match_generated`
- `codex-rs/app-server-protocol/tests/schema_fixtures.rs:53` `assert_schema_trees_match`
- `codex-rs/app-server-protocol/tests/schema_fixtures.rs:107` `schema_root`

### fixture 读写与规范化

- `codex-rs/app-server-protocol/src/schema_fixtures.rs:43` `read_schema_fixture_subtree`
- `codex-rs/app-server-protocol/src/schema_fixtures.rs:53` `generate_typescript_schema_fixture_subtree_for_tests`
- `codex-rs/app-server-protocol/src/schema_fixtures.rs:87` `write_schema_fixtures_with_options`
- `codex-rs/app-server-protocol/src/schema_fixtures.rs:120` `read_file_bytes`
- `codex-rs/app-server-protocol/src/schema_fixtures.rs:148` `canonicalize_json`
- `codex-rs/app-server-protocol/src/schema_fixtures.rs:225` `collect_files_recursive`
- `codex-rs/app-server-protocol/src/schema_fixtures.rs:266` `collect_typescript_fixture_file`

### 协议导出与实验字段过滤

- `codex-rs/app-server-protocol/src/export.rs:105` `generate_ts_with_options`
- `codex-rs/app-server-protocol/src/export.rs:195` `generate_json_with_experimental`
- `codex-rs/app-server-protocol/src/export.rs:259` `filter_experimental_ts_tree`
- `codex-rs/app-server-protocol/src/export.rs:400` `filter_experimental_schema`
- `codex-rs/app-server-protocol/src/export.rs:946` `build_schema_bundle`
- `codex-rs/app-server-protocol/src/export.rs:1966` `generate_index_ts_tree`

### 宏展开提供的遍历/导出入口

- `codex-rs/app-server-protocol/src/protocol/common.rs:85` `client_request_definitions!` 宏
- `codex-rs/app-server-protocol/src/protocol/common.rs:150` `EXPERIMENTAL_CLIENT_METHODS`
- `codex-rs/app-server-protocol/src/protocol/common.rs:175` `visit_client_response_types`
- `codex-rs/app-server-protocol/src/protocol/common.rs:547` `server_request_definitions!` 宏
- `codex-rs/app-server-protocol/src/protocol/common.rs:604` `visit_server_response_types`

### 工具链与构建系统耦合点

- `codex-rs/app-server-protocol/BUILD.bazel:6` `test_data_extra = glob(["schema/**"])`
- `justfile:1` 工作目录固定 `codex-rs`
- `justfile:82` `write-app-server-schema` recipe
- `codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs:29` fixture 写入 CLI
- `codex-rs/cli/src/main.rs:658-675` app-server schema 生成子命令

## 依赖与外部交互

### 代码级依赖

- `ts-rs`：导出 TypeScript 类型，支持 `visit_dependencies` 类型图遍历。
- `schemars` + `serde_json`：导出并组装 JSON Schema。
- `codex_experimental_api_macros` + `inventory`：记录并过滤实验方法/字段。
- `codex-utils-cargo-bin`：在 Cargo/Bazel 环境下统一定位资源。
- `similar`：测试失败时输出 diff。
- `tempfile`：JSON 生成临时目录。

### 外部交互形态

- 文件系统：
  - 读取 `schema/` 下 vendored fixtures。
  - JSON 测试流程写临时文件。
- 进程调用：
  - 在“回写 fixture”流程中，`generate_ts_with_options` 可调用 Prettier（可选），但本目录测试本身不依赖外部 formatter。
- 网络：
  - 本目录测试与 schema 导出过程不依赖网络 IO。

### 协议与上游关系

- 协议边界遵循 app-server JSON-RPC 结构（request/response/notification）。
- `v2` 类型是当前主要演进面，`common.rs` 宏将请求方法与 params/response 类型绑定并暴露给导出器。

## 风险、边界与改进建议

### 风险

1. `canonicalize_json` 的“可排序数组”策略是启发式：
   - 优点：减少跨平台无意义 diff。
   - 风险：若未来出现语义上顺序敏感但仍被误判可排序的数组，可能掩盖真实差异。

2. 当前对比重点在“稳定 schema（experimental=false）”路径。
   - 实验 schema 主要靠生成命令与其他单测覆盖，目录级守卫不直接比较 `--experimental` fixture 子树。

3. 错误路径以 `panic!` 快速失败为主，定位体验好，但在超大变更时输出可能较大。

### 边界

1. 本目录不校验 app-server 运行时行为，仅校验协议产物一致性。
2. 不负责审查“协议设计是否合理”，只确保“定义与产物同步”。
3. Bazel 依赖 `schema/**` 作为测试数据；若后续新增编译期读文件路径而未更新 `BUILD.bazel`，仍可能在其他测试阶段失败。

### 改进建议

1. 增加一个“实验 fixture 一致性”集成测试开关（可按 feature/env 控制），覆盖 `--experimental` 产物与过滤逻辑回归。
2. 为 `assert_schema_trees_match` 增加“差异摘要统计”（新增/删除/修改数量），在大改动场景提升可读性。
3. 对 `canonicalize_json` 增补“顺序敏感数组不排序”回归测试样例（例如 tuple-like schema 结构），降低误排序风险。
4. 在 CI 中明确分层：先跑本目录 drift guard，再跑协议行为类测试，便于快速识别“只是 fixture 未回写”还是“协议逻辑变更”。
