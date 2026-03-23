# comment_matches.rs 研究文档

## 场景与职责

本文件是 `argument_comment_lint` 工具的 UI 测试用例，用于验证 `argument_comment_mismatch` lint 规则在**参数注释正确匹配**时的行为。

核心场景：当函数调用中的 `/*param*/` 注释与函数定义的参数名称完全一致时，lint 不应产生任何警告。这是该 lint 的"正常路径"（happy path）测试。

## 功能点目的

验证以下场景不会产生 lint 警告：
1. 参数注释与参数名称完全匹配时，不触发 `argument_comment_mismatch`
2. 混合使用变量和带注释的字面量时，lint 能正确处理
3. 验证 lint 的基本功能正常工作

### 测试场景覆盖
- 变量参数（无注释）：`base_url` 变量
- 字面量参数（无注释）：`3`（数字字面量，但此处未触发警告，因为未启用 `uncommented_anonymous_literal_argument`）
- 带正确注释的字面量：`/*base_url*/ None`

## 具体技术实现

### 测试代码分析

```rust
#![warn(argument_comment_mismatch)]

fn create_openai_url(base_url: Option<String>, retry_count: usize) -> String {
    let _ = (base_url, retry_count);
    String::new()
}

fn main() {
    let base_url = Some(String::from("https://api.openai.com"));
    create_openai_url(base_url, 3);
    create_openai_url(/*base_url*/ None, 3);
}
```

测试要点：
1. **第一处调用**：`create_openai_url(base_url, 3)`
   - 使用变量 `base_url`，无注释
   - 使用数字字面量 `3`，无注释
   - 不触发 `argument_comment_mismatch`（该 lint 只检查已有注释是否匹配）

2. **第二处调用**：`create_openai_url(/*base_url*/ None, 3)`
   - `/*base_url*/` 注释与参数名 `base_url` 完全匹配 ✓
   - 期望：**不产生警告**

### Lint 检查逻辑

在 `src/lib.rs` 第 197-214 行：

```rust
let argument_comment = parse_argument_comment(gap_text.as_ref())
    .or_else(|| parse_argument_comment(lookbehind_text.as_ref()))
    .or_else(|| parse_argument_comment_prefix(arg_text.as_ref()));

if let Some(actual_name) = argument_comment {
    if actual_name != expected_name {
        span_lint_and_help(
            cx,
            ARGUMENT_COMMENT_MISMATCH,
            arg.span,
            format!(
                "argument comment `/*{actual_name}*/` does not match parameter `{expected_name}`"
            ),
            None,
            format!("use `/*{expected_name}*/`"),
        );
    }
    continue;
}
```

关键逻辑：
- 只有当 `actual_name != expected_name` 时才发出警告
- 本测试中的 `/*base_url*/` 与参数名 `base_url` 相等，因此 `continue`，不进入错误分支

### 注释解析策略

`parse_argument_comment` 函数（`src/comment_parser.rs:1-7`）支持三种查找方式：
1. **间隙文本**：前一个参数/函数名与当前参数之间的文本
2. **回溯文本**：当前参数前最多 64 字节的文本
3. **前缀文本**：参数本身的文本前缀

本测试使用的是第一种（间隙文本）策略。

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `tools/argument-comment-lint/ui/comment_matches.rs` | 本测试文件 |
| `tools/argument-comment-lint/src/lib.rs:197-214` | 注释匹配检查逻辑 |
| `tools/argument-comment-lint/src/comment_parser.rs:1-14` | 注释解析函数 |
| `tools/argument-comment-lint/src/lib.rs:85-122` | `ARGUMENT_COMMENT_MISMATCH` lint 定义 |

## 依赖与外部交互

### 编译器 API 使用
- `rustc_span::Span::between`：计算两个 span 之间的间隙
- `clippy_utils::source::snippet`：提取源代码片段
- `rustc_middle::ty::TyCtxt::fn_arg_idents`：获取函数参数名称

### 测试框架
- `dylint_testing::ui_test`：自动对比 `.stderr` 文件，本测试期望无输出

## 风险、边界与改进建议

### 当前边界
1. **仅检查已注释的参数**：`argument_comment_mismatch` 不会强制要求添加注释，只检查已有注释是否正确
2. **参数顺序依赖**：依赖参数在调用中的位置与定义中的位置对应
3. **方法调用偏移**：对于方法调用（`self` 占第 0 位），会自动调整参数索引（见 `parameter_offset`）

### 潜在风险
1. **重命名传播**：函数参数重命名后，所有调用点的注释都需要更新，但 lint 会捕获这些不匹配
2. **大小写敏感**：注释匹配是大小写敏感的，`/*BaseUrl*/` 不会匹配 `base_url`

### 改进建议
1. **自动修复**：提供 `--fix` 选项自动将不匹配的注释替换为正确的参数名
2. **模糊匹配**：对常见的命名变体（camelCase vs snake_case）提供警告而非错误
3. **IDE 集成**：在参数重命名重构时自动更新所有注释
4. **批量检查**：提供脚本批量检查整个代码库的注释匹配情况
