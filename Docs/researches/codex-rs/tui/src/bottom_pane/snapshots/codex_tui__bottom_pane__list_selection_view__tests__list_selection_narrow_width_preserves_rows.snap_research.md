# Research: list_selection_narrow_width_preserves_rows

## 1. Feature Overview

This snapshot tests the `ListSelectionView` rendering at an extremely narrow width (24 columns). It verifies that all selection items remain visible even when horizontal space is severely constrained, demonstrating the component's responsive layout capabilities.

## 2. Code Location

- **Test Function**: `snapshot_narrow_width_preserves_third_option` in `list_selection_view.rs` (line ~1527)
- **Source Module**: `codex-rs/tui/src/bottom_pane/list_selection_view.rs`
- **Related Test**: `narrow_width_keeps_all_rows_visible` (unit test)

## 3. Snapshot Description

The snapshot shows a selection popup at 24 columns width containing three items:

**Header:**
- Title: "Debug"

**List Items:**

1. **Item 1** (selected)
   ```
   › 1. Item 1
n              xxxxxxxxx
              x
   ```

2. **Item 2**
   ```
     2. Item 2
              xxxxxxxxx
              x
   ```

3. **Item 3**
   ```
     3. Item 3
              xxxxxxxxx
              x
   ```

At this narrow width:
- Item names and descriptions wrap to separate lines
- Descriptions (10 'x' characters) appear on their own lines with indentation
- All three items remain visible despite the constraint

## 4. Key Concepts

### Responsive Layout at Narrow Widths

When width is insufficient for side-by-side name/description layout:

1. **Name wraps first** - The item name takes available space
2. **Description moves below** - Description appears on subsequent lines
3. **Indentation preserved** - Wrapped lines maintain visual alignment via `wrap_indent`

### wrap_indent Mechanism

```rust
let wrap_indent = description.is_none().then_some(wrap_prefix_width);
```

For items with descriptions, wrapped lines are indented to align with where the description would start.

### Minimum Viable Width

The test verifies that even at 24 columns:
- All items are rendered
- Selection indicator (›) is visible
- Item numbering is preserved
- Descriptions remain readable (though wrapped)

## 5. Test Setup

```rust
#[test]
fn snapshot_narrow_width_preserves_third_option() {
    let desc = "x".repeat(10); // 10-character description
    let items: Vec<SelectionItem> = (1..=3)
        .map(|idx| SelectionItem {
            name: format!("Item {idx}"),
            description: Some(desc.clone()),
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
        render_lines_with_width(&view, 24)
    );
}
```

## 6. Dependencies

- `SelectionItem` - Data model with description support
- `GenericDisplayRow::wrap_indent` - Controls wrapped line indentation
- `wrap_row_lines` - Handles multi-line wrapping with indentation
- `ColumnWidthMode::AutoVisible` (default)

## 7. Related Snapshots

| Snapshot | Description |
|----------|-------------|
| `list_selection_model_picker_width_80` | Same pattern at comfortable width (80 columns) |

## 8. Related Unit Tests

| Test | Purpose |
|------|---------|
| `narrow_width_keeps_all_rows_visible` | Verifies item 3 is present at width 24 |
| `width_changes_do_not_hide_rows` | Verifies all items visible across widths 60-90 |

## 9. Layout Behavior

**At 24 columns:**
- Item number + name: "› 1. Item 1" (11 chars) fits on first line
- Description wraps to: "xxxxxxxxxx" split across 2 lines with 14-space indent
- The indent (14) = prefix width ("› 1. " = 5) + name ("Item 1" = 6) + gap (2) ≈ 13-14

**Key Insight:**
The component gracefully degrades from a two-column layout to a stacked layout as width decreases, ensuring content remains accessible even in extreme constraints.
