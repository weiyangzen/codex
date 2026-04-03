# footer_composer_has_draft_queue_hint_enabled

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/footer.rs
- **Snapshot File**: codex_tui__bottom_pane__footer__tests__footer_composer_has_draft_queue_hint_enabled.snap
- **Test Function**: footer_snapshots

## Purpose
This snapshot tests the footer rendering when the composer has a draft and a task is running. It displays the queue message hint to inform users they can queue additional messages while a task is active.

## Source Code Context
The snapshot is generated from:

```rust
snapshot_footer(
    "footer_composer_has_draft_queue_hint_enabled",
    FooterProps {
        mode: FooterMode::ComposerHasDraft,
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

The queue hint logic:
```rust
let show_queue_hint = match props.mode {
    FooterMode::ComposerHasDraft => props.is_task_running,
    _ => false,
};
```

The left side line generation:
```rust
SummaryHintKind::QueueMessage => {
    line.push_span(key_hint::plain(KeyCode::Tab));
    line.push_span(" to queue message".dim());
}
```

## UI Components Involved
- `FooterProps` - Footer configuration
- `FooterMode::ComposerHasDraft` - Mode when composer has content
- `SummaryHintKind::QueueMessage` - Queue hint variant
- `key_hint::plain()` - Key binding display

## Key Rendering Logic
The footer renders:
- Left side: "tab to queue message" (with Tab key styled)
- Right side: "100% context left"

The queue hint appears only when:
1. Mode is `ComposerHasDraft`
2. A task is currently running (`is_task_running: true`)

## Test Setup Details
The test creates `FooterProps` with:
- Mode: `ComposerHasDraft`
- `is_task_running`: true
- No collaboration mode
- Default context window

## Dependencies
- `FooterProps` - Footer configuration
- `FooterMode` - Footer mode enum
- `SummaryHintKind` - Hint type enum
- `key_hint` - Key binding styling

## Notes
- The queue hint allows users to send follow-up messages while Codex is working
- This is useful for adding context or correcting course mid-task
- The hint is suppressed when no task is running (normal draft mode)
- The Tab key is the shortcut for queuing messages
