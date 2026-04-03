# list_selection_col_width_mode_auto_visible_scroll 快照研究

## 场景与职责

本快照测试验证了 `ListSelectionView` 在使用 `ColumnWidthMode::AutoVisible` 模式时的滚动行为。这是默认的列宽模式，仅基于当前视口内可见的行计算列宽，实现更紧凑的布局。

此模式适用于空间敏感的场景，特别是在终端宽度有限时，能够根据当前可见内容动态调整列宽，最大化利用可用空间。

## 功能点目的

`AutoVisible` 列宽模式的核心目标是：

1. **空间效率**：仅基于可见行计算列宽，避免为非可见的长项目名称预留过多空间
2. **动态适应**：随着用户滚动，列宽会自动调整以适应新的可见内容
3. **紧凑布局**：在有限宽度下提供更紧凑的视觉呈现

测试展示了滚动前后描述列位置的变化：滚动前短项目名称导致描述列靠前，滚动后长项目名称进入视口导致描述列后移。

## 具体技术实现

### 列宽计算逻辑

在 `selection_popup_common.rs` 中的 `compute_desc_col` 函数处理 `AutoVisible` 模式：

```rust
ColumnWidthMode::AutoVisible => rows_all
    .iter()
    .enumerate()
    .skip(start_idx)
    .take(visible_items)
    .map(|(_, row)| {
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

与 `AutoAllRows` 不同，`AutoVisible` 仅遍历 **视口内可见行**（`skip(start_idx).take(visible_items)`）计算最大名称宽度。

### 快照对比分析

**滚动前**（显示项目 1-8）：
- 所有项目名称较短（"Item 1" 到 "Item 8"）
- 描述列从第 12 列开始（紧凑布局）
- 格式：`› 1. Item 1  desc 1`

**滚动后**（显示项目 2-9）：
- Item 9 的长名称（"Item 9 with an intentionally much longer name"）进入视口
- 描述列后移至第 52 列以适应长名称
- 格式：`› 9. Item 9 with an intentionally much longer name  desc 9`

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui_app_server/src/bottom_pane/list_selection_view.rs` | `ListSelectionView` 组件，默认使用 `AutoVisible` 模式 |
| `codex-rs/tui_app_server/src/bottom_pane/selection_popup_common.rs` | `compute_desc_col` 函数，实现列宽计算逻辑 |
| `codex-rs/tui_app_server/src/bottom_pane/selection_popup_common.rs:46-56` | `ColumnWidthMode` 枚举定义，`AutoVisible` 为默认模式 |

### 默认配置

```rust
impl Default for SelectionViewParams {
    fn default() -> Self {
        Self {
            // ...
            col_width_mode: ColumnWidthMode::AutoVisible,  // 默认模式
            // ...
        }
    }
}
```

### 渲染调用链

```
ListSelectionView::render
  └── render_rows  (AutoVisible 模式)
        └── render_rows_inner
              └── compute_desc_col(..., ColumnWidthMode::AutoVisible)
```

### 测试函数

```rust
#[test]
fn snapshot_auto_visible_col_width_mode_scroll_behavior() {
    assert_snapshot!(
        "list_selection_col_width_mode_auto_visible_scroll",
        render_before_after_scroll_snapshot(ColumnWidthMode::AutoVisible, 96)
    );
}
```

## 依赖与外部交互

- **ratatui**: 提供 `Line`、`Span` 等渲染基础类型
- **unicode-width**: 用于计算字符串的显示宽度
- **ScrollState**: 管理滚动位置和选中状态，提供 `start_idx` 和 `visible_items`

## 风险、边界与改进建议

### 潜在风险

1. **视觉跳动**：滚动时列宽变化可能导致视觉上的"跳动"感，影响用户体验
2. **不一致性**：不同滚动位置下相同项目的描述列位置不同，可能让用户困惑

### 边界情况

- 当视口内没有项目时（空列表），返回 0
- 描述列位置受 `max_auto_desc_col` 限制（最多占 70% 宽度），防止名称列过宽

### 改进建议

1. **平滑过渡**：考虑添加动画或过渡效果，减轻列宽变化时的视觉跳动
2. **智能缓存**：缓存最近计算的最大宽度，只在必要时更新，减少跳动频率
3. **混合策略**：对于频繁滚动的场景，可以短暂延迟列宽更新，避免快速滚动时的频繁布局变化
4. **用户提示**：在界面中提供视觉提示，让用户了解列宽是动态计算的

### 模式选择建议

| 场景 | 推荐模式 |
|------|----------|
| 空间受限、项目长度差异大 | `AutoVisible`（默认） |
| 需要稳定视觉布局 | `AutoAllRows` |
| 固定比例的布局需求 | `Fixed` |
