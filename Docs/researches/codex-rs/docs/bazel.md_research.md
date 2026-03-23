# Bazel in codex-rs 研究文档

## 场景与职责

本文档描述 codex-rs 项目中 Bazel 构建系统的配置和使用方式。codex-rs 是一个大型 Rust 工作空间，包含 70+ 个 crate。项目采用混合构建策略：

- **Cargo** 作为 crate 和特性的单一真相源（source of truth）
- **Bazel** 提供 hermetic builds（封闭构建）、工具链管理和跨平台产物生成

该设置截至 2026年1月仍处于实验阶段，正在稳定化过程中。

## 功能点目的

### 1. 混合构建架构

| 组件 | 职责 | 目的 |
|------|------|------|
| Cargo.toml/Cargo.lock | 定义依赖和特性 | 保持 Rust 生态兼容性 |
| MODULE.bazel | 定义 Bazel 依赖和 Rust 工具链 | 提供封闭构建环境 |
| rules_rs | 从 Cargo 文件导入第三方 crate | 桥接 Cargo 和 Bazel |
| defs.bzl | 提供 `codex_rust_crate` 宏 | 统一 Bazel 目标配置 |
| BUILD.bazel | 每个 crate 的构建配置 | 细粒度控制编译行为 |

### 2. 核心功能

- **Hermetic Builds**: 确保构建可重现，不受外部环境变化影响
- **跨平台支持**: 支持 Linux (arm64/amd64)、macOS (arm64/amd64)、Windows (arm64/amd64)
- **工具链管理**: 通过 Bzlmod 管理 Rust 工具链（当前使用 Rust 1.93.0, Edition 2024）
- **多平台二进制文件生成**: 通过 `multiplatform_binaries` 宏生成各平台产物

## 具体技术实现

### 1. 高层布局

```
MODULE.bazel          # 根模块定义，Bazel 依赖和工具链配置
MODULE.bazel.lock     # Bzlmod 锁定文件
defs.bzl              # codex_rust_crate 宏定义
codex-rs/
├── Cargo.toml        # Workspace 定义
├── Cargo.lock        # 依赖锁定
├── BUILD.bazel       # 导出文件配置
└── */BUILD.bazel     # 各 crate 的构建配置
```

### 2. MODULE.bazel 关键配置

```starlark
# 模块定义
module(name = "codex")

# 平台依赖
bazel_dep(name = "platforms", version = "1.0.0")
bazel_dep(name = "rules_rs", version = "0.0.43")

# Rust 工具链配置
rules_rust = use_extension("@rules_rs//rs/experimental:rules_rust.bzl", "rules_rust")
toolchains = use_extension("@rules_rs//rs/experimental/toolchains:module_extension.bzl", "toolchains")
toolchains.toolchain(
    edition = "2024",
    version = "1.93.0",
)

# 从 Cargo 导入 crate
crate = use_extension("@rules_rs//rs:extensions.bzl", "crate")
crate.from_cargo(
    cargo_lock = "//codex-rs:Cargo.lock",
    cargo_toml = "//codex-rs:Cargo.toml",
    platform_triples = [
        "aarch64-unknown-linux-gnu",
        "aarch64-unknown-linux-musl",
        "aarch64-apple-darwin",
        # ... 更多平台
    ],
)
```

### 3. codex_rust_crate 宏

位于 `defs.bzl`，封装了 `rust_library`、`rust_binary` 和 `rust_test`，提供：

- 自动检测 `src/` 目录下的源文件
- 构建脚本支持（build.rs）
- 单元测试和集成测试目标自动生成
- `CARGO_BIN_EXE_*` 环境变量设置（用于集成测试）
- 路径重映射（使 Insta 快照测试与 Cargo 兼容）

关键参数：
- `crate_name`: Cargo crate 名称
- `crate_features`: 启用的特性
- `build_script_data`: 构建脚本数据依赖
- `compile_data`: 编译时数据文件
- `test_tags`: 测试标签（如 `no-sandbox`）
- `extra_binaries`: 额外的二进制文件依赖

### 4. 典型 BUILD.bazel 结构

```starlark
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "core",
    crate_name = "codex_core",
    compile_data = ["config.schema.json"],  # 编译时数据
    test_tags = ["no-sandbox"],  # 特殊测试标签
)
```

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 作用 |
|----------|------|
| `/home/sansha/Github/codex/MODULE.bazel` | Bazel 模块定义，依赖和工具链配置 |
| `/home/sansha/Github/codex/MODULE.bazel.lock` | Bzlmod 锁定文件，确保依赖可重现 |
| `/home/sansha/Github/codex/defs.bzl` | `codex_rust_crate` 宏定义 |
| `/home/sansha/Github/codex/codex-rs/Cargo.toml` | Rust Workspace 定义 |
| `/home/sansha/Github/codex/codex-rs/BUILD.bazel` | 根 BUILD 文件 |
| `/home/sansha/Github/codex/codex-rs/*/BUILD.bazel` | 各 crate 的构建配置（77个） |

### 相关脚本

- `just bazel-lock-update`: 更新 MODULE.bazel.lock
- `just bazel-lock-check`: 验证锁定文件一致性（CI 使用）

### 模板文件

- `workspace_root_test_launcher.sh.tpl`: Unix 测试启动器模板
- `workspace_root_test_launcher.bat.tpl`: Windows 测试启动器模板

## 依赖与外部交互

### 1. Bazel 依赖

```starlark
# 核心依赖
bazel_dep(name = "platforms", version = "1.0.0")
bazel_dep(name = "llvm", version = "0.6.7")           # LLVM 工具链
bazel_dep(name = "apple_support", version = "2.1.0")  # macOS 支持
bazel_dep(name = "rules_cc", version = "0.2.16")
bazel_dep(name = "rules_platform", version = "0.1.0")
bazel_dep(name = "rules_rs", version = "0.0.43")      # Rust 规则

# 系统库依赖
bazel_dep(name = "zstd", version = "1.5.7")
bazel_dep(name = "bzip2", version = "1.0.8.bcr.3")
bazel_dep(name = "zlib", version = "1.3.1.bcr.8")
bazel_dep(name = "openssl", version = "3.5.4.bcr.0")
bazel_dep(name = "alsa_lib", version = "1.2.9.bcr.4")
bazel_dep(name = "libcap", version = "2.27.bcr.1")
```

### 2. Crate 注解

为特定 crate 提供自定义构建配置：

```starlark
# zstd-sys: 使用外部 zstd 库
crate.annotation(
    crate = "zstd-sys",
    gen_build_script = "off",
    deps = ["@zstd"],
)

# openssl-sys: 使用外部 OpenSSL
crate.annotation(
    crate = "openssl-sys",
    build_script_env = {
        "OPENSSL_DIR": "$(execpath @openssl//:gen_dir)",
        "OPENSSL_NO_VENDOR": "1",
        "OPENSSL_STATIC": "1",
    },
)

# coreaudio-sys: macOS 音频支持
crate.annotation(
    crate = "coreaudio-sys",
    build_script_env = {
        "COREAUDIO_SDK_PATH": "$(location @macos_sdk//sysroot)",
    },
)
```

### 3. 与 Cargo 的交互

- `crate.from_cargo()` 从 `Cargo.toml` 和 `Cargo.lock` 导入依赖
- 依赖变更时需要同时更新 Cargo.lock 和 MODULE.bazel.lock
- `DEP_DATA` 从 `@crates//:data.bzl` 导入，包含二进制文件信息

## 风险、边界与改进建议

### 当前风险

1. **实验性状态**: 截至 2026年1月，Bazel 设置仍在稳定化过程中
2. **沙箱嵌套限制**: 使用 Seatbelt 的测试需要 `test_tags = ["no-sandbox"]`，因为沙箱不能嵌套
3. **平台特定问题**: 某些上游 crate 需要 patch 或 annotation 才能在 Bazel 沙箱中构建
4. **Windows ARM64**: lzma-sys 的注解暂时禁用，需要修复 Windows arm64 构建

### 边界条件

1. **测试标签**: `no-sandbox` 标签会扩大影响范围，建议将此类测试隔离到单独的 crate
2. **锁定文件同步**: 必须同时更新 Cargo.lock 和 MODULE.bazel.lock，否则 CI 会失败
3. **构建脚本数据**: Bazel 不会自动将源树文件提供给编译时 Rust 文件访问，需要手动配置 `compile_data` 或 `build_script_data`

### 改进建议

1. **稳定化**: 继续完善 Bazel 设置，移除实验性标记
2. **文档完善**: 为常见自定义场景（如添加新 crate、处理特殊依赖）提供更多示例
3. **CI 集成**: 强化 `just bazel-lock-check` 检查，确保锁定文件一致性
4. **跨平台测试**: 增加更多平台的 CI 测试覆盖
5. **沙箱优化**: 研究减少 `no-sandbox` 测试数量的方法，提高构建隔离性

### 相关参考

- Bazel 概览: https://bazel.build/
- Bzlmod 模块系统: https://bazel.build/external/overview
- rules_rust: https://github.com/bazelbuild/rules_rust
- rules_rs: https://github.com/bazelbuild/rules_rs
