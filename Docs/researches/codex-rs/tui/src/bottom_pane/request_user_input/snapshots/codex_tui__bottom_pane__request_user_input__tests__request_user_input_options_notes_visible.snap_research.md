# 研究文档: request_user_input_options_notes_visible.snap

## 场景与职责

本快照文件测试 **选项问题的笔记输入界面**。当用户在选项问题中按下 Tab 键后，系统显示笔记输入区域，允许用户为选中的选项添加额外说明。

测试用例位于 `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` 第 2469-2489 行。

## 功能点目的

### 核心功能
1. **笔记输入区**: 为选中的选项添加文本说明
2. **焦点切换**: Tab 键在选项和笔记之间切换
3. **占位符提示**: 根据状态显示不同的占位符文本
4. **操作提示更新**: 笔记模式下显示不同的操作提示

### 笔记交互模型

```
Question 1/1 (1 unanswered)
Choose an option.

  › 1. Option 1  First choice.
    2. Option 2  Second choice.
    3. Option 3  Third choice.

  › Add notes                    ← 笔记输入区（焦点在此）





  tab or esc to clear notes | enter to submit answer  ← 更新后的提示
```

## 具体技术实现

### 数据结构

```rust
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Focus {
    Options,  // 选项列表焦点
    Notes,    // 笔记输入焦点
}

struct AnswerState {
    options_state: ScrollState,
    draft: ComposerDraft,         // 笔记草稿
    answer_committed: bool,
    notes_visible: bool,          // 笔记UI是否可见
}
```

### 关键流程

1. **Tab 键处理** (`handle_key_event`, mod.rs 第 1113-1118 行):
   ```rust
   KeyCode::Tab => {
       if self.selected_option_index().is_some() {
           self.focus = Focus::Notes;
           self.ensure_selected_for_notes();
       }
   }
   ```

2. **笔记区显示判断** (`notes_ui_visible`, mod.rs 第 240-247 行):
   ```rust
   pub(super) fn notes_ui_visible(&self) -> bool {
       if !self.has_options() {
           return true;  // 自由文本模式始终显示
       }
       let idx = self.current_index();
       self.current_answer()
           .is_some_and(|answer| {
               answer.notes_visible || self.notes_has_content(idx)
           })
   }
   ```

3. **占位符选择** (`notes_placeholder`, mod.rs 第 401-409 行):
   ```rust
   fn notes_placeholder(&self) -> &'static str {
       if self.has_options() && self.selected_option_index().is_none() {
           SELECT_OPTION_PLACEHOLDER  // "Select an option to add notes"
       } else if self.has_options() {
           NOTES_PLACEHOLDER  // "Add notes"
       } else {
           ANSWER_PLACEHOLDER
       }
   }
   ```

4. **提示更新** (`footer_tips`, mod.rs 第 432-438 行):
   ```rust
   if self.has_options() {
       if self.selected_option_index().is_some() && !notes_visible {
           tips.push(FooterTip::highlighted("tab to add notes"));
       }
       if self.selected_option_index().is_some() && notes_visible {
           tips.push(FooterTip::new("tab or esc to clear notes"));
       }
   }
   ```

### 渲染输出分析

```
  Question 1/1 (1 unanswered)
  Choose an option.

  › 1. Option 1  First choice.
    2. Option 2  Second choice.
    3. Option 3  Third choice.

  › Add notes





  tab or esc to clear notes | enter to submit answer
```

关键观察：
- 选项列表保持可见
- 笔记输入区显示在选项下方
- 占位符显示 "Add notes"
- 底部提示更新为 "tab or esc to clear notes"

## 关键代码路径与文件引用

### 主要代码文件

| 文件路径 | 职责 |
|---------|------|
| `mod.rs` | 焦点管理、提示生成 |
| `render.rs` | 笔记区渲染 |
| `layout.rs` | 布局计算（考虑笔记区高度）|

### 关键代码位置

1. **Tab 处理**: `mod.rs:1113-1118`
2. **笔记区可见性**: `mod.rs:240-247`
3. **提示生成**: `mod.rs:432-438`
4. **笔记渲染**: `render.rs:330-332`, `render.rs:413-425`
5. **测试用例**: `mod.rs:2469-2489`

### 布局计算

```rust
// layout.rs:172-195
// 当 notes_visible 为 true 时，分配空间给笔记区
let mut notes_height = notes_pref_height.min(remaining);
remaining = remaining.saturating_sub(notes_height);
// ...
LayoutPlan {
    // ...
    notes_height,
    // ...
}
```

## 依赖与外部交互

### 笔记编辑器

复用 `ChatComposer` 作为笔记编辑器：

```rust
let mut composer = ChatComposer::new_with_config(
    has_input_focus,
    app_event_tx.clone(),
    enhanced_keys_supported,
    ANSWER_PLACEHOLDER.to_string(),
    disable_paste_burst,
    ChatComposerConfig::plain_text(),  // 纯文本模式
);
// 禁用弹窗和斜杠命令
composer.set_footer_hint_override(Some(Vec::new()));
```

### 答案提交格式

```rust
// 带笔记的答案
RequestUserInputAnswer {
    answers: vec![
        "Option 1".to_string(),
        "user_note: 用户添加的笔记内容".to_string(),
    ],
}
```

## 风险、边界与改进建议

### 潜在风险

1. **笔记丢失**: 切换选项或问题时，如果保存逻辑有 bug 可能导致笔记丢失
2. **空笔记提交**: 用户可能不小心提交了空笔记
3. **焦点混乱**: 选项和笔记之间的焦点切换可能让用户困惑

### 边界情况

| 场景 | 行为 |
|------|------|
| 未选选项按 Tab | 无响应（必须先选选项）|
| 笔记区为空按 Esc | 清除笔记并返回选项 |
| 笔记区有内容按 Esc | 清除笔记并返回选项 |
| 切换问题 | 自动保存笔记草稿 |

### 改进建议

1. **笔记预览**: 在选项列表中显示哪些选项有笔记
2. **笔记计数**: 显示当前笔记的字符数
3. **富文本支持**: 支持 Markdown 或其他格式
4. **笔记历史**: 显示之前类似问题的笔记作为参考

### 相关测试

```rust
// 验证 Tab 打开笔记
#[test]
fn tab_opens_notes_when_option_selected() {
    // mod.rs:1811-1827
}

// 验证笔记被捕获
#[test]
fn notes_are_captured_for_selected_option() {
    // mod.rs:2266-2305
}

// 验证笔记提交时提交选项
#[test]
fn notes_submission_commits_selected_option() {
    // mod.rs:2308-2337
}

// 验证 Tab 在笔记模式清除笔记
#[test]
fn tab_in_notes_clears_notes_and_hides_ui() {
    // mod.rs:2065-2092
}
```

### 代码审查建议

当前笔记和选项使用相同的 `AnswerState` 结构，可以考虑分离：

```rust
struct OptionAnswer {
    selected_idx: Option<usize>,
    committed: bool,
}

struct NotesDraft {
    content: ComposerDraft,
    visible: bool,
}

struct AnswerState {
    option: OptionAnswer,
    notes: NotesDraft,
}
```
