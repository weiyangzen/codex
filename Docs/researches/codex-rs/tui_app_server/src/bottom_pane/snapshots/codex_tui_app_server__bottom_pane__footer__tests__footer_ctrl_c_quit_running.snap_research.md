# Research: Footer Ctrl+C Quit Running Snapshot

## 场景与职责

此快照展示了当用户在任务运行状态下首次按下 Ctrl+C 时的底部栏状态。与空闲状态类似，此时显示 "ctrl + c again to quit" 提示，但在运行状态下，第二次 Ctrl+C 可能会触发任务取消而非立即退出应用。

## 功能点目的

- **任务保护**: 在执行任务时防止意外退出导致任务中断
- **取消确认**: 明确告知用户需要再次确认才能取消当前操作
- **状态感知**: 根据应用运行状态（空闲/运行）提供适当的退出行为

## 具体技术实现

当检测到用户按下 Ctrl+C 且当前有任务正在运行时：

1. **状态检测**: 检查 `FooterProps.is_running` 判断是否有任务在执行
2. **模式切换**: 进入 `FooterMode::QuitShortcutReminder` 模式
3. **差异化处理**: 
   - 空闲状态：第二次 Ctrl+C 直接退出应用
   - 运行状态：第二次 Ctrl+C 先取消当前任务，第三次才退出应用
4. **提示显示**: 显示 "ctrl + c again to quit"（与空闲状态相同）

代码逻辑：
```rust
// 事件处理
KeyEvent { code: Char('c'), modifiers: CONTROL } => {
    match footer_mode {
        QuitShortcutReminder { .. } if is_running => {
            // 取消当前任务
            cancel_current_task();
        }
        QuitShortcutReminder { .. } => {
            // 退出应用
            quit_application();
        }
        _ => {
            // 显示退出提示
            set_footer_mode(QuitShortcutReminder { expires_at: ... });
        }
    }
}
```

## 关键代码路径与文件引用

- **主要实现**: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
- **运行状态**: `FooterProps.is_running: bool` 标识是否有任务在执行
- **任务取消**: 与任务管理系统交互取消正在执行的操作
- **事件路由**: 应用主循环中的键盘事件处理逻辑

## 依赖与外部交互

- 依赖 `FooterProps.is_running` 判断当前运行状态
- 依赖任务管理系统的取消接口
- 与空闲状态的退出提示共享相同的 UI 文本，但行为不同
- 需要与后端通信取消正在进行的 AI 请求

## 风险、边界与改进建议

- **边界情况**: 任务取消可能需要时间，需要显示取消中的状态
- **改进建议**: 在运行状态下显示不同的提示文本，如 "ctrl + c again to cancel"
- **改进建议**: 添加任务取消进度指示器
- **改进建议**: 对于长时间运行的任务，考虑添加 "强制退出" 选项
- **改进建议**: 记录用户取消任务的历史，用于优化任务执行策略
