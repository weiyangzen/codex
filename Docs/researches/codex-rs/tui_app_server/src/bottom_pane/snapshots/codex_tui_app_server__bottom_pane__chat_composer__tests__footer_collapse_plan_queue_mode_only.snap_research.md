# Footer Collapse Test: Plan Mode Queue Mode Only

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer rendering behavior in the `tui_app_server` crate's ChatComposer component when:
- The composer textarea has **content** ("Test")
- A **task is running** (agent is busy)
- The terminal width is **20 columns** (extremely narrow)
- **Plan mode** collaboration mode is active
- Only the **mode indicator** can be displayed
- Queue hint and context are both **hidden**

This test ensures the footer gracefully degrades to show only the essential mode information at extremely narrow widths during task execution.

## 2. 功能点目的 (Feature Purpose)

The test verifies the **minimum viable queue mode display** with Plan mode active. At 20 columns:
- Shows only `"Plan mode"` in magenta
- Queue hint (`"tab to queue message"`) is **hidden**
- Context indicator is **hidden**
- Composer content ("Test") is visible but footer is minimized

This demonstrates the most compact footer state during task execution while still indicating the active collaboration mode.

## 3. 具体技术实现 (Technical Implementation)

### Test Setup
```rust
snapshot_composer_state_with_width(
    "footer_collapse_plan_queue_mode_only",
    20,  // extremely narrow width
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
2. `single_line_footer_layout()` tries all queue states:
   - `"tab to queue message · Plan mode"`: **too wide** (~38 chars)
   - `"tab to queue message"`: **too wide** (~20 chars at 20 cols minus indent)
   - `"tab to queue"`: **too wide** (~14 chars, but algorithm drops it)
3. Falls back to mode-only display
4. Even mode-only without context is returned

### Key Logic
```rust
// After trying all queue variants without success
if let Some(collaboration_mode_indicator) = collaboration_mode_indicator {
    let mode_only_state = LeftSideState {
        hint: SummaryHintKind::None,
        show_cycle_hint: false,
    };
    let mode_only_width = left_side_line(Some(collaboration_mode_indicator), mode_only_state).width();
    if left_fits(area, mode_only_width) {
        return (SummaryLeft::Custom(...), false);
    }
}
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files
- `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`
  - Lines 4926-4935: Specific test case setup

- `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - Lines 440-469: Final fallback logic for mode-only display
  - Lines 471-472: Ultimate fallback `(SummaryLeft::None, true)` if even mode doesn't fit

### Width Calculations
- Width: 20 columns
- Indent: 2 columns
- Available: 18 columns
- "Plan mode" = 9 characters (fits)
- "tab to queue" = 12 characters + "Tab" key indicator (~4) = 16 (might fit but algorithm is conservative)

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Conservative Layout Algorithm
- The algorithm is conservative about what fits
- Prefers clean, uncluttered display over cramming information
- At 20 columns, only the most essential information (mode) is shown

### Composer State
- Despite narrow footer, composer still shows "Test" content
- User can still type and submit/queue messages
- Footer minimization doesn't affect core functionality

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks and Edge Cases
1. **Queue Discoverability**: Users can't see that queuing is available
2. **Severe Usability**: 20 columns is barely usable for any TUI application
3. **Information Loss**: Critical hints are hidden at this width

### Boundary Conditions
- This is the **narrowest** queue mode test case
- Below ~12 columns, even "Plan mode" might not fit
- The composer itself is severely constrained at this width

### Improvement Suggestions
1. **Single Character Mode**: Use "P" instead of "Plan mode" for ultra-narrow
2. **Vertical Footer**: Stack elements vertically for narrow terminals
3. **Minimum Width Enforcement**: Define and enforce a minimum supported width
4. **Warning Message**: Show a warning when terminal is below usable width

### Related Tests
- `footer_collapse_plan_queue_full` - 120 columns
- `footer_collapse_plan_queue_short_with_context` - 50 columns
- `footer_collapse_plan_queue_message_without_context` - 40 columns
- `footer_collapse_plan_queue_short_without_context` - 30 columns

### Comparison: Queue vs Empty at 20 Columns
- Empty state at 20 cols: Shows context only
- Queue state at 20 cols: Shows "Plan mode" only (this test)
- Mode indicator is prioritized over queue hint in ultra-narrow mode

### Design Philosophy
- At extreme narrow widths, maintaining mode awareness is prioritized
- Users can still queue by pressing Tab (muscle memory)
- The mode indicator helps users understand agent behavior even in constrained UI
- This is an edge case; most users will have wider terminals
