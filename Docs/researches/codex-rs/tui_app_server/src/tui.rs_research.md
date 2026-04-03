# tui.rs 研究文档

## 场景与职责

`tui.rs` 是 Codex TUI 应用服务器的核心终端用户界面（TUI）管理模块，负责：

1. **终端初始化和恢复**：设置终端为原始模式（raw mode），启用键盘增强、粘贴支持、焦点变化检测等功能
2. **事件流管理**：通过 `EventBroker` 和 `TuiEventStream` 协调键盘输入、绘制事件和系统事件
3. **终端状态切换**：支持内联（inline）和备用屏幕（alternate screen）两种显示模式
4. **外部程序集成**：提供 `with_restored` 机制，在运行外部编辑器（如 vim）时临时恢复终端状态
5. **桌面通知**：在终端失去焦点时发送桌面通知
6. **历史行插入**：支持将历史记录行插入到终端滚动缓冲区

该模块是 TUI 应用与底层终端之间的主要抽象层，封装了 crossterm 和 ratatui 的复杂性。

## 功能点目的

### 1. 终端模式管理

**目的**：配置终端以支持 TUI 的交互需求。

**关键函数**：
- `set_modes()`：启用原始模式、键盘增强标志、粘贴支持、焦点变化检测
- `restore()` / `restore_keep_raw()`：恢复终端到原始状态
- `init()`：初始化终端并验证 stdin/stdout 是否为终端

**键盘增强标志**（KeyboardEnhancementFlags）：
- `DISAMBIGUATE_ESCAPE_CODES`：区分 Escape 序列和普通按键
- `REPORT_EVENT_TYPES`：报告按键事件类型（按下/释放）
- `REPORT_ALTERNATE_KEYS`：报告替代键（带修饰符的按键）

### 2. 备用屏幕管理

**目的**：支持全屏覆盖界面（如帮助、选择器）与内联界面的切换。

**关键方法**：
- `enter_alt_screen()`：进入备用屏幕，扩展视口到全终端大小
- `leave_alt_screen()`：离开备用屏幕，恢复内联视口
- `set_alt_screen_enabled()`：控制备用屏幕功能开关（用于 Zellij 等终端复用器的兼容性）

**备用滚动（Alternate Scroll）**：
- 启用 `ESC[?1007h` 将鼠标滚轮事件转换为方向键，提升滚动体验

### 3. 事件流架构

**目的**：统一管理键盘输入、绘制事件和系统事件。

**核心组件**：
- `EventBroker`：共享的 crossterm 事件源，支持暂停/恢复
- `TuiEventStream`：合并 crossterm 事件和绘制事件的异步流
- `FrameRequester`：请求界面重绘的句柄

**事件类型**（`TuiEvent`）：
- `Key(KeyEvent)`：键盘按键
- `Paste(String)`：粘贴的文本
- `Draw`：绘制请求

### 4. 外部程序集成

**目的**：在 TUI 中启动外部编辑器（如 vim、nano）时避免终端状态冲突。

**实现机制**：
- `pause_events()`：暂停事件流，释放 stdin
- `with_restored()`：临时恢复终端状态，运行外部程序，然后恢复 TUI 状态
- `flush_terminal_input_buffer()`：清除终端输入缓冲区，避免外部程序读取到残留输入

### 5. 桌面通知

**目的**：当终端失去焦点时，通过桌面通知提醒用户新消息。

**实现**：
- 检测终端焦点状态（`FocusGained`/`FocusLost` 事件）
- 使用 `detect_backend()` 检测系统通知后端
- `notify()` 方法在终端未聚焦时发送通知

### 6. 历史行插入

**目的**：将历史记录插入到终端滚动缓冲区，保持内联视口的完整性。

**实现**：
- `insert_history_lines()`：将行插入到视口上方
- 使用 ANSI 滚动区域（scroll region）控制插入位置
- 支持视口自动调整以适应插入的行

## 具体技术实现

### 数据结构

```rust
pub struct Tui {
    frame_requester: FrameRequester,           // 帧请求器
    draw_tx: broadcast::Sender<()>,           // 绘制事件广播通道
    event_broker: Arc<EventBroker>,           // 事件代理
    terminal: Terminal,                        // 自定义终端
    pending_history_lines: Vec<Line<'static>>, // 待插入的历史行
    alt_saved_viewport: Option<Rect>,         // 备用屏幕保存的视口
    #[cfg(unix)]
    suspend_context: SuspendContext,          // Unix 挂起上下文
    alt_screen_active: Arc<AtomicBool>,       // 备用屏幕状态
    terminal_focused: Arc<AtomicBool>,       // 终端焦点状态
    enhanced_keys_supported: bool,            // 键盘增强支持
    notification_backend: Option<DesktopNotificationBackend>, // 通知后端
    alt_screen_enabled: bool,                 // 备用屏幕启用开关
}
```

### 关键流程

#### 终端初始化流程

1. 验证 stdin 和 stdout 是否为终端
2. 调用 `set_modes()` 配置终端
3. 刷新输入缓冲区
4. 设置 panic hook，确保 panic 时恢复终端
5. 创建 `CustomTerminal` 实例

#### 事件流处理流程

1. `TuiEventStream` 同时监听：
   - `EventBroker` 的 crossterm 事件
   - `draw_tx` 广播通道的绘制事件
   - `resume_events_rx` 的恢复通知（Unix 下还有挂起上下文）

2. 使用轮询（round-robin）策略交替处理绘制事件和输入事件，避免饥饿

#### 备用屏幕切换流程

**进入备用屏幕**：
1. 发送 `EnterAlternateScreen` ANSI 序列
2. 启用备用滚动
3. 保存当前视口
4. 设置视口为全终端大小
5. 清除屏幕

**离开备用屏幕**：
1. 禁用备用滚动
2. 发送 `LeaveAlternateScreen` ANSI 序列
3. 恢复保存的视口

#### 外部程序执行流程

1. 暂停事件流（`pause_events()`）
2. 如果处于备用屏幕，临时离开
3. 恢复终端模式（可能保持原始模式）
4. 执行外部程序
5. 重新设置 TUI 模式
6. 刷新输入缓冲区
7. 如果之前处于备用屏幕，重新进入
8. 恢复事件流（`resume_events()`）

### 平台特定实现

#### Unix

- 使用 `libc::tcflush()` 刷新输入缓冲区
- 支持 `SIGTSTP`（Ctrl+Z）挂起处理
- `SuspendContext` 管理挂起/恢复状态

#### Windows

- 使用 `FlushConsoleInputBuffer()` 刷新输入缓冲区
- 使用 Windows API 处理控制台输入

## 关键代码路径与文件引用

### 内部模块

| 模块 | 文件 | 职责 |
|------|------|------|
| `event_stream` | `tui/event_stream.rs` | 事件流和 EventBroker 实现 |
| `frame_requester` | `tui/frame_requester.rs` | 帧请求和调度 |
| `frame_rate_limiter` | `tui/frame_rate_limiter.rs` | 帧率限制（120 FPS） |
| `job_control` | `tui/job_control.rs` | Unix 作业控制（Ctrl+Z） |

### 依赖文件

| 文件 | 用途 |
|------|------|
| `custom_terminal.rs` | 自定义 Terminal 实现，支持视口管理 |
| `insert_history.rs` | 历史行插入实现 |
| `notifications.rs` | 桌面通知后端检测 |
| `terminal_palette.rs` | 终端调色板管理 |

### 关键常量

```rust
pub(crate) const TARGET_FRAME_INTERVAL: Duration = frame_rate_limiter::MIN_FRAME_INTERVAL; // ~8.33ms (120 FPS)
```

### 类型别名

```rust
pub type Terminal = CustomTerminal<CrosstermBackend<Stdout>>;
```

## 依赖与外部交互

### 外部 Crate

| Crate | 用途 |
|-------|------|
| `crossterm` | 跨平台终端控制（模式、事件、光标） |
| `ratatui` | TUI 渲染框架 |
| `tokio` | 异步运行时（broadcast、sync） |
| `tokio-stream` | 异步流支持 |

### 内部依赖

| 模块 | 用途 |
|------|------|
| `codex_core::config::types::NotificationMethod` | 通知方法配置 |

### 系统交互

- **ANSI 转义序列**：控制终端模式、滚动区域、备用屏幕
- **信号处理**（Unix）：`SIGTSTP` 挂起信号
- **桌面通知**：通过系统特定 API 发送通知

## 风险、边界与改进建议

### 已知风险

1. **终端兼容性**：
   - 某些终端（如旧版 Windows 控制台）不支持键盘增强标志
   - 备用滚动支持因终端而异

2. **并发安全**：
   - `alt_screen_active` 和 `terminal_focused` 使用 `Ordering::Relaxed`，在极端情况下可能出现可见性延迟

3. **资源泄漏**：
   - 如果 panic hook 被覆盖，终端可能无法恢复
   - 需要确保 `restore()` 在程序退出时被调用

### 边界条件

1. **终端大小变化**：
   - `pending_viewport_area()` 处理终端大小变化时的视口调整
   - 保持光标位置稳定

2. **事件流竞争**：
   - 多个 `TuiEventStream` 实例同时轮询可能导致事件丢失
   - 设计假设：同一时间只有一个流被轮询

3. **Zellij 兼容性**：
   - `alt_screen_enabled` 标志允许禁用备用屏幕，解决 Zellij 的滚动回退问题

### 改进建议

1. **错误处理**：
   - 当前某些错误被静默忽略（如 `let _ = execute!(...)`），建议增加更详细的日志记录

2. **测试覆盖**：
   - 增加终端模式切换的集成测试
   - 模拟不同终端类型的兼容性测试

3. **性能优化**：
   - 考虑使用 `parking_lot` 替代标准库的锁，减少同步开销

4. **可观测性**：
   - 增加终端状态变化的结构化日志
   - 暴露指标（如帧率、事件处理延迟）

5. **跨平台一致性**：
   - 统一 Unix 和 Windows 的输入缓冲区刷新行为
   - 考虑抽象平台特定的挂起/恢复逻辑
