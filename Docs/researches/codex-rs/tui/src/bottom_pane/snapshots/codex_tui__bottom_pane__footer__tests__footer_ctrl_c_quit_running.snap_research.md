# 快照研究文档: footer_ctrl_c_quit_running

## 基本信息
- **快照文件**: `codex_tui__bottom_pane__footer__tests__footer_ctrl_c_quit_running.snap`
- **源文件**: `codex-rs/tui/src/bottom_pane/footer.rs`
- **测试函数**: `footer_snapshots`
- **表达式**: `terminal.backend()`

---

## 场景与职责

### 功能场景
此快照捕获了**任务运行状态下按Ctrl+C后的退出提示**。当用户在有任务运行时按下Ctrl+C，底部栏显示与空闲状态相同的"再次按Ctrl+C退出"提示，但此时退出操作会中断正在运行的任务。

### 业务职责
1. **任务中断确认**: 防止用户意外中断正在运行的任务
2. **退出保护**: 与空闲状态一致的退出确认机制
3. **状态一致性**: 无论任务是否运行，退出快捷键行为保持一致

### 与空闲状态的区别
| 状态 | 再次按Ctrl+C的结果 |
|------|-------------------|
| 空闲 (is_task_running: false) | 直接退出应用 |
| 运行中 (is_task_running: true) | 中断任务，可能需要再次确认退出 |

---

## 功能点目的

### 核心功能
| 功能点 | 目的 | 实现方式 |
|--------|------|----------|
| 退出提示 | 提示再次按键中断/退出 | `quit_shortcut_reminder_line()` |
| 快捷键显示 | 显示Ctrl+C快捷键 | `key_hint::ctrl(KeyCode::Char('c'))` |
| 状态无关 | 提示文本与任务状态无关 | 相同的渲染逻辑 |

### UI内容
```
"  ctrl + c again to quit                                                        "
```

### 与空闲状态快照对比
两个快照（`footer_ctrl_c_quit_idle` 和 `footer_ctrl_c_quit_running`）的渲染输出**完全相同**，区别仅在于内部状态 `is_task_running` 的值。这验证了退出提示的渲染与任务状态无关。

---

## 具体技术实现

### 测试配置对比
```rust
// footer_ctrl_c_quit_idle
FooterProps {
    mode: FooterMode::QuitShortcutReminder,
    is_task_running: false,  // <-- 区别在此
    quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),
    // ...
}

// footer_ctrl_c_quit_running
FooterProps {
    mode: FooterMode::QuitShortcutReminder,
    is_task_running: true,   // <-- 区别在此
    quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),
    // ...
}
```

### 渲染逻辑
```rust
fn footer_from_props_lines(
    props: &FooterProps,
    collaboration_mode_indicator: Option<CollaborationModeIndicator>,
    show_cycle_hint: bool,
    show_shortcuts_hint: bool,
    show_queue_hint: bool,
) -> Vec<Line<'static>> {
    match props.mode {
        FooterMode::QuitShortcutReminder => {
            // 仅依赖 quit_shortcut_key，与 is_task_running 无关
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
| `footer.rs` | 1333-1349 | `footer_ctrl_c_quit_running` 测试配置 |
| `footer.rs` | 1315-1331 | `footer_ctrl_c_quit_idle` 测试配置 |
| `footer.rs` | 593-595 | QuitShortcutReminder 模式处理 |

### 实际行为差异
虽然渲染输出相同，但 `is_task_running` 会影响实际行为：
```rust
// 在 ChatWidget 或 ChatComposer 中
fn handle_ctrl_c(&mut self) {
    if self.is_task_running {
        // 发送中断信号给任务
        self.interrupt_task();
    } else {
        // 直接退出
        self.exit();
    }
}
```

---

## 依赖与外部交互

### 行为差异逻辑
```
用户按Ctrl+C
    ↓
显示 "ctrl + c again to quit"
    ↓
用户再次按Ctrl+C
    ├── is_task_running: false → 直接退出
    └── is_task_running: true  → 中断任务
```

---

## 风险边界与改进建议

### 潜在风险

#### 1. 提示信息不明确
- **问题**: 运行中和空闲状态显示相同的提示
- **影响**: 用户可能不知道再次按Ctrl+C会中断任务
- **建议**: 根据状态显示不同的提示

#### 2. 数据丢失风险
- **问题**: 中断运行中的任务可能导致数据丢失
- **建议**: 添加确认对话框或保存状态

### 改进建议

#### 1. 差异化提示
```rust
fn quit_shortcut_reminder_line(key: KeyBinding, is_task_running: bool) -> Line<'static> {
    let action = if is_task_running {
        "interrupt task"
    } else {
        "quit"
    };
    Line::from(vec![key.into(), format!(" again to {}", action).into()]).dim()
}
```

#### 2. 添加警告
```rust
// 运行中时显示警告
if is_task_running {
    Line::from(vec![
        "⚠️ ".yellow().into(),
        key.into(),
        " again to interrupt running task".into(),
    ]).dim()
}
```

### 测试覆盖分析
- ✅ 运行状态退出提示渲染测试
- ✅ 与空闲状态的对比验证
- ⚠️ 建议添加: 实际行为差异测试（mock任务中断）
