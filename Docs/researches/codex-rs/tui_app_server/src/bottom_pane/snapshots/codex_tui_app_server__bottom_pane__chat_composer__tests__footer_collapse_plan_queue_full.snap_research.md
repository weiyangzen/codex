# Footer Collapse Test: Plan Mode Queue Full

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer rendering behavior in the `tui_app_server` crate's ChatComposer component when:
- The composer textarea has **content** ("Test")
- A **task is running** (agent is busy)
- The terminal width is **120 columns** (wide)
- **Plan mode** collaboration mode is active
- **Queue hint** is displayed (Tab to queue message)
- Full context indicator is shown

This test ensures the footer properly displays queue functionality when the agent is busy in Plan mode.

## 2. 功能点目的 (Feature Purpose)

The test verifies the **queue mode full display** with Plan mode active. At 120 columns:
- Shows `"tab to queue message"` hint (queue functionality)
- Shows `"Plan mode"` in magenta (collaboration mode)
- Shows `"98% context left"` context indicator
- The cycle hint is **hidden** because a task is running

This demonstrates the complete footer state when users can queue messages while a task runs.

## 3. 具体技术实现 (Technical Implementation)

### Test Setup
```rust
snapshot_composer_state_with_width(
    "footer_collapse_plan_queue_full",
    120,  // wide terminal
    true, // enhanced_keys_supported
    |composer| {
        composer.set_collaboration_modes_enabled(true);
        composer.set_collaboration_mode_indicator(Some(CollaborationModeIndicator::Plan));
        composer.set_context_window(Some(98), None);
        composer.set_task_running(true); // Task is running!
        composer.set_text_content("Test".to_string(), Vec::new(), Vec::new());
    },
);
```

### Key Differences from Empty State
1. `set_task_running(true)` - indicates agent is busy
2. `set_text_content("Test", ...)` - composer has draft content
3. This triggers `FooterMode::ComposerHasDraft` with queue hint

### Footer Rendering Flow
1. `footer_mode` becomes `ComposerHasDraft` due to non-empty textarea
2. `show_queue_hint = true` because `is_task_running = true`
3. `show_cycle_hint = false` because `is_task_running = true`
4. Renders: `"tab to queue message · Plan mode"` + `"98% context left"`

### Queue Hint Logic
```rust
SummaryHintKind::QueueMessage => {
    line.push_span(key_hint::plain(KeyCode::Tab));
    line.push_span(" to queue message".dim());
}
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files
- `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`
  - Lines 4886-4895: Specific test case setup
  - Line 376: `is_task_running` field in ChatComposer
  - Lines 1608-1610: `set_task_running()` method

- `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - Lines 195-201: Queue hint display logic in `footer_height()`
  - Lines 617-630: `ComposerHasDraft` mode handling
  - Lines 282-285: `QueueMessage` hint kind
  - Lines 348-395: Queue-specific collapse logic

### Footer Mode Transitions
```rust
enum FooterMode {
    ComposerEmpty,      // No content, no task
    ComposerHasDraft,   // Has content (shows queue hint if task running)
    // ... other modes
}
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Task Running State
- `set_task_running(true)` simulates agent processing
- Affects multiple footer behaviors:
  - Shows queue hint instead of submit hint
  - Hides cycle hint (can't change mode while running)
  - Affects Ctrl+C behavior (interrupt vs quit)

### Queue Functionality
- Users can press Tab to queue a message while task runs
- Queued messages are sent after current task completes
- Queue hint is instructional: tells users they can queue

### Context Usage
- `set_context_window(Some(98), None)` - 98% context remaining
- Shows actual context usage during task execution
- Helps users monitor resource consumption

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks and Edge Cases
1. **Queue Overflow**: If users queue many messages, there's no visual indication of queue depth
2. **Mode Confusion**: Cycle hint is hidden, but users might not know why they can't change modes
3. **Context During Task**: Context percentage may fluctuate during task execution

### Boundary Conditions
- At 120 columns: Full display (this test)
- At 50 columns: Short queue hint + context
- At 40 columns: Full queue hint, no context
- At 30 columns: Short queue hint, no context
- At 20 columns: Mode only

### Improvement Suggestions
1. **Queue Depth Indicator**: Show "3 queued" when multiple messages are queued
2. **Mode Lock Indicator**: Show 🔒 or similar when mode can't be changed
3. **Animated Queue Hint**: Subtle animation to draw attention to queue capability
4. **Context Trend**: Show ↑ or ↓ next to context percentage to indicate trend

### Related Tests
- `footer_collapse_plan_queue_short_with_context` - 50 columns
- `footer_collapse_plan_queue_message_without_context` - 40 columns
- `footer_collapse_plan_queue_short_without_context` - 30 columns
- `footer_collapse_plan_queue_mode_only` - 20 columns

### Comparison with Non-Plan Queue
- Without Plan mode: `"tab to queue message"` + context
- With Plan mode: `"tab to queue message · Plan mode"` + context (this test)
- Plan mode adds visual branding without affecting queue functionality

### User Experience Considerations
- Queue hint is critical - users need to know they can continue typing while task runs
- Plan mode styling helps users maintain context of the agent's behavior mode
- Context percentage helps users understand conversation complexity
