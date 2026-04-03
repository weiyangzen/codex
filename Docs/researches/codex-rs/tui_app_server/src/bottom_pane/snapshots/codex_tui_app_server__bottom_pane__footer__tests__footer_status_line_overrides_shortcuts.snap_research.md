# Research: Footer Status Line Overrides Shortcuts Snapshot

## 场景与职责

此快照展示了当状态行内容覆盖快捷提示时的底部栏状态。状态行显示 "Status line content"，优先于其他快捷提示（如 "? for shortcuts" 的展开内容或其他操作提示），确保状态信息在需要时能够突出显示。

## 功能点目的

- **状态信息突出**: 在需要时让状态行内容成为底部栏的焦点
- **临时覆盖**: 允许临时性的状态信息覆盖常规提示
- **重要信息传递**: 确保关键状态更新能够及时传达给用户

## 具体技术实现

状态行覆盖快捷提示的逻辑：

1. **覆盖触发**: 当 `status_line_content` 有值且 `status_line_overrides_shortcuts` 为 true 时
2. **内容替换**: 状态行内容替换常规的快捷提示
3. **恢复机制**: 状态行内容清除后，自动恢复常规提示

代码逻辑：
```rust
let left_content = if props.status_line_overrides_shortcuts && props.status_line_content.is_some() {
    // 状态行覆盖左侧快捷提示区域
    props.status_line_content.clone().unwrap()
} else {
    // 显示常规快捷提示
    "? for shortcuts".to_string()
};

// 中间区域也显示状态行内容
let center_content = props.status_line_content.clone().unwrap_or_default();
```

## 关键代码路径与文件引用

- **主要实现**: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
- **覆盖配置**: `FooterProps.status_line_overrides_shortcuts: bool`
- **状态内容**: `FooterProps.status_line_content`
- **恢复逻辑**: 状态清除后的提示恢复机制

## 依赖与外部交互

- 依赖 `FooterProps` 中的覆盖配置
- 依赖状态行内容的更新机制
- 与提示管理系统交互，保存和恢复被覆盖的提示
- 需要处理覆盖期间的键盘事件（如 Esc 取消覆盖）

## 风险、边界与改进建议

- **边界情况**: 长期覆盖快捷提示可能影响用户发现功能
- **改进建议**: 添加覆盖超时机制，自动恢复常规提示
- **改进建议**: 当状态行覆盖提示时，添加视觉指示器（如闪烁边框）
- **改进建议**: 支持用户按特定键（如 Esc）手动取消状态行覆盖
- **改进建议**: 记录被覆盖提示的历史，允许用户查看错过的提示
