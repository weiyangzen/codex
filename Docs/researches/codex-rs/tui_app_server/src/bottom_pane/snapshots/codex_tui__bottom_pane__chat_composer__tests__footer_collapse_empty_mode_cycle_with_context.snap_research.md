# Footer Collapse: Empty Mode Cycle With Context

## 1. 场景与职责 (Usage Scenario and Responsibility)

This snapshot tests the footer rendering behavior when:
- The chat composer textarea is **empty** (idle state)
- The terminal width is **60 columns** (medium width)
- Collaboration modes are enabled but **no specific mode is active**
- Context window information ("100% context left") is displayed on the right side

This test validates the footer's responsive layout at medium widths, ensuring that the shortcuts hint and context information can coexist properly.

## 2. 功能点目的 (Feature Purpose)

The purpose of this test is to verify:
- Footer correctly displays the **shortcuts hint** (`? for shortcuts`) at medium widths
- The **context window indicator** ("100% context left") is visible on the right side
- The footer maintains proper spacing and alignment at 60-column width
- No mode indicator is shown when no collaboration mode is active

## 3. 具体技术实现 (Technical Implementation)

### Test Setup
```rust
snapshot_composer_state_with_width(
    "footer_collapse_empty_mode_cycle_with_context",
    60,  // width
    true,
    |composer| {
        composer.set_collaboration_modes_enabled(true);
        composer.set_collaboration_mode_indicator(None);  // No mode active
        composer.set_context_window(Some(100), None);
    },
);
```

### Key Components
- **`single_line_footer_layout()`** in `footer.rs` - Computes the optimal footer layout based on available width
- **`can_show_left_with_context()`** - Determines if both left-side hints and right-side context can fit
- **`left_side_line()`** - Renders the left-side footer content (shortcuts hint + mode indicator)
- **`render_context_right()`** - Renders the context window percentage on the right

### Layout Logic
1. At 60 columns, the full layout with shortcuts hint and context can fit
2. No mode indicator is present (indicator is `None`)
3. Context window line shows "100% context left" on the right

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files
- `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs` (lines 4779-4786)
- `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - `single_line_footer_layout()` (lines 310-472)
  - `left_side_line()` (lines 271-300)
  - `can_show_left_with_context()` (lines 518-527)
  - `render_context_right()` (lines 529-554)

### Footer Collapse Logic Flow
```
ChatComposer::footer_props() -> FooterProps
  -> single_line_footer_layout(area, context_width, collaboration_mode_indicator, ...)
    -> can_show_left_with_context(area, left_width, context_width)
    -> left_side_line(collaboration_mode_indicator, state)
  -> render_context_right(area, buf, line)
```

### Snapshot Output
```
"  ? for shortcuts                        100% context left  "
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Dependencies
- `ratatui` - Terminal UI rendering library
- `crossterm` - Terminal backend for key events
- `insta` - Snapshot testing framework

### Related State
- `FooterMode::ComposerEmpty` - Base mode when textarea is empty
- `context_window_percent: Option<i64>` - Context window percentage (100%)
- `collaboration_mode_indicator: Option<CollaborationModeIndicator>` - None in this case

### Width Constants
- `FOOTER_INDENT_COLS = 2` - Left indentation for footer content
- `FOOTER_CONTEXT_GAP_COLS = 1` - Minimum gap between left and right content

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvements)

### Edge Cases
1. **Width boundary**: At exactly 60 columns, the layout should still show both sides
2. **Context percentage changes**: If context drops below certain thresholds, display format may change
3. **Empty vs non-empty textarea**: This test covers empty; behavior differs when text is present

### Potential Risks
1. **Truncation**: If the terminal width decreases slightly, the right-side context may be hidden
2. **Localization**: "100% context left" is hardcoded in English
3. **Color/styling**: The dim styling on context text may not be visible in all terminal themes

### Improvement Suggestions
1. **Add boundary tests**: Test at 59 and 61 columns to verify exact boundary behavior
2. **Test context thresholds**: Verify behavior when context is at 0%, 50%, and 100%
3. **Accessibility**: Consider adding high-contrast mode for better visibility
4. **Documentation**: Add inline comments explaining the width calculations in `single_line_footer_layout()`

### Related Tests
- `footer_collapse_empty_full` - Full width (120 columns) version
- `footer_collapse_empty_mode_cycle_without_context` - Narrower width (44 columns) where context is hidden
- `footer_collapse_empty_mode_only` - Very narrow (26 columns) showing minimal content
