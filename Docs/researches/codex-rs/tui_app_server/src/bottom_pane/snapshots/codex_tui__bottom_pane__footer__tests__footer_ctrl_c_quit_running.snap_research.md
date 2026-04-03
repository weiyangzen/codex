# Research: footer_ctrl_c_quit_running Snapshot Test

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer rendering when the **Ctrl+C shortcut reminder** is displayed while a task is running. This scenario occurs when:
- The user has pressed Ctrl+C once
- A task is currently executing (`is_task_running: true`)
- The system is showing a reminder to press Ctrl+C again to interrupt

Note: The snapshot shows "ctrl + c again to quit" (same as idle), but the actual behavior differs when integrated with the full application - when a task is running, Ctrl+C typically interrupts the running task rather than quitting the application.

## 2. 功能点目的 (Purpose of the Feature)

The Ctrl+C reminder during task execution serves these purposes:
- **Task Interruption**: Allows users to stop long-running or stuck operations
- **Graceful Handling**: Gives the system time to clean up before interruption
- **User Control**: Prevents runaway tasks from consuming resources indefinitely
- **Safety**: Requires confirmation to prevent accidental interruptions

Key behaviors:
- Mode: `FooterMode::QuitShortcutReminder`
- Display: "ctrl + c again to quit" (in this test configuration)
- Context info: Suppressed during reminder
- The actual action (quit vs interrupt) depends on higher-level state management

## 3. 具体技术实现 (Technical Implementation Details)

### FooterProps Configuration
```rust
snapshot_footer(
    "footer_ctrl_c_quit_running",
    FooterProps {
        mode: FooterMode::QuitShortcutReminder,
        esc_backtrack_hint: false,
        use_shift_enter_hint: false,
        is_task_running: true,  // Task is running
        collaboration_modes_enabled: false,
        is_wsl: false,
        quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),
        context_window_percent: None,
        context_window_used_tokens: None,
        status_line_value: None,
        status_line_enabled: false,
        active_agent_label: None,
    },
);
```

### Rendering Implementation
The footer rendering is identical to the idle case:
```rust
fn quit_shortcut_reminder_line(key: KeyBinding) -> Line<'static> {
    Line::from(vec![key.into(), " again to quit".into()]).dim()
}
```

### Context Suppression
```rust
let show_context = can_show_left_and_context
    && !matches!(
        props.mode,
        FooterMode::EscHint
            | FooterMode::QuitShortcutReminder  // Always suppressed
            | FooterMode::ShortcutOverlay
    );
```

### Higher-Level Behavior
The footer is **pure rendering** - it doesn't decide the action. The actual behavior difference (quit vs interrupt) is handled by:
- `ChatWidget`: Checks `is_task_running` to decide action
- `ChatComposer`: Manages the footer mode based on state
- Event handlers: Process the second Ctrl+C press

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Source File
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/footer.rs`

### Key Functions
- `footer_snapshots()` test (line 1260-1667) - Test case around line 1333-1349
- `quit_shortcut_reminder_line()` (line 731-733)
- `footer_from_props_lines()` (line 580-631)
- `draw_footer_frame()` (line 1074-1234)

### Snapshot File Location
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/snapshots/codex_tui__bottom_pane__footer__tests__footer_ctrl_c_quit_running.snap`

### Related Snapshots
- `footer_ctrl_c_quit_idle` - Same footer text, different `is_task_running` value
- `footer_mode_ctrl_c_interrupt` (in chat_composer tests) - Shows actual interrupt behavior

### State Machine
The actual quit/interrupt decision is in `ChatWidget`:
```rust
// Pseudocode based on module documentation
if is_task_running {
    // Interrupt current task
} else {
    // Quit application (or show reminder)
}
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Internal Dependencies
- `ratatui`: Terminal UI framework
- `crossterm::event::KeyCode`: Key code definitions

### Module Dependencies
- `crate::key_hint`: Key binding formatting

### Integration Points
The footer receives state from:
- `ChatComposer`: Sets `FooterMode` and `is_task_running`
- `ChatWidget`: Manages the overall application state

### Signal Handling
Ctrl+C handling involves:
1. `crossterm` captures key event
2. `ChatWidget` or `ChatComposer` receives event
3. State machine decides: show reminder, interrupt, or quit
4. Footer re-renders with updated mode

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks
1. **UI/Logic Mismatch**: Footer shows "quit" but may trigger "interrupt" in practice
2. **Ambiguous Messaging**: Users may not understand if they're quitting or interrupting
3. **Data Loss**: Interrupting a task may lose in-progress work
4. **Stuck Tasks**: Some tasks may not respond to interruption signals

### Edge Cases
1. **Rapid Task Completion**: Task finishes between first and second Ctrl+C
2. **Nested Tasks**: Interrupting a parent task vs child task behavior
3. **Cleanup Failures**: Task cleanup may hang, requiring force quit
4. **Partial Output**: Interrupted tasks may leave partial/corrupted output
5. **Network Operations**: Network timeouts may delay interruption

### Improvement Suggestions
1. **Contextual Messaging**: Show "ctrl + c again to interrupt" when task is running
2. **Task Name Display**: Show which task will be interrupted
3. **Progress Preservation**: Option to resume interrupted tasks
4. **Force Quit**: Triple Ctrl+C for force quit when task won't interrupt
5. **Interrupt History**: Log interrupted tasks for later review
6. **Confirmation for Destructive**: Extra confirmation for destructive operations
7. **Test Coverage**:
   - Test actual interrupt behavior (integration test)
   - Test task cleanup on interrupt
   - Test rapid Ctrl+C presses
   - Test interrupt during network operations
   - Verify footer text matches actual behavior

### Documentation Note
The identical snapshot output for idle vs running suggests the footer is truly "pure rendering" as documented. The behavior difference is implemented at a higher level (`ChatWidget`), which is the intended architecture but may be confusing without documentation.
