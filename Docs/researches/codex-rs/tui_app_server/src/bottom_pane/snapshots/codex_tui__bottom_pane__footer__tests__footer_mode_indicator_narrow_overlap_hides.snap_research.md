# Research: footer_mode_indicator_narrow_overlap_hides Snapshot Test

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer behavior when the terminal is too narrow to display both the collaboration mode indicator and the context information on the same line. This scenario occurs when:

- The terminal width is constrained (50 characters in this test)
- The collaboration mode indicator is active (Plan mode with cycle hint)
- The footer must decide whether to show the mode indicator, context, or neither

**Responsibility**: Ensures the footer gracefully handles narrow terminal widths by prioritizing content display and avoiding visual overlap or truncation issues.

## 2. 功能点目的 (Feature Purpose)

The width-based collapse feature serves to:
- Adapt footer content to available terminal width
- Prevent text overlap between left-side hints and right-side context
- Prioritize essential information (mode indicator) over optional context
- Maintain readable footer layout across different terminal sizes

**Test Purpose**: Verify that at 50-character width, the footer shows only the collaboration mode indicator without the context percentage, avoiding overlap.

## 3. 具体技术实现 (Technical Implementation)

### Test Configuration
```rust
let props = FooterProps {
    mode: FooterMode::ComposerEmpty,
    esc_backtrack_hint: false,
    use_shift_enter_hint: false,
    is_task_running: false,
    collaboration_modes_enabled: true,  // Enables mode indicator
    is_wsl: false,
    quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),
    context_window_percent: None,
    context_window_used_tokens: None,
    status_line_value: None,
    status_line_enabled: false,
    active_agent_label: None,
};

snapshot_footer_with_mode_indicator(
    "footer_mode_indicator_narrow_overlap_hides",
    50,  // Narrow width
    &props,
    Some(CollaborationModeIndicator::Plan),
);
```

### Rendering Flow
1. `single_line_footer_layout()` is called with 50-character width
2. Layout algorithm attempts to fit: shortcuts hint + mode indicator + context
3. With only 50 chars, the context cannot fit alongside the mode indicator
4. Algorithm falls back to showing only the mode indicator without context
5. The cycle hint is also removed due to space constraints

### Key Code Path
```rust
// footer.rs:396-435
// Fallback logic when collaboration_mode_indicator is Some:
// 1. Try with cycle hint + context
// 2. Try mode only + context  
// 3. Try mode only without context (this test hits this path)
// 4. Final fallback: hide everything

let mode_only_state = LeftSideState {
    hint: SummaryHintKind::None,
    show_cycle_hint: false,  // Cycle hint removed
};
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files
- `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - Lines 308-472: `single_line_footer_layout()` function
  - Lines 396-435: Mode-only fallback logic
  - Lines 1463-1468: Test definition

### Related Functions
- `left_side_line()` - Builds the left-side footer content
- `can_show_left_with_context()` - Determines if both sides can fit
- `CollaborationModeIndicator::styled_span()` - Renders the mode indicator

### Snapshot Output
```
"  Plan mode (shift+tab to cycle)                  "
```
Note: The context percentage is NOT shown on the right side due to narrow width.

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Dependencies
- `FOOTER_INDENT_COLS` (2 spaces) - Left padding constant
- `FOOTER_CONTEXT_GAP_COLS` (1 space) - Minimum gap between left and right
- `right_aligned_x()` - Calculates right-side content position
- `can_show_left_with_context()` - Width collision detection

### Layout Algorithm
```
Available width: 50 chars
- Indent: 2 chars
- Mode indicator: ~32 chars ("Plan mode (shift+tab to cycle)")
- Gap: 1 char
- Context: ~18 chars ("100% context left")
Total needed: ~53 chars > 50 available
→ Context hidden
```

### Related Components
- `ChatComposer` - Provides the collaboration mode state
- Terminal resize events - Trigger footer re-layout

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks
1. **Information Loss**: Users on narrow terminals miss context percentage information
2. **Layout Instability**: Rapid resizing could cause footer flickering
3. **Mode Confusion**: Without context info, users may not realize context limits

### Edge Cases
- **Extremely narrow (< 20 chars)**: Even mode indicator may not fit
- **Unicode width**: Multi-byte characters could affect width calculations
- **Rapid resize**: Multiple resize events in quick succession

### Width Thresholds
| Width | Left Content | Right Content |
|-------|-------------|---------------|
| 120+  | Full hint + Mode + Cycle | Context |
| ~80   | Mode + Cycle | Context |
| 50    | Mode only | Hidden |
| < 30  | Hidden | Hidden |

### Improvement Suggestions
1. **Compact Context**: Show abbreviated context (e.g., "72%") instead of full text
2. **Truncation Indicator**: Add "…" when content is hidden due to width
3. **Minimum Width Warning**: Warn users when terminal is below recommended width
4. **Priority Configuration**: Allow users to prioritize context over mode indicator
5. **Tooltip on Hover**: If terminal supports mouse, show full info on hover

### Test Coverage
- Complementary test `footer_mode_indicator_wide` (120 chars) shows full layout
- Test `footer_mode_indicator_running_hides_hint` shows task running state
- Together these cover the width-responsive design of the footer
