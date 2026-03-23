# 研究文档: request_user_input_unanswered_confirmation.snap

## 场景与职责

本快照文件测试 **未答问题确认对话框** 的 UI 渲染。当用户尝试提交但还有未回答的问题时，系统显示确认对话框，让用户选择继续提交或返回补答。

测试用例位于 `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` 第 2875-2898 行。

## 功能点目的

### 核心功能
1. **未答检测**: 检测用户尝试提交时是否有未答问题
2. **确认对话框**: 显示模态对话框让用户确认操作
3. **两个选项**: 
   - "Proceed": 继续提交，未答问题留空
   - "Go back": 返回第一个未答问题
4. **上下文信息**: 显示有多少问题未回答

### 确认对话框交互模型

```
Submit with unanswered questions?
2 unanswered questions

  › 1. Proceed  Submit with 2 unanswered questions.
    2. Go back  Return to the first unanswered question.




Press enter to confirm or esc to go back
```

## 具体技术实现

### 数据结构

```rust
pub(crate) struct RequestUserInputOverlay {
    // ...
    confirm_unanswered: Option<ScrollState>,  // None = 未显示，Some = 显示并跟踪选择
    // ...
}

// 确认对话框中的行数据
struct UnansweredConfirmationData {
    title_line: Line<'static>,
    subtitle_line: Line<'static>,
    hint_line: Line<'static>,
    rows: Vec<GenericDisplayRow>,
    state: ScrollState,
}
```

### 关键流程

1. **触发确认** (`go_next_or_submit`, mod.rs 第 700-711 行):
   ```rust
   fn go_next_or_submit(&mut self) {
       if self.current_index() + 1 >= self.question_count() {
           self.save_current_draft();
           if self.unanswered_count() > 0 {
               self.open_unanswered_confirmation();  // 触发确认
           } else {
               self.submit_answers();
           }
       } else {
           self.move_question(true);
       }
   }
   ```

2. **打开确认对话框** (`open_unanswered_confirmation`, 第 772-776 行):
   ```rust
   fn open_unanswered_confirmation(&mut self) {
       let mut state = ScrollState::new();
       state.selected_idx = Some(0);  // 默认选中 "Proceed"
       self.confirm_unanswered = Some(state);
   }
   ```

3. **生成确认选项** (`unanswered_confirmation_rows`, 第 806-835 行):
   ```rust
   fn unanswered_confirmation_rows(&self) -> Vec<GenericDisplayRow> {
       let entries = [
           (UNANSWERED_CONFIRM_SUBMIT, self.unanswered_submit_description()),
           (UNANSWERED_CONFIRM_GO_BACK, UNANSWERED_CONFIRM_GO_BACK_DESC.to_string()),
       ];
       // 生成 GenericDisplayRow 列表
   }
   ```

4. **处理确认输入** (`handle_confirm_unanswered_key_event`, 第 945-985 行):
   ```rust
   match key_event.code {
       KeyCode::Esc | KeyCode::Backspace => {
           self.close_unanswered_confirmation();
           if let Some(idx) = self.first_unanswered_index() {
               self.jump_to_question(idx);  // 返回第一个未答问题
           }
       }
       KeyCode::Enter => {
           let selected = state.selected_idx.unwrap_or(0);
           self.close_unanswered_confirmation();
           if selected == 0 {
               self.submit_answers();  // 继续提交
           } else {
               self.jump_to_question(self.first_unanswered_index().unwrap());
           }
       }
       // ... 导航处理
   }
   ```

### 渲染输出分析

```
  Submit with unanswered questions?
  2 unanswered questions

  › 1. Proceed  Submit with 2 unanswered questions.
    2. Go back  Return to the first unanswered question.




  Press enter to confirm or esc to go back
```

## 关键代码路径与文件引用

### 主要代码文件

| 文件路径 | 职责 |
|---------|------|
| `mod.rs` | 确认逻辑、输入处理 |
| `render.rs` | 确认对话框渲染 |

### 关键代码位置

1. **触发确认**: `mod.rs:700-711`
2. **打开对话框**: `mod.rs:772-776`
3. **生成选项**: `mod.rs:806-835`
4. **输入处理**: `mod.rs:945-985`
5. **渲染**: `render.rs:117-245`
6. **测试用例**: `mod.rs:2875-2898`

### 常量定义

```rust
// mod.rs:49-54
const UNANSWERED_CONFIRM_TITLE: &str = "Submit with unanswered questions?";
const UNANSWERED_CONFIRM_GO_BACK: &str = "Go back";
const UNANSWERED_CONFIRM_GO_BACK_DESC: &str = "Return to the first unanswered question.";
const UNANSWERED_CONFIRM_SUBMIT: &str = "Proceed";
const UNANSWERED_CONFIRM_SUBMIT_DESC_SINGULAR: &str = "question";
const UNANSWERED_CONFIRM_SUBMIT_DESC_PLURAL: &str = "questions";
```

## 依赖与外部交互

### 未答检测

```rust
fn unanswered_count(&self) -> usize {
    let current_text = self.composer.current_text();
    self.request.questions
        .iter()
        .enumerate()
        .filter(|(idx, _)| !self.is_question_answered(*idx, &current_text))
        .count()
}

fn is_question_answered(&self, idx: usize, _current_text: &str) -> bool {
    let question = self.request.questions.get(idx)?;
    let answer = self.answers.get(idx)?;
    
    let has_options = question.options.as_ref()
        .is_some_and(|options| !options.is_empty());
    
    if has_options {
        answer.options_state.selected_idx.is_some() && answer.answer_committed
    } else {
        answer.answer_committed
    }
}
```

### 第一个未答问题

```rust
fn first_unanswered_index(&self) -> Option<usize> {
    let current_text = self.composer.current_text();
    self.request.questions
        .iter()
        .enumerate()
        .find(|(idx, _)| !self.is_question_answered(*idx, &current_text))
        .map(|(idx, _)| idx)
}
```

## 风险、边界与改进建议

### 潜在风险

1. **用户困惑**: 用户可能不理解 "Proceed" 和 "Go back" 的具体含义
2. **意外提交**: 默认选中 "Proceed" 可能导致意外提交不完整答案
3. **循环陷阱**: 如果所有问题都未答，"Go back" 可能让用户陷入循环

### 边界情况

| 场景 | 行为 |
|------|------|
| 所有问题已答 | 不显示确认，直接提交 |
| 1 个问题未答 | 显示 "1 unanswered question" |
| 多个问题未答 | 显示 "N unanswered questions" |
| 按 Ctrl+C | 发送中断信号 |

### 改进建议

1. **默认选项**: 考虑默认选中 "Go back" 而非 "Proceed"，避免意外提交
2. **问题列表**: 显示具体哪些问题的摘要
3. **答案预览**: 显示已答问题的答案摘要
4. **快捷键**: 添加数字键 1/2 快速选择

### 相关测试

```rust
// 验证未答计数
#[test]
fn skipped_option_questions_count_as_unanswered() {
    // mod.rs:2095-2106
}

// 验证高亮选项仍算未答
#[test]
fn highlighted_option_questions_are_unanswered() {
    // mod.rs:2109-2122
}

// 验证自由文本需要显式提交
#[test]
fn freeform_requires_enter_with_text_to_mark_answered() {
    // mod.rs:2125-2151
}
```

### 代码审查建议

当前确认对话框使用 `Option<ScrollState>` 表示显示状态，可以考虑使用枚举：

```rust
enum OverlayState {
    Normal,
    UnansweredConfirmation { selected: usize },
}

impl RequestUserInputOverlay {
    fn handle_key_event(&mut self, key: KeyEvent) {
        match &self.state {
            OverlayState::Normal => self.handle_normal_key(key),
            OverlayState::UnansweredConfirmation { .. } => {
                self.handle_confirmation_key(key)
            }
        }
    }
}
```
