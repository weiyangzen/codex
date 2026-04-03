# Research: Footer Status Line Yields To Queue Hint Snapshot

## 场景与职责

此快照展示了当状态行内容让位于队列提示时的底部栏状态。显示 "tab to queue message" 和 "100% context left"，当输入框中有草稿内容时，队列提示优先于状态行内容显示，确保用户能够发现队列功能。

## 功能点目的

- **功能发现优先**: 确保用户在输入草稿时能够看到队列功能提示
- **动态优先级**: 根据应用状态动态调整显示内容的优先级
- **用户体验**: 在用户可能需要队列功能时提供及时的提示

## 具体技术实现

队列提示优先于状态行的逻辑：

1. **条件判断**: 当 `composer_has_draft` 为 true 且 `queue_hint_enabled` 为 true 时
2. **优先级调整**: 队列提示优先级 > 状态行内容
3. **显示内容**: 显示 "tab to queue message" 而非状态行内容
4. **恢复机制**: 当草稿被发送或清除后，恢复显示状态行内容

代码逻辑：
```rust
let center_content = if props.composer_has_draft && props.queue_hint_enabled {
    // 队列提示优先
    "tab to queue message".to_string()
} else if let Some(status) = &props.status_line_content {
    // 显示状态行内容
    status.clone()
} else {
    String::new()
};
```

## 关键代码路径与文件引用

- **主要实现**: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
- **优先级逻辑**: 队列提示与状态行的优先级判断
- **草稿状态**: `FooterProps.composer_has_draft`
- **队列提示开关**: `FooterProps.queue_hint_enabled`

## 依赖与外部交互

- 依赖 `FooterProps` 中的草稿和队列提示配置
- 依赖输入框状态检测系统
- 与状态行内容提供者交互，保存被覆盖的状态行内容
- 需要处理草稿状态变化时的显示切换

## 风险、边界与改进建议

- **边界情况**: 重要的状态信息可能因为队列提示而被隐藏
- **改进建议**: 当状态行包含重要信息时，可以短暂显示状态行后再切换回队列提示
- **改进建议**: 添加指示器显示有状态行内容被隐藏，用户可以按键查看
- **改进建议**: 考虑在队列提示旁边以较小字体显示状态行内容
- **改进建议**: 支持用户配置提示优先级，根据个人偏好调整
