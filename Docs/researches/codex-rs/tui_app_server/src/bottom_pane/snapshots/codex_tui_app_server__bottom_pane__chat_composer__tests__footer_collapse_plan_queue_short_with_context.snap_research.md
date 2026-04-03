# Footer Collapse: Plan Mode + Queue Short with Context

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer collapse behavior in the tui_app_server's chat composer when:
- The composer contains draft text ("Test")
- A task is running (`set_task_running(true)`)
- Plan collaboration mode is active (`CollaborationModeIndicator::Plan`)
- The terminal width is moderately constrained (50 columns)
- Context window information is available (98% context left)

This test ensures that when space is limited but sufficient, the footer can display both the queue hint and the Plan mode indicator alongside the context percentage on the right side.

## 2. 功能点目的 (Purpose of the Feature)

The footer collapse system is designed to gracefully degrade the footer content as terminal width decreases. This specific test verifies the "short with context" breakpoint where:

- The full "tab to queue message" hint is preserved
- The "Plan mode" label is displayed (without cycle hint)
- The context percentage ("98% context left") remains visible on the right

This ensures users in Plan mode with running tasks still see actionable queue instructions and context usage even in moderately narrow terminals.

## 3. 具体技术实现 (Technical Implementation)

### Test Setup
```rust
snapshot_composer_state_with_width(
    "footer_collapse_plan_queue_short_with_context",
    50,  // width: 50 columns
    true,
    |composer| {
        setup_collab_footer(composer, 98, Some(CollaborationModeIndicator::Plan));
        composer.set_task_running(true);
        composer.set_text_content("Test".to_string(), Vec::new(), Vec::new());
    },
);
```

### Footer Layout Logic
The footer rendering follows the collapse hierarchy defined in `single_line_footer_layout()`:

1. **Queue mode priority**: When `show_queue_hint` is true, the system prioritizes keeping queue-related hints visible
2. **Width calculation**: At 50 columns, the layout can accommodate:
   - Left side: "tab to queue · Plan mode" (with styling)
   - Right side: "98% context left"
3. **Fallback progression**: If width were narrower, the system would progressively drop:
   - First: The context indicator (right side)
   - Then: Shorten "tab to queue message" → "tab to queue"
   - Finally: Drop the queue hint entirely, showing only mode

### Key Rendering Components
- `left_side_line()`: Constructs the left-side footer content with hint + mode
- `can_show_left_with_context()`: Determines if both left content and context can fit
- `render_context_right()`: Renders the context percentage on the right side

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`
  - Test function: `footer_collapse_plan_queue_short_with_context` (line ~4897)
  - Setup helper: `setup_collab_footer()` (line ~4765)
  - Test harness: `snapshot_composer_state_with_width()` (line ~4672)

- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - Core logic: `single_line_footer_layout()` (line ~310)
  - Left content builder: `left_side_line()` (line ~271)
  - Context width check: `can_show_left_with_context()` (line ~518)
  - Right-side renderer: `render_context_right()` (line ~529)

### Related Types
- `CollaborationModeIndicator::Plan` - Indicates Plan collaboration mode
- `SummaryHintKind::QueueMessage` - Full queue hint variant
- `FooterMode::ComposerHasDraft` - Mode when composer has content

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Internal Dependencies
- `ratatui` - Terminal UI rendering framework
- `crossterm` - Terminal event handling (for key hints)
- `insta` - Snapshot testing framework

### State Dependencies
- `ChatComposer` state:
  - `is_task_running: true` - Triggers queue hint display
  - `collaboration_mode_indicator: Some(Plan)` - Shows Plan mode
  - `context_window_percent: Some(98)` - Displays context usage
  - Text content: "Test" - Puts composer in `ComposerHasDraft` mode

### External Protocol
- Context window percentage comes from app-server protocol
- Collaboration mode state is synchronized with the backend

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks
1. **Width sensitivity**: The 50-column breakpoint is hardcoded in tests; changes to font metrics or styling could break the layout
2. **Translation impact**: If "tab to queue" or "Plan mode" strings are translated, their lengths may exceed the expected bounds
3. **Color contrast**: The magenta styling for Plan mode may not be visible on all terminal color schemes

### Edge Cases
1. **Very long mode names**: If future collaboration modes have longer names, the layout may overflow
2. **Context percentage at extremes**: 0% or 100% context may display differently (different string lengths)
3. **Unicode width**: Multi-byte characters in the textarea could affect width calculations

### Improvement Suggestions
1. **Dynamic breakpoint calculation**: Instead of hardcoded widths, calculate minimum widths based on actual content
2. **Truncation strategy**: Add ellipsis truncation for mode names that exceed available space
3. **Responsive priority**: Consider allowing users to configure which footer elements have priority
4. **Test coverage**: Add tests for edge cases like 0% context, very long draft text, and different terminal color modes
5. **Accessibility**: Ensure the footer content is readable by screen readers (aria labels for mode indicators)

### Snapshot Maintenance
- If footer styling changes (colors, spacing), this snapshot will need updating
- If the queue hint text changes (e.g., "tab to queue" → "press Tab to queue"), the snapshot will fail
