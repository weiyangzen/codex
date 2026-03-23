# Research: request_user_input_options_notes_visible.snap (tui_app_server)

## 场景与职责

本快照文件是 `codex-tui-app-server` crate 中 `request_user_input` 模块的 insta 快照测试结果，验证当选项的 notes 输入区域可见时的 UI 渲染行为。

## 功能点目的

### 测试目标
验证当用户选择选项并打开 notes 输入区域后的 UI 渲染。

### 快照内容分析
```
Question 1/1 (1 unanswered)                                                                                           
Choose an option.                                                                                                      
                                                                                                                      
› 1. Option 1  First choice.                                                                                           
  2. Option 2  Second choice.                                                                                          
  3. Option 3  Third choice.                                                                                           
                                                                                                                      
› Add notes                                                                                                            
                                                                                                                      
                                                                                                                      
                                                                                                                      
                                                                                                                      
                                                                                                                      
tab or esc to clear notes | enter to submit answer
```

关键观察点：
1. **Notes 区域可见**: 显示 `› Add notes` 占位符
2. **底部提示变化**: 
   - 从 `tab to add notes` 变为 `tab or esc to clear notes`
   - 移除了 `esc to interrupt`
3. **焦点指示**: `›` 表示当前焦点在 notes 区域

## 具体技术实现

### Notes 可见性判断

`notes_ui_visible()` 方法:
```rust
pub(super) fn notes_ui_visible(&self) -> bool {
    if !self.has_options() {
        return true;
    }
    let idx = self.current_index();
    self.current_answer()
        .is_some_and(|answer| answer.notes_visible || self.notes_has_content(idx))
}
```

### Tab 键处理

Options 焦点时的 Tab 处理:
```rust
KeyCode::Tab => {
    if self.selected_option_index().is_some() {
        self.focus = Focus::Notes;
        self.ensure_selected_for_notes();
    }
}
```

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui_app_server/src/bottom_pane/request_user_input/mod.rs` | `notes_ui_visible()` 方法 |
| `codex-rs/tui_app_server/src/bottom_pane/request_user_input/mod.rs` | Tab 键处理 |

## 风险、边界与改进建议

### 潜在风险
1. **焦点混淆**: 用户可能不清楚当前焦点在 Options 还是 Notes
2. **内容丢失**: 清除 notes 时没有确认

### 改进建议
1. **焦点高亮**: 更明显的焦点指示
2. **内容确认**: 清除非空 notes 前添加确认对话框
