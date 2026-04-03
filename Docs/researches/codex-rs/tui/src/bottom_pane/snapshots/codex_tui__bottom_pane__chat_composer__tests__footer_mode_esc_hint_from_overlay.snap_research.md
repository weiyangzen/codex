# Research: footer_mode_esc_hint_from_overlay

## Snapshot Description

This snapshot captures the footer UI state when the user dismisses the shortcut overlay (triggered by `?` key) by pressing Escape. It shows the transition from `FooterMode::ShortcutOverlay` to `FooterMode::EscHint`, displaying "esc esc to edit previous message".

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

**Source:** `codex-rs/tui/src/bottom_pane/chat_composer.rs` (lines 4722-4726)

```rust
snapshot_composer_state("footer_mode_esc_hint_from_overlay", true, |composer| {
    let _ =
        composer.handle_key_event(KeyEvent::new(KeyCode::Char('?'), KeyModifiers::NONE));
    let _ = composer.handle_key_event(KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE));
});
```

### Key State Components

1. **Initial Footer Mode:** `FooterMode::ComposerEmpty`
2. **After `?` key:** `FooterMode::ShortcutOverlay`
3. **After Esc key:** `FooterMode::EscHint`
4. **Esc Backtrack Hint:** `false` (default)
5. **Composer State:** Empty

### State Transition Flow

```
ComposerEmpty
    ↓ (? key pressed)
ShortcutOverlay
    ↓ (Esc key pressed)
EscHint  <-- THIS STATE
```

### Shortcut Overlay Key Handling

**From chat_composer.rs (lines 1359-1367):**

```rust
fn handle_key_event_with_slash_popup(&mut self, key_event: KeyEvent) -> (InputResult, bool) {
    if self.handle_shortcut_overlay_key(&key_event) {
        return (InputResult::None, true);
    }
    if key_event.code == KeyCode::Esc {
        let next_mode = esc_hint_mode(self.footer_mode, self.is_task_running);
        if next_mode != self.footer_mode {
            self.footer_mode = next_mode;
            return (InputResult::None, true);
        }
    }
    // ...
}
```

### Shortcut Overlay Key Handler

**From chat_composer.rs (lines ~3150-3170):**

```rust
fn handle_shortcut_overlay_key(&mut self, key_event: &KeyEvent) -> bool {
    if key_event.code == KeyCode::Char('?') 
        && key_event.modifiers == KeyModifiers::NONE 
    {
        self.footer_mode = toggle_shortcut_mode(
            self.footer_mode, 
            /*ctrl_c_hint*/ false, 
            self.is_empty()
        );
        true
    } else {
        false
    }
}
```

### Toggle Shortcut Mode

**From footer.rs (lines 148-167):**

```rust
pub(crate) fn toggle_shortcut_mode(
    current: FooterMode,
    ctrl_c_hint: bool,
    is_empty: bool,
) -> FooterMode {
    if ctrl_c_hint && matches!(current, FooterMode::QuitShortcutReminder) {
        return current;
    }

    let base_mode = if is_empty {
        FooterMode::ComposerEmpty
    } else {
        FooterMode::ComposerHasDraft
    };

    match current {
        FooterMode::ShortcutOverlay | FooterMode::QuitShortcutReminder => base_mode,
        _ => FooterMode::ShortcutOverlay,  // <-- This path when ? pressed
    }
}
```

### Esc Hint Mode Selection

**From footer.rs (lines 169-175):**

```rust
pub(crate) fn esc_hint_mode(current: FooterMode, is_task_running: bool) -> FooterMode {
    if is_task_running {
        current
    } else {
        FooterMode::EscHint
    }
}
```

### Esc Hint Rendering

**From footer.rs (lines 735-748):**

```rust
fn esc_hint_line(esc_backtrack_hint: bool) -> Line<'static> {
    let esc = key_hint::plain(KeyCode::Esc);
    if esc_backtrack_hint {
        Line::from(vec![esc.into(), " again to edit previous message".into()]).dim()
    } else {
        // THIS BRANCH - double esc
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

## UI Behavior

### User Flow

```
1. User presses ? key
   → Shortcut overlay appears showing all keyboard shortcuts
   
2. User presses Escape (to dismiss overlay)
   → Overlay closes
   → Footer shows "esc esc to edit previous message"
   
3a. User presses Escape twice more
    → Opens previous message for editing
    
3b. User types any character
    → Footer returns to normal state
```

### Why "esc esc" Instead of "esc again"?

The `esc_backtrack_hint` flag is `false` in this scenario because:
- The user hasn't previously navigated message history
- This is a fresh Esc hint from dismissing the overlay
- The system requires TWO Escape presses from this state:
  1. First Esc dismissed the overlay
  2. Second and third Esc presses will trigger edit previous

## Technical Details

### Footer Mode Enum

```rust
pub(crate) enum FooterMode {
    QuitShortcutReminder,
    ShortcutOverlay,       // Intermediate state
    EscHint,               // Final state
    ComposerEmpty,
    ComposerHasDraft,
}
```

### Mode Reset Logic

After the Esc hint is shown, any activity resets to `ComposerEmpty`:

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

### Key Event Flow

```
KeyEvent(Esc)
    ↓
handle_key_event()
    ↓
handle_key_event_with_slash_popup() [if overlay active]
    ↓
esc_hint_mode(ShortcutOverlay, false) → EscHint
    ↓
footer_mode = EscHint
    ↓
Re-render with esc_hint_line(false)
```

## Comparison with Other Esc Hint Scenarios

| Scenario | Previous State | esc_backtrack_hint | Display |
|----------|---------------|-------------------|---------|
| From overlay | ShortcutOverlay | false | `esc esc to edit previous message` |
| After Ctrl+C | QuitShortcutReminder | false | `esc esc to edit previous message` |
| With backtrack | ComposerEmpty | true | `esc again to edit previous message` |

## Related Snapshots

- `footer_mode_shortcut_overlay` - The overlay state before Esc is pressed
- `footer_mode_esc_hint_backtrack` - Esc hint with backtrack flag enabled
- `footer_mode_ctrl_c_then_esc_hint` - Esc hint after quit reminder
