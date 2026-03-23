# Research: request_user_input_multi_question_last.snap (tui_app_server)

## 场景与职责

本快照文件是 `codex-tui-app-server` crate 中 `request_user_input` 模块的 insta 快照测试结果，验证多问题模式下最后一个问题的 UI 渲染行为。

## 功能点目的

### 测试目标
验证多问题模式下最后一个问题的渲染，特别是 `enter to submit all` 提示的高亮显示。

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
3. **提交提示**: `enter to submit all` (高亮显示)
4. **导航提示**: `ctrl + p / ctrl + n change question` (freeform 模式使用 Ctrl 组合键)

## 具体技术实现

### 最后问题检测

```rust
let is_last_question = self.current_index().saturating_add(1) >= question_count;
```

### 提交提示差异

`footer_tips()` 方法:
```rust
let enter_tip = if question_count == 1 {
    FooterTip::highlighted("enter to submit answer")
} else if is_last_question {
    FooterTip::highlighted("enter to submit all")  // 最后一个问题高亮
} else {
    FooterTip::new("enter to submit answer")
};
```

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui_app_server/src/bottom_pane/request_user_input/mod.rs` | 提交提示生成逻辑 |
| `codex-rs/tui_app_server/src/bottom_pane/request_user_input/mod.rs` | 导航提示生成逻辑 |

## 风险、边界与改进建议

### 潜在风险
1. **提示不一致**: Options 和 Freeform 使用不同的导航方式
2. **提交确认**: 用户可能未意识到 `submit all` 会提交所有问题答案

### 改进建议
1. **统一导航**: 考虑统一使用一种导航方式
2. **提交确认**: 添加确认对话框，显示将要提交的所有答案摘要
