# approval_overlay_permissions_prompt

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/approval_overlay.rs
- **Snapshot File**: codex_tui__bottom_pane__approval_overlay__tests__approval_overlay_permissions_prompt.snap
- **Test Function**: permissions_prompt_snapshot

## Purpose
This snapshot tests the rendering of the `ApprovalOverlay` for a standalone permissions request (not tied to a specific command execution). It shows the UI when the agent is requesting permission grants for network and file system access.

## Source Code Context

### Test Function
```rust
#[test]
fn permissions_prompt_snapshot() {
    let (tx, _rx) = unbounded_channel::<AppEvent>();
    let tx = AppEventSender::new(tx);
    let view = ApprovalOverlay::new(make_permissions_request(), tx, Features::with_defaults());
    assert_snapshot!(
        "approval_overlay_permissions_prompt",
        normalize_snapshot_paths(render_overlay_lines(&view, 120))
    );
}

fn make_permissions_request() -> ApprovalRequest {
    ApprovalRequest::Permissions {
        thread_id: ThreadId::new(),
        thread_label: None,
        call_id: "test".to_string(),
        reason: Some("need workspace access".to_string()),
        permissions: RequestPermissionProfile {
            network: Some(NetworkPermissions {
                enabled: Some(true),
            }),
            file_system: Some(FileSystemPermissions {
                read: Some(vec![absolute_path("/tmp/readme.txt")]),
                write: Some(vec![absolute_path("/tmp/out.txt")]),
            }),
        },
    }
}
```

### Key Structs/Components
- `ApprovalOverlay`: Modal overlay for user approval
- `ApprovalRequest::Permissions`: Standalone permissions request variant
- `RequestPermissionProfile`: Permissions being requested
- `permissions_options()`: Generates options for permissions approval

## UI Components Involved
- `ApprovalOverlay` (modal container)
- `ListSelectionView` (for action options)
- Title: "Would you like to grant these permissions?"
- Reason line (italics): "need workspace access"
- Permission rule line (cyan colored)
- Action options with keyboard shortcuts
- Footer hint with key bindings

## Key Rendering Logic
1. **Permissions Request Header** (`build_header()`):
   - Different from Exec requests - no command snippet shown
   - Shows thread label if present
   - Shows reason if provided
   - Shows permission rule from `format_requested_permissions_rule()`

2. **Action Options** (`permissions_options()`):
   - "Yes, grant these permissions" (y)
   - "Yes, grant these permissions for this session" (a)
   - "No, continue without permissions" (n)

3. **Decision Handling** (`handle_permissions_decision()`):
   - `Approved`: Grants permissions for current turn
   - `ApprovedForSession`: Grants permissions for entire session
   - `Denied`: Grants no permissions
   - Creates history cell documenting the grant

## Test Setup Details
- Creates an `ApprovalRequest::Permissions` (not Exec)
- Sets `reason` to "need workspace access"
- Requests permissions:
  - Network access enabled
  - Read access to `/tmp/readme.txt`
  - Write access to `/tmp/out.txt`
- Renders at width 120 pixels
- Uses `normalize_snapshot_paths()` for consistent formatting

## Dependencies
- `codex_protocol::request_permissions::RequestPermissionProfile`
- `codex_protocol::request_permissions::PermissionGrantScope`
- `codex_protocol::models::NetworkPermissions`
- `codex_protocol::models::FileSystemPermissions`
- `ratatui` for rendering

## Notes
- Permissions requests are distinct from exec approval - they don't include a command
- The three options allow fine-grained control over permission scope
- Session-scoped grants use `PermissionGrantScope::Session`
- Turn-scoped grants use `PermissionGrantScope::Turn`
- Compare with exec approval snapshots to see the difference in header content
