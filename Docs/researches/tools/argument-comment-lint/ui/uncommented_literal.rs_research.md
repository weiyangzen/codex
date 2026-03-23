# uncommented_literal.rs 研究文档

## 场景与职责

本文件是 `argument_comment_lint` 工具的 UI 测试用例，用于验证 `uncommented_anonymous_literal_argument` lint 规则的核心功能——**检测未注释的匿名字面量参数**。

这是该 lint 最基础也是最重要的测试场景，涵盖了函数调用和方法调用中各种需要注释的字面量类型。

## 功能点目的

验证以下场景会产生正确的 lint 警告：
1. `None` 作为函数参数时缺少 `/*param*/` 注释
2. 数字字面量作为函数参数时缺少注释
3. 布尔字面量作为方法参数时缺少注释

### 测试场景覆盖
- 普通函数调用：`create_openai_url(None, 3)`
- 方法调用：`client.set_flag(true)`
- 多种字面量类型：`None`、整数、布尔值

## 具体技术实现

### 测试代码分析

```rust
#![warn(uncommented_anonymous_literal_argument)]

struct Client;

impl Client {
    fn set_flag(&self, enabled: bool) {}
}

fn create_openai_url(base_url: Option<String>, retry_count: usize) -> String {
    let _ = (base_url, retry_count);
    String::new()
}

fn main() {
    let client = Client;
    let _ = create_openai_url(None, 3);
    client.set_flag(true);
}
```

测试要点：
1. **`create_openai_url(None, 3)`**：
   - `None` 对应参数 `base_url`
   - `3` 对应参数 `retry_count`
   - 两者都应该有注释

2. **`client.set_flag(true)`**：
   - `true` 对应参数 `enabled`
   - 方法调用场景

### 预期警告输出（uncommented_literal.stderr）

```
warning: anonymous literal-like argument for parameter `base_url`
  --> $DIR/uncommented_literal.rs:16:31
   |
LL |     let _ = create_openai_url(None, 3);
   |                               ^^^^ help: prepend the parameter name comment: `/*base_url*/ None`

warning: anonymous literal-like argument for parameter `retry_count`
  --> $DIR/uncommented_literal.rs:16:37
   |
LL |     let _ = create_openai_url(None, 3);
   |                                     ^ help: prepend the parameter name comment: `/*retry_count*/ 3`

warning: anonymous literal-like argument for parameter `enabled`
  --> $DIR/uncommented_literal.rs:17:21
   |
LL |     client.set_flag(true);
   |                     ^^^^ help: prepend the parameter name comment: `/*enabled*/ true`
```

### Lint 检测逻辑

在 `src/lib.rs` 第 217-229 行：

```rust
if !is_anonymous_literal_like(cx, arg) {
    continue;
}

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

关键逻辑：
1. 检查是否为"匿名字面量类"参数
2. 使用 `span_lint_and_sugg` 提供自动修复建议
3. `Applicability::MachineApplicable` 表示这是机器可应用的修复

### 匿名字面量判定

在 `src/lib.rs` 第 234-247 行的 `is_anonymous_literal_like` 函数：

```rust
fn is_anonymous_literal_like(cx: &LateContext<'_>, expr: &Expr<'_>) -> bool {
    let expr = peel_blocks(expr);
    match expr.kind {
        ExprKind::Lit(lit) => !matches!(
            lit.node,
            LitKind::Str(..) | LitKind::ByteStr(..) | LitKind::CStr(..) | LitKind::Char(..)
        ),
        ExprKind::Unary(UnOp::Neg, inner) => matches!(peel_blocks(inner).kind, ExprKind::Lit(_)),
        ExprKind::Path(qpath) => {
            is_res_lang_ctor(cx, cx.qpath_res(&qpath, expr.hir_id), LangItem::OptionNone)
        }
        _ => false,
    }
}
```

判定规则：
| 表达式类型 | 是否触发 | 示例 |
|-----------|---------|------|
| 数字字面量 | ✅ | `3`, `-5` |
| 布尔字面量 | ✅ | `true`, `false` |
| `None` | ✅ | `None` |
| 字符串字面量 | ❌ | `"text"` |
| 字符字面量 | ❌ | `'a'` |
| 负数 | ✅ | `-42`（通过 `UnOp::Neg` 处理）|

### 方法调用处理

在 `src/lib.rs` 第 141-143 行：

```rust
ExprKind::MethodCall(_, receiver, args, _) => {
    self.check_call(cx, expr, receiver.span, args, 1);
}
```

- `parameter_offset = 1` 表示方法调用的第 0 个参数是 `self`，实际参数从第 1 位开始

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `tools/argument-comment-lint/ui/uncommented_literal.rs` | 本测试文件 |
| `tools/argument-comment-lint/ui/uncommented_literal.stderr` | 预期错误输出 |
| `tools/argument-comment-lint/src/lib.rs:217-229` | 匿名字面量警告生成 |
| `tools/argument-comment-lint/src/lib.rs:234-247` | `is_anonymous_literal_like` 判定函数 |
| `tools/argument-comment-lint/src/lib.rs:85-122` | `UNCOMMENTED_ANONYMOUS_LITERAL_ARGUMENT` lint 定义 |

## 依赖与外部交互

### Rustc 内部类型
- `rustc_hir::ExprKind::Lit`：字面量表达式
- `rustc_hir::ExprKind::Path`：路径表达式（用于检测 `None`）
- `rustc_hir::LangItem::OptionNone`：标准库 `None` 变体
- `rustc_ast::LitKind`：字面量类型枚举

### Clippy Utils
- `peel_blocks`：剥离块表达式，获取内部表达式
- `is_res_lang_ctor`：检查是否为语言级构造函数
- `span_lint_and_sugg`：生成带修复建议的 lint

## 风险、边界与改进建议

### 当前边界
1. **默认 Allow 级别**：该 lint 默认是 `Allow` 级别（见第 120 行），需要显式启用
2. **仅检查已解析的函数**：无法解析的函数调用（如函数指针）不会被检查
3. **宏展开**：宏生成的代码可能 span 信息不准确

### 潜在风险
1. **过度警告**：在大量调用标准库的场景下，可能产生过多警告
2. **修复冲突**：多个参数的自动修复可能在同一行产生冲突
3. **语义丢失**：`/*param*/ None` 比单纯的 `None` 更冗长

### 改进建议
1. **智能豁免**：
   - 对明显自描述的调用（如 `Option::map(None, ...)`）提供豁免
   - 对测试代码提供特殊处理

2. **配置选项**：
   - 允许配置哪些字面量类型需要注释
   - 允许配置参数名长度阈值（短参数名可能不需要注释）

3. **批量修复**：
   - 提供 `--fix` 模式自动应用所有建议
   - 支持只修复特定文件或模块

4. **IDE 集成**：
   - 提供代码动作（Code Action）快速添加注释
   - 在参数提示中显示参数名

5. **文档完善**：
   - 在 AGENTS.md 中添加更多使用示例
   - 解释为什么某些字面量被豁免

### 测试覆盖扩展
- 负数字面量（`-42`）
- 嵌套调用（`foo(Some(bar(None)))`）
- 闭包参数
- 泛型函数调用
