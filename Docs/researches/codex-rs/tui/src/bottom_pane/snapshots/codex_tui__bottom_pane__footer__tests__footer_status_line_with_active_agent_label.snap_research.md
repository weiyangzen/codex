# Research: footer_status_line_with_active_agent_label

## Snapshot Content
```
"  Status line content · Robie [explorer]                                        "
```

## Source Location
`codex-rs/tui/src/bottom_pane/footer.rs`

## Test Context
This snapshot is generated in the `footer_snapshots` test function. It tests the footer rendering when:
- `status_line_enabled: true` - Status line feature enabled
- `status_line_value: Some(Line::from("Status line content"))` - Status line has content
- `active_agent_label: Some("Robie [explorer]".to_string())` - Active agent label present
- `mode: FooterMode::ComposerEmpty` - Composer is empty
- Terminal width: 80 columns

## Expected Behavior (What the Test Validates)
When both a status line value and an active agent label are present, they are combined into a single footer line with the " · " separator (middle dot with spaces). The status line content appears first, followed by the separator, then the active agent label.

## Component Documentation

### FooterProps Relevant Fields
- `status_line_enabled: bool` - Enables status line display
- `status_line_value: Option<Line<'static>>` - Configurable status line content
- `active_agent_label: Option<String>` - Label of the currently viewed agent/thread

### Key Functions
- `passive_footer_status_line()` - Combines status line and agent label:
  ```rust
  pub(crate) fn passive_footer_status_line(props: &FooterProps) -> Option<Line<'static>> {
      // ... early returns ...
      let mut line = if props.status_line_enabled {
          props.status_line_value.clone()
      } else {
          None
      };

      if let Some(active_agent_label) = props.active_agent_label.as_ref() {
          if let Some(existing) = line.as_mut() {
              existing.spans.push(" · ".into());
              existing.spans.push(active_agent_label.clone().into());
          } else {
              line = Some(Line::from(active_agent_label.clone()));
          }
      }
      line
  }
  ```

## Layout and Rendering Details
- Left indent: 2 spaces (`FOOTER_INDENT_COLS`)
- Status line: "Status line content" (19 characters)
- Separator: " · " (3 characters with middle dot)
- Agent label: "Robie [explorer]" (16 characters)
- Total content: 38 characters
- Right padding: 40 spaces to fill 80-column width

## Related Snapshots
- `footer_active_agent_label` - Agent label alone (no status line)
- `footer_status_line_overrides_shortcuts` - Status line without agent label
- `footer_status_line_enabled_no_mode_right` - Empty status line with no agent

## Architectural Notes
The footer supports displaying contextual information from two sources:
1. **Status line** - User-configurable via `/statusline` commands (e.g., model, git branch, context usage)
2. **Active agent label** - Shows the currently selected agent/thread name

When both are present, they are concatenated with the " · " separator to provide a unified contextual footer row. This allows users to see both their custom status information and the current agent context simultaneously.

The separator " · " (U+00B7 Middle Dot) is a stylistic choice that provides visual separation without being as heavy as a pipe or dash character.

If only the agent label is present (no status line value), the agent label is displayed alone.
