# truncation.rs 深入研究文档

## 场景与职责

`truncation.rs` 是 Codex 核心测试套件中的关键测试文件，负责验证**工具输出截断（Tool Output Truncation）**功能的正确性。该功能确保当工具（如 shell_command、MCP 工具）产生大量输出时，系统能够智能地将输出截断到模型可处理的合理大小，同时保留关键信息。

### 核心场景
1. **大输出 shell 命令**：如 `seq 1 100000` 生成 10 万行数字
2. **MCP 工具大输出**：如 echo 工具返回超大消息
3. **图像输出保留**：确保图像内容不被截断
4. **配置化截断限制**：验证用户可配置的 `tool_output_token_limit` 生效

---

## 功能点目的

### 1. 工具输出截断的必要性
- **模型上下文限制**：LLM 有固定的上下文窗口，过大的工具输出会耗尽 token 预算
- **性能优化**：传输和处理大输出会显著增加延迟
- **成本优化**：减少不必要的 token 消耗

### 2. 截断策略
- **基于 Token 的截断**：使用 `tool_output_token_limit` 配置（默认模型特定）
- **基于字节的估算**：当无法精确计算 token 时，使用 4 字节/token 的启发式估算
- **保留首尾**：截断中间部分，保留输出的开头和结尾，便于理解上下文

### 3. 截断标记格式
```
Exit code: 0
Wall time: 0.5 seconds
Total output lines: 100000
Output:
1
2
3
...
…137224 tokens truncated…
...
99999
100000
```

---

## 具体技术实现

### 关键流程

#### 1. 截断决策流程（`codex-rs/core/src/truncate.rs`）

```rust
// TruncationPolicy 定义截断策略
pub enum TruncationPolicy {
    Bytes(usize),   // 基于字节的截断
    Tokens(usize),  // 基于 token 的截断
}

// 主截断函数
pub(crate) fn truncate_text(content: &str, policy: TruncationPolicy) -> String {
    match policy {
        TruncationPolicy::Bytes(_) => truncate_with_byte_estimate(content, policy),
        TruncationPolicy::Tokens(_) => {
            let (truncated, _) = truncate_with_token_budget(content, policy);
            truncated
        }
    }
}
```

#### 2. 字节预算分割算法

```rust
fn split_budget(budget: usize) -> (usize, usize) {
    let left = budget / 2;
    (left, budget - left)  // 前后各占一半预算
}

fn split_string(s: &str, beginning_bytes: usize, end_bytes: usize) -> (usize, &str, &str) {
    // 遍历字符，确保在 UTF-8 边界处分割
    for (idx, ch) in s.char_indices() {
        let char_end = idx + ch.len_utf8();
        if char_end <= beginning_bytes {
            prefix_end = char_end;
            continue;
        }
        if idx >= tail_start_target {
            // 进入后缀区域
        }
        removed_chars += 1;
    }
}
```

#### 3. Token 估算

```rust
const APPROX_BYTES_PER_TOKEN: usize = 4;

pub(crate) fn approx_token_count(text: &str) -> usize {
    let len = text.len();
    len.saturating_add(APPROX_BYTES_PER_TOKEN.saturating_sub(1)) / APPROX_BYTES_PER_TOKEN
}
```

#### 4. MCP 工具输出截断（`codex-rs/core/src/tools/handlers/dynamic.rs`）

```rust
fn truncate_function_output_items_with_policy(
    items: &[FunctionCallOutputContentItem],
    policy: TruncationPolicy,
) -> Vec<FunctionCallOutputContentItem> {
    // 遍历内容项，对文本项应用截断，图像项直接保留
    for it in items {
        match it {
            FunctionCallOutputContentItem::InputText { text } => {
                // 应用截断策略
            }
            FunctionCallOutputContentItem::InputImage { .. } => {
                // 图像内容直接保留，不截断
            }
        }
    }
}
```

### 数据结构

#### 1. `TruncationPolicy`（`codex-rs/core/src/truncate.rs`）
```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum TruncationPolicy {
    Bytes(usize),
    Tokens(usize),
}

impl TruncationPolicy {
    pub fn token_budget(&self) -> usize {
        match self {
            TruncationPolicy::Bytes(bytes) => {
                usize::try_from(approx_tokens_from_byte_count(*bytes)).unwrap_or(usize::MAX)
            }
            TruncationPolicy::Tokens(tokens) => *tokens,
        }
    }

    pub fn byte_budget(&self) -> usize {
        match self {
            TruncationPolicy::Bytes(bytes) => *bytes,
            TruncationPolicy::Tokens(tokens) => approx_bytes_for_tokens(*tokens),
        }
    }
}
```

#### 2. 配置项（`codex-rs/core/src/config/mod.rs`）
```rust
pub struct Config {
    // ...
    /// Token budget applied when storing tool/function outputs in the context manager.
    pub tool_output_token_limit: Option<usize>,
    // ...
}
```

#### 3. 模型信息中的截断配置（`codex-rs/core/src/models_manager/model_info.rs`）
```rust
pub struct ModelInfo {
    // ...
    pub tool_output_token_limit: Option<i64>,
    // ...
}
```

---

## 关键代码路径与文件引用

### 核心实现文件

| 文件 | 职责 |
|------|------|
| `codex-rs/core/src/truncate.rs` | 截断算法核心实现，包括文本截断、token 估算 |
| `codex-rs/core/src/rollout/truncation.rs` | Rollout 级别的截断，基于用户消息边界 |
| `codex-rs/core/src/tools/handlers/dynamic.rs` | MCP 工具输出的截断处理 |
| `codex-rs/core/src/tools/context.rs` | 工具上下文管理，应用截断策略 |

### 配置文件

| 文件 | 职责 |
|------|------|
| `codex-rs/core/src/config/mod.rs` | `tool_output_token_limit` 配置定义 |
| `codex-rs/core/src/models_manager/model_info.rs` | 模型特定的截断限制 |

### 测试文件

| 文件 | 职责 |
|------|------|
| `codex-rs/core/tests/suite/truncation.rs` | 截断功能集成测试 |
| `codex-rs/core/src/truncate_tests.rs` | 截断算法单元测试 |

### 关键代码路径

```
1. 工具执行 -> 输出收集
   codex-rs/core/src/tools/handlers/dynamic.rs
   └── execute_tool_call_internal
       └── build_function_call_output
           └── apply_truncation_if_needed

2. 截断策略应用
   codex-rs/core/src/tools/context.rs
   └── ToolContext::apply_truncation_policy
       └── truncate_function_output_items_with_policy

3. 文本截断算法
   codex-rs/core/src/truncate.rs
   ├── truncate_text
   ├── truncate_with_token_budget
   └── truncate_with_byte_estimate
```

---

## 依赖与外部交互

### 内部依赖

```rust
// 测试依赖
use core_test_support::responses;  // Mock SSE 响应
use core_test_support::test_codex::test_codex;  // 测试 harness
use core_test_support::wait_for_event;  // 事件等待

// 协议类型
use codex_protocol::protocol::{EventMsg, Op, SandboxPolicy};
use codex_protocol::user_input::UserInput;

// 配置类型
use codex_core::config::types::{McpServerConfig, McpServerTransportConfig};
```

### 外部系统交互

1. **Mock OpenAI API Server**
   - 使用 `wiremock` 创建模拟服务器
   - 模拟 SSE 流式响应
   - 捕获和验证请求体中的 `function_call_output`

2. **MCP 测试服务器**
   - `test_stdio_server`：提供 echo 和 image 工具
   - 通过 STDIO 传输与 Codex 通信

### 测试基础设施

```rust
// 创建 Mock SSE 响应
mount_sse_once(&server, sse(vec![
    responses::ev_response_created("resp-1"),
    responses::ev_function_call(call_id, "shell_command", &args),
    responses::ev_completed("resp-1"),
])).await;

// 验证截断后的输出
let output = mock2
    .single_request()
    .function_call_output_text(call_id)
    .context("function_call_output present for shell call")?;
```

---

## 风险、边界与改进建议

### 已知风险

1. **Token 估算不准确**
   - 使用 4 字节/token 的启发式估算，实际 token 数可能不同
   - 不同模型的 tokenizer 可能产生不同结果
   - **缓解**：配置留有余量，实际限制略低于模型最大值

2. **截断位置不当**
   - 简单的前后分割可能截断关键信息
   - 某些输出（如 JSON）需要保留完整性
   - **缓解**：对结构化输出使用专门的序列化处理

3. **图像内容误截断**
   - 早期实现可能错误地截断图像数据
   - **测试覆盖**：`mcp_image_output_preserves_image_and_no_text_summary` 专门验证

### 边界情况

| 场景 | 处理方式 |
|------|----------|
| 空输出 | 直接返回，不添加截断标记 |
| 输出刚好在限制内 | 完整保留，无截断标记 |
| 单字符超过预算 | 仅返回截断标记 |
| 多行输出 | 保留行结构，显示总行数 |
| 图像 + 文本混合 | 图像始终保留，仅截断文本 |

### 改进建议

1. **智能截断**
   - 基于内容类型选择截断策略（代码、日志、JSON 等）
   - 使用语义分割而非简单的字节分割
   - 保留关键行（如错误信息、堆栈跟踪顶部）

2. **可观测性**
   - 增加截断事件遥测
   - 记录截断前后的 token 数
   - 向用户显示截断警告

3. **配置增强**
   - 支持按工具类型配置截断限制
   - 支持按文件类型配置截断策略
   - 支持动态调整截断限制

4. **测试覆盖**
   - 增加 Unicode 边界测试
   - 增加多字节字符测试
   - 增加极端大输出测试（MB 级别）

### 相关配置项

```toml
# config.toml 示例
[model]
tool_output_token_limit = 10000  # 设置工具输出 token 限制

[ghost_snapshot]
ignore_large_untracked_files = 10485760  # 10MB
ignore_large_untracked_dirs = 200
```

---

## 测试用例详解

### 1. `tool_call_output_configured_limit_chars_type`
- **目的**：验证自定义 token 限制生效
- **输入**：`seq 1 100000`（约 10 万行）
- **配置**：`tool_output_token_limit = 100_000`
- **验证**：输出长度约 40 万字符（约 10 万 token），无截断标记

### 2. `tool_call_output_exceeds_limit_truncated_chars_limit`
- **目的**：验证默认截断行为
- **输入**：`seq 1 100000`
- **验证**：输出约 10KB，包含 `…chars truncated…` 标记

### 3. `tool_call_output_exceeds_limit_truncated_for_model`
- **目的**：验证 gpt-5.1-codex 模型的 token 截断
- **验证**：输出包含 `…tokens truncated…` 标记

### 4. `tool_call_output_truncated_only_once`
- **目的**：确保只截断一次，避免重复标记
- **验证**：`tokens truncated` 只出现一次

### 5. `mcp_tool_call_output_exceeds_limit_truncated_for_model`
- **目的**：验证 MCP 工具输出截断
- **工具**：`mcp__rmcp__echo`
- **验证**：JSON 输出被截断，长度小于 2500 字符

### 6. `mcp_image_output_preserves_image_and_no_text_summary`
- **目的**：验证图像内容不被截断
- **验证**：输出为数组格式，包含完整图像数据，无截断标记

### 7. `token_policy_marker_reports_tokens` / `byte_policy_marker_reports_bytes`
- **目的**：验证不同策略的标记格式
- **验证**：Token 策略显示 "tokens truncated"，字节策略显示 "chars truncated"

### 8. `shell_command_output_not_truncated_with_custom_limit` / `mcp_tool_call_output_not_truncated_with_custom_limit`
- **目的**：验证大预算下不截断
- **配置**：`tool_output_token_limit = 50_000`
- **验证**：完整输出，无截断标记
