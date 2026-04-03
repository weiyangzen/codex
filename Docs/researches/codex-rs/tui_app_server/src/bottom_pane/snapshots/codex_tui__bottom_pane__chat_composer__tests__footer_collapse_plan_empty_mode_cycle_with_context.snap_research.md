# Footer Collapse: Plan Empty Mode Cycle With Context

## 1. 场景与职责 (Usage Scenario and Responsibility)

This snapshot tests the footer rendering behavior when:
- The chat composer textarea is **empty** (idle state)
- The terminal width is **60 columns** (medium width)
- **Plan mode is active** with cycle hint visible
- The **context window indicator** is displayed on the right side

This test validates the responsive footer layout at medium widths with Plan mode active, ensuring both mode information and context are visible.

## 2. 功能点目的 (Feature Purpose)

The purpose of this test is to verify:
- Footer displays **Plan mode indicator with cycle hint** at medium width
- The **context window indicator** ("100% context left") remains visible
- The shortcuts hint is **hidden** to make room for mode + context
- The layout prioritizes mode information over generic shortcuts

## 3. 具体技术实现 (Technical Implementation)

### Test Setup
```rust
snapshot_composer_state_with_width(
    "footer_collapse_plan_empty_mode_cycle_with_context",
    60,  // medium width
    true,
    |composer| {
        composer.set_collaboration_modes_enabled(true);
        composer.set_collaboration_mode_indicator(Some(CollaborationModeIndicator::Plan));
        composer.set_context_window(Some(100), None);
    },
);
```

### Key Components
- **`single_line_footer_layout()`** - Collapse logic for medium widths
- **Collapse priority**: When mode is active, hide shortcuts hint first
- **`LeftSideState`** with `hint: SummaryHintKind::None` and `show_cycle_hint: true`

### Layout Logic
1. At 60 columns, full layout (shortcuts + mode + context) doesn't fit
2. First fallback: Drop shortcuts hint, keep mode with cycle hint
3. Mode line: `Plan mode (shift+tab to cycle)`
4. Context: `100% context left` on the right

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files
- `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs` (lines 4813-4820)
- `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - `single_line_footer_layout()` lines 396-436
  - Mode-only fallback logic (lines 416-435)

### Collapse Logic
```rust
// First fallback: drop shortcut hint but keep the cycle hint
let cycle_state = LeftSideState {
    hint: SummaryHintKind::None,
    show_cycle_hint: true,
};
```

### Snapshot Output
```
"  Plan mode (shift+tab to cycle)         100% context left  "
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Dependencies
- `ratatui` - Terminal UI rendering
- `ratatui::style::Stylize` - For styling

### Related State
- `FooterMode::ComposerEmpty`
- `collaboration_mode_indicator: Some(CollaborationModeIndicator::Plan)`
- `show_cycle_hint: true` - Idle state allows cycle hint

### Width Analysis
- Mode with cycle: ~32 characters
- Context: ~17 characters  
- Indent + gap: ~3 characters
- Total: ~52 characters - fits in 60 columns

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvements)

### Edge Cases
1. **Longer mode names**: Other modes like "Pair Programming" are longer
2. **Different context formats**: Token counts vs percentages have different widths
3. **Boundary at 60**: Just enough space; slight variations could cause issues

### Potential Risks
1. **Discoverability**: Users lose the `? for shortcuts` hint at this width
2. **Mode confusion**: Without shortcuts hint, users may not know how to access help
3. **Responsive jump**: Transition between widths may feel abrupt

### Improvement Suggestions
1. **Progressive disclosure**: Gradually shorten text rather than hiding entirely
2. **Abbreviated hints**: Show `?` alone instead of full `? for shortcuts`
3. **Minimum width enforcement**: Warn users when terminal is too narrow
4. **Consistent styling**: Ensure mode color is consistent across all widths

### Related Tests
- `footer_collapse_plan_empty_full` - 120 columns with shortcuts
- `footer_collapse_plan_empty_mode_cycle_without_context` - 44 columns
- `footer_collapse_plan_empty_mode_only` - 26 columns
