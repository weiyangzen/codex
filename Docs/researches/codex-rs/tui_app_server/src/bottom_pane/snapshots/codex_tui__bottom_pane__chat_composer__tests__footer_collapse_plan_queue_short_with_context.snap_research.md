# Research: Footer Collapse - Plan Queue Short with Context

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer rendering behavior in the TUI (Terminal User Interface) chat composer when:
- The composer is in **Plan mode** with a collaboration mode indicator active
- A **task is running** (queue mode active)
- The terminal width is **narrow (50 columns)** - triggering footer collapse behavior
- **Context window information** can still be displayed alongside the queue hint

The test ensures that the footer gracefully degrades its content display when screen real estate is limited, prioritizing essential information (queue hint + mode indicator) while still showing context information when space permits.

## 2. 功能点目的 (Feature Purpose)

The footer collapse feature serves to:
1. **Responsive Layout**: Adapt footer content to available terminal width
2. **Information Hierarchy**: Prioritize critical user actions (queue message hint) over auxiliary information
3. **Context Preservation**: Show context window usage ("98% context left") when space allows
4. **Mode Visibility**: Always display the active collaboration mode ("Plan mode") to keep users aware of the current operating mode

This specific test validates the "short with context" variant where the queue hint is abbreviated to "tab to queue" (from "tab to queue message") but the context indicator remains visible.

## 3. 具体技术实现 (Technical Implementation)

### Core Algorithm
The footer collapse logic is implemented in `single_line_footer_layout()` in `footer.rs`:

```rust
pub(crate) fn single_line_footer_layout(
    area: Rect,
    context_width: u16,
    collaboration_mode_indicator: Option<CollaborationModeIndicator>,
    show_cycle_hint: bool,
    show_shortcuts_hint: bool,
    show_queue_hint: bool,
) -> (SummaryLeft, bool)
```

### Collapse Strategy for Queue Mode
When `show_queue_hint` is true, the algorithm follows this priority:
1. **Full variant**: "tab to queue message" + mode indicator + context
2. **Short variant**: "tab to queue" + mode indicator + context (this test case)
3. **Mode only**: Just the mode indicator
4. **Without context**: Drop context if left side cannot fit

### Width Calculations
- The test uses a 50-column width
- Left side shows: "tab to queue · Plan mode" (with magenta styling for Plan mode)
- Right side shows: "98% context left" (dimmed)
- The layout ensures at least `FOOTER_CONTEXT_GAP_COLS` (1 column) gap between left and right content

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files
1. **`codex-rs/tui_app_server/src/bottom_pane/footer.rs`**
   - `single_line_footer_layout()` - Main collapse logic (lines 310-472)
   - `left_side_line()` - Constructs the left-side footer content (lines 271-300)
   - `can_show_left_with_context()` - Width validation (lines 518-527)
   - `SummaryHintKind` enum - Defines hint variants: `QueueMessage`, `QueueShort` (lines 257-263)

2. **`codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`**
   - `footer_collapse_snapshots()` test function (lines 4764-4936)
   - Specific test case at lines 4896-4905:
     ```rust
     snapshot_composer_state_with_width(
         "footer_collapse_plan_queue_short_with_context",
         50,  // 50-column width triggers short variant
         true,
         |composer| {
             setup_collab_footer(composer, 98, Some(CollaborationModeIndicator::Plan));
             composer.set_task_running(true);
             composer.set_text_content("Test".to_string(), Vec::new(), Vec::new());
         },
     );
     ```

### Supporting Types
- `CollaborationModeIndicator::Plan` - Renders as magenta "Plan mode" text
- `FooterMode::ComposerHasDraft` - Triggered when textarea has content
- `SummaryLeft::Custom` - Returned when a non-default line is chosen

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Dependencies
- **ratatui**: Terminal UI framework for rendering lines and spans
- **crossterm**: Key event handling (for mode transitions)
- **insta**: Snapshot testing framework

### External State Integration
The footer reads from several external state sources:
1. **Task running state**: `is_task_running` - Controls queue hint visibility
2. **Context window**: `context_window_percent` (98% in this test) - Right-side indicator
3. **Collaboration mode**: Set via `set_collaboration_mode_indicator()`
4. **Textarea content**: "Test" - Triggers `ComposerHasDraft` mode

### Styling Dependencies
- `Stylize` trait from ratatui for color application
- Plan mode uses `.magenta()` styling
- Context indicator uses `.dim()` styling

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvements)

### Identified Risks
1. **Width Threshold Sensitivity**: The 50-column threshold is hardcoded in tests; terminal resizing near boundaries could cause flickering
2. **Translation Impact**: If "tab to queue" or "Plan mode" strings are translated, width calculations may break
3. **Context Starvation**: Very narrow terminals (< 30 cols) lose context information entirely

### Edge Cases
1. **Exact Width Boundary**: At exactly the width where context fits/doesn't fit, the display could oscillate
2. **Unicode Width**: Multi-byte characters in mode names could cause misalignment
3. **Rapid Resizing**: Quick terminal resizing could trigger redundant re-renders

### Improvement Suggestions
1. **Configurable Thresholds**: Allow users to customize what footer information is prioritized
2. **Truncation Strategy**: For very narrow terminals, consider truncating "Plan mode" to just "Plan" or "P"
3. **Animation**: Smooth transition when footer content changes due to resize
4. **Minimum Width Warning**: Display a warning when terminal is too narrow for basic functionality
5. **Caching**: Cache width calculations to avoid recomputation on every render frame

### Related Tests
- `footer_collapse_plan_queue_full` - Full width variant
- `footer_collapse_plan_queue_short_without_context` - Same width, no context
- `footer_collapse_plan_queue_mode_only` - Narrowest variant
- `footer_collapse_queue_short_with_context` - Non-plan mode variant
