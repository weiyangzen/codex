# 研究文档: request_user_input_wrapped_options.snap

## 场景与职责

本快照文件测试 **选项文本自动换行** 的渲染效果。当选项的标签或描述较长时，系统需要在适当位置换行，并保持良好的视觉对齐。

测试用例位于 `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` 第 2602-2633 行。

## 功能点目的

### 核心功能
1. **智能换行**: 在单词边界处换行，避免截断单词
2. **缩进对齐**: 换行后的文本与第一行适当对齐
3. **描述对齐**: 选项描述与标签的后续行对齐
4. **高度计算**: 准确计算换行后的总高度

### 测试场景设计

测试数据包含三个选项，每个都有较长的描述：

```rust
RequestUserInputQuestionOption {
    label: "Discuss a code change".to_string(),
    description: "Walk through a plan, then implement it together with careful checks.".to_string(),
}
```

## 具体技术实现

### 数据结构

```rust
pub struct GenericDisplayRow {
    pub name: String,                    // 显示文本（带前缀）
    pub description: Option<String>,     // 描述文本
    pub wrap_indent: Option<usize>,      // 换行缩进量
    // ...
}
```

### 关键流程

1. **选项行生成** (`option_rows`, mod.rs 第 268-312 行):
   ```rust
   let prefix_label = format!("{prefix} {number}. ");
   let wrap_indent = UnicodeWidthStr::width(prefix_label.as_str());
   
   GenericDisplayRow {
       name: format!("{prefix_label}{label}"),
       description: Some(opt.description.clone()),
       wrap_indent: Some(wrap_indent),  // 关键：设置缩进
       ..Default::default()
   }
   ```

2. **换行渲染** (`render_rows`, selection_popup_common.rs):
   ```rust
   // 使用 wrap_styled_line 进行换行
   // 考虑 wrap_indent 保持对齐
   ```

3. **高度计算** (`measure_rows_height`, selection_popup_common.rs):
   ```rust
   pub fn measure_rows_height(
       rows: &[GenericDisplayRow],
       state: &ScrollState,
       max_results: usize,
       width: u16,
   ) -> u16 {
       // 计算考虑换行后的总高度
   }
   ```

### 渲染输出分析

```
  Question 1/1 (1 unanswered)
  Choose the next step for this task.

  › 1. Discuss a code change  Walk through a plan, then implement it together with
                               careful checks.
    2. Run targeted tests     Pick the most relevant crate and validate the current
                               behavior first.
    3. Review the diff        Summarize the changes and highlight the most important
                               risks and gaps.

  tab to add notes | enter to submit answer | esc to interrupt
```

关键观察：
- 选项1的描述换行后与第一行对齐
- 换行位置在单词边界（"with" 后换行）
- 缩进保持视觉层次

## 关键代码路径与文件引用

### 主要代码文件

| 文件路径 | 职责 |
|---------|------|
| `mod.rs` | 选项行生成、缩进计算 |
| `selection_popup_common.rs` | 通用行渲染、换行处理 |

### 关键代码位置

1. **选项行生成**: `mod.rs:268-312`
2. **缩进计算**: `mod.rs:284` (`UnicodeWidthStr::width`)
3. **测试数据**: `mod.rs:1361-1389` (`question_with_wrapped_options`)
4. **测试用例**: `mod.rs:2602-2633`

### 测试构造

```rust
let width = 110u16;
let question_height = overlay.wrapped_question_lines(width).len() as u16;
let options_height = overlay.options_required_height(width);
let height = 1u16
    .saturating_add(question_height)
    .saturating_add(options_height)
    .saturating_add(8);  // 额外空间

let area = Rect::new(0, 0, width, height);
insta::assert_snapshot!("request_user_input_wrapped_options", render_snapshot(&overlay, area));
```

## 依赖与外部交互

### Unicode 宽度计算

```rust
use unicode_width::UnicodeWidthStr;

// 计算前缀的实际显示宽度
let wrap_indent = UnicodeWidthStr::width(prefix_label.as_str());
```

### 文本换行

```rust
// selection_popup_common.rs 中的换行实现
pub fn wrap_styled_line(line: &Line<'_>, width: usize) -> Vec<Line<'static>> {
    // 使用 textwrap 或其他算法进行换行
    // 考虑 wrap_indent 参数
}
```

## 风险、边界与改进建议

### 潜在风险

1. **缩进计算错误**: 如果前缀包含宽字符，缩进可能不对齐
2. **极端长单词**: 单个单词超过行宽时可能被截断
3. **描述与标签错位**: 当标签换行次数与描述不一致时，对齐可能出错

### 边界情况

| 场景 | 当前处理 |
|------|---------|
| 单词超过行宽 | 强制截断 |
| 描述为空 | 只显示标签 |
| 宽度为 0 | 返回最小高度 |
| 包含换行符 | 由换行算法处理 |

### 改进建议

1. **连字符断行**: 支持使用连字符（-）在单词中间断行
2. **动态缩进**: 根据实际内容动态调整缩进
3. **最大行数**: 限制单个选项的最大行数，避免占用过多空间
4. **展开/折叠**: 长选项默认折叠，点击展开

### 相关测试

```rust
// 验证布局分配所有换行选项
#[test]
fn layout_allocates_all_wrapped_options_when_space_allows() {
    // mod.rs:2509-2534
    let width = 48u16;
    // ...
    assert_eq!(sections.options_area.height, options_height);
}

// 验证首选高度保持间距
#[test]
fn desired_height_keeps_spacers_and_preferred_options_visible() {
    // mod.rs:2537-2563
}
```

### 代码优化建议

当前 `option_rows` 方法每次都重新生成行数据，可以考虑缓存：

```rust
pub(crate) struct RequestUserInputOverlay {
    // ...
    cached_option_rows: Vec<GenericDisplayRow>,
    cached_question_idx: usize,
}

impl RequestUserInputOverlay {
    pub(super) fn option_rows(&mut self) -> &[GenericDisplayRow] {
        if self.current_idx != self.cached_question_idx {
            self.cached_option_rows = self.compute_option_rows();
            self.cached_question_idx = self.current_idx;
        }
        &self.cached_option_rows
    }
}
```

### 与长选项文本测试的区别

| 特性 | wrapped_options | long_option_text |
|------|-----------------|------------------|
| 测试重点 | 描述换行对齐 | 超长标签换行 |
| 选项数量 | 3 个 | 2 个 |
| 标签长度 | 中等 | 超长 |
| 描述长度 | 长 | 中等 |
