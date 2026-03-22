# Thread History 模块研究文档

## 文件位置
`codex-rs/app-server-protocol/src/protocol/thread_history.rs`

---

## 1. 场景与职责

### 1.1 核心定位
`thread_history.rs` 是 Codex App-Server Protocol 的核心历史记录转换模块，负责将底层的 `RolloutItem` 事件流转换为高层 API 可用的 `Turn`（回合）数据结构。它是连接底层协议事件与上层应用历史视图的关键桥梁。

### 1.2 主要使用场景

| 场景 | 说明 |
|------|------|
| **Thread Resume** | 当客户端恢复一个已有线程时，将持久化的 rollout 文件解析为 `Vec<Turn>` |
| **Thread Fork** | 分叉线程时需要重建历史记录 |
| **Thread Read** | 读取线程历史时提供结构化的回合数据 |
| **实时事件累积** | `ThreadState` 使用 `ThreadHistoryBuilder` 累积当前回合的事件 |
| **Rollback 处理** | 处理线程回滚事件，调整历史记录 |

### 1.3 职责边界
- **输入**: `RolloutItem` 列表（来自 rollout 文件或实时事件流）
- **输出**: `Vec<Turn>`（结构化历史记录）
- **不处理**: 原始 SSE 事件、文件系统 I/O、网络传输

---

## 2. 功能点目的

### 2.1 核心功能

#### 2.1.1 事件到回合的聚合 (`build_turns_from_rollout_items`)
```rust
pub fn build_turns_from_rollout_items(items: &[RolloutItem]) -> Vec<Turn>
```
将扁平的 rollout 事件列表聚合成回合结构，维护回合边界和状态。

#### 2.1.2 回合边界管理
- **TurnStarted**: 显式开启新回合，标记 `opened_explicitly = true`
- **TurnComplete**: 完成当前回合，标记状态为 `Completed`
- **TurnAborted**: 中断回合，标记状态为 `Interrupted`
- **UserMessage**: 隐式开启新回合（向后兼容）

#### 2.1.3 工具调用生命周期追踪
支持多种工具调用的 Begin/End 事件配对：
- WebSearch (Begin/End)
- ExecCommand (Begin/End)
- PatchApply (Begin/End/ApprovalRequest)
- McpToolCall (Begin/End)
- DynamicToolCall (Request/Response)
- CollabAgent (Spawn/Interaction/Wait/Close/Resume Begin/End)

#### 2.1.4 延迟事件处理
处理可能乱序到达的事件，特别是 `ExecCommandEnd` 可能在回合结束后才到达的情况。通过 `turn_id` 路由到正确的回合。

### 2.2 状态管理

| 状态 | 说明 |
|------|------|
| `Completed` | 回合正常完成 |
| `InProgress` | 回合进行中（有显式 TurnStarted） |
| `Interrupted` | 回合被中断（TurnAborted） |
| `Failed` | 回合失败（Error 事件影响） |

---

## 3. 具体技术实现

### 3.1 核心数据结构

#### 3.1.1 ThreadHistoryBuilder
```rust
pub struct ThreadHistoryBuilder {
    turns: Vec<Turn>,           // 已完成的回合
    current_turn: Option<PendingTurn>,  // 当前进行中的回合
    next_item_index: i64,       // 自增 item ID 生成器
}
```

#### 3.1.2 PendingTurn（内部状态）
```rust
struct PendingTurn {
    id: String,
    items: Vec<ThreadItem>,
    error: Option<TurnError>,
    status: TurnStatus,
    opened_explicitly: bool,    // 是否显式开启
    saw_compaction: bool,       // 是否包含压缩标记
}
```

#### 3.1.3 Turn（输出结构，定义在 v2.rs）
```rust
pub struct Turn {
    pub id: String,
    pub items: Vec<ThreadItem>,
    pub status: TurnStatus,
    pub error: Option<TurnError>,
}
```

### 3.2 事件处理流程

```
RolloutItem::EventMsg(event)
    ↓
handle_event(event)
    ↓
match event {
    UserMessage → handle_user_message()
    AgentMessage → handle_agent_message()
    ExecCommandBegin/End → handle_exec_command_xxx()
    PatchApplyBegin/End → handle_patch_apply_xxx()
    TurnStarted → handle_turn_started()
    TurnComplete → handle_turn_complete()
    TurnAborted → handle_turn_aborted()
    ThreadRolledBack → handle_thread_rollback()
    ...
}
    ↓
upsert_item_in_turn_id() / upsert_item_in_current_turn()
    ↓
upsert_turn_item()  // 更新或追加 item
```

### 3.3 关键算法

#### 3.3.1 Item ID 生成
```rust
fn next_item_id(&mut self) -> String {
    let id = format!("item-{}", self.next_item_index);
    self.next_item_index += 1;
    id
}
```
使用简单的自增整数生成唯一 ID（如 `item-1`, `item-2`...）。

#### 3.3.2 Upsert 逻辑
```rust
fn upsert_turn_item(items: &mut Vec<ThreadItem>, item: ThreadItem) {
    if let Some(existing) = items.iter_mut().find(|e| e.id() == item.id()) {
        *existing = item;  // 更新已存在的 item
    } else {
        items.push(item);  // 追加新 item
    }
}
```
通过 `call_id` 匹配，支持工具调用的 Begin/End 配对更新。

#### 3.3.3 回合回滚
```rust
fn handle_thread_rollback(&mut self, payload: &ThreadRolledBackEvent) {
    self.finish_current_turn();
    let n = usize::try_from(payload.num_turns).unwrap_or(usize::MAX);
    if n >= self.turns.len() {
        self.turns.clear();
    } else {
        self.turns.truncate(self.turns.len().saturating_sub(n));
    }
    // 重新计算 next_item_index
    let item_count: usize = self.turns.iter().map(|t| t.items.len()).sum();
    self.next_item_index = i64::try_from(item_count.saturating_add(1)).unwrap_or(i64::MAX);
}
```

### 3.4 支持的 ThreadItem 类型

| 类型 | 来源事件 | 说明 |
|------|----------|------|
| `UserMessage` | UserMessageEvent | 用户输入（支持文本、图片、本地图片） |
| `AgentMessage` | AgentMessageEvent | AI 回复消息 |
| `Reasoning` | AgentReasoningEvent + AgentReasoningRawContentEvent | 推理过程 |
| `Plan` | ItemStarted/ItemCompleted (TurnItem::Plan) | 计划项 |
| `CommandExecution` | ExecCommandBegin + ExecCommandEnd | 命令执行 |
| `FileChange` | PatchApplyBegin/End, ApplyPatchApprovalRequest | 文件变更 |
| `McpToolCall` | McpToolCallBegin + McpToolCallEnd | MCP 工具调用 |
| `DynamicToolCall` | DynamicToolCallRequest + DynamicToolCallResponse | 动态工具调用 |
| `CollabAgentToolCall` | CollabAgentSpawn/Interaction/Wait/Close/Resume Begin/End | 协作代理工具 |
| `WebSearch` | WebSearchBegin + WebSearchEnd | 网页搜索 |
| `ImageView` | ViewImageToolCallEvent | 图片查看 |
| `ImageGeneration` | ImageGenerationBegin + ImageGenerationEnd | 图片生成 |
| `EnteredReviewMode` | EnteredReviewMode | 进入审核模式 |
| `ExitedReviewMode` | ExitedReviewMode | 退出审核模式 |
| `ContextCompaction` | ContextCompactedEvent | 上下文压缩 |

---

## 4. 关键代码路径与文件引用

### 4.1 模块内部结构

```
thread_history.rs
├── 公开 API
│   ├── build_turns_from_rollout_items()
│   └── ThreadHistoryBuilder
│       ├── new()
│       ├── reset()
│       ├── finish()
│       ├── handle_event()
│       ├── handle_rollout_item()
│       ├── active_turn_snapshot()
│       └── has_active_turn()
├── 私有事件处理器 (handle_*)
├── 工具函数 (convert_*, map_*, format_*)
├── PendingTurn 内部结构
└── 测试模块 (#[cfg(test)])
```

### 4.2 调用方（Caller）

| 文件 | 调用点 | 用途 |
|------|--------|------|
| `app-server/src/codex_message_processor.rs:175` | `use codex_app_server_protocol::build_turns_from_rollout_items;` | 导入函数 |
| `app-server/src/codex_message_processor.rs:3278` | `thread.turns = build_turns_from_rollout_items(&items);` | Thread Read 响应 |
| `app-server/src/codex_message_processor.rs:7336` | `.map(|items| build_turns_from_rollout_items(&items))` | Thread Resume 历史加载 |
| `app-server/src/codex_message_processor.rs:7345` | `ThreadTurnSource::HistoryItems(items) => build_turns_from_rollout_items(items)` | 从历史项加载 |
| `app-server/src/bespoke_event_handling.rs:103` | `use codex_app_server_protocol::build_turns_from_rollout_items;` | 导入函数 |
| `app-server/src/bespoke_event_handling.rs:1753` | `thread.turns = build_turns_from_rollout_items(&items);` | 自定义事件处理 |
| `app-server/src/thread_state.rs:4` | `use codex_app_server_protocol::ThreadHistoryBuilder;` | 导入结构体 |
| `app-server/src/thread_state.rs:61` | `current_turn_history: ThreadHistoryBuilder` | 实时回合累积 |
| `app-server/src/thread_state.rs:107-115` | `active_turn_snapshot()`, `track_current_turn_event()` | 状态追踪 |

### 4.3 被调用方/依赖（Callee）

| 文件 | 依赖项 | 用途 |
|------|--------|------|
| `protocol/src/protocol.rs:2418` | `RolloutItem` | 输入数据结构 |
| `protocol/src/protocol.rs` | `EventMsg` 及所有子类型 | 事件处理 |
| `app-server-protocol/src/protocol/v2.rs` | `Turn`, `ThreadItem`, `TurnStatus`, `TurnError` | 输出数据结构 |
| `app-server-protocol/src/protocol/v2.rs` | `UserInput`, `CommandAction`, `WebSearchAction` | 嵌套类型 |
| `app-server-protocol/src/protocol/v2.rs` | `PatchApplyStatus`, `CommandExecutionStatus`, `McpToolCallStatus`, `DynamicToolCallStatus`, `CollabAgentToolCallStatus` | 状态枚举 |

### 4.4 模块导出

```rust
// lib.rs 第17行
pub use protocol::thread_history::*;
```

所有公开 API 通过 `codex_app_server_protocol` crate 的根模块导出。

---

## 5. 依赖与外部交互

### 5.1 直接依赖

```rust
// 内部模块
use crate::protocol::v2::*;  // Turn, ThreadItem, 各种状态枚举

// 外部 crate
codex_protocol::protocol::*  // EventMsg, RolloutItem, 各种事件类型
codex_protocol::items::*     // TurnItem (CoreTurnItem)
codex_protocol::models::*    // MessagePhase, WebSearchAction
std::collections::HashMap
uuid::Uuid                   // Turn ID 生成
tracing::warn                // 日志
shlex                        // 命令行拼接
```

### 5.2 协议版本依赖

| 协议组件 | 来源 | 说明 |
|----------|------|------|
| `RolloutItem` | `codex_protocol` (core) | 底层持久化格式 |
| `EventMsg` | `codex_protocol` (core) | 事件消息枚举 |
| `Turn` | `v2.rs` | API v2 输出格式 |
| `ThreadItem` | `v2.rs` | API v2 项目类型 |

### 5.3 与 Core Protocol 的映射关系

```
codex_protocol (core)          app-server-protocol (v2)
─────────────────────────────────────────────────────────
RolloutItem::EventMsg          → handle_event()
RolloutItem::Compacted         → handle_compacted()
EventMsg::UserMessage          → ThreadItem::UserMessage
EventMsg::AgentMessage         → ThreadItem::AgentMessage
EventMsg::ExecCommandBegin/End → ThreadItem::CommandExecution
EventMsg::PatchApplyBegin/End  → ThreadItem::FileChange
...                            → ...
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 事件乱序处理
**风险**: `ExecCommandEnd` 可能在 `TurnComplete` 之后到达，如果回合已关闭，事件会被丢弃或错误路由。

**当前处理**:
```rust
// 通过 turn_id 路由到已完成的回合
fn upsert_item_in_turn_id(&mut self, turn_id: &str, item: ThreadItem) {
    // 先尝试当前回合
    if let Some(turn) = self.current_turn.as_mut() && turn.id == turn_id { ... }
    // 再尝试已完成的回合
    if let Some(turn) = self.turns.iter_mut().find(|turn| turn.id == turn_id) { ... }
    // 找不到则警告丢弃
    warn!(...)
}
```

**边界**: 如果 `turn_id` 不匹配任何回合，事件会被丢弃。

#### 6.1.2 回合空内容优化
```rust
fn finish_current_turn(&mut self) {
    if let Some(turn) = self.current_turn.take() {
        if turn.items.is_empty() && !turn.opened_explicitly && !turn.saw_compaction {
            return;  // 丢弃空回合
        }
        self.turns.push(turn.into());
    }
}
```
- 隐式开启的空回合会被丢弃
- 显式开启或包含压缩标记的回合会被保留

#### 6.1.3 ID 冲突风险
使用简单的自增整数生成 item ID，在 rollback 后会重新计算 `next_item_index`，但如果有并发或重复处理可能导致 ID 重复。

### 6.2 测试覆盖

模块包含 **39 个单元测试**，覆盖：
- 基本回合构建
- 推理项聚合（summary + content）
- 回合中断（TurnAborted）
- 线程回滚（ThreadRollback）
- 显式回合边界（TurnStarted/TurnComplete）
- 工具调用重建（WebSearch, ExecCommand, McpToolCall, DynamicToolCall）
- 延迟事件路由（late ExecCommandEnd）
- 压缩标记回合保留
- 协作代理工具（CollabAgent）
- 错误状态处理

### 6.3 改进建议

#### 6.3.1 性能优化
- **现状**: 每次 `upsert_item_in_turn_id` 都线性搜索 `turns` Vec
- **建议**: 对于高频场景，考虑使用 `HashMap<String, usize>` 缓存 turn_id 到索引的映射

#### 6.3.2 错误处理增强
- **现状**: 未知 turn_id 的事件仅记录 warning 后丢弃
- **建议**: 考虑添加 metrics 或结构化日志，便于监控事件丢失情况

#### 6.3.3 类型安全
- **现状**: `turn_id` 使用 `String`，运行时验证
- **建议**: 考虑使用 newtype 模式（如 `TurnId(String)`）增强类型安全

#### 6.3.4 文档完善
- **现状**: 部分复杂逻辑（如 reasoning 的 summary/content 合并）缺乏文档说明
- **建议**: 添加更多内联文档解释设计决策

#### 6.3.5 向后兼容性
- **现状**: 处理 `UserMessage` 时有专门的向后兼容逻辑
- **建议**: 定期审查并清理遗留兼容代码，添加版本标记

### 6.4 监控建议

| 指标 | 说明 |
|------|------|
| `thread_history.turns_created` | 创建的回合数 |
| `thread_history.items_upserted` | 更新/插入的 item 数 |
| `thread_history.events_dropped` | 因未知 turn_id 丢弃的事件数 |
| `thread_history.rollbacks` | 回滚操作次数 |
| `thread_history.build_duration_ms` | 构建历史耗时 |

---

## 7. 总结

`thread_history.rs` 是 Codex App-Server 中承上启下的关键模块，负责将底层的持久化事件流转换为高层 API 友好的回合结构。其设计充分考虑了：

1. **事件乱序处理**: 通过 `turn_id` 路由支持延迟事件
2. **向后兼容**: 支持隐式和显式回合边界
3. **工具生命周期**: 完整的 Begin/End 配对追踪
4. **状态完整性**: 回合状态（Completed/Interrupted/Failed/InProgress）准确维护

该模块的稳定性直接影响 Thread Resume、Fork、Read 等核心功能的用户体验。
