# footer_ctrl_c_quit_idle

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/footer.rs
- **Snapshot File**: codex_tui__bottom_pane__footer__tests__footer_ctrl_c_quit_idle.snap
- **Test Function**: footer_snapshots

## Purpose
This snapshot tests the footer rendering when the user has pressed Ctrl+C once while idle and needs to press it again to quit. It displays the quit shortcut reminder.

## Source Code Context
The snapshot is generated from:

```rust
snapshot_footer(
    "footer_ctrl_c_quit_idle",
    FooterProps {
        mode: FooterMode::QuitShortcutReminder,
        esc_backtrack_hint: false,
        use_shift_enter_hint: false,
        is_task_running: false,
        collaboration_modes_enabled: false,
        is_wsl: false,
        quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),
        context_window_percent: None,
        context_window_used_tokens: None,
        status_line_value: None,
        status_line_enabled: false,
        active_agent_label: None,
    },
);
```

The quit reminder line generation:
```rust
fn quit_shortcut_reminder_line(key: KeyBinding) -> Line<'static> {
    Line::from(vec![key.into(), " again to quit".into()]).dim()
}
```

## UI Components Involved
- `FooterProps` - Footer configuration
- `FooterMode::QuitShortcutReminder` - Transient quit reminder mode
- `quit_shortcut_reminder_line()` - Reminder text generator
- `KeyBinding` - Key combination display

## Key Rendering Logic
The footer renders:
- "ctrl + c again to quit" (dimmed text)

This is a transient instructional state that:
- Overrides normal footer content
- Requires the user to press the same key again to confirm quit
- Suppresses context window indicators and other hints

## Test Setup Details
The test creates `FooterProps` with:
- Mode: `QuitShortcutReminder`
- `quit_shortcut_key`: Ctrl+C
- `is_task_running`: false (idle state)

## Dependencies
- `FooterProps` - Footer configuration
- `FooterMode::QuitShortcutReminder` - Mode for quit confirmation
- `KeyBinding` - Key binding representation
- `key_hint::ctrl()` - Ctrl key formatter

## Notes
- The quit reminder appears after the first Ctrl+C press
- This prevents accidental quits by requiring confirmation
- The same pattern applies to Ctrl+D for EOF/quit
- When `is_task_running` is false, this is a quit confirmation
- When `is_task_running` is true, Ctrl+C would interrupt the task instead
