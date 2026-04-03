# footer_esc_hint_idle

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/footer.rs
- **Snapshot File**: codex_tui__bottom_pane__footer__tests__footer_esc_hint_idle.snap
- **Test Function**: footer_snapshots

## Purpose
This snapshot tests the footer rendering when the user has pressed Esc once while idle and needs to press it again to edit the previous message. It displays the Esc hint with the double-press pattern.

## Source Code Context
The snapshot is generated from:

```rust
snapshot_footer(
    "footer_esc_hint_idle",
    FooterProps {
        mode: FooterMode::EscHint,
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

The Esc hint line generation:
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

## UI Components Involved
- `FooterProps` - Footer configuration
- `FooterMode::EscHint` - Transient Esc hint mode
- `esc_hint_line()` - Esc hint text generator
- `key_hint::plain()` - Plain key formatter

## Key Rendering Logic
The footer renders:
- "esc esc to edit previous message" (dimmed text)

When `esc_backtrack_hint` is false, the hint shows the double-press pattern (esc esc) to indicate the user needs to press Esc twice.

## Test Setup Details
The test creates `FooterProps` with:
- Mode: `EscHint`
- `esc_backtrack_hint`: false
- `is_task_running`: false

## Dependencies
- `FooterProps` - Footer configuration
- `FooterMode::EscHint` - Mode for Esc hint display
- `esc_hint_line()` - Hint line generator
- `key_hint::plain()` - Key binding formatter

## Notes
- The Esc hint appears after the first Esc press when idle
- `esc_backtrack_hint: false` means this is the initial hint (showing "esc esc")
- `esc_backtrack_hint: true` would show "esc again" (after first Esc in sequence)
- This allows users to edit their previous message in the conversation
- The hint is suppressed when a task is running
