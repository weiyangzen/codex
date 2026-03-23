# event_stream.rs 深度研究文档

## 场景与职责

`event_stream.rs` 是 Codex TUI 的事件流基础设施，负责处理终端输入事件（键盘、粘贴、焦点变化、窗口大小调整）和绘制事件的统一流式抽象。它是 TUI 事件循环的核心组件，解决了以下关键问题：

1. **终端输入共享问题**：crossterm 使用全局 stdin 读取器，不支持多路复用。`EventBroker` 提供单一共享事件源，多个 `TuiEventStream` 实例可复用同一输入源
2. **暂停/恢复机制**：支持 TUI 在需要时完全释放 stdin（如启动外部编辑器 vim 时），避免窃取其他进程的输入
3. **跨平台兼容性**：Unix 平台支持 SIGTSTP（Ctrl+Z）挂起处理，Windows 平台有相应适配
4. **事件合并与过滤**：将 crossterm 底层事件映射为高层 `TuiEvent`，过滤掉不需要的事件（如鼠标事件）

## 功能点目的

### 1. EventSource  trait - 事件源抽象
- **目的**：允许在测试中使用假事件源替代真实的 crossterm 事件流
- **生产实现**：`CrosstermEventSource` 包装 `crossterm::event::EventStream`
- **测试实现**：`FakeEventSource` 通过 channel 发送测试事件

### 2. EventBroker - 共享事件代理
- **核心职责**：
  - 管理单一 crossterm 事件流实例的生命周期
  - 支持 `pause_events()` 完全丢弃底层流，释放 stdin
  - 支持 `resume_events()` 重新创建事件流
  - 通过 `watch::channel` 通知暂停中的流恢复

- **状态机**：
  ```
  Paused -> Start -> Running(S)
    ↑                    |
    └────────────────────┘ (error/EOF)
  ```

### 3. TuiEventStream - 统一事件流
- **职责**：合并两个事件源：
  - **绘制事件**：来自 `broadcast::channel` 的 `TuiEvent::Draw`
  - **输入事件**：通过 `EventBroker` 获取的键盘/粘贴/焦点事件

- **轮询策略**：使用 round-robin（`poll_draw_first` 标志交替）避免饥饿

### 4. 事件映射 (map_crossterm_event)
| Crossterm 事件 | TuiEvent | 说明 |
|---------------|----------|------|
| Key | Key | 键盘输入，支持 Ctrl+Z 挂起 |
| Resize | Draw | 窗口大小变化触发重绘 |
| Paste | Paste | 粘贴文本 |
| FocusGained | Draw | 终端获得焦点，触发颜色重新查询 |
| FocusLost | None (跳过) | 终端失去焦点 |
| Mouse/其他 | None (跳过) | 忽略鼠标事件 |

## 具体技术实现

### 关键数据结构

```rust
// 事件代理状态
enum EventBrokerState<S: EventSource> {
    Paused,     // 底层事件源已丢弃
    Start,      // 下次轮询时创建新事件源
    Running(S), // 事件源运行中
}

// 统一事件类型
pub enum TuiEvent {
    Key(KeyEvent),
    Paste(String),
    Draw,
}

// 事件流结构
pub struct TuiEventStream<S: EventSource> {
    broker: Arc<EventBroker<S>>,
    draw_stream: BroadcastStream<()>,      // 绘制事件广播
    resume_stream: WatchStream<()>,        // 恢复通知
    terminal_focused: Arc<AtomicBool>,     // 焦点状态
    poll_draw_first: bool,                 // 轮询顺序交替
    #[cfg(unix)]
    suspend_context: SuspendContext,       // Unix 挂起上下文
    #[cfg(unix)]
    alt_screen_active: Arc<AtomicBool>,    // 备用屏幕状态
}
```

### 关键流程

#### 1. 暂停/恢复流程
```rust
// 暂停：丢弃底层事件源
pub fn pause_events(&self) {
    *state = EventBrokerState::Paused;
}

// 恢复：标记为 Start，发送恢复通知
pub fn resume_events(&self) {
    *state = EventBrokerState::Start;
    let _ = self.resume_events_tx.send(());
}
```

#### 2. 轮询逻辑 (poll_crossterm_event)
```rust
loop {
    // 1. 获取活跃事件源（如为 Paused 则等待恢复）
    let events = state.active_event_source_mut()?;
    
    // 2. 轮询底层事件
    match Pin::new(events).poll_next(cx) {
        Ready(Some(Ok(event))) => {
            // 映射事件，如为 None 则继续轮询
            if let Some(mapped) = self.map_crossterm_event(event) {
                return Ready(Some(mapped));
            }
        }
        Ready(Some(Err(_))) | Ready(None) => {
            // 错误或 EOF：重置状态，结束流
            *state = EventBrokerState::Start;
            return Ready(None);
        }
        Pending => {
            // 等待时同时监听恢复通知
            match Pin::new(&mut self.resume_stream).poll_next(cx) {
                Ready(Some(())) => continue,  // 恢复后重试
                Ready(None) => return Ready(None),
                Pending => return Pending,
            }
        }
    }
}
```

#### 3. Stream trait 实现
```rust
impl Stream for TuiEventStream {
    fn poll_next(mut self: Pin<&mut Self>, cx: &mut Context) -> Poll<Option<TuiEvent>> {
        // Round-robin 轮询：交替优先检查 draw/crossterm
        let draw_first = self.poll_draw_first;
        self.poll_draw_first = !self.poll_draw_first;
        
        if draw_first {
            if let Ready(event) = self.poll_draw_event(cx) { return Ready(event); }
            if let Ready(event) = self.poll_crossterm_event(cx) { return Ready(event); }
        } else {
            if let Ready(event) = self.poll_crossterm_event(cx) { return Ready(event); }
            if let Ready(event) = self.poll_draw_event(cx) { return Ready(event); }
        }
        Pending
    }
}
```

### 测试实现

测试使用 `FakeEventSource` 通过 mpsc channel 模拟事件：

```rust
struct FakeEventSource {
    rx: mpsc::UnboundedReceiver<EventResult>,
    tx: mpsc::UnboundedSender<EventResult>,  // 通过 handle 发送
}
```

**测试覆盖**：
- `key_event_skips_unmapped`：验证 FocusLost 被跳过，Key 事件被传递
- `draw_and_key_events_yield_both`：验证两种事件都能被接收
- `lagged_draw_maps_to_draw`：广播 channel lag 时仍触发 Draw
- `error_or_eof_ends_stream`：错误/EOF 结束流
- `resume_wakes_paused_stream`：暂停后恢复能唤醒流
- `resume_wakes_pending_stream`：Pending 状态下暂停再恢复

## 关键代码路径与文件引用

### 本文件关键行
| 行号 | 内容 | 说明 |
|-----|------|------|
| 43-45 | `EventSource` trait | 事件源抽象接口 |
| 51-115 | `EventBroker` | 共享事件代理实现 |
| 117-130 | `CrosstermEventSource` | 生产环境事件源 |
| 139-171 | `TuiEventStream::new` | 事件流构造 |
| 178-222 | `poll_crossterm_event` | 核心轮询逻辑 |
| 224-234 | `poll_draw_event` | 绘制事件轮询 |
| 237-260 | `map_crossterm_event` | 事件映射 |
| 265-291 | `Stream` trait 实现 | 统一流接口 |
| 293-511 | 测试模块 | 完整测试覆盖 |

### 调用方文件
| 文件 | 使用方式 |
|------|----------|
| `tui.rs:241-258` | `Tui` 结构体持有 `event_broker` 和 `frame_requester` |
| `tui.rs:311-319` | `pause_events()` / `resume_events()` 包装 |
| `tui.rs:387-403` | `event_stream()` 创建 `TuiEventStream` |
| `tui.rs:326-358` | `with_restored()` 使用暂停/恢复运行外部程序 |
| `app.rs` | 通过 `tui.event_stream()` 获取事件流驱动主循环 |

### 依赖文件
| 文件 | 依赖内容 |
|------|----------|
| `tui/job_control.rs` | `SuspendContext`, `SUSPEND_KEY` (Unix) |
| `tui.rs` | `TuiEvent` 定义 |
| `key_hint.rs` | `KeyBinding` 用于检测 Ctrl+Z |
| `terminal_palette.rs` | `requery_default_colors()` 在 FocusGained 时调用 |

## 依赖与外部交互

### 外部 crate
| Crate | 用途 |
|-------|------|
| `crossterm` | 终端事件读取 (`EventStream`, `Event`, `KeyEvent`) |
| `tokio::sync` | `broadcast`, `watch`, `mpsc` 异步通道 |
| `tokio_stream` | `Stream` trait 及包装器 |

### 平台相关代码
- **Unix**：集成 `job_control::SuspendContext` 处理 SIGTSTP
- **Windows**：标准实现，无特殊挂起处理

### 与 TUI 其他模块交互
```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   FrameRequester │────▶│ broadcast::chan │◀────│ TuiEventStream  │
│   (frame_requester.rs)│ │   (draw events) │     │  (event_stream.rs)│
└─────────────────┘     └─────────────────┘     └────────┬────────┘
                                                         │
┌─────────────────┐     ┌─────────────────┐              │
│   EventBroker    │◀────│ Arc<EventBroker>│◀─────────────┘
│  (event_stream.rs)│    │   (shared)      │              │
└────────┬────────┘     └─────────────────┘              │
         │                                               │
         ▼                                               ▼
┌─────────────────┐                           ┌─────────────────┐
│ CrosstermEventSource │                      │      App        │
│ (crossterm::EventStream)│                   │  (event loop)   │
└─────────────────┘                           └─────────────────┘
```

## 风险、边界与改进建议

### 潜在风险

1. **事件窃取风险**
   - 多个 `TuiEventStream` 实例同时轮询时，一个实例可能消费事件导致另一个丢失
   - 缓解：设计上保证同一时刻只有一个流被轮询（通过 `Tui::event_stream()` 生命周期管理）

2. **Poisoned Mutex**
   - `EventBrokerState` 使用 `std::sync::Mutex`，panic 时可能中毒
   - 缓解：使用 `unwrap_or_else(PoisonError::into_inner)` 恢复

3. **平台差异**
   - Unix 的 SIGTSTP 处理在 Windows 不存在
   - 条件编译 `#[cfg(unix)]` 确保代码正确性

4. **恢复通知丢失**
   - 如果 `resume_events_rx` 在 `resume_events()` 调用后才订阅，可能错过通知
   - 缓解：`TuiEventStream::new` 时立即创建 `WatchStream`

### 边界情况

| 场景 | 行为 |
|------|------|
| 快速 pause/resume | 通过 `Start` 状态确保重新创建事件源 |
| 所有发送者被丢弃 | `FrameScheduler` 退出循环（见 frame_requester.rs） |
| 广播 channel lag | 映射为 `TuiEvent::Draw`，不丢失重绘 |
| FocusLost 事件 | 更新 `terminal_focused` 标志，不生成 TuiEvent |
| Ctrl+Z (Unix) | 触发挂起流程，返回 `TuiEvent::Draw` 刷新 UI |

### 改进建议

1. **性能优化**
   - 当前使用 `std::sync::Mutex` 保护 `EventBrokerState`，可考虑 `parking_lot::Mutex` 减少开销
   - `poll_crossterm_event` 中的循环在事件密集时可能 starve draw events，当前 round-robin 已缓解

2. **可观测性**
   - 添加 tracing span 跟踪事件流状态变化（Paused/Running）
   - 记录事件映射丢弃情况（如鼠标事件）用于调试

3. **代码结构**
   - `map_crossterm_event` 中的 `#[cfg(unix)]` 块可提取为平台无关的抽象
   - 考虑将 `FakeEventSource` 作为测试公用设施移至独立模块

4. **健壮性**
   - 考虑为 `resume_events()` 添加超时机制，防止无限等待
   - 添加事件流健康检查指标（如长时间无事件）

5. **文档**
   - 添加更多架构图说明事件流向
   - 说明 `pause_events()` / `resume_events()` 的调用约定
