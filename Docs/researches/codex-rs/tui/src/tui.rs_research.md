# tui.rs 研究文档

## 场景与职责

`tui.rs` 是 Codex TUI（终端用户界面）的核心基础设施模块，负责终端的初始化、模式设置、事件流管理、绘制调度和状态恢复。它是整个 TUI 应用的底层支撑层，为上层 UI 组件提供统一的终端抽象。

主要使用场景：
- TUI 应用启动时初始化终端环境
- 管理终端的原始模式（raw mode）和交替屏幕（alternate screen）
- 处理键盘增强标志和焦点变化事件
- 协调绘制帧率（最高 120 FPS）
- 支持终端挂起/恢复（Ctrl+Z）
- 与外部程序（如编辑器）共享终端时的状态切换

## 功能点目的

### 1. 终端初始化与模式设置

**目的**：配置终端以支持交互式 TUI 操作。

**关键功能**：
- `init()`：检查 stdin/stdout 是否为终端，启用 bracketed paste、原始模式、键盘增强标志
- `set_modes()`：启用键盘增强（区分修饰键的 Enter）、焦点变化检测
- `restore()` / `restore_keep_raw()`：恢复终端到原始状态

**键盘增强标志**（Keyboard Enhancement Flags）：
- `DISAMBIGUATE_ESCAPE_CODES`：区分 Escape 序列
- `REPORT_EVENT_TYPES`：报告事件类型
- `REPORT_ALTERNATE_KEYS`：报告替代键

这些标志使终端能够正确识别带修饰键的按键（如 Ctrl+Enter），这对 chat_composer.rs 中的多行输入至关重要。

### 2. 交替屏幕管理

**目的**：支持全屏覆盖 UI（如弹出窗口）与内联视口的切换。

**关键结构**：
```rust
pub struct Tui {
    alt_saved_viewport: Option<ratatui::layout::Rect>,  // 保存的内联视口
    alt_screen_active: Arc<AtomicBool>,                 // 交替屏幕状态
    alt_screen_enabled: bool,                           // 是否启用交替屏幕（Zellij 兼容）
}
```

**方法**：
- `enter_alt_screen()`：进入交替屏幕，扩展视口到全屏
- `leave_alt_screen()`：离开交替屏幕，恢复内联视口
- `set_alt_screen_enabled()`：控制交替屏幕开关（用于 Zellij 等终端复用器的滚动回退支持）

### 3. 事件流管理

**目的**：统一处理键盘、粘贴、绘制等事件，支持事件暂停/恢复。

**事件类型**：
```rust
pub enum TuiEvent {
    Key(KeyEvent),
    Paste(String),
    Draw,
}
```

**关键组件**：
- `EventBroker`：共享的 crossterm 事件源，支持多消费者
- `TuiEventStream`：事件流包装器，实现 `Stream` trait
- `pause_events()` / `resume_events()`：暂停/恢复事件监听

**设计动机**：
当 TUI 需要运行外部交互式程序（如 Vim）时，必须完全释放 stdin。如果仅停止轮询而不丢弃事件流，crossterm 的读取线程可能继续消耗输入，导致外部程序错过输入。

### 4. 帧率控制与绘制调度

**目的**：平滑动画和状态更新，同时避免过度绘制。

**关键组件**：
- `FrameRequester`：轻量级句柄，用于请求重绘
- `FrameScheduler`：后台任务，合并多个绘制请求
- `FrameRateLimiter`：限制最高 120 FPS

**工作流程**：
1. UI 组件调用 `frame_requester.schedule_frame()`
2. `FrameScheduler` 接收请求，合并短时间内的大量请求
3. 达到帧率限制后，通过广播通道发送绘制信号
4. `TuiEventStream` 接收 `TuiEvent::Draw` 并触发重绘

### 5. 终端挂起/恢复（Unix）

**目的**：支持 Ctrl+Z 挂起 TUI，恢复后正确还原状态。

**关键结构**：
```rust
#[cfg(unix)]
pub struct SuspendContext {
    resume_pending: Arc<Mutex<Option<ResumeAction>>>,
    suspend_cursor_y: Arc<AtomicU16>,
}
```

**恢复动作**：
- `RealignInline`：重新对齐内联视口
- `RestoreAlt`：恢复交替屏幕

### 6. 桌面通知

**目的**：当终端失去焦点时，向用户发送桌面通知。

**关键方法**：
- `notify(message)`：检查终端焦点状态，发送通知
- `set_notification_method()`：配置通知方式

## 具体技术实现

### 终端输入缓冲区刷新

平台特定实现：
- **Unix**：使用 `libc::tcflush(STDIN_FILENO, TCIFLUSH)`
- **Windows**：使用 `FlushConsoleInputBuffer()`
- **其他**：空操作

用途：在外部程序运行后清除缓冲的按键，避免按键被误读。

### 同步更新（Synchronized Update）

使用 `crossterm::SynchronizedUpdate` 包装绘制操作，确保：
1. 视口更新和光标位置查询在同步块外完成
2. 绘制操作在同步块内原子执行
3. 避免与事件读取器竞争

### 视口调整策略

当终端大小改变且光标位置移动时：
```rust
fn pending_viewport_area(&mut self) -> Result<Option<Rect>> {
    // 如果屏幕大小改变且光标移动，调整视口区域以保持光标位置
    let offset = Offset {
        x: 0,
        y: cursor_pos.y as i32 - last_known_cursor_pos.y as i32,
    };
    Ok(Some(terminal.viewport_area.offset(offset)))
}
```

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 |
|------|------|
| `tui.rs` | 主模块，Tui 结构体定义和公共接口 |
| `tui/event_stream.rs` | 事件流实现，EventBroker 和 TuiEventStream |
| `tui/frame_requester.rs` | 帧请求和调度 |
| `tui/frame_rate_limiter.rs` | 帧率限制（120 FPS） |
| `tui/job_control.rs` | Unix 挂起/恢复支持 |

### 关键调用路径

**启动流程**：
```
main.rs -> Tui::new() -> init() -> set_modes() -> EventBroker::new()
```

**绘制流程**：
```
Widget::schedule_frame() -> FrameRequester::schedule_frame() 
-> FrameScheduler::run() -> draw_tx.send(()) 
-> TuiEventStream::poll_draw_event() -> TuiEvent::Draw
-> App::run() -> tui.draw()
```

**外部程序执行**：
```
with_restored() -> pause_events() -> leave_alt_screen() -> restore()
-> f().await -> set_modes() -> flush_terminal_input_buffer() 
-> enter_alt_screen() -> resume_events()
```

**挂起/恢复（Unix）**：
```
Ctrl+Z -> SUSPEND_KEY -> suspend_context.suspend() 
-> SIGTSTP -> 用户 fg -> set_modes() -> prepare_resume_action()
```

## 依赖与外部交互

### 外部 crate

| Crate | 用途 |
|-------|------|
| `crossterm` | 跨平台终端控制（模式设置、事件读取） |
| `ratatui` | TUI 框架（Backend、Buffer、Rect 等） |
| `tokio` | 异步运行时（广播通道、任务调度） |
| `tokio-stream` | 流处理 |

### 内部模块依赖

| 模块 | 用途 |
|------|------|
| `custom_terminal` | 自定义 Terminal 实现，支持视口管理 |
| `notifications` | 桌面通知后端检测和发送 |
| `insert_history` | 历史行插入（由 draw() 调用） |

### 平台特定依赖

- **Unix**：`libc`（SIGTSTP、tcflush）
- **Windows**：`windows-sys`（控制台 API）

## 风险、边界与改进建议

### 已知风险

1. **键盘增强标志兼容性**
   - 旧版 Windows 控制台不支持键盘增强标志
   - 缓解：使用 `let _ = execute!(...)` 忽略错误

2. **Zellij 滚动回退问题**
   - 交替屏幕模式下，Zellij 等终端复用器无法正确捕获滚动回退
   - 缓解：`set_alt_screen_enabled(false)` 允许用户禁用交替屏幕

3. **事件流竞争**
   - 如果 `pause_events()` 和 `resume_events()` 调用不当，可能导致事件丢失或重复
   - 缓解：`with_restored()` 封装了正确的调用顺序

4. **挂起时的光标位置**
   - 挂起时必须正确设置光标 Y 坐标，否则恢复后光标位置错误
   - 缓解：`suspend_context.set_cursor_y()` 在正常绘制时持续更新

### 边界条件

1. **终端大小为 0**：`draw()` 中检查 `size.height` 避免除以零
2. **视口扩展超出屏幕**：自动滚动上方区域腾出空间
3. **广播通道滞后**：`poll_draw_event()` 将 `Lagged` 错误映射为 `Draw` 事件

### 改进建议

1. **配置化帧率限制**
   - 当前硬编码 120 FPS，可考虑根据终端性能或用户偏好调整

2. **更好的错误恢复**
   - `restore()` 中的错误被忽略，可添加日志记录

3. **Windows 挂起支持**
   - 当前仅 Unix 支持 Ctrl+Z 挂起，Windows 可实现类似功能

4. **事件源抽象测试**
   - `FakeEventSource` 已存在，但可扩展以支持更多测试场景

5. **内存优化**
   - `pending_history_lines` 使用 `Vec<Line<'static>>`，在大量历史行时可能占用较多内存
   - 考虑使用环形缓冲区或流式处理
