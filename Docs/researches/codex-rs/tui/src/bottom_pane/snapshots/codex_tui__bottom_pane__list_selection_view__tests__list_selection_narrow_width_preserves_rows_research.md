# 快照研究文档: list_selection_narrow_width_preserves_rows

## 场景与职责

此快照测试验证 `ListSelectionView` 在 **极窄终端宽度（24 列）** 下的渲染行为。核心职责是：**确保即使在极端窄宽度条件下，所有列表项仍然可见且可交互，不会因为布局计算错误而导致项目被隐藏或截断**。

测试场景：
- 创建 3 个带有描述的项目
- 在 24 列的极窄宽度下渲染
- 验证所有 3 个项目都能正确显示（特别是第 3 项）

## 功能点目的

**窄宽度兼容性** 的设计目的：

1. **极端环境支持**: 支持在极小终端窗口、分屏终端或嵌入式环境中使用
2. **数据完整性**: 确保所有选项都可访问，不因宽度限制而丢失
3. **降级优雅**: 在资源受限时提供可用的降级体验
4. **回归防护**: 防止布局算法在极端条件下的计算错误

## 具体技术实现

### 测试数据构造

```rust
// list_selection_view.rs:1527-1551
#[test]
fn snapshot_narrow_width_preserves_rows() {
    let desc = "x".repeat(10);  // 10 个 x 的描述
    let items: Vec<SelectionItem> = (1..=3)
        .map(|idx| SelectionItem {
            name: format!("Item {idx}"),
            description: Some(desc.clone()),  // 所有项目相同描述
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
        render_lines_with_width(&view, 24)  // 极窄宽度
    );
}
```

### 相关回归测试

```rust
// list_selection_view.rs:1452-1478
#[test]
fn narrow_width_keeps_all_rows_visible() {
    // 使用相同测试数据
    let rendered = render_lines_with_width(&view, 24);
    assert!(
        rendered.contains("3."),
        "third option missing for width 24:\n{rendered}"
    );
}
```

### 描述列计算的安全处理

```rust
// selection_popup_common.rs:124-183
fn compute_desc_col(...) -> usize {
    if content_width <= 1 {
        return 0;  // 极端情况保护
    }
    let max_desc_col = content_width.saturating_sub(1) as usize;
    // ...
}
```

### 换行缩进计算

```rust
// selection_popup_common.rs:185-196
fn wrap_indent(row: &GenericDisplayRow, desc_col: usize, max_width: u16) -> usize {
    let max_indent = max_width.saturating_sub(1) as usize;
    let indent = row.wrap_indent.unwrap_or_else(|| {
        if row.description.is_some() || row.disabled_reason.is_some() {
            desc_col
        } else {
            0
        }
    });
    indent.min(max_indent)  // 确保不超出最大宽度
}
```

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/bottom_pane/list_selection_view.rs` | 窄宽度测试用例（第 1527-1551, 1452-1478 行） |
| `codex-rs/tui/src/bottom_pane/selection_popup_common.rs` | 安全计算逻辑 |

### 关键函数路径

1. **快照测试**: `list_selection_view.rs:1527`
   ```rust
   #[test]
   fn snapshot_narrow_width_preserves_rows()
   ```

2. **回归测试**: `list_selection_view.rs:1452`
   ```rust
   #[test]
   fn narrow_width_keeps_all_rows_visible()
   ```

3. **列宽计算**: `selection_popup_common.rs:124-183`
   ```rust
   fn compute_desc_col(...)
   ```

4. **行渲染**: `selection_popup_common.rs:498-581`
   ```rust
   fn render_rows_inner(...)
   ```

### 安全计算模式

代码中多处使用 `saturating_sub` 和 `max(1)` 防止溢出：

```rust
let content_width = width.saturating_sub(1).max(1);
let max_indent = max_width.saturating_sub(1) as usize;
height = height.saturating_add(note_lines.len() as u16);
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `selection_popup_common::compute_desc_col` | 描述列位置计算 |
| `selection_popup_common::wrap_row_lines` | 行内容换行 |
| `list_selection_view::build_rows` | 行数据构建 |

### 外部 Crate

| Crate | 用途 |
|-------|------|
| `ratatui::layout::Rect` | 区域计算 |
| `unicode_width` | 字符宽度计算 |

### 宽度相关常量

```rust
// list_selection_view.rs:39
const MIN_LIST_WIDTH_FOR_SIDE: u16 = 40;  // 侧边内容的最小宽度

// list_selection_view.rs:46
const MENU_SURFACE_HORIZONTAL_INSET: u16 = 4;  // 菜单表面水平内边距
```

## 风险边界与改进建议

### 当前风险边界

1. **描述列位置为 0**: 在极窄宽度下，`compute_desc_col` 可能返回 0，导致名称和描述重叠

2. **换行质量下降**: 24 列宽度下，每行只能显示很少字符，换行频繁
   - 从快照可见：描述 `xxxxxxxxxx` 被拆分为多行

3. **选择指示器占用空间**: `› 1. ` 前缀占用 5 列，在 24 列宽度下占比过高

4. **可读性极限**: 24 列已接近可用性的边界，再窄可能无法正常使用

### 快照观察

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

**关键观察**:
- 所有 3 个项目都正确显示（`1.`, `2.`, `3.`）
- 描述 `xxxxxxxxxx` 被拆分为两行（`xxxxxxxxx` + `x`）
- 换行后的描述有缩进，与名称对齐
- 标题 "Debug" 完整显示

### 改进建议

1. **最小宽度限制**: 设置合理的最低宽度，低于此宽度显示警告
   ```rust
   const MIN_USABLE_WIDTH: u16 = 40;
   if width < MIN_USABLE_WIDTH {
       render_width_warning(area, buf);
       return;
   }
   ```

2. **简化模式**: 在极窄宽度下自动切换到简化布局
   - 隐藏描述，仅显示名称
   - 使用更紧凑的选择指示器（如仅 `>` 而非 `›`）

3. **描述截断**: 在窄宽度下优先截断描述而非换行
   ```rust
   if width < 40 {
       // 单行模式，描述截断
       render_rows_single_line(...)
   } else {
       // 正常换行模式
       render_rows(...)
   }
   ```

4. **水平滚动**: 对于极窄宽度，考虑支持水平滚动而非强制换行

5. **响应式前缀**: 根据宽度动态调整前缀长度
   ```rust
   let prefix = if width < 30 {
       format!("{prefix}")  // 仅选择指示器
   } else {
       format!("{prefix} {n}. ")  // 完整前缀
   };
   ```

### 测试增强建议

1. 添加 20 列、16 列的极限测试
2. 添加 Unicode 字符（中文、emoji）的窄宽度测试
3. 添加长名称（20+ 字符）在窄宽度下的表现测试
4. 添加交互测试：验证在窄宽度下仍能正常选择和确认

### 相关测试

| 测试 | 描述 |
|------|------|
| `width_changes_do_not_hide_rows` | 验证 60-90 列宽度范围 |
| `snapshot_model_picker_width_80` | 标准宽度 80 列的对比 |
| `one_cell_width_falls_back_without_panic` | 极端 1 列宽度的安全测试 |

### 实际应用场景

此测试确保 Codex TUI 能在以下环境中正常工作：
- 分屏终端（如 tmux 垂直分割）
- 小尺寸笔记本屏幕
- 远程 SSH 会话（低带宽，小窗口）
- 嵌入式设备终端
