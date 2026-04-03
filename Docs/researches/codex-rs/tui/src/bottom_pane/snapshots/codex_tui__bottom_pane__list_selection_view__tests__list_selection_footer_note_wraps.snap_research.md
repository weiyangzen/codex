# Research: list_selection_footer_note_wraps

## 1. Feature Overview

This snapshot tests the text wrapping behavior of the `footer_note` field in `ListSelectionView`. The footer note allows displaying multi-line informational or instructional text at the bottom of selection popups, with automatic line wrapping when content exceeds available width.

## 2. Code Location

- **Test Function**: `snapshot_footer_note_wraps` in `list_selection_view.rs` (line ~1234)
- **Source Module**: `codex-rs/tui/src/bottom_pane/list_selection_view.rs`
- **Related Function**: `wrap_styled_line` in `selection_popup_common.rs`

## 3. Snapshot Description

The snapshot shows a selection popup rendered at 40 columns width with:

**Header Section:**
- Title: "Select Approval Mode"

**List Items:**
- Selected item: "› 1. Read Only (current)" with wrapped description "Codex can read files"

**Footer Note (wrapped across 2 lines):**
```
Note: Use /setup-default-sandbox to
allow network access.
```

**Footer Hint:**
- "Press enter to confirm or esc to go ba" (truncated due to narrow width)

The footer note demonstrates proper wrapping of styled text with mixed formatting (dim + cyan + dim spans).

## 4. Key Concepts

### Footer Note in SelectionViewParams

```rust
pub(crate) struct SelectionViewParams {
    pub footer_note: Option<Line<'static>>,  // Styled, wrappable note text
    pub footer_hint: Option<Line<'static>>, // Keyboard shortcut hints
    // ...
}
```

### Footer Note Rendering

```rust
fn desired_height(&self, width: u16) -> u16 {
    if let Some(note) = &self.footer_note {
        let note_width = width.saturating_sub(2);
        let note_lines = wrap_styled_line(note, note_width);
        height = height.saturating_add(note_lines.len() as u16);
    }
    // ...
}
```

### wrap_styled_line Function

```rust
pub(crate) fn wrap_styled_line<'a>(line: &'a Line<'a>, width: u16) -> Vec<Line<'a>> {
    use crate::wrapping::RtOptions;
    use crate::wrapping::word_wrap_line;

    let width = width.max(1) as usize;
    let opts = RtOptions::new(width)
        .initial_indent(Line::from(""))
        .subsequent_indent(Line::from(""));
    word_wrap_line(line, opts)
}
```

## 5. Test Setup

```rust
#[test]
fn snapshot_footer_note_wraps() {
    let footer_note = Line::from(vec![
        "Note: ".dim(),
        "Use /setup-default-sandbox".cyan(),
        " to allow network access.".dim(),
    ]);
    let view = ListSelectionView::new(
        SelectionViewParams {
            title: Some("Select Approval Mode".to_string()),
            footer_note: Some(footer_note),
            footer_hint: Some(standard_popup_hint_line()),
            items, // Single "Read Only" item
            ..Default::default()
        },
        tx,
    );
    assert_snapshot!(
        "list_selection_footer_note_wraps",
        render_lines_with_width(&view, 40)
    );
}
```

## 6. Dependencies

- `ratatui::text::Line` - Styled line representation
- `selection_popup_common::wrap_styled_line` - Preserves styles during wrapping
- `crate::wrapping::word_wrap_line` - Core wrapping logic
- `popup_consts::standard_popup_hint_line` - Standard footer hint

## 7. Related Snapshots

| Snapshot | Description |
|----------|-------------|
| `list_selection_spacing_with_subtitle` | Shows footer hint without note |
| `list_selection_spacing_without_subtitle` | Shows footer hint without note |

## 8. Styling Behavior

**Style Preservation During Wrap:**
- The footer note combines multiple styled spans: `"Note: "` (dim), `"Use /setup-default-sandbox"` (cyan), `" to allow network access."` (dim)
- When wrapped, each line segment maintains its original styling
- This allows rich, multi-colored instructional text in footers

**Layout Integration:**
- Footer note is rendered above footer hint
- Note width is calculated as `width.saturating_sub(2)` to account for margins
- Each wrapped line is rendered with a 2-column left offset for visual padding
