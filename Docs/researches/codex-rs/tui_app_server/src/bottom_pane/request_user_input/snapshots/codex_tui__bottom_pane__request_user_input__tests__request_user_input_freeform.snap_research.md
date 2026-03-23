# Research: request_user_input_freeform.snap

## 场景与职责

本快照文件是 `codex-tui` crate 中 `request_user_input` 模块的 insta 快照测试结果，验证自由文本输入模式(freeform mode)的 UI 渲染行为。当问题没有预定义选项时，用户可以通过文本输入框直接输入答案。

## 功能点目的

### 测试目标
验证当问题不包含选项列表时，UI 正确显示为自由文本输入模式，显示文本输入框和相应的提示信息。

### 快照内容分析
```
Question 1/1 (1 unanswered)                                                                                           
Share details.                                                                                                        
                                                                                                                      
› Type your answer (optional)                                                                                          
                                                                                                                      
                                                                                                                      
                                                                                                                      
enter to submit answer | esc to interrupt
```

关键观察点：
1. **问题进度**: `Question 1/1 (1 unanswered)` 显示单问题模式
2. **问题文本**: `Share details.` 显示问题描述
3. **输入占位符**: `› Type your answer (optional)` 提示用户可以输入可选答案
4. **简洁底部栏**: 只有 `enter to submit answer | esc to interrupt` 两个操作提示
5. **无选项区域**: 不显示选项列表，整个区域用于文本输入

### 与选项模式的区别
| 特性 | Freeform 模式 | Options 模式 |
|------|--------------|--------------|
| 选项列表 | 无 | 有 |
| 输入区域 | 始终可见 | 按 Tab 切换 |
| 占位符文本 | "Type your answer (optional)" | "Add notes" / "Select an option to add notes" |
| 导航提示 | ctrl + p / ctrl + n | ←/→ |

## 具体技术实现

### 关键常量定义

```rust
const NOTES_PLACEHOLDER: &str = "Add notes";
const ANSWER_PLACEHOLDER: &str = "Type your answer (optional)";
const SELECT_OPTION_PLACEHOLDER: &str = "Select an option to add notes";
```

### 占位符选择逻辑

`notes_placeholder()` 方法 (第402-410行):
```rust
fn notes_placeholder(&self) -> &'static str {
    if self.has_options() && self.selected_option_index().is_none() {
        SELECT_OPTION_PLACEHOLDER
    } else if self.has_options() {
        NOTES_PLACEHOLDER
    } else {
        ANSWER_PLACEHOLDER  // Freeform 模式使用此占位符
    }
}
```

### Focus 管理

Freeform 模式下自动设置 Focus (第528-537行):
```rust
fn ensure_focus_available(&mut self) {
    if self.question_count() == 0 {
        return;
    }
    if !self.has_options() {
        self.focus = Focus::Notes;  // Freeform 自动聚焦到输入区
        if let Some(answer) = self.current_answer_mut() {
            answer.notes_visible = true;  // 始终显示输入 UI
        }
        return;
    }
    // ...
}
```

### 布局计算

`layout_without_options()` 方法 (第203-221行):
```rust
fn layout_without_options(
    &self,
    available_height: u16,
    question_height: u16,
    notes_pref_height: u16,
    footer_pref: u16,
    question_lines: &mut Vec<String>,
) -> LayoutPlan {
    let required = question_height;
    if required > available_height {
        self.layout_without_options_tight(available_height, question_height, question_lines)
    } else {
        self.layout_without_options_normal(
            available_height,
            question_height,
            notes_pref_height,
            footer_pref,
        )
    }
}
```

## 关键代码路径与文件引用

| 文件路径 | 相关代码行 | 说明 |
|---------|-----------|------|
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 41-42 | 占位符常量定义 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 201-205 | `has_options()` 检查 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 241-248 | `notes_ui_visible()` 判断 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 402-410 | `notes_placeholder()` 方法 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 528-543 | `ensure_focus_available()` 方法 |
| `codex-rs/tui/src/bottom_pane/request_user_input/layout.rs` | 198-279 | Freeform 布局计算 |
| `codex-rs/tui/src/bottom_pane/request_user_input/render.rs` | 61-105 | `desired_height()` 计算 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 2810-2825 | 本快照对应的测试用例 |

## 依赖与外部交互

### 数据结构依赖

**RequestUserInputQuestion** (protocol crate):
```rust
pub struct RequestUserInputQuestion {
    pub id: String,
    pub header: String,
    pub question: String,
    pub is_other: bool,
    pub is_secret: bool,
    pub options: Option<Vec<RequestUserInputQuestionOption>>,  // Freeform 模式为 None
}
```

### 与 ChatComposer 的集成

Freeform 模式复用 `ChatComposer` 组件处理文本输入:
```rust
pub(crate) struct RequestUserInputOverlay {
    composer: ChatComposer,  // 复用聊天输入组件
    // ...
}
```

### 答案提交逻辑

`submit_answers()` 方法中处理 Freeform 答案 (第715-770行):
```rust
fn submit_answers(&mut self) {
    // ...
    let notes = if answer_state.answer_committed {
        answer_state.draft.text_with_pending().trim().to_string()
    } else {
        String::new()
    };
    // Freeform 问题只提交文本内容
    let mut answer_list = Vec::new();
    if !notes.is_empty() {
        answer_list.push(format!("user_note: {notes}"));
    }
    // ...
}
```

## 风险、边界与改进建议

### 潜在风险
1. **空答案处理**: Freeform 模式允许空答案提交，需要确保后端能正确处理空数组
2. **文本长度限制**: 没有明显的文本长度限制，可能导致内存问题
3. **粘贴内容**: 大段粘贴内容可能影响性能

### 边界情况
1. **秘密输入**: `is_secret` 为 true 时，输入应显示为掩码字符(如 `*`)
2. **多问题混合**: 当问题列表中同时包含 options 和 freeform 问题时，导航需要正确处理
3. **高度不足**: 当终端高度不足以显示完整输入框时的处理

### 改进建议
1. **字符计数**: 添加可选的字符计数显示
2. **最大长度限制**: 考虑添加最大输入长度限制
3. **多行支持优化**: 优化多行文本的显示和编辑体验
4. **历史记录**: 考虑支持输入历史记录功能
