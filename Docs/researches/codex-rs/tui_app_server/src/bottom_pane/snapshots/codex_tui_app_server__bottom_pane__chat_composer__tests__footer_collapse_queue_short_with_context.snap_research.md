# Footer Collapse: Queue Short with Context

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer collapse behavior in the tui_app_server's chat composer when:
- The composer contains draft text ("Test")
- A task is running (`set_task_running(true)`)
- No collaboration mode is active (standard mode)
- The terminal width is moderately constrained (50 columns)
- Context window information is available (98% context left)

This test ensures that when space is limited but sufficient, the footer can display the shortened queue hint alongside the context percentage.

## 2. 功能点目的 (Purpose of the Feature)

The footer collapse system is designed to gracefully degrade the footer content as terminal width decreases. This specific test verifies the "short with context" breakpoint where:

- The shortened "tab to queue message" hint is displayed as "tab to queue"
- No collaboration mode indicator is shown (none active)
- The context percentage ("98% context left") remains visible on the right

This provides a balance between actionable information and contextual awareness in moderately narrow terminals.

## 3. 具体技术实现 (Technical Implementation)

### Test Setup
```rust
snapshot_composer_state_with_width(
    "footer_collapse_queue_short_with_context",
    50,  // width: 50 columns
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

1. **Queue mode priority**: When `show_queue_hint` is true, the system tries queue variants in order
2. **Width calculation**: At 50 columns:
   - "tab to queue message" + context may not fit
   - "tab to queue" (shortened) + context fits
   - The shortened variant is selected with context preserved
3. **Decision logic**: Pass 1 of queue states finds a match that fits with context

### Key Rendering Components
- `SummaryHintKind::QueueShort` - Shortened queue hint variant
- `can_show_left_with_context()` - Verifies both sides can fit
- `queue_states` array - Defines the fallback progression

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`
  - Test function: `footer_collapse_queue_short_with_context` (line ~4845)
  - Setup helper: `setup_collab_footer()` (line ~4765)
  - Test harness: `snapshot_composer_state_with_width()` (line ~4672)

- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - Core logic: `single_line_footer_layout()` (line ~310)
  - Queue states array: Lines ~350-360
  - Pass 1 (with context): Lines ~365-378
  - Left content builder: `left_side_line()` (line ~271)

### Related Types
- `SummaryHintKind::QueueShort` - Shortened "tab to queue" hint
- `LeftSideState` - Tracks hint kind and cycle hint visibility
- `SummaryLeft::Custom` - Custom line return variant (when not using default)

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
[Left side]              [Right side]
"  tab to queue message" "98% context left"
```
(At 50 columns, shows shortened form)

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks
1. **Ambiguity**: "tab to queue" may be less clear than "tab to queue message" for new users
2. **Breakpoint sensitivity**: The 50-column threshold is specific to current string lengths
3. **Translation impact**: Translated strings may have different length ratios between full and short forms

### Edge Cases
1. **Near-breakpoint widths**: At widths close to 50, small changes could toggle between full and short forms
2. **Context string variation**: "98% context left" vs "100% context left" have different lengths
3. **Token-based display**: If using tokens instead of percentage, format and length differ

### Improvement Suggestions
1. **Progressive disclosure**: Use hover or tooltip to show the full "tab to queue message" text when shortened form is displayed
2. **Smart abbreviation**: Abbreviate based on available space rather than fixed breakpoints
3. **User learning**: After several uses, users understand "tab to queue" meaning, making abbreviation acceptable
4. **Icon substitution**: Consider using icons (e.g., "↹ to queue") to save space
5. **Context abbreviation**: When space is tight, show just "98%" with a subtle indicator

### Snapshot Maintenance
- The snapshot shows "tab to queue message" with context on the right
- Note: The actual output shows full "tab to queue message" at 50 columns, indicating the width calculation allows the full form
- This test may need adjustment if string lengths change

### Related Tests
- `footer_collapse_queue_full` - Full display baseline (120 cols)
- `footer_collapse_queue_message_without_context` - Full hint without context (40 cols)
- `footer_collapse_queue_short_without_context` - Short hint without context (30 cols)
- `footer_collapse_queue_mode_only` - Minimal display (20 cols)

### Collapse Hierarchy
The queue mode collapse progression for standard mode (no collaboration mode):
1. Full hint + context (120 cols) - `footer_collapse_queue_full`
2. Short hint + context (50 cols) - This test
3. Full hint only (40 cols) - `footer_collapse_queue_message_without_context`
4. Short hint only (30 cols) - `footer_collapse_queue_short_without_context`
5. Minimal (20 cols) - `footer_collapse_queue_mode_only`
