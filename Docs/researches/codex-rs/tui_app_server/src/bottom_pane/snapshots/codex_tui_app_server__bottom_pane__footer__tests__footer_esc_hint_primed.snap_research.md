# Research: Footer Esc Hint Primed Snapshot

## 场景与职责

此快照展示了当用户首次按下 Esc 键后的底部栏状态。此时底部栏显示 "esc again to edit previous message" 提示，告知用户需要再次按下 Esc 键才能进入上一条消息的编辑模式。这是 Esc 键双击确认机制的中间状态。

## 功能点目的

- **确认提示**: 告知用户第一次 Esc 键已被识别，等待第二次确认
- **超时警告**: 提示用户需要在有效时间内完成第二次按键
- **状态反馈**: 提供清晰的视觉反馈，确认系统已接收到首次按键

## 具体技术实现

当用户首次按下 Esc 键且满足编辑条件时，系统进入 "Primed" 状态：

1. **状态转换**: 从 `EscHint::Idle` 转换到 `EscHint::Primed`
2. **超时设置**: 设置有效时间窗口（如 2 秒）
3. **提示更新**: 显示 "esc again to edit previous message"
4. **后续处理**:
   - 再次按下 Esc：进入消息编辑模式
   - 超时：自动恢复到 `EscHint::Idle` 状态
   - 按下其他键：取消 Primed 状态

代码逻辑：
```rust
// 键盘事件处理
KeyEvent { code: Esc, .. } => {
    match esc_hint_state {
        EscHint::Idle => {
            esc_hint_state = EscHint::Primed { 
                expires_at: Instant::now() + Duration::from_secs(2) 
            };
        }
        EscHint::Primed { .. } => {
            enter_edit_mode();
        }
    }
}

// 渲染逻辑
FooterMode::EscHint { state: EscHint::Primed { .. }, .. } => {
    // 显示 "esc again to edit previous message"
}
```

## 关键代码路径与文件引用

- **主要实现**: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
- **状态枚举**: `EscHint::Primed { expires_at: Instant }` 定义
- **超时检查**: 在渲染循环或事件循环中检查超时
- **编辑触发**: 与消息编辑功能的集成点

## 依赖与外部交互

- 依赖 `Instant` 和 `Duration` 实现超时机制
- 依赖键盘事件系统捕获 Esc 键
- 与消息编辑组件交互，触发编辑界面
- 需要访问消息历史以加载上一条消息内容

## 风险、边界与改进建议

- **边界情况**: 在 Primed 状态下开始新任务或收到新消息时，应自动重置状态
- **改进建议**: 添加视觉倒计时条或动画，显示剩余的有效时间
- **改进建议**: 在 Primed 状态下可以轻微改变底部栏背景色，增强视觉区分
- **改进建议**: 支持按其他键（如 Enter）确认，提供更多交互选择
- **改进建议**: 考虑添加音效反馈，在状态转换时提供听觉提示
