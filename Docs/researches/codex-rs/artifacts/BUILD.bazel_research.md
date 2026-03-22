# codex-rs/artifacts/BUILD.bazel 研究文档

## 场景与职责

`BUILD.bazel` 是 Bazel 构建系统中 `codex-artifacts` crate 的构建配置文件。它定义了如何将这个 Rust crate 集成到整个项目的 Bazel 构建体系中。

该文件位于 `codex-rs/artifacts/` 目录下，与 `Cargo.toml` 共同构成该 crate 的构建配置双轨制（Bazel + Cargo）。

## 功能点目的

### 1. 加载共享构建规则

```bazel
load("//:defs.bzl", "codex_rust_crate")
```

从项目根目录的 `defs.bzl` 加载 `codex_rust_crate` 宏。这是一个自定义的 Bazel 宏，用于统一所有 Rust crate 的构建配置，确保 Bazel 和 Cargo 构建行为的一致性。

### 2. 定义 Rust Crate 构建目标

```bazel
codex_rust_crate(
    name = "artifacts",
    crate_name = "codex_artifacts",
)
```

- `name = "artifacts"`: Bazel 目标名称，用于在 Bazel 命令中引用（如 `bazel build //codex-rs/artifacts`）
- `crate_name = "codex_artifacts"`: 实际的 Rust crate 名称（下划线命名），与 `Cargo.toml` 中的 `name = "codex-artifacts"` 对应

## 具体技术实现

### 构建规则解析

`codex_rust_crate` 宏（定义于 `defs.bzl`）会自动处理以下任务：

1. **库目标生成**: 创建 `rust_library` 目标，编译 `src/lib.rs` 及其依赖模块
2. **单元测试**: 创建 `rust_test` 目标运行 `src/` 下的 `#[cfg(test)]` 测试
3. **依赖管理**: 从 `@crates` 仓库解析 Cargo 依赖并映射到 Bazel 依赖
4. **构建脚本**: 如果存在 `build.rs`，自动配置 `cargo_build_script`
5. **路径重映射**: 使用 `--remap-path-prefix` 确保 `file!()` 宏输出与 Cargo 一致

### 关键配置继承

该 crate 通过 `codex_rust_crate` 继承以下全局配置：

- **Rust Edition**: 从工作区配置继承（通常是 2021）
- **依赖解析**: 使用 `MODULE.bazel.lock` 中锁定的依赖版本
- **编译标志**: 统一的 `rustc_flags` 和 `rustc_env`
- **测试环境**: `INSTA_WORKSPACE_ROOT` 和 `INSTA_SNAPSHOT_PATH` 用于快照测试

## 关键代码路径与文件引用

### 直接依赖文件

| 文件 | 说明 |
|------|------|
| `//:defs.bzl` | 项目级 Bazel 宏定义，提供 `codex_rust_crate` |
| `@crates//:data.bzl` | 依赖数据，包含 `DEP_DATA` |
| `@crates//:defs.bzl` | 依赖定义，提供 `all_crate_deps` |

### 相关源码文件

| 文件 | 说明 |
|------|------|
| `src/lib.rs` | 库入口，导出公共 API |
| `src/client.rs` | `ArtifactsClient` 实现 |
| `src/runtime/` | Runtime 管理模块目录 |
| `src/tests.rs` | 集成测试 |

### Cargo 对应配置

| Cargo 配置 | Bazel 对应 |
|-----------|-----------|
| `Cargo.toml` | 本文件 + `defs.bzl` 宏 |
| `Cargo.lock` | `MODULE.bazel.lock` |
| `src/**/*.rs` | `native.glob(["src/**/*.rs"])` |

## 依赖与外部交互

### Bazel 工作区依赖

```
@crates//:codex_package_manager
@crates//:reqwest
@crates//:serde
@crates//:serde_json
@crates//:tempfile
@crates//:thiserror
@crates//:tokio
@crates//:url
@crates//:which
```

这些依赖通过 `all_crate_deps()` 函数自动从 `Cargo.toml` 解析并映射到 Bazel。

### 开发依赖（仅测试）

```
@crates//:flate2
@crates//:pretty_assertions
@crates//:sha2
@crates//:tar
@crates//:wiremock
@crates//:zip
```

## 风险、边界与改进建议

### 风险点

1. **命名不一致风险**: 
   - Bazel `name = "artifacts"` 与 Cargo `name = "codex-artifacts"` 与 crate 内部 `crate_name = "codex_artifacts"` 三种命名方式
   - 可能导致跨工具引用时的混淆

2. **双轨维护成本**:
   - 任何依赖变更需要同时更新 `Cargo.toml` 和 `MODULE.bazel.lock`
   - 运行 `just bazel-lock-update` 是必需的（根据 `AGENTS.md`）

3. **平台支持限制**:
   - 通过 `PackagePlatform` 仅支持 6 种平台组合
   - 不支持的平台会导致构建失败

### 边界条件

1. **文件存在性**: `codex_rust_crate` 宏依赖 `src/lib.rs` 存在，如果只有二进制目标需要特殊配置
2. **测试排除**: Windows 平台测试通过 `#[cfg(all(test, not(windows)))]` 条件排除
3. **构建脚本**: 如果添加 `build.rs`，需要同步更新 `build_script_data`

### 改进建议

1. **文档增强**: 在文件中添加注释说明 `crate_name` 与 `Cargo.toml` 的映射关系

2. **验证脚本**: 添加 CI 检查确保 `Cargo.toml` 中的 `name` 与 `BUILD.bazel` 中的 `crate_name` 一致（将连字符替换为下划线后比较）

3. **依赖显式化**: 考虑在文件中注释主要依赖的用途，便于快速理解 crate 功能

4. **平台支持扩展**: 如果未来需要支持更多平台，需要同步更新 `codex-package-manager` 中的 `PackagePlatform`

### 相关命令

```bash
# Bazel 构建
bazel build //codex-rs/artifacts

# Bazel 测试
bazel test //codex-rs/artifacts:artifacts-unit-tests

# 更新 Bazel 锁文件（依赖变更后必须执行）
just bazel-lock-update

# Cargo 构建（本地开发）
cargo build -p codex-artifacts

# Cargo 测试
cargo test -p codex-artifacts
```
