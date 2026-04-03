# list_selection_col_width_mode_fixed_scroll 快照研究

## 场景与职责

本快照测试验证了 `ListSelectionView` 在使用 `ColumnWidthMode::Fixed` 模式时的滚动行为。该模式使用固定的 30/70 比例分割名称列和描述列，完全独立于内容长度。

此模式适用于需要严格布局控制的场景，确保无论项目名称长短，描述始终从固定位置开始，提供完全一致的视觉体验。

## 功能点目的

`Fixed` 列宽模式的核心目标是：

1. **布局一致性**：无论内容如何变化，列宽始终保持 30/70 的固定比例
2. **可预测性**：用户能够准确预期描述信息的位置
3. **设计控制**：允许 UI 设计者精确控制布局比例

测试展示了即使在滚动前后，描述列位置始终保持在固定比例位置（约第 28 列，基于 96 宽度计算）。

## 具体技术实现

### 固定比例常量

在 `selection_popup_common.rs` 中定义：

```rust
// Fixed split used by explicitly fixed column mode: 30% label, 70% description.
const FIXED_LEFT_COLUMN_NUMERATOR: usize = 3;
const FIXED_LEFT_COLUMN_DENOMINATOR: usize = 10;
```

### 列宽计算逻辑

```rust
ColumnWidthMode::Fixed => ((content_width as usize * FIXED_LEFT_COLUMN_NUMERATOR)
    / FIXED_LEFT_COLUMN_DENOMINATOR)
    .clamp(1, max_desc_col),
```

计算方式：
- 给定宽度 96，内容宽度约为 94（减去边距）
- 描述列位置 = 94 * 3 / 10 = 28（约）
- 描述区域宽度 = 94 - 28 = 66（约 70%）

### 快照对比分析

**滚动前**（显示项目 1-8）：
- 描述列固定在约第 28 列
- 短项目名称右侧有较多空白
- 格式：`› 1. Item 1                 desc 1`

**滚动后**（显示项目 2-9）：
- 描述列位置保持不变（第 28 列）
- 长名称被截断显示（"Item 9 with an intent…"）
- 格式：`› 9. Item 9 with an intent… desc 9`

注意：与 `AutoAllRows` 不同，`Fixed` 模式会对超长名称进行截断（显示省略号）。

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui_app_server/src/bottom_pane/list_selection_view.rs` | `ListSelectionView` 组件，支持 `Fixed` 模式 |
| `codex-rs/tui_app_server/src/bottom_pane/selection_popup_common.rs` | 固定比例常量和列宽计算实现 |
| `codex-rs/tui_app_server/src/bottom_pane/selection_popup_common.rs:58-61` | 30/70 比例常量定义 |

### 渲染调用链

```
ListSelectionView::render
  └── render_rows_with_col_width_mode(..., ColumnWidthMode::Fixed)
        └── render_rows_inner
              └── compute_desc_col(..., ColumnWidthMode::Fixed)
```

### 测试函数

```rust
#[test]
fn snapshot_fixed_col_width_mode_scroll_behavior() {
    assert_snapshot!(
        "list_selection_col_width_mode_fixed_scroll",
        render_before_after_scroll_snapshot(ColumnWidthMode::Fixed, 96)
    );
}
```

### 相关单元测试

```rust
#[test]
fn fixed_col_width_is_30_70_and_does_not_shift_when_scrolling() {
    // ...
    let expected_desc_col = ((width.saturating_sub(2) as usize) * 3) / 10;
    assert_eq!(
        before_col, expected_desc_col,
        "fixed mode should place description column at a 30/70 split"
    );
    // ...
}
```

## 依赖与外部交互

- **ratatui**: 提供渲染基础类型
- **line_truncation**: 提供 `truncate_line_with_ellipsis_if_overflow` 用于截断超长名称

## 风险、边界与改进建议

### 潜在风险

1. **内容截断**：固定比例可能导致长名称被截断，信息丢失
2. **空间浪费**：短名称项目会浪费左侧空间
3. **不适应性**：无法根据内容自动调整，在极端情况下表现不佳

### 边界情况

- 当宽度极小时，描述列至少保留 1 列（通过 `clamp(1, max_desc_col)`）
- 超长名称会被截断并显示省略号（"…"）

### 改进建议

1. **可配置比例**：允许调用者自定义分割比例，而非固定 30/70
2. **最小宽度保护**：为名称列设置最小宽度，确保基本信息可读
3. **智能截断**：截断时优先保留名称的关键部分（如前缀）
4. **响应式调整**：在极窄宽度下自动切换到 `AutoVisible` 模式

### 三种模式对比

| 特性 | AutoVisible | AutoAllRows | Fixed |
|------|-------------|-------------|-------|
| 计算范围 | 仅可见行 | 所有行 | 固定比例 |
| 滚动稳定性 | 列宽变化 | 列宽稳定 | 列宽稳定 |
| 空间效率 | 高 | 中 | 低 |
| 内容截断 | 少 | 少 | 可能 |
| 适用场景 | 空间受限 | 稳定布局 | 严格设计 |
