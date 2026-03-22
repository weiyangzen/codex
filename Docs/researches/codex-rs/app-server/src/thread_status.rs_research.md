# thread_status.rs 研究文档

## 场景与职责

`thread_status.rs` 实现了线程状态监视和管理功能，负责跟踪线程的运行时状态（如运行中、等待用户输入、等待批准等），并向客户端广播状态变更通知。该模块是 App Server 状态管理的核心组件，为 UI 提供线程状态的实时视图。

## 功能点目的

### 1. 线程状态跟踪
跟踪每个线程的运行时状态，包括：
- 是否加载
- 是否运行中
- 待处理的权限请求数
- 待处理的用户输入请求数
- 是否发生系统错误

### 2. 状态变更通知
当线程状态发生变化时，自动向所有连接的客户端发送 `thread/status/changed` 通知。

### 3. 运行中 Turn 计数
维护全局运行中 turn 计数，用于优雅关闭和资源管理。

### 4. 活动守卫模式
使用 RAII 模式管理活动状态（权限请求、用户输入请求），确保状态自动清理。

## 具体技术实现

### 核心结构

#### ThreadWatchManager
```rust
#[derive(Clone)]
pub(crate) struct ThreadWatchManager {
    state: Arc<Mutex<ThreadWatchState>>,
    outgoing: Option<Arc<OutgoingMessageSender>>,
    running_turn_count_tx: watch::Sender<usize>,
}
```

#### ThreadWatchActiveGuard
```rust
pub(crate) struct ThreadWatchActiveGuard {
    manager: ThreadWatchManager,
    thread_id: String,
    guard_type: ThreadWatchActiveGuardType,
    handle: tokio::runtime::Handle,
}

#[derive(Clone, Copy)]
enum ThreadWatchActiveGuardType {
    Permission,
    UserInput,
}
```

**Drop 实现**:
```rust
impl Drop for ThreadWatchActiveGuard {
    fn drop(&mut self) {
        let manager = self.manager.clone();
        let thread_id = self.thread_id.clone();
        let guard_type = self.guard_type;
        self.handle.spawn(async move {
            manager.note_active_guard_released(thread_id, guard_type).await;
        });
    }
}
```

#### ThreadWatchState
```rust
#[derive(Default)]
struct ThreadWatchState {
    runtime_by_thread_id: HashMap<String, RuntimeFacts>,
}

#[derive(Clone, Default)]
struct RuntimeFacts {
    is_loaded: bool,
    running: bool,
    pending_permission_requests: u32,
    pending_user_input_requests: u32,
    has_system_error: bool,
}
```

### 状态计算方法

#### loaded_thread_status
```rust
fn loaded_thread_status(runtime: &RuntimeFacts) -> ThreadStatus {
    if !runtime.is_loaded {
        return ThreadStatus::NotLoaded;
    }

    let mut active_flags = Vec::new();
    if runtime.pending_permission_requests > 0 {
        active_flags.push(ThreadActiveFlag::WaitingOnApproval);
    }
    if runtime.pending_user_input_requests > 0 {
        active_flags.push(ThreadActiveFlag::WaitingOnUserInput);
    }

    if runtime.running || !active_flags.is_empty() {
        return ThreadStatus::Active { active_flags };
    }

    if runtime.has_system_error {
        return ThreadStatus::SystemError;
    }

    ThreadStatus::Idle
}
```

#### resolve_thread_status
```rust
pub(crate) fn resolve_thread_status(
    status: ThreadStatus,
    has_in_progress_turn: bool,
) -> ThreadStatus {
    if has_in_progress_turn && matches!(status, ThreadStatus::Idle | ThreadStatus::NotLoaded) {
        return ThreadStatus::Active { active_flags: Vec::new() };
    }
    status
}
```

### 状态更新方法

#### Turn 生命周期
```rust
pub(crate) async fn note_turn_started(&self, thread_id: &str)
pub(crate) async fn note_turn_completed(&self, thread_id: &str, _failed: bool)
pub(crate) async fn note_turn_interrupted(&self, thread_id: &str)
```

#### 线程生命周期
```rust
pub(crate) async fn upsert_thread(&self, thread: Thread)
pub(crate) async fn upsert_thread_silently(&self, thread: Thread)
pub(crate) async fn remove_thread(&self, thread_id: &str)
pub(crate) async fn note_thread_shutdown(&self, thread_id: &str)
```

#### 错误处理
```rust
pub(crate) async fn note_system_error(&self, thread_id: &str)
```

#### 活动请求跟踪
```rust
pub(crate) async fn note_permission_requested(&self, thread_id: &str) -> ThreadWatchActiveGuard
pub(crate) async fn note_user_input_requested(&self, thread_id: &str) -> ThreadWatchActiveGuard
```

### 状态变更通知流程

#### mutate_and_publish
```rust
async fn mutate_and_publish<F>(&self, mutate: F)
where
    F: FnOnce(&mut ThreadWatchState) -> Option<ThreadStatusChangedNotification>,
{
    let (notification, running_turn_count) = {
        let mut state = self.state.lock().await;
        let notification = mutate(&mut state);
        let running_turn_count = state
            .runtime_by_thread_id
            .values()
            .filter(|runtime| runtime.running)
            .count();
        (notification, running_turn_count)
    };
    let _ = self.running_turn_count_tx.send(running_turn_count);

    if let Some(notification) = notification
        && let Some(outgoing) = &self.outgoing
    {
        outgoing.send_server_notification(...).await;
    }
}
```

## 关键代码路径与文件引用

### 定义位置
- `codex-rs/app-server/src/thread_status.rs`

### 协议层类型
- `codex-rs/app-server-protocol/src/protocol/v2.rs`:
  - `ThreadStatus` 枚举: `NotLoaded`, `Idle`, `Active { active_flags }`, `SystemError`
  - `ThreadActiveFlag` 枚举: `WaitingOnApproval`, `WaitingOnUserInput`
  - `ThreadStatusChangedNotification`
  - `Thread` 结构

### 使用位置
| 文件 | 用途 |
|------|------|
| `lib.rs` | 模块声明，创建 `ThreadWatchManager` |
| `bespoke_event_handling.rs` | 调用状态更新方法 |
| `codex_message_processor.rs` | 调用状态更新方法，查询线程状态 |
| `tests/suite/v2/thread_status.rs` | 集成测试 |
| `tests/suite/v2/thread_unsubscribe.rs` | 集成测试 |

### 测试覆盖
模块包含全面的单元测试：
- 默认状态为 `NotLoaded`
- 非交互式线程状态跟踪
- 状态更新跟踪单个线程
- 运行中 turn 解析为活跃状态
- 系统错误设置直到下次 turn
- 关闭标记线程为 `NotLoaded`
- 批量状态查询
- 运行中 turn 计数仅跟踪 `running` 标志
- 状态变更发送通知
- 静默 upsert 跳过初始通知

## 依赖与外部交互

### 外部依赖
```rust
use crate::outgoing_message::OutgoingMessageSender;
use codex_app_server_protocol::{ServerNotification, Thread, ThreadActiveFlag, ThreadStatus, ThreadStatusChangedNotification};
use tokio::sync::{Mutex, watch};
```

### 状态转换图

```
NotLoaded -> Idle (upsert_thread)
Idle -> Active { flags: [] } (note_turn_started)
Active { flags: [] } -> Active { flags: [WaitingOnApproval] } (note_permission_requested)
Active { flags: [] } -> Active { flags: [WaitingOnUserInput] } (note_user_input_requested)
Active { ... } -> Idle (note_turn_completed / note_turn_interrupted)
Active { ... } -> SystemError (note_system_error)
SystemError -> Active { flags: [] } (note_turn_started)
Idle -> NotLoaded (note_thread_shutdown)
```

### 调用时序示例

#### Turn 开始
1. `note_turn_started` 被调用
2. `RuntimeFacts.running` 设为 `true`
3. `has_system_error` 重置为 `false`
4. 发送 `ThreadStatusChangedNotification`

#### 权限请求
1. `note_permission_requested` 被调用
2. `pending_permission_requests` 递增
3. 返回 `ThreadWatchActiveGuard`
4. 发送状态变更通知
5. 守卫被 drop，`pending_permission_requests` 递减
6. 发送状态变更通知

## 风险、边界与改进建议

### 当前风险
1. **状态竞争**: `has_in_progress_turn` 参数用于解决状态竞争，但依赖调用方正确传递
2. **计数溢出**: `pending_permission_requests` 和 `pending_user_input_requests` 使用 `u32`，理论上可能溢出（使用 `saturating_add` 缓解）
3. **通知丢失**: 如果 `outgoing` 发送失败，客户端可能错过状态变更
4. **内存增长**: `runtime_by_thread_id` 可能无限增长，如果线程不被移除

### 边界情况
1. **重复 turn 开始**: 连续调用 `note_turn_started` 会重置状态，可能导致状态闪烁
2. **守卫泄漏**: 如果 `ThreadWatchActiveGuard` 未被正确 drop，计数不会递减
3. **静默 upsert**: `upsert_thread_silently` 不发送通知，但后续状态变更会正常通知
4. **空连接**: `outgoing` 为 `None` 时，状态变更不发送通知（用于测试）

### 改进建议
1. **状态校验**: 添加状态转换校验，防止非法转换（如 `NotLoaded` 直接到 `Active`）
2. **历史记录**: 记录状态变更历史，便于调试和审计
3. **批量通知**: 考虑批量发送状态变更通知，减少网络开销
4. **订阅过滤**: 支持客户端订阅特定状态或状态变更
5. **状态超时**: 对 `Active` 状态添加超时检测，防止永久挂起
6. **指标收集**: 记录各状态的持续时间、状态变更频率等指标
