# Research: request_user_input_long_option_text.snap

## 场景与职责

本快照文件是 `codex-tui` crate 中 `request_user_input` 模块的 insta 快照测试结果，验证超长选项文本的自动换行和渲染行为。当选项标签或描述文本过长时，UI 需要正确处理文本换行，保持可读性和布局美观。

## 功能点目的

### 测试目标
验证当选项文本长度超过可用宽度时，文本能够正确换行显示，且描述文本与标签对齐，保持视觉层次清晰。

### 快照内容分析
```
Question 1/1 (1 unanswered)                                                                                           
Choose one option.                                                                                                    
                                                                                                                      
› 1. Job: running/completed/failed/expired; Run/Experiment: succeeded/failed/    Keep async job statuses for          
     unknown (Recommended when triaging long-running background work and status  progress tracking and include        
     transitions)                                                                enough context for debugging          
                                                                                  retries, stale workers, and          
                                                                                  unexpected expiration paths.         
    2. Add a short status model                                                    Simpler labels with less detail for  
                                                                                   quick rollouts.                      
                                                                                                                      
tab to add notes | enter to submit answer | esc to interrupt
```

关键观察点：
1. **标签换行**: 第一个选项的标签被分成3行显示
2. **描述对齐**: 描述文本与标签的第二行对齐（有缩进）
3. **视觉层次**: 使用缩进区分标签和描述，保持可读性
4. **选中标记**: `›` 标记只在第一行显示

### 换行策略
- 选项编号和选中标记固定在行首
- 标签文本自动换行
- 描述文本与标签主体对齐（考虑缩进）
- 保持选项间的视觉分隔

## 具体技术实现

### 选项行构建

`option_rows()` 方法 (mod.rs 第269-313行):
```rust
pub(super) fn option_rows(&self) -> Vec<GenericDisplayRow> {
    self.current_question()
        .and_then(|question| question.options.as_ref().map(|options| (question, options)))
        .map(|(question, options)| {
            let selected_idx = self
                .current_answer()
                .and_then(|answer| answer.options_state.selected_idx);
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
                        wrap_indent: Some(wrap_indent),  // 关键：设置换行缩进
                        ..Default::default()
                    }
                })
                .collect::<Vec<_>>();
            // ...
        })
        .unwrap_or_default()
}
```

### GenericDisplayRow 结构

```rust
pub struct GenericDisplayRow {
    pub name: String,           // 选项标签（含前缀）
    pub description: Option<String>,  // 选项描述
    pub wrap_indent: Option<usize>,   // 换行缩进宽度
    // ...
}
```

### 渲染时的换行处理

`render_rows()` 函数 (selection_popup_common.rs):
```rust
pub fn render_rows(
    area: Rect,
    buf: &mut Buffer,
    rows: &[GenericDisplayRow],
    state: &ScrollState,
    max_results: usize,
    empty_message: &str,
) -> u16 {
    // ...
    for (row_idx, row) in visible_rows.iter().enumerate() {
        // 渲染名称（标签）
        let name_lines = wrap_line(&row.name, available_width as usize);
        // 渲染描述（带缩进）
        if let Some(desc) = &row.description {
            let indent = row.wrap_indent.unwrap_or(0);
            let desc_width = available_width.saturating_sub(indent as u16);
            let desc_lines = wrap_line(desc, desc_width as usize);
            // 描述与标签对齐...
        }
    }
}
```

### 测试数据构造

`question_with_very_long_option_text()` 辅助函数 (mod.rs 第1391-1409行):
```rust
fn question_with_very_long_option_text(id: &str, header: &str) -> RequestUserInputQuestion {
    RequestUserInputQuestion {
        id: id.to_string(),
        header: header.to_string(),
        question: "Choose one option.".to_string(),
        is_other: false,
        is_secret: false,
        options: Some(vec![
            RequestUserInputQuestionOption {
                label: "Job: running/completed/failed/expired; Run/Experiment: succeeded/failed/unknown (Recommended when triaging long-running background work and status transitions)".to_string(),
                description: "Keep async job statuses for progress tracking and include enough context for debugging retries, stale workers, and unexpected expiration paths.".to_string(),
            },
            RequestUserInputQuestionOption {
                label: "Add a short status model".to_string(),
                description: "Simpler labels with less detail for quick rollouts.".to_string(),
            },
        ]),
    }
}
```

## 关键代码路径与文件引用

| 文件路径 | 相关代码行 | 说明 |
|---------|-----------|------|
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 269-313 | `option_rows()` 构建选项行 |
| `codex-rs/tui/src/bottom_pane/selection_popup_common.rs` | - | `GenericDisplayRow` 定义和渲染 |
| `codex-rs/tui/src/bottom_pane/selection_popup_common.rs` | - | `render_rows()` 换行渲染 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 1391-1409 | 测试数据构造函数 |
| `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 2636-2653 | 本快照对应的测试用例 |

## 依赖与外部交互

### textwrap 库

用于文本换行:
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

### unicode-width 库

计算 Unicode 文本显示宽度:
```rust
use unicode_width::UnicodeWidthStr;

let wrap_indent = UnicodeWidthStr::width(prefix_label.as_str());
```

## 风险、边界与改进建议

### 潜在风险
1. **极端长度**: 如果选项标签或描述极长，可能占用过多屏幕空间
2. **CJK 字符**: 中日韩字符宽度计算可能不准确
3. **性能**: 大量长文本的换行计算可能影响渲染性能

### 边界情况
1. **无空格文本**: 超长无空格文本(如 URL)的换行行为
2. **多字节字符**: Emoji 或其他多字节 Unicode 字符的处理
3. **终端宽度变化**: 动态调整大小时的重新换行

### 改进建议
1. **最大行数限制**: 限制每个选项的最大显示行数，避免占用过多空间
2. **截断指示**: 超长文本显示省略号(...)并提供展开机制
3. **智能换行**: 优先在标点符号或语义边界处换行
4. **性能优化**: 缓存换行结果，避免每次渲染重新计算
