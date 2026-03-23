# event_stream.rs 深度研究文档

## 场景与职责

`event_stream.rs` 是 Codex TUI 应用服务器的事件流处理核心模块，负责管理终端输入事件的捕获、分发和生命周期控制。该模块解决了以下关键问题：

1. **终端输入共享问题**：crossterm 的 `EventStream` 使用全局 stdin 读取器，不支持多路复用（fan-out），需要集中管理
2. **终端状态切换**：当 TUI 需要让出终端给其他进程（如 Vim）时，必须完全释放 stdin 以避免输入冲突
3. **事件流暂停/恢复**：支持在运行外部程序时暂停事件流，返回后恢复

### 核心使用场景

- **正常 TUI 交互**：捕获键盘输入、窗口大小变化、焦点变化、粘贴事件
- **外部编辑器集成**：用户打开 Vim/Emacs 时，TUI 必须完全 relinquish stdin
- **进程挂起恢复**：处理 Unix SIGTSTP 信号后的终端状态恢复
- **多屏幕切换**：支持嵌套或顺序屏幕的事件流复用

## 功能点目的

### 1. EventBroker - 共享事件源管理器

```rust
pub struct EventBroker<S: EventSource = CrosstermEventSource> {
    state: Mutex<EventBrokerState<S>>,
    resume_events_tx: watch::Sender<()>,
}
```

**目的**：
- 持有共享的 crossterm 事件流，使多个 `TuiEventStream` 实例复用同一输入源
- 支持在 pause/resume 时丢弃/重建底层事件流而不重建消费者
- 通过 `watch::channel` 通知等待中的流恢复事件

**状态机设计**：
```rust
enum EventBrokerState<S: EventSource> {
    Paused,     // 底层事件源已丢弃
    Start,      // 下次 poll 时创建新事件源
    Running(S), // 事件源正在运行
}
```

### 2. TuiEventStream - 统一事件流

```rust
pub struct TuiEventStream<S: EventSource + Default + Unpin = CrosstermEventSource> {
    broker: Arc<EventBroker<S>>,
    draw_stream: BroadcastStream<()>,
    resume_stream: WatchStream<()>,
    terminal_focused: Arc<AtomicBool>,
    poll_draw_first: bool,
    #[cfg(unix)] suspend_context: SuspendContext,
    #[cfg(unix)] alt_screen_active: Arc<AtomicBool>,
}
```

**目的**：
- 合并两类事件源：
  - **绘制事件**（`BroadcastStream<()>`）：由 `FrameRequester` 触发的重绘请求
  - **终端输入事件**（`CrosstermEventSource`）：用户键盘、鼠标、窗口变化等
- 实现 round-robin 公平调度，避免某一事件源饿死
- Unix 平台支持挂起上下文和备用屏幕状态跟踪

### 3. EventSource Trait - 可测试抽象

```rust
pub trait EventSource: Send + 'static {
    fn poll_next(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<EventResult>>;
}
```

**目的**：
- 允许在生产环境使用 `CrosstermEventSource`
- 允许在测试中使用 `FakeEventSource` 注入模拟事件
- 解耦业务逻辑与底层 crossterm 依赖

### 4. 事件映射与过滤

```rust
fn map_crossterm_event(&mut self, event: Event) -> Option<TuiEvent>
```

**映射规则**：
| Crossterm 事件 | TuiEvent | 说明 |
|---------------|----------|------|
| `Key(key)` | `Key(key)` | 键盘事件，Unix 下检查 Ctrl+Z 挂起 |
| `Resize(_, _)` | `Draw` | 窗口大小变化触发重绘 |
| `Paste(text)` | `Paste(text)` | 粘贴文本 |
| `FocusGained` | `Draw` | 重新获取焦点，刷新调色板 |
| `FocusLost` | `None` | 失去焦点，更新状态但不触发事件 |
| 其他（鼠标等） | `None` | 忽略未使用的事件 |

## 具体技术实现

### 关键流程 1：事件流暂停与恢复

```rust
// 暂停事件流（如打开外部编辑器前）
pub fn pause_events(&self) {
    let mut state = self.state.lock().unwrap_or_else(...);
    *state = EventBrokerState::Paused;
}

// 恢复事件流
pub fn resume_events(&self) {
    let mut state = self.state.lock().unwrap_or_else(...);
    *state = EventBrokerState::Start;  // 标记为需要重建
    let _ = self.resume_events_tx.send(());  // 唤醒等待中的流
}
```

**关键设计**：
- 暂停时**完全丢弃** `EventStream`，而非仅停止轮询
- 原因：crossterm 的 `EventStream` 在 pending 状态下仍会从 stdin 读取，可能"窃取"其他进程的输入
- 参考：[ratatui recipes](https://ratatui.rs/recipes/apps/spawn-vim/) 和 [Reddit 讨论](https://www.reddit.com/r/rust/comments/1f3o33u/myterious_crossterm_input_after_running_vim)

### 关键流程 2：Poll 实现（公平调度）

```rust
impl<S: EventSource + Default + Unpin> Stream for TuiEventStream<S> {
    type Item = TuiEvent;

    fn poll_next(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        // 近似公平 + 无饥饿的 round-robin
        let draw_first = self.poll_draw_first;
        self.poll_draw_first = !self.poll_draw_first;

        if draw_first {
            if let Poll::Ready(event) = self.poll_draw_event(cx) { return ... }
            if let Poll::Ready(event) = self.poll_crossterm_event(cx) { return ... }
        } else {
            if let Poll::Ready(event) = self.poll_crossterm_event(cx) { return ... }
            if let Poll::Ready(event) = self.poll_draw_event(cx) { return ... }
        }
        Poll::Pending
    }
}
```

### 关键流程 3：挂起键处理（Unix）

```rust
#[cfg(unix)]
if crate::tui::job_control::SUSPEND_KEY.is_press(key_event) {
    let _ = self.suspend_context.suspend(&self.alt_screen_active);
    return Some(TuiEvent::Draw);
}
```

- `SUSPEND_KEY` 定义为 `Ctrl+Z`
- 触发 `SuspendContext::suspend()` 发送 SIGTSTP
- 返回 `Draw` 事件确保 UI 在挂起前刷新

### 数据结构详解

#### EventBrokerState 状态转换

```
Start --(active_event_source_mut)--> Running
  ^                                    |
  |                                    |
  +--------(pause_events)--------------+
  |
  +--------(resume_events)-------------+

Paused --(resume_events)--> Start
Paused --(poll 时遇到)--> 返回 Pending，等待 resume_stream
```

#### TuiEvent 枚举

```rust
pub enum TuiEvent {
    Key(KeyEvent),    // 键盘输入
    Paste(String),    // 粘贴内容
    Draw,             // 重绘请求
}
```

## 关键代码路径与文件引用

### 模块内引用

| 路径 | 用途 |
|------|------|
| `super::TuiEvent` | 事件类型定义（在 `tui.rs` 中） |
| `super::job_control::SuspendContext` | Unix 挂起上下文（仅 Unix） |

### 调用方（外部使用）

| 文件 | 使用方式 |
|------|----------|
| `tui.rs:387-403` | `Tui::event_stream()` 创建事件流 |
| `tui.rs:311-318` | `Tui::pause_events/resume_events` 代理到 EventBroker |
| `app.rs` | 通过 `event_stream` 获取事件并处理 |

### 被调用方（依赖）

| 依赖 | 用途 |
|------|------|
| `crossterm::event::EventStream` | 底层终端事件源 |
| `tokio::sync::{broadcast, watch}` | 异步事件通道 |
| `tokio_stream::{Stream, wrappers}` | Stream trait 和包装器 |

## 依赖与外部交互

### 外部 crate 依赖

```rust
use crossterm::event::Event;           // 终端事件定义
use tokio::sync::broadcast;            // 广播通道（绘制事件）
use tokio::sync::watch;                // 观察通道（恢复通知）
use tokio_stream::Stream;              // 异步流 trait
use tokio_stream::wrappers::{BroadcastStream, WatchStream};
```

### 与 job_control 的交互（Unix）

```rust
// event_stream.rs 中
#[cfg(unix)]
if crate::tui::job_control::SUSPEND_KEY.is_press(key_event) {
    let _ = self.suspend_context.suspend(&self.alt_screen_active);
    return Some(TuiEvent::Draw);
}
```

- `SuspendContext` 管理 SIGTSTP 的处理
- `alt_screen_active` 跟踪备用屏幕状态，决定恢复时的行为

### 与 frame_requester 的交互

```rust
// TuiEventStream 订阅绘制广播
draw_stream: BroadcastStream<()>,  // 来自 FrameRequester 的 draw_tx
```

- `FrameRequester` 通过 `broadcast::channel` 发送绘制请求
- `TuiEventStream` 将广播事件转换为 `TuiEvent::Draw`

## 风险、边界与改进建议

### 已知风险

1. **输入竞争风险**
   - 如果多个 `TuiEventStream` 同时被 poll，一个实例可能"窃取"输入事件
   - 文档明确警告："only one should be polled at a time"
   - **缓解**：通过 `Tui` 结构集中管理，确保生命周期不重叠

2. **Poisoned Mutex 处理**
   - 使用 `unwrap_or_else(std::sync::PoisonError::into_inner)` 处理 poisoned lock
   - 这可能在 panic 后继续运行，状态可能不一致
   - **风险**：低，但可能导致事件流状态异常

3. **平台差异**
   - Unix 有挂起支持，`SuspendContext` 和 `alt_screen_active` 仅在 Unix 编译
   - Windows 不支持挂起，代码通过条件编译处理
   - **风险**：跨平台行为不一致

### 边界情况

1. **Lagged Draw 事件**
   ```rust
   Poll::Ready(Some(Err(BroadcastStreamRecvError::Lagged(_)))) => {
       Poll::Ready(Some(TuiEvent::Draw))  // 仍然触发重绘
   }
   ```
   - 当消费者处理速度慢于生产者时，广播通道可能丢弃消息
   - 实现选择：即使 lagged 也触发重绘，确保 UI 最终一致

2. **EOF/Error 处理**
   ```rust
   Poll::Ready(Some(Err(_))) | Poll::Ready(None) => {
       *state = EventBrokerState::Start;
       return Poll::Ready(None);  // 流结束
   }
   ```
   - 错误时重置为 Start 状态，允许下次重新创建

3. **Resume 唤醒竞争**
   - `poll_crossterm_event` 在多个点检查 `resume_stream`
   - 确保无论处于 `Paused` 还是 `Pending` 状态都能被唤醒

### 改进建议

1. **更严格的并发控制**
   - 考虑使用 `tokio::sync::RwLock` 替代 `std::sync::Mutex` 以更好地集成异步运行时
   - 或者使用 `tokio::sync::mpsc` 将状态变更序列化到单个任务

2. **可配置的帧率限制**
   - 当前绘制事件通过 `frame_rate_limiter` 限制在 120 FPS
   - 可考虑将限制逻辑移至 event_stream，提供更统一的背压控制

3. **改进错误处理**
   - 当前错误处理较为简单，可添加更详细的日志和恢复策略
   - 特别是 crossterm 错误时，可尝试重新初始化而非直接结束流

4. **测试覆盖扩展**
   - 当前测试覆盖了基本功能，但缺少：
     - 多平台（Windows）行为测试
     - 高并发场景下的竞争条件测试
     - 长时间运行的压力测试

5. **文档改进**
   - 添加架构图说明 EventBroker、TuiEventStream、FrameRequester 的关系
   - 更详细地说明 pause/resume 的使用场景和约束
