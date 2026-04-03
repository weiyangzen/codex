# Research: list_selection_spacing_with_subtitle

## 1. Feature Overview

This snapshot tests the vertical spacing layout of `ListSelectionView` when both a title and subtitle are provided. It verifies that a blank line appears between the subtitle and the list items, creating proper visual separation in the popup header.

## 2. Code Location

- **Test Function**: `renders_blank_line_between_subtitle_and_items` in `list_selection_view.rs` (line ~1161)
- **Source Module**: `codex-rs/tui/src/bottom_pane/list_selection_view.rs`
- **Comparison Test**: `renders_blank_line_between_title_and_items_without_subtitle`

## 3. Snapshot Description

The snapshot shows a selection popup with both title and subtitle:

```
                                                
  Select Approval Mode                          
  Switch between Codex approval presets         
                                                
› 1. Read Only (current)  Codex can read files
  2. Full Access          Codex can edit files
                                                
  Press enter to confirm or esc to go back
```

**Layout Structure:**
1. Blank line (top padding)
2. Title: "Select Approval Mode" (bold)
3. Subtitle: "Switch between Codex approval presets" (dim)
4. **Blank line** (separator between header and items)
5. List items
6. Blank line (separator)
7. Footer hint

## 4. Key Concepts

### Header Composition with Subtitle

```rust
if params.title.is_some() || params.subtitle.is_some() {
    let title = params.title.map(|title| Line::from(title.bold()));
    let subtitle = params.subtitle.map(|subtitle| Line::from(subtitle.dim()));
    header = Box::new(ColumnRenderable::with([
        header,
        Box::new(title),
        Box::new(subtitle),
    ]));
}
```

### Vertical Spacing Rules

The layout always includes:
- 1 blank line after the menu surface border (top)
- 1 blank line between header (title/subtitle) and list items
- 1 blank line between list items and footer

### Header Rendering

```rust
let [header_area, _, search_area, list_area, _, stacked_side_area] = Layout::vertical([
    Constraint::Max(header_height),
    Constraint::Max(1),  // <- This is the blank line separator
    Constraint::Length(if self.is_searchable { 1 } else { 0 }),
    Constraint::Length(rows_height),
    // ...
])
```

## 5. Test Setup

```rust
fn make_selection_view(subtitle: Option<&str>) -> ListSelectionView {
    let items = vec![
        SelectionItem {
            name: "Read Only".to_string(),
            description: Some("Codex can read files".to_string()),
            is_current: true,
            dismiss_on_select: true,
            ..Default::default()
        },
        SelectionItem {
            name: "Full Access".to_string(),
            description: Some("Codex can edit files".to_string()),
            is_current: false,
            dismiss_on_select: true,
            ..Default::default()
        },
    ];
    ListSelectionView::new(
        SelectionViewParams {
            title: Some("Select Approval Mode".to_string()),
            subtitle: subtitle.map(str::to_string),  // "Switch between Codex approval presets"
            footer_hint: Some(standard_popup_hint_line()),
            items,
            ..Default::default()
        },
        tx,
    )
}

#[test]
fn renders_blank_line_between_subtitle_and_items() {
    let view = make_selection_view(Some("Switch between Codex approval presets"));
    assert_snapshot!("list_selection_spacing_with_subtitle", render_lines(&view));
}
```

## 6. Dependencies

- `SelectionViewParams::title` - Main header text
- `SelectionViewParams::subtitle` - Secondary header text (dimmed)
- `ColumnRenderable` - Stacks header elements vertically
- `standard_popup_hint_line()` - Standard footer hint

## 7. Related Snapshots

| Snapshot | Description |
|----------|-------------|
| `list_selection_spacing_without_subtitle` | Same view without subtitle (different spacing) |

## 8. Comparison: With vs Without Subtitle

**With Subtitle (this snapshot):**
```
  Select Approval Mode
  Switch between Codex approval presets
  
› 1. Read Only...
```

**Without Subtitle:**
```
  Select Approval Mode
  
› 1. Read Only...
```

**Key Difference:**
- With subtitle: Title and subtitle appear consecutively, then blank line, then items
- Without subtitle: Title appears, then blank line, then items

The blank line separator is always present between the header section and the list items, regardless of whether a subtitle exists.
