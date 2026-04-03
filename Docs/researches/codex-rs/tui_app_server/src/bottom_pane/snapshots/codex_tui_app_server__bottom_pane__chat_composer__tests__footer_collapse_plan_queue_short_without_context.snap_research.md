# Footer Collapse: Plan Mode + Queue Short without Context

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer collapse behavior in the tui_app_server's chat composer when:
- The composer contains draft text ("Test")
- A task is running (`set_task_running(true)`)
- Plan collaboration mode is active (`CollaborationModeIndicator::Plan`)
- The terminal width is narrow (30 columns)
- Context window information is available but cannot fit

This test ensures that when space is constrained, the footer prioritizes showing the queue hint and mode indicator over the context percentage.

## 2. 功能点目的 (Purpose of the Feature)

The footer collapse system is designed to gracefully degrade the footer content as terminal width decreases. This specific test verifies the "short without context" breakpoint where:

- The "tab to queue" hint is displayed (shortened form)
- The "Plan mode" label is displayed (without cycle hint)
- The context percentage is hidden due to space constraints

This ensures users in Plan mode with running tasks still see the most important actionable information (queue hint) even in narrow terminals, sacrificing the contextual context percentage.

## 3. 具体技术实现 (Technical Implementation)

### Test Setup
```rust
snapshot_composer_state_with_width(
    "footer_collapse_plan_queue_short_without_context",
    30,  // width: 30 columns
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
2. **Width calculation**: At 30 columns, the layout cannot fit the context indicator, so:
   - Left side: "tab to queue · Plan mode" (shortened queue hint)
   - Right side: Empty (context dropped)
3. **Fallback progression**: The system tries multiple queue hint variants:
   - "tab to queue message" (full) - too long
   - "tab to queue" (short) - fits

### Key Rendering Components
- `SummaryHintKind::QueueShort` - Shortened queue hint variant
- `left_side_line()`: Constructs the left-side footer content
- `left_fits()`: Checks if content fits without considering context

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`
  - Test function: `footer_collapse_plan_queue_short_without_context` (line ~4917)
  - Setup helper: `setup_collab_footer()` (line ~4765)
  - Test harness: `snapshot_composer_state_with_width()` (line ~4672)

- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - Core logic: `single_line_footer_layout()` (line ~310)
  - Queue state variants: `queue_states` array (lines ~350-360)
  - Left content builder: `left_side_line()` (line ~271)
  - Width check: `left_fits()` (line ~252)

### Related Types
- `CollaborationModeIndicator::Plan` - Indicates Plan collaboration mode
- `SummaryHintKind::QueueShort` - Shortened queue hint variant
- `LeftSideState` - Tracks hint kind and cycle hint visibility

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Internal Dependencies
- `ratatui` - Terminal UI rendering framework
- `crossterm` - Terminal event handling (for key hints)
- `insta` - Snapshot testing framework

### State Dependencies
- `ChatComposer` state:
  - `is_task_running: true` - Triggers queue hint display
  - `collaboration_mode_indicator: Some(Plan)` - Shows Plan mode
  - `context_window_percent: Some(98)` - Available but hidden due to width
  - Text content: "Test" - Puts composer in `ComposerHasDraft` mode

### Collapse Priority
When width is constrained, the system follows this priority:
1. Keep queue hint (most actionable)
2. Keep mode indicator (contextual)
3. Drop context percentage (least critical)

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks
1. **Information loss**: Users in narrow terminals lose visibility into context usage, which could lead to unexpected context window exhaustion
2. **Width threshold sensitivity**: The 30-column breakpoint may not account for all terminal font variations
3. **Mode name length**: Longer collaboration mode names could push the queue hint out of view

### Edge Cases
1. **Extremely narrow terminals**: Below ~25 columns, even the shortened queue hint may not fit
2. **Multi-byte characters**: If mode names contain multi-byte Unicode characters, width calculations may be off
3. **Future mode additions**: New collaboration modes with longer names could break the layout

### Improvement Suggestions
1. **Minimum viable footer**: Define a minimum width below which the footer shows only the most critical element (queue hint)
2. **Truncation with ellipsis**: Truncate mode names with "..." when space is tight instead of hiding context
3. **Alternative display modes**: Consider vertical stacking or alternating display for very narrow terminals
4. **User preference**: Allow users to prioritize which footer elements they want to see in constrained spaces
5. **Responsive breakpoints**: Calculate breakpoints dynamically based on actual rendered string widths rather than hardcoded values

### Snapshot Maintenance
- The snapshot shows "tab to queue · Plan mode" without context
- Any changes to hint text, mode labels, or styling will require snapshot updates
- The 30-column width is a critical test boundary
