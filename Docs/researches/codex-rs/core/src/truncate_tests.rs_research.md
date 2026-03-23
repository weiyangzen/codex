# truncate_tests.rs 研究文档

## 场景与职责

`truncate_tests.rs` 是 `truncate.rs` 的配套测试模块，全面验证文本截断功能的正确性：

1. **字符串分割测试**：验证 `split_string` 的 UTF-8 安全性和预算分配
2. **截断策略测试**：验证 Bytes 和 Tokens 两种模式的截断行为
3. **边界条件测试**：空字符串、零预算、预算重叠等边界
4. **函数输出截断测试**：验证混合内容（文本+图片）的处理
5. **格式化截断测试**：验证行数统计和合并逻辑

该模块使用内联测试方式，是核心工具模块的测试保障。

## 功能点目的

### 1. 字符串分割测试

| 测试 | 验证点 |
|------|--------|
| `split_string_works` | 基本分割功能 |
| `split_string_handles_empty_string` | 空字符串处理 |
| `split_string_only_keeps_prefix_when_tail_budget_is_zero` | 仅前缀模式 |
| `split_string_only_keeps_suffix_when_prefix_budget_is_zero` | 仅后缀模式 |
| `split_string_handles_overlapping_budgets_without_removal` | 预算重叠处理 |
| `split_string_respects_utf8_boundaries` | UTF-8 边界安全 |

### 2. 截断策略测试

| 测试 | 验证点 |
|------|--------|
| `truncate_bytes_less_than_placeholder_returns_placeholder` | 小预算产生标记 |
| `truncate_tokens_less_than_placeholder_returns_placeholder` | token 模式小预算 |
| `truncate_tokens_under_limit_returns_original` | 未超限不截断 |
| `truncate_bytes_under_limit_returns_original` | 字节模式未超限 |
| `truncate_tokens_over_limit_returns_truncated` | token 模式截断 |
| `truncate_bytes_over_limit_returns_truncated` | 字节模式截断 |

### 3. 行数统计测试

| 测试 | 验证点 |
|------|--------|
| `truncate_bytes_reports_original_line_count_when_truncated` | 字节模式行数 |
| `truncate_tokens_reports_original_line_count_when_truncated` | token 模式行数 |

### 4. 函数输出截断测试

| 测试 | 验证点 |
|------|--------|
| `truncates_across_multiple_under_limit_texts_and_reports_omitted` | 多项内容截断 |
| `formatted_truncate_text_content_items_with_policy_returns_original_under_limit` | 未超限保留 |
| `formatted_truncate_text_content_items_with_policy_merges_text_and_appends_images` | 文本合并+图片保留 |
| `formatted_truncate_text_content_items_with_policy_merges_all_text_for_token_budget` | token 预算合并 |

## 具体技术实现

### 基础分割断言

```rust
#[test]
fn split_string_works() {
    assert_eq!(split_string("hello world", 5, 5), (1, "hello", "world"));
    assert_eq!(split_string("abc", 0, 0), (3, "", ""));
}
```

### UTF-8 边界测试

```rust
#[test]
fn split_string_respects_utf8_boundaries() {
    // emoji 占 4 字节
    assert_eq!(split_string("😀abc😀", 5, 5), (1, "😀a", "c😀"));
    
    // 全 emoji 字符串，预算不足时返回空
    assert_eq!(split_string("😀😀😀😀😀", 1, 1), (5, "", ""));
    
    // 预算刚好覆盖部分 emoji
    assert_eq!(split_string("😀😀😀😀😀", 7, 7), (3, "😀", "😀"));
    assert_eq!(split_string("😀😀😀😀😀", 8, 8), (1, "😀😀", "😀😀"));
}
```

### 截断输出验证

```rust
#[test]
fn truncate_tokens_over_limit_returns_truncated() {
    let content = "this is an example of a long output that should be truncated";
    
    assert_eq!(
        "Total output lines: 1\n\nthis is an…10 tokens truncated… truncated",
        formatted_truncate_text(content, TruncationPolicy::Tokens(5)),
    );
}
```

### 函数输出截断验证

```rust
#[test]
fn truncates_across_multiple_under_limit_texts_and_reports_omitted() {
    // 构造 5 个文本项 + 1 个图片项
    let items = vec![
        InputText { text: t1.clone() },  // 完整保留
        InputText { text: t2.clone() },  // 完整保留
        InputImage { ... },              // 保留
        InputText { text: t3.repeat(10) }, // 截断
        InputText { text: t4 },          // 跳过（预算耗尽）
        InputText { text: t5 },          // 跳过（预算耗尽）
    ];

    let output = truncate_function_output_items_with_policy(&items, policy);

    // 期望：t1, t2, image, truncated_t3, summary
    assert_eq!(output.len(), 5);
    assert!(summary_text.contains("omitted 2 text items"));
}
```

## 关键代码路径与文件引用

### 被测函数

| 函数 | 路径 | 测试覆盖 |
|------|------|----------|
| `split_string` | `truncate.rs:267` | `split_string_*` 系列 |
| `formatted_truncate_text` | `truncate.rs:79` | `truncate_*` 系列 |
| `truncate_text` | `truncate.rs:88` | 间接测试 |
| `truncate_with_token_budget` | `truncate.rs:208` | `truncate_with_token_budget_*` |
| `truncate_function_output_items_with_policy` | `truncate.rs:145` | `truncates_across_multiple_*` |
| `formatted_truncate_text_content_items_with_policy` | `truncate.rs:98` | `formatted_truncate_text_content_items_*` |

### 测试依赖

| crate | 用途 |
|-------|------|
| `codex_protocol::models::FunctionCallOutputContentItem` | 函数输出内容项类型 |
| `pretty_assertions::assert_eq` | 友好断言输出 |

## 依赖与外部交互

### 纯单元测试

所有测试均为纯计算，无：
- 异步操作
- 文件系统访问
- 网络请求
- 外部进程

### 快速执行

测试执行时间极短，适合频繁运行。

## 风险、边界与改进建议

### 当前覆盖缺口

1. **极大预算**：未测试 `usize::MAX` 级别的预算
2. **极大字符串**：未测试 GB 级字符串的性能
3. **多行内容**：`split_string` 未直接测试含换行符的内容
4. **预算缩放**：`TruncationPolicy::Mul<f64>` 未测试
5. **零预算边界**：仅测试了 `Tokens(0)`，未测试 `Bytes(0)`

### 潜在问题

1. **浮点精度**：`Mul<f64>` 实现使用 `ceil()`，可能产生意外行为
```rust
// 当前实现
TruncationPolicy::Bytes(10) * 0.1  // = Bytes(1)
TruncationPolicy::Bytes(10) * 0.01 // = Bytes(1)，可能非预期
```

2. **行数统计**：`content.lines().count()` 不统计末尾空行

### 改进建议

1. **添加边界测试**：
```rust
#[test]
fn handles_very_large_budget() {
    let s = "small";
    let policy = TruncationPolicy::Bytes(usize::MAX);
    assert_eq!(truncate_text(s, policy), s);
}

#[test]
fn mul_handles_fractional_correctly() {
    let policy = TruncationPolicy::Bytes(100);
    assert_eq!(policy * 0.5, TruncationPolicy::Bytes(50));
    assert_eq!(policy * 0.01, TruncationPolicy::Bytes(1));
}
```

2. **性能基准测试**：
```rust
// 使用 criterion crate
fn bench_large_string_truncation(c: &mut Criterion) {
    let text = "x".repeat(10_000_000);
    c.bench_function("truncate 10MB", |b| {
        b.iter(|| truncate_text(&text, TruncationPolicy::Bytes(1000)))
    });
}
```

3. **Property-based 测试**：
```rust
// 使用 proptest crate
proptest! {
    #[test]
    fn truncated_length_never_exceeds_budget(s in ".*", budget in 0..1000usize) {
        let result = truncate_text(&s, TruncationPolicy::Bytes(budget));
        prop_assert!(result.len() <= budget + /* marker overhead */);
    }
}
```

### 代码统计

- 测试行数：313 行
- 测试函数：18 个
- 辅助导入：9 个

### 测试组织

测试按功能分组，但未使用模块组织。建议：
```rust
mod split_string_tests { ... }
mod truncation_policy_tests { ... }
mod function_output_tests { ... }
```
