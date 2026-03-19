# codex-rs/app-server-protocol/src/bin 研究

## 场景与职责

`codex-rs/app-server-protocol/src/bin` 目录包含两个可执行入口，职责是把协议类型导出为可消费的 schema 产物：

- `export.rs`：面向“任意输出目录”的一次性导出工具，同时生成 TypeScript 与 JSON Schema。
- `write_schema_fixtures.rs`：面向仓库内 vendored fixtures（`schema/typescript`、`schema/json`）的重生成工具，是维护流程主入口。

它们本身不定义协议语义，只是将 `codex_app_server_protocol` crate 的导出能力（`generate_ts_with_options` / `generate_json_with_experimental` / `write_schema_fixtures_with_options`）做成 CLI。

## 功能点目的

### 1) `export` 二进制

目的：给外部调用者快速导出当前协议的 TS + JSON schema（默认 stable，支持 experimental）。

- 参数：`-o/--out`、`-p/--prettier`、`--experimental`（`src/bin/export.rs:9-20`）。
- 执行顺序：先 TS 后 JSON（`src/bin/export.rs:25-33`）。
- 适用场景：工具链、临时目录验证、非 vendored 输出。

### 2) `write_schema_fixtures` 二进制

目的：更新仓库内协议 fixtures，供测试与下游消费。

- 参数：`--schema-root`、`-p/--prettier`、`--experimental`（`src/bin/write_schema_fixtures.rs:8-19`）。
- 默认输出根：`$CARGO_MANIFEST_DIR/schema`（`src/bin/write_schema_fixtures.rs:25-27`）。
- 调用 `write_schema_fixtures_with_options` 前会构造上下文错误信息，便于失败定位（`src/bin/write_schema_fixtures.rs:29-41`）。
- 维护主路径：`just write-app-server-schema` 直接调用这个 bin（`justfile:81-83`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. 关键流程

1. 参数解析（Clap derive）
- 两个 bin 均通过 `clap::Parser` 解析参数（`src/bin/export.rs:5`，`src/bin/write_schema_fixtures.rs:6`）。

2. 进入库导出层
- `export` -> `generate_ts_with_options` + `generate_json_with_experimental`（`src/bin/export.rs:25-33`）。
- `write_schema_fixtures` -> `write_schema_fixtures_with_options`（`src/bin/write_schema_fixtures.rs:29-35`）。

3. TS 生成与后处理
- `generate_ts_with_options` 导出 4 类总线类型及关联响应，随后按 `experimental_api` 过滤，生成 index.ts，补 header，可选调用 prettier（`src/export.rs:105-182`）。
- TS experimental 过滤由 `filter_experimental_ts` 驱动：
  - 裁剪 `ClientRequest.ts` 联合臂
  - 裁剪 experimental 字段
  - 删除 experimental 参数/响应类型文件（`src/export.rs:246-256`, `259-291`, `294-398`, `576-597`）。

4. JSON 生成与打包
- `generate_json_with_experimental` 生成 envelope + params/response schemas，组装 bundle，再产出 `codex_app_server_protocol.schemas.json` 与 flat-v2 bundle（`src/export.rs:195-244`）。
- `build_schema_bundle` 负责 definitions 命名空间归并、`$ref` 重写、title 注解（`src/export.rs:946-1027`）。
- `build_flat_v2_schema` 拉平 `definitions.v2`，补共享 root 依赖，校验引用完整性（`src/export.rs:1029-1088`）。

5. fixtures 写入与清理
- `write_schema_fixtures_with_options` 先 `remove_dir_all` 清空 `typescript/`、`json/` 再重建，避免陈旧文件残留（`src/schema_fixtures.rs:87-117`）。

### B. 关键数据结构

- `GenerateTsOptions`：
  - `generate_indices`
  - `ensure_headers`
  - `run_prettier`
  - `experimental_api`
  （`src/export.rs:83-98`）

- `SchemaFixtureOptions`：当前仅 `experimental_api`（`src/schema_fixtures.rs:23-26`）。

- `GeneratedSchema`：承载 `namespace`、`logical_name`、`value`、`in_v1_dir`，供 bundle 构建与过滤使用（`src/export.rs:52-73`）。

### C. 协议/能力语义关联

- protocol 侧通过宏维护 experimental 方法/类型集合（`EXPERIMENTAL_CLIENT_METHODS` 等），导出层据此过滤 TS/JSON（`src/protocol/common.rs:45-79`, `133-164`; `src/export.rs:246-256`, `556-560`）。
- runtime 侧也依赖同一语义：
  - 入站请求若命中 experimental 且未协商 capability，则返回 `<reason> requires experimentalApi capability`（`app-server/src/message_processor.rs:616-625`，`src/experimental_api.rs:29-32`）。
  - 出站部分 server request 参数会在未启用 experimental 时剥离字段（`app-server/src/transport.rs:660-681`，`src/protocol/v2.rs:5081-5088`）。

### D. 命令链路

- 仓库维护命令：
  - `just write-app-server-schema`
  - `just write-app-server-schema --experimental`
  （`justfile:81-83`，`app-server/README.md:1447-1453`）

- 用户侧命令（由 `codex` CLI 暴露）：
  - `codex app-server generate-ts --out DIR [--experimental]`
  - `codex app-server generate-json-schema --out DIR [--experimental]`
  （`cli/src/main.rs:355-390`, `655-678`; `app-server/README.md:1356-1366`）

- 本目录 bin 的直接调用：
  - `cargo run -p codex-app-server-protocol --bin export -- -o DIR [-p PRETTIER_BIN] [--experimental]`
  - `cargo run -p codex-app-server-protocol --bin write_schema_fixtures -- [--schema-root DIR] [-p PRETTIER_BIN] [--experimental]`

## 关键代码路径与文件引用

- 目录入口
  - `codex-rs/app-server-protocol/src/bin/export.rs:1-34`
  - `codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs:1-42`

- 导出核心
  - `codex-rs/app-server-protocol/src/export.rs:83-244`
  - `codex-rs/app-server-protocol/src/export.rs:246-406`
  - `codex-rs/app-server-protocol/src/export.rs:545-597`
  - `codex-rs/app-server-protocol/src/export.rs:946-1088`
  - `codex-rs/app-server-protocol/src/export.rs:1947-2027`

- fixtures 管理
  - `codex-rs/app-server-protocol/src/schema_fixtures.rs:23-109`
  - `codex-rs/app-server-protocol/src/schema_fixtures.rs:111-240`

- API 暴露与依赖接入
  - `codex-rs/app-server-protocol/src/lib.rs:7-47`
  - `codex-rs/app-server-protocol/Cargo.toml:14-43`
  - `codex-rs/app-server-protocol/BUILD.bazel:3-7`

- 调用方与文档
  - `codex-rs/cli/src/main.rs:355-390`
  - `codex-rs/cli/src/main.rs:655-678`
  - `justfile:81-83`
  - `codex-rs/app-server/README.md:1356-1366`
  - `codex-rs/app-server/README.md:1447-1459`

- 测试与运行时协同
  - `codex-rs/app-server-protocol/tests/schema_fixtures.rs:11-143`
  - `codex-rs/app-server/tests/suite/v2/experimental_api.rs:25-219`
  - `codex-rs/app-server/src/message_processor.rs:616-625`
  - `codex-rs/app-server/src/transport.rs:660-681`
  - `codex-rs/app-server-protocol/src/protocol/v2.rs:5019-5088`

## 依赖与外部交互

### 内部模块依赖

- `src/bin/*` 仅依赖 `codex_app_server_protocol` 对外 API（`lib.rs` re-export）。
- 实际逻辑集中在：
  - `export.rs`（生成、过滤、打包）
  - `schema_fixtures.rs`（目录清理、fixture 读写）
  - `protocol/common.rs` + `experimental_api.rs`（experimental 元数据来源）

### 外部库/系统交互

- `clap`：参数解析。
- `ts-rs`：TS 类型导出。
- `schemars`：JSON Schema 生成。
- `serde_json`：bundle 构造与 JSON 重写。
- `inventory`：收集 `ExperimentalField`。
- `std::process::Command`：可选调用 `prettier --write`（`src/export.rs:165-179`）。
- 文件系统：创建目录、遍历、删除旧产物（`src/schema_fixtures.rs:95-117`）。

### 与 Bazel / Cargo 交互

- Bazel target 通过 `test_data_extra = glob(["schema/**"])` 把 schema fixtures 作为测试数据暴露（`BUILD.bazel:3-7`）。
- 测试通过 `find_resource!` 在 runfiles 场景定位 fixtures（`tests/schema_fixtures.rs:107-133`）。

## 风险、边界与改进建议

### 风险与边界

1. `write_schema_fixtures` 的清理策略是“先删后建”，如果 `--schema-root` 指向错误目录会导致误删风险（`src/schema_fixtures.rs:95-117`）。
2. TS 过滤部分依赖字符串解析与重写（type alias/field/import），对 `ts-rs` 输出格式变化较敏感（`src/export.rs:308-398`）。
3. 出站 experimental 字段剥离目前存在硬编码（`strip_experimental_fields`），protocol 新增字段后容易漏同步（`src/protocol/v2.rs:5082-5088`）。
4. `export` bin 在仓库主流程中的可见度较低（`justfile` 未直接暴露该 bin），易与 `codex app-server generate-*` 的职责产生重叠认知。
5. 本目录二进制缺少独立集成测试；当前主要靠库级测试覆盖，CLI 参数层面的回归防护较弱。

### 改进建议

1. 给 `write_schema_fixtures` 增加 `--dry-run` 或安全路径校验（至少要求目标目录含 `typescript/` 与 `json/` 约束），降低误删概率。
2. 为 `src/bin/*` 增加最小 smoke tests（参数解析 + 调用失败信息断言），补齐入口层回归保护。
3. 将 `strip_experimental_fields` 从手写字段列表升级为基于 `ExperimentalField` 的自动剥离策略，避免 protocol 演进时漏改。
4. 在 `justfile` 或 README 中补充 `export` bin 适用场景说明（“任意输出目录导出” vs “仓库 fixtures 重生成”），降低使用歧义。
