# footer_ctrl_c_quit_running

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/footer.rs
- **Snapshot File**: codex_tui__bottom_pane__footer__tests__footer_ctrl_c_quit_running.snap
- **Test Function**: footer_snapshots

## Purpose
This snapshot tests the footer rendering when the user has pressed Ctrl+C while a task is running. It displays the quit shortcut reminder, though functionally this would typically interrupt the running task rather than quit.

## Source Code Context
The snapshot is generated from:

```rust
snapshot_footer(
    "footer_ctrl_c_quit_running",
    FooterProps {
        mode: FooterMode::QuitShortcutReminder,
        esc_backtrack_hint: false,
        use_shift_enter_hint: false,
        is_task_running: true,
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

## UI Components Involved
- `FooterProps` - Footer configuration
- `FooterMode::QuitShortcutReminder` - Transient quit reminder mode
- `quit_shortcut_reminder_line()` - Reminder text generator

## Key Rendering Logic
The footer renders:
- "ctrl + c again to quit" (dimmed text)

Note: While the UI shows "again to quit", the actual behavior when `is_task_running: true` would typically be to interrupt the current task on the first Ctrl+C, not quit the application.

## Test Setup Details
The test creates `FooterProps` with:
- Mode: `QuitShortcutReminder`
- `quit_shortcut_key`: Ctrl+C
- `is_task_running`: true

## Dependencies
- `FooterProps` - Footer configuration
- `FooterMode::QuitShortcutReminder` - Mode for quit confirmation
- `KeyBinding` - Key binding representation

## Notes
- This snapshot shows the same UI as the idle case but with `is_task_running: true`
- The visual output is identical, but the underlying behavior differs
- In practice, the first Ctrl+C during a running task interrupts the task
- The second Ctrl+C would then trigger the quit confirmation flow
- This test verifies the footer renders correctly regardless of task state
