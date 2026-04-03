# pending_input_preview_render_one_message

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/pending_input_preview.rs
- **Snapshot File**: codex_tui__bottom_pane__pending_input_preview__tests__render_one_message.snap
- **Test Function**: render_one_message

## Purpose
Tests the rendering of the PendingInputPreview widget with a single queued message. This snapshot validates the UI for displaying queued follow-up messages that will be submitted after the current turn completes.

## Source Code Context
```rust
// From pending_input_preview.rs
pub(crate) struct PendingInputPreview {
    pub pending_steers: Vec<String>,
    pub queued_messages: Vec<String>,
    edit_binding: key_hint::KeyBinding,
}

const PREVIEW_LINE_LIMIT: usize = 3;

fn as_renderable(&self, width: u16) -> Box<dyn Renderable> {
    if (self.pending_steers.is_empty() && self.queued_messages.is_empty()) || width < 4 {
        return Box::new(());
    }

    let mut lines = vec![];

    if !self.queued_messages.is_empty() {
        Self::push_section_header(&mut lines, width, "Queued follow-up messages".into());

        for message in &self.queued_messages {
            let wrapped = adaptive_wrap_lines(
                message.lines().map(|line| Line::from(line.dim().italic())),
                RtOptions::new(width as usize)
                    .initial_indent(Line::from("  ↳ ".dim()))
                    .subsequent_indent(Line::from("    ")),
            );
            Self::push_truncated_preview_lines(
                &mut lines,
                wrapped,
                Line::from("    …".dim().italic()),
            );
        }
    }

    if !self.queued_messages.is_empty() {
        lines.push(
            Line::from(vec![
                "    ".into(),
                self.edit_binding.into(),
                " edit last queued message".into(),
            ])
            .dim(),
        );
    }

    Paragraph::new(lines).into()
}
```

## UI Components Involved
- `PendingInputPreview`: Main widget struct
- `adaptive_wrap_lines()`: Text wrapping with indentation
- `push_section_header()`: Renders bullet-prefixed section headers
- `push_truncated_preview_lines()`: Limits display to PREVIEW_LINE_LIMIT lines
- `key_hint::alt(KeyCode::Up)`: Default edit binding display

## Key Rendering Logic
The widget renders:
1. Section header: "• Queued follow-up messages" (dimmed)
2. Message content with:
   - "↳" prefix indicator (dimmed)
   - Message text in dimmed italic style
   - Indentation for wrapped lines
3. Edit hint: "⌥ + ↑ edit last queued message" (dimmed)

The content is wrapped using `adaptive_wrap_lines` with proper indentation for multi-line messages.

## Test Setup Details
```rust
#[test]
fn render_one_message() {
    let mut queue = PendingInputPreview::new();
    queue.queued_messages.push("Hello, world!".to_string());
    let width = 40;
    let height = queue.desired_height(width);
    let mut buf = Buffer::empty(Rect::new(0, 0, width, height));
    queue.render(Rect::new(0, 0, width, height), &mut buf);
    assert_snapshot!("render_one_message", format!("{buf:?}"));
}
```

## Dependencies
- `crate::wrapping::adaptive_wrap_lines`: Text wrapping
- `crate::wrapping::RtOptions`: Wrapping options
- `crate::key_hint`: Key binding display
- `ratatui::text::Line`: Line styling
- `ratatui::style::Stylize`: Dim and italic styling

## Notes
- Messages are displayed in dimmed italic style to indicate pending status
- The edit hint shows users how to recall the last message for editing
- Default edit binding is Alt+Up (⌥ + ↑)
- The widget has a 3-line limit per message (`PREVIEW_LINE_LIMIT`)
