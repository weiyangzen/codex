# remote_image_rows

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/chat_composer.rs
- **Snapshot File**: codex_tui__bottom_pane__chat_composer__tests__remote_image_rows.snap
- **Test Function**: (part of remote image tests)

## Purpose
This snapshot tests the rendering of the `ChatComposer` when remote images (from URLs) are attached. It shows how remote images are displayed as separate rows above the text input area, distinct from local image placeholders in the text.

## Source Code Context

### Related Code
```rust
fn remote_images_lines(&self, _width: u16) -> Vec<Line<'static>> {
    self.remote_image_urls
        .iter()
        .enumerate()
        .map(|(idx, _)| {
            let label = local_image_label_text(idx + 1);
            if self.selected_remote_image_index == Some(idx) {
                label.cyan().reversed().into()
            } else {
                label.cyan().into()
            }
        })
        .collect()
}

pub(crate) fn set_remote_image_urls(&mut self, urls: Vec<String>) {
    self.remote_image_urls = urls;
    self.selected_remote_image_index = None;
    self.relabel_attached_images_and_update_placeholders();
    self.sync_popups();
}
```

### Key Structs/Components
- `ChatComposer`: Main text input component
- `remote_image_urls`: Vector of remote image URLs
- `selected_remote_image_index`: Tracks keyboard selection
- `remote_images_lines()`: Generates lines for rendering

## UI Components Involved
- `ChatComposer` (main container)
- Remote image rows: "[Image #1]", "[Image #2]" (cyan colored)
- Text area with content "describe these"
- Prompt indicator `›`
- Context window indicator: "100% context left"

## Key Rendering Logic
1. **Remote Image Display**:
   - Rendered as separate rows above the textarea
   - Each row shows `[Image #N]` in cyan
   - Non-editable (can only be removed, not modified)

2. **Keyboard Navigation**:
   - `Up` at cursor position 0 enters remote row selection
   - `Up`/`Down` move between rows
   - `Delete`/`Backspace` remove selected row
   - `Down` on last row returns to textarea

3. **Unified Numbering**:
   - Remote images: `[Image #1]` to `[Image #M]`
   - Local placeholders: `[Image #M+1]` to `[Image #N]`
   - Deleting remote image relabels local placeholders

4. **Layout** (`layout_areas()`):
   - Remote images take height based on count
   - Separator line if remote images exist
   - Remaining space for textarea

## Test Setup Details
- Creates a `ChatComposer`
- Sets remote image URLs (2 images)
- Sets text content "describe these"
- Renders showing both remote rows and text area

## Dependencies
- `codex_protocol::models::local_image_label_text`
- `ratatui::text::Line`
- `ratatui::style::Stylize` for cyan color

## Notes
- Remote images come from history or external sources
- Local images are pasted/attached by the user
- Remote rows are selectable for deletion
- Compare with `remote_image_rows_selected` for selection state
- Compare with `image_placeholder_single` for local image display
