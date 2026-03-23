# Research: request_user_input_multi_question_first.snap (tui_app_server)

## 场景与职责

本快照文件是 `codex-tui-app-server` crate 中 `request_user_input` 模块的 insta 快照测试结果，验证多问题模式下第一个问题的 UI 渲染行为。

## 功能点目的

### 测试目标
验证多问题模式下第一个问题的渲染，包括问题进度指示器、导航提示的正确显示。

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
1. **问题进度**: `Question 1/2 (2 unanswered)` 显示当前第1个问题，共2个
2. **提交提示**: `enter to submit answer` (非高亮，表示进入下一题)
3. **导航提示**: `←/→ to navigate questions` 显示左右导航可用

## 具体技术实现

### 问题进度显示

`render_ui()` 方法中的进度渲染:
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
```

### 提交提示生成

`footer_tips()` 方法:
```rust
let question_count = self.question_count();
let is_last_question = self.current_index().saturating_add(1) >= question_count;
let enter_tip = if question_count == 1 {
    FooterTip::highlighted("enter to submit answer")
} else if is_last_question {
    FooterTip::highlighted("enter to submit all")
} else {
    FooterTip::new("enter to submit answer")  // 非最后问题不高亮
};
```

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui_app_server/src/bottom_pane/request_user_input/render.rs` | 问题进度渲染 |
| `codex-rs/tui_app_server/src/bottom_pane/request_user_input/mod.rs` | `footer_tips()` 方法 |

## 风险、边界与改进建议

### 潜在风险
1. **草稿丢失**: 切换问题时如果保存/恢复逻辑有 bug，可能导致草稿丢失
2. **循环导航**: 当前实现是循环的，可能不符合用户预期

### 改进建议
1. **非循环导航**: 考虑在首尾问题禁用相应方向的导航
2. **问题列表**: 添加问题列表侧边栏，快速跳转
