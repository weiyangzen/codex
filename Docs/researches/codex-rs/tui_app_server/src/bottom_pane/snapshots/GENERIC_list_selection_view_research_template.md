# List Selection View Generic Research Template

## 场景与职责

该文档是列表选择视图的通用研究模板，适用于以下快照文件：
- `list_selection_col_width_mode_auto_visible_scroll.snap`
- `list_selection_col_width_mode_fixed_scroll.snap`
- `list_selection_footer_note_wraps.snap`
- `list_selection_narrow_width_preserves_rows.snap`
- `list_selection_spacing_with_subtitle.snap`
- `list_selection_spacing_without_subtitle.snap`

### 业务场景
- 显示可选择的列表项
- 支持不同的列宽模式
- 适应不同的终端宽度

### 列宽模式
| 模式 | 描述 |
|------|------|
| AutoVisible | 根据可见行计算列宽 |
| AutoAllRows | 根据所有行计算列宽 |
| Fixed | 固定 30/70 分割 |

## 功能点目的

### 核心功能
1. **列表显示**：显示可选择的列表项
2. **列宽调整**：根据内容和宽度调整列宽
3. **滚动支持**：支持上下滚动
4. **选中指示**：清晰显示当前选中项

### 用户体验目标
- **信息完整**：长内容不会被截断
- **视觉稳定**：滚动时列宽保持稳定
- **导航便捷**：支持键盘滚动导航

## 具体技术实现

### 关键数据结构
```rust
pub(crate) enum ColumnWidthMode {
    AutoVisible,
    AutoAllRows,
    Fixed,
}

pub(crate) struct ListSelectionView {
    col_width_mode: ColumnWidthMode,
    items: Vec<SelectionItem>,
    state: ScrollState,
}
```

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/list_selection_view.rs`

## 依赖与外部交互

### 内部依赖
- `ListSelectionView` - 列表选择视图
- `ColumnWidthMode` - 列宽模式

### 外部交互
- 无直接外部交互

## 风险、边界与改进建议

### 潜在风险
1. **性能问题**：大量行时计算列宽可能影响性能
2. **显示问题**：极端宽度下显示可能不理想

### 改进建议
1. **虚拟滚动**：大量项时使用虚拟滚动
2. **响应式调整**：终端宽度变化时重新计算

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/list_selection_view.rs`
