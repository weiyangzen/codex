# Research: request_user_input_multi_question_last.snap

## 场景与职责

本快照文件是 `codex-tui` crate 中 `request_user_input` 模块的 insta 快照测试结果，验证多问题模式下最后一个问题的 UI 渲染行为。与第一个问题相比，最后一个问题的提交按钮提示不同，且导航提示也有差异。

## 功能点目的

### 测试目标
验证多问题模式下最后一个问题的渲染，特别是 `enter to submit all` 提示的高亮显示，以及 freeform 类型问题的导航提示差异。

### 快照内容分析
```
Question 2/2 (2 unanswered)                                                                                           
Share details.                                                                                                        
                                                                                                                      
› Type your answer (optional)                                                                                          
                                                                                                                      
                                                                                                                      
                                                                                                                      
                                                                                                                      
                                                                                                                      
enter to submit all | ctrl + p / ctrl + n change question | esc to interrupt
```

关键观察点：
1. **问题进度**: `Question 2/2 (2 unanswered)` 显示当前是最后一个问题
2. **Freeform 模式**: 没有选项列表，显示文本输入框
3. **提交提示**: `enter to submit all` (高亮显示，表示将提交所有答案)
4. **导航提示**: `ctrl + p / ctrl + n change question` (freeform 模式使用 Ctrl 组合键)

### 与第一个问题的差异
| 特性 | 第一个问题 | 最后一个问题 |
|------|-----------|-------------|
| 进度 | `Question 1/2` | `Question 2/2` |
| 提交提示 | `enter to submit answer` | `enter to submit all` (高亮) |
| 导航提示 | `←/→ to navigate questions` | `ctrl + p / ctrl + n change question` |
| 问题类型 | Options | Freeform |

## 具体技术实现

### 最后问题检测

```rust
let is_last_question = self.current_index().saturating_add(1) >= question_count;
```

### 提交提示差异

`footer_tips()` 方法 (mod.rs 第444-451行):
```rust
let enter_tip = if question_count == 1 {
    FooterTip::highlighted("enter to submit answer")
} else if is_last_question {
    FooterTip::highlighted("enter to submit all")  // 最后一个问题高亮
} else {
    FooterTip::new("enter to submit answer")  // 非最后问题不高亮
};
```

### Freeform 导航提示

`footer_tips()` 方法中的导航提示 (mod.rs 第452-458行):
```rust
if question_count > 1 {
    if self.has_options() && !self.focus_is_notes() {
        tips.push(FooterTip::new("←/→ to navigate questions"));
    } else if !self.has_options() {
        // Freeform 模式使用 Ctrl+P/N
        tips.push(FooterTip::new("ctrl + p / ctrl + n change question"));
    }
}
```

### 问题切换实现

```rust
fn move_question(&mut self, next: bool) {
    let len = self.question_count();
    if len == 0 {
        return;
    }
    self.save_current_draft();
    let offset = if next { 1 } else { len.saturating_sub(1) };
    self.current_idx = (self.current_idx + offset) % len;
    self.restore_current_draft();
    self.ensure_focus_available();  // 关键：确保焦点状态适合新问题类型
}
```

### Freeform 焦点设置

`ensure_focus_available()` 方法 (mod.rs 第528-543行):
```rust
fn ensure_focus_available(&mut self) {
    if self.question_count() == 0 {
        return;
    }
    if !self.has_options() {
        // Freeform 自动聚焦到 Notes
        self.focus = Focus::Notes;
        if let Some(answer) = self.current_answer_mut() {
            answer.notes_visible = true;
        }
        return;
    }
    // ...
}
```

## 关键代码路径与文件引用

| 文件路径 | 相关代码行 | 说明 |
|---------|-----------|------|
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 444-451 | 提交提示生成逻辑 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 452-458 | 导航提示生成逻辑 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 617-627 | `move_question()` 方法 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 528-543 | `ensure_focus_available()` 方法 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 1015-1042 | Ctrl+P/N 导航处理 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 2850-2872 | 本快照对应的测试用例 |

## 依赖与外部交互

### 测试用例构造

```rust
#[test]
fn request_user_input_multi_question_last_snapshot() {
    let (tx, _rx) = test_sender();
    let mut overlay = RequestUserInputOverlay::new(
        request_event(
            "turn-1",
            vec![
                question_with_options("q1", "Area"),      // 第一个：options
                question_without_options("q2", "Goal"),   // 第二个：freeform
            ],
        ),
        tx,
        true,
        false,
        false,
    );
    overlay.move_question(true);  // 移动到第二个问题
    let area = Rect::new(0, 0, 120, 12);
    insta::assert_snapshot!(
        "request_user_input_multi_question_last",
        render_snapshot(&overlay, area)
    );
}
```

### Ctrl+P/N 键盘处理

```rust
KeyEvent {
    code: KeyCode::Char('p'),
    modifiers: KeyModifiers::CONTROL,
    ..
} | KeyEvent {
    code: KeyCode::PageUp,
    modifiers: KeyModifiers::NONE,
    ..
} => {
    self.move_question(/*next*/ false);  // 上一题
    return;
}
KeyEvent {
    code: KeyCode::Char('n'),
    modifiers: KeyModifiers::CONTROL,
    ..
} | KeyEvent {
    code: KeyCode::PageDown,
    modifiers: KeyModifiers::NONE,
    ..
} => {
    self.move_question(/*next*/ true);  // 下一题
    return;
}
```

## 风险、边界与改进建议

### 潜在风险
1. **提示不一致**: Options 和 Freeform 使用不同的导航方式，用户可能困惑
2. **焦点丢失**: 切换问题类型时焦点状态转换可能出错
3. **提交确认**: 用户可能未意识到 `submit all` 会提交所有问题答案

### 边界情况
1. **快速切换**: 快速连续切换问题可能导致状态混乱
2. **混合编辑**: 在多个问题间编辑后，最终提交的内容可能不符合预期
3. **中断恢复**: 中断后恢复时，多问题的状态恢复复杂性

### 改进建议
1. **统一导航**: 考虑统一使用一种导航方式(如都支持 Ctrl+P/N 和方向键)
2. **提交确认**: 添加确认对话框，显示将要提交的所有答案摘要
3. **问题预览**: 在底部或侧边显示所有问题的回答状态概览
4. **快捷键提示**: 在 UI 中更明显地显示可用的快捷键
