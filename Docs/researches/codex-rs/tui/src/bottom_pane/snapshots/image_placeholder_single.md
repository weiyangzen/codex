# image_placeholder_single

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/chat_composer.rs
- **Snapshot File**: codex_tui__bottom_pane__chat_composer__tests__image_placeholder_single.snap
- **Test Function**: (part of image attachment tests)

## Purpose
This snapshot tests the rendering of the `ChatComposer` when a single local image is attached. It shows how image placeholders are displayed in the text area and how they appear as non-editable elements.

## Source Code Context

### Related Code
```rust
pub fn attach_image(&mut self, path: PathBuf) {
    let image_number = self.remote_image_urls.len() + self.attached_images.len() + 1;
    let placeholder = local_image_label_text(image_number);
    // Insert as an element to match large paste placeholder behavior:
    // styled distinctly and treated atomically for cursor/mutations.
    self.textarea.insert_element(&placeholder);
    self.attached_images
        .push(AttachedImage { placeholder, path });
}

// local_image_label_text function from codex_protocol::models
pub fn local_image_label_text(image_number: usize) -> String {
    format!("[Image #{image_number}]")
}
```

### Key Structs/Components
- `ChatComposer`: Main text input component
- `AttachedImage`: Struct tracking attached image placeholder and path
- `local_image_label_text()`: Generates placeholder text like "[Image #1]"
- `TextArea::insert_element()`: Inserts non-editable placeholder element

## UI Components Involved
- `ChatComposer` (main container)
- Text area with image placeholder "[Image #1]"
- Prompt indicator `›`
- Context window indicator: "100% context left"

## Key Rendering Logic
1. **Image Attachment** (`attach_image()`):
   - Generates placeholder text based on image number
   - Inserts as an element (non-editable atomic unit)
   - Tracks in `attached_images` vector

2. **Placeholder Numbering**:
   - Remote images: `[Image #1]` to `[Image #M]`
   - Local images: `[Image #M+1]` to `[Image #N]`
   - Numbering is contiguous across remote and local

3. **Rendering**:
   - Placeholders render as cyan-colored text
   - Selected remote images show with reversed colors
   - Context window shows percentage remaining

## Test Setup Details
- Creates a `ChatComposer` with image paste enabled
- Attaches a single local image
- Renders the composer showing the placeholder

## Dependencies
- `codex_protocol::models::local_image_label_text`
- `TextArea` component with element support
- `ratatui` for rendering

## Notes
- Image placeholders are atomic elements - they can't be partially edited
- Deleting a placeholder removes the associated image attachment
- Compare with `image_placeholder_multiple` for multiple images
- Compare with `remote_image_rows` for remote image display
