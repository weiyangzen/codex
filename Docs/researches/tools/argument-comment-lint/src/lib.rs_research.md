# lib.rs 研究文档

## 场景与职责

`lib.rs` 是 `argument-comment-lint` crate 的主入口，实现了一个基于 Dylint 框架的 Rust 自定义 lint 库。该 lint 工具用于强制执行项目特定的代码风格规范：要求对匿名字面量参数（如 `None`、`true`、`false`、数字）添加 `/*param*/` 形式的注释，并验证注释与参数名匹配。

### 项目定位
- **文件路径**: `tools/argument-comment-lint/src/lib.rs`
- **Crate 类型**: `cdylib`（动态库，供 Dylint 加载）
- **目标项目**: OpenAI Codex Rust 代码库 (`codex-rs`)

### 核心职责
1. 注册两个 lint 规则到 Rust 编译器
2. 分析函数/方法调用表达式
3. 验证参数注释与形参名的一致性
4. 对缺失注释的匿名字面量参数发出警告

## 功能点目的

### Lint 规则 1: `ARGUMENT_COMMENT_MISMATCH`

| 属性 | 值 |
|-----|-----|
| 名称 | `argument_comment_mismatch` |
| 级别 | `Warn`（默认警告） |
| 目的 | 验证 `/*param*/` 注释与解析后的参数名匹配 |

**触发场景**:
```rust
fn create_openai_url(base_url: Option<String>) -> String { ... }

create_openai_url(/*api_base*/ None);  // 警告：注释 "api_base" 与参数 "base_url" 不匹配
```

**设计理念**: 错误的注释比无注释更糟，会主动误导读者。

### Lint 规则 2: `UNCOMMENTED_ANONYMOUS_LITERAL_ARGUMENT`

| 属性 | 值 |
|-----|-----|
| 名称 | `uncommented_anonymous_literal_argument` |
| 级别 | `Allow`（默认允许，CI 中提升为 Deny） |
| 目的 | 要求匿名字面量参数必须带 `/*param*/` 注释 |

**触发场景**:
```rust
create_openai_url(None, 3);  // 警告：匿名字面量参数缺少注释
// 应改为：
create_openai_url(/*base_url*/ None, /*retry_count*/ 3);
```

**豁免类型**: 字符串和字符字面量（通常已自描述）

## 具体技术实现

### 架构概览

```
┌─────────────────────────────────────────────────────────────┐
│                    Dylint Framework                         │
├─────────────────────────────────────────────────────────────┤
│  register_lints()                                           │
│    ├── register ARGUMENT_COMMENT_MISMATCH                   │
│    └── register UNCOMMENTED_ANONYMOUS_LITERAL_ARGUMENT      │
├─────────────────────────────────────────────────────────────┤
│  ArgumentCommentLint (LateLintPass)                         │
│    └── check_expr()                                         │
│          ├── ExprKind::Call      → check_call()             │
│          └── ExprKind::MethodCall → check_call()            │
├─────────────────────────────────────────────────────────────┤
│  check_call()                                               │
│    ├── 解析函数定义 (fn_def_id)                              │
│    ├── 过滤外部 crate 函数                                  │
│    ├── 遍历参数                                             │
│    │    ├── 提取参数名                                      │
│    │    ├── 解析注释 (comment_parser)                       │
│    │    ├── 匹配检查 → ARGUMENT_COMMENT_MISMATCH            │
│    │    └── 匿名检查 → UNCOMMENTED_ANONYMOUS_LITERAL        │
│    └── 报告诊断                                             │
└─────────────────────────────────────────────────────────────┘
```

### 关键数据结构

#### `ArgumentCommentLint`

```rust
#[derive(Default)]
pub struct ArgumentCommentLint;
```

- 零大小类型（ZST），仅作为 lint pass 的标记
- 实现 `LateLintPass` trait，在类型检查之后运行

#### 参数名存储

```rust
let parameter_names: Vec<_> = cx.tcx.fn_arg_idents(def_id).iter().copied().collect();
```

- 使用 `rustc_middle::ty::TyCtxt::fn_arg_idents` 获取形参标识符
- 返回 `Vec<Option<Ident>>`，处理 `self` 等无名参数

### 核心算法流程

#### 1. Lint 注册

```rust
#[unsafe(no_mangle)]
pub fn register_lints(_sess: &rustc_session::Session, lint_store: &mut rustc_lint::LintStore) {
    lint_store.register_lints(&[ARGUMENT_COMMENT_MISMATCH, UNCOMMENTED_ANONYMOUS_LITERAL_ARGUMENT]);
    lint_store.register_late_pass(|_| Box::new(ArgumentCommentLint));
}
```

- `dylint_library!()` 宏标记 Dylint 入口
- `#[unsafe(no_mangle)]` 确保符号导出供 Dylint 加载

#### 2. 表达式检查入口

```rust
impl<'tcx> LateLintPass<'tcx> for ArgumentCommentLint {
    fn check_expr(&mut self, cx: &LateContext<'tcx>, expr: &'tcx Expr<'tcx>) {
        if expr.span.from_expansion() {
            return;  // 跳过宏展开代码
        }

        match expr.kind {
            ExprKind::Call(callee, args) => {
                self.check_call(cx, expr, callee.span, args, 0);  // offset=0 普通函数
            }
            ExprKind::MethodCall(_, receiver, args, _) => {
                self.check_call(cx, expr, receiver.span, args, 1);  // offset=1 方法（跳过 self）
            }
            _ => {}
        }
    }
}
```

#### 3. 调用检查核心逻辑

```rust
fn check_call<'tcx>(
    &self,
    cx: &LateContext<'tcx>,
    call: &'tcx Expr<'tcx>,
    first_gap_anchor: Span,      // 第一个参数间隙的锚点
    args: &'tcx [Expr<'tcx>],    // 实参列表
    parameter_offset: usize,     // 参数偏移（方法调用为 1）
)
```

**过滤逻辑**:
```rust
let Some(def_id) = fn_def_id(cx, call) else { return; };
// 仅检查本地函数或 workspace crate
if !def_id.is_local() && !is_workspace_crate_name(cx.tcx.crate_name(def_id.krate).as_str()) {
    return;
}
// 仅检查函数/关联函数
if !matches!(cx.tcx.def_kind(def_id), DefKind::Fn | DefKind::AssocFn) {
    return;
}
```

**Workspace Crate 白名单**:
```rust
fn is_workspace_crate_name(name: &str) -> bool {
    name.starts_with("codex_")
        || matches!(name, "app_test_support" | "core_test_support" | "mcp_test_support")
}
```

#### 4. 注释提取策略

采用三级回退策略：

```rust
// 1. 间隙文本（前一个参数/锚点到当前参数之间）
let boundary_span = if index == 0 {
    first_gap_anchor
} else {
    args[index - 1].span
};
let gap_span = boundary_span.between(arg.span);
let gap_text = snippet(cx, gap_span, "");

// 2. 回溯文本（当前参数前 64 字节）
let lookbehind_start = BytePos(arg.span.lo().0.saturating_sub(64));
let lookbehind_text = snippet(cx, arg.span.shrink_to_lo().with_lo(lookbehind_start), "");

// 3. 参数表达式前缀
let arg_text = snippet(cx, arg.span, "..");

// 解析尝试
let argument_comment = parse_argument_comment(gap_text.as_ref())
    .or_else(|| parse_argument_comment(lookbehind_text.as_ref()))
    .or_else(|| parse_argument_comment_prefix(arg_text.as_ref()));
```

#### 5. 诊断报告

**注释不匹配**:
```rust
span_lint_and_help(
    cx,
    ARGUMENT_COMMENT_MISMATCH,
    arg.span,
    format!("argument comment `/*{actual_name}*/` does not match parameter `{expected_name}`"),
    None,
    format!("use `/*{expected_name}*/`"),
);
```

**缺失注释**（带自动修复）:
```rust
span_lint_and_sugg(
    cx,
    UNCOMMENTED_ANONYMOUS_LITERAL_ARGUMENT,
    arg.span,
    format!("anonymous literal-like argument for parameter `{expected_name}`"),
    "prepend the parameter name comment",
    format!("/*{expected_name}*/ {arg_text}"),
    Applicability::MachineApplicable,
);
```

### 匿名字面量检测

```rust
fn is_anonymous_literal_like(cx: &LateContext<'_>, expr: &Expr<'_>) -> bool {
    let expr = peel_blocks(expr);  // 剥除块包装
    match expr.kind {
        // 字面量（排除字符串、字节串、C字符串、字符）
        ExprKind::Lit(lit) => !matches!(
            lit.node,
            LitKind::Str(..) | LitKind::ByteStr(..) | LitKind::CStr(..) | LitKind::Char(..)
        ),
        // 负数字面量
        ExprKind::Unary(UnOp::Neg, inner) => matches!(peel_blocks(inner).kind, ExprKind::Lit(_)),
        // Option::None
        ExprKind::Path(qpath) => {
            is_res_lang_ctor(cx, cx.qpath_res(&qpath, expr.hir_id), LangItem::OptionNone)
        }
        _ => false,
    }
}
```

## 关键代码路径与文件引用

### 源码结构

| 行号范围 | 内容 | 说明 |
|---------|------|------|
| 1-33 | 导入与模块声明 | `rustc_*` crate 外部依赖 |
| 36-43 | `register_lints` | Dylint 入口函数 |
| 45-122 | Lint 声明 | `declare_lint!` 宏定义 |
| 124-129 | Lint Pass 实现 | 结构体定义与宏实现 |
| 131-147 | `LateLintPass::check_expr` | 表达式检查入口 |
| 149-231 | `ArgumentCommentLint::check_call` | 核心检查逻辑 |
| 234-247 | `is_anonymous_literal_like` | 匿名字面量检测 |
| 249-251 | `is_meaningful_parameter_name` | 有意义参数名判断 |
| 253-259 | `is_workspace_crate_name` | Workspace crate 过滤 |
| 261-273 | 测试 | UI 测试与单元测试 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `rustc_ast` | 字面量类型 (`LitKind`) |
| `rustc_errors` | 诊断级别 (`Applicability`) |
| `rustc_hir` | HIR 表达式、语言项 (`LangItem`) |
| `rustc_lint` | Lint 框架 (`LateContext`, `LateLintPass`) |
| `rustc_middle` | 类型上下文 (`TyCtxt`), 定义种类 (`DefKind`) |
| `rustc_session` | Lint 声明宏、Session |
| `rustc_span` | 源码位置 (`Span`, `BytePos`) |
| `clippy_utils` | 辅助函数 (`fn_def_id`, `peel_blocks`, `snippet` 等) |
| `dylint_linting` | Dylint 库宏 |

### 调用链

```
rustc 编译器
    └── Dylint 加载器
            └── register_lints()
                    └── LateLintPass::check_expr()
                            └── check_call()
                                    ├── comment_parser::parse_argument_comment()
                                    ├── span_lint_and_help()
                                    └── span_lint_and_sugg()
```

## 依赖与外部交互

### 构建依赖

**Cargo.toml**:
```toml
[dependencies]
clippy_utils = { git = "https://github.com/rust-lang/rust-clippy", rev = "20ce69b9a63bcd2756cd906fe0964d1e901e042a" }
dylint_linting = "5.0.0"

[dev-dependencies]
dylint_testing = "5.0.0"
```

**特殊配置**:
- `.cargo/config.toml`: 使用 `dylint-link` 作为链接器
- `rust-toolchain`: 锁定到 `nightly-2025-09-18`，需 `rustc-dev` 组件

### 与 AGENTS.md 的关联

项目级 `AGENTS.md` 明确规定了 `/*param*/` 注释的使用规范：

> Use an exact `/*param_name*/` comment before opaque literal arguments such as `None`, booleans, and numeric literals when passing them by position.

本 lint 工具是上述规范的自动化强制执行机制。

### 与 justfile 的集成

```justfile
[no-cd]
argument-comment-lint *args:
    ./tools/argument-comment-lint/run.sh "$@"
```

### run.sh 包装器

`run.sh` 脚本提供以下功能：
1. 默认检查 `codex-rs` workspace
2. 自动设置 `-D uncommented-anonymous-literal-argument`（提升为错误）
3. 自动设置 `-A unknown_lints`（抑制未知 lint 警告）
4. 默认 `CARGO_INCREMENTAL=0`（避免增量编译 ICE）

## 风险、边界与改进建议

### 已知限制

1. **宏展开代码跳过**:
   ```rust
   macro_rules! foo { ($x:expr) => { bar($x) }; }
   foo!(None);  // 不会被检查
   ```
   原因：`expr.span.from_expansion()` 返回 true

2. **外部 Crate 函数过滤**:
   - 标准库函数（如 `Option::map`）不会被检查
   - 仅白名单中的 workspace crate 被包含

3. **参数名解析限制**:
   - 需要函数定义可解析（`fn_def_id`）
   - 泛型函数、函数指针、闭包调用无法检查

4. **注释位置限制**:
   - 回溯窗口仅 64 字节，超长多行注释可能检测失败

### 边界情况

| 场景 | 行为 | 说明 |
|-----|------|------|
| `foo(_x: i32)` | 跳过 | 下划线开头视为无意义参数名 |
| `foo(42)` | 警告 | 数字字面量需注释 |
| `foo("text")` | 通过 | 字符串字面量豁免 |
| `foo('c')` | 通过 | 字符字面量豁免 |
| `foo(-42)` | 警告 | 负数字面量需注释 |
| `foo!{ None }` | 跳过 | 宏调用不检查 |

### 潜在风险

1. **Nightly Rust 依赖**:
   - 依赖 `rustc_private` 特性
   - 每次 Rust 升级可能需要同步更新 clippy_utils 版本

2. **性能影响**:
   - 每个函数调用需解析参数名
   - 大型代码库编译时间可能略有增加

3. **误报/漏报**:
   - 复杂宏生成的代码可能产生意外行为
   - 某些合法的 API 设计可能触发警告（如 builder 模式）

### 改进建议

1. **配置化支持**:
   ```rust
   // 允许通过配置文件排除特定函数/模块
   [lint.argument-comment]
   exclude = ["Builder::build", "test::*"]
   ```

2. **更智能的豁免检测**:
   - 识别 builder 模式（链式调用通常无需注释）
   - 识别测试代码（`#[test]` 函数内部放宽要求）

3. **增强注释提取**:
   - 支持多行注释 `/*param*/\n    value`
   - 增加回溯窗口或实现更智能的跨行检测

4. **IDE 集成**:
   - 提供 LSP 插件支持实时检查
   - 提供自动修复代码动作

5. **文档改进**:
   - 添加更多关于设计决策的注释
   - 提供常见误用场景的示例和解决方案

### 测试覆盖

**UI 测试** (`ui/` 目录):
| 文件 | 测试内容 |
|-----|---------|
| `comment_matches.rs` | 正确注释通过检查 |
| `comment_mismatch.rs` | 不匹配注释触发警告 |
| `uncommented_literal.rs` | 匿名字面量触发警告 |
| `allow_string_literals.rs` | 字符串字面量豁免 |
| `allow_char_literals.rs` | 字符字面量豁免 |
| `comment_matches_multiline.rs` | 多行调用场景 |
| `ignore_external_methods.rs` | 外部函数被忽略 |

**单元测试**:
- `workspace_crate_filter_accepts_first_party_names_only`: 验证 crate 白名单逻辑

### 维护建议

1. **Rust 升级流程**:
   - 更新 `rust-toolchain` 到新的 nightly
   - 更新 `clippy_utils` 到兼容版本
   - 运行 `cargo test` 验证
   - 更新 `README.md` 中的安装说明

2. **规则演进**:
   - 新增 lint 规则时需同步更新 `register_lints`
   - 修改检查逻辑时需更新 UI 测试期望输出

3. **监控指标**:
   - 跟踪 lint 触发频率（评估规则有效性）
   - 收集开发者反馈（识别误报/漏报）
