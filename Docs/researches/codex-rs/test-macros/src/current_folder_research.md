# codex-rs/test-macros/src 研究文档

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 定位

`codex-rs/test-macros` 是 Codex 项目的 Rust 测试辅助宏库，专门提供**过程宏（proc-macro）**来增强测试能力。该 crate 位于工作区 `codex-rs/test-macros/` 目录下，是 Codex Rust 代码库的基础测试设施之一。

### 核心职责

该 crate 的核心职责是提供单一但关键的测试宏 `#[large_stack_test]`，用于解决 Rust 测试中常见的**栈溢出**问题：

1. **大栈测试支持**：为需要大栈空间的测试用例提供 16MB 的专用线程栈空间
2. **异步测试兼容**：支持 `async` 测试函数，自动创建 Tokio 运行时
3. **属性自动管理**：智能处理测试属性（如 `#[test]`、`#[tokio::test]`、`#[test_case]`）的冲突与合并

### 使用场景

在 Codex 项目中，以下场景需要使用 `#[large_stack_test]`：

- **集成测试**：特别是涉及复杂文件操作、补丁应用的测试（如 `apply_patch_cli.rs` 中的 40+ 个测试用例）
- **递归深度大的测试**：如 AST 遍历、复杂数据结构处理
- **异步集成测试**：需要 Tokio 运行时且栈需求较大的测试

### 典型使用示例

```rust
// 基本用法 - 同步测试
#[large_stack_test]
fn test_deep_recursion() {
    // 递归深度较大的测试逻辑
}

// 异步测试
#[large_stack_test]
async fn test_async_operation() {
    // 异步测试逻辑
}

// 与 test_case 组合使用
#[large_stack_test]
#[test_case(ApplyPatchModelOutput::Freeform)]
#[test_case(ApplyPatchModelOutput::Function)]
async fn test_multiple_cases(output_type: ApplyPatchModelOutput) {
    // 参数化测试
}
```

---

## 功能点目的

### 1. 解决默认线程栈空间不足问题

Rust 标准库的测试运行器使用默认线程栈大小（通常 2MB 或 8MB，取决于平台），这在以下情况下可能不足：

- 深度递归调用
- 大量栈分配的临时数据结构
- 复杂的宏展开或解析逻辑

`#[large_stack_test]` 通过创建自定义栈大小（16MB）的线程来解决此问题。

### 2. 简化测试编写

开发者无需手动编写线程创建和同步代码，只需添加属性宏即可：

```rust
// 不使用宏 - 需要手动管理线程
#[test]
fn test_with_large_stack() {
    let handle = std::thread::Builder::new()
        .stack_size(16 * 1024 * 1024)
        .spawn(|| {
            // 实际测试逻辑
        })
        .unwrap();
    handle.join().unwrap();
}

// 使用宏 - 简洁明了
#[large_stack_test]
fn test_with_large_stack() {
    // 实际测试逻辑
}
```

### 3. 属性智能处理

宏会自动处理与其他测试属性的交互：

| 属性 | 处理方式 | 原因 |
|------|----------|------|
| `#[test]` | 保留（如果不存在则添加） | 确保测试框架识别 |
| `#[tokio::test]` | 移除 | 宏内部自建 Tokio 运行时，避免冲突 |
| `#[test_case]` | 保留 | 支持参数化测试 |

---

## 具体技术实现

### 核心数据结构

#### 1. 栈大小常量

```rust
const LARGE_STACK_TEST_STACK_SIZE_BYTES: usize = 16 * 1024 * 1024; // 16MB
```

该值是硬编码的经验值，足以覆盖 Codex 项目中所有已知的大栈测试需求。

#### 2. 函数属性过滤逻辑

宏通过 `filtered_attributes` 函数处理输入函数的属性：

```rust
fn filtered_attributes(attrs: &[Attribute]) -> Vec<Attribute> {
    let mut filtered = Vec::with_capacity(attrs.len() + 1);
    let mut has_test_attr = false;

    for attr in attrs {
        if is_tokio_test_attr(attr) {
            continue;  // 移除 tokio::test
        }
        if is_test_attr(attr) || is_test_case_attr(attr) {
            has_test_attr = true;
        }
        filtered.push(attr.clone());
    }

    if !has_test_attr {
        filtered.push(parse_quote!(#[test]));  // 添加默认 test 属性
    }

    filtered
}
```

### 关键流程

#### 1. 宏展开流程

```
输入: #[large_stack_test] async fn test_example() { ... }

步骤 1: 解析输入
  - 解析属性参数（无参数，使用 syn::parse::Nothing）
  - 解析函数定义（使用 syn::ItemFn）

步骤 2: 处理属性
  - 过滤掉 #[tokio::test]
  - 保留 #[test_case] 等其他属性
  - 如果没有测试属性，添加 #[test]

步骤 3: 生成线程体
  - 如果是 async 函数：
    * 创建 Tokio multi-thread 运行时（2 个 worker 线程）
    * 使用 runtime.block_on() 执行异步代码
  - 如果是同步函数：
    * 直接使用原始函数体

步骤 4: 包装函数体
  - 使用 std::thread::Builder 创建线程
  - 设置栈大小为 16MB
  - 设置线程名为函数名
  - 使用 join() 等待线程完成
  - 正确处理 panic 传播

输出: 转换后的函数定义
```

#### 2. 异步测试运行时构建

```rust
let runtime = ::tokio::runtime::Builder::new_multi_thread()
    .worker_threads(2)
    .enable_all()
    .build()
    .unwrap_or_else(|error| {
        panic!("failed to build tokio runtime for large-stack test: {error}")
    });
runtime.block_on(async move #body)
```

关键点：
- 使用 `new_multi_thread()` 创建多线程运行时
- 固定 2 个 worker 线程（平衡资源使用与并发能力）
- `enable_all()` 启用所有特性（IO、定时器等）
- 使用 `block_on` 在独立线程中执行异步代码

#### 3. 线程创建与错误处理

```rust
let handle = ::std::thread::Builder::new()
    .name(::std::string::String::from(::std::stringify!(#name)))
    .stack_size(#LARGE_STACK_TEST_STACK_SIZE_BYTES)
    .spawn(move || #thread_body)
    .unwrap_or_else(|error| {
        panic!("failed to spawn large-stack test thread: {error}")
    });

match handle.join() {
    Ok(result) => result,
    Err(payload) => ::std::panic::resume_unwind(payload),
}
```

关键点：
- 使用 `std::thread::Builder` 设置自定义栈大小
- 线程名与函数名一致，便于调试
- 使用 `resume_unwind` 正确传播 panic，保持测试失败行为一致

### 属性检测实现

#### 检测 `#[test]`

```rust
fn is_test_attr(attr: &Attribute) -> bool {
    attr.path().is_ident("test")
}
```

#### 检测 `#[test_case]`

```rust
fn is_test_case_attr(attr: &Attribute) -> bool {
    attr.path().is_ident("test_case")
}
```

#### 检测 `#[tokio::test]`

```rust
fn is_tokio_test_attr(attr: &Attribute) -> bool {
    let mut segments = attr.path().segments.iter();
    matches!(
        (segments.next(), segments.next(), segments.next()),
        (Some(first), Some(second), None) 
            if first.ident == "tokio" && second.ident == "test"
    )
}
```

注意：该检测要求路径**恰好**有两个 segment（`tokio` 和 `test`），不支持 `#[tokio::test(flavor = "multi_thread")]` 这种带参数的形式的精确匹配，但由于是遍历所有属性，带参数的也会被匹配到。

---

## 关键代码路径与文件引用

### 源文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/test-macros/src/lib.rs` | 宏实现主文件（155 行） |

### 配置文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/test-macros/Cargo.toml` | Crate 配置，声明 proc-macro = true |
| `codex-rs/test-macros/BUILD.bazel` | Bazel 构建配置 |
| `codex-rs/Cargo.toml` | 工作区配置，定义 codex-test-macros 依赖 |

### 使用方

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/core/Cargo.toml` | 在 dev-dependencies 中依赖 codex-test-macros |
| `codex-rs/core/tests/suite/apply_patch_cli.rs` | 主要使用方，40+ 个测试用例使用 #[large_stack_test] |

### 构建规则

| 文件路径 | 说明 |
|----------|------|
| `defs.bzl` | 定义 `codex_rust_crate` 宏，支持 proc_macro 参数 |

---

## 依赖与外部交互

### 编译时依赖

```toml
[dependencies]
proc-macro2 = "1"    # TokenStream 操作
quote = "1"          # 代码生成（quote! 宏）
syn = { version = "2", features = ["full"] }  # Rust 语法解析
```

#### proc-macro2

- **用途**：提供 `TokenStream2` 类型，比标准库的 `TokenStream` 更易于操作
- **关键使用**：`quote!` 宏生成代码时返回 `TokenStream2`

#### quote

- **用途**：提供 `quote!` 宏用于生成 Rust 代码
- **关键使用**：生成线程创建、Tokio 运行时构建等模板代码

#### syn

- **用途**：解析 Rust 源代码为 AST
- **关键使用**：
  - `syn::ItemFn`：解析函数定义
  - `syn::Attribute`：处理属性
  - `syn::parse_quote!`：解析内联代码片段
  - `syn::parse2`：将 `TokenStream2` 解析回 AST

### 运行时依赖

宏生成的代码在运行时依赖：

- **标准库**：`std::thread::Builder`, `std::panic::resume_unwind`
- **Tokio**（可选）：`tokio::runtime::Builder`（仅当测试函数是 async 时）

### 与测试框架的交互

```
┌─────────────────────────────────────────────────────────────┐
│                      测试编译阶段                            │
│  1. rustc 遇到 #[large_stack_test]                          │
│  2. 调用 proc_macro  crate (codex-test-macros)              │
│  3. 宏展开生成新的函数定义                                    │
│  4. 生成的函数带有 #[test] 属性                               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      测试运行阶段                            │
│  1. 测试框架（cargo test）发现 #[test] 函数                   │
│  2. 调用生成的包装函数                                        │
│  3. 包装函数创建大栈线程                                      │
│  4. 在线程中执行实际测试逻辑                                  │
│  5. 等待线程完成并返回结果                                    │
└─────────────────────────────────────────────────────────────┘
```

### 与 Bazel 构建系统的集成

```python
# BUILD.bazel
codex_rust_crate(
    name = "test-macros",
    crate_name = "codex_test_macros",
    proc_macro = True,  # 标记为 proc-macro crate
)
```

`defs.bzl` 中的 `codex_rust_crate` 宏会根据 `proc_macro` 参数选择使用 `rust_proc_macro` 或 `rust_library` 规则。

---

## 风险、边界与改进建议

### 已知风险

#### 1. 栈大小硬编码

**风险**：16MB 栈大小是硬编码的，可能不适用于所有场景。

```rust
const LARGE_STACK_TEST_STACK_SIZE_BYTES: usize = 16 * 1024 * 1024;
```

**影响**：
- 对于某些极端测试可能仍然不足
- 对于简单测试可能浪费内存

**建议**：考虑支持属性参数自定义栈大小：

```rust
#[large_stack_test(stack_size = 32 * 1024 * 1024)]
fn test_extreme_case() { }
```

#### 2. Tokio 运行时配置固定

**风险**：Tokio 运行时固定使用 2 个 worker 线程：

```rust
::tokio::runtime::Builder::new_multi_thread()
    .worker_threads(2)
```

**影响**：
- 可能与某些需要特定运行时配置的测试冲突
- 无法使用 `#[tokio::test(flavor = "current_thread")]` 等配置

**建议**：考虑通过属性参数传递运行时配置。

#### 3. 属性检测的局限性

**风险**：`is_tokio_test_attr` 只检测 `tokio::test`，不支持：
- `tokio::test(flavor = "...")` 的参数化形式
- 其他异步测试运行时（如 `async-std`）

**影响**：
- 使用其他异步运行时可能导致意外行为
- 带参数的 `tokio::test` 属性处理可能不完全

#### 4. 错误信息丢失

**风险**：使用 `unwrap_or_else` 和 `panic!` 处理错误：

```rust
.spawn(move || #thread_body)
.unwrap_or_else(|error| {
    panic!("failed to spawn large-stack test thread: {error}")
});
```

**影响**：错误信息可能不够详细，难以诊断问题。

### 边界条件

#### 1. 与 `#[should_panic]` 的交互

未明确测试与 `#[should_panic]` 属性的交互。由于宏使用 `resume_unwind` 传播 panic，理论上应该兼容，但需要验证。

#### 2. 与 `serial_test` 的交互

在 `apply_patch_cli.rs` 中，`#[large_stack_test]` 与 `#[test_case]` 组合使用，但未与 `serial_test` 等需要串行执行的属性组合使用。

#### 3. 嵌套使用

不支持嵌套使用（即一个测试函数同时使用多个 `#[large_stack_test]`），但这在实际中没有意义。

### 改进建议

#### 1. 支持自定义栈大小

```rust
#[proc_macro_attribute]
pub fn large_stack_test(attr: TokenStream, item: TokenStream) -> TokenStream {
    // 解析可选的栈大小参数
    let args = parse_macro_input!(attr as LargeStackArgs);
    let stack_size = args.stack_size.unwrap_or(LARGE_STACK_TEST_STACK_SIZE_BYTES);
    // ...
}
```

#### 2. 增强 Tokio 运行时配置

```rust
#[large_stack_test(tokio_threads = 4)]
async fn test_with_more_threads() { }
```

#### 3. 支持更多异步运行时

添加对 `async-std` 等其他异步运行时的支持：

```rust
fn is_async_std_test_attr(attr: &Attribute) -> bool {
    // 检测 async_std::test
}
```

#### 4. 改进错误处理

使用 `Result` 类型和 `?` 操作符替代 `unwrap_or_else`，提供更详细的错误上下文。

#### 5. 添加更多测试覆盖

当前 crate 自身的测试只有 2 个：

```rust
#[cfg(test)]
mod tests {
    #[test]
    fn adds_test_attribute_when_missing() { }

    #[test]
    fn removes_tokio_test_and_keeps_test_case() { }
}
```

建议添加：
- 同步函数测试
- 多层属性组合测试
- 错误处理测试

#### 6. 文档改进

在宏的文档注释中添加更多使用示例：

```rust
/// # Examples
///
/// Basic synchronous test:
/// ```
/// #[large_stack_test]
/// fn test_sync() { }
/// ```
///
/// Async test:
/// ```
/// #[large_stack_test]
/// async fn test_async() { }
/// ```
///
/// With test_case:
/// ```
/// #[large_stack_test]
/// #[test_case(1)]
/// #[test_case(2)]
/// async fn test_parametrized(x: i32) { }
/// ```
```

### 维护建议

1. **监控使用范围**：定期检查新添加的测试是否也需要 `#[large_stack_test]`
2. **栈大小调优**：如果未来 16MB 不足，考虑增加或支持配置
3. **与测试框架同步**：关注 Rust 测试框架和 Tokio 的更新，确保兼容性
4. **文档同步**：当添加新功能时，同步更新 AGENTS.md 中的相关说明

---

## 总结

`codex-rs/test-macros/src/lib.rs` 是一个简洁但关键的测试基础设施组件。它通过单一宏 `#[large_stack_test]` 解决了 Rust 测试中栈空间不足的问题，同时保持了对异步测试和参数化测试的良好兼容。代码实现清晰，测试覆盖基本场景，但在可配置性和扩展性方面仍有改进空间。
