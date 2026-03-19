# DIR `codex-rs/app-server-protocol/schema/typescript/serde_json` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/serde_json`
- 研究日期：2026-03-19
- 目录快照：当前仅 1 个生成文件 `JsonValue.ts`

## 场景与职责

该目录是 app-server 协议 TypeScript fixtures 中的“JSON 通用值桥接层”，职责非常聚焦：

1. 把 Rust 侧 `serde_json::Value` 映射为 TS 递归联合类型，供 v1/v2 协议类型复用。
2. 作为生成产物目录（非手写业务逻辑），由 `codex-app-server-protocol` 导出流程统一生成与回归校验。
3. 维持稳定 import 路径（`./serde_json/JsonValue` 或 `../serde_json/JsonValue`），避免每个协议类型重复定义 JSON 任意值。

直接证据：
- `codex-rs/app-server-protocol/schema/typescript/serde_json/JsonValue.ts:1-5`
- `codex-rs/app-server-protocol/src/protocol/v2.rs:95`（`use serde_json::Value as JsonValue;`）

## 功能点目的

1. 统一表达“可嵌套任意 JSON 值”
- `JsonValue.ts` 定义：`number | string | boolean | Array<JsonValue> | { [key in string]?: JsonValue } | null`。
- 用于配置扩展字段、动态工具参数、MCP 负载、线程 item 等“结构未知但必须 JSON 可序列化”的场景。

2. 降低 schema 与 TS 导出的耦合复杂度
- 在 `McpToolCallResult` 处明确说明：不直接使用 rmcp 的 Rust 结构，而是保留 `serde_json::Value` 以便 schema/TS 导出稳定。
- 证据：`codex-rs/app-server-protocol/src/protocol/v2.rs:4595-4601`。

3. 复用单一类型，减少协议文件冗余
- 当前 TypeScript schema 下共有 20 个文件直接 import `JsonValue`（根层 + `v2/`）。
- 示例：
  - `codex-rs/app-server-protocol/schema/typescript/Tool.ts:4-9`
  - `codex-rs/app-server-protocol/schema/typescript/v2/ThreadStartParams.ts:6,15`
  - `codex-rs/app-server-protocol/schema/typescript/v2/Config.ts:10`

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键数据结构

- 生成产物：
  - `JsonValue.ts`（唯一文件）
  - 内容是自引用递归联合，覆盖 JSON 全域值。
- Rust 源头类型：
  - `serde_json::Value`（在 v2 协议中大量作为 `JsonValue` 别名字段出现）。

### 2) 生成流程

1. `just write-app-server-schema`
- 命令入口：`justfile:81-83`
- 实际执行：`cargo run -p codex-app-server-protocol --bin write_schema_fixtures -- "$@"`

2. `write_schema_fixtures` 二进制
- 参数：`--schema-root`、`--prettier`、`--experimental`
- 实现：`codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs:6-37`

3. 写盘逻辑
- `write_schema_fixtures_with_options` 会先清空 `schema/typescript` 与 `schema/json`，再分别生成，避免旧文件残留。
- 实现：`codex-rs/app-server-protocol/src/schema_fixtures.rs:87-109`

4. TS 导出主流程
- `generate_ts_with_options` 调用 `ts-rs` 导出所有类型、过滤 experimental、生成索引、补 header、可选 prettier。
- 实现：`codex-rs/app-server-protocol/src/export.rs:105-182`

### 3) 协议与命名约定

- v2 结构体通常 `#[serde(rename_all = "camelCase")]` + `#[ts(export_to = "v2/")]`；
- 但 `serde_json::Value` 的 TS 定义放在 `typescript/serde_json/JsonValue.ts`，并被各类型通过相对路径导入。
- 注意：根 `index.ts` 不直接 re-export `serde_json/JsonValue`，消费方通常通过其它类型间接依赖，或自行按路径导入。
  - 证据：`codex-rs/app-server-protocol/schema/typescript/index.ts:3-77`

### 4) 与过滤器的兼容细节

- experimental 字段过滤会重写 TS 内容并清理无用 import。
- 有单测专门验证 intersection 场景下 `JsonValue` import 不会被误删。
- 证据：`codex-rs/app-server-protocol/src/export.rs:2634-2675`

## 关键代码路径与文件引用

目标目录与直接产物：
- `codex-rs/app-server-protocol/schema/typescript/serde_json/JsonValue.ts:1-5`

上游类型来源（被调用方）：
- `codex-rs/app-server-protocol/src/protocol/v2.rs:95`
- `codex-rs/app-server-protocol/src/protocol/v2.rs:544-551`
- `codex-rs/app-server-protocol/src/protocol/v2.rs:608-609`
- `codex-rs/app-server-protocol/src/protocol/v2.rs:743`
- `codex-rs/app-server-protocol/src/protocol/v2.rs:4595-4601`

生成与写盘链路（调用方/脚本）：
- `justfile:81-83`
- `codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs:6-37`
- `codex-rs/app-server-protocol/src/schema_fixtures.rs:78-109`
- `codex-rs/app-server-protocol/src/export.rs:105-182`

回归测试：
- `codex-rs/app-server-protocol/tests/schema_fixtures.rs:11-21`
- `codex-rs/app-server-protocol/tests/schema_fixtures.rs:53-105`
- `codex-rs/app-server-protocol/tests/schema_fixtures.rs:107-133`
- `codex-rs/app-server-protocol/src/export.rs:2634-2675`

下游消费示例（被调用方）：
- `codex-rs/app-server-protocol/schema/typescript/Tool.ts:4-9`
- `codex-rs/app-server-protocol/schema/typescript/Resource.ts:4-9`
- `codex-rs/app-server-protocol/schema/typescript/v2/ThreadStartParams.ts:6,15`
- `codex-rs/app-server-protocol/schema/typescript/v2/DynamicToolCallParams.ts:4-6`

## 依赖与外部交互

1. Rust 依赖
- `ts-rs`：生成 TS 类型文件（含 `serde_json/JsonValue.ts`）。
- `schemars` + `serde_json`：同步生成 JSON schema 与值模型。
- 配置位置：`codex-rs/app-server-protocol/Cargo.toml:13-32`

2. 外部命令/工具
- `just`：团队标准入口命令。
- 可选 `prettier`：在生成后统一格式化 TS。
  - 运行点：`codex-rs/app-server-protocol/src/export.rs:160-179`

3. 构建系统交互
- Bazel 通过 `test_data_extra = glob(["schema/**"])` 将 schema 作为测试数据注入 runfiles。
- 位置：`codex-rs/app-server-protocol/BUILD.bazel:3-7`

4. 文档流程交互
- app-server README 要求改协议后执行 schema 重生成与协议测试。
- 位置：`codex-rs/app-server/README.md:1447-1459`

## 风险、边界与改进建议

风险：
1. `JsonValue.ts` 为生成产物，手工修改会被下次生成覆盖，且会触发 fixture diff。
2. 根 `index.ts` 未导出 `JsonValue`，第三方若直接需要该类型，必须知道子路径；存在可发现性成本。
3. `JsonValue` 很宽泛，调用方若把关键字段长期保持为 `JsonValue`，会牺牲 TS 静态约束与演进可控性。

边界：
1. 本目录不承载协议语义源头；语义在 `src/protocol/**`。
2. 本目录不决定 experimental 能力是否可用；运行时能力协商由 app-server 处理。
3. 当前目录只有 1 个文件，任何扩展都应优先在上游 Rust 类型层处理，再走生成链路。

改进建议：
1. 在 `schema/typescript/index.ts` 增加 `export type { JsonValue } from "./serde_json/JsonValue";`，降低消费方路径负担（需评估兼容性与既有导入风格）。
2. 在 README 的 schema 导出章节补充“`serde_json/JsonValue` 的定位与推荐使用边界”，避免将可结构化字段长期留在弱类型。
3. 为 `JsonValue` 下游关键 payload（如 `DynamicToolCallParams.arguments`）逐步引入更强 schema（可通过 typed wrapper + `JsonValue` 兜底）以改善类型质量。
