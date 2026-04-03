# Research: footer_status_line_yields_to_queue_hint

## Snapshot Content
```
"  tab to queue message                                       100% context left  "
```

## Source Location
`codex-rs/tui/src/bottom_pane/footer.rs`

## Test Context
This snapshot is generated in the `footer_snapshots` test function. It tests the footer rendering when:
- `mode: FooterMode::ComposerHasDraft` - Composer has a draft message
- `is_task_running: true` - A task is currently running
- `status_line_enabled: true` - Status line feature is enabled
- `status_line_value: Some(Line::from("Status line content"))` - Status line has content
- `context_window_percent: None` - No context percentage set
- Terminal width: 80 columns

## Expected Behavior (What the Test Validates)
When a task is running and the composer has a draft, the queue hint ("tab to queue message") takes precedence over the status line. The status line yields to the instructional queue hint because telling the user how to queue their message is more important than showing ambient context when a task is active.

## Component Documentation

### FooterProps Relevant Fields
- `mode: FooterMode::ComposerHasDraft` - Composer has draft content
- `is_task_running: bool` - Determines if queue hint should be shown
- `status_line_enabled: bool` - Status line would be shown if not for running task
- `status_line_value: Option<Line<'static>>` - Status line content (yielded to queue hint)

### Key Functions
- `shows_passive_footer_line()` - Returns FALSE for `ComposerHasDraft` when `is_task_running`:
  ```rust
  pub(crate) fn shows_passive_footer_line(props: &FooterProps) -> bool {
      match props.mode {
          FooterMode::ComposerEmpty => true,
          FooterMode::ComposerHasDraft => !props.is_task_running,  // FALSE in this case
          // ...
      }
  }
  ```

- `passive_footer_status_line()` - Returns `None` when `shows_passive_footer_line()` is false

### Rendering Flow
1. `shows_passive_footer_line()` returns false because task is running
2. `passive_footer_status_line()` returns None
3. Footer falls through to mode-based rendering in `footer_from_props_lines()`
4. `ComposerHasDraft` with `show_queue_hint: true` produces "tab to queue message"
5. Context window line appears on the right side

## Layout and Rendering Details
- Left indent: 2 spaces (`FOOTER_INDENT_COLS`)
- Left content: "⇥ tab to queue message" (with tab key hint styling)
  - Tab key symbol: "⇥" (Unicode right arrow)
  - Text: " tab to queue message" in dim style
- Right content: "100% context left" (dim style, right-aligned)
- The queue hint is prioritized over the status line because it's instructional

## Related Snapshots
- `footer_status_line_overrides_draft_idle` - Same mode but idle (shows status line)
- `footer_composer_has_draft_queue_hint_enabled` - Queue hint without status line
- `footer_status_line_overrides_shortcuts` - Status line taking precedence when idle

## Architectural Notes
The footer has a priority hierarchy for different types of content:

1. **Instructional hints** (highest priority)
   - Quit reminders
   - Esc hints  
   - Queue hints (when task running)
   - These tell the user what actions they can take

2. **Passive context** (lower priority)
   - Status line
   - Active agent label
   - These provide ambient information

When a task is running and the user has composed a draft message, the queue hint takes precedence because it's critical for the user to know they can queue their message while waiting for the current task to complete. The status line yields in this case because instructional hints are more important than contextual information.

This behavior is controlled by `shows_passive_footer_line()` which returns false when `ComposerHasDraft` mode has `is_task_running: true`.
