# Research: request_user_input_multi_question_first.snap

## 场景与职责

本快照文件是 `codex-tui` crate 中 `request_user_input` 模块的 insta 快照测试结果，验证多问题模式下第一个问题的 UI 渲染行为。当一次请求包含多个问题时，UI 需要显示问题导航指示，并允许用户在问题间切换。

## 功能点目的

### 测试目标
验证多问题模式下第一个问题的渲染，包括问题进度指示器、导航提示的正确显示，以及非最后一个问题的提交按钮提示差异。

### 快照内容分析
```
Question 1/2 (2 unanswered)                                                                                           
Choose an option.                                                                                                      
                                                                                                                      
› 1. Option 1  First choice.                                                                                           
  2. Option 2  Second choice.                                                                                          
  3. Option 3  Third choice.                                                                                           
                                                                                                                      
tab to add notes | enter to submit answer | ←/→ to navigate questions | esc to interrupt
```

关键观察点：
1. **问题进度**: `Question 1/2 (2 unanswered)` 显示当前第1个问题，共2个，2个未回答
2. **提交提示**: `enter to submit answer` (非高亮，表示进入下一题而非最终提交)
3. **导航提示**: `←/→ to navigate questions` 显示左右导航可用
4. **未回答计数**: 明确显示还有2个问题未回答

### 与单问题模式的差异
| 特性 | 多问题模式 | 单问题模式 |
|------|-----------|-----------|
| 进度显示 | `Question X/Y` | `Question 1/1` |
| 未回答计数 | 显示 `(N unanswered)` | 显示 `(1 unanswered)` |
| 提交提示 | `enter to submit answer` | `enter to submit answer` |
| 最后问题提示 | `enter to submit all` | - |
| 导航提示 | `←/→` 或 `ctrl+p/n` | 不显示 |

## 具体技术实现

### 问题进度显示

`render_ui()` 方法中的进度渲染 (render.rs 第267-279行):
```rust
let progress_line = if self.question_count() > 0 {
    let idx = self.current_index() + 1;
    let total = self.question_count();
    let base = format!("Question {idx}/{total}");
    if unanswered > 0 {
        Line::from(format!("{base} ({unanswered} unanswered)").dim())
    } else {
        Line::from(base.dim())
    }
} else {
    Line::from("No questions".dim())
};
Paragraph::new(progress_line).render(sections.progress_area, buf);
```

### 提交提示生成

`footer_tips()` 方法中的提示生成 (mod.rs 第442-451行):
```rust
let question_count = self.question_count();
let is_last_question = self.current_index().saturating_add(1) >= question_count;
let enter_tip = if question_count == 1 {
    FooterTip::highlighted("enter to submit answer")
} else if is_last_question {
    FooterTip::highlighted("enter to submit all")  // 最后一个问题
} else {
    FooterTip::new("enter to submit answer")  // 非最后一个问题（如本快照）
};
tips.push(enter_tip);
```

### 问题导航

`move_question()` 方法 (mod.rs 第617-627行):
```rust
fn move_question(&mut self, next: bool) {
    let len = self.question_count();
    if len == 0 {
        return;
    }
    self.save_current_draft();  // 保存当前草稿
    let offset = if next { 1 } else { len.saturating_sub(1) };
    self.current_idx = (self.current_idx + offset) % len;  // 循环导航
    self.restore_current_draft();  // 恢复目标问题草稿
    self.ensure_focus_available();
}
```

### 键盘导航处理

方向键导航 (mod.rs 第1043-1075行):
```rust
KeyEvent {
    code: KeyCode::Char('h'),
    modifiers: KeyModifiers::NONE,
    ..
} if self.has_options() && matches!(self.focus, Focus::Options) => {
    self.move_question(/*next*/ false);  // 左/h：上一题
    return;
}
KeyEvent {
    code: KeyCode::Char('l'),
    modifiers: KeyModifiers::NONE,
    ..
} if self.has_options() && matches!(self.focus, Focus::Options) => {
    self.move_question(/*next*/ true);  // 右/l：下一题
    return;
}
```

## 关键代码路径与文件引用

| 文件路径 | 相关代码行 | 说明 |
|---------|-----------|------|
| `codex-rs/tui/src/bottom_pane/request_user_input/render.rs` | 267-279 | 问题进度渲染 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 430-463 | `footer_tips()` 方法 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 442-458 | 提交提示和导航提示生成 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 617-627 | `move_question()` 方法 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 1043-1075 | 方向键导航处理 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 2827-2848 | 本快照对应的测试用例 |

## 依赖与外部交互

### 答案状态管理

```rust
struct AnswerState {
    options_state: ScrollState,
    draft: ComposerDraft,
    answer_committed: bool,  // 标记是否已提交
    notes_visible: bool,
}
```

### 草稿保存与恢复

```rust
fn save_current_draft(&mut self) {
    let draft = self.capture_composer_draft();
    if let Some(answer) = self.current_answer_mut() {
        if answer.answer_committed && answer.draft != draft {
            answer.answer_committed = false;  // 修改后重置提交状态
        }
        answer.draft = draft;
        if !draft.text.trim().is_empty() {
            answer.notes_visible = true;
        }
    }
}

fn restore_current_draft(&mut self) {
    // 恢复目标问题的草稿到 composer
    let Some(answer) = self.current_answer() else { return };
    let draft = answer.draft.clone();
    self.composer.set_text_content(draft.text, draft.text_elements, draft.local_image_paths);
    // ...
}
```

## 风险、边界与改进建议

### 潜在风险
1. **草稿丢失**: 切换问题时如果保存/恢复逻辑有 bug，可能导致草稿丢失
2. **状态同步**: `answer_committed` 状态可能在复杂操作序列中不同步
3. **循环导航**: 当前实现是循环的(从第一题左移到最后题)，可能不符合用户预期

### 边界情况
1. **大量问题**: 当问题数量很多时，进度显示可能需要调整
2. **混合类型**: options 和 freeform 问题混合时的导航一致性
3. **未回答跳转**: 从确认对话框跳转到第一个未回答问题的准确性

### 改进建议
1. **非循环导航**: 考虑在首尾问题禁用相应方向的导航
2. **问题列表**: 添加问题列表侧边栏，快速跳转
3. **进度保存**: 自动保存草稿到持久化存储，防止意外丢失
4. **视觉区分**: 更明显的视觉区分已回答和未回答问题
