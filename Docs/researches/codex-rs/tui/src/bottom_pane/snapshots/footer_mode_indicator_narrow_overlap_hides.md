# footer_mode_indicator_narrow_overlap_hides

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/footer.rs
- **Snapshot File**: codex_tui__bottom_pane__footer__tests__footer_mode_indicator_narrow_overlap_hides.snap
- **Test Function**: footer_snapshots

## Purpose
This snapshot tests the footer rendering at narrow width (50 columns) with a collaboration mode indicator. It demonstrates how the footer collapses when there isn't enough space for both the mode indicator and context.

## Source Code Context
The snapshot is generated from:

```rust
let props = FooterProps {
    mode: FooterMode::ComposerEmpty,
    esc_backtrack_hint: false,
    use_shift_enter_hint: false,
    is_task_running: false,
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
    "footer_mode_indicator_narrow_overlap_hides",
    50,
    &props,
    Some(CollaborationModeIndicator::Plan),
);
```

The collapse logic in `single_line_footer_layout()`:
```rust
// When the mode cycle hint is applicable (idle, non-queue mode), only show
// the right-side context indicator if the "(shift+tab to cycle)" variant
// can also fit.
let context_requires_cycle_hint = show_cycle_hint && !show_queue_hint;

// ... fallback logic drops context when it can't fit
let mode_only_state = LeftSideState {
    hint: SummaryHintKind::None,
    show_cycle_hint: false,
};
let mode_only_width = state_width(mode_only_state);
if mode_only_width > 0 && left_fits(area, mode_only_width) {
    return (
        SummaryLeft::Custom(state_line(mode_only_state)),
        false, // show_context
    );
}
```

## UI Components Involved
- `FooterProps` - Footer configuration
- `CollaborationModeIndicator::Plan` - Mode indicator
- `single_line_footer_layout()` - Width-based collapse logic

## Key Rendering Logic
At 50 columns width:
- The full mode indicator with cycle hint doesn't fit with context
- The footer falls back to showing only: "Plan mode (shift+tab to cycle)"
- The context window indicator is hidden due to space constraints

## Test Setup Details
The test creates `FooterProps` with:
- Mode: `ComposerEmpty`
- `collaboration_modes_enabled`: true
- Width: 50 columns
- Mode indicator: `CollaborationModeIndicator::Plan`

## Dependencies
- `FooterProps` - Footer configuration
- `CollaborationModeIndicator` - Mode indicator enum
- `single_line_footer_layout()` - Layout calculation

## Notes
- At narrow widths, the footer prioritizes showing the mode indicator over context
- The cycle hint "(shift+tab to cycle)" is preserved when possible
- The context window indicator is the first element to be dropped
- This demonstrates the responsive design of the footer
