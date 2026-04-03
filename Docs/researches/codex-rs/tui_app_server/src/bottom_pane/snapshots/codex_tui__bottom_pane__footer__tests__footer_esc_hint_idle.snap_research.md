# Research: footer_esc_hint_idle Snapshot Test

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer rendering when the **Esc hint** is displayed in idle state. This scenario occurs when:
- The user has pressed the Escape key once
- The composer is idle (no task running)
- The system is prompting the user to press Esc again to edit the previous message

This feature enables quick navigation to edit prior messages without using arrow keys or other navigation methods.

## 2. 功能点目的 (Purpose of the Feature)

The Esc hint feature serves these purposes:
- **Quick Edit Access**: Fast way to modify the most recent message
- **Backtracking**: Allows users to correct mistakes in their last input
- **Discoverability**: Teaches users about the Esc Esc shortcut
- **Non-Destructive**: Requires confirmation (second press) to prevent accidental edits

Key behaviors:
- Mode: `FooterMode::EscHint`
- Display: "esc esc to edit previous message" (when `esc_backtrack_hint: false`)
- Alternative: "esc again to edit previous message" (when `esc_backtrack_hint: true`)
- Only shown when `is_task_running: false`

## 3. 具体技术实现 (Technical Implementation Details)

### FooterProps Configuration
```rust
snapshot_footer(
    "footer_esc_hint_idle",
    FooterProps {
        mode: FooterMode::EscHint,  // Esc hint mode
        esc_backtrack_hint: false,  // Shows "esc esc" format
        use_shift_enter_hint: false,
        is_task_running: false,  // Idle state required
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

### Esc Hint Line Generation
```rust
fn esc_hint_line(esc_backtrack_hint: bool) -> Line<'static> {
    let esc = key_hint::plain(KeyCode::Esc);
    if esc_backtrack_hint {
        // User has already used Esc to backtrack once
        Line::from(vec![esc.into(), " again to edit previous message".into()]).dim()
    } else {
        // First time showing the hint
        Line::from(vec![
            esc.into(),
            " ".into(),
            esc.into(),
            " to edit previous message".into(),
        ])
        .dim()
    }
}
```

### Mode Determination
The `esc_hint_mode()` function determines when to show Esc hint:
```rust
pub(crate) fn esc_hint_mode(current: FooterMode, is_task_running: bool) -> FooterMode {
    if is_task_running {
        current  // Don't change mode if task is running
    } else {
        FooterMode::EscHint  // Show Esc hint
    }
}
```

### State Machine Integration
The Esc hint flow:
1. User presses Esc once
2. `ChatComposer` or `ChatWidget` sets `FooterMode::EscHint`
3. Footer shows "esc esc to edit previous message"
4. User either:
   - Presses Esc again → enters edit mode for previous message
   - Presses any other key → cancels hint, handles key normally
   - Waits for timeout → hint expires

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Source File
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/footer.rs`

### Key Functions
- `footer_snapshots()` test (line 1260-1667) - Test case around line 1351-1367
- `esc_hint_line()` (line 735-748)
- `esc_hint_mode()` (line 169-175)
- `footer_from_props_lines()` (line 580-631)
- `draw_footer_frame()` (line 1074-1234)

### Snapshot File Location
- `/home/sansha/Github/codex/Docs/researches/codex-rs/tui_app_server/src/bottom_pane/snapshots/codex_tui__bottom_pane__footer__tests__footer_esc_hint_idle.snap`

### Related Snapshots
- `footer_esc_hint_primed` - Shows "esc again" variant (esc_backtrack_hint: true)
- `footer_mode_esc_hint_backtrack` (in chat_composer tests) - Integration test

### Shortcut Overlay Entry
The Esc shortcut is also documented in the shortcut overlay:
```rust
ShortcutDescriptor {
    id: ShortcutId::EditPrevious,
    bindings: &[ShortcutBinding {
        key: key_hint::plain(KeyCode::Esc),
        condition: DisplayCondition::Always,
    }],
    prefix: "",
    label: "",
},
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Internal Dependencies
- `ratatui`: Terminal UI framework
- `crossterm::event::KeyCode`: Key code definitions

### Module Dependencies
- `crate::key_hint`: Key binding formatting (`key_hint::plain(KeyCode::Esc)`)

### State Management
The Esc hint state is managed by:
- `ChatComposer`: Tracks first Esc press, sets hint mode
- `ChatWidget`: Higher-level coordination
- History system: Provides previous message for editing

### User Interaction Flow
1. User presses Esc while in `ComposerEmpty` mode
2. System transitions to `FooterMode::EscHint`
3. Footer renders hint
4. Timer starts for auto-dismissal
5. User presses Esc again:
   - History is accessed
   - Previous message loaded into composer
   - Composer enters edit mode
6. Or user presses other key:
   - Hint is dismissed
   - Key is processed normally

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks
1. **Discovery**: Users may not discover the Esc Esc shortcut naturally
2. **Timing**: Hint may disappear before user reads it
3. **No Previous Message**: Behavior undefined if there's no previous message
4. **Accessibility**: Double-press may be difficult for some users
5. **Conflict**: Esc is commonly used for "cancel" - this repurposes it

### Edge Cases
1. **Empty History**: What happens when user presses Esc Esc with no history?
2. **First Message**: Editing the very first message in a session
3. **Deleted Messages**: Previous message was deleted by user
4. **Concurrent Edits**: Multiple users in collaborative mode
5. **Very Long Messages**: Loading huge messages into composer
6. **Running Task**: Hint is suppressed when task is running

### Improvement Suggestions
1. **Conditional Display**: Only show hint if there's actually a previous message
2. **Persistent Hint**: Option to always show Esc hint in footer
3. **Alternative Shortcut**: Add Ctrl+E as alternative to Esc Esc
4. **Visual Preview**: Show snippet of message that will be edited
5. **Undo Stack**: Allow multiple levels of backtracking (Esc Esc Esc...)
6. **Help Integration**: Mention in onboarding/tutorial
7. **Test Coverage**:
   - Test with empty history
   - Test with very long previous message
   - Test timeout behavior
   - Test cancellation with various keys
   - Test interaction with message queue
   - Test in collaborative/multi-user scenarios
