# Cargo.toml 研究文档

## 场景与职责

该文件是 `codex-test-macros` crate 的 Cargo 构建配置，定义了 Rust 过程宏 crate 的元数据、依赖和构建设置。该 crate 提供了一个自定义测试属性宏 `#[large_stack_test]`，用于在独立线程中运行需要大栈空间的测试。

## 功能点目的

1. **定义 crate 元数据**: 名称、版本、Rust 版本、许可证信息
2. **声明过程宏库**: 标记这是一个 `proc-macro` 类型的 crate
3. **管理依赖**: 声明过程宏开发所需的核心库
4. **统一工作空间配置**: 继承工作空间级别的版本、版本号和许可证设置

## 具体技术实现

### 包配置解析

```toml
[package]
name = "codex-test-macros"        # Cargo 包名（kebab-case）
version.workspace = true          # 继承工作空间版本
edition.workspace = true          # 继承工作空间 Rust 版本（2021/2024）
license.workspace = true          # 继承工作空间许可证（MIT）
```

### 库类型声明

```toml
[lib]
proc-macro = true                 # 标记为过程宏 crate
```

这告诉 Cargo：
- 该 crate 编译为 `cdylib` 格式
- 导出项是 `proc_macro::TokenStream` 处理函数
- 在依赖者编译时执行（编译期代码生成）

### 依赖分析

| 依赖 | 版本 | 功能 | 用途 |
|------|------|------|------|
| `proc-macro2` | "1" | - | TokenStream 的更好抽象，支持 span 信息 |
| `quote` | "1" | - |  quasi-quoting 宏，简化代码生成 |
| `syn` | "2" | ["full"] | Rust 语法解析，支持完整语法树 |

依赖组合说明：
- `syn` 用于解析输入的 Rust 代码（`ItemFn`、`Attribute` 等）
- `quote` 用于生成输出代码（`quote!` 宏）
- `proc-macro2` 提供底层 TokenStream 操作

### 代码检查配置

```toml
[lints]
workspace = true                  # 继承工作空间级别的 lint 配置
```

## 关键代码路径与文件引用

### 当前 crate 文件
- `codex-rs/test-macros/Cargo.toml` - 本文件
- `codex-rs/test-macros/src/lib.rs` - 过程宏实现（155 行）
- `codex-rs/test-macros/BUILD.bazel` - Bazel 构建配置

### 工作空间配置
- 根目录 `Cargo.toml`（工作空间定义）
- `codex-rs/Cargo.toml`（可能包含工作空间级配置）

### 主要调用方
- `codex-rs/core/Cargo.toml` - 依赖 `codex-test-macros`
- `codex-rs/core/tests/suite/apply_patch_cli.rs` - 大量使用 `#[large_stack_test]`

### 宏导出详情

`src/lib.rs` 导出的主要宏：

```rust
#[proc_macro_attribute]
pub fn large_stack_test(attr: TokenStream, item: TokenStream) -> TokenStream
```

功能：
- 在独立线程中运行测试，栈大小为 16MB（`16 * 1024 * 1024`）
- 支持同步和异步（tokio）测试
- 自动处理 `#[test]`、`#[tokio::test]`、`#[test_case]` 属性

## 依赖与外部交互

### 编译时依赖关系

```
codex-core (测试) 
    ↓ 依赖
codex-test-macros
    ↓ 编译时执行
proc-macro2, quote, syn
```

### 与 Bazel 的对应

| Cargo.toml | BUILD.bazel | 说明 |
|------------|-------------|------|
| `name = "codex-test-macros"` | `name = "test-macros"` | Bazel 使用短名称 |
| `proc-macro = true` | `proc_macro = True` | 两者都标记为过程宏 |
| `[dependencies]` | 通过 `@crates` 解析 | Bazel 从 Cargo.lock 读取 |

### 特性传播

- 该 crate 自身没有定义特性（features）
- `syn` 启用了 `"full"` 特性以支持完整语法解析

## 风险、边界与改进建议

### 风险点

1. **栈大小硬编码**: `LARGE_STACK_TEST_STACK_SIZE_BYTES = 16 * 1024 * 1024` 是编译时常量，无法通过配置调整

2. **tokio 运行时假设**: 异步测试硬编码使用多线程运行时：
   ```rust
   ::tokio::runtime::Builder::new_multi_thread()
       .worker_threads(2)
   ```
   这可能与某些测试的期望不符

3. **属性处理不完善**: 当前只处理 `#[test]`、`#[test_case]`、`#[tokio::test]`，其他测试框架（如 `async-std`）不支持

4. **错误处理**: 使用 `unwrap_or_else(|error| panic!(...))`，在宏展开失败时 panic 信息可能不够友好

### 边界条件

- **最小 Rust 版本**: 依赖 syn 2.x，需要 Rust 1.56+
- **平台兼容性**: 栈大小设置在所有支持 `std::thread::Builder` 的平台上有效
- **测试类型限制**: 仅支持函数形式的测试，不支持 `mod tests` 级别的属性

### 改进建议

1. **可配置栈大小**: 考虑支持属性参数指定栈大小：
   ```rust
   #[large_stack_test(stack_size = 32 * 1024 * 1024)]
   ```

2. **tokio 运行时配置**: 允许自定义运行时配置：
   ```rust
   #[large_stack_test(runtime = "single_thread")]
   ```

3. **文档增强**: 在 Cargo.toml 中添加更详细的描述：
   ```toml
   [package]
   description = "Procedural macro for running tests with enlarged stack size"
   ```

4. **依赖版本细化**: 考虑指定最小兼容版本而非仅主版本：
   ```toml
   syn = { version = "^2.0", features = ["full"] }
   ```

5. **测试覆盖率**: 当前 `src/lib.rs` 包含单元测试，建议添加集成测试验证宏在各种边界情况下的行为

6. **与 Bazel 的同步检查**: 添加 CI 检查确保 Cargo.toml 和 BUILD.bazel 的依赖信息保持一致
