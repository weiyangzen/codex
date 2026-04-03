# Footer Collapse: Queue Full Width

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer collapse behavior in the tui_app_server's chat composer when:
- The composer contains draft text ("Test")
- A task is running (`set_task_running(true)`)
- No collaboration mode is active (standard mode)
- The terminal width is very wide (120 columns)
- Context window information is available (98% context left)

This test ensures that in spacious terminals, the footer displays the full queue hint with complete context information.

## 2. 功能点目的 (Purpose of the Feature)

The footer collapse system is designed to gracefully degrade the footer content as terminal width decreases. This specific test verifies the "full width" baseline where:

- The complete "tab to queue message" hint is displayed
- No collaboration mode indicator is shown (none active)
- The context percentage ("98% context left") is displayed on the right side

This establishes the maximum content baseline that narrower terminals will progressively reduce.

## 3. 具体技术实现 (Technical Implementation)

### Test Setup
```rust
snapshot_composer_state_with_width("footer_collapse_queue_full", 120, true, |composer| {
    setup_collab_footer(composer, 98, None);  // No collaboration mode
    composer.set_task_running(true);
    composer.set_text_content("Test".to_string(), Vec::new(), Vec::new());
});
```

### Footer Layout Logic
The footer rendering follows the collapse hierarchy defined in `single_line_footer_layout()`:

1. **Queue mode detection**: When `is_task_running` is true and composer has draft content, `show_queue_hint` is enabled
2. **Width calculation**: At 120 columns, all content fits comfortably:
   - Left side: "tab to queue message" (with Tab key styling)
   - Right side: "98% context left"
3. **No mode indicator**: Since `collaboration_mode_indicator` is `None`, only the queue hint appears on the left

### Key Rendering Components
- `SummaryHintKind::QueueMessage` - Full queue hint variant
- `can_show_left_with_context()` - Verifies both sides can fit
- `render_context_right()` - Renders context on the right side

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`
  - Test function: `footer_collapse_queue_full` (line ~4839)
  - Setup helper: `setup_collab_footer()` (line ~4765)
  - Test harness: `snapshot_composer_state_with_width()` (line ~4672)

- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - Core logic: `single_line_footer_layout()` (line ~310)
  - Queue hint rendering: `left_side_line()` with `SummaryHintKind::QueueMessage`
  - Context check: `can_show_left_with_context()` (line ~518)
  - Right-side renderer: `render_context_right()` (line ~529)

### Related Types
- `SummaryHintKind::QueueMessage` - Full "tab to queue message" hint
- `FooterMode::ComposerHasDraft` - Mode when composer has content
- `FooterProps::is_task_running` - Triggers queue hint display

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Internal Dependencies
- `ratatui` - Terminal UI rendering framework
- `crossterm` - Terminal event handling (for key hints)
- `insta` - Snapshot testing framework

### State Dependencies
- `ChatComposer` state:
  - `is_task_running: true` - Triggers queue hint display
  - `collaboration_mode_indicator: None` - No mode shown
  - `context_window_percent: Some(98)` - Displays context usage
  - Text content: "Test" - Puts composer in `ComposerHasDraft` mode

### Visual Structure
```
[Left side]                    [Right side]
"  tab to queue message"       "98% context left"
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks
1. **Baseline drift**: As the "full" baseline, changes to this snapshot indicate changes to the maximum footer content
2. **Spacing consistency**: The gap between left and right content must remain consistent across all width variants
3. **Key hint styling**: Changes to how Tab is rendered (e.g., from "tab" to "Tab" or adding brackets) affect width calculations

### Edge Cases
1. **Context at 0%**: When context is exhausted, the display might change (different string length)
2. **Token-based context**: When `context_window_used_tokens` is set instead of percentage, format changes
3. **Very long queue**: If many messages are queued, the hint might need to indicate queue depth

### Improvement Suggestions
1. **Dynamic spacing**: Adjust the gap between left and right content based on available space
2. **Alignment options**: Allow right-side content to be left-aligned near the center for better balance
3. **Additional context info**: Show both percentage and tokens when space permits
4. **Queue depth indicator**: Show number of queued messages when multiple are queued
5. **Animation**: Subtle animation on the queue hint to draw attention when a task completes

### Snapshot Maintenance
- This is the "full" baseline snapshot - changes here affect all narrower variants
- The 120-column width should accommodate any reasonable footer content
- Changes to hint text, key styling, or context format require updating this and all dependent snapshots

### Related Tests
- `footer_collapse_queue_short_with_context` - Next step in collapse progression
- `footer_collapse_queue_message_without_context` - Context dropped
- `footer_collapse_queue_short_without_context` - Shortened hint
- `footer_collapse_queue_mode_only` - Minimal display
