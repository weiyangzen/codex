# Footer Collapse Test: Plan Mode Empty Full

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer rendering behavior in the `tui_app_server` crate's ChatComposer component when:
- The composer textarea is **empty** (idle state)
- The terminal width is **120 columns** (wide)
- **Plan mode** collaboration mode is active
- Full context indicator is displayed
- All footer elements are visible including the mode cycle hint

This test ensures the footer displays the complete information set when sufficient space is available.

## 2. 功能点目的 (Feature Purpose)

The test verifies the **full footer display** with collaboration mode active. At 120 columns width:
- Shows `"? for shortcuts"` hint
- Shows `"Plan mode (shift+tab to cycle)"` with magenta styling
- Shows `"100% context left"` context indicator
- Demonstrates the complete footer experience with all features enabled

This is the "gold standard" layout showing all available footer information.

## 3. 具体技术实现 (Technical Implementation)

### Test Setup
```rust
snapshot_composer_state_with_width(
    "footer_collapse_plan_empty_full",
    120,  // wide terminal
    true, // enhanced_keys_supported
    |composer| {
        composer.set_collaboration_modes_enabled(true);
        composer.set_collaboration_mode_indicator(Some(CollaborationModeIndicator::Plan));
        composer.set_context_window(Some(100), None);
    },
);
```

### Footer Rendering Flow
1. `single_line_footer_layout()` with 120-column width
2. `can_show_left_with_context()` returns `true` - plenty of space
3. Returns `(SummaryLeft::Default, true)` - full display with context
4. Renders:
   - Left: `"? for shortcuts · Plan mode (shift+tab to cycle)"`
   - Right: `"100% context left"`

### Mode Indicator Styling
```rust
// In CollaborationModeIndicator::styled_span()
CollaborationModeIndicator::Plan => Span::from(label).magenta(),
```

### Separator
- Uses `" · "` (middle dot with spaces) as separator between hint and mode
- Styled with `.dim()` for subtle separation

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files
- `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`
  - Lines 4805-4812: Specific test case setup

- `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - Lines 101-125: `CollaborationModeIndicator` enum and styling
  - Lines 271-300: `left_side_line()` - constructs the left-side footer line
  - Lines 117-124: `styled_span()` - applies mode-specific colors
  - Line 98: `MODE_CYCLE_HINT = "shift+tab to cycle"`

### Mode Indicator Definition
```rust
pub(crate) enum CollaborationModeIndicator {
    Plan,
    #[allow(dead_code)]
    PairProgramming,
    #[allow(dead_code)]
    Execute,
}
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Styling Dependencies
- `ratatui::style::Stylize` trait for `.magenta()`, `.dim()`, etc.
- Color coding:
  - Plan: Magenta
  - PairProgramming: Cyan
  - Execute: Dim (gray)

### Collaboration Mode System
- Enabled via `set_collaboration_modes_enabled(true)`
- Mode indicator set via `set_collaboration_mode_indicator()`
- Cycle hint shown when `show_cycle_hint = true` (idle state)

### Key Hint System
- `key_hint::plain(KeyCode::Char('?'))` - renders "?" key
- `key_hint::shift(KeyCode::Tab)` - used in cycle hint

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks and Edge Cases
1. **Mode Label Length**: "Plan mode (shift+tab to cycle)" is long; translations could break layout
2. **Color Accessibility**: Magenta text may not be visible on all terminal color schemes
3. **Disabled Modes**: PairProgramming and Execute are marked `#[allow(dead_code)]` - may be removed

### Boundary Conditions
- This is the **widest** test case (120 columns)
- All elements visible: shortcuts hint, mode with cycle hint, context
- Serves as reference for what "full" display looks like

### Improvement Suggestions
1. **Color Contrast**: Ensure mode colors have sufficient contrast on common terminal themes
2. **Abbreviated Mode Names**: Consider shorter labels for narrow terminals (e.g., "Plan" vs "Plan mode")
3. **Configurable Cycle Hint**: Allow users to disable cycle hint if desired
4. **Mode Icons**: Consider adding emoji/icons alongside text (e.g., 📋 for Plan)

### Related Tests
- `footer_collapse_plan_empty_mode_cycle_with_context` - 60 columns
- `footer_collapse_plan_empty_mode_cycle_without_context` - 44 columns
- `footer_collapse_plan_empty_mode_only` - 26 columns
- `footer_collapse_empty_full` - Same width but no mode indicator

### Future Considerations
- PairProgramming and Execute modes are currently disabled
- If enabled, they would use cyan and dim styling respectively
- Mode cycling via Shift+Tab is only shown when `!is_task_running`
