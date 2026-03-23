# Research: request_user_input_options_notes_visible.snap

## 场景与职责

本快照文件是 `codex-tui` crate 中 `request_user_input` 模块的 insta 快照测试结果，验证当选项的 notes 输入区域可见时的 UI 渲染行为。用户按 Tab 键后，会显示一个文本输入区域供用户添加额外备注。

## 功能点目的

### 测试目标
验证当用户选择选项并打开 notes 输入区域后的 UI 渲染，包括输入框的显示、占位符文本和更新的底部提示。

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
   - 移除了 `esc to interrupt`（因为 ESC 现在用于清除 notes）
3. **焦点指示**: `›` 表示当前焦点在 notes 区域
4. **输入区域**: 多行空白区域供用户输入

### 状态变化对比
| 元素 | Notes 隐藏 | Notes 可见 |
|------|-----------|-----------|
| Notes 区域 | 不显示 | 显示输入框 |
| 占位符 | - | `Add notes` |
| Tab 提示 | `tab to add notes` | `tab or esc to clear notes` |
| ESC 提示 | `esc to interrupt` | 移除 |
| 焦点 | Options | Notes |

## 具体技术实现

### Notes 可见性判断

`notes_ui_visible()` 方法 (mod.rs 第241-248行):
```rust
pub(super) fn notes_ui_visible(&self) -> bool {
    if !self.has_options() {
        return true;  // Freeform 模式始终可见
    }
    let idx = self.current_index();
    self.current_answer()
        .is_some_and(|answer| answer.notes_visible || self.notes_has_content(idx))
}
```

### Tab 键处理

Options 焦点时的 Tab 处理 (mod.rs 第1113-1118行):
```rust
KeyCode::Tab => {
    if self.selected_option_index().is_some() {
        self.focus = Focus::Notes;  // 切换到 Notes 焦点
        self.ensure_selected_for_notes();
    }
}
```

Notes 焦点时的 Tab 处理 (mod.rs 第1140-1142行):
```rust
if self.has_options() && matches!(key_event.code, KeyCode::Tab) {
    self.clear_notes_and_focus_options();  // 清除 notes 并返回 Options
    return;
}
```

### Notes 占位符

`notes_placeholder()` 方法 (mod.rs 第402-410行):
```rust
fn notes_placeholder(&self) -> &'static str {
    if self.has_options() && self.selected_option_index().is_none() {
        SELECT_OPTION_PLACEHOLDER  // "Select an option to add notes"
    } else if self.has_options() {
        NOTES_PLACEHOLDER  // "Add notes"
    } else {
        ANSWER_PLACEHOLDER  // "Type your answer (optional)"
    }
}
```

### 底部提示更新

Notes 可见时的提示变化 (mod.rs 第433-461行):
```rust
fn footer_tips(&self) -> Vec<FooterTip> {
    let mut tips = Vec::new();
    
    if self.has_options() {
        if self.selected_option_index().is_some() && !notes_visible {
            tips.push(FooterTip::highlighted("tab to add notes"));
        }
        if self.selected_option_index().is_some() && notes_visible {
            tips.push(FooterTip::new("tab or esc to clear notes"));  // 变化点
        }
    }
    
    // ...
    
    if !(self.has_options() && notes_visible) {
        tips.push(FooterTip::new("esc to interrupt"));  // Notes 可见时不显示
    }
    tips
}
```

### ESC 在 Notes 中的处理

```rust
if matches!(key_event.code, KeyCode::Esc) {
    if self.has_options() && self.notes_ui_visible() {
        self.clear_notes_and_focus_options();  // 清除 notes 并返回 Options
        return;
    }
    // ... 中断处理
}
```

## 关键代码路径与文件引用

| 文件路径 | 相关代码行 | 说明 |
|---------|-----------|------|
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 241-248 | `notes_ui_visible()` 方法 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 402-410 | `notes_placeholder()` 方法 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 417-428 | `clear_notes_draft()` 方法 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 675-690 | `clear_notes_and_focus_options()` |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 1113-1118 | Tab 键处理（Options 焦点） |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 1140-1142 | Tab 键处理（Notes 焦点） |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 2468-2489 | 本快照对应的测试用例 |

## 依赖与外部交互

### ChatComposer 集成

Notes 区域复用 `ChatComposer` 组件:
```rust
pub(crate) struct RequestUserInputOverlay {
    composer: ChatComposer,  // 用于 notes 输入
    // ...
}
```

Composer 配置:
```rust
let mut composer = ChatComposer::new_with_config(
    has_input_focus,
    app_event_tx.clone(),
    enhanced_keys_supported,
    ANSWER_PLACEHOLDER.to_string(),
    disable_paste_burst,
    ChatComposerConfig::plain_text(),  // 纯文本模式
);
composer.set_footer_hint_override(Some(Vec::new()));  // 禁用默认 footer
```

### 焦点状态枚举

```rust
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Focus {
    Options,  // 选项列表焦点
    Notes,    // Notes 输入焦点
}
```

## 风险、边界与改进建议

### 潜在风险
1. **焦点混淆**: 用户可能不清楚当前焦点在 Options 还是 Notes
2. **ESC 行为变化**: ESC 的行为根据上下文变化，可能导致误操作
3. **内容丢失**: 清除 notes 时没有确认，可能丢失已输入内容

### 边界情况
1. **空 notes 提交**: 打开 notes 但未输入内容就提交
2. **快速切换**: 快速按 Tab 切换可能导致状态不一致
3. **粘贴内容**: 大段粘贴内容到 notes 的显示和性能

### 改进建议
1. **焦点高亮**: 更明显的焦点指示，如边框或背景色变化
2. **内容确认**: 清除非空 notes 前添加确认对话框
3. **字符计数**: 显示 notes 的字符计数
4. **预览模式**: 添加 notes 预览模式，方便查看已输入内容
