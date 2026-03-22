# BUILD.bazel 研究文档

## 场景与职责

该文件是 Bazel 构建系统中用于定义 `app-server` 测试通用支持库（test support library）的构建配置。它位于 `codex-rs/app-server/tests/common/` 目录下，负责将测试支持代码打包成一个独立的 Rust crate，供同目录下的其他测试模块使用。

## 功能点目的

1. **定义 Rust Crate 构建规则**：使用项目自定义的 `codex_rust_crate` 宏来声明一个 Rust crate
2. **指定 Crate 名称**：将 crate 名称设置为 `app_test_support`，这是其他测试代码引用该库时使用的名称
3. **自动收集源文件**：使用 `glob(["*.rs"])` 自动包含目录下所有 `.rs` 文件作为源码

## 具体技术实现

### 关键配置

```bazel
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "common",
    crate_name = "app_test_support",
    crate_srcs = glob(["*.rs"]),
)
```

| 配置项 | 值 | 说明 |
|--------|-----|------|
| `name` | `"common"` | Bazel 目标名称 |
| `crate_name` | `"app_test_support"` | Rust crate 名称，用于 `use app_test_support::...` |
| `crate_srcs` | `glob(["*.rs"])` | 自动收集所有 Rust 源文件 |

### 与 Cargo.toml 的对应关系

该 Bazel 配置与 `Cargo.toml` 中的配置相对应：
- `crate_name = "app_test_support"` 对应 `Cargo.toml` 中的 `name = "app_test_support"`
- `glob(["*.rs"])` 对应 `Cargo.toml` 中的 `path = "lib.rs"`（lib.rs 通过 mod 声明引入其他文件）

## 关键代码路径与文件引用

- **当前文件**: `codex-rs/app-server/tests/common/BUILD.bazel`
- **对应的 Cargo 配置**: `codex-rs/app-server/tests/common/Cargo.toml`
- **库入口文件**: `codex-rs/app-server/tests/common/lib.rs`
- **被引用的构建宏**: `//:defs.bzl`（项目根目录的 Bazel 定义文件）

## 依赖与外部交互

### 上游依赖（构建时）
- `//:defs.bzl` - 项目自定义的 Bazel 宏定义，提供 `codex_rust_crate` 函数

### 下游使用者
该 crate 被以下测试文件引用（通过 `use app_test_support::...`）：
- `codex-rs/app-server/tests/suite/v2/*.rs` - 所有 v2 API 测试套件
- `codex-rs/app-server/tests/suite/auth.rs`
- `codex-rs/app-server/tests/suite/conversation_summary.rs`
- `codex-rs/app-server/tests/suite/fuzzy_file_search.rs`

## 风险、边界与改进建议

### 风险
1. **glob 模式风险**：使用 `glob(["*.rs"])` 可能意外包含不需要的源文件，如果目录结构变化需要谨慎
2. **命名一致性**：Bazel 的 `name = "common"` 与 crate 名称 `app_test_support` 不一致，可能导致混淆

### 边界
- 该配置仅适用于 Bazel 构建系统，不影响 Cargo 构建
- 需要与 `Cargo.toml` 保持同步，否则可能导致两种构建系统的行为差异

### 改进建议
1. **显式源文件列表**：考虑将 `glob(["*.rs"])` 替换为显式文件列表，提高可预测性
2. **统一命名**：考虑将 Bazel target 名称与 crate 名称统一，减少认知负担
3. **添加文档注释**：在 BUILD 文件中添加更多注释说明该 crate 的用途
