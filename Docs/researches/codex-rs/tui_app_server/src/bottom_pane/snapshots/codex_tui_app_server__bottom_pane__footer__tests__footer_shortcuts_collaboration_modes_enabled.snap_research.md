# Research: Footer Shortcuts Collaboration Modes Enabled Snapshot

## 场景与职责

此快照展示了当用户按下 "?" 键后显示的完整快捷键帮助覆盖层，特别是包含协作模式相关命令的多行快捷键列表。这个覆盖层提供了应用所有可用快捷键的详细说明，帮助用户发现和记忆各种功能。

## 功能点目的

- **功能发现**: 向用户展示所有可用的键盘快捷键
- **协作模式支持**: 特别突出显示协作模式相关的快捷键（如模式切换、确认执行等）
- **快速参考**: 提供一个随时可访问的快捷键速查表

## 具体技术实现

当用户按下 "?" 键时，底部栏进入 `FooterMode::ShortcutOverlay` 模式：

1. **模式切换**: 从当前模式切换到 `ShortcutOverlay`
2. **内容生成**: 根据当前配置生成快捷键列表
   - 基础快捷键（发送消息、退出等）
   - 协作模式快捷键（Shift+Tab 切换模式、Enter 确认执行等）
   - 编辑快捷键（Esc 编辑上一条、Ctrl+C 退出等）
3. **多行显示**: 在覆盖层中显示多行快捷键说明
4. **退出方式**: 再次按下 "?" 或 Esc 键退出覆盖层

代码逻辑：
```rust
enum FooterMode {
    ShortcutOverlay,
    // ... other variants
}

fn render_shortcut_overlay() -> Vec<Line> {
    vec![
        Line::from("Shortcuts:"),
        Line::from("  enter      Send message"),
        Line::from("  shift+enter  New line"),
        Line::from("  shift+tab    Cycle collaboration mode"),
        Line::from("  tab          Queue message"),
        Line::from("  esc esc      Edit previous message"),
        Line::from("  ctrl+c       Quit / Cancel"),
        Line::from("  ?            Toggle this help"),
    ]
}
```

## 关键代码路径与文件引用

- **主要实现**: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
- **模式定义**: `FooterMode::ShortcutOverlay` 枚举变体
- **渲染函数**: `render_shortcut_overlay()` 或类似函数生成帮助内容
- **事件处理**: "?" 键的按下/释放检测

## 依赖与外部交互

- 依赖键盘事件系统捕获 "?" 键
- 依赖当前配置决定显示哪些快捷键（如协作模式是否启用）
- 与 `CollaborationModeIndicator` 交互获取当前模式相关的快捷键
- 需要处理覆盖层与底层内容的叠加显示

## 风险、边界与改进建议

- **边界情况**: 当终端高度不足时，可能需要分页或滚动显示快捷键列表
- **改进建议**: 添加搜索功能，允许用户快速查找特定快捷键
- **改进建议**: 根据用户的使用频率，动态调整快捷键的显示顺序
- **改进建议**: 添加快捷键分类（导航、编辑、协作等），提高可读性
- **改进建议**: 支持自定义快捷键显示，允许用户隐藏不常用的快捷键
