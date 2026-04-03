# Research: footer_status_line_overrides_shortcuts

## Snapshot Content
```
"  Status line content                                                           "
```

## Source Location
`codex-rs/tui/src/bottom_pane/footer.rs`

## Test Context
This snapshot is generated in the `footer_snapshots` test function. It tests the footer rendering when:
- `mode: FooterMode::ComposerEmpty` - Composer is empty
- `status_line_enabled: true` - Status line feature is enabled
- `status_line_value: Some(Line::from("Status line content"))` - Status line has content
- `collaboration_modes_enabled: false` - Collaboration modes not enabled
- Terminal width: 80 columns

## Expected Behavior (What the Test Validates)
When the status line is enabled with content, it overrides the default "? for shortcuts" hint that normally appears when the composer is empty. The status line content takes precedence over the standard shortcut hint.

## Component Documentation

### FooterProps Relevant Fields
- `mode: FooterMode::ComposerEmpty` - Base state when composer has no content
- `status_line_enabled: bool` - Enables the configurable status line
- `status_line_value: Option<Line<'static>>` - The status line content to display
- `collaboration_modes_enabled: bool` - Affects whether mode cycle hints appear

### Key Functions
- `passive_footer_status_line()` - Returns the status line when enabled and mode allows passive display:
  ```rust
  pub(crate) fn passive_footer_status_line(props: &FooterProps) -> Option<Line<'static>> {
      if !shows_passive_footer_line(props) {
          return None;
      }
      let mut line = if props.status_line_enabled {
          props.status_line_value.clone()
      } else {
          None
      };
      // ... active_agent_label handling
      line
  }
  ```

### Rendering Flow
1. `footer_from_props_lines()` checks for passive status line first
2. If status line exists, it's returned immediately with `.dim()` styling
3. The default "? for shortcuts" hint is skipped
4. Context window info may still appear on the right side if space permits

## Layout and Rendering Details
- Left indent: 2 spaces (`FOOTER_INDENT_COLS`)
- Content: "Status line content" (19 characters)
- Right padding: 59 spaces to fill 80-column width
- Styling: `.dim()` for subtle, non-intrusive appearance

## Related Snapshots
- `footer_shortcuts_default` - Shows "? for shortcuts" when status line disabled
- `footer_status_line_overrides_context` - Status line replacing context display
- `footer_status_line_overrides_draft_idle` - Status line in draft mode

## Architectural Notes
The status line feature provides users with customizable footer content via the `/statusline` command system. When enabled, it replaces the default contextual hints, giving users control over what information appears at the bottom of the TUI. This is part of the "passive footer" system that shows ambient context instead of instructional hints.

The override behavior ensures that user-configured status line content is always visible when available, taking precedence over generic hints like "? for shortcuts".
