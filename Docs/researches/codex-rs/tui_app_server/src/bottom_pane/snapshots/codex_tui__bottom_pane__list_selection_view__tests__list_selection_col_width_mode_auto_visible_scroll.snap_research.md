# list_selection_col_width_mode_auto_visible_scroll 测试研究文档

## 1. 场景与职责

该测试验证列表选择视图在使用 `AutoVisible` 列宽模式（默认模式）时的滚动行为。这是 TUI 应用选择弹窗在滚动时根据可见行动态调整列宽的场景。

**使用场景**：
- 用户打开选择弹窗（如 `/model` 命令）
- 列表项数量较多，需要滚动查看
- 使用默认的 `AutoVisible` 模式，根据当前可见行优化列宽
- 在有限空间内最大化信息展示效率

## 2. 功能点目的

**测试目标**：验证 `ColumnWidthMode::AutoVisible` 模式下，列表滚动时列宽会根据当前可见行动态调整，以最优方式利用可用空间。

**预期行为**：
- 滚动前，列宽基于初始可见行（Item 1-8）计算
- 滚动后，当长名称项（Item 9）进入视图，描述列位置可能调整
- 相比 `AutoAllRows`，`AutoVisible` 在初始状态可能提供更紧凑的布局

## 3. 具体技术实现

### 测试代码位置
`codex-rs/tui_app_server/src/bottom_pane/list_selection_view.rs` 行 1553-1559

### 关键测试逻辑
```rust
#[test]
fn snapshot_auto_visible_col_width_mode_scroll_behavior() {
    assert_snapshot!(
        "list_selection_col_width_mode_auto_visible_scroll",
        render_before_after_scroll_snapshot(ColumnWidthMode::AutoVisible, 96)
    );
}
```

### 列宽计算逻辑（AutoVisible）
```rust
fn compute_desc_col(
    rows_all: &[GenericDisplayRow],
    start_idx: usize,
    visible_items: usize,
    content_width: u16,
    col_width_mode: ColumnWidthMode,
) -> usize {
    match col_width_mode {
        ColumnWidthMode::AutoVisible => {
            // 仅基于可见行计算最大名称宽度
            let max_name_width = rows_all
                .iter()
                .enumerate()
                .skip(start_idx)
                .take(visible_items)  // 只考虑可见行
                .map(|(_, row)| {
                    let mut spans = row.name_prefix_spans.clone();
                    spans.push(row.name.clone().into());
                    if row.disabled_reason.is_some() {
                        spans.push(" (disabled)".dim());
                    }
                    Line::from(spans).width()
                })
                .max()
                .unwrap_or(0);
            max_name_width.saturating_add(2).min(max_auto_desc_col)
        }
        // ...
    }
}
```

### 与 AutoAllRows 的差异
| 特性 | AutoVisible | AutoAllRows |
|------|-------------|-------------|
| 计算范围 | 仅可见行 | 所有行 |
| 滚动时列宽 | 可能变化 | 保持稳定 |
| 初始空间利用 | 更紧凑 | 预留空间 |
| 性能 | 更好（数据量少） | 稍差（遍历所有行） |

## 4. 关键代码路径与文件引用

### 核心文件
- `codex-rs/tui_app_server/src/bottom_pane/list_selection_view.rs` - 列表选择视图主实现
- `codex-rs/tui_app_server/src/bottom_pane/selection_popup_common.rs` - 选择弹窗通用逻辑
- `codex-rs/tui_app_server/src/bottom_pane/snapshots/codex_tui__bottom_pane__list_selection_view__tests__list_selection_col_width_mode_auto_visible_scroll.snap` - 预期快照

### 关键函数
- `compute_desc_col()` - `selection_popup_common.rs` 行 124-183
- `render_rows()` - 行 591-608，使用 `AutoVisible` 的渲染
- `measure_rows_height()` - 行 758-771，配套高度测量

### 默认配置
```rust
impl Default for SelectionViewParams {
    fn default() -> Self {
        Self {
            col_width_mode: ColumnWidthMode::AutoVisible,  // 默认模式
            // ...
        }
    }
}
```

## 5. 依赖与外部交互

### 可见行计算
- `start_idx` - 当前视图起始索引
- `visible_items` - 可见行数量（受 `MAX_POPUP_ROWS` 限制）
- `skip(start_idx).take(visible_items)` - 仅处理可见行

### 渲染系统
- `render_rows()` - 使用 `AutoVisible` 模式的渲染函数
- `measure_rows_height()` - 配套高度测量

### 限制常量
```rust
const MAX_POPUP_ROWS: usize = 8;  // 弹窗最大行数
```

## 6. 风险、边界与改进建议

### 潜在风险
1. **列宽跳动**：滚动时列宽变化可能造成视觉不稳定
2. **描述列截断**：如果可见行中有短名称，描述列空间可能不足
3. **长名称突然进入**：长名称项突然进入视图时，布局可能剧烈变化

### 边界情况
1. **首行超长**：如果第一行名称就很长，初始布局可能不紧凑
2. **滚动到末尾**：滚动到列表末尾时，可见行数量可能减少
3. **过滤后行数变化**：搜索过滤后可见行减少，列宽重新计算

### 改进建议
1. **平滑过渡**：
   - 列宽变化时添加过渡动画
   - 使用防抖避免快速滚动时的频繁重计算

2. **智能预计算**：
   - 预计算接下来几行的宽度，提前调整布局
   - 使用加权平均，不完全依赖当前可见行

3. **增加测试覆盖**：
   - `list_selection_auto_visible_filter` - 过滤后的列宽变化
   - `list_selection_auto_visible_jump` - 跳转到特定项
   - `list_selection_auto_visible_resize` - 终端大小变化

4. **混合模式**：
   - 实现自适应模式，在小数据集使用 `AutoAllRows`，大数据集使用 `AutoVisible`
   - 根据滚动速度动态切换模式（快速滚动时用 `AutoVisible`，停止后用 `AutoAllRows`）

5. **用户控制**：
   - 添加快捷键临时切换列宽模式
   - 记住用户对特定列表的列宽模式偏好

### 性能优化建议
- 缓存最近计算的列宽，避免重复计算
- 使用增量计算，仅更新变化的行
- 在后台线程预计算列宽

### 用户体验改进
- 列宽变化时提供视觉提示
- 允许用户锁定当前列宽
- 在设置中提供列宽模式说明和预览
