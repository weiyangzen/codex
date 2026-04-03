# Footer Collapse Test: Plan Mode Queue Message Without Context

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer rendering behavior in the `tui_app_server` crate's ChatComposer component when:
- The composer textarea has **content** ("Test")
- A **task is running** (agent is busy)
- The terminal width is **40 columns** (narrow)
- **Plan mode** collaboration mode is active
- **Queue hint** is displayed (`"tab to queue message"`)
- Context indicator is **hidden**

This test ensures the footer prioritizes queue functionality over context information at narrow widths when in Plan mode.

## 2. 功能点目的 (Feature Purpose)

The test verifies the **narrow-width queue layout** with Plan mode active. At 40 columns:
- Shows `"tab to queue message"` hint
- Shows `"Plan mode"` in magenta
- Context indicator is **hidden** to save space
- The full queue hint is preserved (not shortened)

This demonstrates the priority: queue functionality > mode indicator > context.

## 3. 具体技术实现 (Technical Implementation)

### Test Setup
```rust
snapshot_composer_state_with_width(
    "footer_collapse_plan_queue_message_without_context",
    40,  // narrow width
    true, // enhanced_keys_supported
    |composer| {
        composer.set_collaboration_modes_enabled(true);
        composer.set_collaboration_mode_indicator(Some(CollaborationModeIndicator::Plan));
        composer.set_context_window(Some(98), None);
        composer.set_task_running(true);
        composer.set_text_content("Test".to_string(), Vec::new(), Vec::new());
    },
);
```

### Footer Rendering Flow
1. Queue mode is active (task running + has draft)
2. `single_line_footer_layout()` evaluates queue states:
   - `"tab to queue message · Plan mode"` (~38 chars) + context (~16) + gap = too wide
3. Falls back to showing queue hint + mode without context
4. Preserves full `"tab to queue message"` text (not shortened to `"tab to queue"`)

### Key Logic
```rust
// Queue states tried in order:
let queue_states = [
    default_state, // "tab to queue message · Plan mode"
    LeftSideState { hint: QueueMessage, show_cycle_hint: false }, // "tab to queue message"
    LeftSideState { hint: QueueShort, show_cycle_hint: false },   // "tab to queue"
];
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files
- `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`
  - Lines 4906-4915: Specific test case setup

- `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - Lines 348-395: Queue-specific collapse logic
  - Lines 350-360: Queue state definitions
  - Lines 365-394: Two-pass layout algorithm (with context, then without)

### Queue Hint Variants
```rust
enum SummaryHintKind {
    None,
    Shortcuts,
    QueueMessage,  // "tab to queue message"
    QueueShort,    // "tab to queue"
}
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Queue State Priority
The algorithm prioritizes keeping queue hints visible:
1. First pass: Try to fit queue hint + mode + context
2. Second pass: Drop context, keep queue hint + mode
3. Final fallback: Shorten queue hint if needed

### Mode Indicator in Queue Mode
- Mode indicator is preserved even when context is dropped
- Helps users maintain awareness of agent behavior mode
- Styled consistently (magenta for Plan)

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks and Edge Cases
1. **Width Sensitivity**: At exactly 40 columns, the layout is tight
2. **Text Variations**: Slight changes to hint text could break this layout
3. **Mode Label Length**: "Plan mode" is short; other modes might not fit

### Boundary Conditions
- At 120 columns: Full display with context
- At 50 columns: Short queue hint with context
- At 40 columns: This test - full queue hint, no context
- At 30 columns: Short queue hint, no context
- At 20 columns: Mode only

### Improvement Suggestions
1. **Abbreviated Queue Hint**: Consider "Tab ↵" or similar for very narrow terminals
2. **Queue Count**: Show "3x" or similar when multiple items are queued
3. **Progress Indicator**: Show task progress instead of static queue hint
4. **Smart Width Detection**: Dynamically measure text instead of hardcoding widths

### Related Tests
- `footer_collapse_plan_queue_full` - 120 columns
- `footer_collapse_plan_queue_short_with_context` - 50 columns
- `footer_collapse_plan_queue_short_without_context` - 30 columns
- `footer_collapse_plan_queue_mode_only` - 20 columns

### Comparison with Non-Plan Queue
- Without Plan mode at 40 cols: `"tab to queue message"` (no mode)
- With Plan mode at 40 cols: `"tab to queue message · Plan mode"` (this test)
- Mode indicator takes space but provides important context

### User Experience
- Users at 40-column width are likely on small screens or split terminals
- Queue hint is critical - they need to know they can continue interacting
- Mode indicator helps set expectations about agent behavior
