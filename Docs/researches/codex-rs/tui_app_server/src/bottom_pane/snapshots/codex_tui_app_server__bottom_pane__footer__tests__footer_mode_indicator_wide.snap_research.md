# Research: Footer Mode Indicator Wide Snapshot

## 场景与职责

此快照展示了在宽屏环境下底部栏模式指示器的完整显示状态。此时显示 "? for shortcuts · Plan mode (shift+tab to cycle)" 和 "100% context left"，充分利用可用空间向用户展示完整的协作模式信息和切换提示。

## 功能点目的

- **完整信息展示**: 在宽度充足时显示模式指示器的完整文本，包括切换提示
- **功能发现**: 告知用户可以使用 Shift+Tab 键循环切换协作模式
- **空间优化**: 合理利用宽屏空间，提供更丰富的信息

## 具体技术实现

当底部栏宽度充足时，`single_line_footer_layout` 显示完整的模式指示器：

1. **宽度检查**: 计算可用宽度是否足以显示完整文本
2. **完整格式**: 
   - 基础格式：`"{mode} mode"`
   - 完整格式：`"{mode} mode (shift+tab to cycle)"`
3. **分隔符**: 使用 "·" 连接快捷提示和模式指示器
4. **右对齐**: 上下文信息保持右对齐

代码逻辑：
```rust
fn format_mode_indicator(mode: CollaborationModeIndicator, available_width: u16) -> String {
    let base = format!("{:?} mode", mode);
    let full = format!("{} (shift+tab to cycle)", base);
    
    if (full.width() as u16) <= available_width {
        full
    } else {
        base
    }
}

// 渲染
let mode_text = format_mode_indicator(collaboration_mode, available_width);
let footer_text = format!("? for shortcuts · {} · {}", mode_text, context_line);
```

## 关键代码路径与文件引用

- **主要实现**: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
- **格式化函数**: 模式指示器的格式化逻辑
- **布局函数**: `single_line_footer_layout()` 处理宽度检测和内容选择
- **模式枚举**: `CollaborationModeIndicator` 定义（Plan, PairProgramming, Execute）

## 依赖与外部交互

- 依赖终端宽度信息
- 依赖 `CollaborationModeIndicator` 枚举值
- 与键盘事件系统交互，处理 Shift+Tab 模式切换
- 需要响应终端大小变化事件

## 风险、边界与改进建议

- **边界情况**: 当窗口大小动态变化时，需要平滑过渡显示内容
- **改进建议**: 考虑使用颜色区分不同协作模式（如 Plan 用蓝色，Execute 用绿色）
- **改进建议**: 添加模式切换的动画过渡效果
- **改进建议**: 在模式指示器旁添加当前模式的图标标识
- **改进建议**: 考虑显示当前模式的简短描述提示
