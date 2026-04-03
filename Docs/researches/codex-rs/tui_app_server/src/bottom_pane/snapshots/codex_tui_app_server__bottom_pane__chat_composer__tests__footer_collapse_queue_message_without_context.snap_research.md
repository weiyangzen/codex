# Footer Collapse: Queue Message without Context

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer collapse behavior in the tui_app_server's chat composer when:
- The composer contains draft text ("Test")
- A task is running (`set_task_running(true)`)
- No collaboration mode is active (standard mode)
- The terminal width is moderately narrow (40 columns)
- Context window information is available but cannot fit alongside the full queue hint

This test ensures that when space is moderately constrained, the footer prioritizes the full queue message hint over the context percentage.

## 2. 功能点目的 (Purpose of the Feature)

The footer collapse system is designed to gracefully degrade the footer content as terminal width decreases. This specific test verifies the "message without context" breakpoint where:

- The complete "tab to queue message" hint is preserved
- No collaboration mode indicator is shown (none active)
- The context percentage is hidden to accommodate the full queue hint

This ensures users see the complete actionable instruction even when the terminal is too narrow for auxiliary context information.

## 3. 具体技术实现 (Technical Implementation)

### Test Setup
```rust
snapshot_composer_state_with_width(
    "footer_collapse_queue_message_without_context",
    40,  // width: 40 columns
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

1. **Queue mode priority**: When `show_queue_hint` is true, the system tries to preserve queue hints
2. **Width calculation**: At 40 columns:
   - "tab to queue message" + context cannot fit together
   - The system prioritizes the full queue hint
   - Context is dropped from the right side
3. **Decision logic**: `can_show_left_with_context()` returns false, so `show_context` becomes false

### Key Rendering Components
- `SummaryHintKind::QueueMessage` - Full queue hint variant
- `can_show_left_with_context()` - Returns false at this width
- `left_fits()` - Verifies the queue hint alone fits

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`
  - Test function: `footer_collapse_queue_message_without_context` (line ~4855)
  - Setup helper: `setup_collab_footer()` (line ~4765)
  - Test harness: `snapshot_composer_state_with_width()` (line ~4672)

- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - Core logic: `single_line_footer_layout()` (line ~310)
  - Queue states iteration: Pass 1 (with context) and Pass 2 (without context)
  - Left content builder: `left_side_line()` (line ~271)
  - Context width check: `can_show_left_with_context()` (line ~518)

### Related Types
- `SummaryHintKind::QueueMessage` - Full "tab to queue message" hint
- `LeftSideState` - Tracks hint kind and cycle hint visibility
- `SummaryLeft::Default` / `SummaryLeft::Custom` - Return variants

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
When width is constrained, the system follows this priority for queue mode:
1. Try full queue hint + context
2. Try full queue hint without context (this test)
3. Try shortened queue hint + context
4. Try shortened queue hint without context
5. Show only mode (if active) or nothing

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks
1. **Context blindness**: Users may not realize context is being tracked if it's frequently hidden
2. **Breakpoint precision**: The 40-column threshold assumes specific string lengths
3. **Inconsistent experience**: Users with varying terminal sizes see different information

### Edge Cases
1. **Borderline widths**: At exactly the breakpoint width, layout might flicker during resize
2. **Rapid resizing**: Quick terminal resizing could cause visual glitches
3. **Different fonts**: Proportional or wide fonts could break the character-based width assumptions

### Improvement Suggestions
1. **Context indicator alternative**: When context is hidden, show a subtle indicator (e.g., colored border) that context is being tracked
2. **Hover/expand**: Allow users to hover or press a key to see hidden context information
3. **Smart truncation**: Instead of hiding context entirely, show abbreviated form (e.g., "98%" instead of "98% context left")
4. **Configurable breakpoints**: Allow users to customize which elements are prioritized
5. **Minimum width enforcement**: Set a minimum terminal width below which a warning is shown

### Snapshot Maintenance
- The snapshot shows only "tab to queue message" on the left with no right-side content
- This is an intermediate step between full display and shortened hint
- Changes to queue hint text will affect this snapshot

### Related Tests
- `footer_collapse_queue_full` - Previous step (with context)
- `footer_collapse_queue_short_with_context` - Alternative path (shortened hint with context)
- `footer_collapse_queue_short_without_context` - Next step (shortened hint without context)
