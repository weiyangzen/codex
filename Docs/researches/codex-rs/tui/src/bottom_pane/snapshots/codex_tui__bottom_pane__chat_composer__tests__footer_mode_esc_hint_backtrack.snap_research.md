# Research: footer_mode_esc_hint_backtrack

## Snapshot Description

This snapshot captures the footer UI state showing the Esc hint with the backtrack flag enabled. When `esc_backtrack_hint` is true, the hint changes from "esc esc to edit previous message" to "esc again to edit previous message", indicating the user has already pressed Escape once and only needs one more press to edit the previous message.

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
"  esc again to edit previous message                                                                "
```

## Code Analysis

### Test Setup

**Source:** `codex-rs/tui/src/bottom_pane/chat_composer.rs` (lines 4728-4731)

```rust
snapshot_composer_state("footer_mode_esc_hint_backtrack", true, |composer| {
    composer.set_esc_backtrack_hint(true);
    let _ = composer.handle_key_event(KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE));
});
```

### Key State Components

1. **Footer Mode:** `FooterMode::EscHint` (transitioned after Esc key)
2. **Esc Backtrack Hint:** `true` - changes the hint text
3. **Composer State:** Empty (required for Esc hint to activate)
4. **Task Running:** `false` (default)

### Esc Backtrack Hint Flag

**From chat_composer.rs (line 360):**

```rust
pub(crate) struct ChatComposer {
    // ...
    esc_backtrack_hint: bool,  // Controls hint text variant
    // ...
}
```

**Setter method:**

```rust
pub fn set_esc_backtrack_hint(&mut self, enabled: bool) {
    self.esc_backtrack_hint = enabled;
}
```

### Esc Hint Line Rendering

**From footer.rs (lines 735-748):**

```rust
fn esc_hint_line(esc_backtrack_hint: bool) -> Line<'static> {
    let esc = key_hint::plain(KeyCode::Esc);
    if esc_backtrack_hint {
        // THIS BRANCH - single "esc" with "again"
        Line::from(vec![esc.into(), " again to edit previous message".into()]).dim()
    } else {
        // Double "esc esc" variant
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

### Hint Text Variants

| esc_backtrack_hint | Output |
|-------------------|--------|
| `false` | `esc esc to edit previous message` |
| `true` | `esc again to edit previous message` |

## UI Behavior

### User Flow with Backtrack Hint

```
1. User has previously interacted with the message history
   → System sets esc_backtrack_hint = true
   
2. User presses Escape (first time in this session)
   → Footer shows "esc again to edit previous message"
   
3. User presses Escape again
   → Opens previous message for editing
```

### When is esc_backtrack_hint Set?

The flag is typically set when:
- The user has navigated message history using Up/Down arrows
- The composer has been populated from a previous session
- The user has previously used the Esc-to-edit feature

### State Transition

```
ComposerEmpty (with esc_backtrack_hint = true)
    ↓ (Esc pressed)
EscHint
    ↓ (Esc pressed again)
[Previous message loaded into composer]
```

## Technical Details

### Key Event Handling

**From chat_composer.rs (lines 2737-2747):**

```rust
if key_event.code == KeyCode::Esc {
    if self.is_empty() {
        let next_mode = esc_hint_mode(self.footer_mode, self.is_task_running);
        if next_mode != self.footer_mode {
            self.footer_mode = next_mode;
            return (InputResult::None, true);
        }
    }
}
```

### Footer Mode Selection

**From footer.rs (lines 169-175):**

```rust
pub(crate) fn esc_hint_mode(current: FooterMode, is_task_running: bool) -> FooterMode {
    if is_task_running {
        current  // Keep current mode if task is running
    } else {
        FooterMode::EscHint  // Switch to Esc hint mode
    }
}
```

### Footer Rendering

**From footer.rs (lines 616):**

```rust
FooterMode::EscHint => vec![esc_hint_line(props.esc_backtrack_hint)],
```

The `FooterProps` struct carries the `esc_backtrack_hint` flag to the rendering layer:

```rust
pub(crate) struct FooterProps {
    // ...
    pub(crate) esc_backtrack_hint: bool,
    // ...
}
```

## Comparison with Other Esc Hints

| Snapshot | esc_backtrack_hint | Context |
|----------|-------------------|---------|
| `footer_mode_esc_hint_backtrack` | `true` | Direct Esc press with history |
| `footer_mode_esc_hint_from_overlay` | `false` | After dismissing shortcut overlay |
| `footer_mode_ctrl_c_then_esc_hint` | `false` | After Ctrl+C quit hint |

## Related Code in Shortcut Overlay

The same backtrack hint logic is used in the shortcut overlay for the Edit Previous entry:

**From footer.rs (lines 926-936):**

```rust
ShortcutId::EditPrevious => {
    if state.esc_backtrack_hint {
        line.push_span(" again to edit previous message");
    } else {
        line.extend(vec![
            " ".into(),
            key_hint::plain(KeyCode::Esc).into(),
            " to edit previous message".into(),
        ]);
    }
}
```

## Related Snapshots

- `footer_mode_esc_hint_from_overlay` - Esc hint without backtrack flag
- `footer_mode_ctrl_c_then_esc_hint` - Esc hint after quit reminder
- `footer_mode_shortcut_overlay` - Full shortcut overlay with Edit Previous entry
