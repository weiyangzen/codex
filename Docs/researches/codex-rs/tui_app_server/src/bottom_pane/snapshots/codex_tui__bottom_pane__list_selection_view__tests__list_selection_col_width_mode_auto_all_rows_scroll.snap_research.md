# List Selection View Column Width Mode Auto All Rows Scroll Snapshot 研究文档

## 场景与职责

该快照文件是 `codex_tui_app_server` crate 中 `list_selection_view.rs` 模块的测试快照，用于验证**列表选择视图的列宽模式（AutoAllRows）和滚动功能**。当列表项内容长度差异较大时，此模式确保列宽稳定。

### 业务场景
- 显示包含长短不一的项列表
- 用户滚动列表时，列宽保持稳定
- 避免因项内容变化导致的列宽跳动

### 列宽模式对比
| 模式 | 描述 | 适用场景 |
|------|------|----------|
| AutoVisible | 根据可见行计算列宽 | 内容长度相对均匀 |
| AutoAllRows | 根据所有行计算列宽 | 内容长度差异大 |
| Fixed | 固定 30/70 分割 | 需要稳定布局 |

## 功能点目的

### 核心功能
1. **稳定列宽**：滚动时列宽保持不变
2. **内容适应**：根据所有内容计算最优列宽
3. **滚动支持**：支持上下滚动浏览
4. **选中指示**：清晰显示当前选中项

### 用户体验目标
- **视觉稳定**：滚动时界面不跳动
- **信息完整**：长内容不会被截断
- **导航便捷**：支持键盘滚动导航

## 具体技术实现

### 关键数据结构
```rust
pub(crate) enum ColumnWidthMode {
    AutoVisible,   // 根据可见行计算
    AutoAllRows,   // 根据所有行计算
    Fixed,         // 固定分割
}

pub(crate) struct ListSelectionView {
    col_width_mode: ColumnWidthMode,
    items: Vec<SelectionItem>,
    state: ScrollState,
}
```

### 行高度计算
```rust
fn measure_rows_height_stable_col_widths(
    rows: &[GenericDisplayRow],
    state: &ScrollState,
    max_visible: usize,
    width: u16,
) -> u16 {
    // 计算所有行的列宽
    let col_widths = compute_stable_col_widths(rows, width);
    
    // 根据可见行的起始索引计算高度
    let start_idx = state.scroll_offset;
    let visible_rows = &rows[start_idx..(start_idx + max_visible).min(rows.len())];
    
    visible_rows
        .iter()
        .map(|row| row.height_with_col_widths(&col_widths))
        .sum()
}
```

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/list_selection_view.rs`
- **测试函数**: `list_selection_col_width_mode_auto_all_rows_scroll` (行 1054 附近)

### 渲染输出分析
```
before scroll:
                                                                                                
  Debug                                                                                          
                                                                                                
› 1. Item 1                                         desc 1                                      
  2. Item 2                                         desc 2                                      
  3. Item 3                                         desc 3                                      
  4. Item 4                                         desc 4                                      
  5. Item 5                                         desc 5                                      
  6. Item 6                                         desc 6                                      
  7. Item 7                                         desc 7                                      
  8. Item 8                                         desc 8                                      
                                                                                                

after scroll:
                                                                                                
  Debug                                                                                          
                                                                                                
  2. Item 2                                         desc 2                                      
  3. Item 3                                         desc 3                                      
  4. Item 4                                         desc 4                                      
  5. Item 5                                         desc 5                                      
  6. Item 6                                         desc 6                                      
  7. Item 7                                         desc 7                                      
  8. Item 8                                         desc 8                                      
› 9. Item 9 with an intentionally much longer name  desc 9
```

- 滚动前后列宽保持一致
- 第 9 项的长名称不会导致列宽变化

## 依赖与外部交互

### 内部依赖
- `measure_rows_height_stable_col_widths` - 稳定列宽高度计算
- `compute_stable_col_widths` - 列宽计算

### 外部交互
- 无直接外部交互

## 风险、边界与改进建议

### 潜在风险
1. **性能问题**：大量行时计算所有行列宽可能影响性能
2. **内存占用**：需要存储所有行的列宽信息
3. **极端长度**：极长内容可能导致列宽不合理

### 边界情况
1. **空列表**：无行时的处理
2. **单行**：只有一行时的处理
3. **宽度不足**：终端宽度不足以显示内容

### 改进建议
1. **懒加载**：仅计算可见区域的列宽
2. **缓存机制**：缓存列宽计算结果
3. **最大宽度限制**：限制列宽不超过某个阈值
4. **响应式调整**：终端宽度变化时重新计算

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/list_selection_view.rs`
- 选择项通用: `codex-rs/tui_app_server/src/bottom_pane/selection_popup_common.rs`
