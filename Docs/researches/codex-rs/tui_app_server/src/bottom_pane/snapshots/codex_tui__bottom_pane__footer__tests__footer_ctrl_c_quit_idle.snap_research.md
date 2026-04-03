# Research: footer_ctrl_c_quit_idle Snapshot Test

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer rendering when the **Ctrl+C quit shortcut reminder** is displayed during idle state (no task running). This scenario occurs when:
- The user has pressed Ctrl+C once
- The system is showing a transient reminder to press Ctrl+C again to quit
- No task is currently running (`is_task_running: false`)

This is a safety mechanism to prevent accidental exits from the application.

## 2. 功能点目的 (Purpose of the Feature)

The quit shortcut reminder serves these purposes:
- **Accidental Exit Prevention**: Requires intentional double-press to quit
- **User Confirmation**: Gives users a moment to cancel if pressed by mistake
- **Consistent Pattern**: Common pattern in terminal applications (like `less`, `vim`)
- **Transient State**: Automatically disappears after timeout or second keypress

Key behaviors:
- Mode: `FooterMode::QuitShortcutReminder`
- Display: "ctrl + c again to quit"
- Context info: Suppressed during quit reminder
- Applies to both Ctrl+C and Ctrl+D (configurable via `quit_shortcut_key`)

## 3. 具体技术实现 (Technical Implementation Details)

### FooterProps Configuration
```rust
snapshot_footer(
    "footer_ctrl_c_quit_idle",
    FooterProps {
        mode: FooterMode::QuitShortcutReminder,  // Quit reminder mode
        esc_backtrack_hint: false,
        use_shift_enter_hint: false,
        is_task_running: false,  // Idle state
        collaboration_modes_enabled: false,
        is_wsl: false,
        quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),  // Ctrl+C
        context_window_percent: None,
        context_window_used_tokens: None,
        status_line_value: None,
        status_line_enabled: false,
        active_agent_label: None,
    },
);
```

### Quit Reminder Line Generation
```rust
fn quit_shortcut_reminder_line(key: KeyBinding) -> Line<'static> {
    Line::from(vec![key.into(), " again to quit".into()]).dim()
}
```

### Mode Handling in footer_from_props_lines
```rust
FooterMode::QuitShortcutReminder => {
    vec![quit_shortcut_reminder_line(props.quit_shortcut_key)]
}
```

### Context Suppression
During quit reminder, context info is NOT shown:
```rust
let show_context = can_show_left_and_context
    && !matches!(
        props.mode,
        FooterMode::EscHint
            | FooterMode::QuitShortcutReminder  // Suppressed!
            | FooterMode::ShortcutOverlay
    );
```

### State Machine Integration
The quit reminder is typically triggered by:
- First Ctrl+C press in `ChatWidget` or `ChatComposer`
- Timer starts for auto-dismissal
- Second Ctrl+C within timeout → quit application
- Any other key → cancel reminder, return to normal mode

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Source File
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/footer.rs`

### Key Functions
- `footer_snapshots()` test (line 1260-1667) - Test case around line 1315-1331
- `quit_shortcut_reminder_line()` (line 731-733)
- `footer_from_props_lines()` (line 580-631)
- `draw_footer_frame()` (line 1074-1234)

### Snapshot File Location
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/snapshots/codex_tui__bottom_pane__footer__tests__footer_ctrl_c_quit_idle.snap`

### Related Snapshots
- `footer_ctrl_c_quit_running` - Same mode but with task running (shows interrupt instead of quit)

### KeyBinding Type
```rust
pub(crate) quit_shortcut_key: KeyBinding,
// KeyBinding can represent: Ctrl+C, Ctrl+D, etc.
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Internal Dependencies
- `ratatui`: Terminal UI framework
- `crossterm::event::KeyCode`: Key code definitions

### Module Dependencies
- `crate::key_hint`: Key binding formatting (`key_hint::ctrl(KeyCode::Char('c'))`)

### State Management
The quit reminder mode is managed by:
- `ChatWidget`: Higher-level state machine
- `ChatComposer`: Determines when quit is allowed
- Timer-based auto-dismissal (scheduled redraws)

### User Interaction Flow
1. User presses Ctrl+C
2. `ChatWidget` checks if quit is allowed
3. If allowed → sets `FooterMode::QuitShortcutReminder`
4. Footer renders "ctrl + c again to quit"
5. Timer starts (e.g., 2 seconds)
6. User either:
   - Presses Ctrl+C again → quit application
   - Presses any other key → cancel reminder
   - Waits for timeout → auto-cancel

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks
1. **Timeout Too Short**: Users may not see reminder before it disappears
2. **Timeout Too Long**: Users may think app is unresponsive
3. **Inconsistent Behavior**: Different behavior in idle vs running states may confuse
4. **Accessibility**: Visual-only reminder may not be accessible to screen readers

### Edge Cases
1. **Rapid Keypress**: Two quick Ctrl+C presses may bypass reminder display
2. **Terminal Capture**: Some terminals intercept Ctrl+C before app sees it
3. **Remote Sessions**: SSH lag may affect double-press timing
4. **Running Task**: Same mode shows "interrupt" instead of "quit" (different snapshot)
5. **Status Line**: Status line is suppressed during quit reminder

### Improvement Suggestions
1. **Configurable Timeout**: Allow users to adjust reminder duration
2. **Persistent Setting**: Option to disable double-press requirement
3. **Visual Timer**: Show countdown bar for remaining time
4. **Sound Feedback**: Optional beep on first press (if terminal supports)
5. **Help Text**: Add "press any other key to cancel" hint
6. **Logging**: Log quit attempts for debugging
7. **Test Coverage**:
   - Test timeout behavior
   - Test cancellation with various keys
   - Test with different `quit_shortcut_key` values
   - Test interaction with status line
