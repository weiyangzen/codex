# Research: footer_status_line_enabled_mode_right

## 1. Feature Overview

This snapshot tests the footer's behavior when the status line feature is enabled (`status_line_enabled: true`) but no status line content is available (`status_line_value: None`). In this configuration, the footer uses the "passive footer status layout" where the left side would normally display the status line content, but since it's empty, nothing appears on the left. The right side displays the collaboration mode indicator ("Plan mode (shift+tab to cycle)") instead of the context window percentage. This represents the status line layout mode with an empty/truncated status line.

## 2. Code Structure

### Test Function
- **File**: `codex-rs/tui/src/bottom_pane/footer.rs`
- **Test**: `footer_snapshots()` (lines 1259-1667)
- **Specific test case**: Lines 1543-1563

```rust
let props = FooterProps {
    mode: FooterMode::ComposerEmpty,
    esc_backtrack_hint: false,
    use_shift_enter_hint: false,
    is_task_running: false,
    collaboration_modes_enabled: true,
    is_wsl: false,
    quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),
    context_window_percent: Some(50),
    context_window_used_tokens: None,
    status_line_value: None,  // No status line content
    status_line_enabled: true,  // But feature is enabled!
    active_agent_label: None,
};

snapshot_footer_with_mode_indicator(
    "footer_status_line_enabled_mode_right",
    120,
    &props,
    Some(CollaborationModeIndicator::Plan),
);
```

### Key Components

1. **`uses_passive_footer_status_layout()`** (lines 680-682): Determines layout mode
   ```rust
   pub(crate) fn uses_passive_footer_status_layout(props: &FooterProps) -> bool {
       props.status_line_enabled && shows_passive_footer_line(props)
   }
   ```

2. **`draw_footer_frame()`** (lines 1074-1234): Test rendering with status line logic
   - Lines 1099-1103: Gets `passive_status_line` (None in this case)
   - Lines 1104-1108: `left_mode_indicator` is `None` when status line active
   - Lines 1136-1144: Right side shows mode indicator when status line active
   - Lines 1174-1180: Renders status line left, mode indicator right

3. **`mode_indicator_line()`** (lines 474-479): Creates mode indicator for right side
   ```rust
   pub(crate) fn mode_indicator_line(
       indicator: Option<CollaborationModeIndicator>,
       show_cycle_hint: bool,
   ) -> Option<Line<'static>> {
       indicator.map(|indicator| Line::from(vec![indicator.styled_span(show_cycle_hint)]))
   }
   ```

## 3. Behavior Analysis

### Input Parameters
- **Terminal width**: 120 columns
- **FooterMode**: `ComposerEmpty`
- **status_line_enabled**: `true`
- **status_line_value**: `None` (command timed out or empty)
- **context_window_percent**: `Some(50)` (ignored in this layout)
- **collaboration_mode_indicator**: `Some(CollaborationModeIndicator::Plan)`

### Layout Decision Path

In `draw_footer_frame()`:

1. **Check status line active** (line 1098):
   ```rust
   let status_line_active = uses_passive_footer_status_layout(props);
   // status_line_enabled: true && shows_passive_footer_line: true → true
   ```

2. **Left side handling** (lines 1099-1103):
   ```rust
   let passive_status_line = if status_line_active {
       passive_footer_status_line(props)  // Returns None
   } else {
       None
   };
   ```

3. **Left mode indicator suppressed** (lines 1104-1108):
   ```rust
   let left_mode_indicator = if status_line_active {
       None  // Mode indicator moves to right side
   } else {
       collaboration_mode_indicator
   };
   ```

4. **Right side shows mode indicator** (lines 1136-1144):
   ```rust
   let right_line = if status_line_active {
       let full = mode_indicator_line(collaboration_mode_indicator, show_cycle_hint);
       // ... width check ...
       full  // "Plan mode (shift+tab to cycle)"
   } else {
       // Would show context_window_line
   };
   ```

5. **Rendering** (lines 1174-1180):
   - Left: `truncated_status_line` is `None` → nothing rendered
   - Right: mode indicator rendered via `render_context_right()`

### Output
```
"                                                                                        Plan mode (shift+tab to cycle)  "
```

## 4. Visual Structure

```
[empty left padding][padding to right-align][mode indicator][right indent]
  2 + ~80            ~4                        32              2
```

The mode indicator is right-aligned with the standard footer right padding.

### Styling
- "Plan mode (shift+tab to cycle)": Magenta (Plan mode color)
- Entire line has dim styling applied via `render_context_right`

## 5. Test Coverage

### What This Test Verifies
1. Status line layout mode activates when `status_line_enabled: true`
2. When status line value is `None`, left side is empty
3. Mode indicator moves to right side (instead of context percentage)
4. Context window percentage is NOT shown in status line layout mode
5. Right-alignment works correctly for mode indicator

### Real-World Scenario
This represents the state when:
- User has enabled the status line feature in config
- The `/statusline` command hasn't returned data yet (timed out)
- Footer still shows the collaboration mode on the right
- Once status line data arrives, it would appear on the left

## 6. Related Tests

- `footer_status_line_disabled_context_right`: Same setup but `status_line_enabled: false`
- `footer_status_line_overrides_shortcuts`: Status line with actual content
- `footer_status_line_truncated_with_gap`: Status line truncation with mode indicator
- `footer_status_line_enabled_no_mode_right`: Status line enabled but no collaboration mode
