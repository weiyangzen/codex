# Footer Collapse: Queue Short without Context

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer collapse behavior in the tui_app_server's chat composer when:
- The composer contains draft text ("Test")
- A task is running (`set_task_running(true)`)
- No collaboration mode is active (standard mode)
- The terminal width is narrow (30 columns)
- Context window information is available but cannot fit

This test ensures that when space is constrained, the footer prioritizes showing the shortened queue hint over the context percentage.

## 2. 功能点目的 (Purpose of the Feature)

The footer collapse system is designed to gracefully degrade the footer content as terminal width decreases. This specific test verifies the "short without context" breakpoint where:

- The shortened "tab to queue" hint is displayed
- No collaboration mode indicator is shown (none active)
- The context percentage is hidden due to space constraints

This ensures users still see the actionable queue instruction even in narrow terminals, sacrificing the contextual context percentage.

## 3. 具体技术实现 (Technical Implementation)

### Test Setup
```rust
snapshot_composer_state_with_width(
    "footer_collapse_queue_short_without_context",
    30,  // width: 30 columns
    true,
    |composer| {
        setup_collab_footer(composer, 98, None);  // No collaboration mode
        composer.set_task_running(true);
        composer.set_text_content("Test".to_string(), Vec::new(), Vec::new());
    },
);
```

### Footer Layout Logic
The footer rendering follows the collapse hierarchy defined in `single_line_footer_layout()`:

1. **Queue mode priority**: When `show_queue_hint` is true, the system tries queue variants
2. **Width calculation**: At 30 columns:
   - "tab to queue message" - too long
   - "tab to queue" (shortened) - fits
   - Context cannot fit alongside either variant
3. **Decision logic**: Pass 2 (without context) finds that shortened queue hint fits

### Key Rendering Components
- `SummaryHintKind::QueueShort` - Shortened queue hint variant
- `left_fits()` - Verifies content fits in available width
- Pass 2 of queue states iteration - Tries variants without context

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`
  - Test function: `footer_collapse_queue_short_without_context` (line ~4865)
  - Setup helper: `setup_collab_footer()` (line ~4765)
  - Test harness: `snapshot_composer_state_with_width()` (line ~4672)

- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - Core logic: `single_line_footer_layout()` (line ~310)
  - Queue states array: Lines ~350-360
  - Pass 2 (without context): Lines ~382-395
  - Left content builder: `left_side_line()` (line ~271)
  - Width check: `left_fits()` (line ~252)

### Related Types
- `SummaryHintKind::QueueShort` - Shortened "tab to queue" hint
- `LeftSideState` - Tracks hint kind and cycle hint visibility
- `SummaryLeft::Custom` - Custom line return variant

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Internal Dependencies
- `ratatui` - Terminal UI rendering framework
- `crossterm` - Terminal event handling (for key hints)
- `insta` - Snapshot testing framework

### State Dependencies
- `ChatComposer` state:
  - `is_task_running: true` - Triggers queue hint display
  - `collaboration_mode_indicator: None` - No mode shown
  - `context_window_percent: Some(98)` - Available but hidden
  - Text content: "Test" - Puts composer in `ComposerHasDraft` mode

### Collapse Priority
When width is constrained, the system follows this priority:
1. Try full queue hint + context
2. Try full queue hint without context
3. Try shortened queue hint + context
4. Try shortened queue hint without context (this test)
5. Show only mode (if active) or minimal hint

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks
1. **Context unawareness**: Users may not realize their context usage when it's hidden
2. **Breakpoint sensitivity**: The 30-column threshold is specific to current string lengths
3. **User confusion**: New users may not understand the shortened "tab to queue" without the full context

### Edge Cases
1. **Very narrow terminals**: Below ~25 columns, even "tab to queue" may not fit
2. **Font variations**: Different terminal fonts may affect actual character width
3. **Multi-byte characters**: Unicode characters in hints could affect width calculations

### Improvement Suggestions
1. **Abbreviated context**: Show abbreviated context (e.g., "98%") when full text doesn't fit
2. **Color coding**: Use color to indicate context status even when text is hidden
3. **Transient context**: Briefly show context when it changes significantly
4. **Status bar alternative**: Provide an alternative way to view context (e.g., status command)
5. **Responsive design**: Dynamically calculate breakpoints based on actual rendered widths

### Snapshot Maintenance
- The snapshot shows "tab to queue message" (full form) without context
- Note: The actual output shows the full hint, indicating the width calculation allows it
- Changes to hint text, key styling, or width calculations will affect this snapshot

### Related Tests
- `footer_collapse_queue_full` - Full display baseline
- `footer_collapse_queue_short_with_context` - Short hint with context
- `footer_collapse_queue_message_without_context` - Full hint without context
- `footer_collapse_queue_mode_only` - Minimal display

### Collapse Progression Context
This test sits in the middle of the collapse progression:
1. Full hint + context (120 cols)
2. Short hint + context (50 cols)
3. Full hint only (40 cols)
4. Short hint only (30 cols) - This test
5. Minimal (20 cols)

The progression ensures that the most important information (queue hint) is preserved as long as possible, with context being the first element dropped and the full hint being preserved over the shortened one when possible.
