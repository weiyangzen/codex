# Research: codex-rs/test-macros/src/lib.rs

## 概述

`codex-rs/test-macros/src/lib.rs` 是一个 Rust 过程宏（proc-macro）库，为 Codex 项目的集成测试提供大栈空间测试支持。该宏通过将测试函数包装在具有 16MB 栈空间的独立线程中执行，解决了 Rust 默认栈空间（通常 2MB）不足以支持复杂异步测试的问题。

---

## 场景与职责

### 核心场景

1. **栈溢出防护**：Codex 核心库的集成测试涉及复杂的异步操作、递归解析和大量数据处理，默认栈空间容易导致栈溢出（stack overflow）
2. **异步测试支持**：为 `#[tokio::test]` 异步测试提供大栈空间执行环境
3. **测试框架兼容性**：与 `#[test]`、`#[test_case]`、`#[tokio::test]` 等主流测试属性兼容

### 主要职责

| 职责 | 说明 |
|------|------|
| 线程包装 | 将测试函数体包装在独立线程中执行 |
| 栈空间配置 | 配置 16MB 线程栈空间（`16 * 1024 * 1024` bytes） |
| 异步运行时管理 | 为 async 测试创建 Tokio multi-thread runtime |
| 属性过滤 | 智能处理测试属性，避免冲突 |
| 错误传播 | 正确处理线程 panic 和错误传播 |

---

## 功能点目的

### 1. `#[large_stack_test]` 宏

**位置**: `lib.rs:17-23`

**目的**: 提供声明式大栈空间测试注解，使开发者能够轻松标记需要大栈空间的测试函数。

**使用示例**:
```rust
#[large_stack_test]
async fn test_complex_operation() -> Result<()> {
    // 测试代码在 16MB 栈空间中执行
}

#[large_stack_test]
#[test_case(ApplyPatchModelOutput::Freeform)]
async fn test_with_params(output_type: ApplyPatchModelOutput) -> Result<()> {
    // 与 test_case 兼容
}
```

### 2. 属性过滤机制

**位置**: `lib.rs:68-103`

**目的**: 处理测试属性冲突，确保生成的测试函数具有正确的属性组合。

**处理规则**:
- 移除 `#[tokio::test]`：避免与宏内部创建的 runtime 冲突
- 保留 `#[test_case(...)]`：支持参数化测试
- 自动添加 `#[test]`：如果原函数没有测试属性

### 3. 异步运行时创建

**位置**: `lib.rs:33-48`

**目的**: 为 async 测试函数创建合适的 Tokio runtime。

**配置**:
- Runtime 类型: `multi_thread`
- Worker 线程数: 2
- 功能启用: `enable_all()`（包含 IO、定时器等）

---

## 具体技术实现

### 关键流程

#### 1. 宏展开流程

```
#[large_stack_test]
async fn my_test() { ... }

↓ 展开后 ↓

#[test]  // 自动添加
fn my_test() {
    let handle = std::thread::Builder::new()
        .name("my_test")
        .stack_size(16 * 1024 * 1024)
        .spawn(move || {
            let runtime = tokio::runtime::Builder::new_multi_thread()
                .worker_threads(2)
                .enable_all()
                .build()
                .unwrap();
            runtime.block_on(async move { ... })
        })
        .unwrap();
    
    match handle.join() {
        Ok(result) => result,
        Err(payload) => std::panic::resume_unwind(payload),
    }
}
```

#### 2. 代码生成逻辑

**位置**: `lib.rs:25-66`

```rust
fn expand_large_stack_test(mut item: ItemFn) -> TokenStream2 {
    // 1. 过滤属性
    let attrs = filtered_attributes(&item.attrs);
    item.attrs = attrs;

    // 2. 检测是否为 async 函数
    let is_async = item.sig.asyncness.take().is_some();
    let name = &item.sig.ident;
    let body = &item.block;

    // 3. 生成线程体
    let thread_body = if is_async {
        // 创建 Tokio runtime 并执行 async block
        quote! { ... }
    } else {
        // 直接使用函数体
        quote! { #body }
    };

    // 4. 替换函数体为线程包装代码
    *item.block = parse_quote!({
        let handle = ::std::thread::Builder::new()
            .name(::std::string::String::from(::std::stringify!(#name)))
            .stack_size(#LARGE_STACK_TEST_STACK_SIZE_BYTES)
            .spawn(move || #thread_body)
            .unwrap_or_else(|error| { panic!(...) });

        match handle.join() {
            Ok(result) => result,
            Err(payload) => ::std::panic::resume_unwind(payload),
        }
    });

    quote! { #item }
}
```

### 数据结构

#### 常量定义

```rust
const LARGE_STACK_TEST_STACK_SIZE_BYTES: usize = 16 * 1024 * 1024;
```

#### 依赖的 syn 类型

| 类型 | 用途 |
|------|------|
| `ItemFn` | 解析和修改函数定义 |
| `Attribute` | 处理函数属性 |
| `TokenStream` / `TokenStream2` | 输入输出 token 流 |

### 属性检测函数

**位置**: `lib.rs:89-103`

```rust
fn is_test_attr(attr: &Attribute) -> bool {
    attr.path().is_ident("test")
}

fn is_test_case_attr(attr: &Attribute) -> bool {
    attr.path().is_ident("test_case")
}

fn is_tokio_test_attr(attr: &Attribute) -> bool {
    let mut segments = attr.path().segments.iter();
    matches!(
        (segments.next(), segments.next(), segments.next()),
        (Some(first), Some(second), None) 
            if first.ident == "tokio" && second.ident == "test"
    )
}
```

---

## 关键代码路径与文件引用

### 当前文件结构

```
codex-rs/test-macros/
├── Cargo.toml          # 包配置，声明 proc-macro = true
├── BUILD.bazel         # Bazel 构建配置
└── src/
    └── lib.rs          # 宏实现（本研究对象）
```

### 调用方（使用者）

**主要使用者**: `codex-rs/core/tests/suite/apply_patch_cli.rs`

```rust
// codex-rs/core/tests/suite/apply_patch_cli.rs:6
use codex_test_macros::large_stack_test;

// 大量使用示例（约 30+ 处）
#[large_stack_test]
#[test_case(ApplyPatchModelOutput::Freeform)]
async fn apply_patch_cli_multiple_operations_integration(
    output_type: ApplyPatchModelOutput,
) -> Result<()> { ... }
```

**其他潜在使用者**: 任何需要大栈空间的 Codex 集成测试

### 依赖关系

#### Cargo.toml 依赖

```toml
[package]
name = "codex-test-macros"
version.workspace = true
edition.workspace = true
license.workspace = true

[lib]
proc-macro = true

[dependencies]
proc-macro2 = "1"      # Token 流操作
quote = "1"            # 代码生成
syn = { version = "2", features = ["full"] }  # Rust 语法解析
```

#### 项目级依赖链

```
codex-rs/core/Cargo.toml (dev-dependencies)
    ↓
codex-test-macros = { workspace = true }
    ↓
codex-rs/Cargo.toml (workspace.dependencies)
    ↓
codex-test-macros = { path = "test-macros" }
```

### 相关栈空间配置

**对比其他模块的栈空间配置**:

| 文件 | 栈空间 | 用途 |
|------|--------|------|
| `test-macros/src/lib.rs` | 16 MB | 测试线程 |
| `arg0/src/lib.rs:18` | 16 MB | Tokio worker 线程（生产环境） |
| `core/tests/suite/rmcp_client.rs:862` | 8 MB | 特定测试（OAuth HTTP 测试） |

---

## 依赖与外部交互

### 编译时依赖

| Crate | 版本 | 用途 |
|-------|------|------|
| `proc-macro2` | 1.x | 提供 `TokenStream2`，支持跨版本兼容 |
| `quote` | 1.x | 提供 `quote!` 宏，简化代码生成 |
| `syn` | 2.x (full) | 解析 Rust 语法树，支持完整语法 |

### 运行时依赖（生成代码依赖）

| 模块 | 说明 |
|------|------|
| `std::thread` | 线程创建和管理 |
| `tokio::runtime` | 异步运行时（被测试代码依赖） |

### 与测试框架的交互

```
┌─────────────────────────────────────────────────────────────┐
│                    测试执行流程                              │
├─────────────────────────────────────────────────────────────┤
│  cargo test                                                  │
│       │                                                      │
│       ▼                                                      │
│  #[large_stack_test] 宏展开                                  │
│       │                                                      │
│       ▼                                                      │
│  生成 #[test] 函数                                           │
│       │                                                      │
│       ▼                                                      │
│  创建线程 (16MB 栈)                                          │
│       │                                                      │
│       ├── 同步测试 ──▶ 直接执行测试体                         │
│       │                                                      │
│       └── 异步测试 ──▶ 创建 Tokio Runtime ──▶ 执行 async 体   │
│                                                              │
│       ▼                                                      │
│  join() 等待完成，传播 panic                                 │
└─────────────────────────────────────────────────────────────┘
```

---

## 风险、边界与改进建议

### 已知风险

#### 1. 栈空间硬编码

**风险**: 16MB 栈空间是经验值，未来可能不足以支持更复杂的测试场景。

**代码位置**: `lib.rs:10`

```rust
const LARGE_STACK_TEST_STACK_SIZE_BYTES: usize = 16 * 1024 * 1024;
```

**缓解**: 当前与生产环境 `arg0/src/lib.rs` 保持一致，如需调整需同步修改。

#### 2. Tokio Runtime 配置固定

**风险**: 固定使用 2 个 worker 线程，可能不适合所有测试场景。

**代码位置**: `lib.rs:36-37`

```rust
.worker_threads(2)
```

#### 3. Panic 处理

**风险**: 使用 `resume_unwind` 传播 panic，可能丢失部分 panic 信息。

**代码位置**: `lib.rs:60-62`

```rust
match handle.join() {
    Ok(result) => result,
    Err(payload) => ::std::panic::resume_unwind(payload),
}
```

### 边界情况

#### 1. 属性组合边界

| 输入属性 | 处理结果 | 说明 |
|----------|----------|------|
| `#[test]` | 保留 | 标准测试属性 |
| `#[tokio::test]` | 移除 | 避免 runtime 冲突 |
| `#[test_case(x)]` | 保留 | 参数化测试支持 |
| 无测试属性 | 添加 `#[test]` | 确保测试可执行 |

#### 2. 函数类型边界

- **支持**: `async fn` 和普通 `fn`
- **不支持**: `const fn`、`unsafe fn`（未明确处理，但可能工作）

### 改进建议

#### 1. 可配置栈空间（可选属性参数）

```rust
// 建议的增强 API
#[large_stack_test(stack_size = 32 * 1024 * 1024)]
async fn test_with_huge_stack() { }
```

**实现复杂度**: 中等，需要解析属性参数。

#### 2. 可配置 Worker 线程数

```rust
// 建议的增强 API
#[large_stack_test(worker_threads = 4)]
async fn test_io_heavy() { }
```

#### 3. 改进错误信息

当前错误信息:
```rust
panic!("failed to build tokio runtime for large-stack test: {error}")
```

建议添加更多上下文:
```rust
panic!(
    "[large_stack_test] failed to build tokio runtime for test '{}': {}. \
     Consider reducing worker_threads or increasing system limits.",
    stringify!(#name), error
)
```

#### 4. 支持更多测试框架

当前支持:
- `#[test]`
- `#[tokio::test]`
- `#[test_case(...)]`

可考虑支持:
- `#[serial_test::serial]`
- 其他自定义测试属性

#### 5. 文档和示例

建议添加:
- 更多使用示例文档
- 性能影响说明（线程创建开销）
- 与 `#[serial]` 等属性的组合使用指南

### 测试覆盖

**当前单元测试**: `lib.rs:105-155`

| 测试用例 | 覆盖场景 |
|----------|----------|
| `adds_test_attribute_when_missing` | 无属性时自动添加 `#[test]` |
| `removes_tokio_test_and_keeps_test_case` | 属性过滤逻辑 |

**建议补充**:
- 同步函数测试
- Panic 传播测试
- 嵌套属性测试

---

## 总结

`codex-test-macros` 是一个简洁而实用的过程宏库，解决了 Codex 项目集成测试中的栈空间限制问题。其核心设计原则包括：

1. **透明性**: 对测试代码无侵入，仅通过属性注解即可启用
2. **兼容性**: 与主流测试框架和属性兼容
3. **一致性**: 栈空间配置与生产环境保持一致（16MB）

该宏在 `apply_patch_cli.rs` 等测试文件中被大量使用（30+ 处），是保障 Codex 核心库测试稳定性的重要基础设施。
