# Research: Footer Status Line Overrides Draft Idle Snapshot

## 场景与职责

此快照展示了当状态行内容覆盖草稿提示时的底部栏状态。即使输入框中有草稿内容，状态行显示 "Status line content" 优先于 "tab to queue message" 提示，确保重要的状态信息能够显示。

## 功能点目的

- **状态信息优先**: 确保重要的应用状态信息能够显示，不受其他提示影响
- **提示层级管理**: 定义不同提示的显示优先级
- **信息一致性**: 在空闲状态下保持状态行的可见性

## 具体技术实现

当状态行启用且有草稿内容时的优先级处理：

1. **优先级判断**: 状态行内容优先级 > 草稿队列提示
2. **显示内容**: 显示 "Status line content" 而非 "tab to queue message"
3. **布局调整**: 状态行占据中间区域，其他内容相应调整

代码逻辑：
```rust
// 优先级：status_line > draft_queue_hint > other_hints
let center_content = if let Some(status) = &props.status_line_content {
    status.clone()
} else if props.composer_has_draft && props.queue_hint_enabled {
    "tab to queue message".to_string()
} else {
    // 其他提示或空
    String::new()
};
```

## 关键代码路径与文件引用

- **主要实现**: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
- **优先级逻辑**: 提示显示优先级的判断代码
- **状态行内容**: `FooterProps.status_line_content`
- **草稿状态**: `FooterProps.composer_has_draft`

## 依赖与外部交互

- 依赖 `FooterProps` 中的多个状态字段
- 依赖优先级配置决定显示顺序
- 与草稿检测系统交互，了解输入框状态
- 需要处理优先级冲突时的用户通知

## 风险、边界与改进建议

- **边界情况**: 用户可能因为看不到队列提示而不知道可以按 Tab 键
- **改进建议**: 当状态行覆盖队列提示时，可以短暂显示一个指示器提示用户
- **改进建议**: 添加配置选项，允许用户调整提示优先级
- **改进建议**: 考虑在状态行旁边以较小字体显示被覆盖的提示
- **改进建议**: 当状态行内容更新时，可以临时隐藏状态行显示被覆盖的提示
