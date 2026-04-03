# list_selection_col_width_mode_fixed_scroll 测试研究文档

## 1. 场景与职责

该测试验证列表选择视图在使用 `Fixed` 列宽模式时的滚动行为。这是 TUI 应用选择弹窗使用固定列宽比例（30% 名称 / 70% 描述）的场景，提供最稳定的布局体验。

**使用场景**：
- 用户打开选择弹窗
- 需要绝对稳定的列宽，不受内容影响
- 使用 `Fixed` 模式确保名称列和描述列始终按 30/70 比例分割
- 适用于内容长度变化大的列表

## 2. 功能点目的

**测试目标**：验证 `ColumnWidthMode::Fixed` 模式下，列表滚动时列宽保持固定的 30/70 比例，不受行内容影响。

**预期行为**：
- 描述列位置固定在内容宽度的 30% 处
- 滚动前后，描述列位置保持不变
- 长名称项会被截断或换行，不会影响列宽
- 提供三种模式中最稳定的视觉体验

## 3. 具体技术实现

### 测试代码位置
`codex-rs/tui_app_server/src/bottom_pane/list_selection_view.rs` 行 1569-1575

### 关键测试逻辑
```rust
#[test]
fn snapshot_fixed_col_width_mode_scroll_behavior() {
    assert_snapshot!(
        "list_selection_col_width_mode_fixed_scroll",
        render_before_after_scroll_snapshot(ColumnWidthMode::Fixed, 96)
    );
}
```

### 固定列宽计算
```rust
// 固定分割常量：30% 名称，70% 描述
const FIXED_LEFT_COLUMN_NUMERATOR: usize = 3;
const FIXED_LEFT_COLUMN_DENOMINATOR: usize = 10;

fn compute_desc_col(
    rows_all: &[GenericDisplayRow],
    start_idx: usize,
    visible_items: usize,
    content_width: u16,
    col_width_mode: ColumnWidthMode,
) -> usize {
    match col_width_mode {
        ColumnWidthMode::Fixed => {
            ((content_width as usize * FIXED_LEFT_COLUMN_NUMERATOR)
                / FIXED_LEFT_COLUMN_DENOMINATOR)
                .clamp(1, max_desc_col)
        }
        // ...
    }
}
```

### 验证测试
```rust
#[test]
fn fixed_col_width_is_30_70_and_does_not_shift_when_scrolling() {
    // ...
    let before_col = description_col(&before_scroll, "8. Item 8", "desc 8");
    let expected_desc_col = ((width.saturating_sub(2) as usize) * 3) / 10;
    assert_eq!(
        before_col, expected_desc_col,
        "fixed mode should place description column at a 30/70 split"
    );
    // ...
}
```

## 4. 关键代码路径与文件引用

### 核心文件
- `codex-rs/tui_app_server/src/bottom_pane/list_selection_view.rs` - 列表选择视图主实现
- `codex-rs/tui_app_server/src/bottom_pane/selection_popup_common.rs` - 选择弹窗通用逻辑
- `codex-rs/tui_app_server/src/bottom_pane/snapshots/codex_tui__bottom_pane__list_selection_view__tests__list_selection_col_width_mode_fixed_scroll.snap` - 预期快照

### 关键函数
- `compute_desc_col()` - `selection_popup_common.rs` 行 124-183
- `render_rows_with_col_width_mode()` - 行 644-662，通用列宽模式渲染
- `measure_rows_height_with_col_width_mode()` - 行 794-802，通用高度测量

### 固定比例常量
```rust
const FIXED_LEFT_COLUMN_NUMERATOR: usize = 3;      // 30%
const FIXED_LEFT_COLUMN_DENOMINATOR: usize = 10;   // 基准
```

## 5. 依赖与外部交互

### 布局系统
- 固定比例计算独立于内容
- 名称列最大宽度：内容宽度 × 30%
- 描述列起始位置：内容宽度 × 30% + 间隙

### 内容处理
- 长名称会被截断（显示 "…"）或换行
- 描述列内容在 70% 空间内渲染
- 不受 `name_prefix_spans` 影响

### 渲染函数
```rust
ColumnWidthMode::Fixed => render_rows_with_col_width_mode(
    render_area,
    buf,
    &rows,
    &self.state,
    render_area.height as usize,
    "no matches",
    ColumnWidthMode::Fixed,
),
```

## 6. 风险、边界与改进建议

### 潜在风险
1. **空间浪费**：短名称项可能浪费左侧空间
2. **长名称截断**：长名称可能在 30% 宽度内被严重截断
3. **描述列拥挤**：如果描述内容长，70% 空间可能仍不足

### 边界情况
1. **极窄终端**：终端宽度小于一定值时，30/70 分割可能不合理
2. **无描述项**：如果列表项都没有描述，70% 空间被浪费
3. **混合内容**：名称和描述长度差异极大的列表

### 改进建议
1. **可配置比例**：
   - 允许用户自定义列宽比例（如 40/60 或 20/80）
   - 提供预设比例选项

2. **自适应边界**：
   - 设置最小名称列宽度，避免极端截断
   - 在极窄终端下自动切换到 `AutoVisible` 模式

3. **增加测试覆盖**：
   - `list_selection_fixed_very_narrow` - 极窄终端下的行为
   - `list_selection_fixed_no_descriptions` - 无描述项的列表
   - `list_selection_fixed_mixed_lengths` - 混合长度内容

4. **智能 Fixed 模式**：
   - 分析内容分布，推荐最优固定比例
   - 根据列表类型自动选择比例（如文件列表用 40/60，模型列表用 30/70）

5. **视觉优化**：
   - 在列边界添加 subtle 分隔线
   - 长名称截断时显示悬停提示
   - 提供列宽调整手柄

### 三种模式对比建议

| 场景 | 推荐模式 | 原因 |
|------|----------|------|
| 内容长度均匀 | AutoVisible | 空间利用率高 |
| 内容长度差异大 | Fixed | 布局稳定 |
| 需要绝对稳定 | AutoAllRows | 滚动无变化 |
| 大数据集 | AutoVisible | 性能更好 |
| 小数据集 | AutoAllRows 或 Fixed | 体验更好 |

### 配置建议
- 在设置中添加列宽模式说明和可视化对比
- 允许按列表类型记忆不同的列宽模式
- 提供一键切换快捷键
