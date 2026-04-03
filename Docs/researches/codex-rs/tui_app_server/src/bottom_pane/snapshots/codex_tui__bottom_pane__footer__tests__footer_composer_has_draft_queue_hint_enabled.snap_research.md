# Research: footer_composer_has_draft_queue_hint_enabled Snapshot Test

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer rendering when:
- The composer has a draft message (user has typed content)
- A task is currently running (`is_task_running: true`)
- The **queue hint** is enabled

This scenario occurs when the user wants to queue a follow-up message while Codex is still processing a previous request. The queue hint informs users they can press Tab to queue their message.

## 2. 功能点目的 (Purpose of the Feature)

The queue hint feature serves these purposes:
- **Async Workflow**: Allows users to prepare next input while waiting for current task
- **Message Queuing**: Informs users about the Tab shortcut for queuing messages
- **Context Preservation**: Shows context window availability even during active tasks
- **Non-Blocking UX**: Users don't have to wait idle for task completion

Key behaviors:
- Queue hint only shows when `is_task_running: true` AND mode is `ComposerHasDraft`
- Hint text: "tab to queue message"
- Context info ("100% context left") still displayed on the right

## 3. 具体技术实现 (Technical Implementation Details)

### FooterProps Configuration
```rust
let props = FooterProps {
    mode: FooterMode::ComposerHasDraft,  // Has draft content
    esc_backtrack_hint: false,
    use_shift_enter_hint: false,
    is_task_running: true,  // Task is running - enables queue hint
    collaboration_modes_enabled: false,
    is_wsl: false,
    quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),
    context_window_percent: None,
    context_window_used_tokens: None,
    status_line_value: None,
    status_line_enabled: false,
    active_agent_label: None,
};
```

### Queue Hint Logic
The `show_queue_hint` flag is computed in `draw_footer_frame()`:
```rust
let show_queue_hint = match props.mode {
    FooterMode::ComposerHasDraft => props.is_task_running,  // Only when task running
    FooterMode::QuitShortcutReminder
    | FooterMode::ComposerEmpty
    | FooterMode::ShortcutOverlay
    | FooterMode::EscHint => false,
};
```

### Footer Line Construction
In `footer_from_props_lines()`:
```rust
FooterMode::ComposerHasDraft => {
    let state = LeftSideState {
        hint: if show_queue_hint {
            SummaryHintKind::QueueMessage  // "tab to queue message"
        } else if show_shortcuts_hint {
            SummaryHintKind::Shortcuts
        } else {
            SummaryHintKind::None
        },
        show_cycle_hint,
    };
    vec![left_side_line(collaboration_mode_indicator, state)]
}
```

### Collapse Logic
The `single_line_footer_layout()` function handles width-based collapse:
- First tries full "tab to queue message"
- Falls back to shorter variants if space is limited
- Prioritizes queue hint visibility over other content

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Source File
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/footer.rs`

### Key Functions
- `footer_snapshots()` test (line 1260-1667) - Contains test case around line 1423-1439
- `draw_footer_frame()` (line 1074-1234) - Computes hint flags
- `footer_from_props_lines()` (line 580-631) - Maps props to footer lines
- `single_line_footer_layout()` (line 310-472) - Width-based layout decisions
- `left_side_line()` (line 271-300) - Constructs left-side content

### Snapshot File Location
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/snapshots/codex_tui__bottom_pane__footer__tests__footer_composer_has_draft_queue_hint_enabled.snap`

### Hint Kind Enum
```rust
enum SummaryHintKind {
    None,
    Shortcuts,
    QueueMessage,  // "tab to queue message"
    QueueShort,    // "tab to queue" (fallback)
}
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Internal Dependencies
- `ratatui`: Terminal UI framework
- `crossterm::event::KeyCode`: For key binding display

### Module Dependencies
- `crate::key_hint`: Key hint formatting (`key_hint::plain(KeyCode::Tab)`)
- `crate::ui_consts::FOOTER_INDENT_COLS`: Indentation constant

### Related Components
- `ChatComposer`: Determines `FooterMode` based on composer state
- `ChatWidget`: Sets `is_task_running` based on task status

### Layout Integration
The queue hint integrates with the collapse/fallback system:
1. Full hint: "tab to queue message"
2. Short hint: "tab to queue" (when space is tight)
3. Mode only: Just collaboration mode indicator
4. Empty: Nothing fits

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks
1. **Hint Overload**: Multiple hints (queue + shortcuts + mode) may overwhelm users
2. **Discoverability**: Users may not notice the Tab shortcut without the hint
3. **False Expectations**: Queue hint implies queuing is always available (may have limits)
4. **Width Sensitivity**: Hint text changes based on terminal width, causing inconsistency

### Edge Cases
1. **No Task Running**: Queue hint is suppressed when `is_task_running: false`
2. **Empty Composer**: `ComposerEmpty` mode never shows queue hint
3. **Status Line Override**: If status line is enabled, queue hint may be hidden
4. **Very Narrow Terminal**: "tab to queue" short form or nothing may show
5. **Multiple Queued Messages**: No indication of queue depth in footer

### Improvement Suggestions
1. **Queue Depth Indicator**: Show "3 messages queued" when queue has items
2. **Persistent Hint**: Option to always show queue hint, not just during tasks
3. **Visual Distinction**: Different color for queue hint vs other hints
4. **Animation**: Subtle pulse on queue hint when draft exists and task is running
5. **Shortcut Consistency**: Consider Ctrl+Enter as alternative to Tab for queuing
6. **Test Coverage**:
   - Test queue hint with status line enabled
   - Test collapse to "tab to queue" short form
   - Test with collaboration mode indicator present
   - Test when queue is full (if there's a limit)
