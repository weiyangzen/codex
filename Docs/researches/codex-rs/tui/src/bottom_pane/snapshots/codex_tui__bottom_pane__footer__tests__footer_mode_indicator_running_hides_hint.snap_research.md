# Research: footer_mode_indicator_running_hides_hint

## 1. Feature Overview

This snapshot tests the footer's behavior when a task is running (`is_task_running: true`) with collaboration modes enabled. When a task is running, the footer suppresses the mode cycle hint ("shift+tab to cycle") because mode switching is not allowed during active task execution. The test verifies that at wide width (120 columns), the footer shows the shortcuts hint, the mode indicator without the cycle hint, and the context window percentage.

## 2. Code Structure

### Test Function
- **File**: `codex-rs/tui/src/bottom_pane/footer.rs`
- **Test**: `footer_snapshots()` (lines 1259-1667)
- **Specific test case**: Lines 1470-1490

```rust
let props = FooterProps {
    mode: FooterMode::ComposerEmpty,
    esc_backtrack_hint: false,
    use_shift_enter_hint: false,
    is_task_running: true,  // Task is running!
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
    120,  // Wide width
    &props,
    Some(CollaborationModeIndicator::Plan),
);
```

### Key Components

1. **`draw_footer_frame()`** (lines 1074-1234): Test helper that sets up rendering
   - Line 1083: `show_cycle_hint = !props.is_task_running` - cycle hint suppressed when running
   - Line 1084-1090: `show_shortcuts_hint` logic based on mode

2. **`single_line_footer_layout()`** (lines 310-472): Width-based layout decisions

3. **`CollaborationModeIndicator::label()`** (lines 102-115): Builds mode label with optional cycle hint

## 3. Behavior Analysis

### Input Parameters
- **Terminal width**: 120 columns (wide)
- **FooterMode**: `ComposerEmpty`
- **is_task_running**: `true` (task is active)
- **collaboration_mode_indicator**: `Some(CollaborationModeIndicator::Plan)`
- **show_cycle_hint**: `false` (suppressed because `is_task_running`)
- **show_shortcuts_hint**: `true` (because mode is `ComposerEmpty`)
- **show_queue_hint**: `false`

### Key Logic

In `draw_footer_frame()` (line 1083):
```rust
let show_cycle_hint = !props.is_task_running;
```

When `is_task_running` is `true`, `show_cycle_hint` becomes `false`, which means:
- The mode label will be "Plan mode" instead of "Plan mode (shift+tab to cycle)"
- This is enforced in `CollaborationModeIndicator::label()` (line 103-107)

### Rendering Flow

1. **Layout calculation**:
   - Default state: shortcuts hint + mode without cycle hint
   - At 120 columns, everything fits comfortably
   - Left content + right context can coexist

2. **Final rendering**:
   - Left side: "? for shortcuts · Plan mode"
   - Right side: "100% context left" (default when no percent/tokens specified)

### Output
```
"  ? for shortcuts · Plan mode                                                                        100% context left  "
```

## 4. Context Window Display

### Default Context Behavior
In `context_window_line()` (lines 848-860):
```rust
pub(crate) fn context_window_line(percent: Option<i64>, used_tokens: Option<i64>) -> Line<'static> {
    if let Some(percent) = percent {
        // Show percent
    }
    if let Some(tokens) = used_tokens {
        // Show tokens
    }
    Line::from(vec![Span::from("100% context left").dim()])  // Default
}
```

Since both `context_window_percent` and `context_window_used_tokens` are `None`, the default "100% context left" is displayed.

## 5. Test Coverage

### What This Test Verifies
1. Mode cycle hint is suppressed when a task is running
2. Footer still shows shortcuts hint in `ComposerEmpty` mode
3. Context window indicator is displayed on the right
4. Wide terminal (120 columns) accommodates all content

### Business Logic Validated
- Users cannot switch collaboration modes during active task execution
- The UI communicates this restriction by hiding the cycle hint
- Other footer functionality remains available

## 6. Related Tests

- `footer_mode_indicator_wide`: Same setup but `is_task_running: false` (shows cycle hint)
- `footer_mode_indicator_narrow_overlap_hides`: Narrow width with same constraints
- `footer_shortcuts_context_running`: Shows context percentage (72%) when running
