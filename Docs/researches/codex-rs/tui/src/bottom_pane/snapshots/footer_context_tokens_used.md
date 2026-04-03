# footer_context_tokens_used

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/footer.rs
- **Snapshot File**: codex_tui__bottom_pane__footer__tests__footer_context_tokens_used.snap
- **Test Function**: footer_snapshots

## Purpose
This snapshot tests the footer rendering when context is displayed as tokens used rather than percentage remaining. It shows the alternative format for context window usage.

## Source Code Context
The snapshot is generated from:

```rust
snapshot_footer(
    "footer_context_tokens_used",
    FooterProps {
        mode: FooterMode::ComposerEmpty,
        esc_backtrack_hint: false,
        use_shift_enter_hint: false,
        is_task_running: false,
        collaboration_modes_enabled: false,
        is_wsl: false,
        quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),
        context_window_percent: None,
        context_window_used_tokens: Some(123_456),
        status_line_value: None,
        status_line_enabled: false,
        active_agent_label: None,
    },
);
```

The context window line generation:
```rust
pub(crate) fn context_window_line(percent: Option<i64>, used_tokens: Option<i64>) -> Line<'static> {
    if let Some(percent) = percent {
        let percent = percent.clamp(0, 100);
        return Line::from(vec![Span::from(format!("{percent}% context left")).dim()]);
    }

    if let Some(tokens) = used_tokens {
        let used_fmt = format_tokens_compact(tokens);
        return Line::from(vec![Span::from(format!("{used_fmt} used")).dim()]);
    }

    Line::from(vec![Span::from("100% context left").dim()])
}
```

## UI Components Involved
- `FooterProps` - Footer configuration
- `context_window_line()` - Context display formatter
- `format_tokens_compact()` - Token count formatting (e.g., 123456 -> "123K")

## Key Rendering Logic
The footer renders:
- Left side: "? for shortcuts" (default hint)
- Right side: "123K used" (formatted token count)

The token count is formatted compactly:
- 123_456 -> "123K"
- Uses `format_tokens_compact()` for human-readable numbers

## Test Setup Details
The test creates `FooterProps` with:
- Mode: `ComposerEmpty`
- `context_window_used_tokens`: Some(123_456)
- `context_window_percent`: None
- Default shortcuts hint

## Dependencies
- `FooterProps` - Footer configuration
- `context_window_line()` - Context formatter
- `format_tokens_compact()` - Number formatting utility

## Notes
- The token-based display is an alternative to percentage-based display
- Token counts are formatted compactly (K for thousands, M for millions)
- Either `context_window_percent` or `context_window_used_tokens` can be set, not both
- If neither is set, defaults to "100% context left"
