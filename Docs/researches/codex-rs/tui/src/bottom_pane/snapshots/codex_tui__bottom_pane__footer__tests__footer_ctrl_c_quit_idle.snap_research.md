# 快照研究文档: footer_ctrl_c_quit_idle

## 基本信息
- **快照文件**: `codex_tui__bottom_pane__footer__tests__footer_ctrl_c_quit_idle.snap`
- **源文件**: `codex-rs/tui/src/bottom_pane/footer.rs`
- **测试函数**: `footer_snapshots`
- **表达式**: `terminal.backend()`

---

## 场景与职责

### 功能场景
此快照捕获了**空闲状态下按Ctrl+C后的退出提示**。当用户在空闲状态（无任务运行）按下Ctrl+C时，底部栏显示"再次按Ctrl+C退出"的提示，防止误操作导致意外退出。

### 业务职责
1. **防误触保护**: 防止用户意外退出应用
2. **退出确认**: 要求用户明确确认退出意图
3. **状态提示**: 告知用户当前处于退出确认状态

### 触发条件
- `mode: FooterMode::QuitShortcutReminder` - 退出快捷键提醒模式
- `quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c'))` - 退出键为Ctrl+C
- `is_task_running: false` - 空闲状态

---

## 功能点目的

### 核心功能
| 功能点 | 目的 | 实现方式 |
|--------|------|----------|
| 退出提示 | 提示再次按键退出 | `quit_shortcut_reminder_line()` |
| 快捷键显示 | 显示Ctrl+C快捷键 | `key_hint::ctrl()` |
| 暗淡样式 | 提示信息使用暗淡样式 | `.dim()` |

### UI内容
```
"  ctrl + c again to quit                                                        "
  └─ 2空格缩进  └─ 退出提示 ─────────────────────────────────────────────────────
```

### 退出流程
```
用户按Ctrl+C（空闲状态）
    ↓
显示 "ctrl + c again to quit"
    ↓
用户再次按Ctrl+C → 退出应用
用户按其他键 → 取消退出提示
```

---

## 具体技术实现

### 退出提示生成
```rust
fn quit_shortcut_reminder_line(key: KeyBinding) -> Line<'static> {
    Line::from(vec![key.into(), " again to quit".into()]).dim()
}
```

### FooterMode定义
```rust
pub(crate) enum FooterMode {
    QuitShortcutReminder,  // <-- 本快照测试的模式
    ShortcutOverlay,
    EscHint,
    ComposerEmpty,
    ComposerHasDraft,
}
```

### 测试配置
```rust
snapshot_footer(
    "footer_ctrl_c_quit_idle",
    FooterProps {
        mode: FooterMode::QuitShortcutReminder,  // <-- 退出提示模式
        esc_backtrack_hint: false,
        use_shift_enter_hint: false,
        is_task_running: false,  // <-- 空闲状态
        collaboration_modes_enabled: false,
        is_wsl: false,
        quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),  // <-- Ctrl+C
        context_window_percent: None,
        context_window_used_tokens: None,
        status_line_value: None,
        status_line_enabled: false,
        active_agent_label: None,
    },
);
```

### 渲染处理
```rust
fn footer_from_props_lines(
    props: &FooterProps,
    // ...
) -> Vec<Line<'static>> {
    match props.mode {
        FooterMode::QuitShortcutReminder => {
            vec![quit_shortcut_reminder_line(props.quit_shortcut_key)]
        }
        // ...
    }
}
```

---

## 关键代码路径与文件引用

### 主要代码位置
| 文件 | 行号范围 | 功能 |
|------|----------|------|
| `footer.rs` | 131-134 | `FooterMode::QuitShortcutReminder` 定义 |
| `footer.rs` | 731-733 | `quit_shortcut_reminder_line()` 函数 |
| `footer.rs` | 593-595 | 退出提示模式处理 |

### 模式切换逻辑
```rust
pub(crate) fn toggle_shortcut_mode(
    current: FooterMode,
    ctrl_c_hint: bool,
    is_empty: bool,
) -> FooterMode {
    if ctrl_c_hint && matches!(current, FooterMode::QuitShortcutReminder) {
        return current;  // 保持退出提示模式
    }
    // ...
}
```

### 测试代码位置
- **测试代码**: `footer.rs` 第 1315-1331 行

---

## 依赖与外部交互

### 依赖模块
| 模块 | 用途 |
|------|------|
| `crate::key_hint` | 快捷键提示渲染 |
| `crossterm::event::KeyCode` | 按键定义 |

### 事件流
```
用户按Ctrl+C
    ↓
ChatWidget/ChatComposer 处理
    ↓
设置 mode = FooterMode::QuitShortcutReminder
    ↓
启动定时器（超时后自动取消）
    ↓
渲染退出提示
    ↓
用户再次按Ctrl+C → 发送 Exit 事件
或用户按其他键 → 重置模式
```

---

## 风险边界与改进建议

### 潜在风险

#### 1. 定时器超时
- **问题**: 退出提示有时间限制，超时后自动消失
- **影响**: 用户可能没注意到提示
- **建议**: 考虑延长超时时间或添加视觉提示

#### 2. 与Ctrl+C中断的混淆
- **问题**: 任务运行时Ctrl+C用于中断，空闲时用于退出
- **影响**: 用户可能混淆两种行为
- **建议**: 添加更明确的提示区分

#### 3. 无障碍性
- **问题**: 仅依赖视觉提示，屏幕阅读器用户可能无法感知
- **建议**: 添加音频提示或屏幕阅读器通知

### 改进建议

#### 1. 添加倒计时
```rust
// 建议: 显示剩余时间
fn quit_shortcut_reminder_line(key: KeyBinding, seconds_left: u8) -> Line<'static> {
    Line::from(vec![
        key.into(),
        format!(" again to quit ({}s)", seconds_left).into(),
    ]).dim()
}
```

#### 2. 视觉强调
```rust
// 建议: 使用更明显的视觉提示
Line::from(vec![
    key.into(),
    " again to ".into(),
    "quit".red().bold(),  // 强调"quit"
]).dim()
```

#### 3. 添加取消提示
```rust
// 建议: 提示如何取消
Line::from(vec![
    key.into(),
    " again to quit".into(),
    " (any other key to cancel)".dim().italic(),
])
```

### 测试覆盖分析
- ✅ 空闲状态退出提示测试
- ✅ 运行状态退出提示测试（`footer_ctrl_c_quit_running`）
- ⚠️ 建议添加: 超时取消测试
- ⚠️ 建议添加: 按键取消测试
