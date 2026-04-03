# Research: Footer Collapse - Plan Queue Short without Context

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer rendering behavior when:
- The composer is in **Plan mode** (collaboration mode indicator active)
- A **task is running** (queue mode active)
- The terminal width is **30 columns** - narrow enough to hide context
- Only the **short queue hint** can fit with the mode indicator

This tests the graceful degradation of the footer when terminal space is severely constrained, ensuring essential information (queue hint + mode) remains visible while non-critical context information is hidden.

## 2. 功能点目的 (Feature Purpose)

The "short without context" variant serves to:
1. **Minimum Viable Information**: Ensure users can still queue messages and see their mode even in very narrow terminals
2. **Space Efficiency**: Drop the context indicator ("98% context left") when it would cause overflow
3. **Consistent UX**: Maintain the same information hierarchy across all terminal sizes
4. **Mode Awareness**: Never hide the collaboration mode indicator as it affects agent behavior

This specific test validates that at 30 columns width, the footer shows "tab to queue · Plan mode" without the right-side context indicator.

## 3. 具体技术实现 (Technical Implementation)

### Collapse Algorithm Flow
The `single_line_footer_layout()` function in `footer.rs` handles this case through a two-pass approach:

```rust
// Pass 1: Try to fit with context
for state in queue_states {
    if can_show_left_with_context(area, width, context_width) {
        return (SummaryLeft::Custom(state_line(state)), true); // show_context = true
    }
}

// Pass 2: Drop context if needed
for state in queue_states {
    if left_fits(area, width) {
        return (SummaryLeft::Custom(state_line(state)), false); // show_context = false
    }
}
```

### State Selection for This Test
At 30 columns, the algorithm selects:
- `SummaryHintKind::QueueShort` - Abbreviated "tab to queue"
- `show_cycle_hint: false` - No room for cycle hint
- `show_context: false` - Context hidden due to width constraint

### Width Calculation
- Terminal width: 30 columns
- Left content: "tab to queue · Plan mode" (~26 chars + styling)
- Right content: Would be "98% context left" but is hidden
- Indent: `FOOTER_INDENT_COLS` (2 spaces)

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Implementation
**`codex-rs/tui_app_server/src/bottom_pane/footer.rs`**

1. **Queue State Definitions** (lines 350-360):
```rust
let queue_states = [
    default_state,
    LeftSideState {
        hint: SummaryHintKind::QueueMessage,
        show_cycle_hint: false,
    },
    LeftSideState {
        hint: SummaryHintKind::QueueShort,
        show_cycle_hint: false,
    },
];
```

2. **Two-Pass Layout Logic** (lines 365-395):
- Pass 1 attempts to fit with context
- Pass 2 drops context if necessary

3. **Width Validation Functions**:
- `left_fits()` (lines 252-255): Checks if left content fits alone
- `can_show_left_with_context()` (lines 518-527): Checks left + context + gap

### Test Location
**`codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`** (lines 4916-4925):

```rust
snapshot_composer_state_with_width(
    "footer_collapse_plan_queue_short_without_context",
    30,  // Narrow width forces context to be hidden
    true,
    |composer| {
        setup_collab_footer(composer, 98, Some(CollaborationModeIndicator::Plan));
        composer.set_task_running(true);
        composer.set_text_content("Test".to_string(), Vec::new(), Vec::new());
    },
);
```

### Helper Function
**`setup_collab_footer()`** (lines 4765-4773):
```rust
fn setup_collab_footer(
    composer: &mut ChatComposer,
    context_percent: i64,
    indicator: Option<CollaborationModeIndicator>,
) {
    composer.set_collaboration_modes_enabled(true);
    composer.set_collaboration_mode_indicator(indicator);
    composer.set_context_window(Some(context_percent), None);
}
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Rendering Pipeline
1. **Test Backend**: Uses ratatui's `TestBackend` for deterministic rendering
2. **Snapshot Capture**: `insta::assert_snapshot!` captures the terminal buffer
3. **Styling**: `Stylize` trait applies magenta color to "Plan mode"

### State Dependencies
| State | Value | Source |
|-------|-------|--------|
| `is_task_running` | `true` | `composer.set_task_running(true)` |
| `collaboration_mode_indicator` | `Some(Plan)` | `setup_collab_footer()` |
| `context_window_percent` | `98` | `setup_collab_footer()` |
| `textarea_content` | "Test" | `set_text_content()` |

### External Constants
- `FOOTER_INDENT_COLS = 2` - Left padding for footer content
- `FOOTER_CONTEXT_GAP_COLS = 1` - Minimum gap between left and right content

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvements)

### Risk Analysis

#### 1. Width Boundary Sensitivity
- **Risk**: At exactly 30-32 columns, small variations in string width could cause inconsistent behavior
- **Mitigation**: The test uses a clear 30-column boundary well below the threshold

#### 2. String Length Changes
- **Risk**: If "tab to queue" or "Plan mode" strings change length, the 30-column test may no longer trigger the expected behavior
- **Current**: "tab to queue" = 12 chars, "Plan mode" = 9 chars, separator = 3 chars = ~24 chars + 2 indent = 26 total

#### 3. Unicode Character Width
- **Risk**: If mode names contain multi-width Unicode characters, alignment could break
- **Example**: "Plan mode" with emoji could exceed expected width

### Edge Cases

1. **Terminal Resize During Input**: User resizing terminal while typing could cause footer flicker
2. **Rapid Mode Changes**: Switching between Plan/Execute modes during narrow width could cause rendering artifacts
3. **Context Window Updates**: Context percentage changing (e.g., 98% → 2%) doesn't affect width but changes visual urgency

### Improvement Suggestions

#### 1. Dynamic Truncation
```rust
// Instead of hiding context entirely, truncate it
let context_text = if width < 35 {
    "98%".to_string()  // Ultra-compact
} else {
    "98% context left".to_string()
};
```

#### 2. Priority-Based Hiding
```rust
// Define clear priority order for what gets hidden first
const HIDING_PRIORITY: &[FooterElement] = &[
    FooterElement::CycleHint,
    FooterElement::ContextIndicator,
    FooterElement::ModeLabel,  // Never hide this
    FooterElement::QueueHint,  // Never hide this
];
```

#### 3. Animation for Context Disappearance
- Smooth fade-out when context is hidden due to resize
- Prevents jarring content jumps

#### 4. Configurable Minimum Width
- Allow users to set a minimum terminal width warning
- Below this width, show a compact "!" indicator that expands on hover/focus

#### 5. Test Coverage Expansion
- Add tests for exact boundary widths (32, 33, 34 columns)
- Add tests with different mode indicators (Execute, PairProgramming)
- Add tests with translated strings

### Related Snapshots
| Snapshot | Width | Context | Mode | Description |
|----------|-------|---------|------|-------------|
| `footer_collapse_plan_queue_full` | 120 | Yes | Yes | Full display |
| `footer_collapse_plan_queue_short_with_context` | 50 | Yes | Yes | Short hint, context visible |
| `footer_collapse_plan_queue_short_without_context` | 30 | No | Yes | This test - minimal display |
| `footer_collapse_plan_queue_mode_only` | 20 | No | Yes | Mode only |
