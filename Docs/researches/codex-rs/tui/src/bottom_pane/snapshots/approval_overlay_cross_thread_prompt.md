# approval_overlay_cross_thread_prompt

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/approval_overlay.rs
- **Snapshot File**: codex_tui__bottom_pane__approval_overlay__tests__approval_overlay_cross_thread_prompt.snap
- **Test Function**: cross_thread_footer_hint_mentions_o_shortcut

## Purpose
This snapshot tests the rendering of the `ApprovalOverlay` for a cross-thread approval request. It shows how the UI displays the source thread label and includes an additional "o to open thread" shortcut in the footer hint.

## Source Code Context

### Test Function
```rust
#[test]
fn cross_thread_footer_hint_mentions_o_shortcut() {
    let (tx, _rx) = unbounded_channel::<AppEvent>();
    let tx = AppEventSender::new(tx);
    let view = ApprovalOverlay::new(
        ApprovalRequest::Exec {
            thread_id: ThreadId::new(),
            thread_label: Some("Robie [explorer]".to_string()),
            id: "test".to_string(),
            command: vec!["echo".to_string(), "hi".to_string()],
            reason: None,
            available_decisions: vec![ReviewDecision::Approved, ReviewDecision::Abort],
            network_approval_context: None,
            additional_permissions: None,
        },
        tx,
        Features::with_defaults(),
    );

    assert_snapshot!(
        "approval_overlay_cross_thread_prompt",
        render_overlay_lines(&view, 80)
    );
}
```

### Key Structs/Components
- `ApprovalOverlay`: Modal overlay for user approval
- `ApprovalRequest::Exec`: Execution approval request variant
- `thread_label`: Optional label identifying the source thread
- `approval_footer_hint()`: Generates footer hint with conditional shortcuts

## UI Components Involved
- `ApprovalOverlay` (modal container)
- `ListSelectionView` (for action options)
- Title: "Would you like to run the following command?"
- Thread label line: "Thread: Robie [explorer]" (bold)
- Command snippet with bash highlighting
- Action options with keyboard shortcuts
- Footer hint with key bindings (including "o to open thread")

## Key Rendering Logic
1. **Cross-Thread Detection**:
   - When `thread_label` is `Some(...)`, the approval is from a different thread
   - The thread label is displayed in the header
   - The footer hint includes the "o" shortcut

2. **Header Generation** (`build_header()`):
   - Shows "Thread: " prefix followed by thread label in bold
   - Empty line separator
   - Shows reason if provided
   - Shows permission rule if applicable
   - Command with bash highlighting

3. **Footer Hint** (`approval_footer_hint()`):
   - Base: "Press enter to confirm or esc to cancel"
   - Cross-thread addition: " or o to open thread"
   - The "o" key sends `AppEvent::SelectAgentThread`

## Test Setup Details
- Creates an `ApprovalRequest::Exec` for an `echo hi` command
- Sets `thread_label` to "Robie [explorer]" (indicating cross-thread context)
- No reason or additional permissions provided
- Renders at width 80 pixels

## Dependencies
- `codex_protocol::ThreadId`
- `codex_protocol::protocol::ReviewDecision`
- `ratatui` for rendering
- `ListSelectionView` for option selection

## Notes
- Cross-thread approvals occur when an agent in one thread needs approval for an action
- The "o" shortcut allows users to quickly navigate to the source thread for context
- This is distinct from same-thread approvals where no thread label is shown
- The footer hint dynamically adjusts based on whether a thread label is present
