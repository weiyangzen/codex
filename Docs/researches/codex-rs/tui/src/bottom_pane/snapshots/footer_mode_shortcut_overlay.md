# footer_mode_shortcut_overlay

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/chat_composer.rs
- **Snapshot File**: codex_tui__bottom_pane__chat_composer__tests__footer_mode_shortcut_overlay.snap
- **Test Function**: footer_mode_snapshots

## Purpose
This snapshot tests the rendering of the `ChatComposer` footer in "Shortcut Overlay" mode. It displays a comprehensive help overlay showing all available keyboard shortcuts when the user presses `?` in an empty composer.

## Source Code Context

### Test Function
```rust
#[test]
fn footer_mode_snapshots() {
    // ... other snapshots ...
    
    snapshot_composer_state("footer_mode_shortcut_overlay", true, |composer| {
        composer.set_esc_backtrack_hint(true);
        let _ =
            composer.handle_key_event(KeyEvent::new(KeyCode::Char('?'), KeyModifiers::NONE));
    });
    
    // ... other snapshots ...
}
```

### Key Structs/Components
- `ChatComposer`: Main text input component
- `FooterMode::ShortcutOverlay`: Footer mode for displaying shortcut help
- `handle_shortcut_overlay_key()`: Handles `?` key to toggle overlay
- `toggle_shortcut_mode()`: Toggles between overlay and normal mode

## UI Components Involved
- `ChatComposer` (main container)
- Text area with placeholder "Ask Codex to do anything"
- Footer area with shortcut overlay
- Multiple rows of keyboard shortcuts

## Key Rendering Logic
1. **Shortcut Overlay Toggle** (`handle_shortcut_overlay_key()`):
   - Only toggles when composer is empty (`is_empty()`)
   - Only toggles when not in a paste burst
   - Pressing `?` again closes the overlay

2. **Footer Rendering** (in `render()` method):
   - When `FooterMode::ShortcutOverlay` is active, displays full shortcut list
   - Shortcuts are organized in two columns
   - Each shortcut shows key combination and description

3. **Shortcuts Displayed**:
   - `/ for commands`
   - `! for shell commands`
   - `shift + enter for newline`
   - `tab to queue message`
   - `@ for file paths`
   - `ctrl + v to paste images`
   - `ctrl + g to edit in external editor`
   - `esc again to edit previous message`
   - `ctrl + c to exit`
   - `ctrl + t to view transcript`

## Test Setup Details
- Creates a `ChatComposer` with `enhanced_keys_supported: true`
- Sets `esc_backtrack_hint: true` (enables backtrack functionality)
- Simulates pressing `?` key to open shortcut overlay
- Renders at default width (100 pixels)

## Dependencies
- `crossterm::event::KeyCode`
- `crossterm::event::KeyEvent`
- `crossterm::event::KeyModifiers`
- `ratatui` for rendering
- `FooterMode` enum for mode tracking

## Notes
- The shortcut overlay only appears when the composer is completely empty
- Typing any character while overlay is shown will close it and insert the character
- The overlay provides discoverability for keyboard shortcuts
- Compare with other `footer_mode_*` snapshots to see different footer states
