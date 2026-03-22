# 研究文档：codex-rs/core/src/rollout/truncation_tests.rs

## 场景与职责

`truncation_tests.rs` 是 `truncation.rs` 模块的单元测试文件，负责验证 rollout 截断功能的正确性。该测试文件确保：

1. **用户消息边界识别** - 正确识别 rollout 中的用户回合边界
2. **截断逻辑正确性** - 基于用户回合的截断操作产生预期结果
3. **回滚标记处理** - `ThreadRolledBack` 事件正确影响截断行为
4. **边界条件处理** - 各种边界情况（空列表、越界索引等）正确处理

这些测试对于确保 Codex 的上下文窗口管理和历史回溯功能的可靠性至关重要。

## 功能点目的

### 1. 基本截断测试 (`truncates_rollout_from_start_before_nth_user_only`)

验证核心截断功能：
- 从起始位置截断，保留前 N 个用户回合
- 截断边界严格位于第 N 个用户消息之前
- 助手消息、推理项、函数调用等非用户消息项随用户回合一起保留或截断

### 2. 无截断测试 (`truncation_max_keeps_full_rollout`)

验证 `usize::MAX` 作为特殊值时返回完整 rollout，不进行任何截断。

### 3. 回滚标记测试 (`truncates_rollout_from_start_applies_thread_rollback_markers`)

验证 `ThreadRolledBack` 事件的正确处理：
- 回滚标记减少有效用户回合计数
- 截断操作基于"有效历史"而非原始 rollout

### 4. 会话前缀忽略测试 (`ignores_session_prefix_messages_when_truncating_rollout_from_start`)

验证会话初始上下文（由 `Session::build_initial_context` 生成）不影响用户回合计数。这些前缀消息（如系统提示）不应被视为用户回合。

## 具体技术实现

### 测试辅助函数

#### `user_msg` - 创建测试用户消息
```rust
fn user_msg(text: &str) -> ResponseItem {
    ResponseItem::Message {
        id: None,
        role: "user".to_string(),
        content: vec![ContentItem::OutputText { text: text.to_string() }],
        end_turn: None,
        phase: None,
    }
}
```

#### `assistant_msg` - 创建测试助手消息
```rust
fn assistant_msg(text: &str) -> ResponseItem {
    ResponseItem::Message {
        id: None,
        role: "assistant".to_string(),
        content: vec![ContentItem::OutputText { text: text.to_string() }],
        end_turn: None,
        phase: None,
    }
}
```

### 测试用例详解

#### 测试 1：基本截断逻辑

```rust
#[test]
fn truncates_rollout_from_start_before_nth_user_only() {
    let items = [
        user_msg("u1"),      // idx 0: 第 1 个用户消息
        assistant_msg("a1"), // idx 1
        assistant_msg("a2"), // idx 2
        user_msg("u2"),      // idx 3: 第 2 个用户消息
        assistant_msg("a3"), // idx 4
        ResponseItem::Reasoning { ... },      // idx 5
        ResponseItem::FunctionCall { ... },   // idx 6
        assistant_msg("a4"), // idx 7
    ];

    let rollout: Vec<RolloutItem> = items
        .iter()
        .cloned()
        .map(RolloutItem::ResponseItem)
        .collect();

    // 截断到第 1 个用户消息之前（保留 u1, a1, a2）
    let truncated = truncate_rollout_before_nth_user_message_from_start(&rollout, 1);
    // 预期: [u1, a1, a2]

    // 截断到第 2 个用户消息之前（保留 u1, a1, a2, u2, a3, Reasoning, FunctionCall）
    let truncated2 = truncate_rollout_before_nth_user_message_from_start(&rollout, 2);
    // 预期: []（因为第 2 个用户消息后无内容）
}
```

**验证点**：
- 截断索引正确计算
- 非用户消息项（Reasoning、FunctionCall）随用户回合一起处理

#### 测试 2：无截断特殊值

```rust
#[test]
fn truncation_max_keeps_full_rollout() {
    let rollout = vec![
        RolloutItem::ResponseItem(user_msg("u1")),
        RolloutItem::ResponseItem(assistant_msg("a1")),
        RolloutItem::ResponseItem(user_msg("u2")),
    ];

    let truncated = truncate_rollout_before_nth_user_message_from_start(&rollout, usize::MAX);
    // 验证: truncated == rollout（完全相等）
}
```

#### 测试 3：回滚标记处理

```rust
#[test]
fn truncates_rollout_from_start_applies_thread_rollback_markers() {
    let rollout_items = vec![
        RolloutItem::ResponseItem(user_msg("u1")),      // 有效历史: u1
        RolloutItem::ResponseItem(assistant_msg("a1")),
        RolloutItem::ResponseItem(user_msg("u2")),      // 被回滚移除
        RolloutItem::ResponseItem(assistant_msg("a2")),
        RolloutItem::EventMsg(EventMsg::ThreadRolledBack(ThreadRolledBackEvent {
            num_turns: 1,  // 回滚 1 个用户回合
        })),
        RolloutItem::ResponseItem(user_msg("u3")),      // 有效历史: u3
        RolloutItem::ResponseItem(assistant_msg("a3")),
        RolloutItem::ResponseItem(user_msg("u4")),      // 有效历史: u4
        RolloutItem::ResponseItem(assistant_msg("a4")),
    ];

    // 有效用户历史: u1, u3, u4
    // n_from_start=2 应该截断到 u4 之前
    let truncated = truncate_rollout_before_nth_user_message_from_start(&rollout_items, 2);
    // 预期: rollout_items[..7]（包含 u1, a1, u2, a2, rollback, u3, a3）
}
```

**关键理解**：
- 回滚标记移除 u2，有效用户消息为 u1, u3, u4
- `n_from_start=2` 表示保留前 2 个有效用户回合（u1 和 u3）
- 截断点在 u4 之前（索引 7）

#### 测试 4：会话前缀处理

```rust
#[tokio::test]
async fn ignores_session_prefix_messages_when_truncating_rollout_from_start() {
    let (session, turn_context) = make_session_and_context().await;
    let mut items = session.build_initial_context(&turn_context).await;  // 会话前缀
    items.push(user_msg("feature request"));  // 第 1 个真实用户消息
    items.push(assistant_msg("ack"));
    items.push(user_msg("second question"));  // 第 2 个真实用户消息
    items.push(assistant_msg("answer"));

    let rollout_items: Vec<RolloutItem> = items
        .iter()
        .cloned()
        .map(RolloutItem::ResponseItem)
        .collect();

    // 截断到第 1 个用户回合之后
    let truncated = truncate_rollout_before_nth_user_message_from_start(&rollout_items, 1);
    // 预期: 保留前缀 + 第 1 个用户回合（u1, a1）
}
```

**重要说明**：
- 会话前缀（系统提示等）通过 `build_initial_context` 生成
- 这些前缀消息的角色可能是 `"system"` 或 `"developer"`
- `event_mapping::parse_turn_item` 会过滤掉非用户消息，因此前缀不影响用户回合计数

## 关键代码路径与文件引用

### 被测试函数

| 函数 | 定义位置 | 测试覆盖 |
|------|----------|----------|
| `truncate_rollout_before_nth_user_message_from_start` | `truncation.rs:51` | 全部 4 个测试 |
| `user_message_positions_in_rollout` | `truncation.rs:20` | 间接测试 |

### 依赖模块

| 模块/函数 | 路径 | 用途 |
|-----------|------|------|
| `make_session_and_context` | `codex_tests.rs` | 创建测试会话和上下文 |
| `event_mapping::parse_turn_item` | `event_mapping.rs:94` | 解析回合项（被间接测试） |

### 协议类型

| 类型 | 定义位置 |
|------|----------|
| `ResponseItem` | `protocol/src/models.rs` |
| `RolloutItem` | `protocol/src/protocol.rs` |
| `TurnItem` | `protocol/src/items.rs` |
| `ThreadRolledBackEvent` | `protocol/src/protocol.rs` |
| `ContentItem` | `protocol/src/models.rs` |
| `ReasoningItemReasoningSummary` | `protocol/src/models.rs` |

## 依赖与外部交互

### 测试依赖 Crate

```rust
use assert_matches::assert_matches;
use pretty_assertions::assert_eq;
```

### 被测模块

```rust
use super::*;  // truncation.rs 的导出
```

### 辅助测试模块

```rust
use crate::codex::make_session_and_context;  // 来自 codex_tests.rs
```

### 协议类型

```rust
use codex_protocol::models::ContentItem;
use codex_protocol::models::ReasoningItemReasoningSummary;
use codex_protocol::protocol::ThreadRolledBackEvent;
```

### 测试数据流

```
测试函数
    ├─> make_session_and_context() -> (Session, TurnContext)
    │    └─> 创建测试配置、模型管理器、执行策略等
    │
    ├─> session.build_initial_context(&turn_context) -> Vec<ResponseItem>
    │    └─> 生成会话前缀（系统提示等）
    │
    ├─> user_msg() / assistant_msg() -> ResponseItem
    │    └─> 创建测试消息项
    │
    └─> truncate_rollout_before_nth_user_message_from_start() -> Vec<RolloutItem>
         └─> 被测函数
```

## 风险、边界与改进建议

### 当前测试覆盖

| 场景 | 覆盖状态 | 说明 |
|------|----------|------|
| 基本截断 | ✅ 已覆盖 | `truncates_rollout_from_start_before_nth_user_only` |
| 无截断（usize::MAX） | ✅ 已覆盖 | `truncation_max_keeps_full_rollout` |
| 回滚标记 | ✅ 已覆盖 | `truncates_rollout_from_start_applies_thread_rollback_markers` |
| 会话前缀 | ✅ 已覆盖 | `ignores_session_prefix_messages_when_truncating_rollout_from_start` |
| 空 rollout | ❌ 未覆盖 | 应添加测试 |
| 越界索引 | ⚠️ 部分覆盖 | `truncates_rollout_from_start_before_nth_user_only` 测试了 n=2 |
| 连续回滚 | ❌ 未覆盖 | 多个连续回滚标记的场景 |
| 零值回滚 | ❌ 未覆盖 | `num_turns = 0` 的边界情况 |

### 潜在风险

1. **测试数据构造复杂**：`make_session_and_context` 是重型辅助函数，涉及多个模块的初始化，可能导致测试运行缓慢。

2. **隐式依赖**：会话前缀的识别依赖于 `event_mapping::parse_turn_item` 的实现细节，如果该函数行为改变，测试可能通过但生产代码行为错误。

3. **序列化比较**：测试使用 `serde_json::to_value` 进行相等性比较，可能掩盖某些字段差异。

### 改进建议

1. **添加边界测试**：
   ```rust
   #[test]
   fn truncation_empty_rollout() {
       let empty: Vec<RolloutItem> = vec![];
       let result = truncate_rollout_before_nth_user_message_from_start(&empty, 0);
       assert!(result.is_empty());
   }

   #[test]
   fn truncation_no_user_messages() {
       let rollout = vec![
           RolloutItem::ResponseItem(assistant_msg("only assistant")),
       ];
       let result = truncate_rollout_before_nth_user_message_from_start(&rollout, 0);
       assert!(result.is_empty());
   }

   #[test]
   fn truncation_zero_turns_rollback() {
       // 测试 num_turns = 0 的情况
   }
   ```

2. **添加性能测试**：
   ```rust
   #[test]
   fn truncation_large_rollout_performance() {
       // 测试 10万+ 项目的 rollout 截断性能
   }
   ```

3. **简化测试辅助函数**：
   - 考虑创建轻量级的 `make_minimal_session` 替代完整的 `make_session_and_context`
   - 或者使用 mock 对象替代真实 Session

4. **明确测试意图**：
   - 在 `ignores_session_prefix_messages_when_truncating_rollout_from_start` 中添加注释，说明前缀消息的角色类型
   - 验证 `build_initial_context` 返回的消息确实不被计为用户回合

5. **增加负面测试**：
   - 测试无效的回滚标记（如 `num_turns` 大于当前用户回合数）
   - 测试回滚标记出现在任何用户消息之前的情况
