# Research: request_user_input_wrapped_options.snap

## 场景与职责

本快照文件是 `codex-tui` crate 中 `request_user_input` 模块的 insta 快照测试结果，验证选项文本自动换行后的渲染行为。当选项标签或描述较长时，需要在有限宽度内正确换行显示。

## 功能点目的

### 测试目标
验证当选项文本长度超过可用宽度时，文本能够正确换行，且描述文本与标签正确对齐，保持界面美观和可读性。

### 快照内容分析
```
Question 1/1 (1 unanswered)                                                                                 
Choose the next step for this task.                                                                         
                                                                                                              
› 1. Discuss a code change  Walk through a plan, then implement it together with careful checks.            
  2. Run targeted tests     Pick the most relevant crate and validate the current behavior first.           
  3. Review the diff        Summarize the changes and highlight the most important risks and gaps.          
                                                                                                              
tab to add notes | enter to submit answer | esc to interrupt
```

关键观察点：
1. **适度换行**: 在48字符宽度下，选项文本有适度换行
2. **描述对齐**: 描述文本与标签对齐，保持视觉层次
3. **完整显示**: 所有选项的完整文本都可见
4. **选中标记**: `›` 标记正确显示在第一个选项

### 与超长文本的区别
| 特性 | Wrapped Options | Long Option Text |
|------|-----------------|------------------|
| 触发条件 | 中等长度文本 | 极长文本 |
| 换行行数 | 1-2行 | 多行 |
| 描述位置 | 与标签同行或下一行 | 可能需要多行 |
| 可读性 | 良好 | 可能需要滚动 |

## 具体技术实现

### 测试数据构造

`question_with_wrapped_options()` 辅助函数 (mod.rs 第1361-1389行):
```rust
fn question_with_wrapped_options(id: &str, header: &str) -> RequestUserInputQuestion {
    RequestUserInputQuestion {
        id: id.to_string(),
        header: header.to_string(),
        question: "Choose the next step for this task.".to_string(),
        is_other: false,
        is_secret: false,
        options: Some(vec![
            RequestUserInputQuestionOption {
                label: "Discuss a code change".to_string(),
                description: "Walk through a plan, then implement it together with careful checks.".to_string(),
            },
            RequestUserInputQuestionOption {
                label: "Run targeted tests".to_string(),
                description: "Pick the most relevant crate and validate the current behavior first.".to_string(),
            },
            RequestUserInputQuestionOption {
                label: "Review the diff".to_string(),
                description: "Summarize the changes and highlight the most important risks and gaps.".to_string(),
            },
        ]),
    }
}
```

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
            let wrap_indent = UnicodeWidthStr::width(prefix_label.as_str());
            GenericDisplayRow {
                name: format!("{prefix_label}{label}"),
                description: Some(opt.description.clone()),
                wrap_indent: Some(wrap_indent),  // 设置换行缩进
                ..Default::default()
            }
        })
        .collect::<Vec<_>>();
}
```

### 换行缩进计算

```rust
let prefix_label = format!("{prefix} {number}. ");
let wrap_indent = UnicodeWidthStr::width(prefix_label.as_str());
```

这确保了：
- 标签换行时，后续行与第一行的标签内容对齐
- 描述文本也与标签内容对齐

### 布局分配测试

`layout_allocates_all_wrapped_options_when_space_allows()` 测试 (mod.rs 第2509-2534行):
```rust
#[test]
fn layout_allocates_all_wrapped_options_when_space_allows() {
    // ...
    let width = 48u16;
    let question_height = overlay.wrapped_question_lines(width).len() as u16;
    let options_height = overlay.options_required_height(width);
    let extras = 1u16 // progress
        .saturating_add(DESIRED_SPACERS_BETWEEN_SECTIONS)
        .saturating_add(overlay.footer_required_height(width));
    let height = question_height
        .saturating_add(options_height)
        .saturating_add(extras);
    let sections = overlay.layout_sections(Rect::new(0, 0, width, height));

    assert_eq!(sections.options_area.height, options_height);
}
```

### 期望高度测试

`desired_height_keeps_spacers_and_preferred_options_visible()` 测试 (mod.rs 第2537-2563行):
```rust
#[test]
fn desired_height_keeps_spacers_and_preferred_options_visible() {
    // ...
    let width = 110u16;
    let height = overlay.desired_height(width);
    let content_area = menu_surface_inset(Rect::new(0, 0, width, height));
    let sections = overlay.layout_sections(content_area);
    let preferred = overlay.options_preferred_height(content_area.width);

    assert_eq!(sections.options_area.height, preferred);
    // 验证间隔存在
    assert_eq!(spacer_after_question, 1);
    assert_eq!(spacer_after_options, 1);
}
```

## 关键代码路径与文件引用

| 文件路径 | 相关代码行 | 说明 |
|---------|-----------|------|
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 269-313 | `option_rows()` 构建选项行 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 1361-1389 | `question_with_wrapped_options()` |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 2509-2534 | 布局分配测试 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 2537-2563 | 期望高度测试 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 2602-2633 | 本快照对应的测试用例 |
| `codex-rs/tui/src/bottom_pane/selection_popup_common.rs` | - | `render_rows()` 渲染函数 |

## 依赖与外部交互

### textwrap 库使用

```rust
use textwrap::wrap;

pub(super) fn wrapped_question_lines(&self, width: u16) -> Vec<String> {
    self.current_question()
        .map(|q| {
            textwrap::wrap(&q.question, width.max(1) as usize)
                .into_iter()
                .map(|line| line.to_string())
                .collect::<Vec<_>>()
        })
        .unwrap_or_default()
}
```

### GenericDisplayRow 换行支持

```rust
pub struct GenericDisplayRow {
    pub name: String,
    pub description: Option<String>,
    pub wrap_indent: Option<usize>,  // 换行缩进宽度
}
```

### 测试配置

```rust
#[test]
fn request_user_input_wrapped_options_snapshot() {
    let (tx, _rx) = test_sender();
    let mut overlay = RequestUserInputOverlay::new(
        request_event("turn-1", vec![question_with_wrapped_options("q1", "Next Step")]),
        tx,
        true,
        false,
        false,
    );
    {
        let answer = overlay.current_answer_mut().expect("answer missing");
        answer.options_state.selected_idx = Some(0);
    }

    let width = 110u16;
    let question_height = overlay.wrapped_question_lines(width).len() as u16;
    let options_height = overlay.options_required_height(width);
    let height = 1u16
        .saturating_add(question_height)
        .saturating_add(options_height)
        .saturating_add(8);
    let area = Rect::new(0, 0, width, height);
    insta::assert_snapshot!(
        "request_user_input_wrapped_options",
        render_snapshot(&overlay, area)
    );
}
```

## 风险、边界与改进建议

### 潜在风险
1. **对齐偏差**: 不同字体的字符宽度可能导致对齐偏差
2. **CJK 字符**: 中日韩字符的宽度计算可能不准确
3. **动态调整**: 终端宽度动态变化时的重排性能

### 边界情况
1. **无空格文本**: 没有空格的长文本(如 URL)的换行
2. **特殊字符**: Emoji 或控制字符的处理
3. **极小宽度**: 宽度不足以显示前缀时的处理

### 改进建议
1. **动态测量**: 使用更精确的字符宽度测量
2. **断词优化**: 优先在语义边界处断行
3. **响应式布局**: 根据宽度自动调整显示模式
4. **折叠长文本**: 提供展开/折叠长描述的功能
