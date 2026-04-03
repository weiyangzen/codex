# Research: footer_status_line_enabled_no_mode_right

## Snapshot Content
```
"                                                                                                                        "
```

## Source Location
`codex-rs/tui/src/bottom_pane/footer.rs`

## Test Context
This snapshot is generated in the `footer_snapshots` test function. It tests the footer rendering when:
- `status_line_enabled: true` (status line feature is enabled)
- `status_line_value: None` (no status line content provided - command timed out or empty)
- `collaboration_mode_indicator: None` (no collaboration mode active)
- `context_window_percent: Some(50)` (50% context left)
- Terminal width: 120 columns

## Expected Behavior (What the Test Validates)
When the status line is enabled but has no content value, and there is no collaboration mode indicator, the footer should render an empty line (just spaces). The status line feature is active but since there's no actual content to display, the footer area remains blank.

## Component Documentation

### FooterProps Relevant Fields
- `status_line_enabled: bool` - Whether the configurable status line feature is active
- `status_line_value: Option<Line<'static>>` - The actual content to display (None in this case)
- `mode: FooterMode::ComposerEmpty` - Base state when composer is empty

### Key Functions
- `uses_passive_footer_status_layout()` - Returns true when status line is enabled and mode allows passive footer
- `passive_footer_status_line()` - Returns the status line content when available
- `render_footer_line()` - Renders the footer line with proper indentation

## Layout and Rendering Details
- The footer uses `FOOTER_INDENT_COLS` (2 spaces) for left indentation
- When `status_line_enabled` is true but `status_line_value` is None, no content is rendered
- The 120-column terminal width results in a line of 120 space characters

## Related Snapshots
- `footer_status_line_enabled_mode_right` - Status line enabled WITH collaboration mode
- `footer_status_line_disabled_context_right` - Status line disabled, shows context instead
- `footer_status_line_overrides_shortcuts` - Status line with actual content

## Architectural Notes
The status line system allows users to configure contextual information display via `/statusline` commands. When enabled but empty, the footer intentionally shows nothing rather than falling back to default hints, maintaining the user's preference for a minimal footer.
