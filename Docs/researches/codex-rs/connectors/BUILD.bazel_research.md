# BUILD.bazel 研究文档

## 场景与职责

该文件是 `codex-rs/connectors` crate 的 Bazel 构建配置文件，定义了如何将 Rust 源代码编译为可重用的库 crate。它是 Bazel 构建系统与 Cargo 构建系统之间的桥梁，确保该 crate 可以被其他 Bazel 目标依赖。

## 功能点目的

### 1. 加载构建规则
```starlark
load("//:defs.bzl", "codex_rust_crate")
```
从项目根目录的 `defs.bzl` 加载自定义的 `codex_rust_crate` 宏，该宏封装了 Rust crate 的标准构建配置。

### 2. 定义 Crate 目标
```starlark
codex_rust_crate(
    name = "connectors",
    crate_name = "codex_connectors",
)
```
- `name`: Bazel 目标名称，用于在 Bazel 依赖图中引用
- `crate_name`: 实际的 Rust crate 名称（使用下划线），对应 `Cargo.toml` 中的 `name = "codex-connectors"`

## 具体技术实现

### 构建规则宏 `codex_rust_crate`

该宏定义在 `/home/sansha/Github/codex/defs.bzl` 中，提供以下功能：

1. **库规则创建**: 使用 `rust_library` 或 `rust_proc_macro` 创建库目标
2. **单元测试**: 自动生成单元测试目标（`{name}-unit-tests`）
3. **二进制文件**: 如果存在 `src/main.rs` 或其他二进制文件，自动创建 `rust_binary` 目标
4. **集成测试**: 自动发现 `tests/*.rs` 文件并创建对应的测试目标
5. **依赖管理**: 通过 `all_crate_deps()` 从 `@crates` 仓库解析 Cargo 依赖

### 关键配置

- **源码 glob**: `src/**/*.rs`（自动发现所有 Rust 源文件）
- **版本**: 从 `DEP_DATA` 读取，默认 `0.0.0`
- **可见性**: `//visibility:public`（允许任何包依赖）

## 关键代码路径与文件引用

| 路径 | 说明 |
|------|------|
| `//:defs.bzl` | 定义 `codex_rust_crate` 宏 |
| `@crates//:defs.bzl` | 提供 `all_crate_deps()` 依赖解析 |
| `@crates//:data.bzl` | 提供 `DEP_DATA` 依赖数据 |
| `codex-rs/connectors/Cargo.toml` | Cargo 元数据和依赖声明 |
| `codex-rs/connectors/src/lib.rs` | 主库源文件 |

## 依赖与外部交互

### Bazel 外部依赖
- `@rules_rust//rust:defs.bzl`: Rust 规则集
- `@rules_platform//platform_data:defs.bzl`: 平台数据规则
- `@crates`: 通过 `crate_universe` 生成的外部 crate 仓库

### 内部依赖（通过 Cargo.toml）
- `codex-app-server-protocol`: 提供 `AppInfo`, `AppBranding`, `AppMetadata` 等类型
- `anyhow`: 错误处理
- `serde`: 序列化/反序列化
- `urlencoding`: URL 编码

### 反向依赖（使用该 crate 的模块）
- `codex-rs/core`: 核心逻辑，通过 `codex_core::connectors` 重新导出部分功能
- `codex-rs/chatgpt`: ChatGPT 客户端，调用 `codex_connectors` 的 API

## 风险、边界与改进建议

### 风险

1. **缓存过期**: 全局静态缓存 `ALL_CONNECTORS_CACHE` 使用 `StdMutex`，在极端并发场景下可能产生竞争条件
2. **Poison Error 处理**: 使用 `unwrap_or_else(std::sync::PoisonError::into_inner)` 处理 mutex poison，可能掩盖真正的并发问题

### 边界

1. **单 crate 配置**: `codex_rust_crate` 宏假设每个目录只有一个 crate，不支持一个目录多个 crate 的场景
2. **Bazel/Cargo 双构建**: 需要同时维护 `Cargo.toml` 和 `BUILD.bazel`，存在配置漂移风险
3. **平台限制**: 通过 `platform_data` 支持多平台，但某些平台特定的代码可能需要条件编译

### 改进建议

1. **统一构建配置**: 考虑使用 `cargo-bazel` 自动生成 `BUILD.bazel` 文件，减少手动维护
2. **缓存策略优化**: 考虑使用 `tokio::sync::RwLock` 替代 `StdMutex` 以获得更好的异步性能
3. **测试覆盖率**: 当前 BUILD.bazel 生成的测试目标使用 `tags = ["manual"]`，需要显式运行，建议添加 CI 检查确保测试被执行
4. **文档生成**: 可以添加 `rust_doc` 目标自动生成文档并发布

## 相关测试命令

```bash
# Bazel 构建
bazel build //codex-rs/connectors:connectors

# 运行单元测试
bazel test //codex-rs/connectors:connectors-unit-tests

# Cargo 构建（开发时使用）
cargo build -p codex-connectors

# Cargo 测试
cargo test -p codex-connectors
```
