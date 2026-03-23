# truncate.rs 研究文档

## 场景与职责

`truncate.rs` 是 Codex 核心 crate 的**文本截断工具模块**，负责处理大段输出的智能截断：

1. **Token/字节预算管理**：支持基于 token 或字节的截断策略
2. **UTF-8 安全截断**：确保截断不破坏多字节字符边界
3. **中间截断模式**：保留内容开头和结尾，截断中间部分（便于查看上下文）
4. **函数输出截断**：处理工具调用返回的多项内容（文本+图片）
5. **预算转换**：token 和字节之间的近似转换

该模块是输出控制的关键组件，防止大段命令输出或文件内容占满上下文窗口。

## 功能点目的

### 1. TruncationPolicy 枚举

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum TruncationPolicy {
    Bytes(usize),
    Tokens(usize),
}
```

支持两种截断模式，可相互转换预算。

### 2. 预算计算方法

```rust
impl TruncationPolicy {
    /// Token 预算：Tokens 直接返回，Bytes 使用启发式转换
    pub fn token_budget(&self) -> usize { ... }
    
    /// 字节预算：Bytes 直接返回，Tokens 使用启发式转换
    pub fn byte_budget(&self) -> usize { ... }
}
```

### 3. 核心截断函数

| 函数 | 用途 |
|------|------|
| `truncate_text` | 基础文本截断 |
| `formatted_truncate_text` | 带行数统计的截断 |
| `truncate_with_token_budget` | 基于 token 预算的截断 |
| `truncate_with_byte_estimate` | 基于字节估计的截断 |

### 4. 函数输出截断

```rust
pub(crate) fn truncate_function_output_items_with_policy(
    items: &[FunctionCallOutputContentItem],
    policy: TruncationPolicy,
) -> Vec<FunctionCallOutputContentItem>
```

处理混合内容（文本+图片），保留图片，截断文本。

## 具体技术实现

### 启发式转换

```rust
const APPROX_BYTES_PER_TOKEN: usize = 4;

pub(crate) fn approx_token_count(text: &str) -> usize {
    let len = text.len();
    len.saturating_add(APPROX_BYTES_PER_TOKEN.saturating_sub(1)) / APPROX_BYTES_PER_TOKEN
}

pub(crate) fn approx_bytes_for_tokens(tokens: usize) -> usize {
    tokens.saturating_mul(APPROX_BYTES_PER_TOKEN)
}
```

使用 4 字节/token 的近似值，这是英语文本的经验值。

### 中间截断算法

```rust
fn split_string(s: &str, beginning_bytes: usize, end_bytes: usize) -> (usize, &str, &str) {
    let len = s.len();
    let tail_start_target = len.saturating_sub(end_bytes);
    let mut prefix_end = 0usize;
    let mut suffix_start = len;
    let mut removed_chars = 0usize;
    let mut suffix_started = false;

    for (idx, ch) in s.char_indices() {
        let char_end = idx + ch.len_utf8();
        if char_end <= beginning_bytes {
            prefix_end = char_end;
            continue;
        }

        if idx >= tail_start_target {
            if !suffix_started {
                suffix_start = idx;
                suffix_started = true;
            }
            continue;
        }

        removed_chars = removed_chars.saturating_add(1);
    }

    if suffix_start < prefix_end {
        suffix_start = prefix_end;
    }

    let before = &s[..prefix_end];
    let after = &s[suffix_start..];
    (removed_chars, before, after)
}
```

算法特点：
- 单次遍历，O(n) 复杂度
- 严格遵循 UTF-8 边界（使用 `char_indices` 和 `len_utf8`）
- 处理前后预算重叠的情况

### 预算分割

```rust
fn split_budget(budget: usize) -> (usize, usize) {
    let left = budget / 2;
    (left, budget - left)  // 前半部分向下取整，后半部分向上取整
}
```

### 截断标记格式

```rust
fn format_truncation_marker(policy: TruncationPolicy, removed_count: u64) -> String {
    match policy {
        TruncationPolicy::Tokens(_) => format!("…{removed_count} tokens truncated…"),
        TruncationPolicy::Bytes(_) => format!("…{removed_count} chars truncated…"),
    }
}
```

### 函数输出截断策略

```rust
pub(crate) fn truncate_function_output_items_with_policy(items, policy) -> Vec<...> {
    let mut out = Vec::with_capacity(items.len());
    let mut remaining_budget = ...;
    let mut omitted_text_items = 0usize;

    for it in items {
        match it {
            InputText { text } => {
                if cost <= remaining_budget {
                    out.push(...);  // 完整保留
                    remaining_budget -= cost;
                } else {
                    // 截断或跳过
                }
            }
            InputImage { ... } => {
                out.push(...);  // 图片不消耗预算，全部保留
            }
        }
    }

    if omitted_text_items > 0 {
        out.push(InputText { 
            text: format!("[omitted {omitted_text_items} text items ...]") 
        });
    }
}
```

## 关键代码路径与文件引用

### 协议依赖

| 类型 | 路径 | 用途 |
|------|------|------|
| `FunctionCallOutputContentItem` | `codex_protocol::models` | 函数输出内容项 |
| `TruncationMode` | `codex_protocol::openai_models` | 截断模式枚举 |
| `TruncationPolicyConfig` | `codex_protocol::openai_models` | 配置结构 |
| `ProtocolTruncationPolicy` | `codex_protocol::protocol` | 协议层截断策略 |

### 转换实现

```rust
impl From<TruncationPolicy> for ProtocolTruncationPolicy { ... }
impl From<TruncationPolicyConfig> for TruncationPolicy { ... }
impl std::ops::Mul<f64> for TruncationPolicy { ... }  // 预算缩放
```

### 调用方

- **RolloutRecorder**: 持久化时截断命令输出
- **工具执行**: 截断大段命令返回
- **文件读取**: 截断大文件内容

## 依赖与外部交互

### 外部 crate

| crate | 用途 |
|-------|------|
| `codex_protocol` | 协议类型定义 |

### 纯工具模块

无异步操作，无文件系统访问，纯字符串处理。

## 风险、边界与改进建议

### 已知限制

1. **启发式精度**：4 字节/token 是近似值，实际 token 数取决于具体分词器
2. **无真实 tokenization**：未使用 tiktoken 等库进行精确计数
3. **图片预算**：图片项不纳入预算计算，可能导致超限

### 边界情况

1. **零预算**：返回仅包含截断标记的字符串
2. **预算小于标记**：可能产生奇怪输出（如 "…13 chars truncated…t"）
3. **空字符串**：正确处理，返回空
4. **UTF-8 边界**：已处理，不会截断多字节字符中间

### 改进建议

1. **精确 tokenization**：
   - 集成 tiktoken 或类似库
   - 添加 `TruncationPolicy::PreciseTokens` 变体

2. **配置启发式**：
```rust
// 允许用户配置 bytes_per_token
pub struct TruncationConfig {
    pub bytes_per_token: usize,  // 默认 4
}
```

3. **图片预算**：
   - 估算图片 token（如 GPT-4V 的 vision 定价）
   - 或添加图片数量限制

4. **性能优化**：
   - `split_string` 可优化为双指针而非单指针
   - 大文本可考虑使用 `memchr` 等快速扫描

5. **更多截断模式**：
   - 仅保留开头（尾部截断）
   - 仅保留结尾（头部截断）
   - 智能摘要（使用模型生成）

### 代码统计

- 代码行数：363 行
- 公共函数：8 个
- 私有辅助函数：10 个
- 测试模块：内联（`truncate_tests.rs`）

### 代码质量

- 文档：模块级文档完整，关键函数有注释
- 错误处理：使用 `saturating_*` 防止溢出
- 边界处理：UTF-8 安全，空字符串处理
