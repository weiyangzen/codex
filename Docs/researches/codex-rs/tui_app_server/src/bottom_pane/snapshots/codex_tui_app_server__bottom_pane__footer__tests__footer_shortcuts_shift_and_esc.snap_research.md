# Research: Footer Shortcuts Shift and Esc Snapshot

## 场景与职责

此快照展示了底部栏显示多行快捷键提示的状态，特别是包含 Shift+Enter 换行提示和 Esc 编辑提示的完整快捷键列表。这种显示模式通常出现在帮助覆盖层或当底部栏需要展示详细操作说明时。

## 功能点目的

- **高级功能发现**: 向用户展示更高级的键盘操作，如 Shift+Enter 换行
- **编辑功能引导**: 提示用户可以使用 Esc 键编辑上一条消息
- **完整操作指南**: 提供比单行提示更详细的操作说明

## 具体技术实现

多行快捷键提示的渲染：

1. **内容组织**: 将快捷键按功能分组显示
   - 发送/换行组：Enter 发送、Shift+Enter 换行
   - 编辑组：Esc Esc 编辑上一条
   - 导航组：Shift+Tab 切换模式
   - 系统组：Ctrl+C 退出、? 帮助
2. **多行布局**: 每行显示一个或一组相关的快捷键
3. **视觉层次**: 使用缩进、颜色或分隔符区分不同组

代码逻辑：
```rust
fn render_detailed_shortcuts() -> Vec<Line> {
    vec![
        Line::from(vec![
            "shift".dim(),
            " + ".dim(),
            "enter".dim(),
            "  New line".into(),
        ]),
        Line::from(vec![
            "esc".dim(),
            " ".into(),
            "esc".dim(),
            "  Edit previous message".into(),
        ]),
        Line::from(vec![
            "shift".dim(),
            " + ".dim(),
            "tab".dim(),
            "  Cycle collaboration mode".into(),
        ]),
        // ... 其他快捷键
    ]
}
```

## 关键代码路径与文件引用

- **主要实现**: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
- **快捷键定义**: 各快捷键的文本和描述定义
- **渲染函数**: 处理多行文本的渲染逻辑
- **样式应用**: 使用 `ratatui` 的 `Stylize` trait 应用样式

## 依赖与外部交互

- 依赖 `ratatui` crate 进行多行文本渲染
- 依赖 `FooterProps.use_shift_enter_hint` 等标志控制提示显示
- 与键盘事件系统交互，确保提示与实际按键行为一致
- 需要处理多行显示时的底部栏高度调整

## 风险、边界与改进建议

- **边界情况**: 多行显示可能需要增加底部栏高度，需要确保不影响主内容区域
- **改进建议**: 添加快捷键搜索功能，允许用户快速查找特定操作
- **改进建议**: 根据用户操作历史，动态调整快捷键的显示顺序（常用优先）
- **改进建议**: 添加快捷键自定义界面，允许用户修改默认快捷键
- **改进建议**: 考虑添加快捷键练习模式，帮助新用户熟悉操作
