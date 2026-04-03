# bottom_pane_queued_messages_visible_when_status_hidden

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/mod.rs
- **Snapshot File**: codex_tui__bottom_pane__tests__queued_messages_visible_when_status_hidden_snapshot.snap
- **Test Function**: queued_messages_visible_when_status_hidden_snapshot

## Purpose
Tests the BottomPane rendering when the status indicator is hidden but queued messages are present. This snapshot validates that pending input previews remain visible even when the task status is not shown, ensuring users can see their queued follow-up messages.

## Source Code Context
```rust
// From mod.rs - as_renderable()
fn as_renderable(&'_ self) -> RenderableItem<'_> {
    // ...
    let mut flex = FlexRenderable::new();
    // Status indicator (optional)
    if let Some(status) = &self.status {
        flex.push(/*flex*/ 0, RenderableItem::Borrowed(status));
    }
    // Unified exec footer (only when no status)
    if self.status.is_none() && !self.unified_exec_footer.is_empty() {
        flex.push(
            /*flex*/ 0,
            RenderableItem::Borrowed(&self.unified_exec_footer),
        );
    }
    // Pending input preview always shown if content exists
    flex.push(
        /*flex*/ 1,
        RenderableItem::Borrowed(&self.pending_input_preview),
    );
    // Composer always shown
    flex2.push(/*flex*/ 0, RenderableItem::Borrowed(&self.composer));
}
```

## UI Components Involved
- `BottomPane`: Main container widget
- `StatusIndicatorWidget`: Task status (hidden in this test)
- `PendingInputPreview`: Queued messages display
- `ChatComposer`: Input composer with placeholder
- `FlexRenderable`: Flexible layout container

## Key Rendering Logic
The layout renders (from top to bottom):
1. **Queued follow-up messages** section:
   - "• Queued follow-up messages"
   - "↳ Queued follow-up question"
   - "⌥ + ↑ edit last queued message"
2. **Empty line** (spacer)
3. **Composer**:
   - "› Ask Codex to do anything" (placeholder)
4. **Footer**:
   - "? for shortcuts" (left)
   - "100% context left" (right)

The status indicator is explicitly hidden via `hide_status_indicator()`, but queued messages remain visible.

## Test Setup Details
```rust
#[test]
fn queued_messages_visible_when_status_hidden_snapshot() {
    let mut pane = BottomPane::new(BottomPaneParams { /* ... */ });
    pane.set_task_running(true);
    pane.set_pending_input_preview(
        vec!["Queued follow-up question".to_string()],
        Vec::new()
    );
    pane.hide_status_indicator();  // Hide the status
    // ... render and snapshot
}
```

## Dependencies
- `PendingInputPreview`: Message queue display
- `StatusIndicatorWidget`: Task status (hidden)
- `ChatComposer`: Input area
- `FlexRenderable`: Layout management

## Notes
- Queued messages remain visible even when status is hidden
- This ensures users don't lose track of pending inputs
- The composer placeholder is shown when no text is entered
- Context usage is displayed in the footer
