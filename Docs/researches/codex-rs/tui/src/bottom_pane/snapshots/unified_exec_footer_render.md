# unified_exec_footer_render

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/unified_exec_footer.rs
- **Snapshot File**: codex_tui__bottom_pane__unified_exec_footer__tests__render_more_sessions.snap
- **Test Function**: render_more_sessions

## Purpose
Tests the UnifiedExecFooter rendering with a single background process. This snapshot validates the UI for displaying a summary of active unified-exec background terminal sessions in the bottom pane.

## Source Code Context
```rust
// From unified_exec_footer.rs
pub(crate) struct UnifiedExecFooter {
    processes: Vec<String>,
}

impl UnifiedExecFooter {
    pub(crate) fn summary_text(&self) -> Option<String> {
        if self.processes.is_empty() {
            return None;
        }

        let count = self.processes.len();
        let plural = if count == 1 { "" } else { "s" };
        Some(format!(
            "{count} background terminal{plural} running · /ps to view · /stop to close"
        ))
    }

    fn render_lines(&self, width: u16) -> Vec<Line<'static>> {
        if width < 4 {
            return Vec::new();
        }
        let Some(summary) = self.summary_text() else {
            return Vec::new();
        };
        let message = format!("  {summary}");
        let (truncated, _, _) = take_prefix_by_width(&message, width as usize);
        vec![Line::from(truncated.dim())]
    }
}
```

## UI Components Involved
- `UnifiedExecFooter`: Main footer widget
- `take_prefix_by_width()`: Truncates text to fit width
- `summary_text()`: Generates the summary message
- `ratatui::text::Line`: Line rendering with dim style

## Key Rendering Logic
The footer renders:
1. **Summary text** (dimmed, indented by 2 spaces):
   - "1 background terminal running · /ps to view · /stop to close"
   - The text is truncated if it exceeds the available width
   - Uses "·" as a separator between elements

The message provides:
- Count of running background terminals
- `/ps` command hint to view sessions
- `/stop` command hint to close sessions

## Test Setup Details
```rust
#[test]
fn render_more_sessions() {
    let mut footer = UnifiedExecFooter::new();
    footer.set_processes(vec!["rg \"foo\" src".to_string()]);
    let width = 50;
    let height = footer.desired_height(width);
    let mut buf = Buffer::empty(Rect::new(0, 0, width, height));
    footer.render(Rect::new(0, 0, width, height), &mut buf);
    assert_snapshot!("render_more_sessions", format!("{buf:?}"));
}
```

## Dependencies
- `crate::live_wrap::take_prefix_by_width`: Width-aware truncation
- `ratatui::style::Stylize`: Dim styling
- `ratatui::widgets::Paragraph`: Text rendering

## Notes
- The footer only renders when there are active processes
- Text is truncated with width-aware logic (not simple character count)
- The summary is shown in dimmed style to be less prominent
- When a status indicator is active, the summary is shown inline instead
- The plural form "terminals" is used when count > 1
