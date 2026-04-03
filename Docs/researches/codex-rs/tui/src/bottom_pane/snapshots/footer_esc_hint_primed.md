# footer_esc_hint_primed

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/footer.rs
- **Snapshot File**: codex_tui__bottom_pane__footer__tests__footer_esc_hint_primed.snap
- **Test Function**: footer_snapshots

## Purpose
This snapshot tests the footer rendering when the user has already pressed Esc once and the backtrack hint is active. It displays the "again" variant of the Esc hint.

## Source Code Context
The snapshot is generated from:

```rust
snapshot_footer(
    "footer_esc_hint_primed",
    FooterProps {
        mode: FooterMode::EscHint,
        esc_backtrack_hint: true,
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

## Key Rendering Logic
The footer renders:
- "esc again to edit previous message" (dimmed text)

When `esc_backtrack_hint` is true, the hint changes from "esc esc" to "esc again" to indicate the user has already pressed Esc once and needs to press it once more.

## Test Setup Details
The test creates `FooterProps` with:
- Mode: `EscHint`
- `esc_backtrack_hint`: true
- `is_task_running`: false

## Dependencies
- `FooterProps` - Footer configuration
- `FooterMode::EscHint` - Mode for Esc hint display
- `esc_hint_line()` - Hint line generator

## Notes
- The "again" variant appears after the user has already pressed Esc once
- This is part of a two-step confirmation to prevent accidental message editing
- The state transition is: normal -> EscHint (esc_backtrack_hint: false) -> after first Esc -> EscHint (esc_backtrack_hint: true)
- Pressing Esc a second time triggers the message editing action
