# codex-rs/test-macros 深度研究文档

## 1. 场景与职责

### 1.1 定位与目标

`codex-test-macros` 是 Codex 项目中专门用于测试基础设施的 **过程宏（proc-macro）crate**。其核心职责是提供一个属性宏 `#[large_stack_test]`，用于解决 Rust 测试中的 **栈溢出（Stack Overflow）** 问题。

### 1.2 解决的问题场景

在 Codex 项目的集成测试中，特别是 `codex-rs/core/tests/suite/apply_patch_cli.rs` 中的测试用例，存在以下挑战：

1. **深层调用链**：apply_patch 相关的集成测试涉及复杂的异步操作、文件系统交互、沙箱执行等，调用栈深度较大
2. **递归解析**：patch 解析和验证逻辑可能涉及递归操作
3. **默认栈空间不足**：Rust 默认的线程栈空间（通常为 2MB）在复杂集成测试中容易耗尽

### 1.3 项目上下文

```
codex-rs/
├── test-macros/          # 本 crate：提供 large_stack_test 宏
│   ├── src/lib.rs        # 宏实现
│   ├── Cargo.toml        # crate 配置
│   └── BUILD.bazel       # Bazel 构建配置
├── core/
│   ├── tests/
│   │   ├── suite/
│   │   │   └── apply_patch_cli.rs  # 主要使用者：~35 个测试用例
│   │   └── common/       # 测试支持库
│   └── Cargo.toml        # 依赖 codex-test-macros
└── arg0/src/lib.rs       # 生产环境使用相同的栈大小配置
```

---

## 2. 功能点目的

### 2.1 `#[large_stack_test]` 宏

该宏的主要功能：

| 功能 | 说明 |
|------|------|
 **大栈空间** | 为测试函数分配 **16MB** 栈空间（默认通常 2MB） |
| **异步支持** | 自动检测 `async fn`，创建 Tokio 多线程运行时 |
| **属性兼容** | 与 `#[test]`、`#[test_case]`、`#[tokio::test]` 无缝协作 |
| **自动注入** | 无 `#[test]` 时自动添加，避免重复 |

### 2.2 设计决策

**为什么 16MB？**
- 与生产环境保持一致：`codex-rs/arg0/src/lib.rs:18` 中 `TOKIO_WORKER_STACK_SIZE_BYTES = 16 * 1024 * 1024`
- 足够覆盖最复杂的集成测试场景
- 不会过度消耗系统资源（现代开发机器通常有足够内存）

**为什么是独立 crate？**
- 过程宏必须在独立的 proc-macro crate 中定义
- 允许多个 crate 共享相同的测试基础设施
- 符合 Rust 生态的最佳实践

---

## 3. 具体技术实现

### 3.1 核心常量

```rust
// src/lib.rs:10
const LARGE_STACK_TEST_STACK_SIZE_BYTES: usize = 16 * 1024 * 1024; // 16MB
```

### 3.2 宏展开逻辑

#### 3.2.1 同步函数展开

输入：
```rust
#[large_stack_test]
fn my_test() {
    // test body
}
```

展开后（简化）：
```rust
#[test]
fn my_test() {
    let handle = ::std::thread::Builder::new()
        .name(::std::string::String::from("my_test"))
        .stack_size(16 * 1024 * 1024)  // 16MB
        .spawn(move || {
            // original test body
        })
        .unwrap_or_else(|error| {
            panic!("failed to spawn large-stack test thread: {error}")
        });

    match handle.join() {
        Ok(result) => result,
        Err(payload) => ::std::panic::resume_unwind(payload),
    }
}
```

#### 3.2.2 异步函数展开

输入：
```rust
#[large_stack_test]
async fn my_async_test() {
    // async test body
}
```

展开后（简化）：
```rust
#[test]
fn my_async_test() {
    let handle = ::std::thread::Builder::new()
        .name(::std::string::String::from("my_async_test"))
        .stack_size(16 * 1024 * 1024)
        .spawn(move || {
            // 创建 Tokio 多线程运行时
            let runtime = ::tokio::runtime::Builder::new_multi_thread()
                .worker_threads(2)
                .enable_all()
                .build()
                .unwrap_or_else(|error| {
                    panic!("failed to build tokio runtime for large-stack test: {error}")
                });
            runtime.block_on(async move {
                // original async test body
            })
        })
        .unwrap_or_else(|error| {
            panic!("failed to spawn large-stack test thread: {error}")
        });

    match handle.join() {
        Ok(result) => result,
        Err(payload) => ::std::panic::resume_unwind(payload),
    }
}
```

### 3.3 属性过滤逻辑

```rust
fn filtered_attributes(attrs: &[Attribute]) -> Vec<Attribute> {
    let mut filtered = Vec::with_capacity(attrs.len() + 1);
    let mut has_test_attr = false;

    for attr in attrs {
        if is_tokio_test_attr(attr) {
            // 移除 #[tokio::test]，因为我们会自己创建运行时
            continue;
        }
        if is_test_attr(attr) || is_test_case_attr(attr) {
            has_test_attr = true;
        }
        filtered.push(attr.clone());
    }

    // 自动添加 #[test]（如果不存在）
    if !has_test_attr {
        filtered.push(parse_quote!(#[test]));
    }

    filtered
}
```

### 3.4 属性检测规则

| 属性 | 处理方式 | 说明 |
|------|----------|------|
| `#[test]` | 保留 | 标准测试属性 |
| `#[test_case(...)]` | 保留 | `test-case` crate 的参数化测试 |
| `#[tokio::test]` | **移除** | 避免冲突，宏内部自行创建运行时 |

---

## 4. 关键代码路径与文件引用

### 4.1 宏实现文件

| 文件 | 行数 | 关键内容 |
|------|------|----------|
| `codex-rs/test-macros/src/lib.rs` | 155 | 完整宏实现 |

### 4.2 关键函数

```
lib.rs
├── large_stack_test()           # 宏入口点 (line 17-23)
├── expand_large_stack_test()    # 展开逻辑 (line 25-66)
│   ├── 提取并过滤属性
│   ├── 检测 async 关键字
│   ├── 生成线程创建代码
│   └── 替换函数体
├── filtered_attributes()        # 属性过滤 (line 68-87)
├── is_test_attr()               # 检测 #[test] (line 89-91)
├── is_test_case_attr()          # 检测 #[test_case] (line 93-95)
└── is_tokio_test_attr()         # 检测 #[tokio::test] (line 97-103)
```

### 4.3 使用方文件

| 文件 | 使用次数 | 场景 |
|------|----------|------|
| `codex-rs/core/tests/suite/apply_patch_cli.rs` | ~35 次 | apply_patch 集成测试 |

典型使用模式：
```rust
// codex-rs/core/tests/suite/apply_patch_cli.rs:6
use codex_test_macros::large_stack_test;

// 与 test_case 组合使用 (line 90-95)
#[large_stack_test]
#[test_case(ApplyPatchModelOutput::Freeform)]
#[test_case(ApplyPatchModelOutput::Function)]
#[test_case(ApplyPatchModelOutput::Shell)]
#[test_case(ApplyPatchModelOutput::ShellViaHeredoc)]
async fn apply_patch_cli_multiple_operations_integration(
    output_type: ApplyPatchModelOutput,
) -> Result<()> {
    // ...
}
```

### 4.4 相关配置文件

| 文件 | 作用 |
|------|------|
| `codex-rs/test-macros/Cargo.toml` | crate 定义，启用 `proc-macro = true` |
| `codex-rs/test-macros/BUILD.bazel` | Bazel 构建配置，`proc_macro = True` |
| `codex-rs/core/Cargo.toml` | 依赖声明 `codex-test-macros = { workspace = true }` |
| `codex-rs/Cargo.toml` | workspace 成员定义 |

---

## 5. 依赖与外部交互

### 5.1 依赖树

```
codex-test-macros
├── proc-macro2 = "1"          # TokenStream 操作
├── quote = "1"                # 代码生成模板
└── syn = { version = "2",     # Rust 语法解析
            features = ["full"] }
```

### 5.2 与测试生态的集成

```
codex-rs/core/tests/
├── suite/apply_patch_cli.rs
│   ├── codex_test_macros::large_stack_test  # 本宏
│   ├── test_case::test_case                 # 参数化测试
│   └── tokio (间接通过宏)                   # 异步运行时
│
└── common/ (core_test_support)
    ├── test_codex.rs        # TestCodex 测试框架
    ├── responses.rs         # Mock 服务器支持
    └── ...
```

### 5.3 与生产代码的对应关系

生产环境同样使用 16MB 栈配置：

```rust
// codex-rs/arg0/src/lib.rs:18
const TOKIO_WORKER_STACK_SIZE_BYTES: usize = 16 * 1024 * 1024;

// codex-rs/arg0/src/lib.rs:179-184
fn build_runtime() -> anyhow::Result<tokio::runtime::Runtime> {
    let mut builder = tokio::runtime::Builder::new_multi_thread();
    builder.enable_all();
    builder.thread_stack_size(TOKIO_WORKER_STACK_SIZE_BYTES);
    Ok(builder.build()?)
}
```

这确保了 **测试环境与生产环境的一致性**。

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 线程命名冲突
```rust
.name(::std::string::String::from(::std::stringify!(#name)))
```
- 使用函数名作为线程名，如果同一测试中并发运行多个大栈测试，线程名可能重复
- **影响**：低，仅影响调试体验

#### 6.1.2 运行时创建失败
```rust
let runtime = ::tokio::runtime::Builder::new_multi_thread()
    .worker_threads(2)
    .enable_all()
    .build()
```
- 如果系统资源不足，运行时创建可能失败
- **缓解**：明确的 panic 消息

#### 6.1.3 与某些测试框架的兼容性
- 目前仅处理 `#[tokio::test]`，其他异步测试运行时（如 `async-std`）未处理
- **影响**：低，项目统一使用 Tokio

### 6.2 边界情况

| 场景 | 行为 | 测试覆盖 |
|------|------|----------|
| 无 `#[test]` 属性 | 自动添加 | ✅ `adds_test_attribute_when_missing` |
| 有 `#[test]` 属性 | 保留原属性 | ✅ 隐式覆盖 |
| 有 `#[test_case]` | 保留，移除 `#[tokio::test]` | ✅ `removes_tokio_test_and_keeps_test_case` |
| 同步函数 | 直接执行函数体 | ✅ 实际使用 |
| 异步函数 | 创建 Tokio 运行时 | ✅ 实际使用 |

### 6.3 改进建议

#### 6.3.1 可配置栈大小（低优先级）

```rust
#[large_stack_test(stack_size = 32 * 1024 * 1024)]  // 32MB for extreme cases
```

**理由**：某些极端测试可能需要更大栈空间，但目前 16MB 已足够。

#### 6.3.2 支持更多测试运行时（低优先级）

添加对 `async-std`、`smol` 等其他异步运行时的检测支持。

**理由**：项目目前统一使用 Tokio，此改进优先级低。

#### 6.3.3 线程池复用（中等优先级）

考虑使用线程池复用大栈线程，而非每个测试创建新线程。

**理由**：
- 减少测试套件的总执行时间
- 降低线程创建开销
- **挑战**：需要处理测试隔离和 panic 传播

#### 6.3.4 文档改进（高优先级）

添加更多使用示例到 crate-level 文档：

```rust
/// # Examples
/// 
/// Basic usage:
/// ```
/// use codex_test_macros::large_stack_test;
/// 
/// #[large_stack_test]
/// fn test_deep_recursion() {
///     // This test has 16MB of stack space
/// }
/// ```
/// 
/// With test_case:
/// ```
/// use codex_test_macros::large_stack_test;
/// use test_case::test_case;
/// 
/// #[large_stack_test]
/// #[test_case(1)]
/// #[test_case(2)]
/// async fn test_with_params(n: usize) {
///     // Async test with parameters
/// }
/// ```
```

### 6.4 监控与度量

建议添加（可选）的栈使用监控：

```rust
#[cfg(feature = "stack-usage-stats")]
fn report_stack_usage() {
    // 使用 stacker 或类似 crate 监控实际栈使用
}
```

这可以帮助确定 16MB 是否过度配置或不足。

---

## 7. 总结

`codex-test-macros` 是一个 **小而精的测试基础设施组件**，通过提供 `#[large_stack_test]` 宏，解决了 Codex 项目中复杂集成测试的栈溢出问题。其设计简洁、与生产环境保持一致、与现有测试生态无缝集成。

关键成功因素：
1. **一致性**：测试和生产环境使用相同的 16MB 栈配置
2. **透明性**：开发者只需添加属性，无需了解底层线程创建细节
3. **兼容性**：与 `test-case`、`tokio` 等主流测试工具链良好协作
