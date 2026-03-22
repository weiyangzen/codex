# BUILD.bazel 研究文档

## 场景与职责

该 BUILD.bazel 文件位于 `codex-rs/app-server-protocol/` 目录下，是 Bazel 构建系统对该 Rust crate 的构建配置。它定义了如何将 app-server-protocol 这个 Rust 库打包成可供其他模块依赖的构建目标。

## 功能点目的

1. **定义 Rust Crate 构建目标**：使用 `codex_rust_crate` 宏（定义在 `//:defs.bzl`）来声明一个 Rust crate。
2. **配置测试数据**：通过 `test_data_extra` 参数包含 `schema/**` 目录下的所有文件，这些文件是协议生成的 JSON Schema 和 TypeScript 类型定义，用于测试时验证生成的 schema 与预期一致。

## 具体技术实现

### 关键配置项

```bzl
codex_rust_crate(
    name = "app-server-protocol",
    crate_name = "codex_app_server_protocol",
    test_data_extra = glob(["schema/**"], allow_empty = True),
)
```

- `name`: Bazel 目标名称，其他模块通过 `//codex-rs/app-server-protocol:app-server-protocol` 引用
- `crate_name`: 生成的 Rust crate 名称，对应 Cargo.toml 中的 `name = "codex-app-server-protocol"`
- `test_data_extra`: 额外的测试数据，使用 glob 模式匹配 schema 目录下的所有文件

### 与 Cargo.toml 的关系

该 BUILD.bazel 与同一目录下的 Cargo.toml 协同工作：
- Cargo.toml 定义 Cargo 构建配置和依赖
- BUILD.bazel 定义 Bazel 构建配置
- 两者保持 crate 名称一致（`codex-app-server-protocol` / `codex_app_server_protocol`）

## 关键代码路径与文件引用

- **构建宏定义**: `//:defs.bzl`（项目根目录的 defs.bzl）
- **Cargo 配置**: `codex-rs/app-server-protocol/Cargo.toml`
- **测试数据目录**: `codex-rs/app-server-protocol/schema/`
  - `schema/typescript/`: 生成的 TypeScript 类型定义
  - `schema/json/`: 生成的 JSON Schema 文件

## 依赖与外部交互

### 上游依赖（由 Cargo.toml 定义）
- `codex-protocol`: 核心协议类型
- `codex-experimental-api-macros`: 实验性 API 宏
- `codex-utils-absolute-path`: 绝对路径工具
- `schemars`, `serde`, `ts-rs`: 序列化和类型生成
- `rmcp`: MCP 协议支持

### 下游使用者
- `codex-rs/app-server`: 应用服务器实现
- `codex-rs/tui`: 终端 UI 客户端
- `codex-rs/tui_app_server`: TUI 应用服务器

## 风险、边界与改进建议

### 风险
1. **Schema 文件同步**: `schema/**` 中的文件是通过 `just write-app-server-schema` 生成的，如果开发者忘记更新，测试会失败
2. **Bazel/Cargo 双构建系统**: 需要保持两者配置同步，否则可能导致构建不一致

### 边界
1. 该 crate 是纯协议定义 crate，不应包含业务逻辑
2. 所有类型必须实现 `Serialize`, `Deserialize`, `JsonSchema`, `TS` 等 trait
3. 实验性 API 需要通过 `#[experimental(...)]` 属性标记

### 改进建议
1. 考虑在 CI 中添加检查，确保 schema 文件已更新
2. 可以添加构建时检查，验证 Cargo.toml 和 BUILD.bazel 的 crate 名称一致
3. 考虑使用 Bazel 的 `write_source_files` 规则来自动管理 schema 文件的生成和更新
