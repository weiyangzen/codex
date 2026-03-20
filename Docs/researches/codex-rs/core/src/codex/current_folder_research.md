# Research: codex-rs/core/src/codex

## 1. 场景与职责

`codex-rs/core/src/codex` 目录是 Codex 核心会话管理模块的关键子目录，专门负责**对话历史的 Rollout 重建（Rollout Reconstruction）**。该目录包含两个主要文件：

- `rollout_reconstruction.rs`：实现从历史 Rollout 数据中重建对话历史的核心逻辑
- `rollout_reconstruction_tests.rs`：包含全面的单元测试，验证重建逻辑的正确性

该模块的主要职责是在**会话恢复（Resume）**和**会话 Fork** 场景下，从持久化的 Rollout 数据中重建对话历史，确保：
1. 历史消息的正确恢复
2. 会话元数据（如模型设置、实时模式状态）的正确继承
3. 处理复杂的边界情况，如线程回滚（Thread Rollback）、历史压缩（Compaction）等

## 2. 功能点目的

### 2.1 RolloutReconstruction 结构

```rust
pub(super) struct RolloutReconstruction {
    pub(super) history: Vec<ResponseItem>,
    pub(super) previous_turn_settings: Option<PreviousTurnSettings>,
    pub(super) reference_context_item: Option<TurnContextItem>,
}
```

该结构体封装了重建后的结果：
- `history`：重建后的对话历史（ResponseItem 列表）
- `previous_turn_settings`：上一轮的设置（模型、实时模式状态等）
- `reference_context_item`：参考上下文项，用于后续回合的上下文更新

### 2.2 TurnReferenceContextItem 枚举

```rust
enum TurnReferenceContextItem {
    #[default]
    NeverSet,           // 尚未设置 TurnContextItem
    Cleared,            // 之前设置的基线被后续的压缩清除
    Latest(Box<TurnContextItem>),  // 最新的基线
}
```

该枚举用于追踪 TurnContextItem 的状态，区分"从未设置"和"被清除"两种情况，这对 resume/fork 时的 hydration 逻辑至关重要。

### 2.3 ActiveReplaySegment 结构

```rust
struct ActiveReplaySegment<'a> {
    turn_id: Option<String>,
    counts_as_user_turn: bool,
    previous_turn_settings: Option<PreviousTurnSettings>,
    reference_context_item: TurnReferenceContextItem,
    base_replacement_history: Option<&'a [ResponseItem]>,
}
```

用于在反向遍历 Rollout 项目时累积每个回合段的信息。

### 2.4 核心方法：`reconstruct_history_from_rollout`

这是该模块的核心方法，执行以下步骤：

1. **反向扫描**（Newest-to-Oldest）：从最新的 Rollout 项开始反向遍历
2. **识别存活的历史基线**：找到最新的未被回滚的 replacement-history checkpoint
3. **收集 Resume 元数据**：提取 `previous_turn_settings` 和 `reference_context_item`
4. **处理回滚**：跳过被 `ThreadRolledBack` 事件影响的回合
5. **正向重建**：从存活的历史基线开始，正向应用 Rollout 项目重建历史

## 3. 具体技术实现

### 3.1 反向扫描算法

```rust
for (index, item) in rollout_items.iter().enumerate().rev() {
    match item {
        RolloutItem::Compacted(compacted) => { /* ... */ }
        RolloutItem::EventMsg(EventMsg::ThreadRolledBack(rollback)) => {
            pending_rollback_turns += rollback.num_turns;
        }
        RolloutItem::EventMsg(EventMsg::TurnComplete(event)) => { /* ... */ }
        RolloutItem::TurnContext(ctx) => { /* ... */ }
        RolloutItem::EventMsg(EventMsg::TurnStarted(event)) => {
            // 完成当前段落的处理
            finalize_active_segment(...);
        }
        // ... 其他事件类型
    }
}
```

### 3.2 finalize_active_segment 逻辑

该函数处理每个完成的回合段落：

1. **回滚处理**：如果存在待处理的回滚，且当前段落是用户回合，则消耗一次回滚
2. **历史基线更新**：如果找到了 replacement history 且尚未设置基线，则设置
3. **设置继承**：从最新的存活用户回合提取 `previous_turn_settings`
4. **上下文项更新**：更新 `reference_context_item`，处理 Cleared 状态

### 3.3 正向重建阶段

```rust
for item in rollout_suffix {
    match item {
        RolloutItem::ResponseItem(response_item) => {
            history.record_items(...);
        }
        RolloutItem::Compacted(compacted) => {
            if let Some(replacement_history) = &compacted.replacement_history {
                history.replace(replacement_history.clone());
            } else {
                // 处理遗留的 compaction（无 replacement_history）
                // ...
            }
        }
        RolloutItem::EventMsg(EventMsg::ThreadRolledBack(rollback)) => {
            history.drop_last_n_user_turns(rollback.num_turns);
        }
        // ...
    }
}
```

### 3.4 关键边界条件处理

1. **Legacy Compaction**：处理没有 `replacement_history` 的旧格式 compaction
2. **Incomplete Turn**：处理未完成的回合（如用户发送消息后会话中断）
3. **Turn ID 匹配**：确保 TurnContext 与对应回合的生命周期事件匹配
4. **Aborted Turn**：处理被中止的回合（如用户中断）

## 4. 关键代码路径与文件引用

### 4.1 主要文件

| 文件 | 行数 | 描述 |
|------|------|------|
| `rollout_reconstruction.rs` | ~297 | 核心重建逻辑 |
| `rollout_reconstruction_tests.rs` | ~1291 | 单元测试 |

### 4.2 关键代码路径

1. **Session::record_initial_history** (`codex.rs:2095`)
   - 调用 `apply_rollout_reconstruction` 应用重建逻辑
   - 处理 New/Resumed/Forked 三种历史类型

2. **Session::apply_rollout_reconstruction** (`codex.rs:2186`)
   ```rust
   let reconstructed_rollout = self
       .reconstruct_history_from_rollout(turn_context, rollout_items)
       .await;
   self.replace_history(
       reconstructed_rollout.history,
       reconstructed_rollout.reference_context_item,
   ).await;
   ```

3. **Session::reconstruct_history_from_rollout** (`rollout_reconstruction.rs:86`)
   - 核心重建算法实现

### 4.3 相关数据结构

- `RolloutItem` (`codex_protocol::protocol::RolloutItem`)：Rollout 中的项目类型
- `TurnContextItem`：回合上下文快照
- `PreviousTurnSettings`：上一轮设置（模型、实时模式）
- `CompactedItem`：历史压缩项

## 5. 依赖与外部交互

### 5.1 内部依赖

```rust
use crate::compact;
use crate::compact::collect_user_messages;
use crate::context_manager::ContextManager;
use crate::protocol::{CompactedItem, EventMsg, RolloutItem, TurnContextItem};
```

### 5.2 协议依赖

```rust
use codex_protocol::protocol::{TurnStartedEvent, TurnCompleteEvent, TurnAbortedEvent, ThreadRolledBackEvent};
use codex_protocol::models::{ContentItem, ResponseItem};
```

### 5.3 交互模块

| 模块 | 交互方式 | 用途 |
|------|----------|------|
| `context_manager` | 调用 `ContextManager::new()` 和 `record_items` | 重建历史存储 |
| `compact` | 调用 `build_compacted_history` | 处理遗留 compaction |
| `codex_protocol` | 使用 `RolloutItem`, `TurnContextItem` 等类型 | 数据协议 |
| `Session` (父模块) | 被调用 `reconstruct_history_from_rollout` | 触发重建 |

## 6. 风险、边界与改进建议

### 6.1 已知风险与边界

1. **Legacy Compaction 降级处理**
   - 对于没有 `replacement_history` 的旧格式 compaction，当前实现会清除 `reference_context_item`
   - 这会导致在恢复后重新注入当前上下文，可能造成暂时的分布外提示形状
   - TODO 注释（line 259-260）表明未来可能放弃对 None replacement_history 的支持

2. **Turn ID 匹配复杂性**
   - `turn_ids_are_compatible` 函数处理多种 ID 匹配情况
   - 包括缺失 ID、ID 不匹配等边界情况
   - 测试用例显示 abort 事件可能没有 turn_id，需要特殊处理

3. **回滚计数仅针对用户回合**
   - `ThreadRolledBack` 只计数包含 `UserMessage` 的回合
   - 独立的任务回合（standalone task turns）不计入回滚

### 6.2 测试覆盖

测试文件包含 20+ 个测试用例，覆盖：
- 基本恢复场景
- 回滚处理（completed/incomplete turns）
- 非用户回合的回滚跳过
- 回滚超出用户回合数（清空历史）
- 遗留 compaction 处理
- TurnContext 在 compaction 后的重新建立
- Aborted turn 的 ID 匹配
- 尾部未完成回合的处理

### 6.3 改进建议

1. **移除 Legacy Compaction 支持**
   - 根据 TODO 注释，当确定不再支持旧格式后，可以简化第二遍循环
   - 这将减少代码复杂度和维护负担

2. **Lazy Reverse Loader**
   - 注释提到当前使用 eager bridge，未来应迁移到 lazy reverse loader
   - 这将改善大历史的内存使用和启动性能

3. **更清晰的错误处理**
   - 当前某些错误情况（如 ID 不匹配）只是静默处理
   - 考虑增加更多诊断日志或警告

4. **测试增强**
   - 可以增加更多并发场景测试
   - 测试极端大历史的性能表现
