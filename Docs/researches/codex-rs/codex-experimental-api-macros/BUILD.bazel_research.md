# BUILD.bazel 研究文档

## 场景与职责

此 BUILD.bazel 文件位于 `codex-rs/codex-experimental-api-macros/` 目录下，是 Bazel 构建系统中用于定义 `codex-experimental-api-macros` crate 的构建配置。该 crate 是一个 **Rust 过程宏 (proc-macro)** 库，负责为 Codex 的 App Server Protocol 提供实验性 API 的派生宏支持。

### 核心职责

1. **定义过程宏 crate 的构建目标**：通过 `codex_rust_crate` 宏声明这是一个 Rust 过程宏库
2. **启用 proc-macro 特性**：设置 `proc_macro = True` 以告知 Bazel 这是一个编译时宏库
3. **统一构建规范**：通过项目根目录的 `defs.bzl` 中定义的 `codex_rust_crate` 宏，确保与 Cargo 构建的兼容性

## 功能点目的

### 1. 过程宏库声明

```bazel
codex_rust_crate(
    name = "codex-experimental-api-macros",
    crate_name = "codex_experimental_api_macros",
    proc_macro = True,
)
```

- **`name`**：Bazel 目标名称，使用 kebab-case（短横线连接）
- **`crate_name`**：Rust crate 名称，使用 snake_case（下划线连接），符合 Rust 命名规范
- **`proc_macro = True`**：关键标志，表示这是一个过程宏库，Bazel 将使用 `rust_proc_macro` 规则而非 `rust_library` 进行构建

### 2. 与 Cargo 的互操作

该配置与同一目录下的 `Cargo.toml` 保持一致：
- `Cargo.toml` 中声明 `[lib] proc-macro = true`
- `BUILD.bazel` 中设置 `proc_macro = True`

这种双重配置确保了开发者既可以使用 `cargo build` 进行开发，也可以使用 `bazel build` 进行生产构建。

## 具体技术实现

### 构建流程

1. **依赖解析**：Bazel 通过 `@crates` 外部仓库解析 `Cargo.toml` 中声明的依赖（`proc-macro2`, `quote`, `syn`）
2. **宏展开**：在编译依赖 `codex-experimental-api-macros` 的其他 crate 时，Bazel 会先构建此过程宏库
3. **编译时执行**：过程宏在编译目标 crate 时执行，生成额外的 Rust 代码

### 关键数据结构

过程宏处理的核心数据结构来自 `syn` crate：

| 类型 | 用途 |
|------|------|
| `DeriveInput` | 解析派生宏输入的完整结构体/枚举定义 |
| `DataStruct` / `DataEnum` | 区分结构体和枚举类型 |
| `Fields` / `Named` / `Unnamed` | 处理命名字段和无名字段（元组结构体）|
| `Attribute` | 解析 `#[experimental(...)]` 属性 |
| `LitStr` | 提取实验性原因的字符串字面量 |

## 关键代码路径与文件引用

### 相关文件

```
codex-rs/codex-experimental-api-macros/
├── BUILD.bazel          # 本文件：Bazel 构建配置
├── Cargo.toml           # Cargo 构建配置
└── src/
    └── lib.rs           # 过程宏实现（329 行）
```

### 调用方（使用者）

过程宏的主要使用者在 `codex-app-server-protocol` crate 中：

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
use codex_experimental_api_macros::ExperimentalApi;

#[derive(Serialize, Deserialize, ..., ExperimentalApi)]
#[serde(rename_all = "snake_case")]
pub struct ProfileV2 {
    #[experimental(nested)]
    pub approval_policy: Option<AskForApproval>,
    #[experimental("config/read.approvalsReviewer")]
    pub approvals_reviewer: Option<ApprovalsReviewer>,
    // ...
}
```

### 被调用方（依赖）

```rust
// codex-rs/codex-experimental-api-macros/src/lib.rs
#[proc_macro_derive(ExperimentalApi, attributes(experimental))]
pub fn derive_experimental_api(input: TokenStream) -> TokenStream {
    // 实现逻辑...
}
```

## 依赖与外部交互

### 编译时依赖（由 Cargo.toml 定义）

| 依赖 | 版本 | 用途 |
|------|------|------|
| `proc-macro2` | 1.x | 提供 `TokenStream` 和 `Span` 的抽象 |
| `quote` | 1.x | 用于生成 Rust 代码的 quasi-quoting |
| `syn` | 2.x | 解析 Rust 语法树，支持 `full` 和 `extra-traits` 特性 |

### 运行时依赖

过程宏 crate **没有运行时依赖**，它仅在编译时执行。

### Bazel 构建依赖

- `//:defs.bzl`：项目级 Bazel 宏定义，提供 `codex_rust_crate` 函数
- `@crates`：外部仓库，包含所有 Cargo 依赖的 Bazel 定义

## 风险、边界与改进建议

### 当前风险

1. **类型推导复杂性**：过程宏需要处理多种字段类型（`Option<T>`, `Vec<T>`, `HashMap<K,V>`, `bool` 等），类型判断逻辑较为复杂
2. **命名转换**：`snake_to_camel` 函数手动实现驼峰命名转换，可能无法覆盖所有边界情况
3. **inventory 集成**：使用 `inventory` crate 进行全局注册，在多线程或特定编译环境下可能有局限性

### 边界情况

1. **不支持 Union 类型**：代码明确拒绝为 Union 类型派生 `ExperimentalApi`
2. **元组结构体限制**：`experimental_presence_expr` 对元组结构体返回 `None`，可能限制某些使用场景
3. **嵌套实验性字段**：通过 `#[experimental(nested)]` 支持，但依赖类型本身实现 `ExperimentalApi` trait

### 改进建议

1. **增加单元测试覆盖**：虽然 `experimental_api.rs` 中有测试，但建议为过程宏本身增加更多边界测试
2. **错误信息优化**：当前错误信息较为简单，可以增加更多上下文帮助开发者定位问题
3. **文档生成**：考虑为派生的 `EXPERIMENTAL_FIELDS` 常量生成文档注释
4. **性能优化**：对于大型结构体，生成的代码可能较长，可以考虑使用 `const` 数组而非多次 `inventory::submit!`

### 相关测试

```bash
# 运行过程宏使用者的测试
cargo test -p codex-app-server-protocol

# 运行集成测试
cargo test -p codex-app-server experimental_api
```
