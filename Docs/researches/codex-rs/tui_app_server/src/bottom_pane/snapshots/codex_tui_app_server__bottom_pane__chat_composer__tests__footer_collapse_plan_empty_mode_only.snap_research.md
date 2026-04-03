# Footer Collapse Test: Plan Mode Empty Mode Only

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer rendering behavior in the `tui_app_server` crate's ChatComposer component when:
- The composer textarea is **empty** (idle state)
- The terminal width is **26 columns** (very narrow)
- **Plan mode** collaboration mode is active
- Only the mode name (`"Plan mode"`) is displayed
- Cycle hint and context are both **hidden**

This test ensures the footer gracefully degrades to show only the essential mode information at extremely narrow widths.

## 2. 功能点目的 (Feature Purpose)

The test verifies the **minimum viable footer display** with Plan mode active. At 26 columns:
- Shows only `"Plan mode"` in magenta
- Cycle hint (`"(shift+tab to cycle)"`) is **removed**
- Context indicator is **hidden**
- Composer placeholder is truncated

This demonstrates the most compact footer state while still indicating the active collaboration mode.

## 3. 具体技术实现 (Technical Implementation)

### Test Setup
```rust
snapshot_composer_state_with_width(
    "footer_collapse_plan_empty_mode_only",
    26,  // very narrow width
    true, // enhanced_keys_supported
    |composer| {
        composer.set_collaboration_modes_enabled(true);
        composer.set_collaboration_mode_indicator(Some(CollaborationModeIndicator::Plan));
        composer.set_context_window(Some(100), None);
    },
);
```

### Footer Rendering Flow
1. `single_line_footer_layout()` with 26-column width
2. Tries mode with cycle hint: **too wide** (~32 chars)
3. Falls back to mode-only state:
   ```rust
   let mode_only_state = LeftSideState {
       hint: SummaryHintKind::None,
       show_cycle_hint: false,
   };
   ```
4. Mode-only width (~10 chars) fits, but context still doesn't fit
5. Returns mode-only line without context

### Key Logic
```rust
// Final fallback in single_line_footer_layout()
let mode_only_state = LeftSideState {
    hint: SummaryHintKind::None,
    show_cycle_hint: false,
};
let mode_only_width = left_side_line(Some(collaboration_mode_indicator), mode_only_state).width();
if left_fits(area, mode_only_width) {
    return (SummaryLeft::Custom(...), false); // no context
}
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files
- `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`
  - Lines 4829-4836: Specific test case setup

- `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - Lines 416-436: Mode-only fallback logic
  - Lines 440-469: Final fallback when earlier options don't fit
  - Lines 108-114: `label()` method without cycle hint

### Mode Label Generation
```rust
fn label(self, show_cycle_hint: bool) -> String {
    let suffix = if show_cycle_hint {
        format!(" ({MODE_CYCLE_HINT})")
    } else {
        String::new()
    };
    match self {
        CollaborationModeIndicator::Plan => format!("Plan mode{suffix}"),
        // ...
    }
}
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Compact Rendering
- `left_fits()` checks: `left_width <= area.width.saturating_sub(FOOTER_INDENT_COLS)`
- At 26 columns with 2-column indent: 24 columns available
- "Plan mode" = 9 characters, easily fits

### Styling Preservation
- Even at this narrow width, the mode indicator retains its magenta styling
- Consistent color coding helps users recognize modes regardless of width

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks and Edge Cases
1. **Usability Concern**: At 26 columns, users can't see how to change modes (no cycle hint)
2. **Context Blindness**: No visibility into context usage, which could lead to errors
3. **Terminal Minimums**: Most modern terminals don't go this narrow; this is an edge case

### Boundary Conditions
- This is the **narrowest** Plan mode test case
- Below ~15 columns, even "Plan mode" might not fit
- The composer itself becomes nearly unusable at this width

### Improvement Suggestions
1. **Abbreviated Mode Labels**: Use "P" for Plan, "PP" for PairProgramming, "E" for Execute
2. **Single Character Indicators**: Use emoji or symbols (📋, 👥, ⚡) for ultra-narrow modes
3. **Vertical Layout**: For very narrow terminals, stack footer elements vertically
4. **Minimum Width Warning**: Show a warning when terminal is below usable width

### Related Tests
- `footer_collapse_plan_empty_full` - 120 columns, full display
- `footer_collapse_plan_empty_mode_cycle_with_context` - 60 columns
- `footer_collapse_plan_empty_mode_cycle_without_context` - 44 columns

### Comparison: With vs Without Mode Indicator
- Without mode (empty): Shows context only at 26 cols
- With Plan mode: Shows "Plan mode" at 26 cols
- Mode indicator replaces context as the single visible element

### Design Philosophy
- Mode indicator is considered more important than context at extreme narrow widths
- Users can still infer context from the conversation history
- Mode affects behavior, so knowing the current mode is critical
