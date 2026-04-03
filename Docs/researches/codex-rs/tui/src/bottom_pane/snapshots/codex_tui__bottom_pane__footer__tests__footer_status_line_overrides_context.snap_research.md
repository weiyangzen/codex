# Research: footer_status_line_overrides_context

## Snapshot Content
```
"  Italic text                                                                   "
```

## Source Location
`codex-rs/tui/src/bottom_pane/footer.rs`

## Test Context
This snapshot is generated in the `footer_snapshots` test function. It tests the footer rendering when:
- `status_line_enabled: true`
- `status_line_value: Some(Line::from("Italic text".to_string()))` - Status line with italic-styled content
- `context_window_percent: Some(50)` - Context window at 50%
- Terminal width: 80 columns

Note: The actual test code shows `status_line_value: None` in the props struct, but the snapshot shows "Italic text". This suggests the test may have been updated or there's additional styling logic that applies italic formatting to the status line content.

## Expected Behavior (What the Test Validates)
When the status line is enabled and has content, it overrides the default context window display. The status line content is shown on the left side of the footer, dimmed (styled with `.dim()`), and takes precedence over showing context window percentage.

## Component Documentation

### FooterProps Relevant Fields
- `status_line_enabled: bool` - Enables the status line feature
- `status_line_value: Option<Line<'static>>` - The configurable status line content
- `context_window_percent: Option<i64>` - Would show "50% context left" if status line wasn't enabled

### Key Functions
- `passive_footer_status_line()` - Returns `Some(Line)` when status line is enabled and mode allows passive display
- `shows_passive_footer_line()` - Returns true for `ComposerEmpty` and `ComposerHasDraft` (when not running)
- `render_footer_line()` - Renders the status line with dim styling

### Rendering Flow
1. `uses_passive_footer_status_layout()` checks if status line should be used
2. `passive_footer_status_line()` retrieves the status line value
3. Content is rendered via `render_footer_line()` with `.dim()` styling applied
4. The context window line is NOT rendered because the status line takes the left side

## Layout and Rendering Details
- Left indent: 2 spaces (`FOOTER_INDENT_COLS`)
- Content: "Italic text" (10 characters)
- Remaining: 68 spaces to fill 80-column width
- Styling: `.dim()` applied to the entire line

## Related Snapshots
- `footer_status_line_overrides_shortcuts` - Status line replacing shortcut hints
- `footer_status_line_overrides_draft_idle` - Status line in draft mode when idle
- `footer_shortcuts_context_running` - Context shown when status line disabled

## Architectural Notes
The status line feature allows users to customize footer content via `/statusline` configuration. When active, it replaces the default "? for shortcuts" hint and context information, giving users control over what contextual information appears in the footer.
