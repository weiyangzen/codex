# Cargo.toml 研究文档

## 场景与职责

此 `Cargo.toml` 文件位于 `codex-rs/codex-experimental-api-macros/` 目录下，是 Rust 包管理工具 Cargo 的配置文件。该 crate 是一个**过程宏 (proc-macro)** 库，为 Codex App Server Protocol 提供 `ExperimentalApi` 派生宏的实现。

### 核心职责

1. **声明过程宏库**：通过 `[lib] proc-macro = true` 标记这是一个编译时宏库
2. **定义依赖关系**：声明实现过程宏所需的核心依赖（`proc-macro2`, `quote`, `syn`）
3. **继承工作区配置**：使用 `workspace = true` 统一版本、edition 和许可证管理
4. **启用代码检查**：继承工作区级别的 lint 配置

## 功能点目的

### 1. 包元数据配置

```toml
[package]
name = "codex-experimental-api-macros"
version.workspace = true
edition.workspace = true
license.workspace = true
```

| 字段 | 值 | 说明 |
|------|-----|------|
| `name` | `codex-experimental-api-macros` | crate 名称，使用 kebab-case |
| `version.workspace` | `true` | 从工作区根目录的 `Cargo.toml` 继承版本号 |
| `edition.workspace` | `true` | 从工作区继承 Rust edition（通常为 2021）|
| `license.workspace` | `true` | 从工作区继承许可证信息 |

### 2. 过程宏库声明

```toml
[lib]
proc-macro = true
```

这是**最关键的配置**，它告诉 Rust 编译器：
- 这个 crate 是一个过程宏库
- 编译后生成 `.so`/`.dll`/`.dylib` 动态库
- 在其他 crate 编译时，这些宏会被加载并执行

### 3. 核心依赖配置

```toml
[dependencies]
proc-macro2 = "1"
quote = "1"
syn = { version = "2", features = ["full", "extra-traits"] }
```

| 依赖 | 版本 | 特性 | 用途 |
|------|------|------|------|
| `proc-macro2` | 1.x | 默认 | 提供 `TokenStream` 和 `Span` 的稳定抽象，是 `quote` 和 `syn` 的基础 |
| `quote` | 1.x | 默认 | 提供 `quote!` 宏，用于生成 Rust 代码片段 |
| `syn` | 2.x | `full`, `extra-traits` | 解析 Rust 源代码为 AST，`full` 支持完整语法，`extra-traits` 提供 `Debug`/`Clone` 等 trait |

### 4. 代码检查配置

```toml
[lints]
workspace = true
```

继承工作区级别的 Clippy 和 rustc lint 配置，确保代码质量一致性。

## 具体技术实现

### 过程宏的工作机制

```
┌─────────────────────────────────────────────────────────────────┐
│  源代码阶段                                                      │
│  #[derive(ExperimentalApi)]                                      │
│  struct ProfileV2 { ... }                                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  编译时：syn 解析                                                │
│  DeriveInput {                                                  │
│      ident: "ProfileV2",                                        │
│      data: Data::Struct { ... },                                │
│      attrs: [Attribute { path: "experimental", ... }]          │
│  }                                                               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  代码生成：quote! 宏                                             │
│  impl ExperimentalApi for ProfileV2 {                           │
│      fn experimental_reason(&self) -> Option<&'static str> {    │
│          // 检查字段是否使用了实验性功能                         │
│      }                                                          │
│  }                                                               │
└─────────────────────────────────────────────────────────────────┘
```

### 依赖详解

#### proc-macro2

- **作用**：提供 `TokenStream` 和 `Span` 的类型定义
- **必要性**：`proc-macro` crate 只能在 proc-macro 上下文中使用，`proc-macro2` 提供了相同的 API 但可以在任何地方使用
- **关键类型**：`proc_macro2::TokenStream`, `proc_macro2::Span`

#### quote

- **作用**：提供 quasi-quoting 功能，将 Rust 代码模板转换为 `TokenStream`
- **使用示例**：
  ```rust
  let expanded = quote! {
      impl ExperimentalApi for #name {
          fn experimental_reason(&self) -> Option<&'static str> {
              #checks
          }
      }
  };
  ```

#### syn

- **作用**：解析 Rust 源代码为结构化数据
- **`full` 特性**：支持解析完整的 Rust 语法，包括复杂类型、泛型、where 子句等
- **`extra-traits` 特性**：为 AST 节点实现 `Debug`, `Clone`, `Eq` 等 trait，便于调试

## 关键代码路径与文件引用

### 本 crate 文件结构

```
codex-rs/codex-experimental-api-macros/
├── Cargo.toml           # 本文件：包配置
├── BUILD.bazel          # Bazel 构建配置
└── src/
    └── lib.rs           # 过程宏实现（329 行）
```

### 实现文件详解

`src/lib.rs` 实现了 `ExperimentalApi` 派生宏，主要功能：

1. **结构体支持**（`derive_for_struct`）：
   - 命名字段结构体（`struct Foo { bar: i32 }`）
   - 元组结构体（`struct Foo(i32, String)`）
   - 单元结构体（`struct Foo;`）

2. **枚举支持**（`derive_for_enum`）：
   - 为每个变体生成匹配分支
   - 支持单元变体、元组变体、结构体变体

3. **属性解析**：
   - `#[experimental("reason")]`：标记实验性字段/变体
   - `#[experimental(nested)]`：标记嵌套实验性类型

### 调用方（使用者）

主要使用者在 `codex-app-server-protocol` crate：

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
use codex_experimental_api_macros::ExperimentalApi;

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS, ExperimentalApi)]
#[serde(rename_all = "snake_case")]
#[ts(export_to = "v2/")]
pub struct ProfileV2 {
    pub model: Option<String>,
    #[experimental(nested)]
    pub approval_policy: Option<AskForApproval>,
    #[experimental("config/read.approvalsReviewer")]
    pub approvals_reviewer: Option<ApprovalsReviewer>,
    // ...
}
```

其他使用 `ExperimentalApi` 的类型：
- `Config`（配置结构体）
- `ConfigReadResponse`（配置读取响应）
- `ConfigRequirements`（配置要求）
- `ServerNotification`（服务器通知枚举）
- 各种实时对话相关类型（`ThreadRealtimeStartParams` 等）

## 依赖与外部交互

### 编译时依赖图

```
codex-experimental-api-macros
├── proc-macro2
│   └── unicode-ident
├── quote
│   └── proc-macro2
└── syn
    ├── proc-macro2
    ├── quote
    └── unicode-ident
```

### 反向依赖

```
codex-app-server-protocol
├── codex-experimental-api-macros (proc-macro)
├── codex-protocol
├── schemars
├── serde
├── ts-rs
└── inventory
```

### Bazel 集成

在 `BUILD.bazel` 中通过 `codex_rust_crate` 宏定义：

```bazel
codex_rust_crate(
    name = "codex-experimental-api-macros",
    crate_name = "codex_experimental_api_macros",
    proc_macro = True,
)
```

Bazel 会自动从 `Cargo.toml` 读取依赖信息，通过 `@crates` 外部仓库解析。

## 风险、边界与改进建议

### 当前风险

1. **syn 版本锁定**：使用 syn 2.x，如果工作区其他 crate 依赖 syn 1.x，可能导致编译问题
2. **特性膨胀**：`full` 和 `extra-traits` 特性增加了编译时间和二进制大小
3. **错误处理**：`experimental_reason_attr` 使用 `parse_args::<LitStr>().ok()`，静默忽略解析错误

### 边界情况

1. **不支持 Union 类型**：代码明确检查并拒绝 Union 类型
   ```rust
   Data::Union(_) => {
       syn::Error::new_spanned(&input.ident, "ExperimentalApi does not support unions")
           .to_compile_error()
           .into()
   }
   ```

2. **元组结构体字段名**：使用索引（0, 1, 2...）作为字段名，可能不够直观

3. **命名转换限制**：`snake_to_camel` 是简单实现，不处理连续下划线等边界情况

### 改进建议

1. **依赖优化**：
   - 评估是否可以移除 `extra-traits` 特性以减少编译时间
   - 考虑使用 `syn` 的 `derive` 特性替代 `full`（如果语法足够简单）

2. **错误处理增强**：
   ```rust
   // 当前代码
   attr.parse_args::<LitStr>().ok()
   
   // 建议改进
   attr.parse_args::<LitStr>()
       .map_err(|e| syn::Error::new_spanned(attr, format!("invalid experimental attribute: {}", e)))
   ```

3. **文档和测试**：
   - 增加更多边界情况的单元测试
   - 为宏提供使用文档示例

4. **性能优化**：
   - 考虑缓存 `inventory::submit!` 调用的结果
   - 对于大型结构体，优化生成的代码量

### 相关命令

```bash
# 构建过程宏 crate
cargo build -p codex-experimental-api-macros

# 检查依赖树
cargo tree -p codex-experimental-api-macros

# 运行使用者的测试
cargo test -p codex-app-server-protocol experimental_api

# Bazel 构建
bazel build //codex-rs/codex-experimental-api-macros
```
