# Research: Footer Status Line Enabled Mode Right Snapshot

## 场景与职责

此快照展示了当状态行功能启用且模式指示器显示在右侧时的底部栏状态。状态行区域显示自定义内容，模式指示器被放置在底部栏右侧，与上下文信息一起显示。

## 功能点目的

- **自定义状态显示**: 允许在底部栏显示应用特定的状态信息
- **灵活布局**: 支持模式指示器在右侧显示，与标准布局不同
- **信息密度**: 在有限空间内显示更多自定义信息

## 具体技术实现

当 `FooterProps.status_line_enabled` 为 true 且模式指示器配置在右侧时：

1. **左侧区域**: 显示快捷提示
   - "? for shortcuts"
2. **中间区域**: 显示状态行内容
   - 自定义状态文本
3. **右侧区域**: 显示模式指示器和上下文信息
   - "Plan mode"
   - "100% context left"

代码逻辑：
```rust
if props.status_line_enabled {
    if props.mode_indicator_right {
        // 模式指示器在右侧
        let left = "? for shortcuts";
        let center = status_line_content;
        let right = format!("{} · {}", mode_indicator, context_line);
    } else {
        // 模式指示器在左侧或中间
        // ...
    }
}
```

## 关键代码路径与文件引用

- **主要实现**: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
- **状态行配置**: `FooterProps.status_line_enabled` 和 `mode_indicator_right`
- **状态内容**: `FooterProps.status_line_content: Option<String>`
- **布局逻辑**: 根据配置选择不同的布局策略

## 依赖与外部交互

- 依赖 `FooterProps` 中的状态行相关配置
- 依赖外部系统提供状态行内容（如文件保存状态、同步状态等）
- 与配置系统交互，读取布局偏好
- 需要响应状态内容的动态更新

## 风险、边界与改进建议

- **边界情况**: 当状态行内容和模式指示器都很长时，可能导致右侧拥挤
- **改进建议**: 添加优先级系统，当空间不足时优先显示更重要的信息
- **改进建议**: 支持状态行内容的滚动显示，处理长文本
- **改进建议**: 添加状态行内容的颜色编码，区分不同类型的状态
- **改进建议**: 支持多个状态项的轮播显示
