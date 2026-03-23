# Research: request_user_input_options.snap

## 场景与职责

本快照文件是 `codex-tui` crate 中 `request_user_input` 模块的 insta 快照测试结果，验证标准选项选择模式的 UI 渲染行为。这是最基本的选项选择界面，显示问题、选项列表和操作提示。

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
4. **简洁布局**: 没有 notes 输入区域，需要按 Tab 打开

### 界面元素
| 元素 | 说明 |
|------|------|
| 进度行 | `Question 1/1 (1 unanswered)` |
| 问题文本 | `Choose an option.` |
| 选项列表 | 3个选项，第一个默认选中 |
| 选中标记 | `›` 表示当前选中 |
| 底部提示 | 操作快捷键提示 |

## 具体技术实现

### 选项行构建

`option_rows()` 方法 (mod.rs 第269-313行):
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

`reset_for_request()` 方法 (mod.rs 第546-575行):
```rust
fn reset_for_request(&mut self) {
    self.answers = self
        .request
        .questions
        .iter()
        .map(|question| {
            let has_options = question
                .options
                .as_ref()
                .is_some_and(|options| !options.is_empty());
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
    // ...
}
```

### 底部提示生成

`footer_tips()` 方法 (mod.rs 第430-463行):
```rust
fn footer_tips(&self) -> Vec<FooterTip> {
    let mut tips = Vec::new();
    
    // Tab 添加 notes 提示
    if self.has_options() {
        if self.selected_option_index().is_some() && !notes_visible {
            tips.push(FooterTip::highlighted("tab to add notes"));
        }
        // ...
    }
    
    // Enter 提交提示
    let enter_tip = if question_count == 1 {
        FooterTip::highlighted("enter to submit answer")
    } else if is_last_question {
        FooterTip::highlighted("enter to submit all")
    } else {
        FooterTip::new("enter to submit answer")
    };
    tips.push(enter_tip);
    
    // ESC 中断提示
    if !(self.has_options() && notes_visible) {
        tips.push(FooterTip::new("esc to interrupt"));
    }
    tips
}
```

### 选项渲染

`render_ui()` 方法中的选项渲染 (render.rs 第310-328行):
```rust
if self.has_options() {
    let mut options_state = self
        .current_answer()
        .map(|answer| answer.options_state)
        .unwrap_or_default();
    if sections.options_area.height > 0 {
        options_state.ensure_visible(option_rows.len(), sections.options_area.height as usize);
        render_rows_bottom_aligned(
            sections.options_area,
            buf,
            &option_rows,
            &options_state,
            option_rows.len().max(1),
            "No options",
        );
    }
}
```

## 关键代码路径与文件引用

| 文件路径 | 相关代码行 | 说明 |
|---------|-----------|------|
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 269-313 | `option_rows()` 构建选项行 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 430-463 | `footer_tips()` 生成底部提示 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 546-575 | `reset_for_request()` 初始化状态 |
| `codex-rs/tui/src/bottom_pane/request_user_input/render.rs` | 310-328 | 选项渲染逻辑 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 2451-2466 | 本快照对应的测试用例 |

## 依赖与外部交互

### GenericDisplayRow

选项行的通用数据结构:
```rust
pub struct GenericDisplayRow {
    pub name: String,           // 显示名称（含前缀）
    pub description: Option<String>,  // 描述文本
    pub wrap_indent: Option<usize>,   // 换行缩进
    pub icon: Option<String>,   // 图标（本场景未使用）
}
```

### render_rows_bottom_aligned

底部对齐的选项渲染函数:
```rust
fn render_rows_bottom_aligned(
    area: Rect,
    buf: &mut Buffer,
    rows: &[GenericDisplayRow],
    state: &ScrollState,
    max_results: usize,
    empty_message: &str,
)
```

### 键盘选择处理

数字键选择 (mod.rs 第1126-1134行):
```rust
KeyCode::Char(ch) => {
    if let Some(option_idx) = self.option_index_for_digit(ch) {
        if let Some(answer) = self.current_answer_mut() {
            answer.options_state.selected_idx = Some(option_idx);
        }
        self.select_current_option(/*committed*/ true);
        self.go_next_or_submit();
    }
}
```

## 风险、边界与改进建议

### 潜在风险
1. **默认选择**: 用户可能未注意到默认选中而直接提交
2. **选项数量**: 大量选项时的渲染性能
3. **描述长度**: 长描述可能影响布局

### 边界情况
1. **无选项**: 选项列表为空时的处理
2. **单选项**: 只有一个选项时的界面合理性
3. **超长标签**: 标签文本极长时的换行

### 改进建议
1. **显式确认**: 考虑添加显式确认步骤，避免误提交
2. **搜索过滤**: 大量选项时添加搜索功能
3. **分组显示**: 选项可分组显示，提高可读性
4. **快捷键**: 显示更多快捷键，如数字键直接选择
