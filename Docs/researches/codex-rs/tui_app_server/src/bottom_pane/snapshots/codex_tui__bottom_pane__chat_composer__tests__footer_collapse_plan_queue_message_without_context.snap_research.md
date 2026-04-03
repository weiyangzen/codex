# Footer Collapse: Plan Queue Message Without Context

## 1. 场景与职责 (Usage Scenario and Responsibility)

This snapshot tests the footer rendering behavior when:
- The chat composer textarea **has content** ("Test")
- A **task is running** (queue mode active)
- The terminal width is **40 columns** (narrow)
- **Plan mode is active**
- The **queue hint** is displayed, **context is hidden**

This test validates the footer layout at narrow widths during task execution, where context information is sacrificed to preserve the queue functionality hint.

## 2. 功能点目的 (Feature Purpose)

The purpose of this test is to verify:
- Footer displays the **full queue hint** (`tab to queue message`) at narrow width
- The **Plan mode indicator** is visible alongside the queue hint
- The **context window indicator is hidden** due to space constraints
- The layout prioritizes actionable hints over ambient information

## 3. 具体技术实现 (Technical Implementation)

### Test Setup
```rust
snapshot_composer_state_with_width(
    "footer_collapse_plan_queue_message_without_context",
    40,  // narrow width
    true,
    |composer| {
        composer.set_collaboration_modes_enabled(true);
        composer.set_collaboration_mode_indicator(Some(CollaborationModeIndicator::Plan));
        composer.set_context_window(Some(98), None);
        composer.set_task_running(true);
        composer.set_text_content("Test".to_string(), Vec::new(), Vec::new());
    },
);
```

### Key Components
- **`SummaryHintKind::QueueMessage`** - Full queue hint text
- **Queue states pass 2**: When context can't fit, drop it but keep queue hint
- **`show_context = false`** returned from layout function

### Layout Logic
1. At 40 columns, queue hint + mode + context doesn't fit
2. Queue mode priority: Keep queue hint visible at all costs
3. Pass 1: Try to fit with context - fails
4. Pass 2: Drop context, keep queue hint + mode
5. Result: `tab to queue message · Plan mode`

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files
- `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs` (lines 4906-4915)
- `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - Queue collapse logic (lines 348-395)

### Queue Collapse Logic
```rust
// Pass 2: if context cannot fit, drop it before dropping the queue hint
let mut previous_state: Option<LeftSideState> = None;
for state in queue_states {
    // ...
    if width > 0 && left_fits(area, width) {
        return (SummaryLeft::Custom(state_line(state)), false); // show_context = false
    }
}
```

### Snapshot Output
```
"  tab to queue message · Plan mode      "
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Dependencies
- `ratatui` - Terminal UI rendering

### Related State
- `FooterMode::ComposerHasDraft`
- `is_task_running: true`
- `show_queue_hint: true`
- `collaboration_mode_indicator: Some(Plan)`

### Width Analysis
- Queue message: ~21 characters
- Mode: ~10 characters
- Separator: 3 characters
- Indent: 2 characters
- Total: ~36 characters - fits in 40 columns (38 available)
- Context would need ~20 more - doesn't fit

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvements)

### Edge Cases
1. **Longer queue hint**: "tab to queue message" is the longer variant
2. **Mode name collision**: Different modes have different lengths
3. **Boundary at 40**: Very close to the limit for this content

### Potential Risks
1. **Context blindness**: Users lose track of context window usage
2. **Queue overflow**: Without context visible, users may queue too many messages
3. **Width sensitivity**: Small resize could cause layout changes

### Improvement Suggestions
1. **Compact queue hint**: Use icon or shorter text (e.g., "↵ queue")
2. **Context alert**: Flash or highlight when context is critically low
3. **Persistent minimal context**: Show just percentage number (e.g., "98%")
4. **Queue notification**: Show visual feedback when message is queued

### Related Tests
- `footer_collapse_plan_queue_full` - 120 columns with context
- `footer_collapse_plan_queue_short_with_context` - 50 columns
- `footer_collapse_plan_queue_short_without_context` - 30 columns with short hint
- `footer_collapse_plan_queue_mode_only` - 20 columns
