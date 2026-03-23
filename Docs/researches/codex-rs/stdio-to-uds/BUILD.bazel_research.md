# BUILD.bazel 研究文档

## 场景与职责

`BUILD.bazel` 是 Bazel 构建系统对 `codex-stdio-to-uds` crate 的构建配置。该文件定义了如何将这个 Rust crate 构建为 Bazel 目标，使其能够被 Bazel 工作空间中的其他目标依赖。

## 功能点目的

该文件的核心目的是：
1. **声明构建目标**：将 `codex-stdio-to-uds` 注册为 Bazel 可识别的 Rust crate
2. **复用构建逻辑**：通过 `codex_rust_crate` 宏统一处理库、二进制文件和测试的构建
3. **维护 Cargo/Bazel 双构建系统兼容性**：确保同一套源码可以用 Cargo 或 Bazel 两种方式构建

## 具体技术实现

### 关键流程

```
加载 defs.bzl → 调用 codex_rust_crate 宏 → 生成 rust_library + rust_binary + rust_test 目标
```

### 数据结构

```python
# 宏调用参数
{
    "name": "stdio-to-uds",           # Bazel 目标名（目录名）
    "crate_name": "codex_stdio_to_uds" # Cargo crate 名（下划线分隔）
}
```

### 宏展开逻辑

`codex_rust_crate` 宏（定义于 `//:defs.bzl`）会自动：

1. **检测源码文件**：通过 `native.glob(["src/**/*.rs"])` 收集所有 Rust 源文件
2. **构建库目标**：如果存在非二进制源码，创建 `rust_library` 目标
3. **构建二进制目标**：根据 `Cargo.toml` 中的 `[[bin]]` 段落创建 `rust_binary`
4. **构建测试目标**：
   - 单元测试：`{name}-unit-tests`（基于库目标）
   - 集成测试：为 `tests/*.rs` 中的每个文件创建独立测试目标

### 依赖解析

依赖通过 `all_crate_deps()` 从 `@crates` 外部仓库解析，该仓库由 `MODULE.bazel` 和 `Cargo.lock` 同步生成。

## 关键代码路径与文件引用

| 文件 | 作用 |
|------|------|
| `//:defs.bzl` | 定义 `codex_rust_crate` 宏，实现统一的 Rust crate 构建逻辑 |
| `codex-rs/stdio-to-uds/Cargo.toml` | 定义 crate 元数据、二进制入口、依赖项 |
| `codex-rs/stdio-to-uds/src/lib.rs` | 库源码，实现 `run()` 函数 |
| `codex-rs/stdio-to-uds/src/main.rs` | 二进制入口，调用 `codex_stdio_to_uds::run()` |
| `codex-rs/stdio-to-uds/tests/stdio_to_uds.rs` | 集成测试 |

## 依赖与外部交互

### 内部依赖
- `//:defs.bzl` - 构建宏定义

### 外部依赖（通过 Cargo.toml 间接引入）
- `anyhow` - 错误处理
- `uds_windows` - Windows 平台的 UDS 支持（条件编译）

### 生成的 Bazel 目标
调用宏后会生成以下目标：
- `//codex-rs/stdio-to-uds:stdio-to-uds` - 库目标
- `//codex-rs/stdio-to-uds:codex-stdio-to-uds` - 二进制目标
- `//codex-rs/stdio-to-uds:stdio-to-uds-unit-tests` - 单元测试
- `//codex-rs/stdio-to-uds:stdio-to-uds-stdio_to_uds-test` - 集成测试

## 风险、边界与改进建议

### 风险
1. **Cargo/Bazel 同步风险**：如果 `Cargo.toml` 更新但 `MODULE.bazel.lock` 未同步，可能导致两种构建系统行为不一致
2. **条件编译依赖**：Windows 依赖 `uds_windows` crate，该依赖在 Bazel 中需要正确配置平台约束

### 边界
- 该 crate 仅包含一个二进制文件，结构简单，宏展开后的目标数量有限
- 无自定义 `build.rs`，无需额外的构建脚本数据处理

### 改进建议
1. **显式声明 srcs**：当前使用 `native.glob` 自动收集源文件，对于简单 crate 可以考虑显式列出以提高可预测性
2. **添加平台特定标签**：如果某些测试在特定平台不稳定，可以通过 `test_tags` 参数添加标签
