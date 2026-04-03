# Remote Image Rows Selected Snapshot Research

## 1. 场景与职责 (Usage Scenario and Responsibility)

This snapshot test validates the **remote image row selection state** in the chat composer. It tests the scenario where a user navigates to the remote image rows using the Up arrow key, verifying that:
1. The selection highlight is properly rendered
2. The last remote image is selected by default when entering selection mode
3. Visual feedback (reversed/cyan styling) indicates the selected row

**Responsibilities:**
- Provide visual indication of which remote image is selected
- Support keyboard navigation into and out of remote row area
- Maintain selection state independently of textarea cursor

## 2. 功能点目的 (Feature Purpose)

This test verifies the selection workflow:
1. **Enter selection mode**: Up arrow at textarea cursor position 0 enters remote row selection
2. **Default selection**: Last remote image is selected first (closest to textarea)
3. **Visual feedback**: Selected row is rendered with reversed colors (highlight)
4. **Exit selection**: Down arrow on last row returns focus to textarea

## 3. 具体技术实现 (Technical Implementation)

### Test Setup

```rust
snapshot_composer_state("remote_image_rows_selected", false, |composer| {
    // Setup: Two remote images
    composer.set_remote_image_urls(vec![
        "https://example.com/one.png".to_string(),
        "https://example.com/two.png".to_string(),
    ]);
    composer.set_text_content("describe these".to_string(), Vec::new(), Vec::new());
    
    // Step 1: Ensure cursor is at position 0
    composer.textarea.set_cursor(0);
    
    // Step 2: Press Up to enter selection mode
    // This selects the last remote image (index 1)
    let _ = composer.handle_key_event(KeyEvent::new(KeyCode::Up, KeyModifiers::NONE));
    // selected_remote_image_index = Some(1)
});
```

### Selection Entry Logic

**`handle_remote_image_selection_key()` - Up Arrow Handling** (lines 2704-2714):
```rust
KeyCode::Up => {
    if let Some(selected) = self.selected_remote_image_index {
        // Already in selection mode: move up
        self.selected_remote_image_index = Some(selected.saturating_sub(1));
        Some((InputResult::None, true))
    } else if self.textarea.cursor() == 0 {
        // Enter selection mode: select last image
        self.selected_remote_image_index = Some(self.remote_image_urls.len() - 1);
        Some((InputResult::None, true))
    } else {
        // Cursor not at 0: normal textarea behavior
        None
    }
}
```

### Visual Rendering

**`remote_images_lines()` with Selection** (lines 2659-2672):
```rust
fn remote_images_lines(&self, _width: u16) -> Vec<Line<'static>> {
    self.remote_image_urls
        .iter()
        .enumerate()
        .map(|(idx, _)| {
            let label = local_image_label_text(idx + 1);
            if self.selected_remote_image_index == Some(idx) {
                // Selected: cyan + reversed (highlight)
                label.cyan().reversed().into()
            } else {
                // Not selected: cyan only
                label.cyan().into()
            }
        })
        .collect()
}
```

### Styling Details

Using `ratatui::style::Stylize`:
- `.cyan()`: Sets foreground color to cyan
- `.reversed()`: Swaps foreground/background (highlight effect)

The combination creates a highlighted appearance for the selected row.

### Cursor Behavior

**`cursor_pos()` method** (lines 4147-4155):
```rust
fn cursor_pos(&self, area: Rect) -> Option<(u16, u16)> {
    // Hide cursor when remote image is selected
    if !self.input_enabled || self.selected_remote_image_index.is_some() {
        return None;
    }
    // ... normal cursor calculation
}
```

When a remote image is selected:
- Textarea cursor is hidden
- User can only navigate between remote rows or exit selection

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Key Methods

| Method | Line Range | Purpose in This Test |
|--------|------------|---------------------|
| `handle_remote_image_selection_key()` | 2693-2738 | Handles Up/Down for selection |
| `remote_images_lines()` | 2659-2672 | Renders with selection styling |
| `cursor_pos()` | 4147-4155 | Hides cursor during selection |
| `set_cursor()` | (textarea) | Positions cursor for entry condition |

### State Machine

```
Normal Mode (textarea active)
    |
    | Up arrow + cursor == 0
    v
Selection Mode (remote rows active)
    |
    | Up/Down arrows
    v
Navigate between rows
    |
    | Down arrow on last row
    v
Return to Normal Mode
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Styling Dependencies

```rust
use ratatui::style::Stylize; // Provides .cyan(), .reversed()
```

### Key Event Dependencies

```rust
use crossterm::event::KeyCode;
use crossterm::event::KeyEvent;
use crossterm::event::KeyModifiers;
use crossterm::event::KeyEventKind; // For Press/Release/Repeat
```

### Interaction Flow

```
User presses Up
    |
    v
handle_key_event_without_popup()
    |
    v
handle_remote_image_selection_key()
    |
    v
Check: cursor == 0?
    |--Yes--> selected_remote_image_index = Some(len - 1)
    |--No----> Normal Up arrow behavior
    |
    v
render() called
    |
    v
remote_images_lines() renders with .cyan().reversed()
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvements)

### Selection-Specific Risks

1. **Hidden Cursor**: Users may not realize they're in selection mode
2. **No Mouse Support**: Selection is keyboard-only
3. **Entry Condition**: Must remember to place cursor at 0

### Edge Cases

| Scenario | Behavior |
|----------|----------|
| Cursor at position > 0 | Up arrow moves cursor, doesn't enter selection |
| No remote images | Selection mode never activates |
| Single remote image | Immediately selected on Up |
| Popup open | Selection mode disabled |

### Visual Design Considerations

1. **Contrast**: Reversed cyan may not be visible on all terminals
2. **Accessibility**: No audio feedback for selection change
3. **Discoverability**: No visual indicator of selection mode vs normal mode

### Improvement Suggestions

1. **Mode Indicator**: Show "SELECTING" or similar in footer when in selection mode
2. **Help Text**: Display "↑↓ to navigate, Delete to remove, Esc to cancel" hint
3. **Mouse Support**: Click to select remote images
4. **Animation**: Brief flash when entering/exiting selection mode
5. **Alternative Entry**: Allow Tab or other key to enter selection from any cursor position

### Testing Matrix

| Test Case | Covered |
|-----------|---------|
| Enter selection from cursor 0 | ✓ (this test) |
| Enter selection from cursor > 0 | ✗ |
| Navigate up through all rows | ✗ |
| Exit selection with Down | ✗ |
| Exit selection with Esc | ✗ |
| Delete while selected | ✓ (separate test) |
| Selection with many images | ✗ |

### Related Accessibility Concerns

- Screen readers may not announce selection state change
- Colorblind users may not distinguish selected vs unselected
- No haptic feedback on supported terminals
