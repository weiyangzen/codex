# job_control.rs 深度研究文档

## 场景与职责

`job_control.rs` 是 Codex TUI 的 **Unix 作业控制模块**，专门处理 SIGTSTP（Ctrl+Z）信号和终端挂起/恢复流程。该模块仅在 Unix 平台编译（`#[cfg(unix)]`），核心职责包括：

1. **挂起处理**：捕获 Ctrl+Z 按键，安全地将 TUI 进程挂起到后台
2. **终端状态保存**：记录挂起前的终端状态（备用屏幕、光标位置）
3. **恢复协调**：进程恢复后正确还原终端状态，确保 UI 一致性
4. **光标管理**：在挂起前将光标放置在合适位置，避免终端混乱

这是 TUI 与 Unix shell 作业控制（job control）交互的关键桥梁。

## 功能点目的

### SuspendContext - 挂起上下文协调器
- **Cloneable**：使用 `Arc` 和原子类型，可在多任务间共享
- **状态跟踪**：
  - `resume_pending`：挂起时捕获的恢复意图
  - `suspend_cursor_y`：挂起时的光标行位置

### ResumeAction - 恢复动作类型
- `RealignInline`：内联视口模式，需要重新对齐视口
- `RestoreAlt`：备用屏幕模式，需要重新进入备用屏幕

### PreparedResumeAction - 预计算的恢复动作
- 在同步绘制中应用的视口调整
- 区分备用屏幕恢复和内联视口重新对齐

### SUSPEND_KEY - 挂起快捷键
- **定义**：`Ctrl+Z`（`key_hint::ctrl(KeyCode::Char('z'))`）
- **检测**：在 `event_stream.rs` 的 `map_crossterm_event` 中检查

## 具体技术实现

### 关键数据结构

```rust
/// 挂起上下文（Clone，共享状态）
#[derive(Clone)]
pub struct SuspendContext {
    resume_pending: Arc<Mutex<Option<ResumeAction>>>,
    suspend_cursor_y: Arc<AtomicU16>,
}

/// 恢复动作类型
#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub(crate) enum ResumeAction {
    RealignInline,  // 内联视口重新对齐
    RestoreAlt,     // 备用屏幕恢复
}

/// 预计算的恢复动作（在同步更新中应用）
#[derive(Clone, Debug)]
pub(crate) enum PreparedResumeAction {
    RestoreAltScreen,
    RealignViewport(Rect),
}
```

### 核心流程

#### 1. 挂起流程 (suspend)
```rust
pub(crate) fn suspend(&self, alt_screen_active: &Arc<AtomicBool>) -> Result<()> {
    if alt_screen_active.load(Ordering::Relaxed) {
        // 备用屏幕模式：退出备用屏幕和备用滚动
        let _ = execute!(stdout(), DisableAlternateScroll);
        let _ = execute!(stdout(), LeaveAlternateScreen);
        self.set_resume_action(ResumeAction::RestoreAlt);
    } else {
        // 内联模式：记录需要重新对齐
        self.set_resume_action(ResumeAction::RealignInline);
    }
    
    // 移动光标到挂起位置
    let y = self.suspend_cursor_y.load(Ordering::Relaxed);
    let _ = execute!(stdout(), MoveTo(0, y), Show);
    
    // 发送 SIGTSTP 挂起进程
    suspend_process()
}
```

#### 2. 恢复准备 (prepare_resume_action)
```rust
pub(crate) fn prepare_resume_action(
    &self,
    terminal: &mut Terminal,
    alt_saved_viewport: &mut Option<Rect>,
) -> Option<PreparedResumeAction> {
    let action = self.take_resume_action()?;
    match action {
        ResumeAction::RealignInline => {
            // 基于当前光标位置计算新视口
            let cursor_pos = terminal
                .get_cursor_position()
                .unwrap_or(terminal.last_known_cursor_pos);
            let viewport = Rect::new(0, cursor_pos.y, 0, 0);
            Some(PreparedResumeAction::RealignViewport(viewport))
        }
        ResumeAction::RestoreAlt => {
            // 更新保存的视口 y 坐标
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

#### 3. 应用恢复动作 (PreparedResumeAction::apply)
```rust
pub(crate) fn apply(self, terminal: &mut Terminal) -> Result<()> {
    match self {
        PreparedResumeAction::RealignViewport(area) => {
            terminal.set_viewport_area(area);
        }
        PreparedResumeAction::RestoreAltScreen => {
            // 重新进入备用屏幕
            execute!(terminal.backend_mut(), EnterAlternateScreen)?;
            execute!(terminal.backend_mut(), EnableAlternateScroll)?;
            if let Ok(size) = terminal.size() {
                terminal.set_viewport_area(Rect::new(0, 0, size.width, size.height));
                terminal.clear()?;
            }
        }
    }
    Ok(())
}
```

#### 4. 进程挂起 (suspend_process)
```rust
fn suspend_process() -> Result<()> {
    // 1. 恢复终端到原始状态（否则 shell 会混乱）
    super::restore()?;
    
    // 2. 发送 SIGTSTP 给自己（进程组 0）
    unsafe { libc::kill(0, libc::SIGTSTP) };
    
    // 3. 进程恢复后，重新应用 TUI 终端模式
    super::set_modes()?;
    Ok(())
}
```

### 完整时序流程

```
用户按下 Ctrl+Z
       │
       ▼
event_stream.rs:map_crossterm_event()
检测到 SUSPEND_KEY
       │
       ▼
SuspendContext::suspend()
┌─────────────────────┐
│ 1. 检查 alt_screen  │
│    是：退出备用屏幕  │
│    否：标记 Realign  │
│ 2. 移动光标         │
│ 3. restore()        │
│ 4. kill(SIGTSTP)    │
└─────────────────────┘
       │
       ▼
   进程挂起
       │
       ▼
用户在 shell 执行 fg
       │
       ▼
   进程恢复
       │
       ▼
Tui::draw() 调用 prepare_resume_action()
       │
       ▼
在 synchronized update 中应用 PreparedResumeAction
┌─────────────────────┐
│ RealignInline:      │
│   调整视口位置      │
│ RestoreAlt:         │
│   重新进入备用屏幕  │
└─────────────────────┘
       │
       ▼
   继续正常运行
```

## 关键代码路径与文件引用

### 本文件关键行
| 行号 | 内容 | 说明 |
|-----|------|------|
| 25 | `SUSPEND_KEY` | Ctrl+Z 快捷键定义 |
| 42-48 | `SuspendContext` 结构体 | 核心数据结构 |
| 64-76 | `suspend()` | 挂起主流程 |
| 82-105 | `prepare_resume_action()` | 恢复准备 |
| 132-153 | `ResumeAction` / `PreparedResumeAction` | 动作类型定义 |
| 155-173 | `PreparedResumeAction::apply()` | 应用恢复动作 |
| 175-182 | `suspend_process()` | 发送 SIGTSTP |

### 调用方文件
| 文件 | 使用方式 |
|------|----------|
| `event_stream.rs:241-244` | 检测 Ctrl+Z，调用 `suspend_context.suspend()` |
| `event_stream.rs:145-148` | `TuiEventStream` 持有 `SuspendContext` |
| `tui.rs:279-280` | `Tui` 持有 `suspend_context` |
| `tui.rs:459-462` | `draw()` 中调用 `prepare_resume_action()` |
| `tui.rs:470-472` | 在 `sync_update` 中应用恢复动作 |
| `tui.rs:507-517` | 更新 `suspend_cursor_y` |

### 依赖文件
| 文件 | 依赖内容 |
|------|----------|
| `key_hint.rs` | `KeyBinding`, `ctrl()` 用于定义 SUSPEND_KEY |
| `tui.rs` | `set_modes()`, `restore()`, `Terminal` |

## 依赖与外部交互

### 外部 crate
| Crate | 用途 |
|-------|------|
| `crossterm` | 终端命令（`EnterAlternateScreen`, `LeaveAlternateScreen` 等） |
| `ratatui` | `Terminal`, `Rect`, `Position` |
| `libc` | `kill(0, SIGTSTP)` 发送信号 |

### 平台限制
- **Unix only**：`#[cfg(unix)]` 条件编译
- **Windows**：无此模块，Ctrl+Z 作为普通按键处理

### 与 TUI 其他模块的交互
```
┌─────────────────────────────────────────────────────────────┐
│                      EventStream                            │
│  ┌─────────────┐    ┌─────────────────────────────────────┐ │
│  │ Key Event   │───▶│ 检测 SUSPEND_KEY (Ctrl+Z)           │ │
│  │ (Ctrl+Z)    │    │ 调用 suspend_context.suspend()      │ │
│  └─────────────┘    └─────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                   SuspendContext                            │
│  ┌─────────────────┐      ┌─────────────────────────────┐   │
│  │ suspend()       │─────▶│ 1. 保存状态                 │   │
│  │                 │      │ 2. restore()                │   │
│  │                 │      │ 3. kill(SIGTSTP)            │   │
│  └─────────────────┘      └─────────────────────────────┘   │
│  ┌─────────────────┐      ┌─────────────────────────────┐   │
│  │ prepare_resume  │◀─────│ 在 draw() 中调用            │   │
│  │ _action()       │      │ 返回 PreparedResumeAction   │   │
│  └─────────────────┘      └─────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                      Tui::draw()                            │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ sync_update(|_| {                                   │    │
│  │   prepared_resume.apply(terminal)?;  // 恢复状态    │    │
│  │   // ... 正常绘制                                   │    │
│  │ })                                                  │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

## 风险、边界与改进建议

### 潜在风险

1. **信号安全性**
   - `suspend_process()` 中的 `libc::kill` 是异步信号安全函数，安全
   - 但 `restore()` 在信号前执行，需确保其信号安全
   - 缓解：`crossterm` 命令使用 ANSI 转义序列，是信号安全的

2. **竞态条件**
   - 挂起和恢复之间终端大小可能变化
   - 缓解：`prepare_resume_action()` 在绘制时重新查询光标位置

3. **Poisoned Mutex**
   - `resume_pending` 使用 `std::sync::Mutex`，panic 时可能中毒
   - 缓解：使用 `unwrap_or_else(PoisonError::into_inner)` 恢复

4. **多次挂起**
   - 如果用户在恢复前再次按 Ctrl+Z，行为未定义
   - 缓解：实际不可能，进程已挂起无法接收输入

### 边界情况

| 场景 | 行为 |
|------|------|
| 备用屏幕激活时挂起 | 退出备用屏幕，恢复时重新进入 |
| 内联模式挂起 | 保持内联，恢复时重新对齐视口 |
| 光标位置查询失败 | 使用 `last_known_cursor_pos` 回退 |
| 终端大小变化 | `prepare_resume_action` 使用当前光标位置 |
| 快速 fg/bg 切换 | 每次恢复都重新计算视口 |

### 改进建议

1. **状态验证**
   - 添加挂起前状态验证，确保终端模式正确保存
   - 恢复后验证终端状态，不匹配时警告

2. **更多信号处理**
   - 当前仅处理 SIGTSTP，可考虑处理 SIGWINCH（窗口大小变化）
   - 在挂起期间窗口变化时，恢复后正确调整

3. **可观测性**
   - 添加 tracing span 跟踪挂起/恢复流程
   - 记录恢复动作类型和视口调整

4. **跨平台抽象**
   - 虽然 Windows 无 SIGTSTP，但可考虑模拟类似行为
   - 如最小化窗口时的状态保存/恢复

5. **测试覆盖**
   - 当前无单元测试（依赖终端和信号）
   - 可考虑使用 `insta` 快照测试恢复后的终端状态
   - 添加集成测试验证挂起/恢复流程

6. **错误处理**
   - 当前多处使用 `let _ =` 忽略错误
   - 考虑记录警告日志，帮助诊断终端问题

7. **文档增强**
   - 添加更多时序图说明挂起/恢复流程
   - 说明与 shell job control 的交互细节

### 与 shell job control 的交互

```bash
# 典型使用场景
$ codex
# ... 使用 TUI ...
# 按 Ctrl+Z
^Z
[1]+  Stopped                 codex

$ fg
codex
# TUI 恢复，状态正确
```

关键点：
1. SIGTSTP 默认行为是停止进程组
2. shell 显示作业状态，返回提示符
3. `fg` 命令发送 SIGCONT，进程继续
4. 代码在 `kill(SIGTSTP)` 返回后继续执行（恢复后）
