# Research: list_selection_spacing_without_subtitle

## 1. Feature Overview

This snapshot tests the vertical spacing layout of `ListSelectionView` when only a title is provided (no subtitle). It verifies the proper visual separation between the title and list items, serving as a baseline comparison for the subtitle spacing test.

## 2. Code Location

- **Test Function**: `renders_blank_line_between_title_and_items_without_subtitle` in `list_selection_view.rs` (line ~1153)
- **Source Module**: `codex-rs/tui/src/bottom_pane/list_selection_view.rs`
- **Comparison Test**: `renders_blank_line_between_subtitle_and_items`

## 3. Snapshot Description

The snapshot shows a selection popup with title only:

```
                                                
  Select Approval Mode                          
                                                
› 1. Read Only (current)  Codex can read files
  2. Full Access          Codex can edit files
                                                
  Press enter to confirm or esc to go back
```

**Layout Structure:**
1. Blank line (top padding)
2. Title: "Select Approval Mode" (bold)
3. **Blank line** (separator between title and items)
4. List items
5. Blank line (separator)
6. Footer hint

## 4. Key Concepts

### Header Composition Without Subtitle

```rust
if params.title.is_some() || params.subtitle.is_some() {
    let title = params.title.map(|title| Line::from(title.bold()));
    let subtitle = params.subtitle.map(|subtitle| Line::from(subtitle.dim()));
    header = Box::new(ColumnRenderable::with([
        header,
        Box::new(title),
        Box::new(subtitle),  // None when no subtitle provided
    ]));
}
```

When `subtitle` is `None`, the `ColumnRenderable` only contains the title.

### Consistent Spacing

The spacing layout is consistent regardless of subtitle presence:
- 1 blank line after header content (title or title+subtitle)
- 1 blank line before footer content

This ensures visual rhythm is maintained across different popup configurations.

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
            subtitle: subtitle.map(str::to_string),  // None in this test
            footer_hint: Some(standard_popup_hint_line()),
            items,
            ..Default::default()
        },
        tx,
    )
}

#[test]
fn renders_blank_line_between_title_and_items_without_subtitle() {
    let view = make_selection_view(None);  // No subtitle
    assert_snapshot!(
        "list_selection_spacing_without_subtitle",
        render_lines(&view)
    );
}
```

## 6. Dependencies

- `SelectionViewParams::title` - Main header text
- `SelectionViewParams::subtitle` - Optional secondary header text
- `ColumnRenderable` - Stacks header elements vertically
- `standard_popup_hint_line()` - Standard footer hint

## 7. Related Snapshots

| Snapshot | Description |
|----------|-------------|
| `list_selection_spacing_with_subtitle` | Same view with subtitle added |

## 8. Comparison: Without vs With Subtitle

**Without Subtitle (this snapshot):**
```
  Select Approval Mode
  
› 1. Read Only...
```

**With Subtitle:**
```
  Select Approval Mode
  Switch between Codex approval presets
  
› 1. Read Only...
```

**Key Difference:**
- Without subtitle: Header is 1 line (title) + 1 blank line
- With subtitle: Header is 2 lines (title + subtitle) + 1 blank line

The blank line separator is always present, ensuring consistent spacing between header and content.

## 9. Design Rationale

The consistent blank line separator:
- Creates visual breathing room between header and interactive content
- Maintains predictable layout across different popup configurations
- Follows the design principle of grouping related content (title+subtitle) and separating distinct sections (header vs. items)
