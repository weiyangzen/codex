# comment_mismatch.rs 研究文档

## 场景与职责

本文件是 `argument_comment_lint` 工具的 UI 测试用例，用于验证 `argument_comment_mismatch` lint 规则在**参数注释不匹配**时的错误报告行为。

核心场景：当函数调用中的 `/*param*/` 注释与函数定义的参数名称不一致时，lint 应该产生警告，并提示正确的参数名。这是该 lint 的核心功能测试。

## 功能点目的

验证以下场景会产生正确的 lint 警告：
1. 参数注释与参数名称不匹配时，触发 `argument_comment_mismatch` 警告
2. 警告消息准确指出不匹配的内容
3. 帮助信息提供正确的注释格式建议

### 测试场景
- 调用函数时使用错误的参数注释 `/*api_base*/`
- 函数实际参数名为 `base_url`
- 期望产生警告，建议使用 `/*base_url*/`

## 具体技术实现

### 测试代码分析

```rust
#![warn(argument_comment_mismatch)]

fn create_openai_url(base_url: Option<String>) -> String {
    let _ = base_url;
    String::new()
}

fn main() {
    let _ = create_openai_url(/*api_base*/ None);
}
```

测试要点：
- 函数定义参数名：`base_url`
- 调用时使用的注释：`/*api_base*/`
- 不匹配点：`api_base` ≠ `base_url`
- 期望警告：提示使用 `/*base_url*/`

### 预期错误输出（comment_mismatch.stderr）

```
warning: argument comment `/*api_base*/` does not match parameter `base_url`
  --> $DIR/comment_mismatch.rs:9:44
   |
LL |     let _ = create_openai_url(/*api_base*/ None);
   |                                            ^^^^
   |
   = help: use `/*base_url*/`
```

### Lint 错误生成逻辑

在 `src/lib.rs` 第 201-214 行：

```rust
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
1. 解析到注释 `actual_name = "api_base"`
2. 期望参数名 `expected_name = "base_url"`
3. 两者不等，触发 `span_lint_and_help`
4. 高亮位置：`arg.span`（即 `None` 的位置）
5. 帮助信息：建议使用正确的注释格式

### 使用 `span_lint_and_help` 而非 `span_lint_and_sugg`

注意这里使用的是 `span_lint_and_help` 而不是 `span_lint_and_sugg`，原因是：
- 这是一个"帮助"信息，告诉用户正确的做法
- 不是自动修复建议（suggestion），因为直接替换注释文本可能不完全准确
- 用户需要手动确认并修改

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `tools/argument-comment-lint/ui/comment_mismatch.rs` | 本测试文件 |
| `tools/argument-comment-lint/ui/comment_mismatch.stderr` | 预期错误输出 |
| `tools/argument-comment-lint/src/lib.rs:201-214` | 不匹配警告生成逻辑 |
| `tools/argument-comment-lint/src/lib.rs:45-83` | `ARGUMENT_COMMENT_MISMATCH` lint 定义和文档 |

## 依赖与外部交互

### Clippy Utils
- `span_lint_and_help`：生成带帮助信息的 lint 警告
- 与 `span_lint_and_sugg`（带自动修复建议）的区别

### UI 测试框架
- `dylint_testing::ui_test` 会自动对比 `.rs` 文件编译输出与 `.stderr` 文件
- 两者必须完全匹配，测试才通过

## 风险、边界与改进建议

### 当前边界
1. **仅检查已注释参数**：不会强制要求无注释的参数添加注释
2. **精确匹配**：注释内容必须与参数名完全一致（大小写敏感）
3. **单参数检查**：每个参数独立检查，不检查参数顺序是否错乱

### 潜在风险
1. **误报**：参数重命名后，旧注释会被标记为不匹配（这是预期行为，但可能产生大量警告）
2. **漏报**：如果注释完全省略，不会触发此 lint（需要启用 `uncommented_anonymous_literal_argument`）
3. **语义等价**：`/*url*/` 和 `/*base_url*/` 在语义上可能等价，但仍会触发不匹配警告

### 改进建议
1. **自动修复**：提供 `--fix` 选项自动将 `/*api_base*/` 替换为 `/*base_url*/`
2. **相似度提示**：当注释与参数名相似但不同时（如 `api_base` vs `base_url`），提供额外提示
3. **批量重命名支持**：与 IDE 集成，在参数重命名时同步更新所有注释
4. **配置白名单**：允许配置某些"等价"注释（如 `/*url*/` 可匹配 `base_url`）
5. **警告级别配置**：允许将不匹配设置为 error 级别，强制在 CI 中阻止合并

### 测试覆盖扩展建议
- 多参数场景下的不匹配
- 方法调用（`self` 参数）场景
- 注释部分匹配场景（如 `/*base*/` vs `base_url`）
