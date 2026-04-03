# network_exec_prompt

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/approval_overlay.rs
- **Snapshot File**: codex_tui__bottom_pane__approval_overlay__tests__network_exec_prompt.snap
- **Test Function**: network_exec_prompt_title_includes_host

## Purpose
This snapshot tests the rendering of the `ApprovalOverlay` for a network access approval request. It shows the specialized UI when a command needs network access to a specific host, with options to approve once, for the session, or permanently.

## Source Code Context

### Test Function
```rust
#[test]
fn network_exec_prompt_title_includes_host() {
    let (tx, _rx) = unbounded_channel::<AppEvent>();
    let tx = AppEventSender::new(tx);
    let exec_request = ApprovalRequest::Exec {
        thread_id: ThreadId::new(),
        thread_label: None,
        id: "test".into(),
        command: vec!["curl".into(), "https://example.com".into()],
        reason: Some("network request blocked".into()),
        available_decisions: vec![
            ReviewDecision::Approved,
            ReviewDecision::ApprovedForSession,
            ReviewDecision::NetworkPolicyAmendment {
                network_policy_amendment: NetworkPolicyAmendment {
                    host: "example.com".to_string(),
                    action: NetworkPolicyRuleAction::Allow,
                },
            },
            ReviewDecision::Abort,
        ],
        network_approval_context: Some(NetworkApprovalContext {
            host: "example.com".to_string(),
            protocol: NetworkApprovalProtocol::Https,
        }),
        additional_permissions: None,
    };

    let view = ApprovalOverlay::new(exec_request, tx, Features::with_defaults());
    let mut buf = Buffer::empty(Rect::new(0, 0, 100, view.desired_height(100)));
    view.render(Rect::new(0, 0, 100, view.desired_height(100)), &mut buf);
    assert_snapshot!("network_exec_prompt", format!("{buf:?}"));
    // ... assertions
}
```

### Key Structs/Components
- `ApprovalOverlay`: Modal overlay for user approval
- `ApprovalRequest::Exec`: Execution approval request variant
- `NetworkApprovalContext`: Context for network approval (host, protocol)
- `NetworkPolicyAmendment`: Policy change for future network access
- `NetworkPolicyRuleAction::Allow` / `Deny`: Policy actions

## UI Components Involved
- `ApprovalOverlay` (modal container)
- `ListSelectionView` (for action options)
- Title: "Do you want to approve network access to \"example.com\"?"
- Reason line (italics)
- Action options with keyboard shortcuts:
  - "Yes, just this once" (y)
  - "Yes, and allow this host for this conversation" (a)
  - "Yes, and allow this host in the future" (p)
  - "No, and tell Codex what to do differently" (esc)
- Footer hint with key bindings

## Key Rendering Logic
1. **Network-Specific Title**:
   - When `network_approval_context` is present, title changes from "Would you like to run..." to "Do you want to approve network access to \"host\"?"
   - Command snippet is NOT shown for network approvals

2. **Network-Specific Options** (`exec_options()`):
   - "Yes, just this once" (instead of "Yes, proceed")
   - "Yes, and allow this host for this conversation" (session scope)
   - "Yes, and allow this host in the future" (policy amendment)
   - "No, and tell Codex what to do differently" (abort)

3. **Hidden Elements**:
   - Command line is hidden (unlike regular exec approvals)
   - Execpolicy amendment option is hidden

4. **Policy Amendment**:
   - Creates a `NetworkPolicyAmendment` with host and action
   - Can be Allow (future approvals) or Deny (future blocks)

## Test Setup Details
- Creates an `ApprovalRequest::Exec` for a `curl` command
- Sets `network_approval_context` with host "example.com" and HTTPS protocol
- Sets `reason` to "network request blocked"
- Provides all four network-specific decision options
- Renders at width 100 pixels

## Dependencies
- `codex_protocol::protocol::NetworkApprovalContext`
- `codex_protocol::protocol::NetworkApprovalProtocol`
- `codex_protocol::protocol::NetworkPolicyAmendment`
- `codex_protocol::protocol::NetworkPolicyRuleAction`
- `ratatui` for rendering

## Notes
- Network approvals have a distinct UI from regular command approvals
- The host name is prominently displayed in the title
- Users can create persistent policy rules (allow/block) for hosts
- The 'd' shortcut for deny is intentionally not bound to prevent accidental blocks
- Compare with regular exec approval snapshots to see the UI differences
