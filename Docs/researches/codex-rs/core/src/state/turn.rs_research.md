# turn.rs 研究文档

## 场景与职责

`turn.rs` 定义了 Codex 单轮对话（Turn）级别的状态管理类型。与 `SessionState`（会话级别持久状态）不同，`TurnState` 和 `ActiveTurn` 专注于管理单轮对话内的临时状态和运行中的任务。

核心职责：
1. **活跃轮次管理** (`ActiveTurn`): 跟踪当前正在执行的轮次及其任务
2. **轮次状态管理** (`TurnState`): 管理单轮对话内的可变状态
3. **任务生命周期** (`RunningTask`): 封装异步任务的执行和取消
4. **挂起操作跟踪**: 跟踪等待用户响应的操作（审批、权限请求、用户输入等）

## 功能点目的

### 1. ActiveTurn - 活跃轮次

管理当前正在执行的轮次：
- 跟踪该轮次内的所有运行中任务
- 提供任务添加、移除、清空操作
- 持有 `TurnState` 的共享状态

### 2. RunningTask - 运行中任务

封装单个异步任务的完整上下文：
- 任务完成通知 (`Notify`)
- 任务类型标识 (`TaskKind`)
- 取消令牌 (`CancellationToken`)
- 任务句柄 (`AbortOnDropHandle`)
- 轮次上下文 (`TurnContext`)
- 执行计时器（用于遥测）

### 3. TaskKind - 任务类型

标识任务的类型：
- `Regular`: 常规用户对话
- `Review`: 代码审查任务
- `Compact`: 历史压缩任务

### 4. TurnState - 轮次状态

管理单轮对话内的临时状态：
- **挂起审批**: 等待用户审批的工具调用
- **挂起权限请求**: 等待用户响应的权限请求
- **挂起用户输入**: 等待用户输入的请求
- **挂起引导**: MCP 服务器的引导请求
- **挂起动态工具**: 动态工具的响应等待
- **挂起输入**: 缓冲的输入项
- **已授予权限**: 本轮次累积的权限
- **工具调用计数**: 本轮次的工具调用次数
- **Token 使用量**: 轮次开始时的 Token 使用量基准

## 具体技术实现

### 数据结构

#### ActiveTurn

```rust
pub(crate) struct ActiveTurn {
    pub(crate) tasks: IndexMap<String, RunningTask>,  // 任务映射（按 sub_id）
    pub(crate) turn_state: Arc<Mutex<TurnState>>,     // 共享的轮次状态
}

impl Default for ActiveTurn {
    fn default() -> Self {
        Self {
            tasks: IndexMap::new(),
            turn_state: Arc::new(Mutex::new(TurnState::default())),
        }
    }
}
```

使用 `IndexMap` 保证任务插入顺序，支持按 `sub_id` 快速查找。

#### RunningTask

```rust
pub(crate) struct RunningTask {
    pub(crate) done: Arc<Notify>,                           // 完成通知
    pub(crate) kind: TaskKind,                              // 任务类型
    pub(crate) task: Arc<dyn SessionTask>,                  // 任务 trait 对象
    pub(crate) cancellation_token: CancellationToken,       // 取消令牌
    pub(crate) handle: Arc<AbortOnDropHandle<()>>,         // 中止句柄
    pub(crate) turn_context: Arc<TurnContext>,             // 轮次上下文
    pub(crate) _timer: Option<codex_otel::Timer>,          // 执行计时器
}
```

#### TaskKind

```rust
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum TaskKind {
    Regular,
    Review,
    Compact,
}
```

#### TurnState

```rust
#[derive(Default)]
pub(crate) struct TurnState {
    pending_approvals: HashMap<String, oneshot::Sender<ReviewDecision>>,
    pending_request_permissions: HashMap<String, oneshot::Sender<RequestPermissionsResponse>>,
    pending_user_input: HashMap<String, oneshot::Sender<RequestUserInputResponse>>,
    pending_elicitations: HashMap<(String, RequestId), oneshot::Sender<ElicitationResponse>>,
    pending_dynamic_tools: HashMap<String, oneshot::Sender<DynamicToolResponse>>,
    pending_input: Vec<ResponseInputItem>,
    granted_permissions: Option<PermissionProfile>,
    pub(crate) tool_calls: u64,
    pub(crate) token_usage_at_turn_start: TokenUsage,
}
```

### 关键方法

#### ActiveTurn 方法

```rust
impl ActiveTurn {
    // 添加任务到活跃轮次
    pub(crate) fn add_task(&mut self, task: RunningTask) {
        let sub_id = task.turn_context.sub_id.clone();
        self.tasks.insert(sub_id, task);
    }

    // 移除任务，返回是否为空
    pub(crate) fn remove_task(&mut self, sub_id: &str) -> bool {
        self.tasks.swap_remove(sub_id);
        self.tasks.is_empty()
    }

    // 清空所有任务
    pub(crate) fn drain_tasks(&mut self) -> Vec<RunningTask> {
        self.tasks.drain(..).map(|(_, task)| task).collect()
    }
}
```

#### TurnState 方法 - 挂起操作管理

```rust
impl TurnState {
    // 审批管理
    pub(crate) fn insert_pending_approval(
        &mut self,
        key: String,
        tx: oneshot::Sender<ReviewDecision>,
    ) -> Option<oneshot::Sender<ReviewDecision>> {
        self.pending_approvals.insert(key, tx)
    }

    pub(crate) fn remove_pending_approval(
        &mut self,
        key: &str,
    ) -> Option<oneshot::Sender<ReviewDecision>> {
        self.pending_approvals.remove(key)
    }

    // 清空所有挂起操作
    pub(crate) fn clear_pending(&mut self) {
        self.pending_approvals.clear();
        self.pending_request_permissions.clear();
        self.pending_user_input.clear();
        self.pending_elicitations.clear();
        self.pending_dynamic_tools.clear();
        self.pending_input.clear();
    }
}
```

#### TurnState 方法 - 输入缓冲

```rust
impl TurnState {
    // 添加输入到末尾
    pub(crate) fn push_pending_input(&mut self, input: ResponseInputItem) {
        self.pending_input.push(input);
    }

    // 前置输入（用于钩子拦截后的重新注入）
    pub(crate) fn prepend_pending_input(&mut self, mut input: Vec<ResponseInputItem>) {
        if input.is_empty() {
            return;
        }
        input.append(&mut self.pending_input);
        self.pending_input = input;
    }

    // 取出所有挂起输入
    pub(crate) fn take_pending_input(&mut self) -> Vec<ResponseInputItem> {
        if self.pending_input.is_empty() {
            Vec::with_capacity(0)
        } else {
            let mut ret = Vec::new();
            std::mem::swap(&mut ret, &mut self.pending_input);
            ret
        }
    }

    pub(crate) fn has_pending_input(&self) -> bool {
        !self.pending_input.is_empty()
    }
}
```

#### TurnState 方法 - 权限管理

```rust
impl TurnState {
    pub(crate) fn record_granted_permissions(&mut self, permissions: PermissionProfile) {
        self.granted_permissions =
            merge_permission_profiles(self.granted_permissions.as_ref(), Some(&permissions));
    }

    pub(crate) fn granted_permissions(&self) -> Option<PermissionProfile> {
        self.granted_permissions.clone()
    }
}
```

#### ActiveTurn 异步方法

```rust
impl ActiveTurn {
    /// 清空当前轮次的所有挂起审批和输入
    pub(crate) async fn clear_pending(&self) {
        let mut ts = self.turn_state.lock().await;
        ts.clear_pending();
    }
}
```

## 关键代码路径与文件引用

### 创建位置

`ActiveTurn` 在 `tasks/mod.rs` 的 `register_new_active_task` 方法中创建：

```rust
// tasks/mod.rs:371
async fn register_new_active_task(
    &self,
    task: RunningTask,
    token_usage_at_turn_start: TokenUsage,
) {
    let mut active = self.active_turn.lock().await;
    let mut turn = ActiveTurn::default();
    let mut turn_state = turn.turn_state.lock().await;
    turn_state.token_usage_at_turn_start = token_usage_at_turn_start;
    drop(turn_state);
    turn.add_task(task);
    *active = Some(turn);
}
```

`RunningTask` 在 `tasks/mod.rs` 的 `spawn_task` 方法中创建：

```rust
// tasks/mod.rs:216
let running_task = RunningTask {
    done,
    handle: Arc::new(AbortOnDropHandle::new(handle)),
    kind: task_kind,
    task,
    cancellation_token,
    turn_context: Arc::clone(&turn_context),
    _timer: timer,
};
```

### 主要使用位置

1. **任务管理** (`tasks/mod.rs`):
   - `spawn_task`: 创建并注册新任务
   - `abort_all_tasks`: 中止所有任务
   - `on_task_finished`: 任务完成处理
   - `handle_task_abort`: 任务中止处理

2. **审批流程** (`codex.rs`):
   - 插入挂起审批：`insert_pending_approval`
   - 移除并响应审批：`remove_pending_approval`

3. **权限请求** (`codex.rs`):
   - 插入权限请求：`insert_pending_request_permissions`
   - 响应权限请求：`remove_pending_request_permissions`

4. **用户输入请求** (`codex.rs`):
   - 插入输入请求：`insert_pending_user_input`
   - 响应输入请求：`remove_pending_user_input`

5. **MCP 引导** (`mcp_tool_call.rs`):
   - 插入引导请求：`insert_pending_elicitation`
   - 响应引导请求：`remove_pending_elicitation`

6. **动态工具** (`codex.rs`):
   - 插入动态工具响应：`insert_pending_dynamic_tool`
   - 响应动态工具：`remove_pending_dynamic_tool`

## 依赖与外部交互

### 导入依赖

```rust
use indexmap::IndexMap;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;
use tokio::sync::Notify;
use tokio_util::sync::CancellationToken;
use tokio_util::task::AbortOnDropHandle;

use codex_protocol::dynamic_tools::DynamicToolResponse;
use codex_protocol::models::ResponseInputItem;
use codex_protocol::request_permissions::RequestPermissionsResponse;
use codex_protocol::request_user_input::RequestUserInputResponse;
use codex_rmcp_client::ElicitationResponse;
use rmcp::model::RequestId;
use tokio::sync::oneshot;

use crate::codex::TurnContext;
use crate::protocol::ReviewDecision;
use crate::protocol::TokenUsage;
use crate::sandboxing::merge_permission_profiles;
use crate::tasks::SessionTask;
use codex_protocol::models::PermissionProfile;
```

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `indexmap` | `IndexMap` - 保持插入顺序的 HashMap |
| `tokio::sync` | `Mutex`, `Notify`, `oneshot` - 异步同步原语 |
| `tokio_util` | `CancellationToken`, `AbortOnDropHandle` - 任务管理 |
| `codex_protocol` | 协议类型（`DynamicToolResponse`, `ResponseInputItem` 等） |
| `codex_rmcp_client` | `ElicitationResponse` - MCP 引导响应 |
| `rmcp` | `RequestId` - MCP 请求 ID |

### 内部模块依赖

| 模块 | 用途 |
|------|------|
| `codex` | `TurnContext` - 轮次上下文 |
| `protocol` | `ReviewDecision`, `TokenUsage` |
| `sandboxing` | `merge_permission_profiles` - 权限合并 |
| `tasks` | `SessionTask` - 任务 trait |

## 风险、边界与改进建议

### 风险点

1. **死锁风险**：`turn_state` 是 `Arc<Mutex<TurnState>>`，长时间持有锁可能导致其他任务阻塞
2. **内存泄漏**：`pending_*` HashMap 中的 `oneshot::Sender` 如果未被消费，可能导致内存泄漏
3. **任务取消**：`AbortOnDropHandle` 在 drop 时会中止任务，需要确保资源正确清理
4. **并发安全**：多个任务同时访问 `TurnState` 需要小心处理竞态条件

### 边界条件

1. **空任务列表**：`remove_task` 返回 `true` 时表示任务列表为空
2. **重复键**：`insert_*` 方法返回 `Option`，表示是否已存在相同键
3. **取消令牌**：`cancellation_token` 被取消后，任务应该尽快退出
4. **输入缓冲**：`prepend_pending_input` 处理空输入时会提前返回

### 改进建议

#### 1. 超时机制

为挂起操作添加超时机制：

```rust
pub(crate) struct PendingApproval {
    tx: oneshot::Sender<ReviewDecision>,
    created_at: Instant,
    timeout: Duration,
}
```

#### 2. 清理机制

定期清理过期的挂起操作：

```rust
impl TurnState {
    pub(crate) fn cleanup_expired(&mut self, max_age: Duration) {
        let now = Instant::now();
        self.pending_approvals.retain(|_, v| now - v.created_at < max_age);
        // ... 其他清理
    }
}
```

#### 3. 指标收集

添加挂起操作的指标收集：

```rust
impl TurnState {
    pub(crate) fn metrics(&self) -> TurnStateMetrics {
        TurnStateMetrics {
            pending_approvals: self.pending_approvals.len(),
            pending_permissions: self.pending_request_permissions.len(),
            pending_input: self.pending_user_input.len(),
            pending_elicitations: self.pending_elicitations.len(),
            pending_dynamic_tools: self.pending_dynamic_tools.len(),
            buffered_input: self.pending_input.len(),
        }
    }
}
```

#### 4. 类型安全

使用类型包装器避免键的混淆：

```rust
struct ApprovalKey(String);
struct PermissionKey(String);
struct UserInputKey(String);
```

#### 5. 测试覆盖

当前文件没有对应的测试文件，建议添加：

```rust
#[cfg(test)]
#[path = "turn_tests.rs"]
mod tests;
```

测试用例建议：
- 任务添加/移除
- 挂起操作的插入/移除
- 输入缓冲的前置/取出
- 权限合并
- 清空操作
- 并发访问

#### 6. 文档完善

为公共方法添加更详细的文档：

```rust
/// 插入一个挂起的审批请求。
/// 
/// # 参数
/// - `key`: 审批的唯一标识
/// - `tx`: 用于发送审批结果的 oneshot 通道
/// 
/// # 返回值
/// 如果已存在相同 key 的审批，返回旧的 sender
/// 
/// # 注意
/// 调用者负责确保 key 的唯一性，通常使用工具调用的 ID
pub(crate) fn insert_pending_approval(...)
```

### 架构建议

考虑将 `TurnState` 拆分为多个专门的子状态：

```rust
struct ApprovalState { ... }
struct PermissionState { ... }
struct InputState { ... }
struct ElicitationState { ... }

struct TurnState {
    approvals: ApprovalState,
    permissions: PermissionState,
    inputs: InputState,
    elicitations: ElicitationState,
    // ...
}
```

这样可以：
- 减少单个结构的复杂度
- 提高内聚性
- 便于单独测试
