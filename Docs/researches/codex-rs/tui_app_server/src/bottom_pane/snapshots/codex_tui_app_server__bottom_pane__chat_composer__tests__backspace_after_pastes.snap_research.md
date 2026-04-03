# Snapshot Research: Chat Composer Backspace After Pastes

## 1. 场景与职责 (Scene and Responsibility)

This snapshot tests the **ChatComposer** component's behavior when the user presses backspace after pasting content, particularly focusing on the removal of paste placeholders and cleanup of pending paste state.

**Key Responsibilities:**
- Remove paste placeholders when backspace is pressed
- Clean up `pending_pastes` vector to prevent memory leaks
- Maintain cursor position correctly after deletion
- Handle mixed content (text + placeholders) correctly

## 2. 功能点目的 (Functional Purpose)

Backspace handling for pasted content ensures:

- **Intuitive editing**: Users can undo paste operations naturally
- **State consistency**: Pending pastes stay synchronized with visible content
- **Memory management**: Orphaned placeholders are cleaned up
- **History integrity**: Deleted content doesn't appear in submissions

**Test Coverage:**
- Validates placeholder removal on backspace
- Tests cleanup of pending_pastes vector
- Verifies cursor positioning after deletion

## 3. 具体技术实现 (Technical Implementation)

### Backspace Handling Flow

```rust
// From chat_composer.rs - handle_key_event_without_popup
fn handle_key_event_without_popup(&mut self, key: KeyEvent) -> (InputResult, bool) {
    match key.code {
        KeyCode::Backspace => {
            // Check if cursor is at a placeholder element
            if let Some(element_id) = self.textarea.element_at_cursor() {
                // Remove from pending_pastes if it's a paste placeholder
                self.pending_pastes.retain(|(placeholder, _)| {
                    placeholder != element_id
                });
            }
            self.textarea.input(key);
            self.sync_popups();
            (InputResult::None, true)
        }
        // ... other keys
    }
}
```

### Pending Paste Cleanup

```rust
pub(crate) fn set_pending_pastes(&mut self, pending_pastes: Vec<(String, String)>) {
    let text = self.textarea.text().to_string();
    self.pending_pastes = pending_pastes
        .into_iter()
        .filter(|(placeholder, _)| text.contains(placeholder))
        .collect();
}
```

### Element-Aware TextArea

```rust
// textarea.rs
pub struct TextArea {
    text: String,
    elements: Vec<TextElement>,  // Tracked byte ranges for placeholders
    cursor: usize,
}

pub fn element_at_cursor(&self) -> Option<&str> {
    // Returns the element ID if cursor is at an element boundary
}
```

## 4. 关键代码路径与文件引用 (Key Code Paths)

### Backspace Implementation

```rust
// chat_composer.rs
impl ChatComposer {
    fn handle_input_basic(&mut self, key: KeyEvent) -> (InputResult, bool) {
        // Line ~1000+ - Basic input handling including backspace
    }
    
    fn handle_key_event_without_popup(&mut self, key: KeyEvent) -> (InputResult, bool) {
        // Line ~1000+ - Routes to appropriate handler
    }
}
```

### TextArea Element Management

```rust
// textarea.rs
impl TextArea {
    pub fn input(&mut self, key: KeyEvent) -> bool {
        // Handles backspace, considering element boundaries
    }
    
    pub fn delete_element(&mut self, id: &str) -> bool {
        // Removes element and associated text
    }
}
```

## 5. 依赖与外部交互 (Dependencies)

### TextElement Protocol

```rust
use codex_protocol::user_input::TextElement;

pub struct TextElement {
    pub id: String,
    pub byte_range: ByteRange,
}
```

### Event Integration

```rust
// When backspace removes a placeholder:
1. TextArea::input(KeyCode::Backspace) called
2. Element boundary detected
3. ChatComposer removes matching entry from pending_pastes
4. sync_popups() updates UI state
5. Render reflects changes
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, Improvements)

### Known Risks

1. **Orphaned Pastes**: If placeholder text is modified, cleanup may fail
2. **Cursor Position**: Complex when deleting multi-byte UTF-8 characters
3. **Batch Operations**: Select-all + delete may not clean up properly

### Edge Cases

| Scenario | Handling |
|----------|----------|
| Backspace at element start | Deletes entire element |
| Backspace in middle of text | Normal character deletion |
| Delete key (forward) | Same cleanup logic as backspace |
| Undo (Ctrl+Y) | May restore placeholder without content |

### Improvement Suggestions

1. **Garbage Collection**: Periodic scan for orphaned pending_pastes
2. **Undo Stack**: Track paste operations for proper undo/redo
3. **Visual Feedback**: Highlight placeholders that will be deleted
4. **Bulk Delete**: Optimize cleanup for multi-element deletion

### Related Snapshots

- `multiple_pastes.snap` - Paste creation counterpart
- `empty.snap` - State after all content deleted
