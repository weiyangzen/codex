# Research: Footer Collapse - Queue Message without Context

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer rendering behavior when:
- The composer has **draft content** ("Test" in the textarea)
- A **task is running** (queue mode active)
- The terminal width is **40 columns** - narrow enough to hide context
- **No collaboration mode** is active
- The **full queue hint** ("tab to queue message") is still displayed

This tests an intermediate collapse state where context information is sacrificed but the full queue message hint is preserved, prioritizing user guidance over status information.

## 2. 功能点目的 (Feature Purpose)

The "queue message without context" variant serves to:
1. **Preserve Action Guidance**: Keep the full "tab to queue message" text for clarity
2. **Sacrifice Status Info**: Hide the context indicator when space is constrained
3. **Maintain Usability**: Ensure users understand they can queue messages
4. **Responsive Design**: Adapt to medium-narrow terminal widths (40 columns)

This represents a trade-off point in the collapse hierarchy: context is less important than clear action guidance.

## 3. 具体技术实现 (Technical Implementation)

### Collapse Decision Logic
The `single_line_footer_layout()` function determines this state through:

```rust
if show_queue_hint {
    // In queue mode, prefer dropping context before dropping the queue hint
    let queue_states = [
        default_state,  // "tab to queue message" with cycle hint
        LeftSideState { hint: SummaryHintKind::QueueMessage, show_cycle_hint: false },
        LeftSideState { hint: SummaryHintKind::QueueShort, show_cycle_hint: false },
    ];
    
    // Pass 1: Try to fit with context
    // ... (fails at 40 columns)
    
    // Pass 2: Drop context, keep full message
    // ... (succeeds at 40 columns)
}
```

### Content Layout at 40 Columns
```
[2-space indent] tab to queue message
```
- **Total width**: ~24 characters + 2 indent = 26 columns used
- **Available**: 40 columns (plenty of headroom)
- **Right side**: Empty (context hidden)

### Why Not Shorter?
At 40 columns, there's enough space for "tab to queue message" (~21 chars), so the algorithm doesn't need to fall back to "tab to queue" (~12 chars).

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Test Implementation
**`codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`** (lines 4854-4863):

```rust
snapshot_composer_state_with_width(
    "footer_collapse_queue_message_without_context",
    40,  // 40-column width
    true,
    |composer| {
        setup_collab_footer(composer, 98, None);  // No collaboration mode
        composer.set_task_running(true);
        composer.set_text_content("Test".to_string(), Vec::new(), Vec::new());
    },
);
```

### Collapse Logic
**`codex-rs/tui_app_server/src/bottom_pane/footer.rs`** (lines 348-395):

```rust
if show_queue_hint {
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

    // Pass 1: keep the right-side context indicator if any queue variant can fit
    let mut previous_state: Option<LeftSideState> = None;
    for state in queue_states {
        // ...
        if width > 0 && can_show_left_with_context(area, width, context_width) {
            return (SummaryLeft::Default, true);  // With context
        }
    }

    // Pass 2: if context cannot fit, drop it before dropping the queue hint
    let mut previous_state: Option<LeftSideState> = None;
    for state in queue_states {
        // ...
        if width > 0 && left_fits(area, width) {
            return (SummaryLeft::Custom(state_line(state)), false);  // Without context
        }
    }
}
```

### Key Functions
1. **`left_fits()`** (lines 252-255): Checks if left content fits in the area
2. **`can_show_left_with_context()`** (lines 518-527): Checks left + gap + context fit
3. **`state_line()`** (lines 335-341): Generates the Line for a given state

### State Enum
**`SummaryHintKind`** (lines 257-263):
```rust
enum SummaryHintKind {
    None,
    Shortcuts,
    QueueMessage,  // "tab to queue message"
    QueueShort,    // "tab to queue"
}
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Configuration
| Parameter | Value | Description |
|-----------|-------|-------------|
| `width` | 40 | Terminal column count |
| `context_window_percent` | 98 | Would show "98% context left" if space allowed |
| `collaboration_mode_indicator` | `None` | No mode label |
| `is_task_running` | `true` | Enables queue hint |
| `show_queue_hint` | `true` | Shows queue-related hints |

### Rendering Chain
1. `snapshot_composer_state_with_width()` - Test helper
2. `ChatComposer::render()` - Renders the composer widget
3. `footer_height()` - Calculates footer height
4. `single_line_footer_layout()` - Determines collapse state
5. `render_footer_line()` or `render_footer_from_props()` - Renders the footer

### Dependencies
- **ratatui**: Terminal UI primitives
- **crossterm**: Key event definitions for hint styling
- **insta**: Snapshot testing

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvements)

### Risk Analysis

#### 1. Width Boundary Precision
- **Current**: 40 columns is well below the context threshold (~50 cols)
- **Risk**: If context calculation changes, this test might not actually trigger "without context"
- **Verification**: At 40 cols, "tab to queue message" (21 chars) + context (18 chars) + gap (1) = 40 chars exactly at boundary

#### 2. String Length Sensitivity
- **"tab to queue message"**: 21 characters
- **With styling**: Key hint adds visual brackets around "tab"
- **Total rendered**: Approximately 24-26 columns

#### 3. Missing Context Warning
- **Risk**: Users on narrow terminals lose visibility into context exhaustion
- **Impact**: May hit token limits unexpectedly
- **Mitigation**: Alternative warning mechanisms (status bar, color changes)

### Edge Cases

1. **Exact Fit**: At exactly 40 columns, the content fits perfectly without context
2. **Rapid Resize**: Resizing between 39 and 41 columns causes footer content to appear/disappear
3. **Font/Character Width**: Non-monospace fonts or double-width characters could cause misalignment

### Improvement Suggestions

#### 1. Context Warning Alternative
```rust
// When context is hidden, show a subtle indicator
if !show_context && context_percent < 20 {
    // Flash the border or change composer background color
    composer.set_border_style(Style::default().yellow());
}
```

#### 2. Progressive Disclosure
```rust
// Show compact context when space is limited
let context_text = if width < 45 {
    "98%".to_string()  // Just the number
} else {
    "98% context left".to_string()
};
```

#### 3. Minimum Width Enforcement
```rust
// Warn users if terminal is too narrow
if width < 30 {
    render_warning("Terminal too narrow - some features hidden");
}
```

#### 4. Smart Hint Truncation
```rust
// Truncate from the end of the hint rather than switching variants
let hint = if width < 45 {
    truncate_keeping_key("tab to queue message", width - 10)  // Keep "tab" visible
} else {
    "tab to queue message".to_string()
};
```

#### 5. Test Coverage Expansion
- Add test at 39 columns (should still show full message)
- Add test at 35 columns (boundary for short variant)
- Add test with different context percentages

### Related Snapshots Comparison
| Snapshot | Width | Context | Hint | Total Content |
|----------|-------|---------|------|---------------|
| `footer_collapse_queue_full` | 120 | Yes | Full | Complete |
| `footer_collapse_queue_short_with_context` | 50 | Yes | Short | Balanced |
| `footer_collapse_queue_message_without_context` | 40 | No | Full | This test |
| `footer_collapse_queue_short_without_context` | 30 | No | Short | Minimal |
| `footer_collapse_queue_mode_only` | 20 | No | None | Ultra-minimal |
