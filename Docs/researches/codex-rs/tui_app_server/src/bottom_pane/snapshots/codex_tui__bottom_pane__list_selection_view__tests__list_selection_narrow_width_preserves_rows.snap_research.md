# Research: list_selection_narrow_width_preserves_rows Snapshot Test

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates that the `ListSelectionView` component correctly preserves all row visibility even at very narrow terminal widths (24 columns). The test ensures that the selection popup remains usable in constrained terminal environments.

**Usage Scenario:**
- Users with small terminal windows or split-screen setups
- Mobile terminal applications with limited width
- Ensuring minimum usability standards across all supported terminal sizes

## 2. 功能点目的 (Purpose of the Feature)

The narrow width preservation feature serves to:

1. **Accessibility**: Ensure the UI remains functional at small terminal widths
2. **Row Preservation**: Guarantee all selection options remain visible regardless of width
3. **Graceful Degradation**: Adapt layout when side-by-side content cannot fit
4. **Minimum Viable Display**: Maintain readable text even with aggressive wrapping

The test specifically validates that:
- All three items (1., 2., 3.) are visible at 24-column width
- Descriptions wrap to multiple lines as needed
- The selection indicator (›) remains visible
- Row numbering is preserved

## 3. 具体技术实现 (Technical Implementation)

### Key Implementation Details:

**Minimum Width Handling:**
```rust
/// Minimum list width required before side-by-side layout activates
const MIN_LIST_WIDTH_FOR_SIDE: u16 = 40;
```

At 24 columns, the component falls back to a stacked layout (no side content) because 24 < 40.

**Row Measurement (`measure_rows_height`, lines 707-728):**
```rust
let rows_height = match self.col_width_mode {
    ColumnWidthMode::AutoVisible => measure_rows_height(
        &rows,
        &self.state,
        MAX_POPUP_ROWS,
        effective_rows_width.saturating_add(1),
    ),
    // ... other modes
};
```

**Description Wrapping:**
- When width is insufficient for side-by-side name/description layout
- Descriptions wrap to new lines under the name
- Indentation is calculated from the prefix width (`wrap_indent`)

### Test Setup:
- Creates three items with 10-character descriptions ("x".repeat(10))
- Renders at width 24 (very narrow)
- Validates that "3." appears in output (third option visible)

**Test Code:**
```rust
let desc = "x".repeat(10);
let items: Vec<SelectionItem> = (1..=3)
    .map(|idx| SelectionItem {
        name: format!("Item {idx}"),
        description: Some(desc.clone()),
        dismiss_on_select: true,
        ..Default::default()
    })
    .collect();
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files:

| File | Path | Description |
|------|------|-------------|
| `list_selection_view.rs` | `codex-rs/tui_app_server/src/bottom_pane/list_selection_view.rs` | Main component implementation |
| `selection_popup_common.rs` | `codex-rs/tui_app_server/src/bottom_pane/selection_popup_common.rs` | Row measurement and rendering |

### Key Functions:

1. **`ListSelectionView::desired_height()`** (lines 694-757)
   - Calculates height accounting for wrapped content
   - Uses `effective_rows_width` which accounts for side content

2. **`side_by_side_layout_widths()`** (lines 76-91)
   - Determines if side-by-side layout is possible
   - Returns `None` when width is insufficient

3. **`measure_rows_height()`** in `selection_popup_common.rs`
   - Calculates wrapped height for each row
   - Handles narrow widths by wrapping descriptions

### Test Location:
- **Test Function:** `snapshot_narrow_width_preserves_third_option()`
- **File:** `codex-rs/tui_app_server/src/bottom_pane/list_selection_view.rs` (lines 1527-1551)
- **Snapshot:** `codex_tui__bottom_pane__list_selection_view__tests__list_selection_narrow_width_preserves_rows.snap`

### Related Tests:
- `narrow_width_keeps_all_rows_visible()`: Unit test version without snapshot
- `width_changes_do_not_hide_rows()`: Tests range of widths 60-90

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Dependencies:

```rust
// External crates
ratatui::layout::Rect
unicode_width::UnicodeWidthStr
textwrap  // For wrapping descriptions

// Internal modules
super::selection_popup_common::measure_rows_height
super::popup_consts::MAX_POPUP_ROWS
```

### Layout Constants:

```rust
const MIN_LIST_WIDTH_FOR_SIDE: u16 = 40;
const SIDE_CONTENT_GAP: u16 = 2;
const MENU_SURFACE_HORIZONTAL_INSET: u16 = 4;
```

### Rendering Flow:

1. `render()` calculates `inner_width = popup_content_width(total_width)`
2. `side_layout_width()` checks if side-by-side is possible
3. At 24 columns, side-by-side is disabled (24 < 40)
4. `build_rows()` creates rows with `wrap_indent` set
5. `render_rows()` wraps descriptions as needed

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks and Edge Cases:

1. **Extreme Narrowness**: Below ~20 columns, even item names may not fit
2. **Description Overflow**: Very long descriptions can consume excessive vertical space
3. **Row Visibility**: With many items and wrapping, some items may scroll out of view
4. **Unicode Width**: CJK characters count as width 2; "24 columns" may fit fewer characters

### Current Limitations:

1. **No Minimum Width Enforcement**: The component attempts to render at any width
2. **No Horizontal Scroll**: Content that doesn't fit is truncated, not scrollable
3. **Fixed MAX_POPUP_ROWS**: Maximum 10 rows visible; wrapped content counts toward this limit

### Improvement Suggestions:

1. **Minimum Width Warning**: Display a warning when terminal is too narrow:
   ```rust
   if width < MIN_VIABLE_WIDTH {
       return Box::new(WarningView::new(
           "Terminal too narrow. Please resize to at least 40 columns."
       ));
   }
   ```

2. **Adaptive Description Display**: Hide descriptions entirely when width is critical:
   ```rust
   if width < DESCRIPTION_MIN_WIDTH {
       // Show only item names
       rows.iter_mut().for_each(|r| r.description = None);
   }
   ```

3. **Horizontal Scroll Option**: For very long item names, consider horizontal scrolling:
   ```rust
   enum OverflowBehavior {
       Wrap,      // Current: wrap to next line
       Truncate,  // Cut with "..."
       Scroll,    // Horizontal scroll on focus
   }
   ```

4. **Test Coverage**:
   - Add test at 10 columns (extreme case)
   - Add test with CJK characters
   - Add test with 20+ items to verify scrolling behavior

### Maintenance Notes:

- The snapshot shows wrapped descriptions indented under item names
- "x" characters in snapshot represent the 10-character test description
- Changes to wrapping indentation will require snapshot update
- This test guards against regression where rows might be hidden at narrow widths
