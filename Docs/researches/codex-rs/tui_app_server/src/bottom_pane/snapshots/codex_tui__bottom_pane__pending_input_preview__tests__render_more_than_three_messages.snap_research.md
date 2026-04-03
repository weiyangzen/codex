# Research: render_more_than_three_messages Snapshot

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the rendering behavior when more than three messages are queued. Unlike the line-level truncation for individual messages, this test shows that the widget displays ALL queued messages without message-count limiting (only line-level truncation within each message).

**Usage Scenario:**
- User rapidly types multiple follow-up questions while AI is processing
- All messages are preserved and displayed in the queue
- User can see the full sequence of pending inputs
- The edit hint allows editing only the last message

## 2. 功能点目的 (Feature Purpose)

The test verifies that:
1. All queued messages are rendered (no message count limit)
2. Each message displays on its own line(s)
3. Messages maintain proper styling and indentation
4. The section header "• Queued follow-up messages" is shown
5. Edit hint appears at the bottom
6. Height scales linearly with message count (6 rows for 4 messages)

## 3. 具体技术实现 (Technical Implementation)

**Test Setup:**
```rust
let mut queue = PendingInputPreview::new();
queue.queued_messages.push("Hello, world!".to_string());
queue.queued_messages.push("This is another message".to_string());
queue.queued_messages.push("This is a third message".to_string());
queue.queued_messages.push("This is a fourth message".to_string());
let width = 40;
let height = queue.desired_height(width);  // Returns 6
```

**Rendering Output Structure:**
```
Row 0: "• Queued follow-up messages             " (DIM bullet + header)
Row 1: "  ↳ Hello, world!                       " (DIM prefix + DIM|ITALIC)
Row 2: "  ↳ This is another message             " (DIM prefix + DIM|ITALIC)
Row 3: "  ↳ This is a third message             " (DIM prefix + DIM|ITALIC)
Row 4: "  ↳ This is a fourth message            " (DIM prefix + DIM|ITALIC)
Row 5: "    ⌥ + ↑ edit last queued message      " (DIM hint)
```

**Key Observation:**
Unlike the `PREVIEW_LINE_LIMIT` which truncates individual messages after 3 lines, there is NO limit on the number of messages displayed. All 4 messages are shown.

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

**Source Files:**
- `codex-rs/tui/src/bottom_pane/pending_input_preview.rs` - Main implementation

**Snapshot Location:**
- `codex-rs/tui_app_server/src/bottom_pane/snapshots/codex_tui__bottom_pane__pending_input_preview__tests__render_more_than_three_messages.snap`

**Key Code Loop:**
```rust
if !self.queued_messages.is_empty() {
    if !lines.is_empty() {
        lines.push(Line::from(""));  // Empty line separator if pending_steers present
    }
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
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

**Dependencies:**
- `ratatui` - Terminal UI rendering
- `insta` - Snapshot testing

**Internal Modules:**
- `crate::wrapping` - Text wrapping with indentation
- `crate::key_hint` - Key binding display

**Integration with BottomPane:**
```rust
// From mod.rs
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

**Critical Risk - No Message Limit:**
Unlike most UI components that limit displayed items, this widget shows ALL queued messages. With 20+ messages, the widget could consume the entire screen.

**Edge Cases:**
1. **Screen Overflow:** 50+ queued messages would overflow any reasonable terminal height
2. **Empty Messages:** Empty strings in the queue
3. **Mixed Content:** Some messages wrap, others don't
4. **Combined with Pending Steers:** Both sections visible simultaneously

**Improvement Suggestions:**

1. **Add Message Count Limit:**
   ```rust
   const MAX_DISPLAYED_MESSAGES: usize = 5;
   // Show "... and N more messages" for overflow
   ```

2. **Scrolling Support:**
   - Allow scrolling through queued messages
   - Show scroll indicators

3. **Message Counter:**
   - Display "Queued: N messages" in header
   - Helps user understand queue depth

4. **Test Coverage:**
   - Test with 10+ messages
   - Test combined with pending_steers (both sections)
   - Test behavior when total height exceeds typical terminal (24-50 rows)

5. **UX Enhancements:**
   - Number the messages (1., 2., 3.) for clarity
   - Show timestamp of when each was queued
   - Allow deleting individual messages (not just editing last)

**Performance Consideration:**
- Current implementation iterates all messages on every render
- With many messages, this could impact render performance
- Consider: Is there a legitimate use case for 20+ queued messages?

**Design Question:**
Should there be a message count limit? The current behavior (unlimited) could lead to:
- Excessive screen usage
- Poor UX with many small messages
- Potential performance issues

A reasonable limit (5-10 messages) with a "+N more" indicator might improve UX.
