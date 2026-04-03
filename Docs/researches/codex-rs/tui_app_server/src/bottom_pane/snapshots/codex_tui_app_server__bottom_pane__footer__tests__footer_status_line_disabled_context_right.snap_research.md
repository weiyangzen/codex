# Research: Footer Status Line Disabled Context Right Snapshot

## 场景与职责

此快照展示了当状态行功能被禁用且上下文信息显示在右侧时的底部栏状态。显示 "? for shortcuts · Plan mode (shift+tab to cycle)" 和 "50% context left"，这是标准的底部栏布局，状态行区域不显示自定义内容。

## 功能点目的

- **标准布局**: 展示底部栏的默认布局方式，状态行区域留空或由其他内容填充
- **上下文右置**: 将上下文使用量信息显示在底部栏右侧
- **模式指示**: 在左侧显示当前协作模式

## 具体技术实现

当 `FooterProps.status_line_enabled` 为 false 时的布局：

1. **左侧区域**: 显示快捷提示和模式指示器
   - "? for shortcuts"
   - "· Plan mode (shift+tab to cycle)"
2. **中间区域**: 状态行区域，由于被禁用，显示为空或默认内容
3. **右侧区域**: 显示上下文使用情况
   - "50% context left"

代码逻辑：
```rust
if !props.status_line_enabled {
    // 标准布局
    let left = format!("? for shortcuts · {}", mode_indicator);
    let right = context_window_line();
    // 中间无状态行内容
} else {
    // 状态行启用时的布局
    // ...
}
```

## 关键代码路径与文件引用

- **主要实现**: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
- **状态行开关**: `FooterProps.status_line_enabled: bool`
- **布局函数**: `single_line_footer_layout()` 处理不同配置下的布局
- **上下文显示**: `context_window_line()` 生成右侧内容

## 依赖与外部交互

- 依赖 `FooterProps.status_line_enabled` 配置
- 依赖 `FooterProps.context_tokens_used` 计算上下文显示
- 与配置系统交互，读取用户的状态行偏好设置
- 需要响应配置变更事件

## 风险、边界与改进建议

- **边界情况**: 当状态行被禁用时，中间区域可能显得空旷，可以考虑显示其他有用信息
- **改进建议**: 允许用户自定义状态行禁用时的默认显示内容
- **改进建议**: 在状态行禁用时，可以考虑将上下文信息移到中间显示
- **改进建议**: 添加配置提示，当状态行长期禁用时提醒用户可以启用
- **改进建议**: 支持动态切换状态行显示，无需重启应用
