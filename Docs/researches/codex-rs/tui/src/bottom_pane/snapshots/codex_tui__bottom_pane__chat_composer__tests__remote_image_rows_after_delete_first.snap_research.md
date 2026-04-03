# Research: Remote Image Rows After Delete First

## Snapshot File
- **File**: `codex-rs/tui/src/bottom_pane/snapshots/codex_tui__bottom_pane__chat_composer__tests__remote_image_rows_after_delete_first.snap`
- **Source**: `codex-rs/tui/src/bottom_pane/chat_composer.rs`
- **Description**: Shows [Image #1] placeholder after deletion of first remote image

## Snapshot Content
```
"                                                                                                    "
"  [Image #1]                                                                                        "
"                                                                                                    "
"› describe these                                                                                    "
"                                                                                                    "
"                                                                                                    "
"                                                                                                    "
"                                                                                                    "
"                                                                                 100% context left  "
```

## UI State Description
This snapshot captures the composer state after deleting the first remote image from a set of attached remote images. Originally there were multiple remote images (e.g., [Image #1], [Image #2]), but after deleting the first one, the remaining image is renumbered to [Image #1] and the placeholder text in the textarea is updated accordingly. The user has typed "describe these" in the composer.

## Component Hierarchy
- `ChatComposer` - Main composer component
  - Remote Image Rows - Display attached remote images
    - `[Image #1]` - Single remaining remote image (renumbered after deletion)
  - `TextArea` - Input field with "describe these"
  - `Footer` - Bottom context indicator

## Key Props / State
- `remote_image_urls`: Vec with 1 remaining URL (was 2+, first was deleted)
- `selected_remote_image_index`: `None` (selection cleared after deletion)
- `attached_images`: Local images (if any) would be renumbered after remote images
- `textarea.text()`: "describe these"
- `context_window_percent`: Some(100)

## Visual Elements
| Element | Type | Description |
|---------|------|-------------|
| `[Image #1]` | Remote Image Row | Cyan-colored label for remaining remote image |
| `›` | Indicator | Prompt prefix character |
| `describe these` | Input | User-typed message text |
| `100% context left` | Context | Footer context usage indicator |

## Related Code References

### Remote Image Lines Rendering (`chat_composer.rs`)
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
```

### Remote Image Label Text (`codex_protocol`)
```rust
pub fn local_image_label_text(image_number: usize) -> String {
    format!("[Image #{}]", image_number)
}
```

### Remove Selected Remote Image (`chat_composer.rs`)
```rust
fn remove_selected_remote_image(&mut self, selected_index: usize) {
    if selected_index >= self.remote_image_urls.len() {
        self.clear_remote_image_selection();
        return;
    }
    self.remote_image_urls.remove(selected_index);
    self.selected_remote_image_index = if self.remote_image_urls.is_empty() {
        None
    } else {
        Some(selected_index.min(self.remote_image_urls.len() - 1))
    };
    self.relabel_attached_images_and_update_placeholders();
    self.sync_popups();
}
```

### Relabel Attached Images (`chat_composer.rs`)
```rust
fn relabel_attached_images_and_update_placeholders(&mut self) {
    for idx in 0..self.attached_images.len() {
        let expected = local_image_label_text(self.remote_image_urls.len() + idx + 1);
        let current = self.attached_images[idx].placeholder.clone();
        if current == expected {
            continue;
        }

        self.attached_images[idx].placeholder = expected.clone();
        let _renamed = self.textarea.replace_element_payload(&current, &expected);
    }
}
```

### Remote Image Selection Key Handler (`chat_composer.rs`)
```rust
fn handle_remote_image_selection_key(
    &mut self,
    key_event: &KeyEvent,
) -> Option<(InputResult, bool)> {
    if self.remote_image_urls.is_empty()
        || key_event.modifiers != KeyModifiers::NONE
        || key_event.kind != KeyEventKind::Press
    {
        return None;
    }

    match key_event.code {
        KeyCode::Up => {
            if let Some(selected) = self.selected_remote_image_index {
                self.selected_remote_image_index = Some(selected.saturating_sub(1));
                Some((InputResult::None, true))
            } else if self.textarea.cursor() == 0 {
                self.selected_remote_image_index = Some(self.remote_image_urls.len() - 1);
                Some((InputResult::None, true))
            } else {
                None
            }
        }
        KeyCode::Down => {
            if let Some(selected) = self.selected_remote_image_index {
                if selected + 1 < self.remote_image_urls.len() {
                    self.selected_remote_image_index = Some(selected + 1);
                } else {
                    self.clear_remote_image_selection();
                }
                Some((InputResult::None, true))
            } else {
                None
            }
        }
        KeyCode::Delete | KeyCode::Backspace => {
            if let Some(selected) = self.selected_remote_image_index {
                self.remove_selected_remote_image(selected);
                Some((InputResult::None, true))
            } else {
                None
            }
        }
        _ => None,
    }
}
```

### Layout Areas (`chat_composer.rs`)
```rust
fn layout_areas(&self, area: Rect) -> [Rect; 4] {
    // ...
    let remote_images_height = self
        .remote_images_lines(textarea_rect.width)
        .len()
        .try_into()
        .unwrap_or(u16::MAX)
        .min(textarea_rect.height.saturating_sub(1));
    let remote_images_separator = u16::from(remote_images_height > 0);
    let consumed = remote_images_height.saturating_add(remote_images_separator);
    let remote_images_rect = Rect {
        x: textarea_rect.x,
        y: textarea_rect.y,
        width: textarea_rect.width,
        height: remote_images_height,
    };
    textarea_rect.y = textarea_rect.y.saturating_add(consumed);
    textarea_rect.height = textarea_rect.height.saturating_sub(consumed);
    // ...
}
```

## Behavior
1. User has multiple remote images attached (e.g., from previous conversation history)
2. User presses `Up` arrow when cursor is at position 0 to enter remote image selection mode
3. User navigates to the first image row with `Up`/`Down` arrows
4. User presses `Delete` or `Backspace` to remove the selected image
5. `remove_selected_remote_image()`:
   - Removes the URL from `remote_image_urls` vector
   - Updates selection to next valid index or clears it
   - Calls `relabel_attached_images_and_update_placeholders()` to renumber remaining images
6. The display updates showing the remaining image as `[Image #1]`

## Image Numbering System
- Remote images occupy `[Image #1]..[Image #M]` where M is the count of remote images
- Local images (attached via paste) are offset after remote images: `[Image #M+1]..[Image #N]`
- When a remote image is deleted, local image placeholders are relabeled to maintain contiguous numbering

## Test Context
This snapshot is generated by the test `remote_image_rows_after_delete_first` which verifies that:
- After deleting the first remote image, remaining images are correctly renumbered
- The placeholder numbering stays contiguous (no gaps)
- Local image placeholders are updated to reflect the new numbering
- The composer textarea content remains intact
