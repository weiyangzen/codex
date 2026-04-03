# Research: Footer Shortcuts Default Snapshot

## 场景与职责

此快照展示了底部栏的默认状态，显示 "? for shortcuts" 和 "100% context left"。这是应用启动后或空闲时的标准底部栏外观，提供了最基本的快捷帮助入口和上下文状态信息。

## 功能点目的

- **默认引导**: 为新用户提供发现快捷键的入口
- **状态基线**: 建立底部栏的标准外观，用户可以快速识别应用状态
- **资源监控**: 显示 100% 上下文剩余，表明会话刚开始或资源充足

## 具体技术实现

默认状态下的底部栏渲染：

1. **左侧提示**: 固定显示 "? for shortcuts"
   - 这是用户发现所有快捷键的入口
   - 始终可见，不受其他状态影响
2. **右侧状态**: 显示上下文使用情况
   - 新会话："100% context left"
   - 已使用部分上下文：显示具体百分比或令牌数
3. **中间区域**: 根据当前模式显示不同内容
   - 空闲时：可能显示模式指示器或其他提示
   - 有草稿时：显示队列提示

代码逻辑：
```rust
// 默认/空闲状态渲染
fn render_default_footer(props: &FooterProps) -> Vec<Line> {
    let left = Span::from("? for shortcuts").dim();
    let right = Span::from(&context_window_line(props)).dim();
    
    vec![Line::from(vec![
        left,
        Span::from(" "),
        // 中间内容根据状态变化
        Span::from(" "),
        right,
    ])]
}
```

## 关键代码路径与文件引用

- **主要实现**: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
- **默认模式**: `FooterMode::ComposerEmpty` 或类似的默认状态
- **快捷提示**: "? for shortcuts" 文本定义
- **上下文显示**: `context_window_line()` 函数

## 依赖与外部交互

- 依赖 `FooterProps` 的默认状态
- 依赖会话初始化时的上下文状态
- 与快捷键系统交互，确保 "?" 键能正确触发帮助覆盖层
- 需要响应会话重置事件，恢复默认显示

## 风险、边界与改进建议

- **边界情况**: 确保 "? for shortcuts" 在所有状态下都可见，不能被其他提示完全覆盖
- **改进建议**: 考虑为新用户添加首次使用引导，高亮显示 "?" 快捷键
- **改进建议**: 添加工具提示，当用户悬停在 "? for shortcuts" 上时显示更多帮助信息
- **改进建议**: 考虑在底部栏添加 Codex 版本信息或连接状态指示器
- **改进建议**: 支持自定义默认底部栏内容，允许高级用户配置显示信息
