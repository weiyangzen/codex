# thread_state.rs 研究文档

## 场景与职责

`thread_state.rs` 实现了线程状态管理的核心逻辑，负责维护每个线程的运行时状态、监听器生命周期、待处理操作队列和 turn 摘要信息。该模块是 App Server 与 Core 层线程交互的枢纽，管理线程的订阅关系、事件流和生命周期转换。

## 功能点目的

### 1. 线程状态维护
- 跟踪待处理的中断请求队列
- 管理待处理的回滚操作
- 维护当前 turn 的摘要信息（文件变更、命令执行、错误）
- 控制实验性原始事件标志

### 2. 监听器生命周期管理
- 设置和清理线程事件监听器
- 管理监听器生成计数（用于识别过期监听器）
- 处理监听器取消信号

### 3. 线程状态管理器
- 维护线程到连接的订阅关系
- 处理连接初始化、订阅和取消订阅
- 管理连接断开时的清理逻辑

### 4. Turn 历史跟踪
- 累积当前 turn 的事件历史
- 提供 turn 快照功能

## 具体技术实现

### 核心结构

#### ThreadState
```rust
pub(crate) struct ThreadState {
    pub(crate) pending_interrupts: PendingInterruptQueue,
    pub(crate) pending_rollbacks: Option<ConnectionRequestId>,
    pub(crate) turn_summary: TurnSummary,
    pub(crate) cancel_tx: Option<oneshot::Sender<()>>,
    pub(crate) experimental_raw_events: bool,
    pub(crate) listener_generation: u64,
    listener_command_tx: Option<mpsc::UnboundedSender<ThreadListenerCommand>>,
    current_turn_history: ThreadHistoryBuilder,
    listener_thread: Option<Weak<CodexThread>>,
}
```

#### TurnSummary
```rust
#[derive(Default, Clone)]
pub(crate) struct TurnSummary {
    pub(crate) file_change_started: HashSet<String>,
    pub(crate) command_execution_started: HashSet<String>,
    pub(crate) last_error: Option<TurnError>,
}
```

#### PendingThreadResumeRequest
```rust
pub(crate) struct PendingThreadResumeRequest {
    pub(crate) request_id: ConnectionRequestId,
    pub(crate) rollout_path: PathBuf,
    pub(crate) config_snapshot: ThreadConfigSnapshot,
    pub(crate) thread_summary: codex_app_server_protocol::Thread,
}
```

#### ThreadListenerCommand
```rust
pub(crate) enum ThreadListenerCommand {
    SendThreadResumeResponse(Box<PendingThreadResumeRequest>),
    ResolveServerRequest {
        request_id: RequestId,
        completion_tx: oneshot::Sender<()>,
    },
}
```

### ThreadState 方法

#### 监听器管理
```rust
pub(crate) fn listener_matches(&self, conversation: &Arc<CodexThread>) -> bool
pub(crate) fn set_listener(&mut self, cancel_tx: oneshot::Sender<()>, conversation: &Arc<CodexThread>) -> (mpsc::UnboundedReceiver<ThreadListenerCommand>, u64)
pub(crate) fn clear_listener(&mut self)
```

**set_listener 逻辑**:
1. 如有现有监听器，发送取消信号
2. 递增 `listener_generation`
3. 创建新的命令通道
4. 存储弱引用到线程

#### Turn 跟踪
```rust
pub(crate) fn active_turn_snapshot(&self) -> Option<Turn>
pub(crate) fn track_current_turn_event(&mut self, event: &EventMsg)
```

### ThreadStateManager
```rust
#[derive(Clone, Default)]
pub(crate) struct ThreadStateManager {
    state: Arc<Mutex<ThreadStateManagerInner>>,
}

struct ThreadStateManagerInner {
    live_connections: HashSet<ConnectionId>,
    threads: HashMap<ThreadId, ThreadEntry>,
    thread_ids_by_connection: HashMap<ConnectionId, HashSet<ThreadId>>,
}

struct ThreadEntry {
    state: Arc<Mutex<ThreadState>>,
    connection_ids: HashSet<ConnectionId>,
}
```

### 订阅管理方法

#### 连接初始化
```rust
pub(crate) async fn connection_initialized(&self, connection_id: ConnectionId)
```

#### 线程订阅
```rust
pub(crate) async fn try_ensure_connection_subscribed(
    &self,
    thread_id: ThreadId,
    connection_id: ConnectionId,
    experimental_raw_events: bool,
) -> Option<Arc<Mutex<ThreadState>>>
```

#### 取消订阅
```rust
pub(crate) async fn unsubscribe_connection_from_thread(
    &self,
    thread_id: ThreadId,
    connection_id: ConnectionId,
) -> bool
```

#### 连接移除
```rust
pub(crate) async fn remove_connection(&self, connection_id: ConnectionId)
```

#### 线程状态移除
```rust
pub(crate) async fn remove_thread_state(&self, thread_id: ThreadId)
```

## 关键代码路径与文件引用

### 定义位置
- `codex-rs/app-server/src/thread_state.rs`

### 使用位置
| 文件 | 用途 |
|------|------|
| `lib.rs` | 模块声明，处理器使用 `ThreadStateManager` |
| `bespoke_event_handling.rs` | 处理线程事件，更新线程状态 |
| `codex_message_processor.rs` | 管理线程生命周期，订阅/取消订阅 |

### 协议层类型
- `codex-rs/app-server-protocol/src/protocol/v2.rs`:
  - `Turn`, `TurnError`
  - `ThreadHistoryBuilder`

### Core 层类型
- `codex-rs/core/src/lib.rs`:
  - `CodexThread`
  - `ThreadConfigSnapshot`

## 依赖与外部交互

### 外部依赖
```rust
use crate::outgoing_message::{ConnectionId, ConnectionRequestId};
use codex_app_server_protocol::{ThreadHistoryBuilder, Turn, TurnError};
use codex_core::CodexThread;
use codex_protocol::ThreadId;
use codex_protocol::protocol::EventMsg;
use tokio::sync::{Mutex, mpsc, oneshot};
```

### 生命周期流程

#### 线程创建
1. 客户端调用 `thread/start` 或 `thread/resume`
2. `CodexMessageProcessor` 创建 Core 层线程
3. 调用 `try_ensure_connection_subscribed` 建立订阅
4. 设置监听器，开始接收事件

#### 事件处理
1. Core 层线程产生事件
2. 监听器接收事件，更新 `ThreadState`
3. 事件发送到所有订阅的连接

#### 连接断开
1. 检测到连接关闭
2. 调用 `remove_connection` 清理订阅
3. 如无其他订阅者，可选择保留或清理线程监听器

#### 线程关闭
1. 客户端调用 `thread/unsubscribe` 或线程完成
2. 调用 `remove_thread_state`
3. 清理监听器，释放资源

## 风险、边界与改进建议

### 当前风险
1. **内存泄漏**: `ThreadStateManager` 中的线程状态可能无限增长，如果客户端不主动取消订阅
2. **竞态条件**: 监听器设置和取消之间可能存在竞态，导致事件丢失或重复
3. **弱引用失效**: `listener_thread` 使用弱引用，升级失败时行为需要仔细处理
4. **命令通道积压**: `ThreadListenerCommand` 通道无界，可能积累大量未处理命令

### 边界情况
1. **重复订阅**: 同一连接多次订阅同一线程，需要去重处理
2. **无订阅者**: 线程无活跃订阅者时，事件仍可能被处理（取决于清理策略）
3. **快速重连**: 连接断开后快速重连，可能遇到旧的监听器状态
4. **并发修改**: 多个连接同时操作同一线程的订阅状态

### 改进建议
1. **自动清理**: 添加线程状态 TTL，长时间无活动的线程自动清理
2. **订阅确认**: 添加订阅确认机制，确保客户端收到初始状态
3. **事件回放**: 支持新订阅者的事件回放，避免错过历史事件
4. **资源限制**: 限制每个连接的订阅线程数和每个线程的订阅连接数
5. **指标监控**: 记录线程状态数量、订阅关系数量、监听器生成计数等指标
6. **优雅降级**: 当资源紧张时，优先保留交互式来源的线程状态
