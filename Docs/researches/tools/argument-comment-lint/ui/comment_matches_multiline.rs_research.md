# comment_matches_multiline.rs 研究文档

## 场景与职责

本文件是 `argument_comment_lint` 工具的 UI 测试用例，用于验证 lint 规则在**多行函数调用**场景下的正确性。

核心场景：当函数调用跨越多行时，参数注释仍然能够被正确解析和匹配。这是测试注释解析器在处理复杂格式（换行、缩进）时的鲁棒性。

## 功能点目的

验证以下场景不会产生 lint 警告：
1. 多行函数调用中的参数注释能被正确识别
2. 换行和缩进不影响注释解析
3. 同时启用两个 lint（`argument_comment_mismatch` 和 `uncommented_anonymous_literal_argument`）时行为正确

### 测试场景覆盖
- 多行函数调用格式
- 混合参数类型（字符串字面量、向量、带注释的 Option）
- 跨行注释位置

## 具体技术实现

### 测试代码分析

```rust
#![warn(argument_comment_mismatch)]
#![warn(uncommented_anonymous_literal_argument)]

fn run_git_for_stdout(repo_root: &str, args: Vec<&str>, env: Option<&str>) -> String {
    let _ = (repo_root, args, env);
    String::new()
}

fn main() {
    let _ = run_git_for_stdout(
        "/tmp/repo",
        vec!["rev-parse", "HEAD"],
        /*env*/ None,
    );
}
```

测试要点：
1. **多行调用格式**：函数调用使用换行和缩进，提高可读性
2. **参数分析**：
   - `"/tmp/repo"`：字符串字面量（被 `uncommented_anonymous_literal_argument` 豁免）
   - `vec!["rev-parse", "HEAD"]`：宏调用结果（非字面量）
   - `/*env*/ None`：带正确注释的 `None`

3. **关键验证点**：`/*env*/` 注释与参数名 `env` 匹配，不触发 `argument_comment_mismatch`

### 多行注释解析策略

在 `src/lib.rs` 第 186-199 行：

```rust
let boundary_span = if index == 0 {
    first_gap_anchor
} else {
    args[index - 1].span
};
let gap_span = boundary_span.between(arg.span);
let gap_text = snippet(cx, gap_span, "");
let arg_text = snippet(cx, arg.span, "..");
let lookbehind_start = BytePos(arg.span.lo().0.saturating_sub(64));
let lookbehind_text =
    snippet(cx, arg.span.shrink_to_lo().with_lo(lookbehind_start), "");
let argument_comment = parse_argument_comment(gap_text.as_ref())
    .or_else(|| parse_argument_comment(lookbehind_text.as_ref()))
    .or_else(|| parse_argument_comment_prefix(arg_text.as_ref()));
```

多行场景下的处理：
1. **间隙 span**：从前一个参数结束到当前参数开始
2. **回溯 span**：从当前参数开始向前最多 64 字节
3. **前缀匹配**：参数文本本身的起始注释

对于本测试的 `/*env*/ None`：
- 间隙文本包含 `\n        /*env*/ `
- `parse_argument_comment` 会 trim 并找到 `/*env*/`

### 注释解析器实现

`src/comment_parser.rs:1-7`：

```rust
pub fn parse_argument_comment(text: &str) -> Option<&str> {
    let trimmed = text.trim_end();
    let comment_start = trimmed.rfind("/*")?;
    let comment = &trimmed[comment_start..];
    let name = comment.strip_prefix("/*")?.strip_suffix("*/")?;
    is_identifier(name).then_some(name)
}
```

关键特性：
- `trim_end()`：去除尾部空白，处理换行
- `rfind("/*")`：从后向前查找，确保取到最后一个注释
- `is_identifier`：验证注释内容是合法标识符

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `tools/argument-comment-lint/ui/comment_matches_multiline.rs` | 本测试文件 |
| `tools/argument-comment-lint/src/lib.rs:186-199` | 多行注释解析策略 |
| `tools/argument-comment-lint/src/comment_parser.rs:1-7` | `parse_argument_comment` 函数 |
| `tools/argument-comment-lint/src/lib.rs:131-146` | `check_expr` 入口，处理 Call 和 MethodCall |

## 依赖与外部交互

### Span 操作
- `Span::between`：计算两个位置之间的 span
- `BytePos`：字节位置，用于回溯计算
- `Span::shrink_to_lo().with_lo()`：创建从某位置开始的 span

### 测试场景对比
与 `comment_matches.rs` 的区别：
| 特性 | `comment_matches.rs` | `comment_matches_multiline.rs` |
|------|---------------------|-------------------------------|
| 调用格式 | 单行 | 多行 |
| 启用 lint | 仅 `argument_comment_mismatch` | 两个 lint |
| 测试重点 | 基本匹配 | 多行解析鲁棒性 |

## 风险、边界与改进建议

### 当前边界
1. **64 字节回溯限制**：`lookbehind_start` 计算使用硬编码的 64 字节限制
2. **注释位置**：必须在参数前或间隙中，不支持行尾注释（如 `None /*env*/`）
3. **多注释冲突**：同一间隙中有多个 `/*...*/` 时，取最后一个

### 潜在风险
1. **超长缩进**：极端缩进可能超出 64 字节回溯范围
2. **注释嵌套**：`/*outer/*inner*/outer*/` 形式的嵌套注释处理可能不符合预期
3. **宏展开**：宏生成的多行代码可能 span 信息不准确

### 改进建议
1. **可配置回溯长度**：将 64 字节改为可配置参数
2. **行尾注释支持**：扩展解析器支持 `arg /*param*/` 格式
3. **嵌套注释处理**：明确是否支持嵌套注释，并添加测试
4. **宏展开测试**：添加对宏生成多行调用的测试用例
5. **性能优化**：对于无注释的代码路径，减少不必要的字符串操作
