# list_selection_spacing_with_subtitle 快照研究

## 场景与职责

本快照测试验证了 `ListSelectionView` 在有副标题（subtitle）时的垂直间距布局。测试确保标题、副标题和列表项之间的间距符合设计规范，提供清晰的视觉层次。

此测试用于审批模式选择器等场景，其中副标题提供额外的上下文说明。

## 功能点目的

带副标题的间距控制核心目标是：

1. **视觉层次**：通过间距区分标题、副标题和列表项
2. **信息分组**：将标题和副标题作为一组，与列表项分隔
3. **一致性**：确保所有带副标题的选择弹窗具有一致的间距

测试验证了标题和副标题之间无空行，副标题和列表项之间有一个空行。

## 具体技术实现

### 测试数据

```rust
fn make_selection_view(subtitle: Option<&str>) -> ListSelectionView {
    let (tx_raw, _rx) = unbounded_channel::<AppEvent>();
    let tx = AppEventSender::new(tx_raw);
    let items = vec![
        SelectionItem {
            name: "Read Only".to_string(),
            description: Some("Codex can read files".to_string()),
            is_current: true,
            dismiss_on_select: true,
            ..Default::default()
        },
        SelectionItem {
            name: "Full Access".to_string(),
            description: Some("Codex can edit files".to_string()),
            is_current: false,
            dismiss_on_select: true,
            ..Default::default()
        },
    ];
    ListSelectionView::new(
        SelectionViewParams {
            title: Some("Select Approval Mode".to_string()),
            subtitle: subtitle.map(str::to_string),  // "Switch between Codex approval presets"
            footer_hint: Some(standard_popup_hint_line()),
            items,
            ..Default::default()
        },
        tx,
    )
}
```

### 渲染效果

```
                                                
  Select Approval Mode                          
  Switch between Codex approval presets         
                                                
› 1. Read Only (current)  Codex can read files  
  2. Full Access          Codex can edit files  
                                                
  Press enter to confirm or esc to go back
```

### 间距结构

```
[空行]
标题: "Select Approval Mode"
副标题: "Switch between Codex approval presets"
[空行]
列表项 1
列表项 2
[空行]
底部提示
```

### 实现逻辑

在 `ListSelectionView::new` 中构建标题区域：

```rust
let mut header = params.header;
if params.title.is_some() || params.subtitle.is_some() {
    let title = params.title.map(|title| Line::from(title.bold()));
    let subtitle = params.subtitle.map(|subtitle| Line::from(subtitle.dim()));
    header = Box::new(ColumnRenderable::with([
        header,
        Box::new(title),
        Box::new(subtitle),
    ]));
}
```

标题和副标题通过 `ColumnRenderable` 垂直堆叠，然后与列表项之间有一个空行分隔。

### 布局约束

在 `render` 方法中的布局：

```rust
let [header_area, _, search_area, list_area, _, stacked_side_area] = Layout::vertical([
    Constraint::Max(header_height),
    Constraint::Max(1),  // 空行
    Constraint::Length(if self.is_searchable { 1 } else { 0 }),
    Constraint::Length(rows_height),
    // ...
])
.areas(content_area);
```

`Constraint::Max(1)` 确保标题区域和列表区域之间始终有一个空行。

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui_app_server/src/bottom_pane/list_selection_view.rs` | `ListSelectionView` 组件 |
| `codex-rs/tui_app_server/src/bottom_pane/list_selection_view.rs:246-255` | 标题和副标题构建逻辑 |
| `codex-rs/tui_app_server/src/bottom_pane/list_selection_view.rs:821-829` | 垂直布局约束定义 |

### 测试函数

```rust
#[test]
fn renders_blank_line_between_subtitle_and_items() {
    let view = make_selection_view(Some("Switch between Codex approval presets"));
    assert_snapshot!("list_selection_spacing_with_subtitle", render_lines(&view));
}
```

## 依赖与外部交互

- **ratatui**: 提供 `Line`、`Constraint`、`Layout` 等布局类型
- **ColumnRenderable**: 垂直堆叠多个可渲染组件

## 风险、边界与改进建议

### 潜在风险

1. **间距不一致**：如果布局约束修改不当，可能导致间距变化
2. **高度计算错误**：标题高度计算不准确可能导致布局问题

### 边界情况

- 当标题或副标题为空字符串时，仍占用一行（显示空行）
- 当两者都为空时，不创建标题区域

### 改进建议

1. **动态间距**：根据内容长度动态调整间距，短内容可以有更紧凑的布局
2. **样式区分**：增强副标题的样式（如更淡的颜色），使其与标题区分更明显
3. **多行副标题**：支持副标题自动换行，适应长说明文字
4. **图标支持**：允许在标题或副标题前添加图标，增强视觉提示

### 对比：有无副标题的布局差异

| 元素 | 无副标题 | 有副标题 |
|------|----------|----------|
| 标题后空行 | 有 | 无 |
| 副标题后空行 | - | 有 |
| 总空行数 | 2 | 2 |
| 视觉重心 | 标题 | 标题+副标题组合 |
