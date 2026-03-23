# 研究文档: request_user_input_multi_question_last.snap

## 场景与职责

本快照文件测试 **多问题场景下的最后一个问题** 渲染。验证当用户导航到最后一个问题时，UI 提示、提交行为和导航选项的变化。

测试用例位于 `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` 第 2851-2872 行。

## 功能点目的

### 核心功能
1. **提交提示变化**: 最后一个问题显示 "enter to submit all" 而非 "enter to submit answer"
2. **导航提示变化**: 自由文本问题使用 Ctrl+P/N 而非方向键
3. **进度更新**: 显示 "Question 2/2" 表示最后一个问题

### 与第一个问题的关键差异

| 方面 | 第一个问题 | 最后一个问题 |
|------|-----------|-------------|
| 提交提示 | "enter to submit answer" | "enter to submit all" |
| 问题类型 | 选项类型 | 自由文本类型 |
| 导航提示 | ←/→ to navigate | ctrl + p / ctrl + n |
| 进度显示 | "(2 unanswered)" | "(2 unanswered)" |

## 具体技术实现

### 关键流程

1. **提交提示差异化** (`footer_tips`, mod.rs 第 442-450 行):
   ```rust
   let is_last_question = self.current_index().saturating_add(1) >= question_count;
   
   let enter_tip = if question_count == 1 {
       FooterTip::highlighted("enter to submit answer")
   } else if is_last_question {
       FooterTip::highlighted("enter to submit all")  // 关键差异
   } else {
       FooterTip::new("enter to submit answer")
   };
   ```

2. **导航提示差异化** (第 451-457 行):
   ```rust
   if question_count > 1 {
       if self.has_options() && !self.focus_is_notes() {
           tips.push(FooterTip::new("←/→ to navigate questions"));
       } else if !self.has_options() {
           tips.push(FooterTip::new("ctrl + p / ctrl + n change question"));
       }
   }
   ```

3. **问题切换实现** (测试代码第 2866 行):
   ```rust
   overlay.move_question(true);  // 前进到最后一个问题
   ```

### 渲染输出分析

```
  Question 2/2 (2 unanswered)
  Share details.

  › Type your answer (optional)





  enter to submit all | ctrl + p / ctrl + n change question | esc to interrupt
```

关键观察：
- "enter to submit all" 明确表示这将提交所有问题的答案
- 使用 Ctrl+P/N 进行问题导航（因为是自由文本问题）
- 输入区域有更大的垂直空间（没有选项列表）

## 关键代码路径与文件引用

### 主要代码文件

| 文件路径 | 职责 |
|---------|------|
| `mod.rs` | 提示生成逻辑、问题切换 |
| `render.rs` | 渲染实现 |

### 关键代码位置

1. **提交提示逻辑**: `mod.rs:442-450`
2. **导航提示逻辑**: `mod.rs:451-457`
3. **测试用例**: `mod.rs:2851-2872`
4. **问题切换**: `mod.rs:616-626` (`move_question`)

### 测试构造

```rust
let mut overlay = RequestUserInputOverlay::new(
    request_event(
        "turn-1",
        vec![
            question_with_options("q1", "Area"),      // 问题1：选项
            question_without_options("q2", "Goal"),   // 问题2：自由文本
        ],
    ),
    tx,
    true, false, false,
);
overlay.move_question(true);  // 切换到问题2
```

## 依赖与外部交互

### 答案提交流程

```rust
fn go_next_or_submit(&mut self) {
    if self.current_index() + 1 >= self.question_count() {
        // 最后一个问题
        self.save_current_draft();
        if self.unanswered_count() > 0 {
            self.open_unanswered_confirmation();  // 有未答问题时显示确认
        } else {
            self.submit_answers();  // 直接提交
        }
    } else {
        self.move_question(true);  // 前进到下一个问题
    }
}
```

### 未答确认对话框

当最后一个问题提交时，如果还有未答问题，会显示确认对话框：

```rust
fn open_unanswered_confirmation(&mut self) {
    let mut state = ScrollState::new();
    state.selected_idx = Some(0);
    self.confirm_unanswered = Some(state);
}
```

选项：
1. "Proceed" - 提交并保留未答问题为空
2. "Go back" - 返回第一个未答问题

## 风险、边界与改进建议

### 潜在风险

1. **用户困惑**: 用户可能不理解 "submit all" 和 "submit answer" 的区别
2. **意外提交**: 在最后一个问题按 Enter 会提交所有答案，用户可能没准备好
3. **未答确认打断**: 确认对话框可能打断用户流程

### 边界情况

| 场景 | 行为 |
|------|------|
| 最后一个问题已答 | 正常提交所有答案 |
| 最后一个问题未答 | 显示未答确认对话框 |
| 所有问题已答 | 直接提交，无确认 |
| 从最后导航回前 | 使用 Ctrl+P 或 ← |

### 改进建议

1. **提交前摘要**: 在最终提交前显示所有问题和答案的摘要
2. **确认快捷键**: 为 "submit all" 添加不同的快捷键（如 Ctrl+Enter）
3. **视觉强调**: 最后一个问题使用不同的背景色或边框强调
4. **进度完成度**: 显示可视化的完成进度（如 ████████░░ 80%）

### 相关测试

```rust
// 验证未答确认对话框
#[test]
fn request_user_input_unanswered_confirmation_snapshot() {
    // mod.rs:2875-2898
}

// 验证提交行为
#[test]
fn enter_commits_default_selection_on_last_option_question() {
    // mod.rs:1558-1576
}
```

### 代码优化建议

当前 `footer_tips` 方法包含多个条件分支，可以考虑提取为策略模式：

```rust
enum QuestionPosition {
    Only,   // 唯一问题
    First,  // 第一个
    Middle, // 中间
    Last,   // 最后一个
}

impl QuestionPosition {
    fn enter_tip(&self) -> &'static str {
        match self {
            Only | First | Middle => "enter to submit answer",
            Last => "enter to submit all",
        }
    }
    
    fn should_highlight_enter(&self) -> bool {
        matches!(self, Only | Last)
    }
}
```
