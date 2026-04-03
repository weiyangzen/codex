# 快照研究文档: list_selection_col_width_mode_auto_visible_scroll

## 场景与职责

此快照测试验证 `ListSelectionView` 在 **AutoVisible** 列宽模式下的滚动行为。作为默认模式，其核心职责是：**仅基于当前可见视口内的行计算列宽，使布局更紧凑，但可能在滚动时产生列宽变化**。

测试场景：
- 创建一个包含 9 个项目的列表，其中第 9 项具有明显更长的名称
- 在 96 列宽度的终端中渲染，记录滚动前后的布局
- 对比滚动前后描述列位置的变化（与 `AutoAllRows` 模式形成对比）

## 功能点目的

**AutoVisible 模式** 是 `ColumnWidthMode` 的默认选项，设计权衡如下：

1. **紧凑布局**: 仅测量可见行，使名称列宽度最小化，为描述列留出更多空间
2. **动态适应**: 随着用户滚动，列宽会自动调整以适应新的可见内容
3. **性能优先**: 不需要遍历所有行，渲染开销更小
4. **视觉权衡**: 牺牲列宽稳定性以换取更紧凑的初始布局

## 具体技术实现

### 列宽计算逻辑

```rust
// selection_popup_common.rs:149-164
ColumnWidthMode::AutoVisible => rows_all
    .iter()
    .enumerate()
    .skip(start_idx)           // 从视口起始索引开始
    .take(visible_items)       // 仅取可见行数
    .map(|(_, row)| {
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

### 与 AutoAllRows 的关键差异

| 特性 | AutoVisible | AutoAllRows |
|------|-------------|-------------|
| 测量范围 | `skip(start_idx).take(visible_items)` | `iter()`（全部） |
| 列宽稳定性 | 滚动时可能变化 | 滚动时保持不变 |
| 初始紧凑度 | 更紧凑 | 可能较宽松 |
| 性能 | O(visible) | O(total) |

### 测试数据构造

```rust
// list_selection_view.rs:1112-1128
fn make_scrolling_width_items() -> Vec<SelectionItem> {
    let mut items: Vec<SelectionItem> = (1..=8)
        .map(|idx| SelectionItem {
            name: format!("Item {idx}"),           // 短名称: "Item 1" ~ "Item 8"
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

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/bottom_pane/list_selection_view.rs` | `ListSelectionView` 主实现，测试用例定义（第 1054 行） |
| `codex-rs/tui/src/bottom_pane/selection_popup_common.rs` | 共享渲染逻辑，列宽计算（第 148-164 行） |

### 关键函数路径

1. **测试入口**: `list_selection_view.rs:1054`
   ```rust
   #[test]
   fn snapshot_auto_visible_col_width_mode_scroll_behavior() {
       assert_snapshot!(
           "list_selection_col_width_mode_auto_visible_scroll",
           render_before_after_scroll_snapshot(ColumnWidthMode::AutoVisible, 96)
       );
   }
   ```

2. **列宽计算**: `selection_popup_common.rs:148-164`
   - `compute_desc_col()` 中 `AutoVisible` 分支仅测量可见行

3. **渲染函数**: `selection_popup_common.rs:591-608`
   - `render_rows()` 使用 `AutoVisible` 模式

4. **默认配置**: `list_selection_view.rs:189`
   ```rust
   col_width_mode: ColumnWidthMode::AutoVisible,  // 默认值
   ```

### 渲染流程

```
ListSelectionView::render()
  ├── build_rows()                    # 构建 GenericDisplayRow
  ├── compute_desc_col()              # 计算描述列位置
  │   └── ColumnWidthMode::AutoVisible # 仅测量可见行
  └── render_rows()                   # 使用计算好的列宽渲染
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `selection_popup_common::compute_desc_col` | 根据模式计算描述列位置 |
| `selection_popup_common::render_rows` | 实际渲染行内容 |
| `scroll_state::ScrollState` | 提供 `scroll_top` 和 `selected_idx` |

### 关键依赖关系

```rust
// selection_popup_common.rs:523
let desc_measure_items = max_items.min(area.height.max(1) as usize);

// selection_popup_common.rs:537-543
let desc_col = compute_desc_col(
    rows_all,
    start_idx,
    desc_measure_items,  // 可见行数限制
    area.width,
    col_width_mode,
);
```

### 外部 Crate

| Crate | 用途 |
|-------|------|
| `ratatui::text::Line` | 计算行宽度 |
| `insta` | 快照测试 |

## 风险边界与改进建议

### 当前风险边界

1. **视觉抖动**: 当可见行中最长名称变化时，描述列位置会跳动
   - 从快照可见：滚动前描述列紧凑，滚动后（第 9 项可见）描述列大幅右移

2. **不一致的用户体验**: 用户滚动时可能感到"布局在跳动"

3. **截断风险**: 如果新滚入的视口包含超长名称，描述可能被严重压缩

### 快照对比分析

```
# AutoVisible 模式（本测试）
before scroll:
› 1. Item 1  desc 1        # 描述紧跟名称，间距小

after scroll:
› 9. Item 9 with an intentionally much longer name  desc 9  # 描述大幅右移

# AutoAllRows 模式（对比）
before scroll:
› 1. Item 1                                         desc 1  # 描述位置固定

after scroll:
› 9. Item 9 with an intentionally much longer name  desc 9  # 描述位置不变
```

### 改进建议

1. **智能过渡**: 实现列宽变化的平滑动画过渡，减少视觉突兀感

2. **自适应阈值**: 当检测到列宽变化超过阈值时，采用更保守的布局策略

3. **混合模式**: 结合两种模式的优点：
   - 初始使用 `AutoVisible` 快速渲染
   - 预计算 `AutoAllRows` 宽度作为上限
   - 实际列宽 = min(可见行最大宽度, 全局最大宽度)

4. **用户控制**: 在配置中暴露列宽模式选项，让高级用户自主选择

5. **启发式选择**: 根据列表特性自动选择模式：
   - 短列表（<20 项）→ `AutoAllRows`
   - 长列表或名称长度差异大 → `AutoVisible` 或 `Fixed`

### 相关测试建议

1. 添加测试验证列宽变化的边界条件
2. 测试不同终端宽度下的行为一致性
3. 性能对比测试：`AutoVisible` vs `AutoAllRows` 在大数据集下的渲染耗时
