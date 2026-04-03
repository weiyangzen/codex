# Research: footer_status_line_truncated_with_gap

## Snapshot Content
```
"  Status line content that … Plan mode  "
```

## Source Location
`codex-rs/tui/src/bottom_pane/footer.rs`

## Test Context
This snapshot is generated in the `footer_snapshots` test function. It tests the footer rendering when:
- Terminal width: 40 columns (narrow)
- `status_line_enabled: true` - Status line feature enabled
- `status_line_value: Some(Line::from("Status line content that should truncate before the mode indicator"))` - Long status line
- `collaboration_mode_indicator: Some(CollaborationModeIndicator::Plan)` - Plan mode active
- `context_window_percent: Some(50)` - Context at 50%

## Expected Behavior (What the Test Validates)
When the terminal is narrow and both status line and mode indicator need to be displayed, the status line is truncated with an ellipsis (…) to ensure the mode indicator remains visible. The truncation preserves a minimum gap between the status line and the mode indicator.

## Component Documentation

### FooterProps Relevant Fields
- `status_line_enabled: bool` - Enables status line display
- `status_line_value: Option<Line<'static>>` - Long status line content that needs truncation
- `collaboration_modes_enabled: bool` - Enables mode indicator display

### Key Functions
- `truncate_line_with_ellipsis_if_overflow()` - Truncates line with "…" when it exceeds max width
- `max_left_width_for_right()` - Calculates maximum width for left content when right content is present
- `can_show_left_with_context()` - Determines if both left and right content can fit

### Truncation Logic
```rust
if status_line_active
    && let Some(max_left) = max_left_width_for_right(area, right_width)
    && left_width > max_left
    && let Some(line) = passive_status_line
        .as_ref()
        .map(|line| line.clone().dim())
        .map(|line| truncate_line_with_ellipsis_if_overflow(line, max_left as usize))
{
    left_width = line.width() as u16;
    truncated_status_line = Some(line);
}
```

## Layout and Rendering Details
- Terminal width: 40 columns
- Left indent: 2 spaces
- Status line shown: "Status line content that …" (truncated with ellipsis)
- Separator: space
- Mode indicator: "Plan mode" (magenta colored)
- Right padding: 2 spaces

The truncation ensures that "Plan mode" remains fully visible even in narrow terminals.

## Related Snapshots
- `footer_status_line_enabled_mode_right` - Wide terminal showing full status line with mode
- `footer_mode_indicator_narrow_overlap_hides` - Mode indicator handling in narrow terminals
- `footer_status_line_truncates_to_keep_mode_indicator` - Unit test for truncation behavior

## Architectural Notes
The footer implements a sophisticated width-based collapse system:
1. First, try to show full status line with full mode indicator
2. If that doesn't fit, truncate status line with ellipsis
3. If still doesn't fit, use compact mode indicator (without "shift+tab to cycle")
4. Final fallback: hide mode indicator entirely

The `FOOTER_CONTEXT_GAP_COLS` constant (1 column) ensures minimum spacing between left and right content. This snapshot demonstrates the ellipsis truncation path in the collapse hierarchy.

The related unit test `footer_status_line_truncates_to_keep_mode_indicator` explicitly validates that:
- Mode indicator remains visible after truncation
- Compact mode is used when space is tight (no "shift+tab to cycle")
- Ellipsis character (…) appears in the truncated output
