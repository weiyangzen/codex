# Research: codex-rs/core/templates/compact/summary_prefix.md

## 场景与职责

该文件是 Codex CLI 核心库中的**上下文压缩摘要前缀模板**，用于标识和标记由 compaction 流程生成的摘要消息。它是一个极短但关键的模板文件，在本地压缩（local compaction）流程中作为摘要消息的头部前缀。

该前缀有两个核心作用：
1. **标识摘要消息**: 区分普通用户消息和 compaction 生成的摘要消息
2. **提示后续 LLM**: 告知接续工作的模型这是一个由之前 LLM 生成的思维过程总结

## 功能点目的

1. **消息类型识别**: 通过特定前缀字符串识别 compaction 摘要，用于后续过滤和处理
2. **避免重复压缩**: 识别已压缩的消息，防止在收集用户消息时重复包含摘要内容
3. **语义标记**: 向模型表明这是之前对话的总结，而非用户的直接输入

模板内容为：
```
Another language model started to solve this problem and produced a summary of its thinking process. You also have access to the state of the tools that were used by that language model. Use this to build on the work that has already been done and avoid duplicating work. Here is the summary produced by the other language model, use the information in this summary to assist with your own analysis:
```

## 具体技术实现

### 关键流程

1. **模板加载**：在 `codex-rs/core/src/compact.rs` 中编译时嵌入：
   ```rust
   pub const SUMMARY_PREFIX: &str = include_str!("../templates/compact/summary_prefix.md");
   ```

2. **摘要消息构造**（`run_compact_task_inner` 函数，第 194 行）：
   ```rust
   let summary_suffix = get_last_assistant_message_from_turn(history_items).unwrap_or_default();
   let summary_text = format!("{SUMMARY_PREFIX}\n{summary_suffix}");
   ```

3. **摘要消息识别**（`is_summary_message` 函数，第 269-271 行）：
   ```rust
   pub(crate) fn is_summary_message(message: &str) -> bool {
       message.starts_with(format!("{SUMMARY_PREFIX}\n").as_str())
   }
   ```

4. **用户消息收集过滤**（`collect_user_messages` 函数，第 253-267 行）：
   ```rust
   pub(crate) fn collect_user_messages(items: &[ResponseItem]) -> Vec<String> {
       items
           .iter()
           .filter_map(|item| match crate::event_mapping::parse_turn_item(item) {
               Some(TurnItem::UserMessage(user)) => {
                   if is_summary_message(&user.message()) {
                       None  // 过滤掉摘要消息
                   } else {
                       Some(user.message())
                   }
               }
               _ => None,
           })
           .collect()
   }
   ```

### 数据结构

摘要消息最终作为 `ResponseItem::Message` 存储：
```rust
ResponseItem::Message {
    id: None,
    role: "user".to_string(),  // 注意：摘要以用户角色存储
    content: vec![ContentItem::InputText { text: summary_text }],
    end_turn: None,
    phase: None,
}
```

### 关键常量

| 常量 | 来源文件 | 用途 |
|------|---------|------|
| `SUMMARY_PREFIX` | `summary_prefix.md` | 摘要消息前缀 |
| `SUMMARIZATION_PROMPT` | `prompt.md` | 请求模型生成摘要的 prompt |

## 关键代码路径与文件引用

### 核心实现文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/src/compact.rs` | 包含 `SUMMARY_PREFIX` 引用和摘要构造逻辑 |
| `codex-rs/core/templates/compact/prompt.md` | 配合使用的压缩请求模板 |

### 使用场景

1. **本地压缩** (`run_compact_task_inner`): 
   - 构造摘要消息时添加前缀
   - 第 194 行: `let summary_text = format!("{SUMMARY_PREFIX}\n{summary_suffix}");`

2. **消息过滤** (`collect_user_messages`):
   - 过滤已存在的摘要消息，避免重复
   - 第 258-260 行: 检查 `is_summary_message()` 返回 `None` 跳过

3. **摘要检测** (`is_summary_message`):
   - 检查消息是否以 `"{SUMMARY_PREFIX}\n"` 开头

### 测试引用

在 `codex-rs/core/tests/suite/compact.rs` 中：
```rust
use codex_core::compact::SUMMARY_PREFIX;

fn summary_with_prefix(summary: &str) -> String {
    format!("{SUMMARY_PREFIX}\n{summary}")
}
```

测试用例验证：
- 压缩后的请求包含带前缀的摘要消息
- 多次压缩时正确累积摘要
- 摘要消息不会被误认为是普通用户消息

## 依赖与外部交互

### 内部依赖

1. **compact.rs 模块**: 主要使用者，负责摘要构造和识别
2. **测试模块**: `compact.rs` 测试使用 `SUMMARY_PREFIX` 构造预期结果

### 与 prompt.md 的关系

| 文件 | 角色 | 交互 |
|------|------|------|
| `prompt.md` | 输入 | 请求模型生成摘要 |
| `summary_prefix.md` | 输出标记 | 标记生成的摘要消息 |

流程关系：
```
User Request + SUMMARIZATION_PROMPT -> Model -> Summary
                                                  |
                                                  v
                                    SUMMARY_PREFIX + Summary -> New History Item
```

## 风险、边界与改进建议

### 风险

1. **硬编码前缀**: 前缀内容是固定的英文文本，如果模型输出格式变化可能导致识别失败
2. **误识别风险**: 如果用户消息恰好以相同文本开头，可能被误认为摘要消息
3. **多语言支持**: 当前前缀为英文，对非英语用户不够友好

### 边界条件

1. **空摘要处理**: 如果模型返回空摘要，代码会替换为 `"(no summary available)"`，但仍会添加前缀
   ```rust
   let summary_text = if summary_text.is_empty() {
       "(no summary available)".to_string()
   } else {
       summary_text.to_string()
   };
   ```

2. **换行符依赖**: `is_summary_message` 检查包含换行符 `"\n"`，确保前缀是独立的一行

### 改进建议

1. **结构化元数据**: 考虑使用结构化字段（如 `phase: Some("compaction_summary")`）而非文本来标识摘要消息
2. **可配置前缀**: 允许通过配置自定义前缀文本，支持多语言场景
3. **版本控制**: 如果前缀内容变更，需要考虑向后兼容性（旧会话中的摘要消息识别）
4. **更精确的识别**: 考虑添加唯一标识符或哈希，避免用户消息误匹配

### 相关代码片段

**构造摘要消息**（compact.rs:191-206）：
```rust
let history_snapshot = sess.clone_history().await;
let history_items = history_snapshot.raw_items();
let summary_suffix = get_last_assistant_message_from_turn(history_items).unwrap_or_default();
let summary_text = format!("{SUMMARY_PREFIX}\n{summary_suffix}");
let user_messages = collect_user_messages(history_items);

let mut new_history = build_compacted_history(Vec::new(), &user_messages, &summary_text);
```

**历史重建**（compact.rs:324-389）：
```rust
pub(crate) fn build_compacted_history(
    initial_context: Vec<ResponseItem>,
    user_messages: &[String],
    summary_text: &str,
) -> Vec<ResponseItem> {
    // ... 保留用户消息，添加带前缀的摘要消息
}
```
