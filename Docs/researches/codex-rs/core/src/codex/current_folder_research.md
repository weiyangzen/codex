# DIR codex-rs/core/src/codex 研究文档

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

`codex-rs/core/src/codex` 目录是 Codex 核心系统的**会话历史重建模块**，专门负责处理对话会话的恢复（Resume）和分支（Fork）场景中的历史记录重建工作。

### 核心职责

1. **Rollout 历史重建**：从持久化的 rollout 文件（JSONL 格式）中重建对话历史，支持会话恢复和分支创建
2. **Compaction 处理**：处理历史记录的压缩（compaction）事件，管理压缩后的历史替换逻辑
3. **Rollback 支持**：处理线程回滚（ThreadRolledBack）事件，正确裁剪历史记录
4. **上下文恢复**：恢复 TurnContextItem，确保会话恢复后模型可见的上下文状态正确

### 在系统中的位置

```
┌─────────────────────────────────────────────────────────────┐
│                     Codex Session                           │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │   Codex      │  │   Session    │  │  RolloutRecorder │  │
│  │   (主入口)    │  │   (状态管理)  │  │  (持久化)        │  │
│  └──────┬───────┘  └──────┬───────┘  └────────┬─────────┘  │
│         │                 │                    │            │
│         └─────────────────┼────────────────────┘            │
│                           │                                 │
│              ┌────────────▼────────────┐                   │
│              │   codex/rollout_        │                   │
│              │   reconstruction.rs     │                   │
│              │   (历史重建核心)         │                   │
│              └─────────────────────────┘                   │
└─────────────────────────────────────────────────────────────┘
```

---

## 功能点目的

### 1. RolloutReconstruction - 历史重建结果

**文件**: `rollout_reconstruction.rs` (第 5-10 行)

```rust
#[derive(Debug)]
pub(super) struct RolloutReconstruction {
    pub(super) history: Vec<ResponseItem>,
    pub(super) previous_turn_settings: Option<PreviousTurnSettings>,
    pub(super) reference_context_item: Option<TurnContextItem>,
}
```

**目的**：封装从 rollout 重建后的完整历史状态，包括：
- `history`: 重建后的对话历史记录
- `previous_turn_settings`: 上一回合的设置（模型、realtime 状态等）
- `reference_context_item`: 参考上下文项，用于后续回合的上下文差异计算

### 2. TurnReferenceContextItem - 上下文引用状态

**文件**: `rollout_reconstruction.rs` (第 12-26 行)

```rust
#[derive(Debug, Default)]
enum TurnReferenceContextItem {
    #[default]
    NeverSet,      // 从未设置过基线
    Cleared,       // 曾被设置但已被 compaction 清除
    Latest(Box<TurnContextItem>),  // 最新的有效基线
}
```

**目的**：跟踪 TurnContextItem 的生命周期状态，区分"从未设置"和"被清除"两种语义，确保 resume/fork 时能正确恢复上下文。

### 3. ActiveReplaySegment - 活跃回放段

**文件**: `rollout_reconstruction.rs` (第 28-35 行)

```rust
#[derive(Debug, Default)]
struct ActiveReplaySegment<'a> {
    turn_id: Option<String>,
    counts_as_user_turn: bool,
    previous_turn_settings: Option<PreviousTurnSettings>,
    reference_context_item: TurnReferenceContextItem,
    base_replacement_history: Option<&'a [ResponseItem]>,
}
```

**目的**：在反向扫描 rollout 项目时，累积单个回合（turn）的元数据，支持 rollback 和 compaction 的正确处理。

### 4. reconstruct_history_from_rollout - 核心重建方法

**文件**: `rollout_reconstruction.rs` (第 85-297 行)

**目的**：实现完整的 rollout 历史重建算法，包括：
- 反向扫描 rollout 项目以找到最新的有效基线
- 处理 ThreadRolledBack 事件（回滚 N 个用户回合）
- 处理 Compacted 事件（压缩后的历史替换）
- 正向重建最终的历史记录

---

## 具体技术实现

### 1. 双向扫描算法

历史重建采用**双向扫描**策略：

#### 第一阶段：反向扫描（Reverse Scan）

```rust
// rollout_reconstruction.rs 第 109-218 行
for (index, item) in rollout_items.iter().enumerate().rev() {
    match item {
        RolloutItem::Compacted(compacted) => { /* ... */ }
        RolloutItem::EventMsg(EventMsg::ThreadRolledBack(rollback)) => {
            pending_rollback_turns += rollback.num_turns;
        }
        // ... 其他事件处理
    }
    
    // 提前终止条件：找到所有必要元数据
    if base_replacement_history.is_some()
        && previous_turn_settings.is_some()
        && !matches!(reference_context_item, TurnReferenceContextItem::NeverSet)
    {
        break;
    }
}
```

**关键逻辑**：
- 从最新项目向最旧项目扫描
- 累积 `pending_rollback_turns` 以处理回滚
- 找到最新的 `base_replacement_history`（压缩后的历史基线）
- 找到最新的 `previous_turn_settings` 和 `reference_context_item`

#### 第二阶段：正向重建（Forward Reconstruction）

```rust
// rollout_reconstruction.rs 第 238-277 行
for item in rollout_suffix {
    match item {
        RolloutItem::ResponseItem(response_item) => {
            history.record_items(/* ... */);
        }
        RolloutItem::Compacted(compacted) => {
            if let Some(replacement_history) = &compacted.replacement_history {
                history.replace(replacement_history.clone());
            } else {
                // 处理 legacy compaction（无 replacement_history）
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

### 2. Rollback 处理机制

**文件**: `rollout_reconstruction.rs` (第 42-83 行)

```rust
fn finalize_active_segment(
    active_segment: ActiveReplaySegment<'a>,
    base_replacement_history: &mut Option<&'a [ResponseItem]>,
    previous_turn_settings: &mut Option<PreviousTurnSettings>,
    reference_context_item: &mut TurnReferenceContextItem,
    pending_rollback_turns: &mut usize,
) {
    // 如果存在待处理的回滚，跳过用户回合
    if *pending_rollback_turns > 0 {
        if active_segment.counts_as_user_turn {
            *pending_rollback_turns -= 1;
        }
        return;  // 该段被回滚跳过
    }
    // ... 正常处理
}
```

**语义**：`ThreadRolledBack { num_turns: N }` 表示丢弃最新的 N 个用户回合。反向扫描时，跳过接下来的 N 个包含 `UserMessage` 的段。

### 3. Compaction 处理

**Legacy vs Modern Compaction**:

```rust
// rollout_reconstruction.rs 第 246-268 行
RolloutItem::Compacted(compacted) => {
    if let Some(replacement_history) = &compacted.replacement_history {
        // Modern: 直接使用替换历史
        history.replace(replacement_history.clone());
    } else {
        // Legacy: 需要重建历史
        saw_legacy_compaction_without_replacement_history = true;
        let user_messages = collect_user_messages(history.raw_items());
        let rebuilt = compact::build_compacted_history(
            Vec::new(),
            &user_messages,
            &compacted.message,
        );
        history.replace(rebuilt);
    }
}
```

**关键区别**：
- **Modern compaction**: `replacement_history` 字段包含完整的替换历史
- **Legacy compaction**: 仅包含摘要消息，需要调用 `build_compacted_history` 重建

### 4. Turn ID 兼容性检查

```rust
// rollout_reconstruction.rs 第 37-40 行
fn turn_ids_are_compatible(active_turn_id: Option<&str>, item_turn_id: Option<&str>) -> bool {
    active_turn_id
        .is_none_or(|turn_id| item_turn_id.is_none_or(|item_turn_id| item_turn_id == turn_id))
}
```

**目的**：处理 TurnContextItem 可能缺失 `turn_id` 的情况（旧版本 rollout），确保兼容性。

---

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 | 关键行号 |
|------|------|----------|
| `rollout_reconstruction.rs` | 历史重建核心实现 | 1-297 |
| `rollout_reconstruction_tests.rs` | 单元测试 | 1-1291 |
| `../codex.rs` | Session 主实现，调用重建逻辑 | 2186-2203 |

### 关键数据结构定义（外部）

| 结构/枚举 | 定义位置 | 用途 |
|-----------|----------|------|
| `RolloutItem` | `codex-rs/protocol/src/protocol.rs:2418` | Rollout 项目枚举 |
| `CompactedItem` | `codex-rs/protocol/src/protocol.rs:2427` | 压缩项 |
| `TurnContextItem` | `codex-rs/protocol/src/protocol.rs:2458` | 回合上下文 |
| `ContextManager` | `codex-rs/core/src/context_manager/history.rs:31` | 历史管理器 |

### 调用链

```
Session::record_initial_history()
    └── Session::apply_rollout_reconstruction()
            └── Session::reconstruct_history_from_rollout()  [codex/rollout_reconstruction.rs:86]
                    ├── finalize_active_segment()            [codex/rollout_reconstruction.rs:42]
                    └── ContextManager::replace()            [context_manager/history.rs:172]
```

### 测试覆盖

**文件**: `rollout_reconstruction_tests.rs`

| 测试函数 | 测试场景 | 行号 |
|----------|----------|------|
| `reconstruct_history_rollback_keeps_history_and_metadata_in_sync_for_completed_turns` | 完整回合回滚 | 149-243 |
| `reconstruct_history_rollback_keeps_history_and_metadata_in_sync_for_incomplete_turn` | 不完整回合回滚 | 246-325 |
| `reconstruct_history_rollback_skips_non_user_turns_for_history_and_metadata` | 跳过非用户回合 | 328-431 |
| `reconstruct_history_rollback_clears_history_and_metadata_when_exceeding_user_turns` | 回滚超出范围 | 434-478 |
| `reconstruct_history_legacy_compaction_without_replacement_history_*` | Legacy compaction | 665-735 |

---

## 依赖与外部交互

### 内部依赖

```
codex/
├── rollout_reconstruction.rs
│   ├── super::*  (从 codex.rs 导入)
│   └── 依赖: Session, TurnContext, PreviousTurnSettings
│
└── rollout_reconstruction_tests.rs
    ├── super::*  (测试目标)
    └── 依赖: codex_protocol, core_test_support
```

### 外部模块依赖

| 模块 | 用途 | 关键类型 |
|------|------|----------|
| `context_manager` | 历史记录管理 | `ContextManager` |
| `compact` | Compaction 历史重建 | `build_compacted_history` |
| `rollout/recorder` | Rollout 持久化 | `RolloutRecorder`, `RolloutItem` |
| `protocol` | 协议类型定义 | `TurnContextItem`, `CompactedItem`, `EventMsg` |

### 协议类型（codex-protocol）

```rust
// codex-rs/protocol/src/protocol.rs

pub enum RolloutItem {
    SessionMeta(SessionMetaLine),
    ResponseItem(ResponseItem),
    Compacted(CompactedItem),       // 压缩事件
    TurnContext(TurnContextItem),   // 回合上下文
    EventMsg(EventMsg),             // 各种事件
}

pub struct CompactedItem {
    pub message: String,
    pub replacement_history: Option<Vec<ResponseItem>>,  // 现代压缩包含完整历史
}

pub struct TurnContextItem {
    pub turn_id: Option<String>,
    pub model: String,
    pub approval_policy: AskForApproval,
    pub sandbox_policy: SandboxPolicy,
    // ... 其他上下文字段
}
```

---

## 风险、边界与改进建议

### 已知风险

1. **Legacy Compaction 降级处理**
   - **风险**: 遇到无 `replacement_history` 的 legacy compaction 时，会清除 `reference_context_item`，导致临时性的 out-of-distribution prompt shape
   - **代码**: `rollout_reconstruction.rs` 第 252-267 行
   - **缓解**: 注释说明此类情况罕见，TODO 标记未来可能移除支持

2. **Turn ID 缺失兼容性**
   - **风险**: 旧版本 rollout 可能缺失 `turn_id`，依赖 `turn_ids_are_compatible` 的宽松匹配
   - **代码**: `rollout_reconstruction.rs` 第 37-40 行

3. **Rollback 与 Compaction 交互**
   - **风险**: 回滚到已压缩的回合时，需要正确处理 `replacement_history` 的边界
   - **测试**: `rollout_reconstruction_tests.rs` 第 544-621 行覆盖此场景

### 边界条件

| 边界 | 处理逻辑 |
|------|----------|
| 空 rollout | 返回空历史，无 previous_turn_settings |
| 回滚数 > 用户回合数 | 清空所有历史和元数据 |
| 无 UserMessage 的回合 | 不消耗 rollback 计数 |
| 不完整回合（无 TurnComplete） | 正确处理，不 panic |

### 改进建议

1. **移除 Legacy Compaction 支持**
   ```rust
   // TODO(ccunningham): 第 259-260 行
   // 如果放弃支持 None replacement_history 的 compaction 项，
   // 可以完全移除第二个循环，直接在第一个循环中构建 history
   ```

2. **延迟加载优化**
   - 当前实现使用 eager bridge 加载 rollout
   - 注释提到未来应实现 "lazy reverse loader" 以减少内存占用

3. **测试增强**
   - 当前测试覆盖主要场景，但可添加：
     - 大规模 rollout 性能测试
     - 并发重建测试
     - 损坏 rollout 的容错测试

4. **代码组织**
   - `rollout_reconstruction.rs` 297 行，接近 500 行阈值
   - 若继续增长，建议将 `ActiveReplaySegment` 和 `finalize_active_segment` 移至子模块

---

## 总结

`codex-rs/core/src/codex` 目录虽然只包含两个文件，但承担了 Codex 系统中**会话历史恢复**的关键职责。其核心算法通过双向扫描策略，优雅地处理了 rollback、compaction 等复杂场景，确保了会话恢复和分支创建的正确性。

该模块的设计体现了以下工程实践：
- **防御性编程**：处理 legacy 数据格式和缺失字段
- **清晰的状态机**：`TurnReferenceContextItem` 枚举明确区分状态
- **全面的测试覆盖**：20+ 个测试用例覆盖各种边界场景
