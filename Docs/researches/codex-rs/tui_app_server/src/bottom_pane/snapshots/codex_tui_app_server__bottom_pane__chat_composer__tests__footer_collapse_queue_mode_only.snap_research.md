# Footer Collapse: Queue Mode Only

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer collapse behavior in the tui_app_server's chat composer when:
- The composer contains draft text ("Test")
- A task is running (`set_task_running(true)`)
- No collaboration mode is active (standard mode)
- The terminal width is very narrow (20 columns)
- Context window information is available but cannot fit

This test ensures that in extremely narrow terminals, the footer gracefully degrades to show only the essential queue hint, dropping all other elements.

## 2. 功能点目的 (Purpose of the Feature)

The footer collapse system is designed to gracefully degrade the footer content as terminal width decreases. This specific test verifies the "mode only" (minimal) breakpoint where:

- The shortened "tab to queue" hint is displayed
- No collaboration mode indicator is shown (none active, and no space anyway)
- The context percentage is hidden

This is the minimal viable footer for queue mode - users still see the critical action hint even in the narrowest usable terminals.

## 3. 具体技术实现 (Technical Implementation)

### Test Setup
```rust
snapshot_composer_state_with_width(
    "footer_collapse_queue_mode_only",
    20,  // width: 20 columns
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

1. **Queue mode priority**: When `show_queue_hint` is true, the system tries all queue variants
2. **Width calculation**: At 20 columns:
   - "tab to queue message" - too long
   - "tab to queue" - fits, selected
   - Context cannot fit alongside either variant
3. **Final fallback**: Only the shortened queue hint is displayed

### Key Rendering Components
- `SummaryHintKind::QueueShort` - Shortened "tab to queue" hint
- `left_fits()` - Verifies content fits in available width
- `left_side_line()` - Constructs the minimal footer content

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`
  - Test function: `footer_collapse_queue_mode_only` (line ~4875)
  - Setup helper: `setup_collab_footer()` (line ~4765)
  - Test harness: `snapshot_composer_state_with_width()` (line ~4672)

- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - Core logic: `single_line_footer_layout()` (line ~310)
  - Queue states array: Defines fallback progression (lines ~350-360)
  - Pass 2 (without context): Lines ~382-395
  - Left content builder: `left_side_line()` (line ~271)

### Related Types
- `SummaryHintKind::QueueShort` - Shortened queue hint variant
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

### Minimum Viable Display
At 20 columns, this is approaching the minimum usable width for the footer. The display shows:
```
"  tab to queue      "
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks
1. **Usability threshold**: 20 columns is extremely narrow; users may not be able to effectively use the composer at this width
2. **Information starvation**: Critical information (context usage) is completely invisible
3. **Resize instability**: Small resize operations could cause frequent footer content changes

### Edge Cases
1. **Below minimum width**: Below ~18 columns, even "tab to queue" may not fit
2. **Wide characters**: If the terminal uses wide characters (e.g., CJK), 20 columns may be insufficient
3. **Padding requirements**: The 2-column indentation (`FOOTER_INDENT_COLS`) reduces effective width

### Improvement Suggestions
1. **Absolute minimum**: Define and enforce a minimum terminal width (e.g., 40 columns) below which a warning overlay is shown
2. **Vertical fallback**: For extremely narrow terminals, consider stacking footer content vertically
3. **Abbreviated key hints**: Use symbols or shorter forms for key hints (e.g., "↹" instead of "tab")
4. **Priority configuration**: Allow users to choose what information is most important to them
5. **Context alert**: When context is hidden and reaches a critical threshold, show a transient warning

### Snapshot Maintenance
- This is the minimal queue mode footer display
- The snapshot shows only "tab to queue" with indentation
- Any changes to minimum hint text, indentation, or key styling will affect this snapshot

### Related Tests
- `footer_collapse_queue_full` - Full display baseline
- `footer_collapse_queue_short_with_context` - Shortened hint with context
- `footer_collapse_queue_short_without_context` - Shortened hint without context
- `footer_collapse_plan_queue_mode_only` - Plan mode variant with mode indicator

### Test Progression Summary
The queue mode collapse progression is:
1. `footer_collapse_queue_full` (120 cols) - Full hint + context
2. `footer_collapse_queue_short_with_context` (50 cols) - Short hint + context
3. `footer_collapse_queue_message_without_context` (40 cols) - Full hint, no context
4. `footer_collapse_queue_short_without_context` (30 cols) - Short hint, no context
5. `footer_collapse_queue_mode_only` (20 cols) - Minimal hint only
