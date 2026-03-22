# policy.rs 研究文档

## 场景与职责

`policy.rs` 是 Codex rollout 模块的持久化策略子模块，位于 `codex-rs/core/src/rollout/policy.rs`。它定义了 rollout 文件中各类事件和响应项的持久化规则，控制哪些数据应该被保存到磁盘。

该模块的核心职责包括：
1. **持久化模式定义**：定义 `Limited` 和 `Extended` 两种持久化模式
2. **响应项过滤**：决定哪些 `ResponseItem` 应该被持久化
3. **事件消息过滤**：根据持久化模式决定哪些 `EventMsg` 应该被保存
4. **记忆提取过滤**：决定哪些响应项应该用于记忆（memories）生成

## 功能点目的

### 1. 持久化模式 `EventPersistenceMode`

**目的**：提供不同级别的数据持久化粒度

```rust
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum EventPersistenceMode {
    #[default]
    Limited,   // 有限持久化：只保存核心事件
    Extended,  // 扩展持久化：保存更多诊断信息
}
```

**使用场景**：
- `Limited`：默认模式，适用于大多数用户场景，平衡存储空间和诊断需求
- `Extended`：调试或审计场景，保存更多执行细节（如命令输出）

### 2. 响应项持久化策略 `should_persist_response_item`

**目的**：决定单个 `ResponseItem` 是否应该被写入 rollout 文件

**持久化白名单**：

| 响应项类型 | 是否持久化 | 说明 |
|-----------|-----------|------|
| `Message` | ✅ | 用户/助手消息 |
| `Reasoning` | ✅ | 推理内容 |
| `LocalShellCall` | ✅ | 本地 shell 调用 |
| `FunctionCall` | ✅ | 函数调用 |
| `ToolSearchCall` | ✅ | 工具搜索调用 |
| `FunctionCallOutput` | ✅ | 函数调用输出 |
| `ToolSearchOutput` | ✅ | 工具搜索输出 |
| `CustomToolCall` | ✅ | 自定义工具调用 |
| `CustomToolCallOutput` | ✅ | 自定义工具输出 |
| `WebSearchCall` | ✅ | 网页搜索调用 |
| `ImageGenerationCall` | ✅ | 图像生成调用 |
| `GhostSnapshot` | ✅ | 幽灵快照 |
| `Compaction` | ✅ | 压缩标记 |
| `Other` | ❌ | 未知类型，不保存 |

### 3. Rollout 项持久化策略 `is_persisted_response_item`

**目的**：在 `RolloutItem` 层面决定持久化行为

**策略逻辑**：
```rust
pub(crate) fn is_persisted_response_item(
    item: &RolloutItem, 
    mode: EventPersistenceMode
) -> bool {
    match item {
        RolloutItem::ResponseItem(item) => should_persist_response_item(item),
        RolloutItem::EventMsg(ev) => should_persist_event_msg(ev, mode),
        // 以下类型总是持久化
        RolloutItem::Compacted(_) | 
        RolloutItem::TurnContext(_) | 
        RolloutItem::SessionMeta(_) => true,
    }
}
```

**说明**：
- `SessionMeta`：会话元数据，必须保存用于恢复
- `TurnContext`：回合上下文，用于状态恢复
- `Compacted`：压缩标记，用于分析流程

### 4. 事件消息持久化策略 `should_persist_event_msg`

**目的**：根据持久化模式决定 `EventMsg` 的保存行为

**Limited 模式保存的事件**：
- `UserMessage` / `AgentMessage` / `AgentReasoning` / `AgentReasoningRawContent`
- `TokenCount` / `ContextCompacted`
- `EnteredReviewMode` / `ExitedReviewMode`
- `ThreadRolledBack` / `UndoCompleted`
- `TurnAborted` / `TurnStarted` / `TurnComplete`
- `ItemCompleted`（仅 Plan 项）

**Extended 模式额外保存的事件**：
- `Error` / `GuardianAssessment`
- `WebSearchEnd` / `ExecCommandEnd`
- `PatchApplyEnd` / `McpToolCallEnd`
- `ViewImageToolCall` / `ImageGenerationEnd`
- 各种协作事件（`CollabAgentSpawnEnd` 等）
- 动态工具调用事件

**永不保存的事件**：
- 各种 Delta 事件（流式更新的中间状态）
- 开始事件（`Begin` 后缀）
- 实时对话事件
- 内部状态更新（`SessionConfigured`, `ThreadNameUpdated`）

### 5. 记忆提取策略 `should_persist_response_item_for_memories`

**目的**：决定哪些响应项应该用于生成记忆（memories）

**策略差异**：

| 响应项类型 | rollout 持久化 | 记忆提取 |
|-----------|---------------|---------|
| `Message` (role != "developer") | ✅ | ✅ |
| `Message` (role == "developer") | ✅ | ❌ |
| `LocalShellCall` | ✅ | ✅ |
| `FunctionCall` / `FunctionCallOutput` | ✅ | ✅ |
| `ToolSearchCall` / `ToolSearchOutput` | ✅ | ✅ |
| `CustomToolCall` / `CustomToolCallOutput` | ✅ | ✅ |
| `WebSearchCall` | ✅ | ✅ |
| `Reasoning` | ✅ | ❌ |
| `ImageGenerationCall` | ✅ | ❌ |
| `GhostSnapshot` | ✅ | ❌ |
| `Compaction` | ✅ | ❌ |

**说明**：
- Developer 消息不进入记忆（避免系统指令污染记忆）
- 推理内容不进入记忆（中间过程对用户无意义）
- 工具调用和输出进入记忆（保留执行历史）

## 具体技术实现

### 内联优化

所有判断函数都标记为 `#[inline]`，确保在热路径上的性能：

```rust
#[inline]
pub(crate) fn is_persisted_response_item(...) -> bool

#[inline]
pub(crate) fn should_persist_response_item(...) -> bool

#[inline]
pub(crate) fn should_persist_response_item_for_memories(...) -> bool

#[inline]
pub(crate) fn should_persist_event_msg(...) -> bool
```

### 模式匹配优化

使用 `matches!` 宏进行简洁的模式匹配：

```rust
fn should_persist_event_msg_limited(ev: &EventMsg) -> bool {
    matches!(
        event_msg_persistence_mode(ev),
        Some(EventPersistenceMode::Limited)
    )
}
```

### 分层策略实现

```rust
// 第一层：根据模式选择策略
pub(crate) fn should_persist_event_msg(ev: &EventMsg, mode: EventPersistenceMode) -> bool {
    match mode {
        EventPersistenceMode::Limited => should_persist_event_msg_limited(ev),
        EventPersistenceMode::Extended => should_persist_event_msg_extended(ev),
    }
}

// 第二层：Limited 策略
fn should_persist_event_msg_limited(ev: &EventMsg) -> bool {
    matches!(event_msg_persistence_mode(ev), Some(EventPersistenceMode::Limited))
}

// 第三层：Extended 策略
fn should_persist_event_msg_extended(ev: &EventMsg) -> bool {
    matches!(
        event_msg_persistence_mode(ev),
        Some(EventPersistenceMode::Limited) | Some(EventPersistenceMode::Extended)
    )
}

// 第四层：具体事件映射
fn event_msg_persistence_mode(ev: &EventMsg) -> Option<EventPersistenceMode> {
    match ev {
        EventMsg::UserMessage(_) => Some(EventPersistenceMode::Limited),
        // ...
    }
}
```

## 关键代码路径与文件引用

### 被调用位置

| 函数 | 调用方 | 文件 |
|-----|-------|------|
| `is_persisted_response_item` | `RolloutRecorder::record_items` | `recorder.rs` |
| `should_persist_response_item_for_memories` | 记忆生成模块 | `memories/phase1.rs` |

### 依赖类型

| 类型 | 来源 | 用途 |
|-----|------|------|
| `EventMsg` | `crate::protocol` | 事件消息枚举 |
| `RolloutItem` | `codex_protocol::protocol` | Rollout 项枚举 |
| `ResponseItem` | `codex_protocol::models` | 响应项枚举 |
| `TurnItem` | `codex_protocol::items` | 回合项枚举（用于 Plan 判断） |

### 模块关系

```
policy.rs
    ├── recorder.rs (调用 is_persisted_response_item)
    └── memories/phase1.rs (调用 should_persist_response_item_for_memories)
```

## 依赖与外部交互

### 与 recorder 的交互

```rust
// recorder.rs
pub(crate) async fn record_items(&self, items: &[RolloutItem]) -> std::io::Result<()> {
    let mut filtered = Vec::new();
    for item in items {
        if is_persisted_response_item(item, self.event_persistence_mode) {
            filtered.push(sanitize_rollout_item_for_persistence(item.clone(), self.event_persistence_mode));
        }
    }
    // 发送过滤后的 items 到写入通道
}
```

### 与记忆模块的交互

```rust
// memories/phase1.rs
let relevant_items: Vec<_> = items
    .iter()
    .filter(|item| should_persist_response_item_for_memories(item))
    .collect();
// 使用 relevant_items 生成记忆
```

## 风险、边界与改进建议

### 当前风险

1. **策略分散**：持久化策略分散在多个 `match` 语句中，修改时容易遗漏
2. **硬编码分类**：事件分类（Limited/Extended/None）硬编码在代码中，无法动态配置
3. **版本兼容性**：新增 `EventMsg` 变体时，如果不更新策略函数，会默认不保存（`None` 分支）

### 边界情况

1. **未知 ResponseItem 类型**：`ResponseItem::Other` 不保存，可能导致数据丢失
2. **模式切换**：运行时切换 `EventPersistenceMode` 可能导致同一 rollout 中混合不同策略的数据
3. **Plan 项特殊处理**：`ItemCompleted` 仅对 `TurnItem::Plan` 保存，逻辑较为隐蔽

### 改进建议

1. **配置化策略**：
   ```rust
   // 建议：使用配置文件定义持久化策略
   #[derive(Deserialize)]
   struct PersistencePolicy {
       limited_events: HashSet<EventMsgType>,
       extended_events: HashSet<EventMsgType>,
       never_events: HashSet<EventMsgType>,
   }
   ```

2. **派生宏自动生成**：
   ```rust
   // 建议：使用宏自动派生持久化策略
   #[derive(PersistencePolicy)]
   #[persistence(mode = "limited")]
   enum EventMsg {
       UserMessage(String),
       #[persistence(mode = "extended")]
       ExecCommandEnd(ExecCommandEndEvent),
       #[persistence(skip)]
       AgentMessageDelta(AgentMessageDeltaEvent),
   }
   ```

3. **编译时检查**：
   ```rust
   // 建议：确保所有 EventMsg 变体都被处理
   #[deny(unreachable_patterns)]
   fn event_msg_persistence_mode(ev: &EventMsg) -> Option<EventPersistenceMode> {
       match ev {
           // 所有变体必须显式处理
           _ => compile_error!("New EventMsg variant must define persistence policy"),
       }
   }
   ```

4. **策略文档自动生成**：
   ```rust
   // 建议：生成策略文档
   #[cfg(doc)]
   fn generate_persistence_policy_docs() {
       // 遍历所有 EventMsg 变体，生成 Markdown 表格
   }
   ```

5. **运行时策略切换保护**：
   ```rust
   // 建议：防止同一 rollout 中混合策略
   struct RolloutRecorder {
       event_persistence_mode: EventPersistenceMode,
       mode_switched: bool,  // 标记是否已切换过模式
   }
   
   impl RolloutRecorder {
       fn set_persistence_mode(&mut self, mode: EventPersistenceMode) {
           if mode != self.event_persistence_mode {
               assert!(!self.mode_switched, "Cannot switch persistence mode more than once");
               self.mode_switched = true;
               self.event_persistence_mode = mode;
           }
       }
   }
   ```

6. **测试覆盖**：
   ```rust
   // 建议：为每个 EventMsg 变体添加策略测试
   #[test_case(EventMsg::UserMessage(_), EventPersistenceMode::Limited => true)]
   #[test_case(EventMsg::AgentMessageDelta(_), EventPersistenceMode::Extended => false)]
   fn test_event_persistence_policy(ev: EventMsg, mode: EventPersistenceMode) -> bool {
       should_persist_event_msg(&ev, mode)
   }
   ```

### 策略决策矩阵

建议维护一个明确的决策矩阵文档：

| 事件类型 | Limited | Extended | Memories | 理由 |
|---------|---------|----------|----------|------|
| UserMessage | ✅ | ✅ | N/A | 核心对话数据 |
| AgentMessage | ✅ | ✅ | ✅ (non-dev) | 助手回复 |
| ExecCommandEnd | ❌ | ✅ | N/A | 诊断信息 |
| AgentMessageDelta | ❌ | ❌ | N/A | 流式中间状态 |
| ... | ... | ... | ... | ... |
