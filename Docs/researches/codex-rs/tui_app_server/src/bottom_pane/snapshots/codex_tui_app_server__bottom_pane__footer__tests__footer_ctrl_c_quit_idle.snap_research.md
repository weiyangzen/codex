# Research: Footer Ctrl+C Quit Idle Snapshot

## 场景与职责

此快照展示了当用户在空闲状态下首次按下 Ctrl+C 时的底部栏状态。此时底部栏显示 "ctrl + c again to quit" 提示，要求用户再次按下 Ctrl+C 才能退出应用，防止误操作导致的意外退出。

## 功能点目的

- **防误触保护**: 防止用户意外按下 Ctrl+C 导致应用立即退出
- **退出确认**: 要求用户明确确认退出意图
- **状态提示**: 告知用户需要再次按下 Ctrl+C 才能完成退出操作

## 具体技术实现

当检测到用户按下 Ctrl+C 且当前处于空闲状态时，底部栏进入 `FooterMode::QuitShortcutReminder` 模式：

1. **首次检测**: 捕获 Ctrl+C 按键事件
2. **状态切换**: 将 `FooterMode` 切换为 `QuitShortcutReminder`
3. **提示显示**: 在底部栏中央显示 "ctrl + c again to quit"
4. **超时处理**: 如果在一定时间内（如 3 秒）没有再次按下 Ctrl+C，自动恢复之前的模式
5. **二次确认**: 再次按下 Ctrl+C 时执行退出操作

代码逻辑：
```rust
enum FooterMode {
    QuitShortcutReminder { expires_at: Instant },
    // ... other variants
}

// 渲染逻辑
FooterMode::QuitShortcutReminder { .. } => {
    // 显示 "ctrl + c again to quit"
}
```

## 关键代码路径与文件引用

- **主要实现**: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
- **模式定义**: `FooterMode::QuitShortcutReminder` 枚举变体
- **事件处理**: 在应用主循环中处理 Ctrl+C 按键事件
- **超时逻辑**: 使用 `Instant` 和 `Duration` 实现提示超时

## 依赖与外部交互

- 依赖键盘事件系统捕获 Ctrl+C 按键
- 依赖 `FooterMode` 状态管理当前底部栏模式
- 与空闲状态（Idle）关联，在任务运行时有不同的处理方式
- 超时后自动恢复到之前的模式（如 `ComposerEmpty` 或 `ComposerHasDraft`）

## 风险、边界与改进建议

- **边界情况**: 用户可能在提示显示期间开始新操作，需要正确处理模式切换
- **改进建议**: 考虑添加视觉倒计时指示器，显示提示剩余的有效时间
- **改进建议**: 支持按 Esc 键取消退出提示，提供更明确的取消方式
- **改进建议**: 在提示显示期间可以添加轻微的背景色变化，增强视觉提示
- **改进建议**: 考虑记录用户习惯，对频繁使用 Ctrl+C 退出的用户减少确认次数
