# Footer Collapse: Plan Queue Mode Only

## 1. 场景与职责 (Usage Scenario and Responsibility)

This snapshot tests the footer rendering behavior when:
- The chat composer textarea **has content** ("Test")
- A **task is running** (queue mode active)
- The terminal width is **20 columns** (very narrow/minimal)
- **Plan mode is active**
- Only the **mode name** is displayed - queue hint is hidden

This test validates the footer's absolute minimum display during task execution at extremely narrow widths.

## 2. 功能点目的 (Feature Purpose)

The purpose of this test is to verify:
- Footer gracefully degrades to show **only Plan mode** at minimal width
- The **queue hint is hidden** when space is severely constrained
- The **context window indicator is also hidden**
- The mode indicator remains visible as the most essential information

## 3. 具体技术实现 (Technical Implementation)

### Test Setup
```rust
snapshot_composer_state_with_width(
    "footer_collapse_plan_queue_mode_only",
    20,  // very narrow/minimal width
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
- **Final fallback** in `single_line_footer_layout()`
- **`SummaryLeft::Custom`** with mode-only line
- **No queue hint, no context, no cycle hint**

### Layout Logic
1. At 20 columns, even queue hint + mode doesn't fit
2. All queue variants tried and fail to fit
3. Final fallback: Show only mode indicator
4. Result: `Plan mode` only

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files
- `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs` (lines 4926-4935)
- `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - Final fallback logic (lines 440-469)

### Final Fallback Logic
```rust
// Final fallback: if queue variants (or other earlier states) could not fit
// at all, drop every hint and try to show just the mode label.
if let Some(collaboration_mode_indicator) = collaboration_mode_indicator {
    let mode_only_state = LeftSideState {
        hint: SummaryHintKind::None,
        show_cycle_hint: false,
    };
    // ...
}
```

### Snapshot Output
```
"  Plan mode         "
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Dependencies
- `ratatui` - Terminal UI rendering

### Related State
- `FooterMode::ComposerHasDraft`
- `is_task_running: true`
- `collaboration_mode_indicator: Some(Plan)`
- `context_window_percent: Some(98)` - Not displayed

### Width Analysis
- Mode only: ~10 characters
- Indent: 2 characters
- Total: 12 characters - fits in 20 columns (18 available)
- Queue hint would add ~21 characters - far too much

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvements)

### Edge Cases
1. **Absolute minimum**: Below ~15 columns, even mode may not fit
2. **Critical information loss**: No queue hint, no context warning
3. **User unawareness**: Users may not know they can queue messages

### Potential Risks
1. **Feature inaccessibility**: Users won't discover queue functionality
2. **Context overflow**: No warning before context limit reached
3. **Terminal compatibility**: Some terminals may have minimum width requirements

### Improvement Suggestions
1. **Minimum width warning**: Display warning when terminal is below 40 columns
2. **Abbreviated queue**: Show just "Q" or "↵" symbol when possible
3. **Vertical fallback**: Stack mode and queue hint on separate lines
4. **Persistent notification**: Show queue capability in status bar elsewhere

### Related Tests
- `footer_collapse_plan_queue_full` - 120 columns with all hints
- `footer_collapse_plan_queue_short_with_context` - 50 columns
- `footer_collapse_plan_queue_message_without_context` - 40 columns
- `footer_collapse_plan_queue_short_without_context` - 30 columns
- `footer_collapse_queue_mode_only` - Same width but without Plan mode
