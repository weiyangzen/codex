# BUILD.bazel 研究文档

## 场景与职责

该文件是 `codex-rs/utils/cache` crate 的 Bazel 构建配置文件，负责定义 Rust 缓存工具库的构建规则。它是 Bazel 构建系统中用于编译 `codex-utils-cache` crate 的入口点。

## 功能点目的

1. **加载构建规则**: 从项目根目录加载 `defs.bzl` 中定义的 `codex_rust_crate` 宏
2. **定义构建目标**: 使用 `codex_rust_crate` 宏创建名为 `cache` 的 Rust 库目标
3. **指定 crate 名称**: 将 crate 名称设置为 `codex_utils_cache`（遵循 AGENTS.md 中规定的 `codex-` 前缀约定）

## 具体技术实现

### 构建规则结构

```bazel
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "cache",
    crate_name = "codex_utils_cache",
)
```

### 关键流程

1. **宏加载**: 通过 `load("//:defs.bzl", "codex_rust_crate")` 导入自定义宏
2. **目标创建**: 调用 `codex_rust_crate` 宏，传入：
   - `name`: Bazel 目标名称（目录名）
   - `crate_name`: Cargo crate 名称（带 `codex_` 前缀）

### 底层构建逻辑（defs.bzl 中 codex_rust_crate 宏）

根据 `defs.bzl` 的内容，`codex_rust_crate` 宏执行以下操作：

1. **库源文件收集**: 使用 `native.glob(["src/**/*.rs"])` 收集所有 Rust 源文件
2. **构建脚本处理**: 如果存在 `build.rs`，创建构建脚本目标
3. **库规则创建**: 使用 `rust_library` 创建库目标
4. **单元测试创建**: 创建单元测试二进制文件和 workspace 根测试启动器
5. **二进制文件处理**: 处理 `DEP_DATA` 中定义的二进制文件
6. **集成测试**: 为 `tests/*.rs` 中的每个测试文件创建集成测试目标

## 关键代码路径与文件引用

### 直接依赖文件
- `//:defs.bzl` - 包含 `codex_rust_crate` 宏定义
- `codex-rs/utils/cache/src/lib.rs` - 库源代码
- `codex-rs/utils/cache/Cargo.toml` - Cargo 配置（依赖解析来源）

### 间接依赖（通过 defs.bzl）
- `@crates//:data.bzl` - 依赖数据（`DEP_DATA`）
- `@crates//:defs.bzl` - crate 依赖解析
- `@rules_rust//rust:defs.bzl` - Rust 规则（`rust_library`, `rust_binary`, `rust_test`）
- `@rules_rust//cargo/private:cargo_build_script_wrapper.bzl` - 构建脚本支持

### 生成的目标
- `:cache` - 主库目标
- `:cache-unit-tests-bin` - 单元测试二进制
- `:cache-unit-tests` - 单元测试启动器

## 依赖与外部交互

### Bazel 外部依赖
| 依赖 | 用途 |
|------|------|
| `@crates` | 解析 Cargo 依赖（通过 `all_crate_deps()`） |
| `@rules_rust` | Rust 编译规则 |
| `@rules_platform` | 平台数据规则 |

### Cargo 依赖（通过 Cargo.toml）
| Crate | 用途 |
|-------|------|
| `lru` | LRU 缓存实现 |
| `sha1` | SHA-1 哈希计算 |
| `tokio` | 异步运行时支持 |

### 调用方
- `codex-rs/utils/image/BUILD.bazel` - 图像处理库依赖
- `codex-rs/core/BUILD.bazel` - 核心库依赖

## 风险、边界与改进建议

### 风险

1. **依赖版本漂移**: 依赖通过 `@crates` 外部仓库解析，需确保 `MODULE.bazel.lock` 与 `Cargo.lock` 同步
2. **构建脚本支持**: 当前配置未显式禁用构建脚本，如果添加 `build.rs` 会自动启用，可能影响构建性能

### 边界

1. **单一配置**: 根据 `defs.bzl` 注释，crate 在整个工作区以单一配置编译（启用所有 `crate_features`）
2. **平台支持**: 继承项目标准平台列表（Linux arm64/amd64 musl, macOS amd64/arm64, Windows amd64/arm64）

### 改进建议

1. **显式源文件**: 考虑显式指定 `crate_srcs` 而非依赖 glob，提高构建可重现性
2. **文档注释**: 添加模块级文档说明缓存库的用途
3. **测试标签**: 如有特殊测试需求（如禁用沙箱），可添加 `test_tags` 参数
4. **功能标志**: 如果某些功能是可选的，考虑添加 `crate_features` 参数

### 与 Cargo 的互操作性

该 Bazel 配置与 Cargo 配置（`Cargo.toml`）保持同步：
- `crate_name = "codex_utils_cache"` 对应 `Cargo.toml` 中的 `name = "codex-utils-cache"`（Bazel 使用下划线，Cargo 使用连字符）
- 依赖版本通过 workspace 统一管理
