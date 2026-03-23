# 研究文档: request_user_input_multi_question_first.snap

## 场景与职责

本快照文件测试 **多问题场景下的第一个问题** 渲染。验证当请求包含多个问题时，第一个问题的 UI 显示、进度指示和导航提示是否正确。

测试用例位于 `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` 第 2828-2848 行。

## 功能点目的

### 核心功能
1. **进度显示**: 显示当前问题编号和总数（如 "Question 1/2"）
2. **未答计数**: 显示还有多少问题未回答（如 "(2 unanswered)"）
3. **导航提示**: 提供问题间导航的快捷键提示
4. **答案提交提示**: 区分 "submit answer"（单个）和 "submit all"（最后）

### 多问题交互模型

```
Question 1/2 (2 unanswered)  ← 进度和状态
Choose an option.             ← 当前问题

  › 1. Option 1  First choice.  ← 选项列表
    2. Option 2  Second choice.
    3. Option 3  Third choice.

tab to add notes | enter to submit answer | ←/→ to navigate questions | esc to interrupt
                               ↑
                               注意：显示 "submit answer" 而非 "submit all"
```

## 具体技术实现

### 数据结构

```rust
pub(crate) struct RequestUserInputOverlay {
    request: RequestUserInputEvent,  // 包含所有问题
    answers: Vec<AnswerState>,       // 每个问题的答案状态
    current_idx: usize,              // 当前问题索引
    // ...
}

struct AnswerState {
    options_state: ScrollState,      // 选项滚动状态
    draft: ComposerDraft,            // 笔记草稿
    answer_committed: bool,          // 是否已提交答案
    notes_visible: bool,             // 笔记UI是否可见
}
```

### 关键流程

1. **进度行生成** (`render_ui`, render.rs 第 267-278 行):
   ```rust
   let progress_line = if self.question_count() > 0 {
       let idx = self.current_index() + 1;  // 1-based
       let total = self.question_count();
       let base = format!("Question {idx}/{total}");
       if unanswered > 0 {
           Line::from(format!("{base} ({unanswered} unanswered)").dim())
       } else {
           Line::from(base.dim())
       }
   };
   ```

2. **导航提示生成** (`footer_tips`, mod.rs 第 429-462 行):
   ```rust
   let question_count = self.question_count();
   let is_last_question = self.current_index().saturating_add(1) >= question_count;
   
   let enter_tip = if question_count == 1 {
       FooterTip::highlighted("enter to submit answer")
   } else if is_last_question {
       FooterTip::highlighted("enter to submit all")
   } else {
       FooterTip::new("enter to submit answer")  // 非最后一个问题
   };
   
   if question_count > 1 {
       if self.has_options() && !self.focus_is_notes() {
           tips.push(FooterTip::new("←/→ to navigate questions"));
       }
   }
   ```

3. **问题切换** (`move_question`, mod.rs 第 616-626 行):
   ```rust
   fn move_question(&mut self, next: bool) {
       let len = self.question_count();
       if len == 0 { return; }
       
       self.save_current_draft();  // 保存当前草稿
       let offset = if next { 1 } else { len.saturating_sub(1) };
       self.current_idx = (self.current_idx + offset) % len;  // 循环导航
       self.restore_current_draft();  // 恢复目标问题的草稿
       self.ensure_focus_available();
   }
   ```

### 渲染输出

```
  Question 1/2 (2 unanswered)
  Choose an option.

  › 1. Option 1  First choice.
    2. Option 2  Second choice.
    3. Option 3  Third choice.

  tab to add notes | enter to submit answer | ←/→ to navigate questions | esc to interrupt
```

## 关键代码路径与文件引用

### 主要代码文件

| 文件路径 | 职责 |
|---------|------|
| `mod.rs` | 状态管理、问题切换、提示生成 |
| `render.rs` | 进度行渲染 |
| `layout.rs` | 多问题布局计算 |

### 关键代码位置

1. **进度渲染**: `render.rs:267-278`
2. **提示生成**: `mod.rs:429-462`
3. **问题切换**: `mod.rs:616-626`
4. **测试用例**: `mod.rs:2828-2848`
5. **测试数据**: `mod.rs:2828-2835`（混合问题类型）

### 测试数据构造

```rust
request_event(
    "turn-1",
    vec![
        question_with_options("q1", "Area"),      // 第一个：选项类型
        question_without_options("q2", "Goal"),   // 第二个：自由文本类型
    ],
)
```

## 依赖与外部交互

### 答案状态跟踪

```rust
fn is_question_answered(&self, idx: usize, _current_text: &str) -> bool {
    let question = self.request.questions.get(idx)?;
    let answer = self.answers.get(idx)?;
    
    let has_options = question.options.as_ref()
        .is_some_and(|options| !options.is_empty());
    
    if has_options {
        // 选项问题：需要选中选项且已提交
        answer.options_state.selected_idx.is_some() && answer.answer_committed
    } else {
        // 自由文本：需要显式提交
        answer.answer_committed
    }
}
```

### 草稿保存与恢复

```rust
fn save_current_draft(&mut self) {
    let draft = self.capture_composer_draft();
    if let Some(answer) = self.current_answer_mut() {
        answer.draft = draft;
    }
}

fn restore_current_draft(&mut self) {
    if let Some(answer) = self.current_answer() {
        let draft = answer.draft.clone();
        self.composer.set_text_content(draft.text, ...);
    }
}
```

## 风险、边界与改进建议

### 潜在风险

1. **草稿丢失**: 如果切换问题时保存/恢复逻辑有 bug，可能导致用户输入丢失
2. **状态不一致**: `answer_committed` 和 `selected_idx` 可能不一致
3. **循环导航困惑**: 从最后一个问题按 "next" 回到第一个可能让用户困惑

### 边界情况

| 场景 | 行为 |
|------|------|
| 0 个问题 | 显示 "No questions" |
| 1 个问题 | 简化提示，不显示导航 |
| 当前问题已答 | 进度行显示剩余未答数 |
| 所有问题已答 | 不显示未答计数 |

### 改进建议

1. **问题列表预览**: 显示所有问题的缩略列表，让用户了解整体结构
2. **快速跳转**: 添加数字快捷键直接跳转到特定问题
3. **答案摘要**: 在提交前显示所有答案的摘要确认
4. **进度条**: 使用可视化进度条替代纯文本

### 相关测试

```rust
// 验证问题切换时草稿保存
#[test]
fn large_paste_is_preserved_when_switching_questions() {
    // mod.rs:2393-2418
}

// 验证自由文本草稿不自动提交
#[test]
fn freeform_draft_is_not_submitted_without_enter() {
    // mod.rs:2198-2220
}
```

### 代码审查建议

当前 `move_question` 使用循环导航（模运算），可以考虑：

```rust
// 当前：循环导航
self.current_idx = (self.current_idx + offset) % len;

// 替代：边界停止，提供明确的首/尾提示
if next && self.current_idx + 1 < len {
    self.current_idx += 1;
} else if !next && self.current_idx > 0 {
    self.current_idx -= 1;
}
// 并在 UI 中显示 "已经是第一个/最后一个问题"
```
