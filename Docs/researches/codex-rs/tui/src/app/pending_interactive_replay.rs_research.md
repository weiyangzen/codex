# pending_interactive_replay.rs 深度研究文档

## 场景与职责

`pending_interactive_replay.rs` 是 Codex TUI 中负责**线程事件快照重放时交互式提示过滤**的关键模块。它解决的核心问题是：

**问题场景**：
当用户在多智能体会话中切换线程（如从主线程切换到子 Agent 线程再切回）时，TUI 需要重放该线程的历史事件来恢复界面状态。但某些交互式提示（如命令执行审批、补丁应用审批、用户输入请求等）如果已经被用户响应过，就不应该在重放时再次出现。

**核心职责**：
1. **跟踪待处理的交互式提示**：记录哪些审批/输入请求仍处于未解决状态
2. **快照过滤**：在生成线程事件快照时，过滤掉已解决的交互式提示
3. **多类型支持**：处理执行审批、补丁审批、MCP 诱导请求、权限请求、用户输入请求等多种类型
4. **Turn 生命周期管理**：当 Turn 完成或中止时，清理相关的待处理提示

**设计原则**：
- 与 `ThreadEventStore` 紧密协作，但保持关注点分离
- 使用双重索引（全局集合 + Turn 映射）支持快速查找和批量清理
- 所有状态变更通过显式方法调用，便于追踪

## 功能点目的

### 1. PendingInteractiveReplayState - 核心状态容器

```rust
#[derive(Debug, Default)]
pub(super) struct PendingInteractiveReplayState {
    // 执行审批
    exec_approval_call_ids: HashSet<String>,
    exec_approval_call_ids_by_turn_id: HashMap<String, Vec<String>>,
    
    // 补丁审批
    patch_approval_call_ids: HashSet<String>,
    patch_approval_call_ids_by_turn_id: HashMap<String, Vec<String>>,
    
    // MCP 诱导请求（使用复合键）
    elicitation_requests: HashSet<ElicitationRequestKey>,
    
    // 权限请求
    request_permissions_call_ids: HashSet<String>,
    request_permissions_call_ids_by_turn_id: HashMap<String, Vec<String>>,
    
    // 用户输入请求（FIFO 队列）
    request_user_input_call_ids: HashSet<String>,
    request_user_input_call_ids_by_turn_id: HashMap<String, Vec<String>>,
}
```

**数据结构说明**：
- `*_call_ids`: 全局快速查找集合，用于 `should_replay_snapshot_event()`
- `*_by_turn_id`: 按 Turn ID 索引的映射，用于 Turn 结束时的批量清理
- `ElicitationRequestKey`: 复合键 `(server_name, request_id)`，因为 MCP 诱导请求需要服务器名称区分

### 2. ElicitationRequestKey - MCP 诱导请求键

```rust
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
struct ElicitationRequestKey {
    server_name: String,
    request_id: codex_protocol::mcp::RequestId,
}
```

### 3. 核心方法

| 方法 | 用途 |
|------|------|
| `note_event()` | 处理入站事件，添加新的待处理提示 |
| `note_outbound_op()` | 处理出站操作，移除已解决的提示 |
| `note_evicted_event()` | 处理被驱逐的事件（缓冲区溢出时） |
| `should_replay_snapshot_event()` | 判断事件是否应在快照重放时显示 |
| `has_pending_thread_approvals()` | 检查是否有待处理的审批（用于 UI 指示器） |
| `event_can_change_pending_thread_approvals()` | 静态方法：判断事件类型是否可能影响审批状态 |
| `op_can_change_state()` | 静态方法：判断操作类型是否可能改变状态 |

## 具体技术实现

### 1. 事件类型检测

```rust
pub(super) fn event_can_change_pending_thread_approvals(event: &Event) -> bool {
    matches!(
        &event.msg,
        EventMsg::ExecApprovalRequest(_)
            | EventMsg::ApplyPatchApprovalRequest(_)
            | EventMsg::ElicitationRequest(_)
            | EventMsg::RequestPermissions(_)
            | EventMsg::ExecCommandBegin(_)      // 执行开始 = 审批通过
            | EventMsg::PatchApplyBegin(_)       // 补丁开始 = 审批通过
            | EventMsg::TurnComplete(_)          // Turn 完成 = 清理
            | EventMsg::TurnAborted(_)           // Turn 中止 = 清理
            | EventMsg::ShutdownComplete         // 关闭完成 = 清理
    )
}
```

### 2. 操作类型检测

```rust
pub(super) fn op_can_change_state(op: &Op) -> bool {
    matches!(
        op,
        Op::ExecApproval { .. }
            | Op::PatchApproval { .. }
            | Op::ResolveElicitation { .. }
            | Op::RequestPermissionsResponse { .. }
            | Op::UserInputAnswer { .. }
            | Op::Shutdown
    )
}
```

### 3. 入站事件处理（note_event）

以执行审批请求为例：
```rust
EventMsg::ExecApprovalRequest(ev) => {
    let approval_id = ev.effective_approval_id();
    self.exec_approval_call_ids.insert(approval_id.clone());
    self.exec_approval_call_ids_by_turn_id
        .entry(ev.turn_id.clone())
        .or_default()
        .push(approval_id);
}
```

**关键逻辑**：
- 同时添加到全局集合和 Turn 映射
- 使用 `effective_approval_id()` 处理可能的别名情况

### 4. 执行开始事件处理

```rust
EventMsg::ExecCommandBegin(ev) => {
    // 执行开始意味着审批已通过，移除待处理状态
    self.exec_approval_call_ids.remove(&ev.call_id);
    Self::remove_call_id_from_turn_map(
        &mut self.exec_approval_call_ids_by_turn_id,
        &ev.call_id,
    );
}
```

### 5. Turn 完成/中止清理

```rust
EventMsg::TurnComplete(ev) => {
    self.clear_exec_approval_turn(&ev.turn_id);
    self.clear_patch_approval_turn(&ev.turn_id);
    self.clear_request_permissions_turn(&ev.turn_id);
    self.clear_request_user_input_turn(&ev.turn_id);
}
```

**注意**：MCP 诱导请求没有 Turn 级别的清理，因为它们可能跨 Turn 存在。

### 6. 出站操作处理（note_outbound_op）

用户输入回答的特殊处理（FIFO）：
```rust
Op::UserInputAnswer { id, .. } => {
    // UI 对同一 Turn 的队列提示按 FIFO 顺序回答
    let mut remove_turn_entry = false;
    if let Some(call_ids) = self.request_user_input_call_ids_by_turn_id.get_mut(id) {
        if !call_ids.is_empty() {
            let call_id = call_ids.remove(0);  // 移除最老的
            self.request_user_input_call_ids.remove(&call_id);
        }
        if call_ids.is_empty() {
            remove_turn_entry = true;
        }
    }
    if remove_turn_entry {
        self.request_user_input_call_ids_by_turn_id.remove(id);
    }
}
```

### 7. 快照重放过滤

```rust
pub(super) fn should_replay_snapshot_event(&self, event: &Event) -> bool {
    match &event.msg {
        EventMsg::ExecApprovalRequest(ev) => self
            .exec_approval_call_ids
            .contains(&ev.effective_approval_id()),
        EventMsg::ApplyPatchApprovalRequest(ev) => {
            self.patch_approval_call_ids.contains(&ev.call_id)
        }
        EventMsg::ElicitationRequest(ev) => {
            self.elicitation_requests.contains(&ElicitationRequestKey::new(
                ev.server_name.clone(),
                ev.id.clone(),
            ))
        }
        EventMsg::RequestUserInput(ev) => {
            self.request_user_input_call_ids.contains(&ev.call_id)
        }
        EventMsg::RequestPermissions(ev) => {
            self.request_permissions_call_ids.contains(&ev.call_id)
        }
        _ => true,  // 非交互式事件总是重放
    }
}
```

### 8. 缓冲区驱逐处理

当 `ThreadEventStore` 的缓冲区满时，旧事件被驱逐：
```rust
pub(super) fn note_evicted_event(&mut self, event: &Event) {
    match &event.msg {
        EventMsg::ExecApprovalRequest(ev) => {
            let approval_id = ev.effective_approval_id();
            self.exec_approval_call_ids.remove(&approval_id);
            // ... 从 Turn 映射中移除
        }
        // ... 其他类型类似
    }
}
```

## 关键代码路径与文件引用

### 本模块关键代码

| 行号 | 代码 | 说明 |
|------|------|------|
| 7-20 | `ElicitationRequestKey` | MCP 诱导请求复合键 |
| 22-46 | `PendingInteractiveReplayState` 结构体 | 核心状态定义 |
| 49-62 | `event_can_change_pending_thread_approvals()` | 事件类型过滤 |
| 64-74 | `op_can_change_state()` | 操作类型过滤 |
| 76-134 | `note_outbound_op()` | 出站操作处理 |
| 136-206 | `note_event()` | 入站事件处理 |
| 208-270 | `note_evicted_event()` | 缓冲区驱逐处理 |
| 272-295 | `should_replay_snapshot_event()` | 快照重放决策 |
| 297-302 | `has_pending_thread_approvals()` | 待处理审批检查 |
| 304-334 | `clear_*_turn()` | Turn 清理辅助方法 |
| 336-361 | `remove_call_id_from_turn_map*()` | 映射清理辅助方法 |

### 调用方（app.rs 中的 ThreadEventStore）

```rust
// app.rs:327-335 - ThreadEventStore 结构体
struct ThreadEventStore {
    session_configured: Option<Event>,
    buffer: VecDeque<Event>,
    user_message_ids: HashSet<String>,
    pending_interactive_replay: PendingInteractiveReplayState,  // 本模块
    input_state: Option<ThreadInputState>,
    capacity: usize,
    active: bool,
}

// app.rs:357-360 - 推送事件
fn push_event(&mut self, event: Event) {
    self.pending_interactive_replay.note_event(&event);
    // ...
}

// app.rs:383-399 - 推送旧版事件（含驱逐逻辑）
fn push_legacy_event(&mut self, event: Event) {
    // ...
    if self.buffer.len() > self.capacity && let Some(removed) = self.buffer.pop_front() {
        self.pending_interactive_replay.note_evicted_event(&removed);
        // ...
    }
}

// app.rs:401-417 - 生成快照
fn snapshot(&self) -> ThreadEventSnapshot {
    ThreadEventSnapshot {
        // ...
        events: self
            .buffer
            .iter()
            .filter(|event| {
                self.pending_interactive_replay
                    .should_replay_snapshot_event(event)
            })
            .cloned()
            .collect(),
        // ...
    }
}

// app.rs:419-421 - 记录出站操作
fn note_outbound_op(&mut self, op: &Op) {
    self.pending_interactive_replay.note_outbound_op(op);
}
```

### App 层调用

```rust
// app.rs:1351-1359 - 记录活动线程的出站操作
async fn note_active_thread_outbound_op(&mut self, op: &Op) {
    if !ThreadEventStore::op_can_change_pending_replay_state(op) {
        return;
    }
    let Some(thread_id) = self.active_thread_id else { return };
    self.note_thread_outbound_op(thread_id, op).await;
}

// app.rs:1513-1540 - 刷新待处理审批指示器
async fn refresh_pending_thread_approvals(&mut self) {
    // ... 遍历所有线程通道，检查 has_pending_thread_approvals()
}

// app.rs:1542-1594 - 入队线程事件
async fn enqueue_thread_event(&mut self, thread_id: ThreadId, event: Event) -> Result<()> {
    let refresh_pending_thread_approvals =
        ThreadEventStore::event_can_change_pending_thread_approvals(&event);
    // ...
}
```

### 依赖模块

| 文件/模块 | 用途 |
|-----------|------|
| `codex_protocol::protocol::Event` | 事件类型定义 |
| `codex_protocol::protocol::EventMsg` | 事件消息变体 |
| `codex_protocol::protocol::Op` | 操作类型定义 |
| `codex_protocol::mcp::RequestId` | MCP 请求 ID 类型 |
| `codex_protocol::approvals::*` | 审批相关类型 |
| `codex_protocol::request_user_input::*` | 用户输入相关类型 |

## 依赖与外部交互

### 上游依赖（协议层）

1. **codex_protocol::protocol**
   - `Event` / `EventMsg`：入站事件
   - `Op`：出站操作
   - `ExecApprovalRequestEvent`、`ApplyPatchApprovalRequestEvent` 等具体事件类型

2. **codex_protocol::mcp**
   - `RequestId`：MCP 请求标识

3. **codex_protocol::approvals**
   - `ElicitationRequestEvent`、`ElicitationAction`

4. **codex_protocol::request_user_input**
   - `RequestUserInputEvent`、`RequestUserInputResponse`

### 下游调用方

1. **app.rs - ThreadEventStore**
   - 封装本模块，提供线程级别的事件存储和快照功能

2. **app.rs - App**
   - 使用 `has_pending_thread_approvals()` 更新 UI 指示器
   - 使用 `event_can_change_pending_thread_approvals()` 决定是否需要刷新 UI

## 风险、边界与改进建议

### 潜在风险

1. **内存泄漏风险**
   - 风险：如果 Turn 完成/中止事件丢失，`*_by_turn_id` 映射可能积累死条目
   - 缓解：定期清理或设置上限，但目前依赖协议层保证事件送达

2. **并发安全**
   - 当前 `PendingInteractiveReplayState` 不是 `Sync`，但包装在 `ThreadEventStore` 中
   - `ThreadEventStore` 通过 `Arc<Mutex<>>` 保护，确保线程安全

3. **事件顺序依赖**
   - 假设：`ExecCommandBegin` 总是在对应的 `ExecApprovalRequest` 之后到达
   - 风险：如果顺序错乱，可能错误地移除不存在的条目（无害但会丢失清理机会）

4. **MCP 诱导请求无 Turn 清理**
   - 风险：如果 MCP 服务器未正确响应，诱导请求可能永远留在集合中
   - 缓解：依赖 `ShutdownComplete` 或缓冲区驱逐清理

### 边界情况

1. **重复事件 ID**
   - `HashSet` 自动去重，同一提示的重复添加无害

2. **UserInput FIFO 队列**
   - 同一 Turn 可能有多个 `RequestUserInput` 事件
   - `UserInputAnswer` 按 Turn ID 回答，内部按 FIFO 匹配
   - 测试用例 `thread_event_snapshot_drops_answered_request_user_input_for_multi_prompt_turn` 验证此行为

3. **缓冲区溢出**
   - 当事件被驱逐时，自动从待处理集合中移除
   - 避免已驱逐但已解决的提示在快照中错误显示

4. **Turn 中止**
   - `TurnAborted` 的 `turn_id` 是 `Option<String>`
   - 仅在 `turn_id` 存在时清理

### 改进建议

1. **可观测性增强**
   - 添加 `tracing` 日志记录状态变更
   - 导出指标：待处理提示数量、各类型分布

2. **防御性编程**
   - 为 `*_by_turn_id` 映射添加大小上限
   - 定期清理无对应全局集合条目的死映射条目

3. **性能优化**
   - 当前 `should_replay_snapshot_event()` 对每个事件进行模式匹配
   - 建议：如果性能成为问题，可预计算事件类型缓存

4. **功能扩展**
   - 支持暂停/恢复特定类型的提示跟踪
   - 支持提示优先级排序

5. **测试覆盖**
   - 当前测试覆盖主要场景（行 376-724）
   - 建议添加：
     - 并发访问测试
     - 极端边界条件（空字符串 ID、特殊字符）
     - 内存压力测试（大量 Turn 和提示）

### 测试要点

```rust
// 核心测试用例
#[test]
fn thread_event_snapshot_keeps_pending_request_user_input() { ... }

#[test]
fn thread_event_snapshot_drops_resolved_request_user_input_after_user_answer() { ... }

#[test]
fn thread_event_snapshot_drops_resolved_exec_approval_after_outbound_approval_id() { ... }

#[test]
fn thread_event_snapshot_drops_answered_request_user_input_for_multi_prompt_turn() { ... }

#[test]
fn thread_event_snapshot_keeps_newer_request_user_input_pending_when_same_turn_has_queue() { ... }

#[test]
fn thread_event_snapshot_drops_resolved_patch_approval_after_outbound_approval() { ... }

#[test]
fn thread_event_snapshot_drops_pending_approvals_when_turn_aborts() { ... }

#[test]
fn thread_event_snapshot_drops_resolved_elicitation_after_outbound_resolution() { ... }

#[test]
fn thread_event_store_reports_pending_thread_approvals() { ... }

#[test]
fn request_user_input_does_not_count_as_pending_thread_approval() { ... }
```

测试使用 `pretty_assertions` 进行清晰断言，使用 `ThreadEventStore` 作为测试入口验证集成行为。
