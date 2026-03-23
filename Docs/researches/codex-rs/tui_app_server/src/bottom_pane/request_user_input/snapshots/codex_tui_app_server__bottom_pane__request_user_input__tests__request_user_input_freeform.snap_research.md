# Research: request_user_input_freeform.snap (tui_app_server)

## 场景与职责

本快照文件是 `codex-tui-app-server` crate 中 `request_user_input` 模块的 insta 快照测试结果，验证自由文本输入模式(freeform mode)的 UI 渲染行为。

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

## 具体技术实现

### 关键常量定义

```rust
const NOTES_PLACEHOLDER: &str = "Add notes";
const ANSWER_PLACEHOLDER: &str = "Type your answer (optional)";
const SELECT_OPTION_PLACEHOLDER: &str = "Select an option to add notes";
```

### 占位符选择逻辑

`notes_placeholder()` 方法:
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

Freeform 模式下自动设置 Focus:
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

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui_app_server/src/bottom_pane/request_user_input/mod.rs` | 主模块，包含 Focus 管理和占位符逻辑 |
| `codex-rs/tui_app_server/src/bottom_pane/request_user_input/layout.rs` | Freeform 布局计算 |
| `codex-rs/tui_app_server/src/bottom_pane/request_user_input/render.rs` | 渲染逻辑 |

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

## 风险、边界与改进建议

### 潜在风险
1. **空答案处理**: Freeform 模式允许空答案提交
2. **文本长度限制**: 没有明显的文本长度限制

### 改进建议
1. **字符计数**: 添加可选的字符计数显示
2. **最大长度限制**: 考虑添加最大输入长度限制
