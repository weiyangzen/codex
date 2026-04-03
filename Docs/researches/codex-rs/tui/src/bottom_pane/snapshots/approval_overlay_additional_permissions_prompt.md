# approval_overlay_additional_permissions_prompt

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/approval_overlay.rs
- **Snapshot File**: codex_tui__bottom_pane__approval_overlay__tests__approval_overlay_additional_permissions_prompt.snap
- **Test Function**: additional_permissions_prompt_snapshot

## Purpose
This snapshot tests the rendering of the `ApprovalOverlay` when requesting approval for a command with additional file system and network permissions. It displays the permission rule line showing network access and specific read/write file paths.

## Source Code Context

### Test Function
```rust
#[test]
fn additional_permissions_prompt_snapshot() {
    let (tx, _rx) = unbounded_channel::<AppEvent>();
    let tx = AppEventSender::new(tx);
    let exec_request = ApprovalRequest::Exec {
        thread_id: ThreadId::new(),
        thread_label: None,
        id: "test".into(),
        command: vec!["cat".into(), "/tmp/readme.txt".into()],
        reason: Some("need filesystem access".into()),
        available_decisions: vec![ReviewDecision::Approved, ReviewDecision::Abort],
        network_approval_context: None,
        additional_permissions: Some(PermissionProfile {
            network: Some(NetworkPermissions {
                enabled: Some(true),
            }),
            file_system: Some(FileSystemPermissions {
                read: Some(vec![absolute_path("/tmp/readme.txt")]),
                write: Some(vec![absolute_path("/tmp/out.txt")]),
            }),
            ..Default::default()
        }),
    };

    let view = ApprovalOverlay::new(exec_request, tx, Features::with_defaults());
    assert_snapshot!(
        "approval_overlay_additional_permissions_prompt",
        normalize_snapshot_paths(render_overlay_lines(&view, 120))
    );
}
```

### Key Structs/Components
- `ApprovalOverlay`: Modal overlay for user approval
- `ApprovalRequest::Exec`: Execution approval request variant
- `PermissionProfile`: Contains network and file system permissions
- `NetworkPermissions`: Network access permissions
- `FileSystemPermissions`: File read/write permissions
- `format_additional_permissions_rule()`: Formats permission rules for display

## UI Components Involved
- `ApprovalOverlay` (modal container)
- `ListSelectionView` (for action options)
- Title: "Would you like to run the following command?"
- Reason line (italics)
- Permission rule line (cyan colored): "network; read `/tmp/readme.txt`; write `/tmp/out.txt`"
- Command snippet with bash highlighting
- Action options with keyboard shortcuts
- Footer hint with key bindings

## Key Rendering Logic
1. **Permission Rule Formatting** (`format_additional_permissions_rule()`):
   - Network: shown as "network" when enabled
   - File read: shows "read `path1`, `path2`"
   - File write: shows "write `path1`, `path2`"
   - Multiple permissions separated by "; "

2. **Action Options** (`exec_options()`):
   - When additional permissions are present, the "ApprovedForSession" option label changes to:
     - "Yes, and allow these permissions for this session" (instead of command-specific)
   - "Yes, proceed" (y)
   - "No, and tell Codex what to do differently" (esc)

3. **Header Layout**:
   - Title in bold
   - Reason in italics
   - Permission rule label + value in cyan
   - Command with `$` prefix

## Test Setup Details
- Creates an `ApprovalRequest::Exec` for a `cat` command
- Sets `reason` to "need filesystem access"
- Provides additional permissions:
  - Network access enabled
  - Read access to `/tmp/readme.txt`
  - Write access to `/tmp/out.txt`
- Renders at width 120 pixels
- Uses `normalize_snapshot_paths()` to ensure consistent path formatting

## Dependencies
- `codex_protocol::models::PermissionProfile`
- `codex_protocol::models::NetworkPermissions`
- `codex_protocol::models::FileSystemPermissions`
- `codex_utils_absolute_path::AbsolutePathBuf`
- `ratatui` for rendering

## Notes
- The permission rule line provides a concise summary of granted permissions
- File paths are displayed with backticks for clarity
- Compare with `approval_overlay_additional_permissions_macos_prompt` for macOS-specific permissions
- The `ApprovedExecpolicyAmendment` option is hidden when additional permissions are present
