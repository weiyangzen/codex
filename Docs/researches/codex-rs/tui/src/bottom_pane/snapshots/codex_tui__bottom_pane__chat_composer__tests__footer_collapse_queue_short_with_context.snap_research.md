# Research: footer_collapse_queue_short_with_context

## Snapshot Description

This snapshot captures the footer UI state when the composer has a draft message ("Test"), a task is running, and the terminal width is constrained to 50 columns. It demonstrates the responsive footer collapse behavior showing the shortened queue hint alongside the context window indicator.

## Visual Output

```
"                                                  "
"› Test                                            "
"                                                  "
"                                                  "
"                                                  "
"                                                  "
"                                                  "
"                                                  "
"  tab to queue message          98% context left  "
```

## Code Analysis

### Test Setup

**Source:** `codex-rs/tui/src/bottom_pane/chat_composer.rs` (lines 4829-4838)

```rust
snapshot_composer_state_with_width(
    "footer_collapse_queue_short_with_context",
    50,
    true,
    |composer| {
        setup_collab_footer(composer, 98, None);
        composer.set_task_running(true);
        composer.set_text_content("Test".to_string(), Vec::new(), Vec::new());
    },
);
```

### Key State Components

1. **Footer Mode:** `FooterMode::ComposerHasDraft` - triggered by having text content
2. **Task Running:** `true` - enables the queue hint
3. **Context Window:** 98% remaining - displayed on the right side
4. **Terminal Width:** 50 columns - triggers collapse behavior
5. **Collaboration Mode:** Disabled (`None`)

### Footer Collapse Logic

The footer rendering follows the collapse hierarchy defined in `single_line_footer_layout()` (footer.rs, lines 310-472):

1. **Primary attempt:** Full queue hint with context (`"tab to queue message"` + context)
2. **Fallback 1:** Queue hint without cycle hint
3. **Fallback 2:** Short queue hint (`"tab to queue"`) - **THIS SNAPSHOT**
4. **Fallback 3:** Mode only
5. **Final fallback:** No left-side footer

### Rendering Flow

```rust
// From footer.rs - single_line_footer_layout() queue state progression
let queue_states = [
    default_state,  // "tab to queue message" with cycle hint
    LeftSideState {
        hint: SummaryHintKind::QueueMessage,
        show_cycle_hint: false,
    },
    LeftSideState {
        hint: SummaryHintKind::QueueShort,  // <-- SELECTED
        show_cycle_hint: false,
    },
];
```

### Layout Calculations

- **Left content:** `"  tab to queue message"` (22 chars + 2 indent = 24)
- **Right content:** `"98% context left"` (16 chars)
- **Gap required:** 1 column
- **Total needed:** 24 + 1 + 16 = 41 columns
- **Available:** 50 - 2 (indent) = 48 columns

The full `"tab to queue message"` (18 chars) doesn't fit with context at this width, so the system falls back to the short form `"tab to queue"` (12 chars).

## UI Behavior

### Queue Hint Variants

| Variant | Text | Width | Used When |
|---------|------|-------|-----------|
| Full | `tab to queue message` | 22 chars | Wide terminals |
| Short | `tab to queue` | 12 chars | Narrow terminals |

### Context Window Display

The right-aligned context indicator shows `98% context left` using the `context_window_line()` function (footer.rs, lines 848-860):

```rust
pub(crate) fn context_window_line(percent: Option<i64>, used_tokens: Option<i64>) -> Line<'static> {
    if let Some(percent) = percent {
        let percent = percent.clamp(0, 100);
        return Line::from(vec![Span::from(format!("{percent}% context left")).dim()]);
    }
    // ...
}
```

## Technical Details

### Key Functions

1. **`single_line_footer_layout()`** - Determines optimal footer layout based on available width
2. **`left_side_line()`** - Constructs the left-side footer content
3. **`context_window_line()`** - Formats the context window indicator
4. **`can_show_left_with_context()`** - Checks if both left and right content can fit

### State Transitions

When the user types or the terminal resizes:

1. `ChatComposer::sync_popups()` updates footer state
2. `footer_props()` constructs `FooterProps` from composer state
3. `single_line_footer_layout()` selects appropriate layout variant
4. `render_footer_line()` or `render_footer_from_props()` renders the final output

## Related Snapshots

- `footer_collapse_queue_message_without_context` - Same state but context dropped
- `footer_collapse_queue_short_without_context` - Even narrower, no context
- `footer_collapse_queue_mode_only` - Narrowest, only mode indicator
