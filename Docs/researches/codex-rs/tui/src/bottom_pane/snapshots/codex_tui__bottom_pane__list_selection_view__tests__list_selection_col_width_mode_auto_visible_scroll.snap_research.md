# Research: list_selection_col_width_mode_auto_visible_scroll

## 1. Feature Overview

This snapshot tests the `ColumnWidthMode::AutoVisible` behavior in `ListSelectionView`, which dynamically calculates column widths based only on the rows currently visible in the viewport. This mode allows the layout to adapt tightly to the current viewport content, optimizing horizontal space usage.

## 2. Code Location

- **Test Function**: `snapshot_auto_visible_col_width_mode_scroll_behavior` in `list_selection_view.rs` (line ~1154)
- **Source Module**: `codex-rs/tui/src/bottom_pane/list_selection_view.rs`
- **Related Module**: `codex-rs/tui/src/bottom_pane/selection_popup_common.rs`

## 3. Snapshot Description

The snapshot captures a before/after comparison of a selection list with 9 items when scrolled:

**Before scroll** (showing items 1-8):
- The description column is positioned close to the item names since all visible items have short names
- Column placement: "desc 1" appears immediately after "Item 1"

**After scroll** (showing items 2-9):
- Item 9 has a much longer name: "Item 9 with an intentionally much longer name"
- The description column shifts right to accommodate the longer visible item name
- This demonstrates that `AutoVisible` recalculates column positions based on currently visible rows

## 4. Key Concepts

### ColumnWidthMode::AutoVisible

```rust
/// Derive column placement from only the visible viewport rows.
#[default]
AutoVisible,
```

- Measures only rows visible in the viewport to determine column widths
- Allows dynamic layout adaptation as user scrolls
- May cause column positions to shift during scroll when item name lengths vary significantly

### compute_desc_col for AutoVisible

```rust
ColumnWidthMode::AutoVisible => rows_all
    .iter()
    .enumerate()
    .skip(start_idx)
    .take(visible_items)
    .map(|(_, row)| { /* calculate name width */ })
    .max()
    .unwrap_or(0),
```

## 5. Test Setup

```rust
fn render_before_after_scroll_snapshot(col_width_mode: ColumnWidthMode, width: u16) -> String {
    let items = make_scrolling_width_items(); // 8 short items + 1 long item
    let mut view = ListSelectionView::new(
        SelectionViewParams {
            title: Some("Debug".to_string()),
            items,
            col_width_mode,
            ..Default::default()
        },
        tx,
    );

    let before_scroll = render_lines_with_width(&view, width);
    for _ in 0..8 {
        view.handle_key_event(KeyEvent::from(KeyCode::Down));
    }
    let after_scroll = render_lines_with_width(&view, width);
    
    format!("before scroll:\n{before_scroll}\n\nafter scroll:\n{after_scroll}")
}
```

## 6. Dependencies

- `selection_popup_common::ColumnWidthMode` - Enum defining column width calculation modes
- `selection_popup_common::measure_rows_height` - Height measurement for AutoVisible mode
- `selection_popup_common::render_rows` - Rendering function for AutoVisible mode
- `ScrollState` - Tracks scroll position and selected index

## 7. Related Snapshots

| Snapshot | Description |
|----------|-------------|
| `list_selection_col_width_mode_auto_all_rows_scroll` | Same test with `AutoAllRows` mode (stable columns) |
| `list_selection_col_width_mode_fixed_scroll` | Same test with `Fixed` mode (30/70 split) |

## 8. Behavioral Implications

**Trade-offs of AutoVisible:**
- **Pros**: Tight layout, maximizes available space for descriptions
- **Cons**: Column positions may shift during scroll when item name lengths vary
- **Best for**: Lists where items have similar name lengths, or when maximizing content density is priority

**Comparison with other modes:**
- `AutoAllRows`: Measures all rows for stable column positions (no shift during scroll)
- `Fixed`: Uses constant 30/70 split regardless of content
