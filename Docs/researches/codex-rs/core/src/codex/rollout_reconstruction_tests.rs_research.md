# rollout_reconstruction_tests.rs 研究文档

## 场景与职责

`rollout_reconstruction_tests.rs` 是 `rollout_reconstruction.rs` 的配套测试模块，包含 **18 个集成测试**，全面验证从历史 rollout 数据重建会话状态的正确性。测试覆盖以下核心场景：

1. **基础恢复场景**：验证 bare TurnContext、完整回合生命周期的处理
2. **Rollback 场景**：验证 ThreadRolledBack 事件对历史和元数据的正确影响
3. **Compaction 场景**：验证历史压缩后的重建逻辑
4. **边界情况**：未完成回合、不匹配的事件 ID、遗留数据格式等

该测试模块使用 **Tokio 异步运行时** 和 **pretty_assertions** 进行断言，确保重建结果与预期一致。

## 功能点目的

### 1. 测试分类

| 测试类别 | 测试函数 | 目的 |
|---------|---------|------|
| **基础恢复** | `record_initial_history_resumed_bare_turn_context_*` | 验证 TurnContext 是否能正确 hydrate settings |
| **Rollback - 已完成回合** | `reconstruct_history_rollback_keeps_history_and_metadata_in_sync_for_completed_turns` | 验证回滚已完成回合时历史和元数据同步 |
| **Rollback - 未完成回合** | `reconstruct_history_rollback_keeps_history_and_metadata_in_sync_for_incomplete_turn` | 验证回滚未完成回合的处理 |
| **Rollback - 跳过非用户回合** | `reconstruct_history_rollback_skips_non_user_turns_for_history_and_metadata` | 验证只有用户回合才计入 rollback |
| **Rollback - 超额回滚** | `reconstruct_history_rollback_clears_history_and_metadata_when_exceeding_user_turns` | 验证回滚数超过用户回合数时清空历史 |
| **Rollback - 仅跳过用户回合** | `record_initial_history_resumed_rollback_skips_only_user_turns` | 验证 standalone task turn 不计入 rollback |
| **Rollback - 未完成回合的 compaction** | `record_initial_history_resumed_rollback_drops_incomplete_user_turn_compaction_metadata` | 验证回滚丢弃未完成回合的 compaction 元数据 |
| **Compaction - 清除参考上下文** | `record_initial_history_resumed_does_not_seed_reference_context_item_after_compaction` | 验证 compaction 后参考上下文被清除 |
| **Compaction - 重新建立上下文** | `record_initial_history_resumed_turn_context_after_compaction_reestablishes_reference_context_item` | 验证 compaction 后新的 TurnContext 可重新建立参考 |
| **Compaction - 遗留格式** | `reconstruct_history_legacy_compaction_without_replacement_history_*` | 验证无 replacement_history 的遗留 compaction 处理 |
| **Abort 处理** | `record_initial_history_resumed_aborted_turn_without_id_*` | 验证 TurnAborted 事件的处理 |
| **尾部未完成回合** | `record_initial_history_resumed_trailing_incomplete_turn_*` | 验证会话末尾未完成回合的处理 |
| **替换未完成 compaction** | `record_initial_history_resumed_replaced_incomplete_compacted_turn_clears_reference_context_item` | 验证新 TurnStarted 替换未完成 compaction 回合 |

### 2. 测试基础设施

```rust
// 辅助函数：创建用户消息
fn user_message(text: &str) -> ResponseItem {
    ResponseItem::Message {
        id: None,
        role: "user".to_string(),
        content: vec![ContentItem::InputText { text: text.to_string() }],
        end_turn: None,
        phase: None,
    }
}

// 辅助函数：创建助手消息
fn assistant_message(text: &str) -> ResponseItem {
    ResponseItem::Message {
        id: None,
        role: "assistant".to_string(),
        content: vec![ContentItem::OutputText { text: text.to_string() }],
        end_turn: None,
        phase: None,
    }
}
```

### 3. 测试模式

每个测试遵循以下模式：
1. 创建 `Session` 和 `TurnContext`（通过 `make_session_and_context()`）
2. 构建 `RolloutItem` 序列，模拟各种场景
3. 调用 `record_initial_history()` 或 `reconstruct_history_from_rollout()`
4. 断言 `previous_turn_settings()` 和 `reference_context_item()` 的结果

## 具体技术实现

### 关键测试详解

#### 1. 基础恢复测试

```rust
#[tokio::test]
async fn record_initial_history_resumed_hydrates_previous_turn_settings_from_lifecycle_turn_with_missing_turn_context_id() {
    // 创建 TurnContextItem，但 turn_id 设为 None（模拟旧数据）
    let mut previous_context_item = TurnContextItem { ... };
    previous_context_item.turn_id = None;
    
    let rollout_items = vec![
        RolloutItem::EventMsg(EventMsg::TurnStarted(...)),
        RolloutItem::EventMsg(EventMsg::UserMessage(...)),
        RolloutItem::TurnContext(previous_context_item),  // 无 turn_id
        RolloutItem::EventMsg(EventMsg::TurnComplete(...)),
    ];
    
    // 验证：即使没有 turn_id，也能正确 hydrate settings
    assert_eq!(session.previous_turn_settings().await, Some(...));
}
```

**目的**：验证 TurnContextItem 即使没有 turn_id，只要位于有效的回合生命周期内，也能正确提取 `previous_turn_settings`。

#### 2. Rollback 测试 - 已完成回合

```rust
#[tokio::test]
async fn reconstruct_history_rollback_keeps_history_and_metadata_in_sync_for_completed_turns() {
    let rollout_items = vec![
        // 第一回合（应保留）
        RolloutItem::EventMsg(EventMsg::TurnStarted(...)),
        RolloutItem::EventMsg(EventMsg::UserMessage(...)),
        RolloutItem::TurnContext(first_context_item.clone()),
        RolloutItem::ResponseItem(turn_one_user.clone()),
        RolloutItem::ResponseItem(turn_one_assistant.clone()),
        RolloutItem::EventMsg(EventMsg::TurnComplete(...)),
        
        // 第二回合（应被回滚）
        RolloutItem::EventMsg(EventMsg::TurnStarted(...)),
        RolloutItem::EventMsg(EventMsg::UserMessage(...)),
        RolloutItem::TurnContext(rolled_back_context_item),
        RolloutItem::ResponseItem(turn_two_user),
        RolloutItem::ResponseItem(turn_two_assistant),
        RolloutItem::EventMsg(EventMsg::TurnComplete(...)),
        
        // 回滚事件
        RolloutItem::EventMsg(EventMsg::ThreadRolledBack(
            ThreadRolledBackEvent { num_turns: 1 }
        )),
    ];
    
    let reconstructed = session.reconstruct_history_from_rollout(&turn_context, &rollout_items).await;
    
    // 断言：只保留第一回合的历史
    assert_eq!(reconstructed.history, vec![turn_one_user, turn_one_assistant]);
    // 断言：metadata 来自第一回合
    assert_eq!(reconstructed.previous_turn_settings, Some(...));
    assert_eq!(reconstructed.reference_context_item, Some(first_context_item));
}
```

**目的**：验证 rollback 正确丢弃最近的用户回合，同时保持历史和元数据同步。

#### 3. Rollback 测试 - 跳过非用户回合

```rust
#[tokio::test]
async fn reconstruct_history_rollback_skips_non_user_turns_for_history_and_metadata() {
    let rollout_items = vec![
        // 第一回合（用户回合，应保留）
        RolloutItem::EventMsg(EventMsg::TurnStarted(...)),
        RolloutItem::EventMsg(EventMsg::UserMessage(...)),
        RolloutItem::TurnContext(first_context_item.clone()),
        RolloutItem::ResponseItem(turn_one_user.clone()),
        RolloutItem::ResponseItem(turn_one_assistant.clone()),
        RolloutItem::EventMsg(EventMsg::TurnComplete(...)),
        
        // 第二回合（用户回合，应被回滚）
        RolloutItem::EventMsg(EventMsg::TurnStarted(...)),
        RolloutItem::EventMsg(EventMsg::UserMessage(...)),
        RolloutItem::ResponseItem(turn_two_user),
        RolloutItem::ResponseItem(turn_two_assistant),
        RolloutItem::EventMsg(EventMsg::TurnComplete(...)),
        
        // 第三回合（standalone task，无 UserMessage，不应计入 rollback）
        RolloutItem::EventMsg(EventMsg::TurnStarted(...)),
        RolloutItem::ResponseItem(standalone_assistant),
        RolloutItem::EventMsg(EventMsg::TurnComplete(...)),
        
        // 回滚 1 个用户回合
        RolloutItem::EventMsg(EventMsg::ThreadRolledBack(
            ThreadRolledBackEvent { num_turns: 1 }
        )),
    ];
    
    // 断言：standalone task 回合不应消耗 rollback 计数
    // 因此第二回合（用户回合）被回滚，第一回合保留
}
```

**目的**：验证 rollback 只计算"用户回合"（包含 UserMessage 的回合），standalone task 回合不计入。

#### 4. Compaction 清除参考上下文

```rust
#[tokio::test]
async fn record_initial_history_resumed_does_not_seed_reference_context_item_after_compaction() {
    let rollout_items = vec![
        RolloutItem::TurnContext(previous_context_item),
        RolloutItem::Compacted(CompactedItem {
            message: String::new(),
            replacement_history: Some(Vec::new()),
        }),
    ];
    
    session.record_initial_history(...).await;
    
    // 断言：compaction 后 reference_context_item 为 None
    assert!(session.reference_context_item().await.is_none());
}
```

**目的**：验证 compaction 会清除参考上下文，因为 compaction 后的历史基线已改变。

#### 5. Compaction 后重新建立参考

```rust
#[tokio::test]
async fn record_initial_history_resumed_turn_context_after_compaction_reestablishes_reference_context_item() {
    let rollout_items = vec![
        RolloutItem::EventMsg(EventMsg::TurnStarted(...)),
        RolloutItem::EventMsg(EventMsg::UserMessage(...)),
        // Compaction 清除基线
        RolloutItem::Compacted(CompactedItem {
            message: String::new(),
            replacement_history: Some(Vec::new()),
        }),
        // 新的 TurnContext 重新建立基线
        RolloutItem::TurnContext(previous_context_item),
        RolloutItem::EventMsg(EventMsg::TurnComplete(...)),
    ];
    
    // 断言：compaction 后的 TurnContext 可以重新建立 reference_context_item
    assert!(session.reference_context_item().await.is_some());
}
```

**目的**：验证 compaction 后，如果在同一回合内有新的 TurnContext，可以重新建立参考上下文。

#### 6. 遗留 Compaction 处理

```rust
#[tokio::test]
async fn reconstruct_history_legacy_compaction_without_replacement_history_does_not_inject_current_initial_context() {
    let rollout_items = vec![
        RolloutItem::ResponseItem(user_message("before compact")),
        RolloutItem::ResponseItem(assistant_message("assistant reply")),
        // 遗留 compaction：无 replacement_history
        RolloutItem::Compacted(CompactedItem {
            message: "legacy summary".to_string(),
            replacement_history: None,
        }),
    ];
    
    let reconstructed = session.reconstruct_history_from_rollout(&turn_context, &rollout_items).await;
    
    // 断言：历史包含 compaction 前的消息和 summary
    assert_eq!(reconstructed.history, vec![
        user_message("before compact"),
        user_message("legacy summary"),
    ]);
    // 断言：reference_context_item 为 None
    assert!(reconstructed.reference_context_item.is_none());
}
```

**目的**：验证对遗留 compaction（无 replacement_history）的处理：使用 `build_compacted_history` 重建历史，并清除参考上下文。

#### 7. TurnAborted 处理

```rust
#[tokio::test]
async fn record_initial_history_resumed_aborted_turn_without_id_clears_active_turn_for_compaction_accounting() {
    let rollout_items = vec![
        // 第一回合（已完成）
        RolloutItem::EventMsg(EventMsg::TurnStarted(...)),
        RolloutItem::EventMsg(EventMsg::UserMessage(...)),
        RolloutItem::TurnContext(previous_context_item),
        RolloutItem::EventMsg(EventMsg::TurnComplete(...)),
        
        // 第二回合（已中止，无 turn_id）
        RolloutItem::EventMsg(EventMsg::TurnStarted(...)),
        RolloutItem::EventMsg(EventMsg::UserMessage(...)),
        RolloutItem::EventMsg(EventMsg::TurnAborted(
            TurnAbortedEvent { turn_id: None, reason: TurnAbortReason::Interrupted }
        )),
        
        // Compaction
        RolloutItem::Compacted(...),
    ];
    
    // 断言：无 turn_id 的 TurnAborted 正确清除活跃回合
    // compaction 不影响第一回合的元数据
}
```

**目的**：验证 TurnAborted 事件（特别是无 turn_id 的情况）正确处理，确保 compaction 会计准确。

#### 8. 不匹配 Abort 保留活跃回合

```rust
#[tokio::test]
async fn record_initial_history_resumed_unmatched_abort_preserves_active_turn_for_later_turn_context() {
    let rollout_items = vec![
        // 第一回合
        RolloutItem::EventMsg(EventMsg::TurnStarted(previous_turn_id)),
        ...
        RolloutItem::EventMsg(EventMsg::TurnComplete(...)),
        
        // 第二回合
        RolloutItem::EventMsg(EventMsg::TurnStarted(current_turn_id.clone())),
        RolloutItem::EventMsg(EventMsg::UserMessage(...)),
        // Abort 指向不同的 turn_id（不匹配）
        RolloutItem::EventMsg(EventMsg::TurnAborted(
            TurnAbortedEvent { turn_id: Some(unmatched_abort_turn_id), ... }
        )),
        // TurnContext 仍关联到当前回合
        RolloutItem::TurnContext(current_context_item.clone()),
        RolloutItem::EventMsg(EventMsg::TurnComplete(...)),
    ];
    
    // 断言：不匹配的 Abort 不影响当前回合
    assert_eq!(session.previous_turn_settings().await, Some(...));
    assert_eq!(session.reference_context_item().await, Some(current_context_item));
}
```

**目的**：验证 TurnAborted 的 turn_id 与当前回合不匹配时，不应影响当前回合的处理。

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/core/src/codex/rollout_reconstruction_tests.rs` (1291 行，18 个测试)

### 被测试的目标文件
- `codex-rs/core/src/codex/rollout_reconstruction.rs` - 重建逻辑
- `codex-rs/core/src/codex.rs` - Session 和 record_initial_history

### 依赖的协议类型

```rust
use crate::protocol::{CompactedItem, InitialHistory, ResumedHistory};
use codex_protocol::ThreadId;
use codex_protocol::models::{ContentItem, ResponseItem};
use codex_protocol::protocol::{
    TurnStartedEvent, TurnCompleteEvent, TurnAbortedEvent, UserMessageEvent,
    ThreadRolledBackEvent, TurnAbortReason, ModeKind
};
```

### 测试辅助

```rust
use pretty_assertions::assert_eq;  // 提供清晰的 diff 输出
```

## 依赖与外部交互

### 测试框架

| 依赖 | 用途 |
|------|------|
| `tokio::test` | 异步测试运行时 |
| `pretty_assertions::assert_eq` | 清晰的断言失败输出 |
| `serde_json::to_value` | 结构体比较（用于 TurnContextItem） |

### 被测系统 (SUT)

```rust
// Session 方法
session.record_initial_history(InitialHistory::Resumed(ResumedHistory { ... })).await;
session.reconstruct_history_from_rollout(&turn_context, &rollout_items).await;

// Session 状态查询
session.previous_turn_settings().await;
session.reference_context_item().await;
```

### 测试数据构建

```rust
// 典型 rollout 结构
[
    RolloutItem::EventMsg(EventMsg::TurnStarted(...)),  // 回合开始
    RolloutItem::EventMsg(EventMsg::UserMessage(...)),  // 用户消息
    RolloutItem::TurnContext(...),                       // 回合上下文
    RolloutItem::ResponseItem(...),                      // 模型响应
    RolloutItem::EventMsg(EventMsg::TurnComplete(...)), // 回合完成
    RolloutItem::EventMsg(EventMsg::ThreadRolledBack(...)), // 回滚
    RolloutItem::Compacted(...),                         // 历史压缩
]
```

## 风险、边界与改进建议

### 测试覆盖分析

| 场景 | 覆盖状态 | 说明 |
|------|---------|------|
| Bare TurnContext（无回合生命周期） | ✅ | `record_initial_history_resumed_bare_turn_context_does_not_hydrate_previous_turn_settings` |
| 完整回合生命周期 | ✅ | 多个测试覆盖 |
| Rollback - 已完成回合 | ✅ | `reconstruct_history_rollback_keeps_history_and_metadata_in_sync_for_completed_turns` |
| Rollback - 未完成回合 | ✅ | `reconstruct_history_rollback_keeps_history_and_metadata_in_sync_for_incomplete_turn` |
| Rollback - 跳过非用户回合 | ✅ | `reconstruct_history_rollback_skips_non_user_turns_for_history_and_metadata` |
| Rollback - 超额回滚 | ✅ | `reconstruct_history_rollback_clears_history_and_metadata_when_exceeding_user_turns` |
| Compaction - 标准格式 | ✅ | 多个测试覆盖 |
| Compaction - 遗留格式 | ✅ | `reconstruct_history_legacy_compaction_without_replacement_history_*` |
| TurnAborted - 有 ID | ✅ | `record_initial_history_resumed_unmatched_abort_preserves_active_turn_for_later_turn_context` |
| TurnAborted - 无 ID | ✅ | `record_initial_history_resumed_aborted_turn_without_id_clears_active_turn_for_compaction_accounting` |
| 尾部未完成回合 | ✅ | `record_initial_history_resumed_trailing_incomplete_turn_*` |
| Fork 场景 | ⚠️ | 通过 `InitialHistory::Forked` 间接测试 |

### 潜在风险

1. **测试与实现耦合**
   - 测试直接构造 `RolloutItem` 序列，如果协议结构变更，测试需要同步更新
   - 建议：考虑使用工厂函数或 builder 模式减少重复代码

2. **硬编码值**
   - 多个测试使用硬编码的模型名称、turn_id 等
   - 建议：提取常量或使用更有意义的命名

3. **缺少性能测试**
   - 当前测试都是功能性的，没有针对大型 rollout 的性能测试
   - 建议：添加基准测试，特别是处理数千条 rollout items 的场景

4. **缺少并发测试**
   - 重建逻辑是异步的，但测试都是顺序执行的
   - 建议：考虑并发调用重建的测试

### 改进建议

1. **提取通用模式**

当前多个测试重复构建类似的 rollout 结构：

```rust
// 建议：提取辅助函数
fn build_turn(
    turn_id: &str,
    user_message: &str,
    context_item: TurnContextItem,
    responses: Vec<ResponseItem>,
) -> Vec<RolloutItem> { ... }
```

2. **参数化测试**

对于 rollback 测试，可以使用参数化测试减少重复：

```rust
#[test_case(1, vec![turn1_user, turn1_assistant])]
#[test_case(2, vec![])]
#[tokio::test]
async fn test_rollback(num_turns: u32, expected_history: Vec<ResponseItem>) { ... }
```

3. **快照测试**

对于复杂的重建结果，考虑使用 `insta` 进行快照测试：

```rust
assert_snapshot!(reconstructed.history);
```

4. **文档测试**

在 `rollout_reconstruction.rs` 中添加文档测试示例，展示典型用法。

### 代码质量

- **优点**：
  - 测试命名清晰，描述性强
  - 使用 `pretty_assertions` 提供清晰的失败信息
  - 覆盖了大量边界情况
  - 使用 `serde_json::to_value` 进行复杂结构体比较

- **可改进**：
  - 测试文件较长（1291 行），可考虑按场景拆分为多个文件
  - 部分测试设置代码重复，可提取共享辅助函数
  - 缺少对错误路径的测试（如无效 rollout 数据）

### 维护建议

1. 当修改重建逻辑时，务必运行完整测试套件：`cargo test -p codex-core rollout_reconstruction`
2. 添加新功能时，同步添加对应的重建测试
3. 定期审查测试，删除已过时或冗余的测试
4. 考虑使用 `test-log` crate 在测试失败时输出调试信息
