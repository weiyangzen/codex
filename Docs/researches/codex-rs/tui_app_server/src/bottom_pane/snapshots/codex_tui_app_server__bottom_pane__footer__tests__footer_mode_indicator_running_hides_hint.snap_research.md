# Research: Footer Mode Indicator Running Hides Hint Snapshot

## 场景与职责

此快照展示了当任务正在运行时底部栏模式指示器的显示状态。此时显示 "? for shortcuts · Plan mode" 和 "100% context left"，任务运行状态下的模式指示器会隐藏某些非关键提示，以突出显示运行状态。

## 功能点目的

- **运行状态突出**: 在任务执行期间简化底部栏信息，减少视觉干扰
- **核心信息保留**: 保留快捷提示和模式指示，确保用户仍能访问关键功能
- **上下文监控**: 继续显示上下文使用情况，帮助用户监控资源消耗

## 具体技术实现

当 `FooterProps.is_running` 为 true 时，底部栏调整显示内容：

1. **简化提示**: 隐藏部分非关键提示（如队列提示、Esc 提示等）
2. **保留核心元素**:
   - 左侧："? for shortcuts" 快捷帮助入口
   - 中间：当前协作模式（如 "Plan mode"）
   - 右侧：上下文使用情况（如 "100% context left"）
3. **分隔符使用**: 使用 "·" 分隔不同信息块

代码逻辑：
```rust
if is_running {
    // 简化模式：只显示核心信息
    let left = "? for shortcuts";
    let center = format!("· {}", collaboration_mode);
    let right = context_window_line();
} else {
    // 完整模式：显示所有可用提示
    // ...
}
```

## 关键代码路径与文件引用

- **主要实现**: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
- **运行状态**: `FooterProps.is_running` 控制显示模式
- **模式显示**: `CollaborationModeIndicator` 的显示格式化
- **布局逻辑**: 根据运行状态选择不同的布局策略

## 依赖与外部交互

- 依赖 `FooterProps.is_running` 判断当前运行状态
- 依赖 `FooterProps.collaboration_mode` 获取当前协作模式
- 与任务状态管理系统集成，实时更新运行状态
- 需要响应任务开始/结束事件

## 风险、边界与改进建议

- **边界情况**: 长时间运行的任务可能需要显示进度信息，考虑添加进度条
- **改进建议**: 在运行状态下可以添加动画效果（如旋转器）增强视觉反馈
- **改进建议**: 考虑显示预计剩余时间或已运行时间
- **改进建议**: 添加快速取消按钮或快捷键提示
- **改进建议**: 对于不同类型的任务（如代码生成、文件操作），可以显示不同的状态图标
