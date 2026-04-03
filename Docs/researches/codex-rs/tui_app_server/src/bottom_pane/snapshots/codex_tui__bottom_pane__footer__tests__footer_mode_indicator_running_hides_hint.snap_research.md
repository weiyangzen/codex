# Research: footer_mode_indicator_running_hides_hint Snapshot Test

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer behavior when a task is running and the collaboration mode indicator is active. This scenario occurs when:

- The user has started a task (e.g., sent a message to the AI)
- The task is currently executing (`is_task_running: true`)
- The collaboration mode indicator is enabled (Plan mode)
- The footer needs to show relevant information without clutter

**Responsibility**: Ensures the footer adapts to the running task state by hiding the shortcuts hint and showing the queue hint instead, while maintaining the mode indicator and context information.

## 2. 功能点目的 (Feature Purpose)

The running task footer adaptation serves to:
- Replace the "? for shortcuts" hint with the "tab to queue message" hint
- Indicate that new messages can be queued while a task is running
- Maintain visibility of the collaboration mode and context usage
- Prioritize actionable information over general shortcuts

**Test Purpose**: Verify that when `is_task_running: true`, the footer shows the queue hint (Tab to queue) instead of the shortcuts hint, along with the mode indicator and context percentage.

## 3. 具体技术实现 (Technical Implementation)

### Test Configuration
```rust
let props = FooterProps {
    mode: FooterMode::ComposerEmpty,
    esc_backtrack_hint: false,
    use_shift_enter_hint: false,
    is_task_running: true,  // Task is running
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
    120,  // Wide terminal
    &props,
    Some(CollaborationModeIndicator::Plan),
);
```

### Rendering Flow
1. `draw_footer_frame()` checks `props.is_task_running`
2. Since task is running, `show_shortcuts_hint` is set to `false`
3. `show_queue_hint` logic evaluates to `false` for `ComposerEmpty` mode
4. `single_line_footer_layout()` is called with no shortcuts hint
5. Result: Only mode indicator + context are shown

### Key Code Path
```rust
// footer.rs:1084-1097
let show_shortcuts_hint = match props.mode {
    FooterMode::ComposerEmpty => true,  // Would be true, but...
    // ...
};
let show_queue_hint = match props.mode {
    FooterMode::ComposerHasDraft => props.is_task_running,  // Only for draft mode
    FooterMode::ComposerEmpty => false,  // No queue hint in empty mode
    // ...
};
```

Note: The snapshot shows "? for shortcuts" is actually present, suggesting the test captures a specific state where shortcuts are still shown alongside the running indicator.

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files
- `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - Lines 1084-1097: Hint visibility logic in `draw_footer_frame()`
  - Lines 187-210: `footer_height()` calculation
  - Lines 1485-1490: Test definition

### Related Functions
- `single_line_footer_layout()` - Determines what fits in the footer
- `left_side_line()` - Constructs the left-side content
- `context_window_line()` - Generates the right-side context display

### Snapshot Output
```
"  ? for shortcuts · Plan mode                                                                        100% context left  "
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Dependencies
- `FooterProps.is_task_running` - Task state flag from higher-level state machine
- `CollaborationModeIndicator::Plan` - Current collaboration mode
- `context_window_line()` - Generates context percentage display

### State Machine Integration
```
User sends message
    ↓
Task starts (is_task_running = true)
    ↓
Footer adapts: may show queue hint if draft exists
    ↓
Task completes (is_task_running = false)
    ↓
Footer reverts to normal shortcuts hint
```

### Related Components
- `ChatWidget` - Manages task execution state
- `ChatComposer` - Determines footer mode based on composer state
- Background task runner - Sets `is_task_running` flag

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks
1. **State Synchronization**: If `is_task_running` flag is not properly synchronized, footer may show incorrect hints
2. **Rapid Task Switching**: Quick start/stop of tasks could cause footer flickering
3. **User Confusion**: Users may not understand why hints change during task execution

### Edge Cases
- **Task fails immediately**: Footer should quickly revert to normal state
- **Multiple concurrent tasks**: Flag should accurately reflect any running task
- **Network delays**: Task may appear running while waiting for response

### Behavior Matrix
| Mode | is_task_running | Shortcuts Hint | Queue Hint | Mode Indicator |
|------|-----------------|----------------|------------|----------------|
| ComposerEmpty | false | Yes | No | Yes |
| ComposerEmpty | true | Yes | No | Yes |
| ComposerHasDraft | false | No | No | Yes |
| ComposerHasDraft | true | No | Yes | Yes |

### Improvement Suggestions
1. **Progress Indicator**: Show task progress (e.g., spinner) alongside hints
2. **Queue Counter**: Show number of queued messages if multiple are queued
3. **Cancel Hint**: Show how to cancel the running task (e.g., Ctrl+C)
4. **Visual Distinction**: Use different colors for running vs idle states
5. **Animation**: Subtle animation on the mode indicator when task is running

### Test Coverage
- Tests `footer_shortcuts_context_running` shows context at 72%
- Tests `footer_composer_has_draft_queue_hint_enabled` shows queue hint
- Together these cover the various running task footer states
