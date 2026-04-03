# Research: Footer Composer Has Draft Queue Hint Enabled Snapshot

## 场景与职责

此快照展示了当用户在输入框中有草稿内容且启用了队列提示功能时的底部栏状态。当用户正在输入消息但尚未发送时，底部栏会显示 "tab to queue message" 提示，告知用户可以按 Tab 键将当前消息加入队列而不是立即发送。

## 功能点目的

- **队列功能发现**: 提示用户可以使用 Tab 键将消息加入发送队列
- **批量发送支持**: 允许用户准备多条消息然后批量发送，提高多任务处理效率
- **上下文保护**: 右侧显示 "100% context left"，提醒用户当前上下文容量充足

## 具体技术实现

当 `FooterProps` 中的 `composer_has_draft` 为 true 且启用了队列提示时，底部栏进入 `FooterMode::ComposerHasDraft` 模式：

1. **队列提示显示**: 在左侧显示 "tab to queue message" 提示文本
2. **布局优先级**: 队列提示优先于其他状态提示（如代理标签、模式指示器）
3. **宽度自适应**: 使用 `single_line_footer_layout` 根据可用宽度决定是否截断提示

代码逻辑：
```rust
if composer_has_draft && queue_hint_enabled {
    // 显示 "tab to queue message"
}
```

## 关键代码路径与文件引用

- **主要实现**: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
- **模式定义**: `FooterMode::ComposerHasDraft` 枚举变体
- **布局函数**: `single_line_footer_layout()` 处理提示文本的显示优先级
- **提示生成**: 在 `render()` 方法中根据状态生成队列提示

## 依赖与外部交互

- 依赖 `FooterProps.composer_has_draft: bool` 判断是否有草稿内容
- 依赖 `FooterProps.queue_hint_enabled: bool` 控制是否显示队列提示
- 与 `active_agent_label` 互斥显示，队列提示具有更高优先级
- 用户按 Tab 键触发消息入队操作

## 风险、边界与改进建议

- **边界情况**: 当底部栏宽度不足时，队列提示可能被截断，用户可能无法看到完整提示
- **改进建议**: 考虑添加键盘快捷键图标或符号（如 "↹"）替代文字 "tab"，节省空间
- **改进建议**: 当队列中有消息时，可以显示队列数量指示器（如 "3 in queue"）
- **改进建议**: 考虑在首次使用时显示更详细的队列功能引导提示
