# BUILD.bazel 研究文档

## 文件信息
- **路径**: `codex-rs/utils/readiness/BUILD.bazel`
- **大小**: 127 bytes
- **所属 crate**: `codex-utils-readiness`

---

## 场景与职责

此 BUILD.bazel 文件是 Bazel 构建系统对 `codex-utils-readiness` crate 的构建配置。它定义了如何将 Rust 源代码编译成可重用的库 crate。

**核心职责**:
1. 声明 `codex-utils-readiness` crate 的 Bazel 构建目标
2. 通过 `codex_rust_crate` 宏统一处理 Rust crate 的标准构建流程
3. 确保与 Cargo 构建系统的互操作性

---

## 功能点目的

### 1. 加载构建规则
```bazel
load("//:defs.bzl", "codex_rust_crate")
```
从项目根目录的 `defs.bzl` 加载自定义的 `codex_rust_crate` 宏。该宏封装了 Rust crate 的标准构建逻辑，包括：
- 库编译 (`rust_library`)
- 单元测试生成 (`rust_test`)
- 构建脚本处理 (`cargo_build_script`)
- 多平台二进制文件生成

### 2. 定义构建目标
```bazel
codex_rust_crate(
    name = "readiness",
    crate_name = "codex_utils_readiness",
)
```

| 参数 | 值 | 说明 |
|------|-----|------|
| `name` | `"readiness"` | Bazel 目标名称，对应目录名 |
| `crate_name` | `"codex_utils_readiness`" | Cargo crate 名称（下划线分隔） |

---

## 具体技术实现

### 关键流程

1. **源码发现**: `codex_rust_crate` 宏通过 `native.glob(["src/**/*.rs"])` 自动发现所有 Rust 源文件
2. **依赖解析**: 从 `@crates` 工作区解析 Cargo.toml 中声明的依赖
3. **库编译**: 调用 `rust_library` 规则生成 `libreadiness.rlib`
4. **测试生成**: 自动生成单元测试目标 `readiness-unit-tests`

### 数据结构

此 BUILD 文件本身非常简单，核心逻辑在 `defs.bzl` 中：

```bazel
# defs.bzl 中的 codex_rust_crate 宏关键逻辑
def codex_rust_crate(name, crate_name, ...):
    # 1. 处理构建脚本 (build.rs)
    if build_script_enabled and native.glob(["build.rs"], allow_empty=True):
        cargo_build_script(...)
    
    # 2. 编译库
    rust_library(
        name = name,
        crate_name = crate_name,
        srcs = lib_srcs,  # src/**/*.rs
        deps = all_crate_deps() + maybe_deps,
        visibility = ["//visibility:public"],
    )
    
    # 3. 生成单元测试
    rust_test(name = name + "-unit-tests-bin", ...)
    workspace_root_test(name = name + "-unit-tests", ...)
```

---

## 关键代码路径与文件引用

### 直接依赖
| 文件 | 关系 | 说明 |
|------|------|------|
| `//:defs.bzl` | 加载 | 定义 `codex_rust_crate` 宏 |
| `src/lib.rs` | 源文件 | crate 主库代码 |
| `Cargo.toml` | 元数据 | 依赖和 crate 元信息 |

### 被引用位置
- `codex-rs/core/Cargo.toml`: 依赖 `codex-utils-readiness`
- `codex-rs/Cargo.toml` (workspace): 定义 workspace 成员路径

---

## 依赖与外部交互

### Bazel 工作区依赖
- `@crates//:defs.bzl`: 提供 `all_crate_deps()` 解析 Cargo 依赖
- `@rules_rust//rust:defs.bzl`: 提供 `rust_library`, `rust_test` 等规则

### Cargo.toml 依赖映射
从 `Cargo.toml` 解析的依赖通过 `@crates` 工作区提供：
- `async-trait`
- `thiserror`
- `time`
- `tokio` (features: sync, time)

---

## 风险、边界与改进建议

### 风险
1. **路径硬编码**: `name = "readiness"` 必须与目录名一致，否则可能导致不一致
2. **无自定义配置**: 此 crate 没有特殊的构建脚本或编译数据需求，配置简单

### 边界
- 此文件仅用于 Bazel 构建，Cargo 用户直接使用 `Cargo.toml`
- 不支持 proc-macro（该 crate 是普通库）
- 无额外二进制文件（只有库）

### 改进建议
1. **文档注释**: 可添加 Bazel 目标的文档字符串：
   ```bazel
   codex_rust_crate(
       name = "readiness",
       crate_name = "codex_utils_readiness",
       # doc = "Readiness flag with token-based authorization",  # 建议添加
   )
   ```

2. **可见性控制**: 当前使用默认可见性，如需限制可显式声明：
   ```bazel
   visibility = ["//codex-rs/core:__pkg__"],  # 仅 core crate 可访问
   ```

3. **测试标签**: 如需特殊测试配置（如禁用沙箱），可添加：
   ```bazel
   test_tags = ["no-sandbox"],
   ```
