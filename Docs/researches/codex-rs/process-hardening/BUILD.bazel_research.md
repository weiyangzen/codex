# BUILD.bazel 研究文档

## 场景与职责

该文件是 Bazel 构建系统的构建定义文件，位于 `codex-rs/process-hardening` 目录下。它定义了 `codex-process-hardening` crate 的 Bazel 构建规则，使该 Rust 库能够被 Bazel 构建系统正确编译和链接。

## 功能点目的

1. **加载构建规则宏**：从项目根目录的 `defs.bzl` 加载 `codex_rust_crate` 宏
2. **定义 Rust crate 目标**：使用 `codex_rust_crate` 宏创建标准化的 Rust 库构建目标
3. **统一构建配置**：确保该 crate 遵循与项目中其他 Rust crate 一致的构建约定

## 具体技术实现

### 构建规则定义

```starlark
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "process-hardening",
    crate_name = "codex_process_hardening",
)
```

### 关键参数说明

| 参数 | 值 | 说明 |
|------|-----|------|
| `name` | `"process-hardening"` | Bazel 目标名称，用于命令行引用（如 `bazel build //codex-rs/process-hardening:process-hardening`） |
| `crate_name` | `"codex_process_hardening"` | Rust crate 名称，对应 `Cargo.toml` 中的 `lib.name`，生成 `libcodex_process_hardening.rlib` |

### codex_rust_crate 宏行为

根据 `defs.bzl` 中的定义，`codex_rust_crate` 宏会：

1. **自动发现源码**：使用 `native.glob(["src/**/*.rs"])` 自动收集 `src` 目录下的所有 Rust 源文件
2. **创建库目标**：使用 `rust_library` 规则创建 Rust 库
3. **处理依赖**：通过 `all_crate_deps()` 从 `@crates` 解析 Cargo.lock 中的依赖
4. **生成测试目标**：自动创建单元测试和集成测试目标
5. **设置可见性**：`visibility = ["//visibility:public"]` 使该库可被工作空间内其他目标依赖

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/process-hardening/BUILD.bazel` - 本构建定义文件

### 依赖的构建规则
- `//:defs.bzl` - 项目级 Bazel 宏定义，包含 `codex_rust_crate` 函数

### 相关的 Cargo 配置
- `codex-rs/process-hardening/Cargo.toml` - Cargo 包配置，定义 crate 元数据和依赖
- `codex-rs/Cargo.toml` - 工作空间配置，定义 `codex-process-hardening` 的路径映射
- `codex-rs/Cargo.lock` - 依赖锁定文件

### 源码文件
- `codex-rs/process-hardening/src/lib.rs` - 库的主要源代码

## 依赖与外部交互

### Bazel 外部依赖

通过 `defs.bzl` 中的 `all_crate_deps()` 函数，该 crate 的依赖来自：
- `@crates//:data.bzl` - 包含 `DEP_DATA` 依赖数据
- `@crates//:defs.bzl` - 包含 `all_crate_deps` 函数

### Cargo 依赖（通过 Bazel 桥接）

根据 `Cargo.toml`，该 crate 的依赖包括：
- `libc` (workspace = true) - 用于系统调用（prctl, ptrace, setrlimit 等）

### 被依赖方

该库被以下组件使用：
- `codex-rs/responses-api-proxy` - 在 `main.rs` 中通过 `#[ctor::ctor]` 调用 `pre_main_hardening()`

## 风险、边界与改进建议

### 风险

1. **平台特定代码的构建复杂性**：该 crate 包含大量条件编译代码（`#[cfg(...)]`），Bazel 构建需要正确处理不同目标平台的条件编译

2. **unsafe 代码依赖**：库内部使用 `libc` crate 进行系统调用，这些调用标记为 `unsafe`，需要确保在正确的平台上执行

### 边界

1. **Windows 支持不完整**：`pre_main_hardening_windows()` 函数目前为空实现（TODO），在 Windows 平台上不会执行任何加固操作

2. **构建脚本**：该 crate 没有 `build.rs`，因此 `codex_rust_crate` 宏不会创建构建脚本目标

### 改进建议

1. **添加平台特定测试标签**：考虑为不同平台添加测试标签，以便在 CI 中正确运行平台特定的测试

2. **文档生成**：可以添加 `rust_doc` 目标来生成 API 文档

3. **Windows 实现**：完成 `pre_main_hardening_windows()` 的实现，并添加相应的 Windows 平台测试

4. **依赖分析**：考虑使用 `cargo-shear` 等工具定期检查未使用的依赖
