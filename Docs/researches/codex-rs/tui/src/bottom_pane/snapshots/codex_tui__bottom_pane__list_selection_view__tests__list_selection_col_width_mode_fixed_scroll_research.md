# 快照研究文档: list_selection_col_width_mode_fixed_scroll

## 场景与职责

此快照测试验证 `ListSelectionView` 在 **Fixed** 列宽模式下的滚动行为。该模式的核心职责是：**使用固定的 30/70 比例分割名称列和描述列，完全不依赖内容动态计算，提供最稳定的布局体验**。

测试场景：
- 创建一个包含 9 个项目的列表，其中第 9 项具有明显更长的名称
- 在 96 列宽度的终端中渲染，记录滚动前后的布局
- 验证描述列位置严格遵循 30/70 固定比例，不受内容长度影响

## 功能点目的

**Fixed 模式** 的设计目的是提供**完全确定的布局行为**：

1. **绝对稳定性**: 列宽完全由终端宽度决定，与内容无关，滚动时零抖动
2. **可预测性**: 用户和开发者都能准确预知布局表现
3. **简化心智模型**: 不需要理解复杂的动态计算逻辑
4. **适用场景**: 需要严格布局控制的场景，如固定格式的配置界面

## 具体技术实现

### 固定比例常量定义

```rust
// selection_popup_common.rs:58-61
const FIXED_LEFT_COLUMN_NUMERATOR: usize = 3;      // 30%
const FIXED_LEFT_COLUMN_DENOMINATOR: usize = 10;   // 分母
```

### 列宽计算逻辑

```rust
// selection_popup_common.rs:145-147
ColumnWidthMode::Fixed => ((content_width as usize * FIXED_LEFT_COLUMN_NUMERATOR)
    / FIXED_LEFT_COLUMN_DENOMINATOR)
    .clamp(1, max_desc_col)
```

计算过程：
- 内容宽度 × 30% = 名称列宽度
- 描述列起始位置 = 名称列宽度
- 最小保证 1 列，最大不超过 `max_desc_col`（内容宽度 - 1）

### 与动态模式的本质区别

```rust
// selection_popup_common.rs:144-182
match col_width_mode {
    ColumnWidthMode::Fixed => {
        // 纯数学计算，不访问 rows_all 数据
        ((content_width as usize * FIXED_LEFT_COLUMN_NUMERATOR)
            / FIXED_LEFT_COLUMN_DENOMINATOR)
            .clamp(1, max_desc_col)
    }
    ColumnWidthMode::AutoVisible | ColumnWidthMode::AutoAllRows => {
        // 需要遍历 rows_all 计算最大名称宽度
        let max_name_width = /* ... */;
        max_name_width.saturating_add(2).min(max_auto_desc_col)
    }
}
```

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/bottom_pane/list_selection_view.rs` | 测试用例定义（第 1062 行） |
| `codex-rs/tui/src/bottom_pane/selection_popup_common.rs` | 固定比例常量和计算逻辑（第 58-61, 145-147 行） |

### 关键函数路径

1. **测试入口**: `list_selection_view.rs:1069-1075`
   ```rust
   #[test]
   fn snapshot_fixed_col_width_mode_scroll_behavior() {
       assert_snapshot!(
           "list_selection_col_width_mode_fixed_scroll",
           render_before_after_scroll_snapshot(ColumnWidthMode::Fixed, 96)
       );
   }
   ```

2. **固定列宽验证测试**: `list_selection_view.rs:1612-1643`
   ```rust
   #[test]
   fn fixed_col_width_is_30_70_and_does_not_shift_when_scrolling() {
       let width = 96;
       let expected_desc_col = ((width.saturating_sub(2) as usize) * 3) / 10;
       // 验证描述列位于 30% 位置
       assert_eq!(before_col, expected_desc_col);
       // 验证滚动前后位置不变
       assert_eq!(before_col, after_col);
   }
   ```

3. **渲染函数**: `selection_popup_common.rs:644-662`
   - `render_rows_with_col_width_mode()` 支持传入任意 `ColumnWidthMode`

### 计算示例

对于 96 列宽度：
```
内容宽度 = 96 - 2（边框）= 94
名称列宽度 = 94 × 30% = 28
描述列起始位置 = 28
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `selection_popup_common` | 固定比例常量和渲染函数 |
| `list_selection_view` | 测试用例和视图实现 |

### 常量定义位置

```rust
// selection_popup_common.rs
const FIXED_LEFT_COLUMN_NUMERATOR: usize = 3;      // 30%
const FIXED_LEFT_COLUMN_DENOMINATOR: usize = 10;   // 100%
const MENU_SURFACE_INSET_V: u16 = 1;
const MENU_SURFACE_INSET_H: u16 = 2;
```

### 外部 Crate

| Crate | 用途 |
|-------|------|
| `ratatui` | 布局计算和渲染 |
| `insta` | 快照测试 |

## 风险边界与改进建议

### 当前风险边界

1. **内容截断**: 固定比例可能导致长名称被截断
   - 从快照可见：第 9 项名称显示为 `"Item 9 with an intent…"`（带省略号）

2. **空间浪费**: 短名称项目会浪费左侧空间，右侧描述区域相对变小

3. **比例僵化**: 30/70 是硬编码的，无法适应不同内容类型的需求

4. **窄终端问题**: 在极窄终端中，30% 可能不足以显示任何有意义的名称

### 快照观察

```
before scroll:
› 1. Item 1                 desc 1      # 名称后有空隙，描述从固定位置开始

after scroll:
› 9. Item 9 with an intent… desc 9      # 长名称被截断，但描述列位置不变
```

**关键观察**: 
- 描述列位置在滚动前后完全一致
- 超长名称被截断并添加省略号（`…`）
- 布局严格遵循 30/70 比例

### 改进建议

1. **可配置比例**: 允许调用者指定自定义比例（如 40/60 或 50/50）
   ```rust
   pub(crate) enum ColumnWidthMode {
       Fixed { left_ratio: u8 },  // 例如 Fixed { left_ratio: 40 }
       // ...
   }
   ```

2. **最小宽度保护**: 为名称列设置最小宽度，确保在窄终端中仍有基本可读性
   ```rust
   .clamp(MIN_NAME_WIDTH, max_desc_col)
   ```

3. **智能截断**: 截断时优先保留名称的关键部分（如文件扩展名、后缀）

4. **混合策略**: 结合 Fixed 和 Auto 的优点：
   - 基础布局使用 Fixed 比例
   - 如果内容超出，允许动态调整但限制调整范围

5. **响应式比例**: 根据终端宽度动态调整比例：
   - 宽终端（>120 列）：30/70
   - 中终端（80-120 列）：40/60
   - 窄终端（<80 列）：50/50 或完全堆叠

### 测试增强建议

1. 测试极端宽度（40 列、200 列）下的布局表现
2. 测试比例计算精度（验证 30/70 的数学正确性）
3. 添加截图对比测试，可视化展示三种模式的差异
4. 测试截断逻辑（验证省略号正确添加）

### 使用建议

| 场景 | 推荐模式 | 原因 |
|------|----------|------|
| 模型选择器 | `AutoAllRows` | 名称长度差异大，需要稳定布局 |
| 配置菜单 | `Fixed` | 界面简洁，追求绝对稳定 |
| 搜索结果 | `AutoVisible` | 需要紧凑布局，内容动态变化 |
| 长列表（100+）| `AutoVisible` | 性能考虑，避免遍历所有行 |
