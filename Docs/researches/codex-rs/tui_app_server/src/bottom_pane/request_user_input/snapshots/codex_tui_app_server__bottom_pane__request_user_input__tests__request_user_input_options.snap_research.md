# Research: request_user_input_options.snap (tui_app_server)

## 场景与职责

本快照文件是 `codex-tui-app-server` crate 中 `request_user_input` 模块的 insta 快照测试结果，验证标准选项选择模式的 UI 渲染行为。

## 功能点目的

### 测试目标
验证标准选项选择界面的基本渲染，包括问题显示、选项列表、选中状态标记和底部操作提示。

### 快照内容分析
```
Question 1/1 (1 unanswered)                                                                                           
Choose an option.                                                                                                      
                                                                                                                      
› 1. Option 1  First choice.                                                                                           
  2. Option 2  Second choice.                                                                                          
  3. Option 3  Third choice.                                                                                           
                                                                                                                      
tab to add notes | enter to submit answer | esc to interrupt
```

关键观察点：
1. **默认选中**: 第一个选项默认被选中(显示 `›`)
2. **选项格式**: `编号. 标签  描述` 的标准格式
3. **底部提示**: 三个操作提示用 `|` 分隔

## 具体技术实现

### 选项行构建

`option_rows()` 方法:
```rust
pub(super) fn option_rows(&self) -> Vec<GenericDisplayRow> {
    // ...
    let mut rows = options
        .iter()
        .enumerate()
        .map(|(idx, opt)| {
            let selected = selected_idx.is_some_and(|sel| sel == idx);
            let prefix = if selected { '›' } else { ' ' };
            let label = opt.label.as_str();
            let number = idx + 1;
            let prefix_label = format!("{prefix} {number}. ");
            GenericDisplayRow {
                name: format!("{prefix_label}{label}"),
                description: Some(opt.description.clone()),
                wrap_indent: Some(UnicodeWidthStr::width(prefix_label.as_str())),
                ..Default::default()
            }
        })
        .collect::<Vec<_>>();
}
```

### 默认选中设置

`reset_for_request()` 方法:
```rust
fn reset_for_request(&mut self) {
    self.answers = self
        .request
        .questions
        .iter()
        .map(|question| {
            let has_options = question.options.as_ref().is_some_and(|o| !o.is_empty());
            let mut options_state = ScrollState::new();
            if has_options {
                options_state.selected_idx = Some(0);  // 默认选中第一个
            }
            AnswerState {
                options_state,
                draft: ComposerDraft::default(),
                answer_committed: false,
                notes_visible: !has_options,
            }
        })
        .collect();
}
```

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui_app_server/src/bottom_pane/request_user_input/mod.rs` | `option_rows()` 构建选项行 |
| `codex-rs/tui_app_server/src/bottom_pane/request_user_input/mod.rs` | `footer_tips()` 生成底部提示 |

## 风险、边界与改进建议

### 潜在风险
1. **默认选择**: 用户可能未注意到默认选中而直接提交
2. **选项数量**: 大量选项时的渲染性能

### 改进建议
1. **显式确认**: 考虑添加显式确认步骤
2. **搜索过滤**: 大量选项时添加搜索功能
