# Footer Collapse Test: Plan Mode Empty Cycle Without Context

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer rendering behavior in the `tui_app_server` crate's ChatComposer component when:
- The composer textarea is **empty** (idle state)
- The terminal width is **44 columns** (narrow)
- **Plan mode** collaboration mode is active
- Context indicator is **hidden** due to space constraints
- Mode cycle hint (`"(shift+tab to cycle)"`) is still shown

This test ensures the footer prioritizes mode information over context when space is limited.

## 2. 功能点目的 (Feature Purpose)

The test verifies the **narrow-width layout** with Plan mode active. At 44 columns:
- Shows `"Plan mode (shift+tab to cycle)"` in magenta
- Context indicator (`"100% context left"`) is **hidden**
- The mode indicator with cycle hint takes priority
- Demonstrates that mode information is more important than context percentage

This shows the priority hierarchy: mode indicator > context indicator.

## 3. 具体技术实现 (Technical Implementation)

### Test Setup
```rust
snapshot_composer_state_with_width(
    "footer_collapse_plan_empty_mode_cycle_without_context",
    44,  // narrow width
    true, // enhanced_keys_supported
    |composer| {
        composer.set_collaboration_modes_enabled(true);
        composer.set_collaboration_mode_indicator(Some(CollaborationModeIndicator::Plan));
        composer.set_context_window(Some(100), None);
    },
);
```

### Footer Rendering Flow
1. `single_line_footer_layout()` with 44-column width
2. Tries mode with cycle hint + context: **too wide**
3. Falls back to mode with cycle hint only (`show_context = false`)
4. Renders: `"Plan mode (shift+tab to cycle)"` left-aligned

### Key Logic
```rust
// In single_line_footer_layout()
let cycle_state = LeftSideState {
    hint: SummaryHintKind::None,
    show_cycle_hint: true,
};
let cycle_width = state_width(cycle_state);
if cycle_width > 0 && can_show_left_with_context(area, cycle_width, context_width) {
    return (SummaryLeft::Custom(state_line(cycle_state)), true);
}
if cycle_width > 0 && left_fits(area, cycle_width) {
    return (SummaryLeft::Custom(state_line(cycle_state)), false); // no context
}
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files
- `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`
  - Lines 4821-4828: Specific test case setup

- `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - Lines 397-410: Cycle hint fallback logic
  - Lines 252-255: `left_fits()` - checks if content fits without context
  - Lines 308-315: `single_line_footer_layout()` entry point

### Width Calculations
- Available width: 44 - 2 (indent) = 42 columns
- Mode with cycle: ~32 characters
- Context: ~17 characters
- Gap: 1 character
- Total needed with context: 50 columns (too wide)
- Mode alone: 32 columns (fits)

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Mode Styling
- `CollaborationModeIndicator::styled_span()` applies magenta color to Plan mode
- Cycle hint is part of the label: `format!("Plan mode ({MODE_CYCLE_HINT})")`
- `MODE_CYCLE_HINT = "shift+tab to cycle"`

### Layout Helpers
- `left_fits(area, width)` - checks if content fits in area with indent
- `state_width()` - calculates width of a given footer state
- `state_line()` - generates the Line for a given state

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks and Edge Cases
1. **Long Mode Names**: If mode names are translated, they might not fit even at 44 columns
2. **Cycle Hint Length**: The 20-character cycle hint is a significant portion of the display
3. **Context Loss**: Users lose visibility into context usage at this width

### Boundary Conditions
- At 60 columns: Mode with cycle + context visible
- At 44 columns: This test - mode with cycle only
- At 26 columns: Mode name only, no cycle hint (`footer_collapse_plan_empty_mode_only`)

### Improvement Suggestions
1. **Abbreviated Cycle Hint**: Use "(Shift+Tab)" (11 chars vs 20) to save space
2. **Icon-Based Cycle**: Use Unicode arrow "↹" or similar instead of text
3. **Truncating Context**: Show abbreviated context (e.g., "100%") instead of hiding entirely
4. **Smart Priority**: When context is low (<20%), prioritize showing it over cycle hint

### Related Tests
- `footer_collapse_plan_empty_full` - 120 columns
- `footer_collapse_plan_empty_mode_cycle_with_context` - 60 columns
- `footer_collapse_plan_empty_mode_only` - 26 columns

### Design Considerations
- The cycle hint is instructional (tells users how to change modes)
- Context is informational (shows current state)
- The priority makes sense: teach users how to interact > show current status
- However, when context is critically low, that information becomes more important
