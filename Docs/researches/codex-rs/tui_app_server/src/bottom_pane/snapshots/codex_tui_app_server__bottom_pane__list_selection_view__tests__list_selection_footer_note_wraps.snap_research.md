# list_selection_footer_note_wraps 快照研究

## 场景与职责

本快照测试验证了 `ListSelectionView` 的底部注释（footer note）自动换行功能。当底部注释内容较长而弹窗宽度有限时，注释需要正确换行显示，同时保持样式信息（如颜色、高亮等）。

此功能用于向用户显示重要的提示信息，如配置建议、操作说明等，确保即使在窄宽度终端上也能完整呈现信息。

## 功能点目的

底部注释换行功能的核心目标是：

1. **信息完整性**：确保长注释在窄宽度下也能完整显示
2. **样式保持**：换行后保留原始文本的样式（颜色、粗细等）
3. **视觉美观**：换行后的文本保持适当的缩进和对齐

测试使用宽度 40 的终端，验证包含样式信息的注释能够正确换行。

## 具体技术实现

### 底部注释定义

```rust
let footer_note = Line::from(vec![
    "Note: ".dim(),
    "/setup-default-sandbox".cyan(),
    " to allow network access.".dim(),
]);
```

注释包含三个部分：
- `"Note: "` - 灰色（dim）前缀
- `"/setup-default-sandbox"` - 青色（cyan）高亮的命令
- `" to allow network access."` - 灰色（dim）后缀

### 换行实现

在 `selection_popup_common.rs` 中的 `wrap_styled_line` 函数：

```rust
pub(crate) fn wrap_styled_line<'a>(line: &'a Line<'a>, width: u16) -> Vec<Line<'a>> {
    use crate::wrapping::RtOptions;
    use crate::wrapping::word_wrap_line;

    let width = width.max(1) as usize;
    let opts = RtOptions::new(width)
        .initial_indent(Line::from(""))
        .subsequent_indent(Line::from(""));
    word_wrap_line(line, opts)
}
```

### 渲染流程

在 `ListSelectionView::render` 中：

```rust
let note_width = area.width.saturating_sub(2);
let note_lines = self
    .footer_note
    .as_ref()
    .map(|note| wrap_styled_line(note, note_width));
let note_height = note_lines.as_ref().map_or(0, |lines| lines.len() as u16);
```

注释区域宽度 = 弹窗宽度 - 2（边距）

### 快照分析

在宽度 40 的终端上：

```
  Select Approval Mode

› 1. Read Only (current)  Codex can
                          read files

  Note: Use /setup-default-sandbox to
  allow network access.
  Press enter to confirm or esc to go ba
```

换行结果：
- 第一行：`Note: Use /setup-default-sandbox to`
- 第二行：`allow network access.`

样式保持：
- "Note: " 保持灰色
- "/setup-default-sandbox" 保持青色
- " to allow network access." 保持灰色

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui_app_server/src/bottom_pane/list_selection_view.rs` | `ListSelectionView` 组件，处理底部注释渲染 |
| `codex-rs/tui_app_server/src/bottom_pane/list_selection_view.rs:765-768` | 注释换行和高度计算 |
| `codex-rs/tui_app_server/src/bottom_pane/list_selection_view.rs:951-970` | 注释渲染实现 |
| `codex-rs/tui_app_server/src/bottom_pane/selection_popup_common.rs:98-107` | `wrap_styled_line` 函数，实现带样式的文本换行 |

### 测试函数

```rust
#[test]
fn snapshot_footer_note_wraps() {
    let (tx_raw, _rx) = unbounded_channel::<AppEvent>();
    let tx = AppEventSender::new(tx_raw);
    let items = vec![SelectionItem {
        name: "Read Only".to_string(),
        description: Some("Codex can read files".to_string()),
        is_current: true,
        dismiss_on_select: true,
        ..Default::default()
    }];
    let footer_note = Line::from(vec![
        "Note: ".dim(),
        "/setup-default-sandbox".cyan(),
        " to allow network access.".dim(),
    ]);
    let view = ListSelectionView::new(
        SelectionViewParams {
            title: Some("Select Approval Mode".to_string()),
            footer_note: Some(footer_note),
            footer_hint: Some(standard_popup_hint_line()),
            items,
            ..Default::default()
        },
        tx,
    );
    assert_snapshot!(
        "list_selection_footer_note_wraps",
        render_lines_with_width(&view, 40)
    );
}
```

## 依赖与外部交互

- **ratatui**: 提供 `Line`、`Span` 等带样式的文本类型
- **wrapping 模块**: 提供 `word_wrap_line` 和 `RtOptions`，处理带样式的文本换行
- **textwrap**: 底层文本换行库

## 风险、边界与改进建议

### 潜在风险

1. **样式丢失**：如果换行实现不当，可能导致样式信息丢失
2. **单词截断**：在单词边界处换行，避免截断单词
3. **过度换行**：极窄宽度下可能导致过多行数

### 边界情况

- 宽度为 0 或 1 时，`wrap_styled_line` 使用 `width.max(1)` 保护
- 空注释时，`note_height` 为 0
- 注释渲染时检查 `idx as u16 >= note_area.height` 防止溢出

### 改进建议

1. **首行缩进**：考虑为续行添加缩进，提高可读性
2. **最大行数限制**：限制注释最大行数，避免占用过多空间
3. **折叠/展开**：对于极长的注释，提供折叠/展开功能
4. **链接检测**：自动检测并高亮注释中的 URL 或命令

### 相关组件

底部注释通常与 `footer_hint` 一起使用：
- `footer_note`: 提供上下文信息或提示
- `footer_hint`: 显示操作快捷键（如 "Press enter to confirm or esc to go back"）
