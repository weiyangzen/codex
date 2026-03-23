# BUILD.bazel 研究文档

## 场景与职责

`BUILD.bazel` 是 Bazel 构建系统对 `codex-execpolicy-legacy` crate 的构建定义文件。它定义了如何将这个 Rust crate 构建为 Bazel 目标，并指定了编译时依赖的数据文件。

## 功能点目的

1. **加载构建规则**: 从项目根目录加载 `defs.bzl` 中定义的 `codex_rust_crate` 宏，这是项目统一的 Rust crate 构建封装
2. **定义 crate 目标**: 使用 `codex_rust_crate` 创建名为 `execpolicy-legacy` 的构建目标
3. **指定 crate 名称**: 将 Rust crate 名称设置为 `codex_execpolicy_legacy`（符合 AGENTS.md 中规定的 `codex-` 前缀规范）
4. **包含编译数据**: 通过 `compile_data` 将 `src/default.policy` 文件作为编译时数据嵌入，该策略文件会被编译进二进制中

## 具体技术实现

### 构建规则引用

```starlark
load("//:defs.bzl", "codex_rust_crate")
```

从项目根目录的 `defs.bzl` 加载自定义的 Rust crate 构建宏。

### 目标定义

```starlark
codex_rust_crate(
    name = "execpolicy-legacy",
    crate_name = "codex_execpolicy_legacy",
    compile_data = ["src/default.policy"],
)
```

- `name`: Bazel 目标名称，用于在构建图中引用
- `crate_name`: 生成的 Rust crate 名称，使用下划线命名规范
- `compile_data`: 编译时需要的数据文件列表，这些文件会被 Bazel 管理并在编译时可用

## 关键代码路径与文件引用

- **构建规则定义**: `//:defs.bzl` (项目根目录)
- **编译数据文件**: `src/default.policy` - 默认执行策略定义文件
- **相关 Cargo 配置**: `Cargo.toml` - 定义了 crate 的元数据和依赖

## 依赖与外部交互

### 内部依赖
- `//:defs.bzl` - 项目级构建规则定义
- `src/default.policy` - 策略文件，会被 `lib.rs` 通过 `include_str!` 嵌入

### Bazel 集成
- 该文件是 Bazel 构建图的一部分，会被 `MODULE.bazel` 或父级 `BUILD.bazel` 文件引用
- 与 `codex-rs/execpolicy/` 目录下的新版策略引擎并存，形成 legacy + 新版的双轨制

## 风险、边界与改进建议

### 风险
1. **策略文件变更检测**: `build.rs` 中设置了 `cargo:rerun-if-changed=src/default.policy`，但 Bazel 构建可能使用不同的变更检测机制，需要确保两者一致
2. **编译数据路径**: `compile_data` 中的路径是相对于 BUILD.bazel 的，移动文件时需要同步更新

### 边界
- 该文件仅定义 Bazel 构建配置，不影响 Cargo 构建
- `compile_data` 仅在 Bazel 构建时有效，Cargo 构建通过 `build.rs` 和 `include_str!` 处理

### 改进建议
1. **统一构建**: 考虑将 Bazel 和 Cargo 的构建配置进一步统一，减少维护成本
2. **文档同步**: 在 `compile_data` 变更时，同步检查 `build.rs` 中的 rerun-if-changed 声明
3. **测试覆盖**: 确保 Bazel 构建的测试覆盖与 Cargo 一致，特别是策略文件加载相关的测试
