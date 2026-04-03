# Approval Overlay - Cross-Thread Prompt Snapshot

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the UI rendering of the `ApprovalOverlay` component when displaying an approval request from a **different thread** (cross-thread approval). This scenario occurs in multi-agent/multi-thread environments when:

- An agent running in a background thread needs user approval for a command
- The user is currently viewing a different thread
- The approval must show context about which thread originated the request
- The user needs the ability to navigate to the source thread

The component serves as a cross-thread coordination mechanism, ensuring users can identify and respond to approval requests regardless of which thread they're currently viewing.

## 2. 功能点目的 (Purpose of the Feature)

The feature being tested serves several coordination and transparency purposes:

1. **Thread Identification**: Clearly shows which thread originated the approval request
2. **Context Preservation**: Displays the command that needs approval
3. **Navigation Support**: Allows users to jump to the source thread (`o` key)
4. **Security**: Maintains approval workflow even across thread boundaries
5. **Multi-Agent Coordination**: Enables complex multi-thread agent workflows

## 3. 具体技术实现 (Technical Implementation)

### Core Data Structures

```rust
// From approval_overlay.rs
pub(crate) enum ApprovalRequest {
    Exec {
        thread_id: ThreadId,
        thread_label: Option<String>,  // Key field for cross-thread display
        id: String,
        command: Vec<String>,
        reason: Option<String>,
        available_decisions: Vec<ReviewDecision>,
        network_approval_context: Option<NetworkApprovalContext>,
        additional_permissions: Option<PermissionProfile>,
    },
    // ... other variants
}

pub(crate) struct ApprovalOverlay {
    current_request: Option<ApprovalRequest>,
    queue: Vec<ApprovalRequest>,
    app_event_tx: AppEventSender,
    list: ListSelectionView,
    options: Vec<ApprovalOption>,
    // ... other fields
}
```

### Thread Label Access

```rust
impl ApprovalRequest {
    fn thread_id(&self) -> ThreadId {
        match self {
            ApprovalRequest::Exec { thread_id, .. }
            | ApprovalRequest::Permissions { thread_id, .. }
            | ApprovalRequest::ApplyPatch { thread_id, .. }
            | ApprovalRequest::McpElicitation { thread_id, .. } => *thread_id,
        }
    }

    fn thread_label(&self) -> Option<&str> {
        match self {
            ApprovalRequest::Exec { thread_label, .. }
            | ApprovalRequest::Permissions { thread_label, .. }
            | ApprovalRequest::ApplyPatch { thread_label, .. }
            | ApprovalRequest::McpElicitation { thread_label, .. } => thread_label.as_deref(),
        }
    }
}
```

### Header Construction with Thread Label

```rust
fn build_header(request: &ApprovalRequest) -> Box<dyn Renderable> {
    match request {
        ApprovalRequest::Exec {
            thread_label,  // Used for cross-thread display
            reason,
            command,
            // ...
        } => {
            let mut header: Vec<Line<'static>> = Vec::new();
            
            // Thread label is shown prominently when present
            if let Some(thread_label) = thread_label {
                header.push(Line::from(vec![
                    "Thread: ".into(),
                    thread_label.clone().bold(),
                ]));
                header.push(Line::from(""));
            }
            
            // Reason (if provided)
            if let Some(reason) = reason {
                header.push(Line::from(vec!["Reason: ".into(), reason.clone().italic()]));
                header.push(Line::from(""));
            }
            
            // Command snippet
            let full_cmd = strip_bash_lc_and_escape(command);
            let mut full_cmd_lines = highlight_bash_to_lines(&full_cmd);
            if let Some(first) = full_cmd_lines.first_mut() {
                first.spans.insert(0, Span::from("$ "));
            }
            header.extend(full_cmd_lines);
            
            Box::new(Paragraph::new(header).wrap(Wrap { trim: false }))
        }
        // ...
    }
}
```

### Footer Hint with Open Thread Option

```rust
fn approval_footer_hint(request: &ApprovalRequest) -> Line<'static> {
    let mut spans = vec![
        "Press ".into(),
        key_hint::plain(KeyCode::Enter).into(),
        " to confirm or ".into(),
        key_hint::plain(KeyCode::Esc).into(),
        " to cancel".into(),
    ];
    
    // Add "o to open thread" hint for cross-thread requests
    if request.thread_label().is_some() {
        spans.extend([
            " or ".into(),
            key_hint::plain(KeyCode::Char('o')).into(),
            " to open thread".into(),
        ]);
    }
    Line::from(spans)
}
```

### Open Thread Shortcut Handling

```rust
fn try_handle_shortcut(&mut self, key_event: &KeyEvent) -> bool {
    match key_event {
        // ... other shortcuts
        KeyEvent {
            kind: KeyEventKind::Press,
            code: KeyCode::Char('o'),
            ..
        } => {
            if let Some(request) = self.current_request.as_ref() {
                if request.thread_label().is_some() {
                    self.app_event_tx
                        .send(AppEvent::SelectAgentThread(request.thread_id()));
                    true
                } else {
                    false
                }
            } else {
                false
            }
        }
        // ...
    }
}
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Source File
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/approval_overlay.rs`

### Test Function
```rust
#[test]
fn cross_thread_prompt_snapshot() {
    // Lines ~1027-1050 in approval_overlay.rs
    let (tx, _rx) = unbounded_channel::<AppEvent>();
    let tx = AppEventSender::new(tx);
    
    let view = ApprovalOverlay::new(
        ApprovalRequest::Exec {
            thread_id: ThreadId::new(),
            thread_label: Some("Robie [explorer]".to_string()),  // Cross-thread indicator
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

### Related Test for Open Thread Functionality
```rust
#[test]
fn o_opens_source_thread_for_cross_thread_approval() {
    // Lines ~998-1026 in approval_overlay.rs
    let (tx, mut rx) = unbounded_channel::<AppEvent>();
    let tx = AppEventSender::new(tx);
    let thread_id = ThreadId::new();
    
    let mut view = ApprovalOverlay::new(
        ApprovalRequest::Exec {
            thread_id,
            thread_label: Some("Robie [explorer]".to_string()),
            // ...
        },
        tx,
        Features::with_defaults(),
    );

    view.handle_key_event(KeyEvent::new(KeyCode::Char('o'), KeyModifiers::NONE));

    let event = rx.try_recv().expect("expected select-agent-thread event");
    assert_eq!(
        matches!(event, AppEvent::SelectAgentThread(id) if id == thread_id),
        true
    );
}
```

### Related Functions
- `approval_footer_hint()` - Lines 484-500
- `try_handle_shortcut()` - Lines 358-404
- `build_header()` - Lines 502-622

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### External Dependencies

| Dependency | Purpose |
|------------|---------|
| `ratatui` | Terminal UI rendering |
| `codex_protocol` | ThreadId and protocol types |
| `codex_core::features::Features` | Feature flag checking |
| `crossterm` | Keyboard input handling |
| `tokio::sync::mpsc` | Async event channel |

### App Events Emitted

| Event | Trigger |
|-------|---------|
| `SelectAgentThread(thread_id)` | User presses `o` to open source thread |
| `SubmitThreadOp { op: ExecApproval { ... } }` | User approves or aborts |

### Protocol Types Used

```rust
use codex_protocol::ThreadId;
use codex_protocol::protocol::ReviewDecision;
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Potential Risks

1. **Thread Confusion**: Users may approve commands without realizing they're from another thread
2. **Context Loss**: Opening the thread may interrupt current work
3. **Queue Buildup**: Multiple cross-thread approvals could queue up unexpectedly

### Edge Cases

1. **Empty Thread Label**: Falls back to standard approval without thread info
2. **Very Long Labels**: May be truncated in narrow terminals
3. **Unicode in Labels**: Should display correctly but depends on terminal support
4. **Deleted Threads**: Thread may no longer exist when user tries to open it

### Snapshot Content Analysis

The snapshot shows:
```
Would you like to run the following command?

Thread: Robie [explorer]

$ echo hi

› 1. Yes, proceed (y)
  2. No, and tell Codex what to do differently (esc)

Press enter to confirm or esc to cancel or o to open thread
```

Key elements:
- ✅ Clear title
- ✅ Thread label prominently displayed in bold: "Thread: Robie [explorer]"
- ✅ Command shown with `$` prefix
- ✅ Standard approval options
- ✅ Extended footer hint including "o to open thread"

### Improvement Suggestions

1. **Thread Color Coding**: Use consistent colors for thread labels across the UI
2. **Thread Activity Indicator**: Show if the thread is still active or has completed
3. **Quick Preview**: Show a snippet of recent activity from that thread
4. **Batch Approvals**: Allow approving multiple pending requests from the same thread
5. **Thread Icon**: Add visual indicator distinguishing agent threads from main thread
6. **Approval History**: Show previous approvals from this thread for context

### Related Tests

- `cross_thread_footer_hint_mentions_o_shortcut` - Footer hint verification
- `o_opens_source_thread_for_cross_thread_approval` - Navigation functionality
- `ctrl_c_aborts_and_clears_queue` - Abort behavior
