# Research: footer_status_line_disabled_context_right

## 1. Feature Overview

This snapshot tests the footer's behavior when the status line feature is disabled (`status_line_enabled: false`) but collaboration modes are enabled. In this configuration, the footer displays the standard left-side content (shortcuts hint and mode indicator with cycle hint) and the right-side shows the context window percentage ("50% context left"). This is the "classic" footer layout without the configurable status line feature, showing how context information is displayed when status line is not active.

## 2. Code Structure

### Test Function
- **File**: `codex-rs/tui/src/bottom_pane/footer.rs`
- **Test**: `footer_snapshots()` (lines 1259-1667)
- **Specific test case**: Lines 1565-1585

```rust
let props = FooterProps {
    mode: FooterMode::ComposerEmpty,
    esc_backtrack_hint: false,
    use_shift_enter_hint: false,
    is_task_running: false,
    collaboration_modes_enabled: true,
    is_wsl: false,
    quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),
    context_window_percent: Some(50),  // Context at 50%
    context_window_used_tokens: None,
    status_line_value: None,
    status_line_enabled: false,  // Status line DISABLED
    active_agent_label: None,
};

snapshot_footer_with_mode_indicator(
    "footer_status_line_disabled_context_right",
    120,
    &props,
    Some(CollaborationModeIndicator::Plan),
);
```

### Key Components

1. **`uses_passive_footer_status_layout()`** (lines 680-682): Determines if status line layout should be used
   ```rust
   pub(crate) fn uses_passive_footer_status_layout(props: &FooterProps) -> bool {
       props.status_line_enabled && shows_passive_footer_line(props)
   }
   ```

2. **`draw_footer_frame()`** (lines 1074-1234): Test helper with branching logic
   - Line 1098: Checks `status_line_active`
   - Lines 1145-1150: When status line NOT active, uses `context_window_line()` for right side

3. **`single_line_footer_layout()`** (lines 310-472): Standard footer layout logic

## 3. Behavior Analysis

### Input Parameters
- **Terminal width**: 120 columns
- **FooterMode**: `ComposerEmpty`
- **status_line_enabled**: `false`
- **context_window_percent**: `Some(50)`
- **collaboration_mode_indicator**: `Some(CollaborationModeIndicator::Plan)`
- **is_task_running**: `false`
- **show_cycle_hint**: `true` (because `!is_task_running`)

### Layout Decision Path

In `draw_footer_frame()` (line 1098):
```rust
let status_line_active = uses_passive_footer_status_layout(props);
// status_line_enabled: false → status_line_active: false
```

Since `status_line_active` is `false`:
1. **Left side** (lines 1104-1108): Uses `collaboration_mode_indicator` (not `None`)
2. **Right side** (lines 1145-1150): Uses `context_window_line()`:
   ```rust
   Some(context_window_line(
       props.context_window_percent,      // Some(50)
       props.context_window_used_tokens,  // None
   ))
   ```
   Result: "50% context left"

### Rendering Flow

1. **Left content** (`single_line_footer_layout`):
   - Shortcuts hint + mode indicator with cycle hint
   - "? for shortcuts · Plan mode (shift+tab to cycle)"

2. **Right content**:
   - Context window percentage
   - "50% context left"

3. **Layout check**:
   - At 120 columns, everything fits
   - Both sides displayed

### Output
```
"  ? for shortcuts · Plan mode (shift+tab to cycle)                                                    50% context left  "
```

## 4. Comparison: Status Line Enabled vs Disabled

| Feature | `footer_status_line_enabled_mode_right` | `footer_status_line_disabled_context_right` |
|---------|----------------------------------------|--------------------------------------------|
| `status_line_enabled` | `true` | `false` |
| Left side | Status line content (empty/truncated) | Shortcuts + mode indicator |
| Right side | Mode indicator | Context window percentage |
| Layout type | Status line layout | Standard footer layout |

When status line is enabled but value is `None`:
- Left side shows nothing (or would show status line if present)
- Right side shows mode indicator

When status line is disabled:
- Left side shows shortcuts + mode
- Right side shows context percentage

## 5. Test Coverage

### What This Test Verifies
1. Footer falls back to standard layout when status line is disabled
2. Context window percentage appears on the right side
3. Mode indicator with cycle hint appears on the left
4. Shortcuts hint is shown in `ComposerEmpty` mode

### Feature Flag Behavior
This test validates the `status_line_enabled` configuration option:
- When `false`: Traditional footer with context percentage
- When `true`: Status line takes over left side, mode moves to right

## 6. Related Tests

- `footer_status_line_enabled_mode_right`: Same setup but `status_line_enabled: true`
- `footer_status_line_overrides_shortcuts`: Status line with actual content
- `footer_status_line_truncated_with_gap`: Status line truncation behavior
- `footer_shortcuts_context_running`: Context percentage with task running
