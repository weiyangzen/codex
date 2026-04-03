# 快照研究文档: list_selection_col_width_mode_auto_all_rows_scroll

## 场景与职责

此快照测试验证 `ListSelectionView` 在 **AutoAllRows** 列宽模式下的滚动行为。该模式的核心职责是：**基于所有行（而非仅可见行）计算列宽，确保滚动过程中列宽保持稳定，不会因视口内最长行的变化而产生视觉抖动**。

测试场景：
- 创建一个包含 9 个项目的列表，其中第 9 项具有明显更长的名称
- 在 96 列宽度的终端中渲染，记录滚动前后的布局
- 验证描述列（description column）的位置在滚动前后保持一致

## 功能点目的

**AutoAllRows 模式** 的设计目的是解决选择列表在滚动时的视觉不稳定问题：

1. **稳定列宽**: 与 `AutoVisible` 模式不同，`AutoAllRows` 会测量所有行的名称宽度，而非仅当前可见的行
2. **防止布局抖动**: 当用户滚动列表时，描述列的位置不会随最长可见行的变化而跳动
3. **提升用户体验**: 在包含长短不一项目名称的列表中（如模型选择器），提供更一致的视觉体验

## 具体技术实现

### 列宽计算逻辑

```rust
// selection_popup_common.rs:165-176
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
    .unwrap_or(0)
```

### 描述列位置计算

```rust
// selection_popup_common.rs:180
max_name_width.saturating_add(2).min(max_auto_desc_col)
```

- 名称列宽度 = 所有行中最长名称宽度 + 2（间距）
- 上限为内容宽度的 70%（确保描述列至少有 30% 空间）

### 测试辅助函数

```rust
// list_selection_view.rs:1130-1150
fn render_before_after_scroll_snapshot(col_width_mode: ColumnWidthMode, width: u16) -> String {
    // 创建 9 个项目的列表，第 9 项名称明显更长
    let mut view = ListSelectionView::new(
        SelectionViewParams {
            title: Some("Debug".to_string()),
            items: make_scrolling_width_items(),  // 8 个短名 + 1 个长名
            col_width_mode,
            ..Default::default()
        },
        tx,
    );
    
    let before_scroll = render_lines_with_width(&view, width);
    // 向下滚动 8 次，使第 9 项可见
    for _ in 0..8 {
        view.handle_key_event(KeyEvent::from(KeyCode::Down));
    }
    let after_scroll = render_lines_with_width(&view, width);
    
    format!("before scroll:\n{before_scroll}\n\nafter scroll:\n{after_scroll}")
}
```

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/bottom_pane/list_selection_view.rs` | `ListSelectionView` 主实现，测试用例定义 |
| `codex-rs/tui/src/bottom_pane/selection_popup_common.rs` | 共享渲染逻辑，列宽计算 |

### 关键函数路径

1. **测试入口**: `list_selection_view.rs:1062`
   ```rust
   #[test]
   fn snapshot_auto_all_rows_col_width_mode_scroll_behavior() {
       assert_snapshot!(
           "list_selection_col_width_mode_auto_all_rows_scroll",
           render_before_after_scroll_snapshot(ColumnWidthMode::AutoAllRows, 96)
       );
   }
   ```

2. **列宽计算**: `selection_popup_common.rs:124-183`
   - `compute_desc_col()` 函数根据 `ColumnWidthMode` 计算描述列位置

3. **渲染函数**: `selection_popup_common.rs:619-636`
   - `render_rows_stable_col_widths()` 使用 `AutoAllRows` 模式渲染

4. **高度测量**: `list_selection_view.rs:715-720`
   - `desired_height()` 中根据 `col_width_mode` 选择对应测量函数

### 数据结构

```rust
// selection_popup_common.rs:46-56
pub(crate) enum ColumnWidthMode {
    #[default]
    AutoVisible,   // 仅测量可见行
    AutoAllRows,   // 测量所有行（本测试覆盖）
    Fixed,         // 固定 30/70 分割
}
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `selection_popup_common` | 共享的行渲染、列宽计算逻辑 |
| `scroll_state::ScrollState` | 滚动位置和选中状态管理 |
| `popup_consts::MAX_POPUP_ROWS` | 弹窗最大行数限制 |

### 外部 Crate

| Crate | 用途 |
|-------|------|
| `ratatui` | 终端 UI 渲染框架 |
| `insta` | 快照测试断言 |
| `crossterm` | 键盘事件处理 |

### 测试依赖

```rust
use insta::assert_snapshot;
use crossterm::event::KeyCode;
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
```

## 风险边界与改进建议

### 当前风险边界

1. **性能开销**: `AutoAllRows` 需要遍历所有行计算最大宽度，对于超长列表（1000+ 项）可能有性能影响
   - 当前实现未对大数据集做优化
   
2. **内存占用**: 需要为所有行构建 `GenericDisplayRow`，而非仅可见行

3. **极端宽度情况**: 当某行名称极长时，描述列可能被压缩到最小宽度
   - 当前有 70% 上限保护，但可能影响描述可读性

4. **与 AutoVisible 的行为差异**: 两种模式在相同数据下可能产生不同视觉布局，用户切换时可能感到困惑

### 快照观察

```
before scroll:
› 1. Item 1                                         desc 1  
...
after scroll:
› 9. Item 9 with an intentionally much longer name  desc 9
```

**关键观察**: 滚动前后，描述列位置保持一致（大约在第 50 列左右），即使第 9 项名称明显更长。

### 改进建议

1. **性能优化**: 对于超长列表，考虑缓存列宽计算结果或采用虚拟化策略

2. **渐进式计算**: 首次渲染使用 `AutoVisible` 快速展示，后台异步计算 `AutoAllRows` 宽度并平滑过渡

3. **配置暴露**: 考虑将 `AutoAllRows` 设为某些场景（如模型选择器）的默认模式，而非统一使用 `AutoVisible`

4. **测试增强**: 
   - 添加性能基准测试，测量 100/1000/10000 项的列宽计算耗时
   - 测试极端情况（单字符名称 vs 超长名称混合）

5. **文档完善**: 在 `ColumnWidthMode` 文档中更清晰地说明三种模式的视觉差异和适用场景
