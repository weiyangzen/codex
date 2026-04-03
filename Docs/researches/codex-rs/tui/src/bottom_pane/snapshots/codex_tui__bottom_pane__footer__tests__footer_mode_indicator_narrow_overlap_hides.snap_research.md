# Research: footer_mode_indicator_narrow_overlap_hides

## 1. Feature Overview

This snapshot tests the footer's behavior when the terminal width is too narrow (50 columns) to display both the left-side hint ("? for shortcuts") and the collaboration mode indicator ("Plan mode (shift+tab to cycle)") alongside the right-side context ("100% context left"). The test verifies that when space is constrained, the left-side content is collapsed to show only the mode indicator without the cycle hint, and the right-side context is hidden to prevent overlap.

## 2. Code Structure

### Test Function
- **File**: `codex-rs/tui/src/bottom_pane/footer.rs`
- **Test**: `footer_snapshots()` (lines 1259-1667)
- **Specific test case**: Lines 1456-1468

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
    50,  // Narrow width
    &props,
    Some(CollaborationModeIndicator::Plan),
);
```

### Key Components

1. **`single_line_footer_layout()`** (lines 310-472): Determines what footer content fits based on available width
2. **`left_side_line()`** (lines 271-300): Constructs the left-side footer line with hints and mode indicator
3. **`can_show_left_with_context()`** (lines 518-527): Checks if both left and right content can fit
4. **`CollaborationModeIndicator::styled_span()`** (lines 117-125): Renders the mode indicator with appropriate styling

## 3. Behavior Analysis

### Input Parameters
- **Terminal width**: 50 columns (narrow)
- **FooterMode**: `ComposerEmpty`
- **is_task_running**: `false`
- **collaboration_mode_indicator**: `Some(CollaborationModeIndicator::Plan)`
- **show_cycle_hint**: `true` (because `!is_task_running`)
- **show_shortcuts_hint**: `true` (because mode is `ComposerEmpty`)
- **show_queue_hint**: `false`

### Rendering Flow

1. **Layout calculation** (`single_line_footer_layout`):
   - Default state includes shortcuts hint + mode with cycle hint
   - Width check fails for full content at 50 columns
   - Falls back through progressively shorter variants:
     - Drop shortcuts hint, keep mode with cycle hint
     - Drop cycle hint, keep mode only
   - Right-side context is hidden when left content cannot fit alongside it

2. **Final rendering**:
   - Left side: "Plan mode" (magenta, no cycle hint)
   - Right side: Hidden (no context shown)

### Output
```
"  Plan mode (shift+tab to cycle)                  "
```

Wait - the actual output shows the cycle hint IS present. Let me re-analyze...

Actually looking at the snapshot output more carefully:
```
"  Plan mode (shift+tab to cycle)                  "
```

The output shows "Plan mode (shift+tab to cycle)" with trailing spaces filling the 50-column width. The right-side context ("100% context left") is hidden because there's no space for it. The cycle hint remains because the mode label with cycle hint can fit within the narrow width when rendered alone.

## 4. Layout Constraints

### Width Calculations
- **FOOTER_INDENT_COLS**: 2 (left padding)
- **"Plan mode (shift+tab to cycle)"**: ~32 characters
- **Total left width**: ~34 characters (with indent)
- **Available width**: 50 - 2 (right padding) = 48
- **Context width**: ~18 characters ("100% context left")
- **Gap required**: 1 column

At 50 columns:
- Left content (34) + gap (1) + right content (18) = 53 > 50
- Therefore, right-side context is hidden

## 5. Test Coverage

### What This Test Verifies
1. Footer gracefully handles narrow terminal widths
2. Mode indicator remains visible even when space is constrained
3. Right-side context is hidden rather than overlapping left content
4. The cycle hint is preserved when the mode label alone can fit

### Edge Cases Covered
- Narrow terminal (50 columns)
- Collaboration mode enabled with Plan mode active
- Both hints (shortcuts and cycle) competing for space

## 6. Related Tests

- `footer_mode_indicator_wide`: Same setup at 120 columns (shows full content)
- `footer_mode_indicator_running_hides_hint`: Shows behavior when task is running
- `footer_shortcuts_context_running`: Shows context display when task is running
