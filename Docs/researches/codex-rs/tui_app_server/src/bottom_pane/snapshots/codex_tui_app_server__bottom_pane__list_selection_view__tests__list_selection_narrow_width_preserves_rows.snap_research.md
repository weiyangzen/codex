# list_selection_narrow_width_preserves_rows 快照研究

## 场景与职责

本快照测试验证了 `ListSelectionView` 在极窄宽度（24 列）终端上的渲染行为。测试确保即使在空间极其有限的情况下，所有列表项仍然可见，不会被截断或隐藏。

此测试对于确保 TUI 在各种终端尺寸下的可用性至关重要，特别是在小窗口或分屏环境下。

## 功能点目的

窄宽度保留行功能的核心目标是：

1. **内容可见性**：即使在极窄宽度下，所有选项都必须可见
2. **行数保持**：不因宽度变化而减少显示的行数
3. **适应布局**：自动调整布局以适应有限空间

测试使用宽度 24 和 3 个项目，验证所有项目都能正确显示。

## 具体技术实现

### 测试数据

```rust
let desc = "x".repeat(10);  // 10 个字符的描述
let items: Vec<SelectionItem> = (1..=3)
    .map(|idx| SelectionItem {
        name: format!("Item {idx}"),
        description: Some(desc.clone()),
        dismiss_on_select: true,
        ..Default::default()
    })
    .collect();
```

### 渲染效果

在宽度 24 的终端上：

```
                        
  Debug                 
                        
› 1. Item 1             
             xxxxxxxxx  
             x          
  2. Item 2             
             xxxxxxxxx  
             x          
  3. Item 3             
             xxxxxxxxx  
             x
```

### 布局适应策略

1. **名称和描述分行**：由于宽度不足以在一行内显示名称和描述，描述被推到下一行
2. **描述缩进**：描述相对于名称有缩进，保持视觉层次
3. **换行处理**：长描述（10 个 'x'）被换行显示

### 两列布局回退

在 `selection_popup_common.rs` 中的 `wrap_two_column_row` 函数处理这种情况：

```rust
fn wrap_two_column_row(row: &GenericDisplayRow, desc_col: usize, width: u16) -> Vec<Line<'static>> {
    // 当宽度不足以并排显示名称和描述时，使用两行布局
    // 第一行：名称
    // 第二行：缩进的描述
}
```

### 换行缩进

在 `build_rows` 中设置 `wrap_indent`：

```rust
let wrap_indent = description.is_none().then_some(wrap_prefix_width);
```

这确保换行后的描述与第一行对齐。

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui_app_server/src/bottom_pane/list_selection_view.rs` | `ListSelectionView` 组件 |
| `codex-rs/tui_app_server/src/bottom_pane/list_selection_view.rs:1451-1477` | 窄宽度测试实现 |
| `codex-rs/tui_app_server/src/bottom_pane/selection_popup_common.rs:210-268` | `wrap_two_column_row` 函数，处理窄宽度下的两列布局 |

### 测试函数

```rust
#[test]
fn snapshot_narrow_width_preserves_third_option() {
    let (tx_raw, _rx) = unbounded_channel::<AppEvent>();
    let tx = AppEventSender::new(tx_raw);
    let desc = "x".repeat(10);
    let items: Vec<SelectionItem> = (1..=3)
        .map(|idx| SelectionItem {
            name: format!("Item {idx}"),
            description: Some(desc.clone()),
            dismiss_on_select: true,
            ..Default::default()
        })
        .collect();
    let view = ListSelectionView::new(
        SelectionViewParams {
            title: Some("Debug".to_string()),
            items,
            ..Default::default()
        },
        tx,
    );
    assert_snapshot!(
        "list_selection_narrow_width_preserves_rows",
        render_lines_with_width(&view, 24)
    );
}
```

### 相关单元测试

```rust
#[test]
fn narrow_width_keeps_all_rows_visible() {
    // ...
    let rendered = render_lines_with_width(&view, 24);
    assert!(
        rendered.contains("3."),
        "third option missing for width 24:\n{rendered}"
    );
}
```

## 依赖与外部交互

- **ratatui**: 提供渲染基础类型
- **unicode-width**: 计算字符串显示宽度
- **textwrap**: 文本换行处理

## 风险、边界与改进建议

### 潜在风险

1. **行数爆炸**：极窄宽度下，每个项目可能占用多行，导致可视项目减少
2. **可读性下降**：过度换行可能影响阅读体验
3. **选择困难**：选中项的指示器（`›`）可能不够明显

### 边界情况

- 当宽度小于项目名称长度时，名称本身也会被换行
- `desc_col` 计算确保至少为 1，避免除零或负数
- 描述缩进通过 `wrap_indent` 控制，确保对齐

### 改进建议

1. **最小宽度限制**：设置一个最小可用宽度，低于此宽度时显示警告或建议用户扩大窗口
2. **紧凑模式**：在极窄宽度下切换到更紧凑的显示模式（如隐藏描述）
3. **垂直滚动提示**：当项目占用多行时，提供更明显的滚动提示
4. **响应式断点**：定义多个宽度断点，在不同断点下使用不同的布局策略

### 宽度适配策略对比

| 宽度范围 | 布局策略 |
|----------|----------|
| ≥ 80 | 标准并排布局 |
| 40-79 | 描述可能换行 |
| 24-39 | 名称和描述分行 |
| < 24 | 考虑紧凑模式 |
