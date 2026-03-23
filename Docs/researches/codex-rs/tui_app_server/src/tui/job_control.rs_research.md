# job_control.rs 深度研究文档

## 场景与职责

`job_control.rs` 是 Codex TUI 的 Unix 专用模块，负责处理**进程挂起与恢复**（Job Control）。它实现了 Unix 终端中经典的 `Ctrl+Z`（SIGTSTP）功能，允许用户临时挂起 TUI 进程，返回 shell 执行其他命令，然后再恢复 TUI。

### 核心使用场景

1. **临时返回 Shell**：用户在 TUI 中按 `Ctrl+Z`，进程挂起，回到 shell
2. **恢复 TUI**：用户在 shell 中执行 `fg`，TUI 恢复并继续运行
3. **终端状态恢复**：确保挂起前后终端状态正确（光标位置、备用屏幕等）

### Unix 特有设计

```rust
#[cfg(unix)]
mod job_control;
```

- 仅在 Unix 平台编译（Linux、macOS 等）
- Windows 不支持 Unix 风格的 Job Control

## 功能点目的

### SuspendContext - 挂起上下文协调器

```rust
#[derive(Clone)]
pub struct SuspendContext {
    resume_pending: Arc<Mutex<Option<ResumeAction>>>,
    suspend_cursor_y: Arc<AtomicU16>,
}
```

**核心职责**：
1. **记录恢复意图**：挂起时决定恢复后需要执行的操作
2. **缓存光标位置**：挂起前记录光标行位置，用于恢复时定位
3. **协调状态恢复**：与 `event_stream.rs` 和 `tui.rs` 协作完成恢复流程

### ResumeAction - 恢复动作枚举

```rust
pub(crate) enum ResumeAction {
    RealignInline,  // 重新对齐内联视口
    RestoreAlt,     // 恢复备用屏幕
}
```

**决策逻辑**：
- 挂起时如果在**备用屏幕**（alt screen）：`RestoreAlt`
- 挂起时如果在**内联模式**（inline）：`RealignInline`

### PreparedResumeAction - 准备好的恢复动作

```rust
pub(crate) enum PreparedResumeAction {
    RestoreAltScreen,
    RealignViewport(Rect),
}
```

**与 ResumeAction 的区别**：
- `ResumeAction`：挂起时**捕获**的原始意图
- `PreparedResumeAction`：恢复前**预计算**的具体操作，包含具体参数（如视口矩形）

### SUSPEND_KEY - 挂起快捷键

```rust
pub const SUSPEND_KEY: key_hint::KeyBinding = key_hint::ctrl(KeyCode::Char('z'));
```

- 定义为 `Ctrl+Z`
- 在 `event_stream.rs` 中检测并触发挂起

## 具体技术实现

### 关键流程 1：挂起流程（suspend）

```rust
pub(crate) fn suspend(&self, alt_screen_active: &Arc<AtomicBool>) -> Result<()> {
    if alt_screen_active.load(Ordering::Relaxed) {
        // 1. 离开备用屏幕
        let _ = execute!(stdout(), DisableAlternateScroll);
        let _ = execute!(stdout(), LeaveAlternateScreen);
        self.set_resume_action(ResumeAction::RestoreAlt);
    } else {
        // 2. 内联模式，记录重新对齐
        self.set_resume_action(ResumeAction::RealignInline);
    }
    
    // 3. 移动光标到挂起位置
    let y = self.suspend_cursor_y.load(Ordering::Relaxed);
    let _ = execute!(stdout(), MoveTo(0, y), Show);
    
    // 4. 发送 SIGTSTP
    suspend_process()
}
```

**详细步骤**：

1. **判断当前屏幕模式**：
   - 备用屏幕（如全屏 UI）：需要恢复时重新进入
   - 内联模式（如普通输出）：需要重新对齐视口

2. **记录恢复动作**：
   - 存储到 `resume_pending` Mutex 中
   - 恢复时通过 `prepare_resume_action` 读取

3. **光标定位**：
   - 将光标移动到 `suspend_cursor_y` 记录的位置
   - 确保 shell 提示符出现在正确位置

4. **发送 SIGTSTP**：
   ```rust
   fn suspend_process() -> Result<()> {
       super::restore()?;           // 恢复终端原始状态
       unsafe { libc::kill(0, libc::SIGTSTP) };  // 发送信号
       super::set_modes()?;         // 恢复后重新设置 TUI 模式
       Ok(())
   }
   ```

### 关键流程 2：恢复准备（prepare_resume_action）

```rust
pub(crate) fn prepare_resume_action(
    &self,
    terminal: &mut Terminal,
    alt_saved_viewport: &mut Option<Rect>,
) -> Option<PreparedResumeAction> {
    let action = self.take_resume_action()?;
    match action {
        ResumeAction::RealignInline => {
            // 1. 获取当前光标位置
            let cursor_pos = terminal
                .get_cursor_position()
                .unwrap_or(terminal.last_known_cursor_pos);
            // 2. 创建视口矩形，保持光标锚定
            let viewport = Rect::new(0, cursor_pos.y, 0, 0);
            Some(PreparedResumeAction::RealignViewport(viewport))
        }
        ResumeAction::RestoreAlt => {
            // 1. 更新保存的视口位置
            if let Ok(Position { y, .. }) = terminal.get_cursor_position()
                && let Some(saved) = alt_saved_viewport.as_mut()
            {
                saved.y = y;
            }
            Some(PreparedResumeAction::RestoreAltScreen)
        }
    }
}
```

**恢复策略详解**：

**内联模式恢复**：
- 目标：保持光标位置稳定，避免内容跳跃
- 方法：创建新的视口矩形，y 坐标与光标对齐
- 结果：用户看到的界面与挂起前一致

**备用屏幕恢复**：
- 目标：重新进入备用屏幕，恢复全屏 UI
- 方法：更新保存的视口位置，准备重新进入
- 结果：全屏 UI 重新显示

### 关键流程 3：应用恢复动作（apply）

```rust
impl PreparedResumeAction {
    pub(crate) fn apply(self, terminal: &mut Terminal) -> Result<()> {
        match self {
            PreparedResumeAction::RealignViewport(area) => {
                terminal.set_viewport_area(area);
            }
            PreparedResumeAction::RestoreAltScreen => {
                // 1. 重新进入备用屏幕
                execute!(terminal.backend_mut(), EnterAlternateScreen)?;
                // 2. 启用备用滚动
                execute!(terminal.backend_mut(), EnableAlternateScroll)?;
                // 3. 设置全屏视口
                if let Ok(size) = terminal.size() {
                    terminal.set_viewport_area(Rect::new(0, 0, size.width, size.height));
                    terminal.clear()?;
                }
            }
        }
        Ok(())
    }
}
```

**调用时机**：
- 在 `tui.rs:draw()` 的同步更新块中调用
- 确保在原子操作中完成恢复，避免闪烁

### 光标位置更新

```rust
pub(crate) fn set_cursor_y(&self, value: u16) {
    self.suspend_cursor_y.store(value, Ordering::Relaxed);
}
```

**调用点**（`tui.rs:506-517`）：
```rust
// Update the y position for suspending so Ctrl-Z can place the cursor correctly.
#[cfg(unix)]
{
    let inline_area_bottom = if self.alt_screen_active.load(Ordering::Relaxed) {
        self.alt_saved_viewport
            .map(|r| r.bottom().saturating_sub(1))
            .unwrap_or_else(|| area.bottom().saturating_sub(1))
    } else {
        area.bottom().saturating_sub(1)
    };
    self.suspend_context.set_cursor_y(inline_area_bottom);
}
```

- 每次绘制时更新光标 Y 位置
- 确保挂起时知道光标在哪里

## 关键代码路径与文件引用

### 模块内引用

| 路径 | 用途 |
|------|------|
| `super::DisableAlternateScroll` / `super::EnableAlternateScroll` | 备用屏幕滚动控制 |
| `super::Terminal` | 终端操作 |
| `crate::key_hint` | 快捷键定义 |

### 调用方（外部使用）

| 文件 | 使用方式 |
|------|----------|
| `tui.rs:47` | `use crate::tui::job_control::SuspendContext;` |
| `tui.rs:249` | `suspend_context: SuspendContext` 字段 |
| `tui.rs:280` | `suspend_context: SuspendContext::new()` 初始化 |
| `tui.rs:387-395` | 创建 `TuiEventStream` 时传递 `suspend_context` |
| `tui.rs:460-462` | `prepare_resume_action` 调用 |
| `tui.rs:506-517` | `set_cursor_y` 调用 |
| `event_stream.rs:146` | `suspend_context: crate::tui::job_control::SuspendContext` 字段 |
| `event_stream.rs:241-243` | 检测 `SUSPEND_KEY` 并调用 `suspend` |

### 被调用方（依赖）

| 依赖 | 用途 |
|------|------|
| `crossterm::{cursor, terminal, event}` | 终端控制 |
| `ratatui::{layout, backend}` | 视口管理 |
| `libc` | SIGTSTP 信号 |
| `std::sync::{Arc, Mutex, AtomicU16}` | 线程安全状态 |

### 跨模块调用链

```
用户按 Ctrl+Z
    │
    ▼
event_stream.rs:poll_crossterm_event()
    │ 检测到 SUSPEND_KEY
    ▼
SuspendContext::suspend(&self.alt_screen_active)
    │
    ├─► 如果是备用屏幕：LeaveAlternateScreen
    ├─► 记录 ResumeAction
    ├─► 移动光标到 suspend_cursor_y
    │
    ▼
suspend_process()
    ├─► restore() 恢复终端原始状态
    ├─► libc::kill(0, SIGTSTP) 挂起进程
    │   [用户执行其他 shell 命令]
    ├─► [用户执行 fg]
    └─► set_modes() 恢复 TUI 模式
    │
    ▼
TUI 恢复运行
    │
    ▼
tui.rs:draw()
    ├─► prepare_resume_action()
    │       ├─► 如果是 RealignInline: 计算新视口
    │       └─► 如果是 RestoreAlt: 准备重新进入备用屏幕
    │
    ▼
PreparedResumeAction::apply()
    ├─► RealignViewport: 设置新视口
    └─► RestoreAltScreen: EnterAlternateScreen + EnableAlternateScroll
```

## 依赖与外部交互

### 外部 crate 依赖

```rust
use crossterm::cursor::MoveTo;
use crossterm::cursor::Show;
use crossterm::event::KeyCode;
use crossterm::terminal::{EnterAlternateScreen, LeaveAlternateScreen};
use ratatui::crossterm::execute;
use ratatui::layout::{Position, Rect};
```

### 与 event_stream 的交互

```rust
// event_stream.rs
#[cfg(unix)]
if crate::tui::job_control::SUSPEND_KEY.is_press(key_event) {
    let _ = self.suspend_context.suspend(&self.alt_screen_active);
    return Some(TuiEvent::Draw);  // 触发最后一次绘制
}
```

- `event_stream` 检测挂起键并调用 `suspend`
- 返回 `Draw` 事件确保 UI 在挂起前刷新

### 与 tui.rs 的交互

```rust
// tui.rs 中的协调
tui.rs:460-462: prepare_resume_action()  // 准备恢复
tui.rs:470-472: prepared.apply()         // 应用恢复
tui.rs:506-517: set_cursor_y()           // 更新光标位置
```

- `tui.rs` 持有 `SuspendContext` 并协调恢复流程
- 恢复动作在 `draw()` 的同步更新块中应用

### 信号处理

```rust
unsafe { libc::kill(0, libc::SIGTSTP) };
```

- `kill(0, ...)` 向当前进程组发送信号
- `SIGTSTP`（信号 20）是"终端停止"信号
- 进程默认行为是停止（挂起）直到收到 `SIGCONT`

## 风险、边界与改进建议

### 已知风险

1. **信号安全性**
   - `suspend_process` 在信号发送前后执行终端操作
   - 如果信号在 `restore()` 和 `kill()` 之间到达，可能状态不一致
   - **缓解**：操作顺序经过精心设计，风险较低

2. **Mutex Poisoning**
   - `resume_pending` 使用 `std::sync::Mutex`
   - 如果持有锁时 panic，锁会被 poison
   - **当前处理**：使用 `unwrap_or_else(PoisonError::into_inner)` 继续
   - **风险**：低，但可能导致恢复动作丢失

3. **光标位置过时**
   - `suspend_cursor_y` 在每次绘制时更新
   - 如果绘制和挂起之间有时间差，位置可能不准确
   - **缓解**：时间窗口很小，实际影响有限

4. **平台限制**
   - 仅 Unix 支持，Windows 无此功能
   - 代码通过条件编译隔离，不会导致编译错误

### 边界情况

1. **快速连续挂起/恢复**
   - 如果用户快速按 Ctrl+Z 和 fg
   - 代码通过 `take_resume_action()` 确保恢复动作只执行一次
   - 测试场景：多次挂起不会累积恢复动作

2. **备用屏幕切换时挂起**
   - 用户在备用屏幕和内联模式之间切换时挂起
   - `alt_screen_active` 原子布尔确保状态正确
   - 恢复时根据记录的动作正确处理

3. **终端大小变化时恢复**
   - 挂起期间用户调整终端大小
   - `prepare_resume_action` 使用当前光标位置重新计算视口
   - 适应新的终端尺寸

4. **信号处理程序干扰**
   - 如果其他代码也处理 SIGTSTP
   - 当前实现依赖默认行为，与其他处理程序可能冲突
   - **建议**：文档中说明不与其他 SIGTSTP 处理程序兼容

### 改进建议

1. **原子状态管理**
   - 考虑使用 `tokio::sync::Mutex` 替代 `std::sync::Mutex`
   - 更好地与异步运行时集成
   - 或者使用状态机将操作序列化到单个任务

2. **恢复失败处理**
   - 当前 `apply` 返回 `Result`，但调用方只是简单传递
   - 建议添加恢复失败时的降级策略
   - 例如：如果重新进入备用屏幕失败，尝试内联模式

3. **更精确的光标跟踪**
   - 当前只在绘制时更新光标位置
   - 可考虑在每次光标移动时更新
   - 使用 `crossterm::cursor::position()` 实时查询

4. **测试覆盖**
   - 当前模块无单元测试
   - 建议添加：
     - Mock 终端测试恢复动作生成
     - 集成测试（需要模拟 SIGTSTP）
     - 边界条件测试（快速挂起/恢复）

5. **文档改进**
   - 添加挂起/恢复流程的时序图
   - 说明与 shell job control 的交互
   - 记录已知限制（如不支持 Windows）

6. **可配置快捷键**
   - 当前硬编码 `Ctrl+Z`
   - 可考虑从配置读取，支持用户自定义
   - 注意：SIGTSTP 通常与 Ctrl+Z 绑定，改变快捷键可能需要信号处理调整

### 代码质量评估

| 维度 | 评分 | 说明 |
|------|------|------|
| 平台适配 | ★★★★★ | 条件编译清晰，Unix 专用代码隔离良好 |
| 设计 | ★★★★☆ | 状态管理清晰，但 Mutex 使用可优化 |
| 文档 | ★★★★☆ | 结构体和方法有文档，可添加更多示例 |
| 可测试性 | ★★☆☆☆ | 缺少单元测试，依赖集成测试 |
| 错误处理 | ★★★☆☆ | 多处 `let _ =` 忽略错误，可更严格 |

### 总结

`job_control.rs` 实现了 Unix TUI 应用中**关键但复杂**的功能：
- 正确处理 `Ctrl+Z` 挂起需要协调终端状态、光标位置、屏幕模式
- 恢复流程涉及多个模块协作（`event_stream`、`tui`、本模块）
- 代码结构清晰，但测试覆盖和错误处理有改进空间

作为 Unix 特有的功能模块，它展示了如何在 Rust 中处理底层终端信号和状态管理。
