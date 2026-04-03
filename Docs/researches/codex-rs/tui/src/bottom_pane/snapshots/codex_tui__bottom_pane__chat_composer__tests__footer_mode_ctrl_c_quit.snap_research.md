# Research: footer_mode_ctrl_c_quit

## Snapshot Description

This snapshot captures the footer UI state when the user presses Ctrl+C while the application is idle (no task running). It displays the "ctrl + c again to quit" hint as a confirmation mechanism to prevent accidental application exit.

## Visual Output

```
"                                                                                                    "
"› Ask Codex to do anything                                                                          "
"                                                                                                    "
"                                                                                                    "
"                                                                                                    "
"                                                                                                    "
"                                                                                                    "
"                                                                                                    "
"  ctrl + c again to quit                                                                            "
```

## Code Analysis

### Test Setup

**Source:** `codex-rs/tui/src/bottom_pane/chat_composer.rs` (lines 4708-4710)

```rust
snapshot_composer_state("footer_mode_ctrl_c_quit", true, |composer| {
    composer.show_quit_shortcut_hint(key_hint::ctrl(KeyCode::Char('c')), true);
});
```

### Key State Components

1. **Footer Mode:** `FooterMode::QuitShortcutReminder`
2. **Task Running:** `false` (default, not explicitly set)
3. **Quit Shortcut Key:** `Ctrl+C` (KeyBinding with CONTROL modifier)
4. **Focus State:** `has_focus = true`
5. **Hint Timer:** Active with `QUIT_SHORTCUT_TIMEOUT` duration

### Quit Shortcut Hint API

**From chat_composer.rs (lines 1247-1259):**

```rust
/// Show the transient "press again to quit" hint for `key`.
///
/// The owner (`BottomPane`/`ChatWidget`) is responsible for scheduling a
/// redraw after [`super::QUIT_SHORTCUT_TIMEOUT`] so the hint can disappear
/// even when the UI is otherwise idle.
pub fn show_quit_shortcut_hint(&mut self, key: KeyBinding, has_focus: bool) {
    self.quit_shortcut_expires_at = Instant::now()
        .checked_add(super::QUIT_SHORTCUT_TIMEOUT)
        .or_else(|| Some(Instant::now()));
    self.quit_shortcut_key = key;
    self.footer_mode = FooterMode::QuitShortcutReminder;
    self.set_has_focus(has_focus);
}
```

### Footer Mode Rendering

**From footer.rs (lines 592-595):**

```rust
fn footer_from_props_lines(
    props: &FooterProps,
    // ...
) -> Vec<Line<'static>> {
    match props.mode {
        FooterMode::QuitShortcutReminder => {
            vec![quit_shortcut_reminder_line(props.quit_shortcut_key)]
        }
        // ...
    }
}
```

### Hint Line Construction

**From footer.rs (lines 731-733):**

```rust
fn quit_shortcut_reminder_line(key: KeyBinding) -> Line<'static> {
    Line::from(vec![key.into(), " again to quit".into()]).dim()
}
```

The `.dim()` style modifier makes the hint appear subdued/gray to indicate it's transient.

## UI Behavior

### User Flow

```
1. User presses Ctrl+C (first time)
   ↓
2. Footer shows "ctrl + c again to quit"
   ↓
3a. User presses Ctrl+C again within timeout
    → Application exits
   
3b. Timeout expires without second press
    → Footer returns to normal state (ComposerEmpty)
    → Application continues running
```

### Timeout Mechanism

The hint visibility is controlled by a time-based check:

```rust
pub(crate) fn quit_shortcut_hint_visible(&self) -> bool {
    self.quit_shortcut_expires_at
        .is_some_and(|expires_at| Instant::now() < expires_at)
}
```

### Clearing the Hint

**From chat_composer.rs (lines 1261-1266):**

```rust
/// Clear the "press again to quit" hint immediately.
pub fn clear_quit_shortcut_hint(&mut self, has_focus: bool) {
    self.quit_shortcut_expires_at = None;
    self.footer_mode = reset_mode_after_activity(self.footer_mode);
    self.set_has_focus(has_focus);
}
```

## Technical Details

### KeyBinding to Display Conversion

The `key.into()` call converts the KeyBinding to styled spans:

```rust
// KeyBinding contains:
// - code: KeyCode::Char('c')
// - modifiers: KeyModifiers::CONTROL

// Renders as: "ctrl + c" with appropriate styling
```

### Footer Mode State Machine

```
                    ┌─────────────────────┐
                    │   ComposerEmpty     │
                    └──────────┬──────────┘
                               │ Ctrl+C pressed
                               ▼
                    ┌─────────────────────┐
                    │ QuitShortcutReminder│◄────┐
                    │   (timer started)   │     │
                    └──────────┬──────────┘     │
                               │                │
              ┌────────────────┼────────────────┘
              │                │
              ▼                ▼
    ┌──────────────┐  ┌────────────────┐
    │  Timeout     │  │ Ctrl+C again   │
    │  (return to  │  │ (quit app)     │
    │   empty)     │  │                │
    └──────────────┘  └────────────────┘
```

### Styling

The hint uses the `dim()` modifier from ratatui's Stylize trait:

```rust
use ratatui::style::Stylize;

Line::from(vec![...]).dim()  // Gray/subdued appearance
```

## Comparison with Interrupt Mode

| Aspect | `footer_mode_ctrl_c_quit` | `footer_mode_ctrl_c_interrupt` |
|--------|---------------------------|--------------------------------|
| Task running | No | Yes |
| Second Ctrl+C action | Exit application | Interrupt/cancel task |
| Visual appearance | Identical | Identical |
| Context | Idle state | Active task |

## Related Snapshots

- `footer_mode_ctrl_c_interrupt` - Same hint but with task running
- `footer_mode_ctrl_c_then_esc_hint` - After quit hint, user presses Esc
- `footer_esc_hint_backtrack` - Esc hint for editing previous message
