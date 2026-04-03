# Research: footer_collapse_queue_short_without_context

## Snapshot Description

This snapshot captures the footer UI state when the composer has a draft message ("Test"), a task is running, and the terminal width is severely constrained to 30 columns. At this narrow width, the context window indicator is dropped entirely, showing only the shortened queue hint.

## Visual Output

```
"                              "
"› Test                        "
"                              "
"                              "
"                              "
"                              "
"                              "
"                              "
"  tab to queue message        "
```

## Code Analysis

### Test Setup

**Source:** `codex-rs/tui/src/bottom_pane/chat_composer.rs` (lines 4849-4858)

```rust
snapshot_composer_state_with_width(
    "footer_collapse_queue_short_without_context",
    30,
    true,
    |composer| {
        setup_collab_footer(composer, 98, None);
        composer.set_task_running(true);
        composer.set_text_content("Test".to_string(), Vec::new(), Vec::new());
    },
);
```

### Key State Components

1. **Footer Mode:** `FooterMode::ComposerHasDraft`
2. **Task Running:** `true` - enables queue hint display
3. **Context Window:** 98% (configured but not displayed due to width)
4. **Terminal Width:** 30 columns - severe constraint
5. **Collaboration Mode:** Disabled

### Footer Collapse Logic

The `single_line_footer_layout()` function (footer.rs) implements a two-pass strategy for queue hints:

**Pass 1:** Try to fit queue hint WITH context indicator
```rust
for state in queue_states {
    let width = state_width(state);
    if width > 0 && can_show_left_with_context(area, width, context_width) {
        // Can fit with context
    }
}
```

**Pass 2:** Drop context, fit queue hint alone
```rust
for state in queue_states {
    let width = state_width(state);
    if width > 0 && left_fits(area, width) {  // <-- THIS PATH
        // Context dropped, queue hint only
    }
}
```

### Why "tab to queue message" Instead of "tab to queue"?

At 30 columns:
- Available width: 30 - 2 (indent) = 28 columns
- `"tab to queue message"` = 22 chars (with styled tab key)
- Fits within 28 columns, so no need to shorten further

The short form `"tab to queue"` would only appear if even the full message couldn't fit.

## UI Behavior

### Collapse Priority for Queue Mode

1. **Full queue hint + context** (preferred)
2. **Full queue hint without context** - **THIS SNAPSHOT**
3. Short queue hint + context
4. Short queue hint without context
5. Mode only
6. Empty

### Width Calculations

| Element | Width |
|---------|-------|
| Indent | 2 columns |
| Tab key styled | ~4 chars |
| "to queue message" | 16 chars |
| **Total left** | ~22 chars |
| Context gap | 1 column |
| Context indicator | 16 chars |
| **Total with context** | ~39 columns |

At 30 columns, the context indicator (16 chars + 1 gap = 17) cannot fit alongside even the shortened queue hint.

## Technical Details

### Key Code Paths

**From footer.rs:**

```rust
// Pass 2: if context cannot fit, drop it before dropping the queue hint
let mut previous_state: Option<LeftSideState> = None;
for state in queue_states {
    if previous_state == Some(state) {
        continue;
    }
    previous_state = Some(state);
    let width = state_width(state);
    if width > 0 && left_fits(area, width) {
        if state == default_state {
            return (SummaryLeft::Default, false);  // show_context = false
        }
        return (SummaryLeft::Custom(state_line(state)), false);
    }
}
```

### SummaryHintKind Enum

```rust
enum SummaryHintKind {
    None,
    Shortcuts,       // "? for shortcuts"
    QueueMessage,    // "tab to queue message" <-- USED
    QueueShort,      // "tab to queue"
}
```

## Related Snapshots

- `footer_collapse_queue_short_with_context` - Wider terminal, context visible
- `footer_collapse_queue_message_without_context` - Intermediate width
- `footer_collapse_queue_mode_only` - Narrowest, no hints at all
