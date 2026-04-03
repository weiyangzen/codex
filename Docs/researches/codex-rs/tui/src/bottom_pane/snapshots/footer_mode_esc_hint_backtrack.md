# footer_mode_esc_hint_backtrack

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/chat_composer.rs
- **Snapshot File**: codex_tui__bottom_pane__chat_composer__tests__footer_mode_esc_hint_backtrack.snap
- **Test Function**: footer_mode_snapshots

## Purpose
This snapshot tests the rendering of the `ChatComposer` footer in "Esc Hint" mode with backtrack functionality enabled. It shows the hint that appears when the user presses Escape in an empty composer, indicating they can press Escape again to edit the previous message.

## Source Code Context

### Test Function
```rust
#[test]
fn footer_mode_snapshots() {
    // ... other snapshots ...
    
    snapshot_composer_state("footer_mode_esc_hint_backtrack", true, |composer| {
        composer.set_esc_backtrack_hint(true);
        let _ = composer.handle_key_event(KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE));
    });
    
    // ... other snapshots ...
}
```

### Key Structs/Components
- `ChatComposer`: Main text input component
- `FooterMode::EscHint`: Footer mode for Escape hint
- `set_esc_backtrack_hint()`: Enables backtrack hint functionality
- `esc_hint_mode()`: Determines the appropriate footer mode for Esc hint

## UI Components Involved
- `ChatComposer` (main container)
- Text area with placeholder "Ask Codex to do anything"
- Footer area with single-line hint
- Hint text: "esc again to edit previous message"

## Key Rendering Logic
1. **Esc Hint Mode Entry**:
   - Triggered by pressing Escape when composer is empty
   - Requires `esc_backtrack_hint: true` to be set
   - Sets `footer_mode` to `FooterMode::EscHint`

2. **Mode Priority** (`footer_mode()` method):
   - `EscHint` has high priority in the mode waterfall
   - Overrides `ComposerEmpty` and `ComposerHasDraft` base modes
   - Persists until another key is pressed or mode is reset

3. **Footer Rendering**:
   - When `FooterMode::EscHint` is active, shows single hint line
   - No context window indicator shown in this mode
   - No shortcut hints shown

## Test Setup Details
- Creates a `ChatComposer` with `enhanced_keys_supported: true`
- Calls `set_esc_backtrack_hint(true)` to enable backtrack functionality
- Simulates pressing `Esc` key to trigger the hint
- Renders at default width (100 pixels)

## Dependencies
- `crossterm::event::KeyCode`
- `crossterm::event::KeyEvent`
- `crossterm::event::KeyModifiers`
- `ratatui` for rendering
- `FooterMode` enum

## Notes
- The Esc hint allows users to quickly edit their previous message
- Pressing Escape again while hint is shown triggers the backtrack action
- The hint is only shown when `esc_backtrack_hint` is explicitly enabled
- Compare with `footer_mode_esc_hint_from_overlay` to see transition from overlay mode
