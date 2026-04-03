# Footer Collapse Test: Empty Mode Only

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer rendering behavior in the `tui_app_server` crate's ChatComposer component when:
- The composer textarea is **empty** (idle state)
- The terminal width is **26 columns** (very narrow)
- **Only the context indicator** can be displayed
- Even the shortcuts hint is dropped due to extreme space constraints

This test ensures the footer gracefully degrades to show only essential status information at very narrow terminal widths.

## 2. 功能点目的 (Feature Purpose)

The test verifies the **final fallback behavior** of the footer collapse system. At 26 columns width:
- The shortcuts hint (`"? for shortcuts"`) is **hidden**
- Only the context indicator (`"100% context left"`) is displayed, right-aligned
- The composer placeholder text is truncated ("Ask Codex to do anythin")

This demonstrates the ultimate degradation path when terminal space is severely constrained.

## 3. 具体技术实现 (Technical Implementation)

### Test Setup
```rust
snapshot_composer_state_with_width(
    "footer_collapse_empty_mode_only",
    26,  // width - very narrow
    true, // enhanced_keys_supported
    |composer| {
        composer.set_collaboration_modes_enabled(true);
        composer.set_collaboration_mode_indicator(None);
        composer.set_context_window(Some(100), None);
    },
);
```

### Footer Rendering Flow
1. `single_line_footer_layout()` evaluates all possible layouts:
   - Full layout with shortcuts + context: **too wide**
   - Shortcuts only: **too wide** (18 chars + indent = 20, but algorithm drops it)
   - Mode indicator only: **fits**
2. Returns `SummaryLeft::None` because no left-side hint fits
3. Context is rendered right-aligned via `render_context_right()`

### Key Logic
```rust
// In single_line_footer_layout()
// All hint variants fail to fit, return None for left side
(SummaryLeft::None, true) // show_context = true
```

### Textarea Truncation
- The composer textarea is also affected by narrow width
- Placeholder "Ask Codex to do anything" is truncated to "Ask Codex to do anythin"

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files
- `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`
  - Lines 4795-4802: Specific test case setup

- `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - Lines 471-472: Returns `(SummaryLeft::None, true)` when nothing fits
  - Lines 529-554: `render_context_right()` - right-aligned context rendering
  - Lines 481-502: `right_aligned_x()` - calculates right-align position

### Layout Calculation
- Width: 26 columns
- Left indent: 2 columns
- Available for context: ~24 columns
- "100% context left" fits at ~17 columns
- Position: 26 - 17 - 2 = 7 (right-aligned with padding)

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Rendering Dependencies
- `ratatui::buffer::Buffer` - Screen buffer manipulation
- `ratatui::layout::Rect` - Area calculations
- `Paragraph` widget for footer rendering

### Context Formatting
- `context_window_line()` formats the context display
- Uses `.dim()` styling for subtle appearance
- Default fallback: "100% context left" when no data provided

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks and Edge Cases
1. **Usability at Narrow Widths**: At 26 columns, users lose all instructional hints
2. **Placeholder Truncation**: The truncated placeholder may confuse users
3. **Minimum Width Support**: 26 columns may be below practical usability threshold

### Boundary Conditions
- This is the **narrowest** test case for empty composer state
- Below 26 columns, even context may not fit properly
- The composer itself becomes barely usable at this width

### Improvement Suggestions
1. **Minimum Width Warning**: Consider showing a warning when terminal is too narrow
2. **Alternative Layouts**: For very narrow terminals, consider vertical stacking
3. **Priority Reevaluation**: Consider if hints should take priority over context at narrow widths
4. **Documentation**: Document minimum recommended terminal width (e.g., 80 columns)

### Related Tests
- `footer_collapse_empty_mode_cycle_with_context` - 60 columns, full display
- `footer_collapse_empty_mode_cycle_without_context` - 44 columns, no context
- `footer_collapse_empty_full` - 120 columns, maximum display

### TUI Best Practices
- Modern terminals typically have ≥80 columns
- 26-column width is edge case, mostly for testing responsive behavior
- Consider setting a minimum supported width and displaying a warning below it
