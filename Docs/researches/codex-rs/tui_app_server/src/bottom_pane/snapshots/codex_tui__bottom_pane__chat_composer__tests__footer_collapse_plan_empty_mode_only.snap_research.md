# Footer Collapse: Plan Empty Mode Only

## 1. 场景与职责 (Usage Scenario and Responsibility)

This snapshot tests the footer rendering behavior when:
- The chat composer textarea is **empty** (idle state)
- The terminal width is **26 columns** (very narrow)
- **Plan mode is active** but cycle hint is hidden
- Only the **mode name** is displayed without additional hints

This test validates the footer's minimum viable display with Plan mode at very narrow widths.

## 2. 功能点目的 (Feature Purpose)

The purpose of this test is to verify:
- Footer displays **Plan mode only** (without cycle hint) at very narrow width
- The **cycle hint is hidden** when space is severely constrained
- The **context window indicator is also hidden**
- The mode indicator remains visible to inform users of the active mode

## 3. 具体技术实现 (Technical Implementation)

### Test Setup
```rust
snapshot_composer_state_with_width(
    "footer_collapse_plan_empty_mode_only",
    26,  // very narrow width
    true,
    |composer| {
        composer.set_collaboration_modes_enabled(true);
        composer.set_collaboration_mode_indicator(Some(CollaborationModeIndicator::Plan));
        composer.set_context_window(Some(100), None);
    },
);
```

### Key Components
- **`single_line_footer_layout()`** - Final fallback to mode-only state
- **`mode_only_state`** with `show_cycle_hint: false`
- **`SummaryLeft::Custom`** with compact mode label

### Layout Logic
1. At 26 columns, even mode with cycle hint doesn't fit well
2. Final fallback: Show mode only, without cycle hint
3. Left side: `Plan mode`
4. Right side: Empty

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files
- `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs` (lines 4829-4836)
- `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - `single_line_footer_layout()` lines 416-435

### Collapse Logic
```rust
// Next fallback: mode label only
let mode_only_state = LeftSideState {
    hint: SummaryHintKind::None,
    show_cycle_hint: false,  // Hide cycle hint
};
```

### Snapshot Output
```
"  Plan mode               "
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Dependencies
- `ratatui` - Terminal UI rendering
- `ratatui::style::Stylize` - For magenta styling on Plan mode

### Related State
- `FooterMode::ComposerEmpty`
- `collaboration_mode_indicator: Some(Plan)`
- `show_cycle_hint: false` - Hidden due to narrow width

### Width Analysis
- Mode only: ~10 characters
- Indent: 2 characters
- Total: 12 characters - easily fits in 26 columns
- Cycle hint would add ~22 characters - too much for this width

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvements)

### Edge Cases
1. **Cycle hint importance**: Users may not discover the shift+tab shortcut
2. **Longer mode names**: "Pair Programming" (~17 chars) vs "Plan mode" (~10 chars)
3. **Minimum width**: Below ~15 columns, even mode name may not fit

### Potential Risks
1. **Feature discoverability**: Users won't know they can cycle modes
2. **Help documentation**: The `?` shortcut hint is also hidden
3. **User confusion**: May not understand why cycle hint appears/disappears

### Improvement Suggestions
1. **Abbreviated cycle hint**: Show `(tab)` or just `↻` symbol when space is tight
2. **Consistent minimum**: Document minimum recommended terminal width
3. **Vertical layout**: Consider stacking mode and cycle hint vertically
4. **Persistent indicator**: Always show a small mode icon regardless of width

### Related Tests
- `footer_collapse_plan_empty_full` - 120 columns with all hints
- `footer_collapse_plan_empty_mode_cycle_with_context` - 60 columns with cycle hint
- `footer_collapse_plan_empty_mode_cycle_without_context` - 44 columns with cycle hint
- `footer_collapse_empty_mode_only` - Same width but no mode active
