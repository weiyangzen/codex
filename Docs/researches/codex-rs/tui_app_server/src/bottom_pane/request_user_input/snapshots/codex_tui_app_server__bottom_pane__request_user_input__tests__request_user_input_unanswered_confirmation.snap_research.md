# Research: request_user_input_unanswered_confirmation.snap (tui_app_server)

## 场景与职责

本快照文件是 `codex-tui-app-server` crate 中 `request_user_input` 模块的 insta 快照测试结果，验证当用户尝试提交但有未回答问题时显示的确认对话框。

## 功能点目的

### 测试目标
验证未回答问题确认对话框的渲染，包括标题、未回答计数、选项列表和操作提示。

### 快照内容分析
```
Submit with unanswered questions?                                             
2 unanswered questions                                                        
                                                                                
› 1. Proceed  Submit with 2 unanswered questions.                              
  2. Go back  Return to the first unanswered question.                        
                                                                                
                                                                                
                                                                                
                                                                                
Press enter to confirm or esc to go back
```

关键观察点：
1. **确认标题**: `Submit with unanswered questions?`
2. **未回答计数**: `2 unanswered questions`
3. **两个选项**: `Proceed` 和 `Go back`
4. **操作提示**: `Press enter to confirm or esc to go back`

## 具体技术实现

### 确认对话框数据结构

```rust
struct UnansweredConfirmationData {
    title_line: Line<'static>,
    subtitle_line: Line<'static>,
    hint_line: Line<'static>,
    rows: Vec<GenericDisplayRow>,
    state: ScrollState,
}
```

### 打开确认对话框

`open_unanswered_confirmation()` 方法:
```rust
fn open_unanswered_confirmation(&mut self) {
    let mut state = ScrollState::new();
    state.selected_idx = Some(0);
    self.confirm_unanswered = Some(state);
}
```

### 未回答计数计算

`unanswered_count()` 方法:
```rust
fn unanswered_count(&self) -> usize {
    let current_text = self.composer.current_text();
    self.request
        .questions
        .iter()
        .enumerate()
        .filter(|(idx, _)| !self.is_question_answered(*idx, &current_text))
        .count()
}
```

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui_app_server/src/bottom_pane/request_user_input/mod.rs` | 确认对话框逻辑 |
| `codex-rs/tui_app_server/src/bottom_pane/request_user_input/render.rs` | 确认对话框渲染 |

## 风险、边界与改进建议

### 潜在风险
1. **用户困惑**: 用户可能不理解为什么某些问题被认为是"未回答"
2. **强制流程**: 确认对话框可能打断用户的工作流程

### 改进建议
1. **问题列表**: 在确认对话框中显示具体哪些问题的列表
2. **记住选择**: 添加"不再询问"选项
