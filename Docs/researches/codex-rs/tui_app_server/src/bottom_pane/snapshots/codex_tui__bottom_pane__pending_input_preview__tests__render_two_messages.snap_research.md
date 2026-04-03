# Research: render_two_messages Snapshot

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the rendering of two queued messages in the `PendingInputPreview` widget. It demonstrates the full widget structure with multiple messages including the section header and edit hint.

**Usage Scenario:**
- User types multiple follow-up messages while AI is processing
- All messages are captured and displayed in order
- User can see the sequence of pending inputs
- User can edit the last message using Alt+Up

## 2. 功能点目的 (Feature Purpose)

The test verifies that:
1. Section header "• Queued follow-up messages" is displayed
2. Multiple messages render in order (first in, first displayed)
3. Each message has its own "↳" prefix with DIM + ITALIC styling
4. Edit hint appears only once at the bottom
5. Total height is 4 rows (header + 2 messages + hint)
6. Messages maintain consistent styling and alignment

## 3. 具体技术实现 (Technical Implementation)

**Test Setup:**
```rust
#[test]
fn render_two_messages() {
    let mut queue = PendingInputPreview::new();
    queue.queued_messages.push("Hello, world!".to_string());
    queue.queued_messages.push("This is another message".to_string());
    let width = 40;
    let height = queue.desired_height(width);
    let mut buf = Buffer::empty(Rect::new(0, 0, width, height));
    queue.render(Rect::new(0, 0, width, height), &mut buf);
    assert_snapshot!("render_two_messages", format!("{buf:?}"));
}
```

**Rendering Output Structure:**
```
Row 0: "• Queued follow-up messages             " (DIM bullet + header)
Row 1: "  ↳ Hello, world!                       " (DIM prefix + DIM|ITALIC text)
Row 2: "  ↳ This is another message             " (DIM prefix + DIM|ITALIC text)
Row 3: "    ⌥ + ↑ edit last queued message      " (DIM hint)
```

**Style Application:**
- Bullet "•": DIM (x: 0-1)
- Header: Normal (x: 2+)
- Prefix "↳": DIM (x: 0-3 on message rows)
- Message text: DIM + ITALIC (x: 4+)
- Hint: DIM with keybinding

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

**Source Files:**
- `codex-rs/tui/src/bottom_pane/pending_input_preview.rs` - Main implementation
- `codex-rs/tui_app_server/src/bottom_pane/pending_input_preview.rs` - TUI app server version

**Snapshot Location:**
- `codex-rs/tui_app_server/src/bottom_pane/snapshots/codex_tui__bottom_pane__pending_input_preview__tests__render_two_messages.snap`

**Related Tests:**
- `render_one_message` - Single message baseline
- `render_more_than_three_messages` - Tests with 4 messages
- `render_wrapped_message` - Tests text wrapping behavior

**Key Code Loop:**
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
- `insta` - Snapshot testing

**Internal Dependencies:**
- `crate::key_hint` - Key binding display (shows ⌥ for Option/Alt)
- `crate::wrapping::{RtOptions, adaptive_wrap_lines}` - Text wrapping
- `crate::render::renderable::Renderable` - Widget trait

**Integration with BottomPane:**
```rust
pub(crate) fn set_pending_input_preview(
    &mut self,
    queued: Vec<String>,
    pending_steers: Vec<String>,
) {
    self.pending_input_preview.pending_steers = pending_steers;
    self.pending_input_preview.queued_messages = queued;
    self.request_redraw();
}
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvements)

**Potential Risks:**
1. **Message Order:** Users might expect last-in-first-out (stack) instead of FIFO (queue)
2. **Edit Hint Confusion:** Hint says "edit last" but some users might want to edit any message
3. **No Message Numbers:** With many messages, hard to tell which is which

**Edge Cases:**
1. **Identical Messages:** Two identical messages look the same
2. **Very Long Second Message:** Would wrap or truncate
3. **Empty First Message:** Edge case not tested
4. **Combined with Steers:** Both sections visible simultaneously

**Comparison with Legacy `message_queue` Test:**
The `message_queue` version:
- Had 3 rows total (no header)
- Simpler but less context

The `pending_input_preview` version:
- Has 4 rows (header + 2 messages + hint)
- Better visual hierarchy
- More informative for users

**Improvement Suggestions:**

1. **Message Numbering:**
   ```
   Row 1: "  1. ↳ Hello, world!"
   Row 2: "  2. ↳ This is another message"
   ```

2. **Visual Separation:**
   - Add subtle separator between messages
   - Or alternate background colors

3. **Test Coverage:**
   - Test with messages of very different lengths
   - Test where second message wraps but first doesn't
   - Test with special characters in messages
   - Test combined with pending steers

4. **UX Enhancements:**
   - Show message count in header ("Queued: 2 messages")
   - Allow editing any message (not just last)
   - Allow reordering or deleting individual messages
   - Show relative time ("queued 2m ago")

5. **Accessibility:**
   - Consider screen reader output
   - Ensure styling doesn't rely solely on color
   - Test with high contrast themes

**Performance:**
- Each render iterates all messages
- With typical use (1-5 messages), this is negligible
- No caching implemented; could be added if needed

**Code Quality:**
- The 40-character width is consistent across tests
- Consider testing at multiple widths to ensure robustness
- The edit hint is only shown when `queued_messages` is not empty
