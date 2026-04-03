# footer_mode_indicator_running_hides_hint

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/footer.rs
- **Snapshot File**: codex_tui__bottom_pane__footer__tests__footer_mode_indicator_running_hides_hint.snap
- **Test Function**: footer_snapshots

## Purpose
This snapshot tests the footer rendering when a task is running with a collaboration mode indicator. It demonstrates how the shortcuts hint is suppressed while the mode indicator remains visible.

## Source Code Context
The snapshot is generated from:

```rust
let props = FooterProps {
    mode: FooterMode::ComposerEmpty,
    esc_backtrack_hint: false,
    use_shift_enter_hint: false,
    is_task_running: true,
    collaboration_modes_enabled: true,
    is_wsl: false,
    quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),
    context_window_percent: None,
    context_window_used_tokens: None,
    status_line_value: None,
    status_line_enabled: false,
    active_agent_label: None,
};

snapshot_footer_with_mode_indicator(
    "footer_mode_indicator_running_hides_hint",
    120,
    &props,
    Some(CollaborationModeIndicator::Plan),
);
```

The hint display logic:
```rust
let show_shortcuts_hint = match props.mode {
    FooterMode::ComposerEmpty => true,
    FooterMode::ComposerHasDraft => false,
    _ => false,
};
```

Note: The cycle hint is also suppressed when `is_task_running` is true:
```rust
let show_cycle_hint = !props.is_task_running;
```

## UI Components Involved
- `FooterProps` - Footer configuration
- `CollaborationModeIndicator::Plan` - Mode indicator
- `show_cycle_hint` logic - Controls cycle hint display

## Key Rendering Logic
When a task is running:
- Left side: "? for shortcuts · Plan mode"
- Right side: "100% context left"

The cycle hint "(shift+tab to cycle)" is hidden because `is_task_running: true`.

## Test Setup Details
The test creates `FooterProps` with:
- Mode: `ComposerEmpty`
- `is_task_running`: true
- `collaboration_modes_enabled`: true
- Width: 120 columns
- Mode indicator: `CollaborationModeIndicator::Plan`

## Dependencies
- `FooterProps` - Footer configuration
- `CollaborationModeIndicator` - Mode indicator enum
- `left_side_line()` - Left side content generator

## Notes
- When a task is running, the cycle hint is suppressed
- This makes sense as users shouldn't switch modes mid-task
- The shortcuts hint and mode indicator are still shown
- The context window indicator remains visible
