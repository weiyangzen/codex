# argument-comment-lint/src 深度研究文档

## 1. 场景与职责

### 1.1 项目定位

`argument-comment-lint` 是一个基于 [Dylint](https://github.com/trailofbits/dylint) 的 Rust 自定义 lint 工具，专门用于强制执行 `/*param_name*/` 形式的参数注释规范。它是 OpenAI Codex 项目代码质量保证体系的重要组成部分。

### 1.2 设计哲学

该工具体现了以下核心设计原则：

1. **优先自文档化 API**：鼓励使用枚举、命名辅助方法、newtype 等惯用 Rust API 设计，而非依赖注释
2. **兼容性保留**：当无法修改 API 时，使用参数注释作为次优解
3. **精确匹配**：要求注释中的参数名必须与函数签名完全一致

### 1.3 适用场景

| 场景 | 处理方式 |
|------|----------|
| `foo(false)` / `bar(None)` | 触发 lint，建议使用 `/*param*/` 注释或重构 API |
| `/*api_base*/ None` (名称不匹配) | 触发 `argument_comment_mismatch` 警告 |
| `/*base_url*/ None` (正确) | 通过检查 |
| `"openai"` / `'\n'` | 字符串/字符字面量豁免，无需注释 |
| 外部 crate 方法调用 | 忽略，仅检查 workspace 内部代码 |

### 1.4 与项目规范的关系

在 `AGENTS.md` 中明确规定（第 15-18 行）：

> When you cannot make that API change and still need a small positional-literal callsite in Rust, follow the `argument_comment_lint` convention:
> - Use an exact `/*param_name*/` comment before opaque literal arguments such as `None`, booleans, and numeric literals when passing them by position.
> - Do not add these comments for string or char literals unless the comment adds real clarity; those literals are intentionally exempt from the lint.
> - If you add one of these comments, the parameter name must exactly match the callee signature.

---

## 2. 功能点目的

### 2.1 提供的 Lints

| Lint 名称 | 默认级别 | 目的 |
|-----------|----------|------|
| `argument_comment_mismatch` | Warn | 验证 `/*param*/` 注释是否与函数参数名匹配 |
| `uncommented_anonymous_literal_argument` | Allow | 标记缺少注释的匿名字面量参数（如 `None`, `true`, `3`） |

### 2.2 各 Lint 详细行为

#### 2.2.1 `argument_comment_mismatch`

**触发条件**：
- 调用处存在 `/*param*/` 注释
- 注释名称与函数定义的参数名不匹配

**示例**：
```rust
fn create_openai_url(base_url: Option<String>) -> String { ... }

// 触发警告：argument comment `/*api_base*/` does not match parameter `base_url`
create_openai_url(/*api_base*/ None);

// 正确
create_openai_url(/*base_url*/ None);
```

**设计理由**：错误的注释比没有注释更具误导性，必须确保注释准确性。

#### 2.2.2 `uncommented_anonymous_literal_argument`

**触发条件**：
- 字面量类参数（`None`, `true`, `false`, 数字字面量）
- 缺少 `/*param*/` 注释
- 该 lint 被显式启用（`#![warn(...)]`）

**豁免类型**：
- 字符串字面量（`"text"`, `r"raw"`）
- 字节字符串（`b"bytes"`）
- C 字符串（`c"cstr"`）
- 字符字面量（`'a'`）

**示例**：
```rust
#![warn(uncommented_anonymous_literal_argument)]

fn create_openai_url(base_url: Option<String>, retry_count: usize) -> String { ... }

// 触发警告：anonymous literal-like argument for parameter `base_url`
// help: prepend the parameter name comment: `/*base_url*/ None`
create_openai_url(None, 3);

// 正确
create_openai_url(/*base_url*/ None, /*retry_count*/ 3);

// 字符串/字符字面量豁免，无需注释
describe("openai", r"https://api.openai.com/v1");
split_top_level("a|b|c", '|');
```

---

## 3. 具体技术实现

### 3.1 项目结构

```
tools/argument-comment-lint/
├── .cargo/
│   └── config.toml          # 使用 dylint-link 作为链接器
├── src/
│   ├── lib.rs               # 主 lint 实现（273 行）
│   └── comment_parser.rs    # 注释解析器（63 行）
├── ui/                      # UI 测试用例
│   ├── allow_char_literals.rs
│   ├── allow_string_literals.rs
│   ├── comment_matches.rs
│   ├── comment_matches_multiline.rs
│   ├── comment_mismatch.rs
│   ├── comment_mismatch.stderr
│   ├── ignore_external_methods.rs
│   ├── uncommented_literal.rs
│   └── uncommented_literal.stderr
├── Cargo.toml               # crate 配置（cdylib 类型）
├── Cargo.lock               # 依赖锁定
├── rust-toolchain           # nightly-2025-09-18
├── run.sh                   # 运行脚本
└── README.md                # 文档
```

### 3.2 关键技术栈

| 组件 | 用途 |
|------|------|
| `rustc_private` | 访问 Rust 编译器内部 API |
| `dylint_linting` | Dylint 框架集成 |
| `clippy_utils` | Clippy 工具函数（诊断、源码片段等）|
| `dylint_testing` | UI 测试支持 |

### 3.3 核心数据结构

#### 3.3.1 Lint 定义

```rust
// src/lib.rs:45-83
rustc_session::declare_lint! {
    pub ARGUMENT_COMMENT_MISMATCH,
    Warn,
    "argument comment does not match the resolved parameter name"
}

rustc_session::declare_lint! {
    pub UNCOMMENTED_ANONYMOUS_LITERAL_ARGUMENT,
    Allow,
    "anonymous literal-like argument is missing a `/*param*/` comment"
}

#[derive(Default)]
pub struct ArgumentCommentLint;

rustc_session::impl_lint_pass!(
    ArgumentCommentLint => [ARGUMENT_COMMENT_MISMATCH, UNCOMMENTED_ANONYMOUS_LITERAL_ARGUMENT]
);
```

#### 3.3.2 注释解析函数

```rust
// src/comment_parser.rs:1-14

/// 从文本末尾解析 `/*param*/` 注释（用于参数间隙）
pub fn parse_argument_comment(text: &str) -> Option<&str> {
    let trimmed = text.trim_end();
    let comment_start = trimmed.rfind("/*")?;
    let comment = &trimmed[comment_start..];
    let name = comment.strip_prefix("/*")?.strip_suffix("*/")?;
    is_identifier(name).then_some(name)
}

/// 从文本开头解析 `/*param*/` 注释（用于参数前缀）
pub fn parse_argument_comment_prefix(text: &str) -> Option<&str> {
    let trimmed = text.trim_start();
    let comment = trimmed.strip_prefix("/*")?;
    let (name, _) = comment.split_once("*/")?;
    is_identifier(name).then_some(name)
}
```

### 3.4 关键流程

#### 3.4.1 Lint 注册流程

```rust
// src/lib.rs:36-43
#[unsafe(no_mangle)]
pub fn register_lints(_sess: &rustc_session::Session, lint_store: &mut rustc_lint::LintStore) {
    lint_store.register_lints(&[
        ARGUMENT_COMMENT_MISMATCH,
        UNCOMMENTED_ANONYMOUS_LITERAL_ARGUMENT,
    ]);
    lint_store.register_late_pass(|_| Box::new(ArgumentCommentLint));
}
```

#### 3.4.2 表达式检查流程

```rust
// src/lib.rs:131-147
impl<'tcx> LateLintPass<'tcx> for ArgumentCommentLint {
    fn check_expr(&mut self, cx: &LateContext<'tcx>, expr: &'tcx Expr<'tcx>) {
        if expr.span.from_expansion() {
            return;  // 忽略宏展开代码
        }

        match expr.kind {
            ExprKind::Call(callee, args) => {
                self.check_call(cx, expr, callee.span, args, 0);
            }
            ExprKind::MethodCall(_, receiver, args, _) => {
                self.check_call(cx, expr, receiver.span, args, 1);  // 方法调用偏移 1（跳过 self）
            }
            _ => {}
        }
    }
}
```

#### 3.4.3 调用检查核心逻辑

```rust
// src/lib.rs:149-231
fn check_call<'tcx>(
    &self,
    cx: &LateContext<'tcx>,
    call: &'tcx Expr<'tcx>,
    first_gap_anchor: Span,
    args: &'tcx [Expr<'tcx>],
    parameter_offset: usize,
) {
    // 1. 解析函数定义 ID
    let Some(def_id) = fn_def_id(cx, call) else { return };
    
    // 2. 过滤外部 crate（仅检查 workspace 内部）
    if !def_id.is_local() && !is_workspace_crate_name(cx.tcx.crate_name(def_id.krate).as_str()) {
        return;
    }
    
    // 3. 确认是函数或关联函数
    if !matches!(cx.tcx.def_kind(def_id), DefKind::Fn | DefKind::AssocFn) {
        return;
    }

    // 4. 获取参数名列表
    let parameter_names: Vec<_> = cx.tcx.fn_arg_idents(def_id).iter().copied().collect();
    
    for (index, arg) in args.iter().enumerate() {
        if arg.span.from_expansion() { continue; }

        // 5. 获取期望的参数名
        let Some(expected_name) = parameter_names.get(index + parameter_offset) else { continue };
        let Some(expected_name) = expected_name else { continue };
        let expected_name = expected_name.name.to_string();
        if !is_meaningful_parameter_name(&expected_name) { continue; }

        // 6. 计算注释搜索范围
        let boundary_span = if index == 0 { first_gap_anchor } else { args[index - 1].span };
        let gap_span = boundary_span.between(arg.span);
        let gap_text = snippet(cx, gap_span, "");
        let arg_text = snippet(cx, arg.span, "..");
        
        // 7. 回溯 64 字节搜索注释
        let lookbehind_start = BytePos(arg.span.lo().0.saturating_sub(64));
        let lookbehind_text = snippet(cx, arg.span.shrink_to_lo().with_lo(lookbehind_start), "");
        
        // 8. 解析注释（三种策略）
        let argument_comment = parse_argument_comment(gap_text.as_ref())
            .or_else(|| parse_argument_comment(lookbehind_text.as_ref()))
            .or_else(|| parse_argument_comment_prefix(arg_text.as_ref()));

        // 9. 检查注释匹配
        if let Some(actual_name) = argument_comment {
            if actual_name != expected_name {
                span_lint_and_help(...);  // 触发 mismatch 警告
            }
            continue;
        }

        // 10. 检查是否为匿名字面量
        if !is_anonymous_literal_like(cx, arg) { continue; }

        span_lint_and_sugg(...);  // 触发 uncommented 警告
    }
}
```

### 3.5 辅助函数详解

#### 3.5.1 匿名字面量检测

```rust
// src/lib.rs:234-247
fn is_anonymous_literal_like(cx: &LateContext<'_>, expr: &Expr<'_>) -> bool {
    let expr = peel_blocks(expr);  // 剥离块表达式
    match expr.kind {
        // 字面量（排除字符串/字符）
        ExprKind::Lit(lit) => !matches!(
            lit.node,
            LitKind::Str(..) | LitKind::ByteStr(..) | LitKind::CStr(..) | LitKind::Char(..)
        ),
        // 负数字面量（如 -1）
        ExprKind::Unary(UnOp::Neg, inner) => matches!(peel_blocks(inner).kind, ExprKind::Lit(_)),
        // None 值（Option::None 语言项）
        ExprKind::Path(qpath) => {
            is_res_lang_ctor(cx, cx.qpath_res(&qpath, expr.hir_id), LangItem::OptionNone)
        }
        _ => false,
    }
}
```

#### 3.5.2 Workspace Crate 过滤

```rust
// src/lib.rs:253-259
fn is_workspace_crate_name(name: &str) -> bool {
    name.starts_with("codex_")
        || matches!(
            name,
            "app_test_support" | "core_test_support" | "mcp_test_support"
        )
}
```

#### 3.5.3 有意义的参数名检测

```rust
// src/lib.rs:249-251
fn is_meaningful_parameter_name(name: &str) -> bool {
    !name.is_empty() && !name.starts_with('_')  // 排除空名和下划线前缀（未使用参数）
}
```

### 3.6 注释解析策略

工具使用三种策略查找参数注释：

| 策略 | 函数 | 搜索范围 | 用途 |
|------|------|----------|------|
| 间隙搜索 | `parse_argument_comment(gap_text)` | 前一个参数/调用点到当前参数之间 | 标准情况：`foo(/*param*/ value)` |
| 回溯搜索 | `parse_argument_comment(lookbehind)` | 当前参数前 64 字节 | 多行调用或复杂表达式 |
| 前缀搜索 | `parse_argument_comment_prefix(arg_text)` | 参数文本开头 | 注释紧贴参数：`/*param*/value` |

### 3.7 运行脚本机制

`run.sh` 脚本提供以下功能：

```bash
# 默认行为
./tools/argument-comment-lint/run.sh -p codex-core

# 等价于：
DYLINT_RUSTFLAGS="-D uncommented-anonymous-literal-argument -A unknown_lints" \
CARGO_INCREMENTAL=0 \
cargo dylint --path tools/argument-comment-lint --all \
  --manifest-path codex-rs/Cargo.toml \
  --workspace --no-deps \
  -p codex-core
```

**关键环境变量**：
- `DYLINT_RUSTFLAGS`: 默认启用 `uncommented-anonymous-literal-argument` 为 error，允许 `unknown_lints`
- `CARGO_INCREMENTAL=0`: 避免 nightly rustc 增量编译 ICE

---

## 4. 关键代码路径与文件引用

### 4.1 核心实现文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `src/lib.rs` | 273 | Lint 主逻辑、诊断生成 |
| `src/comment_parser.rs` | 63 | 注释解析、标识符验证 |

### 4.2 关键代码位置索引

| 功能 | 文件 | 行号 |
|------|------|------|
| Lint 注册 | `src/lib.rs` | 36-43 |
| `ARGUMENT_COMMENT_MISMATCH` 定义 | `src/lib.rs` | 45-83 |
| `UNCOMMENTED_ANONYMOUS_LITERAL_ARGUMENT` 定义 | `src/lib.rs` | 85-122 |
| `LateLintPass::check_expr` | `src/lib.rs` | 131-147 |
| `ArgumentCommentLint::check_call` | `src/lib.rs` | 149-231 |
| `is_anonymous_literal_like` | `src/lib.rs` | 234-247 |
| `is_meaningful_parameter_name` | `src/lib.rs` | 249-251 |
| `is_workspace_crate_name` | `src/lib.rs` | 253-259 |
| `parse_argument_comment` | `src/comment_parser.rs` | 1-7 |
| `parse_argument_comment_prefix` | `src/comment_parser.rs` | 9-14 |
| `is_identifier` | `src/comment_parser.rs` | 16-25 |

### 4.3 测试文件

| 文件 | 测试目的 |
|------|----------|
| `ui/allow_char_literals.rs` | 验证字符字面量豁免 |
| `ui/allow_string_literals.rs` | 验证字符串字面量豁免 |
| `ui/comment_matches.rs` | 验证正确注释通过检查 |
| `ui/comment_matches_multiline.rs` | 验证多行调用场景 |
| `ui/comment_mismatch.rs` | 验证注释不匹配警告 |
| `ui/ignore_external_methods.rs` | 验证外部方法被忽略 |
| `ui/uncommented_literal.rs` | 验证未注释字面量警告 |

---

## 5. 依赖与外部交互

### 5.1 编译时依赖

```toml
# Cargo.toml
[dependencies]
clippy_utils = { git = "https://github.com/rust-lang/rust-clippy", rev = "20ce69b9a63bcd2756cd906fe0964d1e901e042a" }
dylint_linting = "5.0.0"

[dev-dependencies]
dylint_testing = "5.0.0"
```

### 5.2 Rust 编译器内部 crate

```rust
#![feature(rustc_private)]

extern crate rustc_ast;
extern crate rustc_errors;
extern crate rustc_hir;
extern crate rustc_lint;
extern crate rustc_middle;
extern crate rustc_session;
extern crate rustc_span;
```

### 5.3 工具链要求

```toml
# rust-toolchain
[toolchain]
channel = "nightly-2025-09-18"
components = ["llvm-tools-preview", "rustc-dev", "rust-src"]
```

### 5.4 外部集成

| 集成点 | 说明 |
|--------|------|
| `justfile` | `just argument-comment-lint` 命令调用 `run.sh` |
| CI/CD | 可在持续集成中运行以保证代码规范 |
| IDE | 通过 `rust-analyzer` 配置 `rustc_private = true` 支持开发 |

### 5.5 依赖关系图

```
argument_comment_lint (cdylib)
├── dylint_linting (运行时框架)
├── clippy_utils (工具函数)
│   └── rustc_* (编译器内部)
└── dylint_testing (测试框架，dev)
    └── compiletest_rs
```

---

## 6. 风险、边界与改进建议

### 6.1 已知限制

#### 6.1.1 宏展开代码

```rust
// src/lib.rs:133-135
if expr.span.from_expansion() {
    return;
}
```

宏生成的代码不会被检查，这既是限制也是设计选择（避免误报）。

#### 6.1.2 外部 Crate 限制

```rust
// src/lib.rs:161-164
if !def_id.is_local() && !is_workspace_crate_name(cx.tcx.crate_name(def_id.krate).as_str()) {
    return;
}
```

仅检查 workspace 内部代码，外部依赖的参数注释不会被验证。

#### 6.1.3 参数名解析依赖

```rust
// src/lib.rs:169
let parameter_names: Vec<_> = cx.tcx.fn_arg_idents(def_id).iter().copied().collect();
```

需要成功解析函数定义才能获取参数名，某些复杂场景（如 trait 对象、动态分发）可能无法解析。

### 6.2 边界情况

| 场景 | 行为 |
|------|------|
| `/* param */`（空格）| 拒绝，必须是 `/*param*/` |
| `/*1param*/`（数字开头）| 拒绝，必须是合法标识符 |
| `/*param=/` | 拒绝，包含非法字符 `=` |
| `_unused` 参数 | 忽略，下划线前缀被视为无意义 |
| 负数字面量 `-1` | 识别为匿名字面量 |

### 6.3 潜在风险

#### 6.3.1 Nightly Rust 依赖

工具依赖特定 nightly 版本（`nightly-2025-09-18`），Rust 编译器 API 变化可能导致：
- 编译失败
- 需要定期更新工具链和 clippy_utils 版本

#### 6.3.2 性能考虑

```rust
let lookbehind_start = BytePos(arg.span.lo().0.saturating_sub(64));
```

每个参数需要回溯 64 字节搜索注释，大型代码库可能有轻微性能影响。

### 6.4 改进建议

#### 6.4.1 功能增强

1. **支持更多字面量类型**
   - 当前：仅支持 `None`, `true`, `false`, 数字
   - 建议：可配置添加其他类型（如空数组 `[]`, 空元组 `()`）

2. **可配置豁免列表**
   - 添加配置文件支持，允许项目自定义豁免规则

3. **改进多行支持**
   - 当前 64 字节回溯可能不足，可考虑基于行的回溯

#### 6.4.2 维护性改进

1. **自动化工具链更新**
   - 设置 CI 任务监控 nightly 兼容性
   - 自动化测试新版本兼容性

2. **扩展测试覆盖**
   - 添加更多边界情况测试
   - 添加性能基准测试

#### 6.4.3 文档改进

1. **添加架构图**
   - 可视化 lint 检查流程

2. **错误示例库**
   - 收集常见错误模式及修复方案

### 6.5 相关规范遵循检查清单

- [x] 遵循 `AGENTS.md` 中的 `argument_comment_lint` 约定
- [x] 字符串/字符字面量正确豁免
- [x] 参数注释格式严格匹配 `/*param_name*/`
- [x] 仅检查 workspace 内部代码
- [x] 使用 `clippy_utils` 进行诊断输出

---

## 附录：快速参考

### 运行命令

```bash
# 安装依赖
cargo install cargo-dylint dylint-link
rustup toolchain install nightly-2025-09-18 \
  --component llvm-tools-preview \
  --component rustc-dev \
  --component rust-src

# 运行测试
cd tools/argument-comment-lint && cargo test

# 运行 lint（通过 just）
just argument-comment-lint -p codex-core

# 运行 lint（直接）
./tools/argument-comment-lint/run.sh -p codex-core

# 覆盖默认行为
DYLINT_RUSTFLAGS="-A uncommented-anonymous-literal-argument" \
  ./tools/argument-comment-lint/run.sh -p codex-core
```

### 代码规范速查

| 写法 | 状态 | 说明 |
|------|------|------|
| `foo(/*enabled*/ true)` | ✅ 正确 | 注释匹配参数名 |
| `foo(/*flag*/ true)` | ⚠️ 警告 | 注释不匹配 |
| `foo(true)` | ⚠️ 警告 | 缺少注释（若 lint 启用）|
| `foo("text")` | ✅ 正确 | 字符串字面量豁免 |
| `foo(None)` | ⚠️ 警告 | 缺少注释（若 lint 启用）|
| `foo(_unused)` | ✅ 正确 | 下划线前缀参数被忽略 |
