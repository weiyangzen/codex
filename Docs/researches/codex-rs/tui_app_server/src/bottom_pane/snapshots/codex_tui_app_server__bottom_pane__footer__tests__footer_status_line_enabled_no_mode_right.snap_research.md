# Research: Footer Status Line Enabled No Mode Right Snapshot

## 场景与职责

此快照展示了当状态行功能启用但右侧不显示模式指示器时的底部栏状态。状态行区域显示自定义内容，右侧区域保持简洁，可能只显示上下文信息或完全为空。

## 功能点目的

- **简化右侧显示**: 在状态行启用时，选择不在右侧显示模式指示器，保持界面简洁
- **专注状态信息**: 让用户更关注状态行显示的自定义内容
- **灵活配置**: 提供多种布局选项，适应不同用户偏好

## 具体技术实现

当 `FooterProps.status_line_enabled` 为 true 且模式指示器不在右侧时：

1. **左侧区域**: 显示快捷提示和/或模式指示器
   - "? for shortcuts"
   - 可能包含 "Plan mode"
2. **中间区域**: 显示状态行内容
   - 自定义状态文本
3. **右侧区域**: 简化显示
   - 可能只显示 "100% context left"
   - 或完全为空

代码逻辑：
```rust
if props.status_line_enabled && !props.mode_indicator_right {
    let left = if show_mode_left {
        format!("? for shortcuts · {}", mode_indicator)
    } else {
        "? for shortcuts".to_string()
    };
    let center = status_line_content;
    let right = context_window_line();
}
```

## 关键代码路径与文件引用

- **主要实现**: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
- **布局配置**: `FooterProps.mode_indicator_right: bool`
- **状态行内容**: `FooterProps.status_line_content`
- **布局函数**: 处理多种布局配置的渲染逻辑

## 依赖与外部交互

- 依赖 `FooterProps` 中的布局配置
- 依赖状态行内容的提供者（可能是应用的其他模块）
- 与配置系统交互，保存和读取用户偏好
- 需要处理布局切换时的平滑过渡

## 风险、边界与改进建议

- **边界情况**: 当状态行内容为空时，中间区域可能显得空旷
- **改进建议**: 当状态行为空时，可以自动调整布局，将其他内容扩展到中间区域
- **改进建议**: 添加状态行内容的占位符提示，引导用户配置状态信息
- **改进建议**: 支持状态行内容的动态更新频率配置
- **改进建议**: 考虑添加状态行历史记录，显示最近的状态变化
