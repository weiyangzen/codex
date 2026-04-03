# list_selection_col_width_mode_auto_all_rows_scroll 快照研究

## 场景与职责

本快照测试验证了 `ListSelectionView` 在使用 `ColumnWidthMode::AutoAllRows` 模式时的滚动行为。该模式用于确保在滚动过程中列宽保持稳定，不会因为视口内可见行的变化而导致描述列位置跳动。

此模式适用于需要稳定视觉布局的场景，特别是当列表中包含长度差异较大的项目时（如某些项目名称特别长），用户滚动时列宽保持一致能提供更好的用户体验。

## 功能点目的

`AutoAllRows` 列宽模式的核心目标是：

1. **滚动稳定性**：在滚动前后，描述列（description column）的位置保持不变
2. **全局最优布局**：基于所有行（而非仅可见行）计算名称列的最大宽度
3. **避免视觉跳动**：防止用户滚动时因列宽重新计算导致的布局变化

测试使用 8 个常规项目 + 1 个超长名称项目（"Item 9 with an intentionally much longer name"）来验证滚动稳定性。

## 具体技术实现

### 列宽计算逻辑

在 `selection_popup_common.rs` 中的 `compute_desc_col` 函数处理 `AutoAllRows` 模式：

```rust
ColumnWidthMode::AutoAllRows => rows_all
    .iter()
    .map(|row| {
        let mut spans = row.name_prefix_spans.clone();
        spans.push(row.name.clone().into());
        if row.disabled_reason.is_some() {
            spans.push(" (disabled)".dim());
        }
        Line::from(spans).width()
    })
    .max()
    .unwrap_or(0),
```

与 `AutoVisible` 不同，`AutoAllRows` 遍历 **所有行** 计算最大名称宽度，而非仅视口内的行。

### 测试数据

```rust
fn make_scrolling_width_items() -> Vec<SelectionItem> {
    let mut items: Vec<SelectionItem> = (1..=8)
        .map(|idx| SelectionItem {
            name: format!("Item {idx}"),
            description: Some(format!("desc {idx}")),
            dismiss_on_select: true,
            ..Default::default()
        })
        .collect();
    items.push(SelectionItem {
        name: "Item 9 with an intentionally much longer name".to_string(),
        description: Some("desc 9".to_string()),
        dismiss_on_select: true,
        ..Default::default()
    });
    items
}
```

### 快照对比

**滚动前**：显示项目 1-8，描述列从第 52 列开始（因 Item 9 的长名称被计入计算）

**滚动后**：显示项目 2-9，描述列位置保持不变

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui_app_server/src/bottom_pane/list_selection_view.rs` | `ListSelectionView` 组件，处理滚动和渲染 |
| `codex-rs/tui_app_server/src/bottom_pane/selection_popup_common.rs` | `compute_desc_col` 函数，实现三种列宽模式的计算逻辑 |
| `codex-rs/tui_app_server/src/bottom_pane/selection_popup_common.rs:144-182` | `ColumnWidthMode` 枚举及列宽计算实现 |

### 渲染调用链

```
ListSelectionView::render
  └── render_rows_stable_col_widths  (AutoAllRows 模式)
        └── render_rows_inner
              └── compute_desc_col(..., ColumnWidthMode::AutoAllRows)
```

### 测试函数

```rust
#[test]
fn snapshot_auto_all_rows_col_width_mode_scroll_behavior() {
    assert_snapshot!(
        "list_selection_col_width_mode_auto_all_rows_scroll",
        render_before_after_scroll_snapshot(ColumnWidthMode::AutoAllRows, 96)
    );
}
```

## 依赖与外部交互

- **ratatui**: 提供 `Line`、`Span`、`Rect` 等渲染基础类型
- **unicode-width**: 用于计算字符串的显示宽度
- **textwrap**: 用于文本换行处理
- **ScrollState**: 管理滚动位置和选中状态

## 风险、边界与改进建议

### 潜在风险

1. **性能开销**：`AutoAllRows` 需要遍历所有行计算最大宽度，对于超长列表可能有性能影响
2. **空间浪费**：如果超长项目很少见，为它们预留空间可能导致大部分行的名称列右侧有大量空白

### 边界情况

- 当列表为空时，返回 0 作为描述列位置
- 当内容宽度 ≤1 时，返回 0
- 描述列位置受 `max_auto_desc_col` 限制（最多占 70% 宽度）

### 改进建议

1. **混合模式**：考虑添加一种混合模式，只在检测到名称长度差异超过阈值时才使用全局计算
2. **延迟计算**：对于超长列表，可以考虑延迟加载或虚拟化，避免一次性遍历所有行
3. **用户偏好**：允许用户在设置中选择是否启用滚动稳定性（权衡空间利用 vs 视觉稳定性）
