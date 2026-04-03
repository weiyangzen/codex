# Research: footer_mode_ctrl_c_interrupt

## Snapshot Description

This snapshot captures the footer UI state when the user presses Ctrl+C while a task is running. It displays the "ctrl + c again to quit" hint, which serves as a confirmation mechanism to prevent accidental interruption of running tasks.

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

**Source:** `codex-rs/tui/src/bottom_pane/chat_composer.rs` (lines 4712-4715)

```rust
snapshot_composer_state("footer_mode_ctrl_c_interrupt", true, |composer| {
    composer.set_task_running(true);
    composer.show_quit_shortcut_hint(key_hint::ctrl(KeyCode::Char('c')), true);
});
```

### Key State Components

1. **Footer Mode:** `FooterMode::QuitShortcutReminder`
2. **Task Running:** `true` - the task state when hint was triggered
3. **Quit Shortcut Key:** `Ctrl+C` (KeyBinding)
4. **Hint Timer:** Active (expires after `QUIT_SHORTCUT_TIMEOUT`)

### Quit Shortcut Hint Mechanism

**From chat_composer.rs (lines 1247-1276):**

```rust
/// Show the transient "press again to quit" hint for `key`.
pub fn show_quit_shortcut_hint(&mut self, key: KeyBinding, has_focus: bool) {
    self.quit_shortcut_expires_at = Instant::now()
        .checked_add(super::QUIT_SHORTCUT_TIMEOUT)
        .or_else(|| Some(Instant::now()));
    self.quit_shortcut_key = key;
    self.footer_mode = FooterMode::QuitShortcutReminder;
    self.set_has_focus(has_focus);
}

/// Whether the quit shortcut hint should currently be shown.
pub(crate) fn quit_shortcut_hint_visible(&self) -> bool {
    self.quit_shortcut_expires_at
        .is_some_and(|expires_at| Instant::now() < expires_at)
}
```

### Footer Rendering

**From footer.rs (lines 731-733):**

```rust
fn quit_shortcut_reminder_line(key: KeyBinding) -> Line<'static> {
    Line::from(vec![key.into(), " again to quit".into()]).dim()
}
```

The hint is rendered with `.dim()` styling to indicate it's transient/secondary information.

### FooterMode State Machine

```rust
pub(crate) enum FooterMode {
    QuitShortcutReminder,  // <-- THIS STATE
    ShortcutOverlay,
    EscHint,
    ComposerEmpty,
    ComposerHasDraft,
}
```

## UI Behavior

### Timeout Behavior

The quit hint is time-based rather than event-based:
- **Duration:** `QUIT_SHORTCUT_TIMEOUT` (defined in parent module)
- **Auto-expiry:** The UI schedules a redraw when the hint expires
- **No user action required** to clear - it fades automatically

### Mode Transition

```
ComposerEmpty/ComposerHasDraft
        ↓ (User presses Ctrl+C)
QuitShortcutReminder
        ↓ (Timeout expires OR user presses Ctrl+C again)
    [Quit application]
        ↓ (Timeout expires without second press)
ComposerEmpty/ComposerHasDraft (reset_mode_after_activity)
```

### Reset Logic

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

## Technical Details

### KeyBinding Structure

The `key.into()` conversion creates a styled representation:

```rust
// From key_hint module
pub fn ctrl(code: KeyCode) -> KeyBinding {
    KeyBinding {
        code,
        modifiers: KeyModifiers::CONTROL,
    }
}
```

### Rendering Priority

The quit shortcut reminder takes precedence over:
- Context window indicators
- Collaboration mode labels
- Status lines
- Other footer hints

This ensures the user sees the critical "press again to quit" warning.

## Comparison: Ctrl+C Quit vs Interrupt

| Scenario | Task Running | Result on Second Ctrl+C |
|----------|--------------|------------------------|
| `footer_mode_ctrl_c_quit` | `false` | Exit application |
| `footer_mode_ctrl_c_interrupt` | `true` | Interrupt running task |

Both scenarios show the same visual hint but have different behaviors on the second keypress.

## Related Snapshots

- `footer_mode_ctrl_c_quit` - Same hint but when idle (no task running)
- `footer_mode_ctrl_c_then_esc_hint` - After Ctrl+C hint, user presses Esc
