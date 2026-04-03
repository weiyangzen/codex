# Research: Footer Mode Indicator Narrow Overlap Hides Snapshot

## 场景与职责

此快照展示了当底部栏宽度不足时模式指示器的处理行为。在窄宽度环境下，"Plan mode (shift+tab to cycle)" 文本被截断，只显示部分内容，确保底部栏的核心功能不受影响。

## 功能点目的

- **响应式布局**: 在有限宽度下优雅地处理内容溢出问题
- **信息优先级**: 确保最重要的信息（如快捷提示）优先显示
- **可用性保证**: 即使在窄窗口下，用户仍能获得关键的操作提示

## 具体技术实现

`single_line_footer_layout` 函数实现了基于宽度的自适应布局：

1. **宽度检测**: 计算底部栏可用宽度
2. **内容优先级排序**:
   - 最高优先级：左侧快捷提示（如 "? for shortcuts"）
   - 中等优先级：模式指示器（如 "Plan mode"）
   - 最低优先级：模式切换提示（如 "(shift+tab to cycle)"）
3. **截断策略**:
   - 首先截断模式切换提示
   - 然后截断模式名称的详细说明
   - 保留核心模式标识

代码逻辑：
```rust
fn single_line_footer_layout(width: u16, props: &FooterProps) -> Layout {
    let shortcuts_width = shortcuts_text.width() as u16;
    let context_width = context_text.width() as u16;
    let available = width.saturating_sub(shortcuts_width + context_width + SPACING);
    
    // 根据可用宽度决定显示内容
    let mode_indicator = if available >= full_text_width {
        "Plan mode (shift+tab to cycle)"
    } else if available >= short_text_width {
        "Plan mode"
    } else {
        "" // 完全隐藏
    };
    // ...
}
```

## 关键代码路径与文件引用

- **主要实现**: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
- **布局函数**: `single_line_footer_layout()` 实现宽度自适应逻辑
- **截断处理**: 使用 Unicode 宽度计算确保正确处理多字节字符
- **模式定义**: `CollaborationModeIndicator` 枚举定义可用模式

## 依赖与外部交互

- 依赖终端宽度信息计算可用空间
- 依赖 `unicode-width`  crate 计算字符串显示宽度
- 与 `CollaborationModeIndicator` 交互获取当前模式信息
- 需要响应终端大小变化事件

## 风险、边界与改进建议

- **边界情况**: 当宽度极窄时，可能需要完全隐藏模式指示器，只保留核心提示
- **改进建议**: 添加悬停提示，当模式指示器被截断时显示完整信息
- **改进建议**: 考虑使用图标或缩写代替长文本（如 "P" 代替 "Plan mode"）
- **改进建议**: 实现滚动文本效果，在有限空间内循环显示完整信息
- **改进建议**: 添加最小宽度限制，低于该宽度时切换为简化布局模式
