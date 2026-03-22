# compact_tests.rs 深度研究文档

## 场景与职责

`compact_tests.rs` 是 `compact.rs` 和 `compact_remote.rs` 的配套测试文件，负责验证上下文压缩功能的正确性。测试覆盖了内容解析、历史构建、上下文注入、压缩后处理等各个方面。

### 测试覆盖范围

1. **内容项解析** - 验证 `content_items_to_text` 函数
2. **用户消息收集** - 验证 `collect_user_messages` 函数
3. **历史构建** - 验证 `build_compacted_history` 和 `build_compacted_history_with_limit`
4. **上下文注入** - 验证 `insert_initial_context_before_last_real_user_or_summary` 函数
5. **压缩后处理** - 验证 `process_compacted_history` 函数

## 功能点目的

### 1. 验证内容解析正确性

确保从 `ContentItem` 向量中正确提取文本内容：
- 合并多个文本段
- 忽略空文本和图像
- 正确处理换行符

### 2. 验证历史构建逻辑

确保压缩后的历史结构正确：
- 保留用户消息
- 添加摘要消息
- 应用 Token 限制

### 3. 验证上下文注入

确保初始上下文在正确的位置注入：
- Mid-turn 压缩：在最后一个用户消息前注入
- Pre-turn 压缩：不注入，后续回合处理

### 4. 防止回归

通过全面的测试用例，防止未来的代码变更破坏：
- 压缩历史结构
- 上下文注入位置
- 消息过滤逻辑

## 具体技术实现

### 测试辅助函数

```rust
async fn process_compacted_history_with_test_session(
    compacted_history: Vec<ResponseItem>,
    previous_turn_settings: Option<&PreviousTurnSettings>,
) -> (Vec<ResponseItem>, Vec<ResponseItem>) {
    let (session, turn_context) = crate::codex::make_session_and_context().await;
    session.set_previous_turn_settings(previous_turn_settings.cloned()).await;
    let initial_context = session.build_initial_context(&turn_context).await;
    let refreshed = crate::compact_remote::process_compacted_history(
        &session,
        &turn_context,
        compacted_history,
        InitialContextInjection::BeforeLastUserMessage,
    )
    .await;
    (refreshed, initial_context)
}
```

### 测试用例 1: 内容项转文本

**测试函数**: `content_items_to_text_joins_non_empty_segments`

**测试数据**:
```rust
let items = vec![
    ContentItem::InputText { text: "hello".to_string() },
    ContentItem::OutputText { text: String::new() },  // 空文本
    ContentItem::OutputText { text: "world".to_string() },
];
```

**期望输出**:
```rust
assert_eq!(Some("hello\nworld".to_string()), joined);
```

**验证点**:
- 非空文本段用换行符连接
- 空文本段被忽略

### 测试用例 2: 图像内容处理

**测试函数**: `content_items_to_text_ignores_image_only_content`

**测试数据**:
```rust
let items = vec![ContentItem::InputImage {
    image_url: "file://image.png".to_string(),
}];
```

**期望输出**:
```rust
assert_eq!(None, joined);
```

### 测试用例 3: 用户消息收集

**测试函数**: `collect_user_messages_extracts_user_text_only`

**验证点**:
- 只提取 role="user" 的消息
- 忽略 role="assistant" 的消息
- 忽略无法解析的项

### 测试用例 4: 会话前缀过滤

**测试函数**: `collect_user_messages_filters_session_prefix_entries`

**测试数据**:
```rust
let items = vec![
    // AGENTS.md 指令前缀
    ResponseItem::Message {
        content: vec![ContentItem::InputText {
            text: "# AGENTS.md instructions...".to_string(),
        }],
        ...
    },
    // 环境上下文前缀
    ResponseItem::Message {
        content: vec![ContentItem::InputText {
            text: "<ENVIRONMENT_CONTEXT>cwd=/tmp</ENVIRONMENT_CONTEXT>".to_string(),
        }],
        ...
    },
    // 真实用户消息
    ResponseItem::Message {
        content: vec![ContentItem::InputText {
            text: "real user message".to_string(),
        }],
        ...
    },
];
```

**期望输出**:
```rust
assert_eq!(vec!["real user message".to_string()], collected);
```

### 测试用例 5: Token 限制截断

**测试函数**: `build_token_limited_compacted_history_truncates_overlong_user_messages`

**测试逻辑**:
```rust
let max_tokens = 16;
let big = "word ".repeat(200);
let history = super::build_compacted_history_with_limit(
    Vec::new(),
    std::slice::from_ref(&big),
    "SUMMARY",
    max_tokens,
);
```

**验证点**:
- 超长消息被截断
- 截断消息包含 "tokens truncated" 标记
- 摘要消息完整保留

### 测试用例 6: 压缩后历史处理

**测试函数**: `process_compacted_history_replaces_developer_messages`

**验证点**:
- 旧的 developer 消息被移除
- 新的初始上下文被注入
- 用户消息被保留

### 测试用例 7: 上下文注入位置

**测试函数**: `process_compacted_history_inserts_context_before_last_real_user_message_only`

**测试数据**:
```rust
let compacted_history = vec![
    user_message("older user"),
    summary_message("summary text"),  // 摘要消息
    user_message("latest user"),      // 最后一个真实用户消息
];
```

**期望输出**:
- 初始上下文插入在 "latest user" 之前
- "older user" 和摘要消息保持原顺序

### 测试用例 8: 模型切换消息保留

**测试函数**: `process_compacted_history_reinjects_model_switch_message`

**验证点**:
- 当 `PreviousTurnSettings` 包含不同模型时
- 初始上下文包含 `<model_switch>` 标记

## 关键代码路径与文件引用

### 被测试函数

```rust
use super::*;  // compact.rs 的公开函数
```

包括：
- `content_items_to_text`
- `collect_user_messages`
- `build_compacted_history`
- `build_compacted_history_with_limit`
- `insert_initial_context_before_last_real_user_or_summary`
- `process_compacted_history` (来自 compact_remote.rs)

### 测试断言库

```rust
use pretty_assertions::assert_eq;
```

### 测试模块结构

```rust
// compact.rs
#[cfg(test)]
#[path = "compact_tests.rs"]
mod tests;
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `compact` | 被测试的压缩函数 |
| `compact_remote` | `process_compacted_history` |
| `codex` | 测试会话构造 |

### 协议类型

```rust
use codex_protocol::models::{ContentItem, ResponseItem};
```

## 风险、边界与改进建议

### 当前风险点

1. **异步测试复杂性**: 多个测试使用 `#[tokio::test]`，增加了测试复杂性和执行时间
2. **硬编码期望值**: 测试依赖硬编码的消息格式和标记
3. **测试数据构造复杂**: 手动构造 `ResponseItem` 较为繁琐

### 边界情况未覆盖

1. **空历史**: 压缩空历史的边界情况
2. **超大 Token 限制**: 极端 Token 限制下的行为
3. **并发压缩**: 多个压缩任务同时执行的场景
4. **错误恢复**: 压缩失败后的恢复逻辑

### 改进建议

1. **测试数据构建器**:
   ```rust
   struct TestHistoryBuilder {
       items: Vec<ResponseItem>,
   }
   
   impl TestHistoryBuilder {
       fn user_message(mut self, text: &str) -> Self {
           self.items.push(ResponseItem::Message { ... });
           self
       }
       
       fn assistant_message(mut self, text: &str) -> Self {
           self.items.push(ResponseItem::Message { ... });
           self
       }
       
       fn build(self) -> Vec<ResponseItem> {
           self.items
       }
   }
   ```

2. **参数化测试**:
   ```rust
   #[rstest]
   #[case(16, true)]   // 小限制，需要截断
   #[case(10000, false)]  // 大限制，不需要截断
   fn test_truncation(#[case] max_tokens: usize, #[case] should_truncate: bool) {
       // ...
   }
   ```

3. **性能测试**:
   ```rust
   #[bench]
   fn bench_build_compacted_history(b: &mut Bencher) {
       let messages = vec!["message".repeat(100); 1000];
       b.iter(|| build_compacted_history(Vec::new(), &messages, "summary"));
   }
   ```

4. **模糊测试**: 使用 `proptest` 生成随机历史进行测试

5. **快照测试**: 使用 `insta` 进行复杂的结构化输出测试

### 相关文档

- `compact.rs` - 本地压缩实现
- `compact_remote.rs` - 远程压缩实现
- `AGENTS.md` - 项目编码规范
