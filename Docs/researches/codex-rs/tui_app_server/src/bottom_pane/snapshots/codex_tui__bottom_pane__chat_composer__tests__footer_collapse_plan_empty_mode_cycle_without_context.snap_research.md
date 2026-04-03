# Footer Collapse: Plan Empty Mode Cycle Without Context

## 1. 场景与职责 (Usage Scenario and Responsibility)

This snapshot tests the footer rendering behavior when:
- The chat composer textarea is **empty** (idle state)
- The terminal width is **44 columns** (narrow width)
- **Plan mode is active** with cycle hint visible
- The **context window indicator is hidden** due to space constraints

This test validates the footer layout at narrow widths where context is sacrificed to preserve the mode indicator with cycle hint.

## 2. 功能点目的 (Feature Purpose)

The purpose of this test is to verify:
- Footer displays **Plan mode indicator with cycle hint** at narrow width
- The **context window indicator is hidden** when space is constrained
- The layout prioritizes mode information over ambient context
- The footer remains functional and informative even at reduced widths

## 3. 具体技术实现 (Technical Implementation)

### Test Setup
```rust
snapshot_composer_state_with_width(
    "footer_collapse_plan_empty_mode_cycle_without_context",
    44,  // narrow width
    true,
    |composer| {
        composer.set_collaboration_modes_enabled(true);
        composer.set_collaboration_mode_indicator(Some(CollaborationModeIndicator::Plan));
        composer.set_context_window(Some(100), None);
    },
);
```

### Key Components
- **`single_line_footer_layout()`** - Returns `(SummaryLeft::Custom(...), false)`
- **`show_context = false`** - Context is hidden
- **Mode-only state with cycle hint**

### Layout Logic
1. At 44 columns, mode + context doesn't fit together
2. Collapse logic: Keep mode with cycle hint, hide context
3. Left side: `Plan mode (shift+tab to cycle)`
4. Right side: Empty (no context)

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files
- `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs` (lines 4821-4828)
- `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - `single_line_footer_layout()` lines 404-410

### Collapse Logic
```rust
if cycle_width > 0 && can_show_left_with_context(area, cycle_width, context_width) {
    return (SummaryLeft::Custom(state_line(cycle_state)), true);
}
if cycle_width > 0 && left_fits(area, cycle_width) {
    return (SummaryLeft::Custom(state_line(cycle_state)), false); // show_context = false
}
```

### Snapshot Output
```
"  Plan mode (shift+tab to cycle)            "
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Dependencies
- `ratatui` - Terminal UI rendering

### Related State
- `FooterMode::ComposerEmpty`
- `collaboration_mode_indicator: Some(Plan)`
- `show_cycle_hint: true`

### Width Analysis
- Mode with cycle: ~32 characters
- Indent: 2 characters
- Total: 34 characters - fits in 44 columns (42 available)
- Context would need additional ~20 characters - doesn't fit

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvements)

### Edge Cases
1. **Context importance**: Users lose visibility into context window usage
2. **Mode name length**: "Pair Programming mode" wouldn't fit at this width
3. **Boundary precision**: Exactly at the threshold where context is dropped

### Potential Risks
1. **Context unawareness**: Users may not realize context is being used
2. **Information asymmetry**: Different info shown at different widths
3. **Terminal resizing**: Rapid resizing could cause visual flicker

### Improvement Suggestions
1. **Compact context**: Show abbreviated context (e.g., just "100%") when space is tight
2. **Visual indicator**: Show a small dot or icon to indicate hidden context
3. **Hover tooltip**: If mouse supported, show full info on hover
4. **Status command**: Ensure `/status` command shows full context info

### Related Tests
- `footer_collapse_plan_empty_mode_cycle_with_context` - 60 columns with context
- `footer_collapse_plan_empty_mode_only` - 26 columns without cycle hint
