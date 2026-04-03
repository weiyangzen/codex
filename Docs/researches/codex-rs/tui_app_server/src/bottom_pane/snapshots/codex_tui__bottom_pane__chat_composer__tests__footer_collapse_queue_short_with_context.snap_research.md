# Research: Footer Collapse - Queue Short with Context

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer rendering behavior when:
- The composer has **draft content** ("Test" in the textarea)
- A **task is running** (queue mode active)
- The terminal width is **50 columns** - moderately narrow
- **No collaboration mode** is active
- The **short queue hint** ("tab to queue") is displayed
- **Context information** ("98% context left") is still visible

This tests a balanced collapse state where some abbreviation occurs but both action guidance and status information remain accessible.

## 2. 功能点目的 (Feature Purpose)

The "queue short with context" variant serves to:
1. **Balanced Information Display**: Show both queue hint and context when space is limited
2. **Abbreviated Action Guidance**: Use "tab to queue" instead of "tab to queue message" to save space
3. **Status Preservation**: Maintain visibility of context window usage
4. **Responsive Adaptation**: Handle medium-width terminals (50 columns) gracefully

This represents a middle ground in the collapse hierarchy - informative yet compact.

## 3. 具体技术实现 (Technical Implementation)

### Collapse State Selection
At 50 columns, the algorithm selects:
- **Hint variant**: `SummaryHintKind::QueueShort` ("tab to queue")
- **Context display**: `show_context = true`
- **Mode indicator**: None (no collaboration mode set)

### Width Calculation
```
Total width: 50 columns
Indent: 2 columns (FOOTER_INDENT_COLS)
Available: 48 columns

Left side: "tab to queue" = ~12 characters
Gap: 1 column (FOOTER_CONTEXT_GAP_COLS)
Right side: "98% context left" = ~16 characters
Total used: ~29 columns
Margin: ~19 columns remaining
```

### Why This State?
At 50 columns:
- "tab to queue message" (~21 chars) + context (~16) + gap (1) = ~38 chars → fits
- But the algorithm prefers shorter hint to maintain comfortable margins
- Actually, looking at the test expectation, it seems the full message might not fit with context at 50 cols

The algorithm iterates through states and picks the first one that fits with context.

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Test Implementation
**`codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`** (lines 4844-4853):

```rust
snapshot_composer_state_with_width(
    "footer_collapse_queue_short_with_context",
    50,  // Medium-narrow width
    true,
    |composer| {
        setup_collab_footer(composer, 98, None);  // No collaboration mode
        composer.set_task_running(true);
        composer.set_text_content("Test".to_string(), Vec::new(), Vec::new());
    },
);
```

### Algorithm Logic
**`codex-rs/tui_app_server/src/bottom_pane/footer.rs`** (lines 348-378):

```rust
if show_queue_hint {
    let queue_states = [
        default_state,  // Try full hint first
        LeftSideState {
            hint: SummaryHintKind::QueueMessage,
            show_cycle_hint: false,
        },
        LeftSideState {
            hint: SummaryHintKind::QueueShort,  // This is selected
            show_cycle_hint: false,
        },
    ];

    // Pass 1: Try to fit with context
    for state in queue_states {
        let width = state_width(state);
        if width > 0 && can_show_left_with_context(area, width, context_width) {
            return (SummaryLeft::Custom(state_line(state)), true);
        }
    }
}
```

### State Width Calculation
**`state_width()`** (line 342):
```rust
let state_width = |state: LeftSideState| -> u16 { state_line(state).width() as u16 };
```

### Context Line Generation
**`context_window_line()`** (lines 848-860):
```rust
pub(crate) fn context_window_line(percent: Option<i64>, used_tokens: Option<i64>) -> Line<'static> {
    if let Some(percent) = percent {
        let percent = percent.clamp(0, 100);
        return Line::from(vec![Span::from(format!("{percent}% context left")).dim()]);
    }
    // ...
}
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Configuration
| Parameter | Value | Description |
|-----------|-------|-------------|
| `width` | 50 | Terminal column count |
| `context_window_percent` | 98 | Shows "98% context left" |
| `collaboration_mode_indicator` | `None` | No mode label |
| `is_task_running` | `true` | Enables queue mode |
| `show_queue_hint` | `true` | Shows queue-related hints |

### Rendering Dependencies
- **ratatui**: `Line`, `Span`, `Rect` for terminal rendering
- **key_hint**: Styled key display for "tab"
- **Stylize**: `.dim()` for context text styling

### Test Framework
- **insta**: Snapshot testing with `assert_snapshot!`
- **TestBackend**: Deterministic terminal backend for testing

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvements)

### Risk Analysis

#### 1. Width Boundary Sensitivity
- **Current**: 50 columns is a comfortable middle ground
- **Boundary**: The transition from "with context" to "without context" happens around 40-45 columns
- **Risk**: Small changes in string length could shift the boundary

#### 2. Context Percentage Display
- **Current**: "98% context left" is optimistic (high availability)
- **Low context**: At 5% or less, the same width is used but urgency is higher
- **Suggestion**: Consider color-coding context based on availability

#### 3. Mode Indicator Absence
- **Current**: No collaboration mode means simpler display
- **With mode**: If Plan mode were active, "tab to queue · Plan mode" might not fit at 50 cols

### Edge Cases

1. **Context at 100%**: "100% context left" is slightly wider than "98%"
2. **Context at 0%**: "0% context left" has same width but critical meaning
3. **Rapid Width Changes**: Resizing between 49 and 51 columns could cause flicker

### Improvement Suggestions

#### 1. Dynamic Context Formatting
```rust
// Adapt context display based on available space
let context_text = match available_width {
    0..=15 => format!("{percent}%"),           // Just number
    16..=25 => format!("{percent}% ctx"),      // Abbreviated
    _ => format!("{percent}% context left"),   // Full
};
```

#### 2. Color-Coded Context
```rust
// Visual urgency indicator
let context_style = match context_percent {
    0..=10 => Style::default().red().bold(),
    11..=25 => Style::default().yellow(),
    _ => Style::default().dim(),
};
```

#### 3. Smart Hint Selection
```rust
// Consider user behavior when selecting hint
let hint = if user_frequently_queues {
    "tab to queue"  // Shorter, they know the feature
} else {
    "tab to queue message"  // More descriptive for new users
};
```

#### 4. Context Tooltip
```rust
// Show detailed context on hover/focus
if footer_hovered && width < 60 {
    show_tooltip("98% context remaining (approx. 3900 tokens)");
}
```

#### 5. Test Coverage
- Add test at boundary width where context disappears (~40 cols)
- Add test with different context percentages
- Add test with collaboration mode active at 50 cols

### Related Snapshots
| Snapshot | Width | Context | Hint | Mode | Description |
|----------|-------|---------|------|------|-------------|
| `footer_collapse_queue_full` | 120 | Yes | Full | No | Baseline |
| `footer_collapse_queue_short_with_context` | 50 | Yes | Short | No | This test |
| `footer_collapse_queue_message_without_context` | 40 | No | Full | No | No context |
| `footer_collapse_queue_short_without_context` | 30 | No | Short | No | Minimal |
| `footer_collapse_queue_mode_only` | 20 | No | Short | No | Ultra-minimal |
