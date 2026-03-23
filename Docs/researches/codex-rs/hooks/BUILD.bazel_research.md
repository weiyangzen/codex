# BUILD.bazel 研究文档

## 场景与职责

该文件是 `codex-hooks` crate 的 Bazel 构建配置，负责定义 Rust 库的构建规则。它位于 `codex-rs/hooks/` 目录下，是整个 hooks 模块的构建入口点。

## 功能点目的

### 1. 加载构建规则
```bazel
load("//:defs.bzl", "codex_rust_crate")
```
从项目根目录加载自定义的 `codex_rust_crate` 宏，该宏封装了 Rust crate 的标准构建配置。

### 2. 收集 Schema 文件
```bazel
SCHEMA_FIXTURES = glob(["schema/generated/*.json"], allow_empty = False)
```
- 收集所有生成的 JSON Schema 文件（位于 `schema/generated/` 目录）
- `allow_empty = False` 确保至少存在一个 schema 文件，防止配置错误
- 这些 schema 文件定义了 hooks 的输入/输出数据结构

### 3. 定义 Rust Crate
```bazel
codex_rust_crate(
    name = "hooks",
    crate_name = "codex_hooks",
    compile_data = SCHEMA_FIXTURES,
    integration_compile_data_extra = SCHEMA_FIXTURES,
    test_data_extra = SCHEMA_FIXTURES,
)
```
- **name**: Bazel 目标名称 `"hooks"`
- **crate_name**: Rust crate 名称 `"codex_hooks"`（遵循 AGENTS.md 中定义的 `codex-` 前缀规范）
- **compile_data**: 编译时数据，schema 文件会被嵌入到二进制中（通过 `include_str!`）
- **integration_compile_data_extra**: 集成测试编译时额外数据
- **test_data_extra**: 测试时额外数据

## 具体技术实现

### Schema 文件用途
被收集的 schema 文件包括：
1. `session-start.command.input.schema.json` - SessionStart 事件输入 schema
2. `session-start.command.output.schema.json` - SessionStart 事件输出 schema
3. `user-prompt-submit.command.input.schema.json` - UserPromptSubmit 事件输入 schema
4. `user-prompt-submit.command.output.schema.json` - UserPromptSubmit 事件输出 schema
5. `stop.command.input.schema.json` - Stop 事件输入 schema
6. `stop.command.output.schema.json` - Stop 事件输出 schema

这些 schema 在代码中被 `schema_loader.rs` 使用 `include_str!` 宏嵌入：
```rust
include_str!("../../schema/generated/session-start.command.input.schema.json")
```

### 依赖关系
- 依赖项目根目录的 `defs.bzl` 中定义的 `codex_rust_crate` 宏
- 该宏进一步封装了 `rules_rust` 的 `rust_library` 规则

## 关键代码路径与文件引用

| 路径 | 说明 |
|------|------|
| `//:defs.bzl` | 项目级 Bazel 宏定义 |
| `schema/generated/*.json` | 生成的 JSON Schema 文件 |
| `src/schema.rs` | 使用 schema 文件生成和验证 |
| `src/engine/schema_loader.rs` | 运行时加载嵌入的 schema |

## 依赖与外部交互

### 内部依赖
- `defs.bzl` 中的 `codex_rust_crate` 宏
- `schema/generated/` 目录下的 JSON 文件

### 外部依赖（通过 Cargo.toml）
- `codex-config`: 配置层栈支持
- `codex-protocol`: 协议类型定义
- `schemars`: JSON Schema 生成
- `serde`/`serde_json`: 序列化

## 风险、边界与改进建议

### 风险
1. **Schema 文件缺失**: `allow_empty = False` 会在 schema 文件缺失时导致构建失败，这有助于及早发现问题
2. **路径硬编码**: schema 文件路径在 Bazel 和 Rust 代码中都有硬编码，修改时需要同步更新

### 边界
1. 该配置仅适用于 `codex-rs/hooks` crate
2. Schema 文件必须通过 `just write-hooks-schema` 或类似命令生成
3. Bazel 和 Cargo 构建需要保持 schema 文件的一致性

### 改进建议
1. **自动生成检查**: 添加 CI 检查确保 schema 文件与代码同步
2. **路径集中管理**: 考虑将 schema 文件路径集中定义，避免分散在多处
3. **文档化**: 在 BUILD.bazel 中添加注释说明 schema 文件的生成方式
