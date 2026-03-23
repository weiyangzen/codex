# BUILD.bazel 研究文档

## 场景与职责

该文件是 `codex-rs/test-macros` crate 的 Bazel 构建配置，定义了如何将这个 Rust 过程宏 crate 集成到项目的 Bazel 构建系统中。它是 Cargo 与 Bazel 双构建系统共存架构的一部分。

## 功能点目的

1. **加载构建规则**: 从项目根目录的 `defs.bzl` 加载 `codex_rust_crate` 宏
2. **定义过程宏 crate**: 使用 `codex_rust_crate` 宏声明这是一个 Rust 过程宏库
3. **指定 crate 名称**: 将 Bazel 目标名 `test-macros` 映射到 Cargo crate 名 `codex_test_macros`

## 具体技术实现

### 关键配置参数

```starlark
codex_rust_crate(
    name = "test-macros",           # Bazel 目标名称
    crate_name = "codex_test_macros",  # Rust crate 名称（下划线分隔）
    proc_macro = True,              # 标记为过程宏 crate
)
```

### 与 defs.bzl 的交互

`defs.bzl` 中的 `codex_rust_crate` 宏会根据 `proc_macro=True` 参数：
- 使用 `rust_proc_macro` 规则代替 `rust_library` 来构建库
- 自动处理过程宏特有的编译配置
- 保持与 Cargo 构建的兼容性

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/test-macros/BUILD.bazel` - 本文件

### 依赖的构建规则
- `//:defs.bzl` - 项目级 Rust crate 构建宏定义

### 相关源文件
- `codex-rs/test-macros/src/lib.rs` - 过程宏实现源码
- `codex-rs/test-macros/Cargo.toml` - Cargo 构建配置（与 Bazel 配置平行）

### 调用方（使用该宏的测试）
- `codex-rs/core/tests/suite/apply_patch_cli.rs` - 大量使用 `#[large_stack_test]` 属性宏

## 依赖与外部交互

### 构建系统依赖
| 依赖 | 来源 | 用途 |
|------|------|------|
| `//:defs.bzl` | 项目根目录 | 复用统一的 crate 构建逻辑 |
| `@crates` | Bazel 外部仓库 | 解析 Cargo.lock 中的依赖 |
| `rules_rust` | Bazel 规则集 | Rust 编译基础设施 |

### 与 Cargo.toml 的对应关系

| BUILD.bazel | Cargo.toml | 说明 |
|-------------|------------|------|
| `name = "test-macros"` | `[package] name = "codex-test-macros"` | Bazel 使用 kebab-case，Cargo 使用 kebab-case |
| `crate_name = "codex_test_macros"` | - | Rust 代码中使用 snake_case |
| `proc_macro = True` | `[lib] proc-macro = true` | 两者都标记为过程宏 |

## 风险、边界与改进建议

### 风险点

1. **命名不一致风险**: Bazel 目标名 (`test-macros`)、Cargo 包名 (`codex-test-macros`)、Rust crate 名 (`codex_test_macros`) 三者形式不同，可能导致混淆

2. **双构建系统维护成本**: 任何依赖变更需要同时在 `Cargo.toml` 和 Bazel 配置中体现（通过 `MODULE.bazel.lock` 同步）

3. **过程宏的特殊性**: 过程宏在编译时执行，如果宏本身有 bug，会导致所有依赖它的 crate 编译失败

### 边界条件

- 该 crate 仅包含一个导出宏 `large_stack_test`
- 仅用于测试代码，不进入生产二进制文件
- 依赖 `proc-macro2`、`quote`、`syn` 三个标准过程宏工具库

### 改进建议

1. **文档增强**: 在 BUILD.bazel 顶部添加注释说明该 crate 的用途和与 Cargo.toml 的对应关系

2. **命名统一考虑**: 考虑将 Bazel 目标名改为 `codex-test-macros` 以与 Cargo 包名保持一致

3. **依赖显式声明**: 虽然 `codex_rust_crate` 宏会自动处理依赖，但建议在注释中列出关键依赖以便阅读者理解

4. **测试覆盖**: 确保 `src/lib.rs` 中的单元测试（`mod tests`）在 Bazel 构建中也能正常运行
