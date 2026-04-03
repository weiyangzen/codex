# Remote Image Rows After Delete First Snapshot Research

## 1. 场景与职责 (Usage Scenario and Responsibility)

This snapshot test validates the **remote image row deletion behavior** in the chat composer. Specifically, it tests the scenario where a user deletes the first remote image from a list of two, verifying that:
1. The first image is removed
2. The second image is renumbered from `[Image #2]` to `[Image #1]`
3. Local image placeholders are also renumbered to maintain continuity
4. Selection state is properly updated

**Responsibilities:**
- Ensure consistent image numbering after deletions
- Maintain correct selection index after removal
- Update local image placeholders to reflect new numbering

## 2. 功能点目的 (Feature Purpose)

This test verifies the deletion workflow:
1. **User deletes first remote image**: Using Up arrow to navigate and Delete key to remove
2. **Renumbering occurs**: Remaining images are renumbered to maintain `[Image #1]`, `[Image #2]` sequence
3. **Local images adjust**: If local images exist, their numbering shifts to fill gaps
4. **Selection updates**: Selection moves to the next available image or clears

## 3. 具体技术实现 (Technical Implementation)

### Test Setup

```rust
snapshot_composer_state("remote_image_rows_after_delete_first", false, |composer| {
    // Setup: Two remote images
    composer.set_remote_image_urls(vec![
        "https://example.com/one.png".to_string(),
        "https://example.com/two.png".to_string(),
    ]);
    composer.set_text_content("describe these".to_string(), Vec::new(), Vec::new());
    
    // Step 1: Move cursor to start of textarea
    composer.textarea.set_cursor(0);
    
    // Step 2: Press Up twice to select first remote image
    let _ = composer.handle_key_event(KeyEvent::new(KeyCode::Up, KeyModifiers::NONE));
    let _ = composer.handle_key_event(KeyEvent::new(KeyCode::Up, KeyModifiers::NONE));
    // Selection: selected_remote_image_index = Some(0)
    
    // Step 3: Press Delete to remove first image
    let _ = composer.handle_key_event(KeyEvent::new(KeyCode::Delete, KeyModifiers::NONE));
    // Result: Only one image remains, renumbered as [Image #1]
});
```

### Deletion Flow

**Step 1: Cursor Positioning**
```rust
// Cursor must be at position 0 for Up arrow to enter remote row selection
composer.textarea.set_cursor(0);
```

**Step 2: Navigation to First Row**
```rust
// First Up: selected_remote_image_index = Some(1) [second image]
let _ = composer.handle_key_event(KeyEvent::new(KeyCode::Up, KeyModifiers::NONE));

// Second Up: selected_remote_image_index = Some(0) [first image]
let _ = composer.handle_key_event(KeyEvent::new(KeyCode::Up, KeyModifiers::NONE));
```

**Step 3: Deletion and Renumbering**
```rust
// Delete removes selected image
let _ = composer.handle_key_event(KeyEvent::new(KeyCode::Delete, KeyModifiers::NONE));

// Internal flow:
// 1. remove_selected_remote_image(0) called
// 2. remote_image_urls.remove(0) - removes first URL
// 3. relabel_attached_images_and_update_placeholders() - renumbers local images
// 4. selected_remote_image_index updated to Some(0) (new first image)
```

### Renumbering Logic

**`remove_selected_remote_image()`** (lines 2678-2691):
```rust
fn remove_selected_remote_image(&mut self, selected_index: usize) {
    // Remove the URL at selected index
    self.remote_image_urls.remove(selected_index);
    
    // Update selection
    self.selected_remote_image_index = if self.remote_image_urls.is_empty() {
        None
    } else {
        Some(selected_index.min(self.remote_image_urls.len() - 1))
    };
    
    // Critical: Renumber local images to maintain continuity
    self.relabel_attached_images_and_update_placeholders();
    self.sync_popups();
}
```

**`relabel_attached_images_and_update_placeholders()`** (lines 3156-3167):
```rust
fn relabel_attached_images_and_update_placeholders(&mut self) {
    for idx in 0..self.attached_images.len() {
        // Formula: remote_count + local_index + 1
        // After deletion: remote_count = 1, so first local = [Image #2]
        let expected = local_image_label_text(self.remote_image_urls.len() + idx + 1);
        let current = self.attached_images[idx].placeholder.clone();
        
        if current != expected {
            self.attached_images[idx].placeholder = expected.clone();
            // Update placeholder in textarea
            let _renamed = self.textarea.replace_element_payload(&current, &expected);
        }
    }
}
```

### Before/After State

**Before Deletion:**
```
[Image #1]  <- remote: https://example.com/one.png
[Image #2]  <- remote: https://example.com/two.png (selected)
[Image #3]  <- local: /tmp/local.png (if exists)
```

**After Deletion (first image):**
```
[Image #1]  <- remote: https://example.com/two.png (renumbered, selected)
[Image #2]  <- local: /tmp/local.png (renumbered from #3)
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Key Methods

| Method | Line Range | Purpose in This Test |
|--------|------------|---------------------|
| `handle_remote_image_selection_key()` | 2693-2738 | Handles Up/Down/Delete keys |
| `remove_selected_remote_image()` | 2678-2691 | Removes image and triggers renumbering |
| `relabel_attached_images_and_update_placeholders()` | 3156-3167 | Maintains unified numbering |
| `clear_remote_image_selection()` | 2674-2676 | Clears selection state |

### Related Tests

This test is part of a suite:
```rust
#[test]
fn remote_image_rows_snapshots() {
    // Test 1: Basic display
    snapshot_composer_state("remote_image_rows", ...);
    
    // Test 2: Selection state
    snapshot_composer_state("remote_image_rows_selected", ...);
    
    // Test 3: After deletion (this test)
    snapshot_composer_state("remote_image_rows_after_delete_first", ...);
}
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### State Dependencies

The test depends on proper state transitions:
1. `set_remote_image_urls()` - Initializes the remote image list
2. `set_text_content()` - Sets up the textarea
3. Keyboard events - Navigate and delete

### TextArea Element Updates

When renumbering occurs, the TextArea must update element payloads:
```rust
// In textarea.rs
pub fn replace_element_payload(&mut self, old: &str, new: &str) -> bool {
    // Finds element with old payload and replaces with new
}
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvements)

### Specific Risks for Deletion

1. **Index Out of Bounds**: Selection index must be validated after removal
2. **Inconsistent Numbering**: Local and remote numbering can become misaligned
3. **Element Payload Mismatch**: TextArea elements may not match attachment state

### Edge Cases Covered

| Scenario | Expected Behavior |
|----------|-------------------|
| Delete first of two | Second becomes first, selection moves to it |
| Delete last | Selection moves to previous or clears |
| Delete only image | Selection cleared, no rows displayed |
| Delete with local images | Local images renumbered to fill gap |

### Potential Bugs

1. **Off-by-One**: Selection index calculation after deletion
2. **Race Condition**: Multiple rapid deletions could corrupt state
3. **Memory Leak**: Old element payloads not properly cleaned up

### Improvement Suggestions

1. **Undo Support**: Allow undo of image deletion
2. **Confirmation**: Confirm before deleting (optional setting)
3. **Batch Delete**: Select and delete multiple images at once
4. **Animation**: Visual feedback during deletion/renumbering
5. **Audit Logging**: Track which images were removed for debugging

### Test Coverage Gaps

- Delete last image (not just first)
- Delete with mixed local/remote images
- Rapid successive deletions
- Delete while popup is open
- Delete during task execution
