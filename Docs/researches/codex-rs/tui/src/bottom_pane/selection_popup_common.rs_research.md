# selection_popup_common.rs 深度研究文档

## 场景与职责

`selection_popup_common.rs` 是 Codex TUI 底部面板中**选择弹出窗口的通用渲染基础设施**。该模块为各种选择列表（命令选择、技能选择、模型选择等）提供统一的渲染逻辑、布局计算和视觉样式。

主要场景：
1. **列表选择视图**：通用的单选列表（`ListSelectionView`）
2. **命令弹出窗口**：`/` 触发的斜杠命令列表
3. **技能弹出窗口**：`$` 触发的 mention 列表
4. **文件搜索弹出窗口**：文件选择
5. **任何需要两列布局（名称+描述）的选择 UI**

## 功能点目的

### 1. 通用行渲染
- **功能**：`GenericDisplayRow` 结构体
- **目的**：统一表示选择列表中的一行，支持名称、描述、快捷键、禁用状态等

### 2. 多列布局模式
- **模式**：`AutoVisible`, `AutoAllRows`, `Fixed`
- **目的**：适应不同数据特征和屏幕尺寸

### 3. 智能文本包装
- **功能**：`wrap_row_lines`, `wrap_two_column_row`
- **目的**：处理长名称和长描述，保持列表可读性

### 4. 滚动视口管理
- **功能**：`compute_item_window_start`, `adjust_start_for_wrapped_selection_visibility`
- **目的**：确保选中项在包装行后仍然可见

### 5. 菜单表面渲染
- **功能**：`render_menu_surface`, `menu_surface_inset`
- **目的**：统一的弹出窗口背景和边框样式

## 具体技术实现

### 核心数据结构

```rust
/// Render-ready representation of one row in a selection popup.
#[derive(Default)]
pub(crate) struct GenericDisplayRow {
    pub name: String,
    pub name_prefix_spans: Vec<Span<'static>>,  // 名称前缀（如图标）
    pub display_shortcut: Option<KeyBinding>,    // 显示快捷键
    pub match_indices: Option<Vec<usize>>,       // 模糊匹配高亮位置
    pub description: Option<String>,             // 描述文本
    pub category_tag: Option<String>,            // 右侧分类标签
    pub disabled_reason: Option<String>,         // 禁用原因
    pub is_disabled: bool,
    pub wrap_indent: Option<usize>,              // 包装行缩进
}

/// Controls how selection rows choose the split between left/right columns.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) enum ColumnWidthMode {
    /// Derive column placement from only the visible viewport rows.
    #[default]
    AutoVisible,
    /// Derive column placement from all rows so scrolling does not shift columns.
    AutoAllRows,
    /// Use a fixed two-column split: 30% left (name), 70% right (description).
    Fixed,
}
```

### 菜单表面渲染

```rust
const MENU_SURFACE_INSET_V: u16 = 1;  // 垂直内边距
const MENU_SURFACE_INSET_H: u16 = 2;  // 水平内边距

/// Apply the shared "menu surface" padding used by bottom-pane overlays.
pub(crate) fn menu_surface_inset(area: Rect) -> Rect {
    area.inset(Insets::vh(MENU_SURFACE_INSET_V, MENU_SURFACE_INSET_H))
}

/// Paint the shared menu background and return the inset content area.
pub(crate) fn render_menu_surface(area: Rect, buf: &mut Buffer) -> Rect {
    if area.is_empty() {
        return area;
    }
    Block::default()
        .style(user_message_style())
        .render(area, buf);
    menu_surface_inset(area)
}
```

### 列宽计算

```rust
const FIXED_LEFT_COLUMN_NUMERATOR: usize = 3;      // 30%
const FIXED_LEFT_COLUMN_DENOMINATOR: usize = 10;   // 分母

fn compute_desc_col(
    rows_all: &[GenericDisplayRow],
    start_idx: usize,
    visible_items: usize,
    content_width: u16,
    col_width_mode: ColumnWidthMode,
) -> usize {
    if content_width <= 1 {
        return 0;
    }

    let max_desc_col = content_width.saturating_sub(1) as usize;
    let max_auto_desc_col = max_desc_col.min(
        ((content_width as usize * (FIXED_LEFT_COLUMN_DENOMINATOR - FIXED_LEFT_COLUMN_NUMERATOR))
            / FIXED_LEFT_COLUMN_DENOMINATOR)
            .max(1),
    );

    match col_width_mode {
        ColumnWidthMode::Fixed => {
            // 固定 30/70 分割
            ((content_width as usize * FIXED_LEFT_COLUMN_NUMERATOR)
                / FIXED_LEFT_COLUMN_DENOMINATOR)
                .clamp(1, max_desc_col)
        }
        ColumnWidthMode::AutoVisible => {
            // 基于可见行计算
            let max_name_width = rows_all
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
                .unwrap_or(0);
            max_name_width.saturating_add(2).min(max_auto_desc_col)
        }
        ColumnWidthMode::AutoAllRows => {
            // 基于所有行计算（滚动时列宽稳定）
            let max_name_width = rows_all
                .iter()
                .map(|row| /* ... */)
                .max()
                .unwrap_or(0);
            max_name_width.saturating_add(2).min(max_auto_desc_col)
        }
    }
}
```

### 双列行包装

```rust
fn wrap_two_column_row(row: &GenericDisplayRow, desc_col: usize, width: u16) -> Vec<Line<'static>> {
    let Some(description) = row.description.as_deref() else {
        return Vec::new();
    };

    let width = width.max(1);
    let max_desc_col = width.saturating_sub(1) as usize;
    if max_desc_col == 0 {
        return Vec::new();
    }

    let desc_col = desc_col.clamp(1, max_desc_col);
    let left_width = desc_col.saturating_sub(2).max(1);
    let right_width = width.saturating_sub(desc_col as u16).max(1) as usize;

    // 分别包装名称和描述
    let name_options = textwrap::Options::new(left_width)
        .initial_indent("")
        .subsequent_indent(" ".repeat(name_wrap_indent).as_str());
    let name_lines = textwrap::wrap(row.name.as_str(), name_options);

    let desc_options = textwrap::Options::new(right_width).initial_indent("");
    let desc_lines = textwrap::wrap(description, desc_options);

    // 合并为行对
    let rows = name_lines.len().max(desc_lines.len()).max(1);
    let mut out = Vec::with_capacity(rows);
    for idx in 0..rows {
        let mut spans: Vec<Span<'static>> = Vec::new();
        if let Some(name) = name_lines.get(idx) {
            spans.push(name.to_string().into());
        }
        if let Some(desc) = desc_lines.get(idx) {
            // 计算间隙对齐描述列
            let left_used = spans.iter()
                .map(|span| UnicodeWidthStr::width(span.content.as_ref()))
                .sum::<usize>();
            let gap = if left_used == 0 { desc_col } else {
                desc_col.saturating_sub(left_used).max(2)
            };
            if gap > 0 {
                spans.push(" ".repeat(gap).into());
            }
            spans.push(desc.to_string().dim());
        }
        out.push(Line::from(spans));
    }
    out
}
```

### 完整行构建

```rust
fn build_full_line(row: &GenericDisplayRow, desc_col: usize) -> Line<'static> {
    // 合并描述和禁用原因
    let combined_description = match (&row.description, &row.disabled_reason) {
        (Some(desc), Some(reason)) => Some(format!("{desc} (disabled: {reason})")),
        (Some(desc), None) => Some(desc.clone()),
        (None, Some(reason)) => Some(format!("disabled: {reason}")),
        (None, None) => None,
    };

    // 限制名称宽度，为描述留空间
    let name_limit = combined_description
        .as_ref()
        .map(|_| desc_col.saturating_sub(2).saturating_sub(name_prefix_width))
        .unwrap_or(usize::MAX);

    // 构建名称 spans，支持模糊匹配高亮
    let mut name_spans: Vec<Span> = Vec::with_capacity(row.name.len());
    let mut used_width = 0usize;
    let mut truncated = false;

    if let Some(idxs) = row.match_indices.as_ref() {
        let mut idx_iter = idxs.iter().peekable();
        for (char_idx, ch) in row.name.chars().enumerate() {
            let ch_w = UnicodeWidthChar::width(ch).unwrap_or(0);
            let next_width = used_width.saturating_add(ch_w);
            if next_width > name_limit {
                truncated = true;
                break;
            }
            used_width = next_width;

            if idx_iter.peek().is_some_and(|next| **next == char_idx) {
                idx_iter.next();
                name_spans.push(ch.to_string().bold());  // 高亮匹配字符
            } else {
                name_spans.push(ch.to_string().into());
            }
        }
    }

    if truncated {
        name_spans.push("…".into());  // 截断指示
    }

    // 构建完整行
    let mut full_spans: Vec<Span> = row.name_prefix_spans.clone();
    full_spans.extend(name_spans);
    // ... 添加快捷键、描述、标签等
    Line::from(full_spans)
}
```

### 行渲染

```rust
pub(crate) fn render_rows(
    area: Rect,
    buf: &mut Buffer,
    rows_all: &[GenericDisplayRow],
    state: &ScrollState,
    max_results: usize,
    empty_message: &str,
) -> u16 {
    render_rows_inner(
        area, buf, rows_all, state, max_results, empty_message,
        ColumnWidthMode::AutoVisible,
    )
}

pub(crate) fn render_rows_stable_col_widths(
    area: Rect,
    buf: &mut Buffer,
    rows_all: &[GenericDisplayRow],
    state: &ScrollState,
    max_results: usize,
    empty_message: &str,
) -> u16 {
    render_rows_inner(
        area, buf, rows_all, state, max_results, empty_message,
        ColumnWidthMode::AutoAllRows,
    )
}

fn render_rows_inner(
    area: Rect,
    buf: &mut Buffer,
    rows_all: &[GenericDisplayRow],
    state: &ScrollState,
    max_results: usize,
    empty_message: &str,
    col_width_mode: ColumnWidthMode,
) -> u16 {
    // 空列表处理
    if rows_all.is_empty() {
        if area.height > 0 {
            Line::from(empty_message.dim().italic()).render(area, buf);
        }
        return u16::from(area.height > 0);
    }

    // 计算可见窗口和描述列位置
    let start_idx = adjust_start_for_wrapped_selection_visibility(
        rows_all, state, max_items, desc_measure_items,
        area.width, area.height, col_width_mode,
    );
    let desc_col = compute_desc_col(rows_all, start_idx, desc_measure_items, area.width, col_width_mode);

    // 渲染可见行
    let mut cur_y = area.y;
    let mut rendered_lines: u16 = 0;
    for (i, row) in rows_all.iter().enumerate().skip(start_idx).take(max_items) {
        if cur_y >= area.y + area.height {
            break;
        }

        let mut wrapped = wrap_row_lines(row, desc_col, area.width);
        apply_row_state_style(
            &mut wrapped,
            Some(i) == state.selected_idx && !row.is_disabled,
            row.is_disabled,
        );

        // 渲染包装后的每一行
        for line in wrapped {
            if cur_y >= area.y + area.height {
                break;
            }
            line.render(/* ... */);
            cur_y = cur_y.saturating_add(1);
            rendered_lines = rendered_lines.saturating_add(1);
        }
    }
    rendered_lines
}
```

### 高度测量

```rust
pub(crate) fn measure_rows_height(
    rows_all: &[GenericDisplayRow],
    state: &ScrollState,
    max_results: usize,
    width: u16,
) -> u16 {
    measure_rows_height_inner(rows_all, state, max_results, width, ColumnWidthMode::AutoVisible)
}

fn measure_rows_height_inner(
    rows_all: &[GenericDisplayRow],
    state: &ScrollState,
    max_results: usize,
    width: u16,
    col_width_mode: ColumnWidthMode,
) -> u16 {
    if rows_all.is_empty() {
        return 1;  // placeholder "no matches" line
    }

    // 计算可见窗口
    let visible_items = max_results.min(rows_all.len());
    let mut start_idx = state.scroll_top.min(rows_all.len().saturating_sub(1));
    if let Some(sel) = state.selected_idx {
        if sel < start_idx {
            start_idx = sel;
        } else if visible_items > 0 {
            let bottom = start_idx + visible_items - 1;
            if sel > bottom {
                start_idx = sel + 1 - visible_items;
            }
        }
    }

    let desc_col = compute_desc_col(rows_all, start_idx, visible_items, content_width, col_width_mode);

    // 累加每行的包装后高度
    let mut total: u16 = 0;
    for row in rows_all.iter().enumerate().skip(start_idx).take(visible_items).map(|(_, r)| r) {
        let wrapped_lines = wrap_row_lines(row, desc_col, content_width).len();
        total = total.saturating_add(wrapped_lines as u16);
    }
    total.max(1)
}
```

## 关键代码路径与文件引用

### 主要使用者

| 使用者 | 文件路径 | 使用功能 |
|--------|----------|----------|
| `ListSelectionView` | `codex-rs/tui/src/bottom_pane/list_selection_view.rs` | `render_rows`, `measure_rows_height` |
| `CommandPopup` | `codex-rs/tui/src/bottom_pane/command_popup.rs` | `render_rows`, `GenericDisplayRow` |
| `SkillPopup` | `codex-rs/tui/src/bottom_pane/skill_popup.rs` | `render_rows_single_line` |
| `FileSearchPopup` | `codex-rs/tui/src/bottom_pane/file_search_popup.rs` | `render_menu_surface` |
| `McpServerElicitationOverlay` | `codex-rs/tui/src/bottom_pane/mcp_server_elicitation.rs` | `render_menu_surface` |
| `ExperimentalFeaturesView` | `codex-rs/tui/src/bottom_pane/experimental_features_view.rs` | `render_menu_surface` |
| `SkillsToggleView` | `codex-rs/tui/src/bottom_pane/skills_toggle_view.rs` | `render_menu_surface` |
| `AppLinkView` | `codex-rs/tui/src/bottom_pane/app_link_view.rs` | `render_menu_surface` |
| `MultiSelectPicker` | `codex-rs/tui/src/bottom_pane/multi_select_picker.rs` | `render_menu_surface` |
| `RequestUserInputOverlay` | `codex-rs/tui/src/bottom_pane/request_user_input/render.rs` | `render_menu_surface` |

### 模块导出

在 `bottom_pane/mod.rs` 中：

```rust
mod selection_popup_common;
pub(crate) use list_selection_view::ColumnWidthMode;  // 重导出
use super::selection_popup_common::GenericDisplayRow;
use super::selection_popup_common::measure_rows_height;
use super::selection_popup_common::render_menu_surface;
use super::selection_popup_common::render_rows;
```

### 样式应用

```rust
fn apply_row_state_style(lines: &mut [Line<'static>], selected: bool, is_disabled: bool) {
    if selected {
        for line in lines.iter_mut() {
            line.spans.iter_mut().for_each(|span| {
                span.style = Style::default().fg(Color::Cyan).bold();
            });
        }
    }
    if is_disabled {
        for line in lines.iter_mut() {
            line.spans.iter_mut().for_each(|span| {
                span.style = span.style.dim();
            });
        }
    }
}
```

## 依赖与外部交互

### 依赖模块

| 模块 | 用途 |
|------|------|
| `ratatui` | TUI 渲染基础（Buffer, Rect, Style, Line, Span, Widget） |
| `unicode_width` | Unicode 字符宽度计算 |
| `textwrap` | 文本包装 |
| `crate::key_hint::KeyBinding` | 快捷键显示 |
| `crate::render::Insets`, `RectExt` | 布局工具 |
| `crate::style::user_message_style` | 用户消息样式 |
| `crate::wrapping::{RtOptions, word_wrap_line}` | 文本包装工具 |
| `super::scroll_state::ScrollState` | 滚动状态 |

### 与 `ScrollState` 的交互

```rust
// 使用 ScrollState 确定渲染窗口
let start_idx = compute_item_window_start(rows_all, state, max_items);

// 确保选中项在包装行后可见
let start_idx = adjust_start_for_wrapped_selection_visibility(
    rows_all, state, max_items, desc_measure_items,
    width, viewport_height, col_width_mode,
);
```

## 风险、边界与改进建议

### 已知风险

1. **列宽计算与渲染不匹配**
   - `measure_rows_height` 和 `render_rows` 必须使用相同的 `ColumnWidthMode`
   - 否则可能导致预留高度与实际渲染高度不一致

2. **极窄宽度处理**
   - 当宽度小于描述列位置时，某些路径可能产生意外结果
   - 当前有 `max_desc_col == 0` 的提前返回，但边缘情况仍需注意

3. **性能问题**
   - `AutoAllRows` 模式需要遍历所有行计算最大名称宽度
   - 对于极长列表可能影响性能

4. **Unicode 宽度计算**
   - 依赖 `unicode_width` 计算显示宽度
   - 某些特殊字符（如 emoji）的宽度计算可能不准确

### 边界条件

| 场景 | 行为 |
|------|------|
| 空列表 | 显示占位消息 "no matches" |
| 宽度 <= 1 | `compute_desc_col` 返回 0 |
| 选中项在包装行后 | `adjust_start_for_wrapped_selection_visibility` 调整视口 |
| 描述列为 None | 使用 `wrap_standard_row` 而非双列布局 |
| 行被禁用 | 应用 `dim()` 样式 |
| 行被选中 | 应用青色粗体样式 |

### 测试覆盖

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use pretty_assertions::assert_eq;

    #[test]
    fn one_cell_width_falls_back_without_panic_for_wrapped_two_column_rows() {
        let row = GenericDisplayRow {
            name: "1. Very long option label".to_string(),
            description: Some("Very long description".to_string()),
            wrap_indent: Some(4),
            ..Default::default()
        };

        let two_col = wrap_two_column_row(&row, 0, 1);
        assert_eq!(two_col.len(), 0);  // 极窄宽度下返回空
    }
}
```

### 改进建议

1. **缓存列宽计算**
   - 对于 `AutoAllRows` 模式，缓存最大名称宽度
   - 仅在数据变化时重新计算

2. **动态列宽调整**
   - 根据内容动态调整左右列比例
   - 如描述普遍较长时增加右列比例

3. **更好的截断指示**
   - 当前仅显示 "…"
   - 可添加悬停提示显示完整内容

4. **图标支持增强**
   - `name_prefix_spans` 支持任意 spans
   - 可添加更多内置图标类型

5. **多行描述优化**
   - 当前描述包装后可能与名称行数不匹配
   - 可考虑限制描述最大行数

6. **可访问性**
   - 添加选中项的屏幕阅读器提示
   - 支持高对比度模式

7. **动画过渡**
   - 列宽变化时添加平滑过渡
   - 滚动时添加视觉反馈

### 相关文件

- `codex-rs/tui/src/bottom_pane/scroll_state.rs`：滚动状态管理
- `codex-rs/tui/src/bottom_pane/list_selection_view.rs`：通用选择视图
- `codex-rs/tui/src/bottom_pane/command_popup.rs`：命令弹出窗口
- `codex-rs/tui/src/bottom_pane/skill_popup.rs`：技能弹出窗口
- `codex-rs/tui/src/wrapping.rs`：文本包装工具
- `codex-rs/tui/styles.md`：样式约定
