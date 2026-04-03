# Research: render_two_messages Snapshot

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the rendering of multiple queued messages in the bottom pane's message queue widget. It demonstrates how the UI handles multiple user inputs that have been queued while a task is in progress.

**Usage Scenario:**
- User types multiple messages while waiting for AI response
- All messages are queued and displayed in order above the composer
- Each message is visually separated with proper indentation
- User can edit the last queued message using Alt+Up keybinding

## 2. 功能点目的 (Feature Purpose)

The test verifies that:
1. Multiple queued messages are rendered in the correct order
2. Each message has its own "↳" prefix with proper indentation
3. Messages are styled consistently with DIM and ITALIC modifiers
4. Only one edit hint is shown at the bottom (applies to last message)
5. Height calculation accounts for multiple messages (3 rows for 2 messages)

## 3. 具体技术实现 (Technical Implementation)

**Test Setup:**
```rust
let mut queue = PendingInputPreview::new();
queue.queued_messages.push("Hello, world!".to_string());
queue.queued_messages.push("This is another message".to_string());
let width = 40;
let height = queue.desired_height(width);
let mut buf = Buffer::empty(Rect::new(0, 0, width, height));
queue.render(Rect::new(0, 0, width, height), &mut buf);
```

**Rendering Output Structure:**
```
Row 0: "  ↳ Hello, world!                       " (DIM prefix + DIM|ITALIC text)
Row 1: "  ↳ This is another message             " (DIM prefix + DIM|ITALIC text)
Row 2: "    alt + ↑ edit                        " (DIM hint)
```

**Implementation Details:**
- Each message is wrapped using `adaptive_wrap_lines()` with indentation
- Initial indent: `"  ↳ "` (dimmed)
- Subsequent indent: `"    "` (4 spaces for wrapped lines)
- Edit hint only appears once at the bottom when `queued_messages` is not empty

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

**Source Files:**
- `codex-rs/tui/src/bottom_pane/pending_input_preview.rs` - Main implementation
- `codex-rs/tui_app_server/src/bottom_pane/pending_input_preview.rs` - TUI app server implementation

**Snapshot Location:**
- `codex-rs/tui_app_server/src/bottom_pane/snapshots/codex_tui__bottom_pane__message_queue__tests__render_two_messages.snap`

**Related Test Methods:**
- `render_two_messages()` - Tests multiple message rendering
- `render_more_than_three_messages()` - Tests message list overflow

**Key Code Section:**
```rust
for message in &self.queued_messages {
    let wrapped = adaptive_wrap_lines(
        message.lines().map(|line| Line::from(line.dim().italic())),
        RtOptions::new(width as usize)
            .initial_indent(Line::from("  ↳ ".dim()))
            .subsequent_indent(Line::from("    ")),
    );
    Self::push_truncated_preview_lines(&mut lines, wrapped, Line::from("    …".dim().italic()));
}
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

**Dependencies:**
- `ratatui` - Terminal UI framework
- `crossterm::event::KeyCode` - Key code definitions
- `insta` - Snapshot testing

**Internal Modules:**
- `crate::wrapping::RtOptions` - Text wrapping options
- `crate::key_hint` - Key binding display
- `crate::render::renderable::Renderable` - Widget trait

**Integration Points:**
- The edit hint keybinding can be customized via `set_edit_binding()`
- Used by `BottomPane` to display queued messages via `set_pending_input_preview()`

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvements)

**Potential Risks:**
1. **Memory Growth:** No limit on queued_messages vector size in the widget itself
2. **Height Overflow:** Very many messages could exceed available screen space
3. **Snapshot Fragility:** Style modifier ordering changes break snapshots

**Edge Cases:**
1. **Message Truncation:** The `PREVIEW_LINE_LIMIT` (3 lines) truncates long individual messages
2. **No Message Limit:** Unlike the 3-line limit per message, there's no limit on message count
3. **Width Changes:** Rendering at different widths produces different line breaks

**Improvement Suggestions:**
1. **Add Message Count Limit:** Consider capping the number of displayed queued messages
2. **Scroll Support:** For many queued messages, add scrolling capability
3. **Message Numbers:** Show message count (e.g., "Message 1 of 5") for clarity
4. **Test Coverage:**
   - Test behavior with 10+ messages
   - Test with messages containing newlines
   - Test minimum width rendering
5. **Documentation:** Clarify that edit hint only applies to the last message

**Related Tests:**
- `render_more_than_three_messages` - Tests 4 messages (no truncation at message level)
- `render_many_line_message` - Tests single message with many lines (triggers truncation)
