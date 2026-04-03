# footer_active_agent_label

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/footer.rs
- **Snapshot File**: codex_tui__bottom_pane__footer__tests__footer_active_agent_label.snap
- **Test Function**: footer_snapshots (within the test function)

## Purpose
This snapshot tests the footer rendering when displaying an active agent label without a status line. It shows how the agent name is displayed in the footer area.

## Source Code Context
The snapshot is generated from the footer test with `active_agent_label` set:

```rust
let props = FooterProps {
    mode: FooterMode::ComposerEmpty,
    esc_backtrack_hint: false,
    use_shift_enter_hint: false,
    is_task_running: false,
    collaboration_modes_enabled: false,
    is_wsl: false,
    quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),
    context_window_percent: None,
    context_window_used_tokens: None,
    status_line_value: None,
    status_line_enabled: false,
    active_agent_label: Some("Robie [explorer]".to_string()),
};

snapshot_footer("footer_active_agent_label", props);
```

The rendering uses `passive_footer_status_line()`:
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

## UI Components Involved
- `FooterProps` - Footer configuration
- `passive_footer_status_line()` - Generates contextual footer line
- `render_context_right()` - Right-aligns the context indicator

## Key Rendering Logic
The footer renders:
- Left side: Empty (no shortcuts hint when showing agent label)
- Right side: "Robie [explorer]" followed by "100% context left"

The agent label appears right-aligned with the context window indicator.

## Test Setup Details
The test creates `FooterProps` with:
- Mode: `ComposerEmpty`
- `active_agent_label`: "Robie [explorer]"
- `status_line_enabled`: false
- No collaboration mode indicator
- Default context window (100% left)

## Dependencies
- `FooterProps` - Footer configuration struct
- `FooterMode::ComposerEmpty` - Base mode when composer is empty
- `passive_footer_status_line()` - Status line generation
- `context_window_line()` - Context window indicator

## Notes
- When only the agent label is present (no status line), it appears on the right side
- The context window indicator is always shown on the right
- The agent label format "Name [role]" suggests agents have both a name and a role/type
