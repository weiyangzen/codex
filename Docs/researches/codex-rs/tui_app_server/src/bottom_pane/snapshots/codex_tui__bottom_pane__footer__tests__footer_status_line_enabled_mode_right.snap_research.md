# Research: footer_status_line_enabled_mode_right Snapshot Test

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer behavior when the status line feature is enabled but the status line value is empty (None). This scenario occurs when:

- The status line feature is enabled (`status_line_enabled: true`)
- The status line command returned no content or timed out (`status_line_value: None`)
- The collaboration mode indicator is active (Plan mode with cycle hint)
- Context usage is at 50%

**Responsibility**: Ensures that when the status line is enabled but empty, the footer correctly displays the collaboration mode indicator on the right side, maintaining a consistent layout even without status line content.

## 2. 功能点目的 (Feature Purpose)

The status line enabled with empty value serves to:
- Handle the case where status line content is not yet available
- Maintain the status line layout structure for consistency
- Show the collaboration mode indicator as fallback content
- Provide visual stability while status line content loads

**Test Purpose**: Verify that with `status_line_enabled: true` but `status_line_value: None`, the footer displays the mode indicator on the right side instead of leaving it empty.

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
    context_window_percent: Some(50),
    context_window_used_tokens: None,
    status_line_value: None,  // No status line content
    status_line_enabled: true,  // But feature is enabled
    active_agent_label: None,
};

snapshot_footer_with_mode_indicator(
    "footer_status_line_enabled_mode_right",
    120,
    &props,
    Some(CollaborationModeIndicator::Plan),
);
```

### Rendering Flow
1. `uses_passive_footer_status_layout()` returns `true` (enabled and passive mode)
2. `status_line_active` is `true`, triggering status line layout path
3. `passive_status_line` is `None` (no status line value)
4. Since status line is None, nothing is rendered on the left
5. `right_line` is set to `mode_indicator_line()` → "Plan mode (shift+tab to cycle)"
6. Mode indicator is right-aligned via `render_context_right()`

### Key Code Path
```rust
// footer.rs:1099-1103
let status_line_active = uses_passive_footer_status_layout(props);
let passive_status_line = if status_line_active {
    passive_footer_status_line(props)  // Returns None
} else {
    None
};

// footer.rs:1136-1144
let right_line = if status_line_active {
    let full = mode_indicator_line(collaboration_mode_indicator, show_cycle_hint);
    let compact = mode_indicator_line(collaboration_mode_indicator, false);
    // Choose based on available space...
    full  // "Plan mode (shift+tab to cycle)"
} else {
    // Context path (not taken)
};
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files
- `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - Lines 638-658: `passive_footer_status_line()` function
  - Lines 1136-1144: Right-side line selection for status line mode
  - Lines 1174-1180: Rendering logic for status line layout
  - Lines 1543-1563: Test definition

### Related Functions
- `passive_footer_status_line()` - Builds status line from value + agent label
- `mode_indicator_line()` - Creates mode indicator for right side
- `render_context_right()` - Renders content right-aligned

### Snapshot Output
```
"                                                                                        Plan mode (shift+tab to cycle)  "
```

### Layout Analysis
```
[88 spaces][Plan mode (shift+tab to cycle)][2 spaces]
```

Note: The left side is completely empty because:
1. Status line value is None
2. No active agent label is set
3. The mode indicator is pushed to the right side

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Dependencies
- `status_line_enabled` and `status_line_value` from `FooterProps`
- `passive_footer_status_line()` combining logic
- `mode_indicator_line()` for right-side fallback
- `shows_passive_footer_line()` mode validation

### Status Line Content Sources
The status line can display:
1. **Status line value only**: From `/statusline` command output
2. **Active agent label only**: Current thread/agent name
3. **Both combined**: "status_value · agent_label"
4. **Neither** (this test): Empty left side, mode on right

### Related Components
- `/statusline` command handler - Populates `status_line_value`
- Agent/thread management - Provides `active_agent_label`
- Status line configuration - Controls `status_line_enabled`

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks
1. **Empty Footer**: Left side completely empty may look broken to users
2. **Loading State**: Users may not realize status line is loading
3. **Wasted Space**: 88 spaces of empty left side is inefficient

### Edge Cases
- **Status line loading**: Timeout or slow command leaves empty state
- **Status line error**: Command failure may result in None
- **Both values present**: Status line + agent label combination

### Status Line Display Matrix
| status_line_value | active_agent_label | Left Side Display | Right Side |
|-------------------|-------------------|-------------------|------------|
| Some("content") | None | "content" | Mode indicator |
| None | Some("agent") | "agent" | Mode indicator |
| Some("content") | Some("agent") | "content · agent" | Mode indicator |
| None (this test) | None | (empty) | Mode indicator |

### Improvement Suggestions
1. **Loading Indicator**: Show "Loading..." or spinner while status line loads
2. **Fallback Content**: Show context percentage when status line is empty
3. **Error Display**: Show error message if status line command fails
4. **Left Alignment**: Consider left-aligning mode indicator when left is empty
5. **User Hint**: Show hint about configuring status line when empty

### Test Coverage
- This test - Empty status line with mode on right
- `footer_status_line_disabled_context_right` - No status line, context on right
- `footer_status_line_with_active_agent_label` - Agent label in status line
- `footer_status_line_overrides_shortcuts` - Status line with content
- Together they cover status line content combinations
