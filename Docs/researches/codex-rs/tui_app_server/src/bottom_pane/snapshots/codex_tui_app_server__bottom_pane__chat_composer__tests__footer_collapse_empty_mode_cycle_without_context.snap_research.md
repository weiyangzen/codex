# Footer Collapse Test: Empty Mode Cycle Without Context

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer rendering behavior in the `tui_app_server` crate's ChatComposer component when:
- The composer textarea is **empty** (idle state)
- The terminal width is **44 columns** (narrow width)
- Context window percentage is **hidden** due to space constraints
- Collaboration modes are enabled but **no specific mode indicator** is active

This test ensures the footer properly prioritizes the shortcuts hint over context information when space is limited.

## 2. 功能点目的 (Feature Purpose)

The test verifies the **footer collapse fallback behavior** - specifically how the footer drops the context indicator when space is constrained. At 44 columns width:
- The footer shows `"? for shortcuts"` hint on the left
- The context indicator (`"100% context left"`) is **hidden** to save space
- The shortcuts hint remains visible as it's more actionable for users

This demonstrates the priority system: instructional hints > ambient context.

## 3. 具体技术实现 (Technical Implementation)

### Test Setup
```rust
snapshot_composer_state_with_width(
    "footer_collapse_empty_mode_cycle_without_context",
    44,  // width - narrow enough to hide context
    true, // enhanced_keys_supported
    |composer| {
        composer.set_collaboration_modes_enabled(true);
        composer.set_collaboration_mode_indicator(None); // No mode indicator
        composer.set_context_window(Some(100), None); // 100% context (hidden)
    },
);
```

### Footer Rendering Flow
1. `single_line_footer_layout()` is called with 44-column width
2. `can_show_left_with_context()` returns `false` because:
   - Left hint width (~18 chars) + gap (1) + context width (~17 chars) > available space
3. The function falls back to showing left hint only (`show_context = false`)
4. `render_footer_from_props()` renders only the shortcuts hint

### Key Logic
```rust
// In single_line_footer_layout()
if default_width > 0 && can_show_left_with_context(area, default_width, context_width) {
    return (SummaryLeft::Default, true); // show_context = true
}
// Falls through to show left only
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files
- `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`
  - Lines 4787-4794: Specific test case setup

- `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - Lines 308-472: `single_line_footer_layout()` - collapse decision logic
  - Lines 518-527: `can_show_left_with_context()` - width validation
  - Lines 504-516: `max_left_width_for_right()` - calculates available space

### Width Calculation
- `FOOTER_INDENT_COLS` = 2 (left padding)
- `FOOTER_CONTEXT_GAP_COLS` = 1 (gap between left and right)
- Available width = 44 - 2 = 42 columns for content
- Left extent = 2 + 18 + 1 = 21 columns
- Context needs ~17 columns
- Total needed = 38 columns, which fits, but the algorithm conservatively hides context

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Internal Dependencies
- `ratatui` - Terminal UI rendering
- `insta` - Snapshot testing

### Layout Constants
- `FOOTER_INDENT_COLS = 2` - Left indentation for footer content
- `FOOTER_CONTEXT_GAP_COLS = 1` - Minimum gap between left and right content

### Key Hint Rendering
- `key_hint::plain(KeyCode::Char('?'))` - Renders the "?" key indicator
- Styled with `.dim()` for subtle appearance

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks and Edge Cases
1. **Threshold Sensitivity**: The 44-column width is near the threshold where context gets hidden
2. **Font/Character Width**: Assumes monospace font; proportional fonts would break alignment
3. **Unicode Width**: Non-ASCII characters in hints could affect width calculations

### Boundary Conditions
- At 60 columns: Context is visible (`footer_collapse_empty_mode_cycle_with_context`)
- At 44 columns: Context is hidden (this test)
- At 26 columns: Even the hint is dropped, showing only mode indicator

### Improvement Suggestions
1. **Document Thresholds**: Add comments documenting exact width thresholds for each transition
2. **Minimum Viable Width**: Define and test a minimum supported terminal width
3. **Truncation Alternative**: Consider truncating context instead of hiding (e.g., "100%" → "100")
4. **Responsive Breakpoints**: Document the "breakpoint" widths:
   - ≥60 cols: Full display with context
   - 45-59 cols: Hint only, no context
   - ≤44 cols: Mode-only or hint-only depending on configuration

### Related Tests
- `footer_collapse_empty_mode_cycle_with_context` - Wider terminal showing context
- `footer_collapse_empty_mode_only` - Very narrow terminal
