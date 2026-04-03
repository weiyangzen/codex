# Footer Collapse: Plan Queue Full

## 1. 场景与职责 (Usage Scenario and Responsibility)

This snapshot tests the footer rendering behavior when:
- The chat composer textarea **has content** ("Test")
- A **task is running** (queue mode active)
- The terminal width is **120 columns** (full/wide width)
- **Plan mode is active** with cycle hint
- The **queue hint** is displayed instead of shortcuts hint

This test validates the full footer layout during active task execution with Plan mode and queued message capability.

## 2. 功能点目的 (Feature Purpose)

The purpose of this test is to verify:
- Footer displays the **queue hint** (`tab to queue message`) when task is running
- The **Plan mode indicator** is visible with the mode name
- The **context window indicator** shows reduced context ("98% context left")
- The layout correctly prioritizes queue functionality over shortcuts

## 3. 具体技术实现 (Technical Implementation)

### Test Setup
```rust
snapshot_composer_state_with_width(
    "footer_collapse_plan_queue_full",
    120,  // full width
    true,
    |composer| {
        composer.set_collaboration_modes_enabled(true);
        composer.set_collaboration_mode_indicator(Some(CollaborationModeIndicator::Plan));
        composer.set_context_window(Some(98), None);  // 98% context left
        composer.set_task_running(true);  // Task running - queue mode
        composer.set_text_content("Test".to_string(), Vec::new(), Vec::new());
    },
);
```

### Key Components
- **`FooterMode::ComposerHasDraft`** - Mode when textarea has content
- **`show_queue_hint = true`** - Shows "tab to queue message" when task running
- **`show_cycle_hint = false`** - Cycle hint hidden when task is running
- **Queue hint takes priority** over shortcuts hint

### Layout Logic
1. At 120 columns, all content fits comfortably
2. Left side: `tab to queue message · Plan mode`
3. Right side: `98% context left`
4. Queue hint replaces shortcuts hint because task is running

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files
- `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs` (lines 4886-4895)
- `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - `single_line_footer_layout()` queue handling (lines 348-395)
  - Queue states array (lines 350-360)

### Queue Hint Logic
```rust
let hint_kind = if show_queue_hint {
    SummaryHintKind::QueueMessage  // "tab to queue message"
} else if show_shortcuts_hint {
    SummaryHintKind::Shortcuts     // "? for shortcuts"
} else {
    SummaryHintKind::None
};
```

### Snapshot Output
```
"  tab to queue message · Plan mode                                                                    98% context left  "
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Dependencies
- `ratatui` - Terminal UI rendering
- `crossterm` - For key event handling (Tab key)

### Related State
- `FooterMode::ComposerHasDraft` - Textarea has "Test"
- `is_task_running: true` - Enables queue hint
- `context_window_percent: Some(98)` - Shows context usage
- `collaboration_mode_indicator: Some(Plan)`

### Queue States (in order of preference)
1. `QueueMessage` - Full "tab to queue message"
2. `QueueShort` - Shortened "tab to queue"
3. Mode only

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvements)

### Edge Cases
1. **Queue vs shortcuts priority**: Queue hint always wins when task running
2. **Context percentage**: 98% vs 100% - slight usage shown
3. **Tab key conflict**: Tab for queue vs Tab for autocomplete

### Potential Risks
1. **User confusion**: Users may not understand difference between submit and queue
2. **Tab key discovery**: New users may not know about queuing
3. **Context anxiety**: Seeing 98% may worry users unnecessarily

### Improvement Suggestions
1. **Queue explanation**: Add tooltip or help text explaining queue behavior
2. **Visual distinction**: Different styling for queue vs normal submit
3. **Queue counter**: Show number of queued messages if multiple
4. **Context threshold**: Only show context warning when below certain percentage

### Related Tests
- `footer_collapse_plan_queue_short_with_context` - 50 columns
- `footer_collapse_plan_queue_message_without_context` - 40 columns
- `footer_collapse_plan_queue_short_without_context` - 30 columns
- `footer_collapse_plan_queue_mode_only` - 20 columns
- `footer_collapse_queue_full` - Same but without Plan mode
