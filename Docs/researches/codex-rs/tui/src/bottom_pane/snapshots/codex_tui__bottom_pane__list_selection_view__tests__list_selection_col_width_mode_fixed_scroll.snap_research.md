# Research: list_selection_col_width_mode_fixed_scroll

## 1. Feature Overview

This snapshot tests the `ColumnWidthMode::Fixed` behavior in `ListSelectionView`, which uses a constant 30/70 split between the name column (30%) and description column (70%) regardless of content. This provides predictable, stable column alignment that doesn't change during scrolling.

## 2. Code Location

- **Test Function**: `snapshot_fixed_col_width_mode_scroll_behavior` in `list_selection_view.rs` (line ~1170)
- **Source Module**: `codex-rs/tui/src/bottom_pane/list_selection_view.rs`
- **Related Module**: `codex-rs/tui/src/bottom_pane/selection_popup_common.rs`

## 3. Snapshot Description

The snapshot captures a before/after comparison of a selection list with 9 items when scrolled:

**Before scroll** (showing items 1-8):
- Description column is at a fixed position (30% of width)
- Item names are padded/truncated to fit the 30% left column
- "desc 1" through "desc 8" all align at the same column position

**After scroll** (showing items 2-9):
- Description column remains at exactly the same position
- Item 9's long name ("Item 9 with an intentionally much longer name") is truncated with ellipsis
- Column positions do NOT shift during scroll

## 4. Key Concepts

### ColumnWidthMode::Fixed

```rust
/// Use a fixed two-column split: 30% left (name), 70% right (description).
Fixed,
```

### Fixed Split Constants

```rust
const FIXED_LEFT_COLUMN_NUMERATOR: usize = 3;
const FIXED_LEFT_COLUMN_DENOMINATOR: usize = 10;
```

### compute_desc_col for Fixed Mode

```rust
ColumnWidthMode::Fixed => ((content_width as usize * FIXED_LEFT_COLUMN_NUMERATOR)
    / FIXED_LEFT_COLUMN_DENOMINATOR)
    .clamp(1, max_desc_col),
```

At width 96, the description column is at position 28 (96 * 3/10 = 28.8, clamped).

## 5. Test Setup

```rust
#[test]
fn snapshot_fixed_col_width_mode_scroll_behavior() {
    assert_snapshot!(
        "list_selection_col_width_mode_fixed_scroll",
        render_before_after_scroll_snapshot(ColumnWidthMode::Fixed, 96)
    );
}
```

The helper function `render_before_after_scroll_snapshot`:
- Creates a list with 8 short-named items and 1 long-named item
- Renders before scrolling (items 1-8 visible)
- Scrolls down 8 times (items 2-9 visible)
- Returns combined before/after output

## 6. Dependencies

- `selection_popup_common::ColumnWidthMode` - Enum defining column width calculation modes
- `selection_popup_common::measure_rows_height_with_col_width_mode` - Height measurement
- `selection_popup_common::render_rows_with_col_width_mode` - Rendering with explicit mode
- `FIXED_LEFT_COLUMN_NUMERATOR/DENOMINATOR` - Constants for 30/70 split

## 7. Related Snapshots

| Snapshot | Description |
|----------|-------------|
| `list_selection_col_width_mode_auto_visible_scroll` | Dynamic columns based on visible rows |
| `list_selection_col_width_mode_auto_all_rows_scroll` | Dynamic columns based on all rows |

## 8. Behavioral Implications

**Trade-offs of Fixed Mode:**
- **Pros**: Predictable layout, columns never shift during scroll, consistent visual alignment
- **Cons**: May waste space if all items are short, or truncate long item names unnecessarily
- **Best for**: Lists with highly variable item name lengths where stable alignment is preferred

**Comparison with test `fixed_col_width_is_30_70_and_does_not_shift_when_scrolling`:**
This snapshot test is complemented by a unit test that verifies:
```rust
let expected_desc_col = ((width.saturating_sub(2) as usize) * 3) / 10;
assert_eq!(before_col, expected_desc_col);
assert_eq!(before_col, after_col); // Column does not shift
```
