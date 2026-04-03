# Footer Collapse: Empty Mode Only

## 1. 场景与职责 (Usage Scenario and Responsibility)

This snapshot tests the footer rendering behavior when:
- The chat composer textarea is **empty** (idle state)
- The terminal width is **26 columns** (very narrow)
- Collaboration modes are enabled but **no specific mode is active**
- Only the **context window indicator** can be displayed

This test validates the footer's minimum viable display at very narrow widths, showing only the most essential ambient information.

## 2. 功能点目的 (Feature Purpose)

The purpose of this test is to verify:
- Footer gracefully degrades to show **only context** at very narrow widths
- The **shortcuts hint is hidden** when space is severely constrained
- The context window indicator ("100% context left") remains visible on the right
- The footer maintains usability even at extremely narrow terminal widths

## 3. 具体技术实现 (Technical Implementation)

### Test Setup
```rust
snapshot_composer_state_with_width(
    "footer_collapse_empty_mode_only",
    26,  // very narrow width
    true,
    |composer| {
        composer.set_collaboration_modes_enabled(true);
        composer.set_collaboration_mode_indicator(None);  // No mode active
        composer.set_context_window(Some(100), None);
    },
);
```

### Key Components
- **`single_line_footer_layout()`** - Returns `SummaryLeft::None` when hints can't fit
- **`left_fits()`** - Determines if any left content can be shown
- **Final fallback**: Show only right-side context when left content doesn't fit

### Layout Logic
1. At 26 columns, even the shortcuts hint cannot fit properly
2. The collapse logic falls back to showing only the context indicator
3. Context is right-aligned: `       100% context left`
4. The left side is empty (just indentation)

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files
- `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs` (lines 4795-4802)
- `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - `single_line_footer_layout()` (lines 310-472)
  - Final fallback at lines 471: `(SummaryLeft::None, true)`

### Footer Collapse Logic Flow
```
single_line_footer_layout(area, context_width, ...)
  -> can_show_left_with_context() // fails - not enough space
  -> Try queue states (not applicable - no task running)
  -> Try mode-only state (not applicable - no mode)
  -> Final fallback: (SummaryLeft::None, true)
     // show_context = true, but no left content
```

### Snapshot Output
```
"       100% context left  "
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Dependencies
- `ratatui` - Terminal UI rendering library
- `insta` - Snapshot testing framework

### Related State
- `FooterMode::ComposerEmpty` - Base mode when textarea is empty
- `context_window_percent: Some(100)` - Full context available
- `collaboration_mode_indicator: None` - No active mode

### Width Analysis
- Available width: 24 columns (26 - 2 indent)
- Context line: ~17 characters
- Right padding: 2 columns
- Total: ~19 columns - fits within 24

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvements)

### Edge Cases
1. **Minimum terminal width**: Below ~20 columns, even context may not fit
2. **Longer context strings**: "100% context left" is shorter than token counts
3. **No hints visible**: Users lose discoverability of shortcuts at this width

### Potential Risks
1. **User confusion**: No visible hints may make UI feel unresponsive
2. **Discoverability loss**: New users won't learn about `?` for shortcuts
3. **Accessibility**: Very narrow terminals may be used with screen readers

### Improvement Suggestions
1. **Absolute minimum**: Define and enforce a minimum supported terminal width
2. **Alternative hints**: Show a minimal indicator (e.g., just `?`) when possible
3. **Resize notification**: Warn users when terminal is too narrow for full experience
4. **Vertical fallback**: Consider stacking hints vertically at narrow widths

### Related Tests
- `footer_collapse_empty_mode_cycle_with_context` - 60 columns
- `footer_collapse_empty_mode_cycle_without_context` - 44 columns
- `footer_collapse_plan_empty_mode_only` - Same width but with Plan mode
