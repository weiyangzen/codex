# rollout_reconstruction.rs 研究文档

## 场景与职责

`rollout_reconstruction.rs` 是 Codex 核心会话管理的关键模块，负责**从历史 rollout 数据中重建会话状态**。主要服务于以下场景：

1. **会话恢复 (Resume)**：用户重新打开之前的会话时，从持久化的 rollout 文件中恢复历史对话状态
2. **会话分支 (Fork)**：基于现有会话创建分支时，复制并重建历史上下文
3. **历史压缩后的状态重建**：处理 compaction 后的历史数据重建

该模块的核心职责是解析 `RolloutItem` 序列（按时间顺序记录的所有会话事件），并从中重建出：
- 完整的对话历史 (`Vec<ResponseItem>`)
- 上一回合的设置 (`PreviousTurnSettings`，包含模型、实时模式等)
- 参考上下文项 (`TurnContextItem`，用于后续 diff 计算)

## 功能点目的

### 1. 反向扫描与正向重建

采用**双阶段算法**：
- **反向扫描阶段**：从最新的 rollout item 向最旧扫描，识别出"幸存"的段（segments）和关键元数据
- **正向重建阶段**：基于反向扫描确定的基线，正向重建完整的历史

这种设计允许：
- 高效处理 rollback（回滚）操作
- 识别 compaction 后的有效历史基线
- 提取最新的用户回合设置作为 resume/fork 的上下文

### 2. 回合边界识别

通过识别特定事件类型来界定回合边界：
- `TurnStarted`：回合开始标记
- `TurnComplete` / `TurnAborted`：回合结束标记
- `UserMessage`：用户消息（标记这是一个"用户回合"）
- `TurnContext`：回合上下文元数据

### 3. Rollback 处理

`ThreadRolledBack` 事件表示需要丢弃最近 N 个用户回合。反向扫描时：
- 维护 `pending_rollback_turns` 计数器
- 跳过被回滚的回合段
- 确保历史和元数据同步

### 4. Compaction 处理

`Compacted` 事件表示历史已被压缩：
- 如果存在 `replacement_history`，用它替换当前历史基线
- 处理遗留的 compaction（无 replacement_history）情况

## 具体技术实现

### 关键数据结构

```rust
/// 重建结果
#[derive(Debug)]
pub(super) struct RolloutReconstruction {
    pub(super) history: Vec<ResponseItem>,                    // 重建的历史
    pub(super) previous_turn_settings: Option<PreviousTurnSettings>,  // 上一回合设置
    pub(super) reference_context_item: Option<TurnContextItem>,       // 参考上下文
}

/// 回合参考上下文项的状态机
#[derive(Debug, Default)]
enum TurnReferenceContextItem {
    #[default]
    NeverSet,           // 尚未设置
    Cleared,            // 被 compaction 清除
    Latest(Box<TurnContextItem>),  // 最新有效的上下文
}

/// 活跃的重建段（反向扫描时使用）
#[derive(Debug, Default)]
struct ActiveReplaySegment<'a> {
    turn_id: Option<String>,
    counts_as_user_turn: bool,           // 是否包含用户消息
    previous_turn_settings: Option<PreviousTurnSettings>,
    reference_context_item: TurnReferenceContextItem,
    base_replacement_history: Option<&'a [ResponseItem]>,
}
```

### 核心算法流程

#### 反向扫描阶段 (`reconstruct_history_from_rollout`)

```rust
for (index, item) in rollout_items.iter().enumerate().rev() {
    match item {
        RolloutItem::Compacted(compacted) => {
            // 标记上下文被清除，记录 replacement_history 基线
        }
        RolloutItem::EventMsg(EventMsg::ThreadRolledBack(rollback)) => {
            // 增加 pending_rollback_turns
        }
        RolloutItem::EventMsg(EventMsg::TurnComplete(event)) => {
            // 捕获 turn_id
        }
        RolloutItem::EventMsg(EventMsg::UserMessage(_)) => {
            // 标记为"用户回合"
        }
        RolloutItem::TurnContext(ctx) => {
            // 捕获 previous_turn_settings 和 reference_context_item
        }
        RolloutItem::EventMsg(EventMsg::TurnStarted(event)) => {
            // 完成当前段，调用 finalize_active_segment
        }
        // ... 其他事件类型忽略
    }
    
    // 提前终止条件：已找到基线和所有必要元数据
    if base_replacement_history.is_some() 
        && previous_turn_settings.is_some() 
        && !matches!(reference_context_item, TurnReferenceContextItem::NeverSet) {
        break;
    }
}
```

#### 段终结逻辑 (`finalize_active_segment`)

```rust
fn finalize_active_segment(
    active_segment: ActiveReplaySegment<'a>,
    base_replacement_history: &mut Option<&'a [ResponseItem]>,
    previous_turn_settings: &mut Option<PreviousTurnSettings>,
    reference_context_item: &mut TurnReferenceContextItem,
    pending_rollback_turns: &mut usize,
) {
    // 1. 处理 rollback：如果是用户回合，减少计数；否则跳过
    if *pending_rollback_turns > 0 {
        if active_segment.counts_as_user_turn {
            *pending_rollback_turns -= 1;
        }
        return;
    }
    
    // 2. 记录最新的 replacement_history 基线
    if base_replacement_history.is_none() 
        && let Some(segment_base) = active_segment.base_replacement_history {
        *base_replacement_history = Some(segment_base);
    }
    
    // 3. 记录最新的用户回合设置
    if previous_turn_settings.is_none() && active_segment.counts_as_user_turn {
        *previous_turn_settings = active_segment.previous_turn_settings;
    }
    
    // 4. 记录最新的参考上下文
    if matches!(reference_context_item, TurnReferenceContextItem::NeverSet)
        && (active_segment.counts_as_user_turn 
            || matches!(active_segment.reference_context_item, TurnReferenceContextItem::Cleared)) {
        *reference_context_item = active_segment.reference_context_item;
    }
}
```

#### 正向重建阶段

```rust
let mut history = ContextManager::new();
if let Some(base) = base_replacement_history {
    history.replace(base.to_vec());
}

for item in rollout_suffix {
    match item {
        RolloutItem::ResponseItem(response_item) => {
            history.record_items(std::iter::once(response_item), truncation_policy);
        }
        RolloutItem::Compacted(compacted) => {
            if let Some(replacement) = &compacted.replacement_history {
                history.replace(replacement.clone());
            } else {
                // 遗留 compaction 处理：重建历史
                let user_messages = collect_user_messages(history.raw_items());
                let rebuilt = compact::build_compacted_history(Vec::new(), &user_messages, &compacted.message);
                history.replace(rebuilt);
            }
        }
        RolloutItem::EventMsg(EventMsg::ThreadRolledBack(rollback)) => {
            history.drop_last_n_user_turns(rollback.num_turns);
        }
        // ... 其他类型忽略
    }
}
```

### Turn ID 兼容性检查

```rust
fn turn_ids_are_compatible(active_turn_id: Option<&str>, item_turn_id: Option<&str>) -> bool {
    active_turn_id.is_none_or(|turn_id| 
        item_turn_id.is_none_or(|item_turn_id| item_turn_id == turn_id)
    )
}
```

该函数确保：
- 如果活跃段没有 turn_id，接受任何 item
- 如果 item 没有 turn_id，也接受（兼容旧数据）
- 否则要求 turn_id 匹配

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/core/src/codex/rollout_reconstruction.rs` (297 行)

### 直接依赖

| 文件 | 用途 |
|------|------|
| `codex-rs/core/src/codex.rs` | 主模块，定义 `Session` 和 `PreviousTurnSettings`，调用重建逻辑 |
| `codex-rs/core/src/context_manager/history.rs` | `ContextManager` 实现，提供历史管理 API |
| `codex-rs/core/src/compact.rs` | `build_compacted_history` 和 `collect_user_messages` |
| `codex-rs/protocol/src/protocol.rs` | `RolloutItem`, `TurnContextItem`, `CompactedItem`, `EventMsg` 等协议类型 |

### 调用关系

```
codex-rs/core/src/codex.rs
    Session::record_initial_history()
        -> Session::apply_rollout_reconstruction()
            -> Session::reconstruct_history_from_rollout() [本文件实现]
                -> finalize_active_segment() [本文件]
                -> ContextManager::replace()
                -> ContextManager::record_items()
                -> ContextManager::drop_last_n_user_turns()
                -> compact::build_compacted_history() [compact.rs]
```

## 依赖与外部交互

### 协议层依赖

```rust
use codex_protocol::protocol::{
    RolloutItem, TurnContextItem, CompactedItem, EventMsg, 
    ThreadRolledBackEvent, TurnStartedEvent, TurnCompleteEvent, 
    TurnAbortedEvent, UserMessageEvent
};
use codex_protocol::models::ResponseItem;
```

### 核心模块依赖

```rust
use crate::codex::{Session, PreviousTurnSettings, TurnContext};
use crate::context_manager::ContextManager;
use crate::compact::{self, collect_user_messages};
```

### 数据流

1. **输入**：`&[RolloutItem]` - 从 rollout 文件解析的事件序列
2. **处理**：反向扫描 + 正向重建
3. **输出**：`RolloutReconstruction` - 包含重建的历史和元数据
4. **副作用**：更新 `Session` 的状态（通过 `apply_rollout_reconstruction`）

## 风险、边界与改进建议

### 已知风险

1. **遗留 Compaction 处理**
   - 代码中明确提到 legacy rollouts 没有 `replacement_history` 的情况
   - 当前处理方式是清除 `reference_context_item` 并接受临时的 out-of-distribution prompt shape
   - **风险**：可能导致恢复后的首回合提示词结构异常

2. **Turn ID 不匹配**
   - 旧数据可能没有 turn_id，依赖 `turn_ids_are_compatible` 的宽松匹配
   - **风险**：极端情况下可能导致元数据关联到错误的回合

3. **Rollback 计数溢出**
   - 使用 `saturating_add` 和 `usize::MAX` 处理 `num_turns` 转换
   - **风险**：如果 rollback 数量异常大，可能无法正确处理

### 边界情况

| 场景 | 处理逻辑 |
|------|----------|
| 空 rollout | 返回空历史和 None 元数据 |
| 只有 Compacted 无历史 | 使用 replacement_history 作为基线 |
| Rollback 超过用户回合数 | 清空所有历史 |
| 非用户回合（如工具调用）被 rollback | 不计入 rollback 计数 |
| TurnContext 无对应 UserMessage | 不视为用户回合，不用于 hydrate settings |
| 未完成的回合（无 TurnComplete） | 根据是否包含 UserMessage 决定是否计入 |

### 改进建议

1. **移除遗留 Compaction 支持**
   - 代码中有 TODO 注释：`TODO(ccunningham): if we drop support for None replacement_history compaction items, we can get rid of this second loop entirely`
   - 移除后可简化正向重建阶段，完全在反向扫描阶段构建历史

2. **延迟加载优化**
   - 当前注释提到："The eventual lazy design should keep this same replay shape, but drive it from a resumable reverse source instead of an eagerly loaded `&[RolloutItem]`"
   - 建议实现真正的懒加载，避免一次性加载所有 rollout items

3. **增强错误处理**
   - 当前对 legacy compaction 的处理是静默的
   - 建议添加警告日志，帮助用户理解为什么参考上下文被清除

4. **测试覆盖**
   - 已有全面的测试覆盖在 `rollout_reconstruction_tests.rs`
   - 建议添加性能测试，特别是处理大型 rollout 文件的场景

### 代码质量

- **优点**：
  - 清晰的阶段分离（反向扫描 vs 正向重建）
  - 详尽的注释解释设计决策
  - 使用状态机模式处理 `TurnReferenceContextItem`
  
- **可改进**：
  - `finalize_active_segment` 函数参数较多，可考虑封装为结构体
  - 部分逻辑（如 legacy compaction 处理）与 `compact.rs` 耦合较紧
