# Research: footer_status_line_disabled_context_right Snapshot Test

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer behavior when the status line feature is disabled but context information is available and should be displayed on the right side. This scenario occurs when:

- The status line feature is explicitly disabled (`status_line_enabled: false`)
- Context usage information is available (50% remaining)
- The collaboration mode indicator is active (Plan mode)
- The terminal is wide (120 characters)

**Responsibility**: Ensures that when the status line is disabled, the footer falls back to showing the standard context information on the right side, maintaining useful information display even without the custom status line feature.

## 2. 功能点目的 (Feature Purpose)

The status line disabled fallback serves to:
- Provide context information even when custom status line is off
- Maintain consistent right-side information display
- Show the collaboration mode indicator alongside context
- Ensure the footer is never completely empty on the right side

**Test Purpose**: Verify that with `status_line_enabled: false`, the footer displays the mode indicator on the left and context percentage on the right, rather than showing nothing.

## 3. 具体技术实现 (Technical Implementation)

### Test Configuration
```rust
let props = FooterProps {
    mode: FooterMode::ComposerEmpty,
    esc_backtrack_hint: false,
    use_shift_enter_hint: false,
    is_task_running: false,
    collaboration_modes_enabled: true,
    is_wsl: false,
    quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),
    context_window_percent: Some(50),  // 50% context remaining
    context_window_used_tokens: None,
    status_line_value: None,
    status_line_enabled: false,  // Status line disabled
    active_agent_label: None,
};

snapshot_footer_with_mode_indicator(
    "footer_status_line_disabled_context_right",
    120,
    &props,
    Some(CollaborationModeIndicator::Plan),
);
```

### Rendering Flow
1. `uses_passive_footer_status_layout()` checks `status_line_enabled` → returns `false`
2. `status_line_active` is `false`, so standard footer flow is used
3. `left_mode_indicator` is set to `Some(CollaborationModeIndicator::Plan)`
4. `right_line` is set to `context_window_line(...)` → "50% context left"
5. `single_line_footer_layout()` determines layout
6. Both mode indicator and context are rendered

### Key Code Path
```rust
// footer.rs:1098-1150 (draw_footer_frame)
let status_line_active = uses_passive_footer_status_layout(props);
// status_line_active = false because status_line_enabled = false

let left_mode_indicator = if status_line_active {
    None
} else {
    collaboration_mode_indicator  // Some(Plan)
};

let right_line = if status_line_active {
    // Status line path (not taken)
} else {
    Some(context_window_line(
        props.context_window_percent,
        props.context_window_used_tokens,
    ))  // "50% context left"
};
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files
- `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - Lines 676-682: `uses_passive_footer_status_layout()` function
  - Lines 1098-1108: Status line check and path selection
  - Lines 1145-1150: Right-side line generation
  - Lines 1565-1585: Test definition

### Related Functions
- `uses_passive_footer_status_layout()` - Determines if status line layout should be used
- `shows_passive_footer_line()` - Checks if passive footer content is allowed
- `context_window_line()` - Generates context display string

### Snapshot Output
```
"  ? for shortcuts · Plan mode (shift+tab to cycle)                                                    50% context left  "
```

### Layout Analysis
```
[2 spaces][? for shortcuts · Plan mode (shift+tab to cycle)][52 spaces][50% context left][2 spaces]
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Dependencies
- `status_line_enabled` flag from `FooterProps`
- `context_window_percent` for right-side display
- `CollaborationModeIndicator` for left-side display
- `single_line_footer_layout()` for width-based layout decisions

### Status Line vs Context Display Logic
```rust
// When status_line_enabled = true:
// - Left: status_line_value
// - Right: mode_indicator_line()

// When status_line_enabled = false (this test):
// - Left: shortcuts + mode indicator (via single_line_footer_layout)
// - Right: context_window_line()
```

### Related Components
- Status line configuration - User preference for custom status
- `/statusline` command - Configures the status line content
- Context tracking system - Provides percentage/used tokens

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks
1. **Information Loss**: Users may not realize context info is available without status line
2. **Inconsistent Experience**: Different footer layouts based on feature flags may confuse users
3. **Configuration Complexity**: Multiple flags interact in complex ways

### Edge Cases
- **Both status line and context None**: Footer may be empty on right side
- **Very narrow terminal**: Context may be hidden due to width constraints
- **Status line empty string**: Different from None, may show blank space

### Comparison with Enabled State
| Feature | `status_line_enabled: true` | `status_line_enabled: false` (this test) |
|---------|---------------------------|------------------------------------------|
| Left side | Status line content | Shortcuts + mode indicator |
| Right side | Mode indicator | Context percentage |
| Fallback | Truncated status line | Hidden context if narrow |

### Improvement Suggestions
1. **Unified Display**: Consider always showing context, even with status line
2. **User Education**: Inform users about status line feature availability
3. **Default On**: Consider enabling status line by default for better UX
4. **Visual Distinction**: Different styling for status line vs context modes
5. **Migration Path**: Help users transition from context to status line

### Test Coverage
- `footer_status_line_enabled_mode_right` - Status line enabled, mode on right
- This test - Status line disabled, context on right
- `footer_status_line_enabled_no_mode_right` - Status line enabled, no mode
- Together they cover the status line feature matrix
