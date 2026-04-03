# Research: footer_status_line_overrides_draft_idle

## Snapshot Content
```
"  Status line content                                                           "
```

## Source Location
`codex-rs/tui/src/bottom_pane/footer.rs`

## Test Context
This snapshot is generated in the `footer_snapshots` test function. It tests the footer rendering when:
- `mode: FooterMode::ComposerHasDraft` - Composer has a draft message
- `is_task_running: false` - No task is currently running
- `status_line_enabled: true` - Status line feature is enabled
- `status_line_value: Some(Line::from("Status line content"))` - Status line has content
- Terminal width: 80 columns

## Expected Behavior (What the Test Validates)
When the composer has a draft but no task is running (idle state), and the status line is enabled, the status line content overrides the default footer behavior. Normally `ComposerHasDraft` would show queue hints if a task were running, but since it's idle, the status line is displayed instead.

## Component Documentation

### FooterProps Relevant Fields
- `mode: FooterMode::ComposerHasDraft` - Indicates composer has draft content
- `is_task_running: bool` - Affects whether queue hint or status line is shown
- `status_line_enabled: bool` - Enables status line display
- `status_line_value: Option<Line<'static>>` - The actual status line content

### Key Functions
- `shows_passive_footer_line()` - Returns true for `ComposerHasDraft` when `!is_task_running`
- `uses_passive_footer_status_layout()` - Returns true when status line enabled and passive line allowed
- `passive_footer_status_line()` - Combines status line value with active agent label if present

### Rendering Logic
```rust
// From shows_passive_footer_line()
FooterMode::ComposerHasDraft => !props.is_task_running,  // true in this case

// From footer_from_props_lines()
if let Some(status_line) = passive_footer_status_line(props) {
    return vec![status_line.dim()];  // Status line takes precedence
}
```

## Layout and Rendering Details
- Left indent: 2 spaces (`FOOTER_INDENT_COLS`)
- Content: "Status line content" (19 characters)
- Total line length: 80 characters
- Styling: `.dim()` applied for subtle appearance

## Related Snapshots
- `footer_status_line_yields_to_queue_hint` - Same mode but with task running (shows queue hint instead)
- `footer_composer_has_draft_queue_hint_enabled` - Queue hint shown when task running
- `footer_status_line_overrides_shortcuts` - Status line in empty composer mode

## Architectural Notes
The footer has a priority system for different states:
1. **Instructional hints** (quit reminder, Esc hint, shortcuts) - Highest priority
2. **Queue hint** - Shown when task running and draft exists
3. **Status line** - Shown when enabled and idle
4. **Default hints** - Fallback when nothing else applies

This snapshot demonstrates that status line takes precedence over the default empty state when the composer has a draft but is idle (no running task).
