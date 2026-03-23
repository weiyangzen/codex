# 研究文档: request_user_input_options.snap

## 场景与职责

本快照文件测试 **标准选项问题** 的基础 UI 渲染。这是 `RequestUserInputOverlay` 最基本的用例，展示带有选项列表的单问题界面。

测试用例位于 `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` 第 2452-2466 行。

## 功能点目的

### 核心功能
1. **选项展示**: 显示带编号的选择列表
2. **选中指示**: 使用 `›` 符号指示当前选中项
3. **描述显示**: 每个选项可以有关联的描述文本
4. **操作提示**: 底部显示可用的键盘操作

### 基础交互模型

```
Question 1/1 (1 unanswered)     ← 进度指示
Choose an option.                ← 问题文本

  › 1. Option 1  First choice.   ← 选中项（› 标记）
    2. Option 2  Second choice.  ← 未选中项（空格）
    3. Option 3  Third choice.

tab to add notes | enter to submit answer | esc to interrupt  ← 操作提示
```

## 具体技术实现

### 数据结构

```rust
// 问题定义
RequestUserInputQuestion {
    id: "q1".to_string(),
    header: "Area".to_string(),
    question: "Choose an option.".to_string(),
    is_other: false,
    is_secret: false,
    options: Some(vec![
        RequestUserInputQuestionOption {
            label: "Option 1".to_string(),
            description: "First choice.".to_string(),
        },
        // ...
    ]),
}

// 内部状态
struct AnswerState {
    options_state: ScrollState,      // 选中索引
    draft: ComposerDraft,            // 笔记草稿
    answer_committed: bool,          // 是否已提交
    notes_visible: bool,             // 笔记UI可见性
}
```

### 关键流程

1. **选项行生成** (`option_rows`, mod.rs 第 268-312 行):
   ```rust
   pub(super) fn option_rows(&self) -> Vec<GenericDisplayRow> {
       let selected_idx = self.current_answer()
           .and_then(|answer| answer.options_state.selected_idx);
       
       options.iter().enumerate().map(|(idx, opt)| {
           let selected = selected_idx.is_some_and(|sel| sel == idx);
           let prefix = if selected { '›' } else { ' ' };
           let number = idx + 1;
           let prefix_label = format!("{prefix} {number}. ");
           
           GenericDisplayRow {
               name: format!("{prefix_label}{}", opt.label),
               description: Some(opt.description.clone()),
               wrap_indent: Some(UnicodeWidthStr::width(prefix_label.as_str())),
               ..Default::default()
           }
       }).collect()
   }
   ```

2. **默认选中** (`reset_for_request`, 第 545-574 行):
   ```rust
   let mut options_state = ScrollState::new();
   if has_options {
       options_state.selected_idx = Some(0);  // 默认选中第一个
   }
   ```

3. **键盘导航** (`handle_key_event`, 第 1082-1136 行):
   ```rust
   KeyCode::Up | KeyCode::Char('k') => {
       answer.options_state.move_up_wrap(options_len);
       answer.answer_committed = false;  // 移动后重置提交状态
   }
   KeyCode::Down | KeyCode::Char('j') => {
       answer.options_state.move_down_wrap(options_len);
       answer.answer_committed = false;
   }
   KeyCode::Char(digit) => {
       // 数字键直接选择并提交
       if let Some(option_idx) = self.option_index_for_digit(ch) {
           answer.options_state.selected_idx = Some(option_idx);
           self.select_current_option(true);
           self.go_next_or_submit();
       }
   }
   ```

### 渲染输出

```
  Question 1/1 (1 unanswered)
  Choose an option.

  › 1. Option 1  First choice.
    2. Option 2  Second choice.
    3. Option 3  Third choice.

  tab to add notes | enter to submit answer | esc to interrupt
```

## 关键代码路径与文件引用

### 主要代码文件

| 文件路径 | 职责 |
|---------|------|
| `mod.rs` | 状态管理、输入处理 |
| `render.rs` | 渲染实现 |
| `layout.rs` | 布局计算 |
| `selection_popup_common.rs` | 通用行渲染 |

### 关键代码位置

1. **选项行生成**: `mod.rs:268-312`
2. **键盘处理**: `mod.rs:1082-1136`
3. **渲染**: `render.rs:307-328`
4. **测试用例**: `mod.rs:2452-2466`
5. **测试数据**: `mod.rs:1313-1335` (`question_with_options`)

### 辅助结构

```rust
// GenericDisplayRow 用于统一行渲染
pub struct GenericDisplayRow {
    pub name: String,
    pub description: Option<String>,
    pub wrap_indent: Option<usize>,
    pub icon: Option<String>,
    pub style: Option<Style>,
}
```

## 依赖与外部交互

### 滚动状态管理

```rust
// ScrollState 管理列表滚动
pub struct ScrollState {
    pub selected_idx: Option<usize>,
    pub offset: usize,  // 滚动偏移
}

impl ScrollState {
    pub fn move_up_wrap(&mut self, len: usize) { ... }
    pub fn move_down_wrap(&mut self, len: usize) { ... }
    pub fn ensure_visible(&mut self, total: usize, viewport: usize) { ... }
}
```

### 答案提交

```rust
fn submit_answers(&mut self) {
    let selected_label = selected_idx
        .and_then(|idx| Self::option_label_for_index(question, idx));
    
    let mut answer_list = selected_label.into_iter().collect::<Vec<_>>();
    if !notes.is_empty() {
        answer_list.push(format!("user_note: {notes}"));
    }
    
    answers.insert(
        question.id.clone(),
        RequestUserInputAnswer { answers: answer_list },
    );
}
```

## 风险、边界与改进建议

### 潜在风险

1. **默认选择争议**: 自动选中第一个选项可能导致用户误提交
2. **数字键冲突**: 数字键作为快捷键可能与其他功能冲突
3. **描述过长**: 选项描述过长时可能影响可读性

### 边界情况

| 场景 | 行为 |
|------|------|
| 0 个选项 | 视为自由文本问题 |
| 1 个选项 | 默认选中，可直接提交 |
| 10+ 个选项 | 数字键只支持 1-9 |
| 选项标签重复 | 按索引区分 |

### 改进建议

1. **无默认选择**: 考虑不默认选中任何选项，强制用户主动选择
2. **搜索过滤**: 选项多时添加搜索功能
3. **分组显示**: 支持选项分组和折叠
4. **多选支持**: 当前只支持单选，可考虑扩展

### 相关测试

```rust
// 验证默认选择提交
#[test]
fn enter_commits_default_selection_on_last_option_question() {
    // mod.rs:1558-1576
}

// 验证数字键选择
#[test]
fn number_keys_select_and_submit_options() {
    // mod.rs:1627-1645
}

// 验证 Vim 键导航
#[test]
fn vim_keys_move_option_selection() {
    // mod.rs:1648-1667
}
```

### 代码优化建议

当前选项渲染使用 `GenericDisplayRow`，这是一个通用结构。可以考虑为选项创建专门的类型：

```rust
struct OptionRow {
    index: usize,
    label: String,
    description: Option<String>,
    is_selected: bool,
}

impl OptionRow {
    fn to_display_row(&self) -> GenericDisplayRow { ... }
}
```
