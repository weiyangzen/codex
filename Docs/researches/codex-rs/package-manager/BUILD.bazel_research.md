# codex-rs/package-manager/BUILD.bazel 研究文档

## 场景与职责

`BUILD.bazel` 是 Bazel 构建系统对 `codex-package-manager` crate 的构建配置声明文件。它位于 `codex-rs/package-manager/` 目录下，负责将该 Rust 库注册为 Bazel 工作空间中的可构建目标。

该文件的核心职责：
- 声明 `codex-package-manager` crate 作为 Bazel 构建目标
- 通过 `codex_rust_crate` 宏标准化 Rust crate 的构建配置
- 建立与 workspace 级别依赖（`@crates`）的链接

## 功能点目的

### 1. 加载构建规则宏

```bazel
load("//:defs.bzl", "codex_rust_crate")
```

从项目根目录的 `defs.bzl` 加载 `codex_rust_crate` 宏。该宏封装了 Rust 库、单元测试、集成测试的完整构建逻辑，确保 Cargo 和 Bazel 构建行为一致。

### 2. 声明 crate 构建目标

```bazel
codex_rust_crate(
    name = "package-manager",
    crate_name = "codex_package_manager",
)
```

| 参数 | 值 | 说明 |
|------|-----|------|
| `name` | `"package-manager"` | Bazel 目标名称，用于命令行引用（如 `bazel build //codex-rs/package-manager`） |
| `crate_name` | `"codex_package_manager"` | 编译后的 Rust crate 名称（下划线命名规范） |

## 具体技术实现

### codex_rust_crate 宏的行为

根据 `defs.bzl` 的实现，`codex_rust_crate` 宏会：

1. **自动发现源码文件**：通过 `native.glob(["src/**/*.rs"])` 自动收集所有 Rust 源文件
2. **处理 build.rs**：如果存在 `build.rs`，自动创建 cargo_build_script 目标
3. **创建库目标**：使用 `rust_library` 规则创建 `codex_package_manager` 库
4. **创建单元测试**：生成 `{name}-unit-tests` 目标，使用 Insta 进行快照测试
5. **处理二进制文件**：如果 `Cargo.toml` 定义了 `[[bin]]`，创建对应的 `rust_binary` 目标
6. **集成测试**：自动发现并构建 `tests/*.rs` 中的集成测试

### 依赖解析

依赖通过 `@crates` 外部仓库解析，该仓库由 `MODULE.bazel` 中的 `crate.from_cargo` 生成，基于 `codex-rs/Cargo.lock` 锁定依赖版本。

运行时依赖（来自 `Cargo.toml`）：
- `fd-lock` - 文件锁实现
- `flate2` - gzip 压缩/解压
- `reqwest` - HTTP 客户端
- `serde` - 序列化/反序列化
- `sha2` - SHA-256 哈希
- `tar` - tar 归档处理
- `tempfile` - 临时文件/目录
- `thiserror` - 错误处理宏
- `tokio` - 异步运行时
- `url` - URL 解析
- `zip` - zip 归档处理

## 关键代码路径与文件引用

```
codex-rs/package-manager/
├── BUILD.bazel          # 本文件：Bazel 构建配置
├── Cargo.toml           # Cargo 包配置和依赖声明
├── src/
│   ├── lib.rs           # 库入口，模块声明和公共导出
│   ├── archive.rs       # 归档提取、校验和验证
│   ├── config.rs        # PackageManagerConfig 配置结构
│   ├── error.rs         # PackageManagerError 错误枚举
│   ├── manager.rs       # PackageManager 核心实现
│   ├── package.rs       # ManagedPackage trait 定义
│   ├── platform.rs      # PackagePlatform 平台检测
│   └── tests.rs         # 单元测试和集成测试
```

## 依赖与外部交互

### 内部依赖

| 依赖路径 | 用途 |
|----------|------|
| `//:defs.bzl` | 提供 `codex_rust_crate` 宏 |
| `@crates//:data.bzl` | 提供 `DEP_DATA` 依赖数据 |
| `@crates//:defs.bzl` | 提供 `all_crate_deps` 函数 |

### 外部 Bazel 规则

| 规则仓库 | 用途 |
|----------|------|
| `@rules_rust//rust:defs.bzl` | 提供 `rust_library`, `rust_binary`, `rust_test` |
| `@rules_rust//cargo/private:cargo_build_script_wrapper.bzl` | 提供 `cargo_build_script` |
| `@rules_platform//platform_data:defs.bzl` | 提供 `platform_data` 用于多平台构建 |

### 消费者

`codex-package-manager` 被以下 crate 依赖：
- `codex-rs/artifacts` - 用于管理 Artifact Runtime（JS 运行时）的下载和安装

## 风险、边界与改进建议

### 风险

1. **依赖版本漂移**：`@crates` 仓库基于 `Cargo.lock` 生成，如果 `Cargo.toml` 修改后未运行 `just bazel-lock-update`，Bazel 构建可能使用旧版本依赖
2. **路径分隔符**：`default_cache_root_relative()` 返回的路径使用 `/`，在 Windows 上通过 `replace('/', std::path::MAIN_SEPARATOR_STR)` 转换，需确保该逻辑在所有调用点一致

### 边界

1. **无自定义编译数据**：该 crate 未使用 `compile_data` 或 `build_script_data` 参数，说明没有编译时文件包含需求
2. **无额外二进制文件**：未定义 `extra_binaries`，该 crate 仅作为库使用
3. **测试标签**：可通过 `test_tags` 参数添加 Bazel 标签（如禁用沙箱），当前保持默认

### 改进建议

1. **显式声明 srcs**：当前使用 `native.glob` 自动发现源文件，虽然方便但可能导致增量构建的不确定性。建议考虑显式列出关键源文件：
   ```bazel
   codex_rust_crate(
       name = "package-manager",
       crate_name = "codex_package_manager",
       crate_srcs = [
           "src/lib.rs",
           "src/archive.rs",
           "src/config.rs",
           "src/error.rs",
           "src/manager.rs",
           "src/package.rs",
           "src/platform.rs",
       ],
   )
   ```

2. **添加文档生成目标**：可以添加 `rust_doc` 目标自动生成 API 文档：
   ```bazel
   load("@rules_rust//rust:defs.bzl", "rust_doc")
   
   rust_doc(
       name = "package-manager-docs",
       crate = ":package-manager",
   )
   ```

3. **考虑 feature flags**：如果某些依赖（如 `zip` 或 `tar`）在特定场景下不需要，可以通过 Cargo features 使其可选，减少编译时间和二进制大小
