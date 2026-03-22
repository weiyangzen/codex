# codex-experimental-api-macros/src/lib.rs 研究文档

## 1. 场景与职责

### 1.1 定位

`codex-experimental-api-macros` 是 Codex Rust 项目中的一个**过程宏（proc-macro）crate**，其核心职责是为 App-Server 协议提供**实验性 API 标记与运行时检查**的能力。它通过派生宏 `#[derive(ExperimentalApi)]` 和属性宏 `#[experimental(...)]` 实现：

- **编译期**：自动为结构体和枚举生成 `ExperimentalApi` trait 实现
- **运行期**：检测请求/参数是否使用了实验性功能，用于权限控制

### 1.2 使用场景

| 场景 | 说明 |
|------|------|
| **API 版本控制** | 新功能以实验性 API 形式发布，客户端需显式声明支持才能使用 |
| **字段级权限** | 某些字段（如 `approval_policy`）仅在特定值（如 `Granular`）下触发实验性检查 |
| **嵌套类型检查** | 支持嵌套结构体的递归实验性检测（如 `Config` → `ProfileV2` → `AskForApproval`） |
| **协议兼容性** | 服务端可拒绝未声明实验性能力的客户端调用实验性接口 |

### 1.3 项目架构位置

```
codex-rs/
├── codex-experimental-api-macros/    <-- 本 crate（过程宏实现）
├── app-server-protocol/              <-- 协议定义，使用本宏
│   ├── src/experimental_api.rs       <-- ExperimentalApi trait 定义
│   └── src/protocol/
│       ├── common.rs                 <-- ClientRequest/ServerNotification 定义
│       └── v2.rs                     <-- v2 API 参数结构体
├── app-server/                       <-- 服务端实现
│   └── src/message_processor.rs      <-- 实验性权限检查点
└── app-server/tests/suite/v2/        <-- 集成测试
    └── experimental_api.rs
```

---

## 2. 功能点目的

### 2.1 核心功能

#### 2.1.1 派生宏 `#[derive(ExperimentalApi)]`

为结构体或枚举自动生成 `ExperimentalApi` trait 实现，提供 `experimental_reason(&self) -> Option<&'static str>` 方法：

- 返回 `Some(reason)`：表示该值使用了实验性功能，`reason` 为功能标识符
- 返回 `None`：表示该值完全稳定，无需特殊权限

#### 2.1.2 属性 `#[experimental(...)]`

标记实验性字段或变体，支持两种形式：

| 形式 | 示例 | 含义 |
|------|------|------|
| **字符串标记** | `#[experimental("askForApproval.granular")]` | 该字段/变体具有指定实验性标识 |
| **嵌套标记** | `#[experimental(nested)]` | 该字段类型本身实现了 `ExperimentalApi`，需递归检查 |

#### 2.1.3 字段存在性检测

宏生成的代码不仅检查字段是否标记为实验性，还检查字段**是否实际被使用**（presence check）：

- `Option<T>`：`is_some()` 才触发检查
- `Vec<T>` / `HashMap<K,V>`：`!is_empty()` 才触发检查
- `bool`：值为 `true` 才触发检查
- 其他类型：始终视为已使用

### 2.2 设计目标

1. **最小侵入性**：通过派生宏避免手写重复代码
2. **精确控制**：支持字段级、方法级、变体级的细粒度标记
3. **递归检查**：支持嵌套结构体的深度检测
4. **零成本抽象**：编译期生成代码，运行期无额外开销

---

## 3. 具体技术实现

### 3.1 入口点与分发

```rust
#[proc_macro_derive(ExperimentalApi, attributes(experimental))]
pub fn derive_experimental_api(input: TokenStream) -> TokenStream {
    let input = parse_macro_input!(input as DeriveInput);
    match &input.data {
        Data::Struct(data) => derive_for_struct(&input, data),
        Data::Enum(data) => derive_for_enum(&input, data),
        Data::Union(_) => { /* 不支持 Union */ }
    }
}
```

### 3.2 结构体处理 (`derive_for_struct`)

#### 3.2.1 命名字段结构体 (Named Fields)

对于每个字段，生成三类代码：

1. **存在性检查表达式**（`checks`）：
```rust
if self.#ident.as_ref().is_some_and(|value| /* 嵌套检查 */) {
    return Some(#reason);
}
```

2. **实验性字段元数据**（`experimental_fields`）：
```rust
crate::experimental_api::ExperimentalField {
    type_name: #type_name_lit,
    field_name: #field_name_lit,  // 自动转换为 camelCase
    reason: #reason,
}
```

3. **inventory 注册**（`registrations`）：
```rust
::inventory::submit! {
    crate::experimental_api::ExperimentalField { ... }
}
```

#### 3.2.2 元组结构体 (Unnamed Fields)

使用索引访问（`self.#index`）而非字段名，字段名使用数字字符串（`"0"`, `"1"`...）。

#### 3.2.3 嵌套检测逻辑

当字段标记为 `#[experimental(nested)]` 时，生成递归调用：

```rust
if let Some(reason) =
    crate::experimental_api::ExperimentalApi::experimental_reason(&self.#ident)
{
    return Some(reason);
}
```

### 3.3 枚举处理 (`derive_for_enum`)

为每个变体生成 match arm：

```rust
match self {
    Self::VariantName { .. } => Some("reason"),  // 标记实验性的变体
    Self::OtherVariant => None,                   // 稳定变体
}
```

**注意**：枚举变体的实验性检查是**静态**的（基于变体类型），不检查变体内部字段。

### 3.4 类型检测辅助函数

| 函数 | 用途 |
|------|------|
| `option_inner(ty)` | 提取 `Option<T>` 的内部类型 `T` |
| `is_vec_like(ty)` | 检查类型是否为 `Vec` |
| `is_map_like(ty)` | 检查类型是否为 `HashMap` 或 `BTreeMap` |
| `is_bool(ty)` | 检查类型是否为 `bool` |
| `type_last_ident(ty)` | 获取类型路径的最后一段标识符 |

### 3.5 存在性表达式生成 (`presence_expr_for_access`)

递归生成检测表达式，处理嵌套 `Option`：

```rust
fn presence_expr_for_access(access: TokenStream, ty: &Type) -> TokenStream {
    if let Some(inner) = option_inner(ty) {
        // Option<Option<T>> 情况：递归检查
        let inner_expr = presence_expr_for_ref(quote!(value), inner);
        return quote! { #access.as_ref().is_some_and(|value| #inner_expr) };
    }
    if is_vec_like(ty) || is_map_like(ty) {
        return quote! { !#access.is_empty() };
    }
    if is_bool(ty) {
        return quote! { #access };
    }
    quote! { true }  // 其他类型视为始终存在
}
```

### 3.6 命名转换

`snake_to_camel` 函数将 Rust 的 snake_case 字段名转换为 TypeScript 风格的 camelCase（用于 `ExperimentalField` 元数据）：

```rust
fn snake_to_camel(s: &str) -> String {
    // "approval_policy" -> "approvalPolicy"
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 宏定义与实现

| 文件 | 行号 | 内容 |
|------|------|------|
| `codex-experimental-api-macros/src/lib.rs` | 16-28 | 入口 `derive_experimental_api` |
| `codex-experimental-api-macros/src/lib.rs` | 30-158 | `derive_for_struct` 实现 |
| `codex-experimental-api-macros/src/lib.rs` | 160-193 | `derive_for_enum` 实现 |
| `codex-experimental-api-macros/src/lib.rs` | 195-218 | 属性解析辅助函数 |
| `codex-experimental-api-macros/src/lib.rs` | 220-242 | 命名转换与字段名处理 |
| `codex-experimental-api-macros/src/lib.rs` | 244-329 | 类型检测与存在性表达式生成 |

### 4.2 Trait 定义与 blanket 实现

| 文件 | 行号 | 内容 |
|------|------|------|
| `app-server-protocol/src/experimental_api.rs` | 4-9 | `ExperimentalApi` trait 定义 |
| `app-server-protocol/src/experimental_api.rs` | 12-20 | `ExperimentalField` 结构体 |
| `app-server-protocol/src/experimental_api.rs` | 22 | `inventory::collect!` 收集器 |
| `app-server-protocol/src/experimental_api.rs` | 34-56 | `Option<T>`, `Vec<T>`, `HashMap<K,V>`, `BTreeMap<K,V>` 的 blanket 实现 |

### 4.3 协议类型使用

| 文件 | 行号 | 内容 |
|------|------|------|
| `app-server-protocol/src/protocol/v2.rs` | 201-223 | `AskForApproval` 枚举（实验性变体示例） |
| `app-server-protocol/src/protocol/v2.rs` | 588-610 | `ProfileV2` 结构体（嵌套实验性字段） |
| `app-server-protocol/src/protocol/v2.rs` | 689-727 | `Config` 结构体（多层嵌套） |
| `app-server-protocol/src/protocol/v2.rs` | 2449-2508 | `ThreadStartParams`（实验性字段示例） |
| `app-server-protocol/src/protocol/common.rs` | 85-203 | `client_request_definitions!` 宏（方法级实验性检查） |
| `app-server-protocol/src/protocol/common.rs` | 642-695 | `server_notification_definitions!` 宏（通知级检查） |

### 4.4 服务端权限检查

| 文件 | 行号 | 内容 |
|------|------|------|
| `app-server/src/message_processor.rs` | 156-163 | `ConnectionSessionState`（存储 `experimental_api_enabled`） |
| `app-server/src/message_processor.rs` | 533-545 | Initialize 时读取客户端能力 |
| `app-server/src/message_processor.rs` | 616-626 | 请求处理时的实验性权限检查 |

### 4.5 测试覆盖

| 文件 | 行号 | 内容 |
|------|------|------|
| `app-server-protocol/src/experimental_api.rs` | 58-172 | 单元测试（枚举、嵌套字段、集合） |
| `app-server-protocol/src/protocol/v2.rs` | 6797-7127 | v2 协议实验性检查单元测试 |
| `app-server-protocol/src/protocol/common.rs` | 1609-1718 | common 模块实验性检查测试 |
| `app-server/tests/suite/v2/experimental_api.rs` | 1-242 | 集成测试（端到端权限验证） |

---

## 5. 依赖与外部交互

### 5.1 编译期依赖

| Crate | 用途 |
|-------|------|
| `proc-macro2` | Token 流的低级操作 |
| `quote` | 生成 Rust 代码的 quasi-quoting |
| `syn` | Rust 代码的解析（AST） |

### 5.2 运行期依赖（生成代码中使用）

| Crate | 用途 |
|-------|------|
| `inventory` | 全局注册 `ExperimentalField` 元数据 |

### 5.3 使用者（下游 crate）

| Crate | 使用方式 |
|-------|----------|
| `app-server-protocol` | 在协议类型上 `#[derive(ExperimentalApi)]` |
| `app-server` | 调用 `experimental_reason()` 进行权限检查 |

### 5.4 交互流程

```
┌─────────────────────────┐
│ 开发者标记实验性字段      │
│ #[experimental("reason")]│
└───────────┬─────────────┘
            ▼
┌─────────────────────────┐
│ 编译期：宏展开            │
│ 生成 ExperimentalApi     │
│ trait 实现代码            │
└───────────┬─────────────┘
            ▼
┌─────────────────────────┐
│ 运行期：客户端请求        │
│ 携带实验性参数           │
└───────────┬─────────────┘
            ▼
┌─────────────────────────┐
│ message_processor        │
│ 调用 experimental_reason()│
│ 检查是否需要实验性能力    │
└───────────┬─────────────┘
            ▼
┌─────────────────────────┐
│ 无权限 → 返回错误        │
│ 有权限 → 继续处理        │
└─────────────────────────┘
```

---

## 6. 风险、边界与改进建议

### 6.1 已知限制与风险

#### 6.1.1 Union 类型不支持

```rust
Data::Union(_) => {
    syn::Error::new_spanned(&input.ident, "ExperimentalApi does not support unions")
        .to_compile_error()
        .into()
}
```

**影响**：若协议需要 Union 类型，无法直接使用本宏。

#### 6.1.2 元组结构体的字段名限制

元组结构体的字段名使用数字索引（`"0"`, `"1"`），可能不利于调试和文档生成。

#### 6.1.3 枚举变体内部字段检查缺失

枚举变体只能整体标记为实验性，无法检查变体内部字段的使用情况。

#### 6.1.4 跨客户端实验性状态不一致

代码注释中提到（`message_processor.rs:527-532`）：

```rust
// TODO(maxj): Revisit capability scoping for `experimental_api_enabled`.
// Current behavior is per-connection. Reviewer feedback notes this can
// create odd cross-client behavior...
```

当前实验性能力是**每连接**的，可能导致共享线程时行为不一致。

### 6.2 边界情况

| 情况 | 行为 |
|------|------|
| `Option<Option<T>>` | 递归检查，仅当最内层 `Some` 且值实验性时返回 reason |
| 空 `Vec` / 空 `HashMap` | 不触发实验性检查（视为未使用） |
| `false` 布尔值 | 不触发实验性检查 |
| 嵌套结构体全为 `None` | 不触发实验性检查 |

### 6.3 改进建议

#### 6.3.1 增强类型支持

- **Union 支持**：评估是否需要支持 Union 类型（需谨慎，Union 在 Rust 中较少使用）
- **泛型特化**：为更多标准容器（如 `BTreeSet`, `LinkedList`）提供 blanket 实现

#### 6.3.2 改进错误信息

当前错误信息格式：

```rust
pub fn experimental_required_message(reason: &str) -> String {
    format!("{reason} requires experimentalApi capability")
}
```

建议：
- 添加文档链接
- 列出可用的实验性能力
- 提供迁移指南

#### 6.3.3 性能优化

- 考虑为 `experimental_fields()` 添加缓存，避免每次遍历 inventory
- 评估是否可使用 `phf` 或 `lazy_static` 优化元数据查找

#### 6.3.4 代码生成优化

- 当结构体无实验性字段时，生成的 `EXPERIMENTAL_FIELDS` 为空数组，可考虑使用 `const EMPTY: &[ExperimentalField] = &[];` 减少二进制体积

#### 6.3.5 测试覆盖

- 添加更多边界测试（如深层嵌套 `Option<Option<Vec<T>>>`）
- 添加性能基准测试
- 添加宏展开结果的快照测试（使用 `insta` 或类似工具）

#### 6.3.6 文档与工具

- 生成实验性 API 文档工具：扫描所有 `ExperimentalField` 注册，生成 Markdown 文档
- IDE 插件支持：在编辑器中高亮显示实验性字段

### 6.4 维护建议

1. **版本兼容性**：实验性 API 稳定后，需要机制移除 `#[experimental]` 标记，宏应支持平滑迁移
2. **Reason 命名规范**：建议制定统一的 reason 命名规范（如 `method/field` 或 `module.method.field`）
3. **与 OpenAPI/JSON Schema 集成**：实验性标记应同步到生成的 Schema 中

---

## 附录：关键代码片段

### A.1 生成的代码示例

对于以下输入：

```rust
#[derive(ExperimentalApi)]
struct ThreadStartParams {
    #[experimental("thread/start.dynamicTools")]
    dynamic_tools: Option<Vec<DynamicToolSpec>>,
    #[experimental(nested)]
    approval_policy: Option<AskForApproval>,
}
```

宏生成的代码大致为：

```rust
impl ThreadStartParams {
    pub(crate) const EXPERIMENTAL_FIELDS: &'static [ExperimentalField] = &[
        ExperimentalField {
            type_name: "ThreadStartParams",
            field_name: "dynamicTools",
            reason: "thread/start.dynamicTools",
        },
        ExperimentalField {
            type_name: "ThreadStartParams",
            field_name: "approvalPolicy",
            reason: "askForApproval.granular",  // 来自嵌套类型
        },
    ];
}

impl ExperimentalApi for ThreadStartParams {
    fn experimental_reason(&self) -> Option<&'static str> {
        // 检查 dynamic_tools
        if self.dynamic_tools.as_ref().is_some_and(|v| !v.is_empty()) {
            return Some("thread/start.dynamicTools");
        }
        // 检查嵌套的 approval_policy
        if let Some(reason) = ExperimentalApi::experimental_reason(&self.approval_policy) {
            return Some(reason);
        }
        None
    }
}

// inventory 注册
::inventory::submit! {
    ExperimentalField { ... }
}
```

### A.2 权限检查流程

```rust
// app-server/src/message_processor.rs:616-626
if let Some(reason) = codex_request.experimental_reason()
    && !session.experimental_api_enabled
{
    let error = JSONRPCErrorError {
        code: INVALID_REQUEST_ERROR_CODE,
        message: experimental_required_message(reason),
        data: None,
    };
    self.outgoing.send_error(connection_request_id, error).await;
    return;
}
```

---

*文档生成时间：2026-03-23*
*基于代码版本：codex-rs/codex-experimental-api-macros/src/lib.rs (329 lines)*
