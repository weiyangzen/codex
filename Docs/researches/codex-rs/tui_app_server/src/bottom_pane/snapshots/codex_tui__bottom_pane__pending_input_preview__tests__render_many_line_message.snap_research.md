# Research: render_many_line_message Snapshot

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the truncation behavior for messages containing many lines. When a user queues a multi-line message, the widget limits the display to prevent excessive screen usage while still indicating that more content exists.

**Usage Scenario:**
- User pastes or types a message with multiple explicit newlines
- The message is queued while AI is processing
- Rather than displaying all lines (which could take excessive space), only the first 3 lines are shown
- An ellipsis ("…") indicates truncated content

## 2. 功能点目的 (Feature Purpose)

The test verifies that:
1. Multi-line messages are truncated to `PREVIEW_LINE_LIMIT` (3 lines)
2. An ellipsis indicator ("…") appears when content is truncated
3. The section header "• Queued follow-up messages" is displayed
4. Each line maintains proper styling (DIM + ITALIC)
5. The edit hint is still shown at the bottom
6. Total height is 6 rows (header + 3 content lines + ellipsis + hint)

## 3. 具体技术实现 (Technical Implementation)

**Test Setup:**
```rust
let mut queue = PendingInputPreview::new();
queue.queued_messages.push("This is\na message\nwith many\nlines".to_string());
let width = 40;
let height = queue.desired_height(width);  // Returns 6
```

**Rendering Output Structure:**
```
Row 0: "• Queued follow-up messages             " (DIM bullet + header)
Row 1: "  ↳ This is                             " (DIM prefix + DIM|ITALIC)
Row 2: "    a message                           " (4-space indent + DIM|ITALIC)
Row 3: "    with many                           " (4-space indent + DIM|ITALIC)
Row 4: "    …                                   " (DIM|ITALIC ellipsis)
Row 5: "    ⌥ + ↑ edit last queued message      " (DIM hint with Option symbol)
```

**Truncation Logic:**
```rust
const PREVIEW_LINE_LIMIT: usize = 3;

fn push_truncated_preview_lines(
    lines: &mut Vec<Line<'static>>,
    wrapped: Vec<Line<'static>>,
    overflow_line: Line<'static>,
) {
    let wrapped_len = wrapped.len();
    lines.extend(wrapped.into_iter().take(PREVIEW_LINE_LIMIT));
    if wrapped_len > PREVIEW_LINE_LIMIT {
        lines.push(overflow_line);
    }
}
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

**Source Files:**
- `codex-rs/tui/src/bottom_pane/pending_input_preview.rs` - Main implementation
- `codex-rs/tui_app_server/src/bottom_pane/pending_input_preview.rs` - TUI app server version

**Snapshot Location:**
- `codex-rs/tui_app_server/src/bottom_pane/snapshots/codex_tui__bottom_pane__pending_input_preview__tests__render_many_line_message.snap`

**Key Code Sections:**

**Section Header Rendering:**
```rust
fn push_section_header(lines: &mut Vec<Line<'static>>, width: u16, header: Line<'static>) {
    let mut spans = vec!["• ".dim()];
    spans.extend(header.spans);
    lines.extend(adaptive_wrap_lines(
        std::iter::once(Line::from(spans)),
        RtOptions::new(width as usize).subsequent_indent(Line::from("  ".dim())),
    ));
}
```

**Message Processing:**
```rust
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
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

**Dependencies:**
- `ratatui` - Buffer, Rect, Line, Paragraph, Stylize
- `crossterm::event::KeyCode` - For key hint display
- `insta` - Snapshot testing

**Internal Dependencies:**
- `crate::wrapping::{RtOptions, adaptive_wrap_lines}` - Text wrapping
- `crate::key_hint` - Key binding formatting (shows ⌥ for Option/Alt)
- `crate::render::renderable::Renderable` - Widget trait

**Keybinding Display:**
- Default: Alt+Up (shown as "⌥ + ↑" on macOS-style terminals)
- Configurable via `set_edit_binding()`

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvements)

**Potential Risks:**
1. **Hardcoded Limit:** `PREVIEW_LINE_LIMIT = 3` may not suit all terminal sizes
2. **Ellipsis Only:** No way to expand/view full message content from the UI
3. **Line Counting:** `message.lines()` splits on `\n`; different line endings (CRLF) not explicitly handled

**Edge Cases:**
1. **Empty Lines:** Message with consecutive newlines ("line1\n\nline3")
2. **Whitespace Only:** Message containing only newlines/spaces
3. **Very Long Single Line:** Combination of wrapping + truncation
4. **No Newlines But Long:** Message that wraps naturally without explicit newlines

**Improvement Suggestions:**

1. **Dynamic Limit:** Make `PREVIEW_LINE_LIMIT` configurable based on available height
2. **Expand Option:** Allow user to press a key to view full message
3. **Better Ellipsis:** Show how many lines were truncated (e.g., "… and 5 more lines")
4. **Line Ending Normalization:** Explicitly handle CRLF vs LF
5. **Test Coverage:**
   - Test with Windows line endings (CRLF)
   - Test with trailing newlines
   - Test with empty lines in the middle
   - Test exact boundary (3 lines should not show ellipsis)

**UX Considerations:**
- The ellipsis styling (DIM|ITALIC) matches the message content styling
- Consider making ellipsis visually distinct (e.g., different color or symbol)
- The "⌥" symbol may not render correctly on all terminals; consider ASCII fallback

**Performance Notes:**
- `message.lines()` creates an iterator over string slices (zero-copy)
- `adaptive_wrap_lines` processes each line independently
- No caching of wrapped output; recalculated on every render
