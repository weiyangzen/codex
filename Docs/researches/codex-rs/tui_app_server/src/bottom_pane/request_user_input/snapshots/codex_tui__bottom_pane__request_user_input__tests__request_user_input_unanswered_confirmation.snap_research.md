# Research: request_user_input_unanswered_confirmation.snap

## 场景与职责

本快照文件是 `codex-tui` crate 中 `request_user_input` 模块的 insta 快照测试结果，验证当用户尝试提交但有未回答问题时显示的确认对话框。这是为了防止用户意外跳过问题而设计的保护机制。

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
1. **确认标题**: `Submit with unanswered questions?` 明确告知用户状态
2. **未回答计数**: `2 unanswered questions` 显示具体问题数量
3. **两个选项**:
   - `Proceed`: 继续提交（带未回答问题）
   - `Go back`: 返回第一个未回答问题
4. **操作提示**: `Press enter to confirm or esc to go back`

### 触发条件
- 用户按 Enter 尝试提交
- 存在未回答的问题（`unanswered_count() > 0`）
- 不是强制回答所有问题的场景

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

`open_unanswered_confirmation()` 方法 (mod.rs 第772-776行):
```rust
fn open_unanswered_confirmation(&mut self) {
    let mut state = ScrollState::new();
    state.selected_idx = Some(0);  // 默认选中 "Proceed"
    self.confirm_unanswered = Some(state);
}
```

### 未回答计数计算

`unanswered_count()` 方法 (mod.rs 第856-864行):
```rust
fn unanswered_count(&self) -> usize {
    let current_text = self.composer.current_text();
    self.request
        .questions
        .iter()
        .enumerate()
        .filter(|(idx, _question)| !self.is_question_answered(*idx, &current_text))
        .count()
}
```

### 问题回答状态判断

`is_question_answered()` 方法 (mod.rs 第837-853行):
```rust
fn is_question_answered(&self, idx: usize, _current_text: &str) -> bool {
    let Some(question) = self.request.questions.get(idx) else { return false };
    let Some(answer) = self.answers.get(idx) else { return false };
    
    let has_options = question
        .options
        .as_ref()
        .is_some_and(|options| !options.is_empty());
    
    if has_options {
        // Options 问题：需要选中选项且已提交
        answer.options_state.selected_idx.is_some() && answer.answer_committed
    } else {
        // Freeform 问题：需要已提交标记
        answer.answer_committed
    }
}
```

### 确认选项生成

`unanswered_confirmation_rows()` 方法 (mod.rs 第806-835行):
```rust
fn unanswered_confirmation_rows(&self) -> Vec<GenericDisplayRow> {
    let selected = self
        .confirm_unanswered
        .as_ref()
        .and_then(|state| state.selected_idx)
        .unwrap_or(0);
    
    let entries = [
        (
            UNANSWERED_CONFIRM_SUBMIT,  // "Proceed"
            self.unanswered_submit_description(),  // "Submit with N unanswered questions."
        ),
        (
            UNANSWERED_CONFIRM_GO_BACK,  // "Go back"
            UNANSWERED_CONFIRM_GO_BACK_DESC.to_string(),  // "Return to the first unanswered question."
        ),
    ];
    
    entries
        .iter()
        .enumerate()
        .map(|(idx, (label, description))| {
            let prefix = if idx == selected { '›' } else { ' ' };
            let number = idx + 1;
            GenericDisplayRow {
                name: format!("{prefix} {number}. {label}"),
                description: Some(description.clone()),
                ..Default::default()
            }
        })
        .collect()
}
```

### 确认对话框键盘处理

`handle_confirm_unanswered_key_event()` 方法 (mod.rs 第945-985行):
```rust
fn handle_confirm_unanswered_key_event(&mut self, key_event: KeyEvent) {
    match key_event.code {
        KeyCode::Esc | KeyCode::Backspace => {
            self.close_unanswered_confirmation();
            if let Some(idx) = self.first_unanswered_index() {
                self.jump_to_question(idx);  // 跳转到第一个未回答问题
            }
        }
        KeyCode::Enter => {
            let selected = state.selected_idx.unwrap_or(0);
            self.close_unanswered_confirmation();
            if selected == 0 {
                self.submit_answers();  // 继续提交
            } else if let Some(idx) = self.first_unanswered_index() {
                self.jump_to_question(idx);  // 返回
            }
        }
        KeyCode::Char('1') | KeyCode::Char('2') => {
            // 数字键直接选择
            state.selected_idx = Some(idx);
        }
        _ => {}
    }
}
```

## 关键代码路径与文件引用

| 文件路径 | 相关代码行 | 说明 |
|---------|-----------|------|
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 772-776 | `open_unanswered_confirmation()` |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 778-780 | `close_unanswered_confirmation()` |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 806-835 | `unanswered_confirmation_rows()` |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 837-853 | `is_question_answered()` |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 856-864 | `unanswered_count()` |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 945-985 | 确认对话框键盘处理 |
| `codex-rs/tui/src/bottom_pane/request_user_input/render.rs` | 117-169 | 确认对话框渲染 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 2874-2898 | 本快照对应的测试用例 |

## 依赖与外部交互

### 常量定义

```rust
const UNANSWERED_CONFIRM_TITLE: &str = "Submit with unanswered questions?";
const UNANSWERED_CONFIRM_GO_BACK: &str = "Go back";
const UNANSWERED_CONFIRM_GO_BACK_DESC: &str = "Return to the first unanswered question.";
const UNANSWERED_CONFIRM_SUBMIT: &str = "Proceed";
const UNANSWERED_CONFIRM_SUBMIT_DESC_SINGULAR: &str = "question";
const UNANSWERED_CONFIRM_SUBMIT_DESC_PLURAL: &str = "questions";
```

### 提交描述生成

```rust
fn unanswered_submit_description(&self) -> String {
    let count = self.unanswered_question_count();
    let suffix = if count == 1 {
        UNANSWERED_CONFIRM_SUBMIT_DESC_SINGULAR
    } else {
        UNANSWERED_CONFIRM_SUBMIT_DESC_PLURAL
    };
    format!("Submit with {count} unanswered {suffix}.")
}
```

## 风险、边界与改进建议

### 潜在风险
1. **用户困惑**: 用户可能不理解为什么某些问题被认为是"未回答"
2. **强制流程**: 确认对话框可能打断用户的工作流程
3. **状态不一致**: `answer_committed` 标记可能与其他状态不同步

### 边界情况
1. **全部未回答**: 所有问题都未回答时的处理
2. **部分提交**: 复杂操作序列后的状态一致性
3. **快速操作**: 快速连续按键可能绕过确认对话框

### 改进建议
1. **问题列表**: 在确认对话框中显示具体哪些问题的列表
2. **记住选择**: 添加"不再询问"选项
3. **可视化标记**: 在主界面更明显地标记未回答问题
4. **快捷操作**: 提供一键跳转到下一个未回答问题的快捷键
