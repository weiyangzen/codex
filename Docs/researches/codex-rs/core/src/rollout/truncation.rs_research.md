# 研究文档：codex-rs/core/src/rollout/truncation.rs

## 场景与职责

`truncation.rs` 是 Codex rollout 系统的截断工具模块，负责基于"用户回合"（user turn）边界对 rollout 历史进行截断。该模块在以下场景发挥关键作用：

1. **上下文窗口管理** - 当会话历史过长时，需要截断早期内容以适配模型上下文限制
2. **历史回溯/撤销** - 支持回退到特定用户回合之前的状态
3. **会话恢复优化** - 加载历史时可能需要忽略某些早期用户回合

该模块的核心职责是识别 rollout 中的用户消息边界，并提供基于这些边界的截断操作。

## 功能点目的

### 1. 用户消息位置识别 (`user_message_positions_in_rollout`)

扫描 rollout 项目列表，识别所有用户消息的位置索引。这是后续截断操作的基础。

**关键特性**：
- 识别 `ResponseItem::Message` 中角色为 `"user"` 的项
- 通过 `event_mapping::parse_turn_item` 解析验证
- 处理 `ThreadRolledBack` 标记，调整有效历史

### 2. 基于用户回合的截断 (`truncate_rollout_before_nth_user_message_from_start`)

提供从起始位置截断 rollout 的功能，保留前 N 个用户回合之前的所有内容。

**边界处理**：
- `n_from_start = usize::MAX`：返回完整 rollout（无截断）
- `n_from_start >= 用户消息数量`：返回空向量（超出范围）
- 正常情况：截断到第 N 个用户消息之前（不包含第 N 个消息）

## 具体技术实现

### 核心算法

#### 用户消息位置识别

```rust
pub(crate) fn user_message_positions_in_rollout(items: &[RolloutItem]) -> Vec<usize> {
    let mut user_positions = Vec::new();
    for (idx, item) in items.iter().enumerate() {
        match item {
            // 识别用户消息
            RolloutItem::ResponseItem(item @ ResponseItem::Message { .. })
                if matches!(
                    event_mapping::parse_turn_item(item),
                    Some(TurnItem::UserMessage(_))
                ) =>
            {
                user_positions.push(idx);
            }
            // 处理回滚标记
            RolloutItem::EventMsg(EventMsg::ThreadRolledBack(rollback)) => {
                let num_turns = usize::try_from(rollback.num_turns).unwrap_or(usize::MAX);
                let new_len = user_positions.len().saturating_sub(num_turns);
                user_positions.truncate(new_len);
            }
            _ => {}
        }
    }
    user_positions
}
```

**算法复杂度**：
- 时间复杂度：O(n)，单次遍历
- 空间复杂度：O(k)，k 为用户消息数量

#### 截断实现

```rust
pub(crate) fn truncate_rollout_before_nth_user_message_from_start(
    items: &[RolloutItem],
    n_from_start: usize,
) -> Vec<RolloutItem> {
    // 特殊情况：usize::MAX 表示无截断
    if n_from_start == usize::MAX {
        return items.to_vec();
    }

    let user_positions = user_message_positions_in_rollout(items);

    // 边界：用户消息不足
    if user_positions.len() <= n_from_start {
        return Vec::new();
    }

    // 截断到第 N 个用户消息之前
    let cut_idx = user_positions[n_from_start];
    items[..cut_idx].to_vec()
}
```

### 数据结构依赖

```rust
// 来自 codex_protocol
codex_protocol::protocol::RolloutItem  // Rollout 项目枚举
codex_protocol::protocol::EventMsg     // 事件消息枚举
codex_protocol::models::ResponseItem   // 响应项目枚举
codex_protocol::items::TurnItem        // 回合项目枚举

// 内部依赖
crate::event_mapping::parse_turn_item  // 解析回合项目
```

### RolloutItem 枚举定义

```rust
pub enum RolloutItem {
    SessionMeta(SessionMetaLine),
    ResponseItem(ResponseItem),
    Compacted(CompactedItem),
    TurnContext(TurnContextItem),
    EventMsg(EventMsg),
}
```

### ThreadRolledBack 事件处理

```rust
pub struct ThreadRolledBackEvent {
    /// Number of user turns that were removed from context.
    pub num_turns: u32,
}
```

当遇到 `ThreadRolledBack` 事件时，从 `user_positions` 尾部移除指定数量的用户消息位置。这确保了截断操作基于"有效历史"而非原始 rollout 流。

## 关键代码路径与文件引用

### 本模块导出

| 函数 | 行号 | 可见性 | 用途 |
|------|------|--------|------|
| `user_message_positions_in_rollout` | 20 | `pub(crate)` | 识别用户消息位置 |
| `truncate_rollout_before_nth_user_message_from_start` | 51 | `pub(crate)` | 截断 rollout |

### 依赖模块

| 模块/函数 | 路径 | 用途 |
|-----------|------|------|
| `event_mapping` | `core/src/event_mapping.rs` | 解析 ResponseItem 为 TurnItem |
| `parse_turn_item` | `event_mapping.rs:94` | 将响应项解析为回合项 |

### 测试模块

| 测试文件 | 路径 |
|----------|------|
| `truncation_tests.rs` | `core/src/rollout/truncation_tests.rs` |

## 依赖与外部交互

### 外部 Crate

```rust
use codex_protocol::items::TurnItem;
use codex_protocol::models::ResponseItem;
use codex_protocol::protocol::{EventMsg, RolloutItem};
```

### 内部模块

```rust
use crate::event_mapping;
```

### 调用关系图

```
truncation.rs
    ├─> event_mapping::parse_turn_item(ResponseItem) -> Option<TurnItem>
    │
    └─> [被调用方]
         ├─> codex.rs (会话恢复/重建)
         ├─> compact.rs (历史压缩)
         └─> 其他需要历史截断的模块
```

## 风险、边界与改进建议

### 潜在风险

1. **回滚标记处理顺序**：`ThreadRolledBack` 标记的处理依赖于其在 rollout 中的出现顺序。如果标记位置与预期不符，可能导致错误的用户位置计算。

2. **整数溢出**：`num_turns` 从 `u32` 转换为 `usize` 时使用了 `unwrap_or(usize::MAX)`，在极端情况下可能导致意外行为。

3. **内存分配**：`items.to_vec()` 在 `usize::MAX` 情况下会克隆整个向量，对于大型 rollout 可能有性能影响。

### 边界情况

| 场景 | 行为 |
|------|------|
| `n_from_start = 0` | 返回第一个用户消息之前的所有内容 |
| `n_from_start = 1` | 返回前 1 个用户消息及其后续到第 2 个用户消息之前的内容 |
| `n_from_start >= 用户消息数` | 返回空向量 |
| `n_from_start = usize::MAX` | 返回完整 rollout（无截断） |
| 空 rollout | 返回空向量 |
| 无用户消息 | 返回空向量（除非 `n_from_start = usize::MAX`） |

### 改进建议

1. **性能优化**：
   - 考虑使用迭代器而非克隆整个向量，减少内存分配
   - 对于大型 rollout，可考虑惰性求值或流式处理

2. **API 增强**：
   - 添加从末尾截断的功能（`truncate_rollout_after_nth_user_message_from_end`）
   - 支持保留特定数量的助手消息
   - 添加基于 token 数量的智能截断（与上下文窗口管理集成）

3. **错误处理**：
   - 考虑使用 `Result` 替代空向量返回，提供更明确的错误信息
   - 添加日志记录截断操作（便于调试）

4. **测试覆盖**：
   - 添加边界测试：空 rollout、单用户消息、连续回滚标记
   - 添加性能测试：大型 rollout（10万+ 项目）的截断性能
   - 添加模糊测试：随机 rollout 结构的有效性验证

5. **文档完善**：
   - 添加更多使用示例
   - 明确说明回滚标记的处理语义
   - 解释与上下文窗口管理的关系
