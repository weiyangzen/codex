# Research: Footer Esc Hint Idle Snapshot

## 场景与职责

此快照展示了在空闲状态下底部栏显示的 Esc 键提示。当用户可以使用 Esc 键编辑上一条消息时，底部栏显示 "esc esc to edit previous message" 提示，告知用户需要连续按两次 Esc 键才能进入编辑模式。

## 功能点目的

- **编辑功能发现**: 提示用户可以使用 Esc 键快速编辑上一条发送的消息
- **防误触设计**: 要求连续按两次 Esc 键，防止单次误触进入编辑模式
- **快捷操作**: 提供比鼠标点击更快的消息编辑方式

## 具体技术实现

当 `FooterProps.esc_backtrack_hint` 为 true 且当前处于空闲状态时：

1. **条件判断**: 检查是否有上一条消息可供编辑
2. **提示显示**: 显示 "esc esc to edit previous message"
3. **状态机管理**: 
   - 首次按下 Esc：进入 `EscHint::Primed` 状态，提示变为 "esc again to edit previous message"
   - 超时未按：恢复到 `EscHint::Idle` 状态
   - 再次按下 Esc：进入消息编辑模式

代码逻辑：
```rust
enum EscHint {
    Idle,
    Primed { expires_at: Instant },
}

// 渲染
match esc_hint {
    EscHint::Idle => "esc esc to edit previous message",
    EscHint::Primed { .. } => "esc again to edit previous message",
}
```

## 关键代码路径与文件引用

- **主要实现**: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
- **状态定义**: `FooterProps.esc_backtrack_hint: bool` 控制是否显示提示
- **Esc 状态**: 内部状态机管理 Esc 键的双击检测
- **编辑模式**: 与消息编辑功能集成

## 依赖与外部交互

- 依赖 `FooterProps.esc_backtrack_hint` 控制提示显示
- 依赖消息历史记录判断是否有可编辑的上一条消息
- 与消息编辑组件交互，触发编辑模式
- 使用超时机制防止状态机卡住

## 风险、边界与改进建议

- **边界情况**: 当没有消息历史时，不应显示此提示
- **改进建议**: 考虑添加可视化倒计时，显示第二次按键的有效时间窗口
- **改进建议**: 支持自定义 Esc 键行为（单次或双击）
- **改进建议**: 当用户首次使用时，可以显示更详细的编辑功能引导
- **改进建议**: 考虑支持编辑任意历史消息，而不仅限于上一条
