# Research: footer_mode_ctrl_c_then_esc_hint

## Snapshot Description

This snapshot captures a specific footer state transition: after the user triggers the Ctrl+C quit shortcut hint and then presses Escape. It demonstrates how the footer mode transitions from `QuitShortcutReminder` to `EscHint`, showing "esc esc to edit previous message" instead of the quit reminder.

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
"  esc esc to edit previous message                                                                  "
```

## Code Analysis

### Test Setup

**Source:** `codex-rs/tui/src/bottom_pane/chat_composer.rs` (lines 4717-4720)

```rust
snapshot_composer_state("footer_mode_ctrl_c_then_esc_hint", true, |composer| {
    composer.show_quit_shortcut_hint(key_hint::ctrl(KeyCode::Char('c')), true);
    let _ = composer.handle_key_event(KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE));
});
```

### Key State Components

1. **Initial Footer Mode:** `FooterMode::QuitShortcutReminder` (set by `show_quit_shortcut_hint`)
2. **Key Event:** Escape key pressed
3. **Resulting Footer Mode:** `FooterMode::EscHint`
4. **Esc Backtrack Hint:** `false` (default)

### State Transition Flow

```
ComposerEmpty
    ↓ (Ctrl+C pressed)
QuitShortcutReminder
    ↓ (Esc pressed)
EscHint  <-- THIS STATE
```

### Key Event Handling

**From chat_composer.rs (lines 2737-2747):**

```rust
fn handle_key_event_without_popup(&mut self, key_event: KeyEvent) -> (InputResult, bool) {
    // ...
    if key_event.code == KeyCode::Esc {
        if self.is_empty() {
            let next_mode = esc_hint_mode(self.footer_mode, self.is_task_running);
            if next_mode != self.footer_mode {
                self.footer_mode = next_mode;
                return (InputResult::None, true);
            }
        }
    }
    // ...
}
```

### Esc Hint Mode Logic

**From footer.rs (lines 169-175):**

```rust
pub(crate) fn esc_hint_mode(current: FooterMode, is_task_running: bool) -> FooterMode {
    if is_task_running {
        current  // Don't change mode if task is running
    } else {
        FooterMode::EscHint  // Transition to EscHint
    }
}
```

### Esc Hint Line Rendering

**From footer.rs (lines 735-748):**

```rust
fn esc_hint_line(esc_backtrack_hint: bool) -> Line<'static> {
    let esc = key_hint::plain(KeyCode::Esc);
    if esc_backtrack_hint {
        Line::from(vec![esc.into(), " again to edit previous message".into()]).dim()
    } else {
        Line::from(vec![
            esc.into(),
            " ".into(),
            esc.into(),
            " to edit previous message".into(),
        ])
        .dim()
    }
}
```

Since `esc_backtrack_hint` is `false`, the output is: `"esc esc to edit previous message"`

## UI Behavior

### User Flow

```
1. User presses Ctrl+C (first time)
   → Footer shows "ctrl + c again to quit"
   
2. User presses Escape (instead of second Ctrl+C)
   → Footer transitions to "esc esc to edit previous message"
   
3a. User presses Escape twice
    → Opens previous message for editing
    
3b. User types or performs other activity
    → Footer returns to normal state via reset_mode_after_activity()
```

### Mode Reset After Activity

**From footer.rs (lines 177-185):**

```rust
pub(crate) fn reset_mode_after_activity(current: FooterMode) -> FooterMode {
    match current {
        FooterMode::EscHint
        | FooterMode::ShortcutOverlay
        | FooterMode::QuitShortcutReminder
        | FooterMode::ComposerHasDraft => FooterMode::ComposerEmpty,
        other => other,
    }
}
```

Any non-Esc keypress will reset the footer mode back to `ComposerEmpty`.

## Technical Details

### FooterMode Enum

```rust
pub(crate) enum FooterMode {
    QuitShortcutReminder,  // Initial state after Ctrl+C
    ShortcutOverlay,
    EscHint,               // <-- Final state after Esc
    ComposerEmpty,
    ComposerHasDraft,
}
```

### Key Event Processing

When Escape is pressed:

1. `handle_key_event()` receives the KeyEvent
2. No popup is active, so `handle_key_event_without_popup()` is called
3. `Esc` code is detected and `is_empty()` is true (no draft text)
4. `esc_hint_mode()` is called with current mode and task state
5. Since `is_task_running` is false, mode transitions to `EscHint`
6. UI redraws with new footer content

### Styling

Both the key hints and message text use `.dim()` styling:

```rust
Line::from(vec![...]).dim()
```

This creates a consistent, subdued appearance for transient hints.

## Comparison: Esc Hint Variants

| Snapshot | esc_backtrack_hint | Display Text |
|----------|-------------------|--------------|
| `footer_mode_ctrl_c_then_esc_hint` | `false` | `esc esc to edit previous message` |
| `footer_mode_esc_hint_backtrack` | `true` | `esc again to edit previous message` |
| `footer_mode_esc_hint_from_overlay` | `false` | `esc esc to edit previous message` |

## Related Snapshots

- `footer_mode_ctrl_c_quit` - Initial state before Esc is pressed
- `footer_mode_esc_hint_backtrack` - Esc hint with backtrack flag enabled
- `footer_mode_esc_hint_from_overlay` - Esc hint after dismissing shortcut overlay
