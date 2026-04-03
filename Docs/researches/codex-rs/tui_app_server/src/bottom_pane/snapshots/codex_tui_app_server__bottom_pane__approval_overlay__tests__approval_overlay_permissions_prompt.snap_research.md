# Approval Overlay - Permissions Prompt Snapshot

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the UI rendering of the `ApprovalOverlay` component for a **standalone permissions request** (not attached to a command execution). This scenario occurs when:

- The system needs to request additional permissions for a thread
- No specific command is being executed, but capabilities need to be expanded
- The user is asked to grant permissions proactively

The component serves as a permission grant dialog, distinct from command execution approval, focusing solely on capability expansion.

## 2. 功能点目的 (Purpose of the Feature)

The feature being tested serves several permission management purposes:

1. **Proactive Permission Granting**: Allows users to grant permissions before they're needed
2. **Capability Expansion**: Expands what a thread can do without executing a specific command
3. **Granular Control**: Offers permanent, session-scoped, or denied options
4. **Transparency**: Shows exactly what permissions are being requested
5. **Session Management**: Distinguishes between one-time and session-long grants

## 3. 具体技术实现 (Technical Implementation)

### Core Data Structures

```rust
// From approval_overlay.rs
pub(crate) enum ApprovalRequest {
    // ...
    Permissions {
        thread_id: ThreadId,
        thread_label: Option<String>,
        call_id: String,
        reason: Option<String>,
        permissions: RequestPermissionProfile,  // Key field
    },
    // ...
}

// From codex_protocol::request_permissions
pub struct RequestPermissionProfile {
    pub network: Option<NetworkPermissions>,
    pub file_system: Option<FileSystemPermissions>,
}

pub enum PermissionGrantScope {
    Turn,    // One-time grant
    Session, // Grant for entire session
}

pub struct RequestPermissionsResponse {
    pub permissions: RequestPermissionProfile,
    pub scope: PermissionGrantScope,
}
```

### Permission Options

```rust
fn permissions_options() -> Vec<ApprovalOption> {
    vec![
        ApprovalOption {
            label: "Yes, grant these permissions".to_string(),
            decision: ApprovalDecision::Review(ReviewDecision::Approved),
            display_shortcut: None,
            additional_shortcuts: vec![key_hint::plain(KeyCode::Char('y'))],
        },
        ApprovalOption {
            label: "Yes, grant these permissions for this session".to_string(),
            decision: ApprovalDecision::Review(ReviewDecision::ApprovedForSession),
            display_shortcut: None,
            additional_shortcuts: vec![key_hint::plain(KeyCode::Char('a'))],
        },
        ApprovalOption {
            label: "No, continue without permissions".to_string(),
            decision: ApprovalDecision::Review(ReviewDecision::Denied),
            display_shortcut: None,
            additional_shortcuts: vec![key_hint::plain(KeyCode::Char('n'))],
        },
    ]
}
```

### Header Construction for Permissions

```rust
fn build_header(request: &ApprovalRequest) -> Box<dyn Renderable> {
    match request {
        ApprovalRequest::Permissions {
            thread_label,
            reason,
            permissions,
            ..
        } => {
            let mut header: Vec<Line<'static>> = Vec::new();
            
            // Thread label (if cross-thread)
            if let Some(thread_label) = thread_label {
                header.push(Line::from(vec![
                    "Thread: ".into(),
                    thread_label.clone().bold(),
                ]));
                header.push(Line::from(""));
            }
            
            // Reason
            if let Some(reason) = reason {
                header.push(Line::from(vec!["Reason: ".into(), reason.clone().italic()]));
                header.push(Line::from(""));
            }
            
            // Permission rule line
            if let Some(rule_line) = format_requested_permissions_rule(permissions) {
                header.push(Line::from(vec![
                    "Permission rule: ".into(),
                    rule_line.cyan(),
                ]));
            }
            
            Box::new(Paragraph::new(header).wrap(Wrap { trim: false }))
        }
        // ...
    }
}
```

### Decision Handling

```rust
fn handle_permissions_decision(
    &self,
    call_id: &str,
    permissions: &RequestPermissionProfile,
    decision: ReviewDecision,
) {
    let Some(request) = self.current_request.as_ref() else { return };
    
    // Determine granted permissions based on decision
    let granted_permissions = match decision {
        ReviewDecision::Approved | ReviewDecision::ApprovedForSession => permissions.clone(),
        ReviewDecision::Denied | ReviewDecision::Abort => Default::default(),
        _ => Default::default(),
    };
    
    // Determine scope
    let scope = if matches!(decision, ReviewDecision::ApprovedForSession) {
        PermissionGrantScope::Session
    } else {
        PermissionGrantScope::Turn
    };
    
    // Insert history cell for user feedback
    if request.thread_label().is_none() {
        let message = if granted_permissions.is_empty() {
            "You did not grant additional permissions"
        } else if matches!(scope, PermissionGrantScope::Session) {
            "You granted additional permissions for this session"
        } else {
            "You granted additional permissions"
        };
        self.app_event_tx.send(AppEvent::InsertHistoryCell(Box::new(
            crate::history_cell::PlainHistoryCell::new(vec![message.into()]),
        )));
    }
    
    // Send response
    let thread_id = request.thread_id();
    self.app_event_tx.request_permissions_response(
        thread_id,
        call_id.to_string(),
        RequestPermissionsResponse {
            permissions: granted_permissions,
            scope,
        },
    );
}
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Source File
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/approval_overlay.rs`

### Test Function
```rust
#[test]
fn permissions_prompt_snapshot() {
    // Lines ~1382-1391 in approval_overlay.rs
    let (tx, _rx) = unbounded_channel::<AppEvent>();
    let tx = AppEventSender::new(tx);
    
    let view = ApprovalOverlay::new(
        make_permissions_request(),  // Helper function
        tx,
        Features::with_defaults(),
    );
    
    assert_snapshot!(
        "approval_overlay_permissions_prompt",
        normalize_snapshot_paths(render_overlay_lines(&view, 120))
    );
}
```

### Helper Function
```rust
fn make_permissions_request() -> ApprovalRequest {
    // Lines ~951-967 in approval_overlay.rs
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

### Related Functions
- `permissions_options()` - Lines 844-865
- `format_requested_permissions_rule()` - Lines 815-819
- `handle_permissions_decision()` - Lines 272-313

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### External Dependencies

| Dependency | Purpose |
|------------|---------|
| `ratatui` | Terminal UI rendering |
| `codex_protocol` | Permission and review types |
| `codex_core::features::Features` | Feature flag checking |
| `codex_utils_absolute_path::AbsolutePathBuf` | Path handling |

### Protocol Types Used

```rust
use codex_protocol::request_permissions::{
    PermissionGrantScope,
    RequestPermissionProfile,
    RequestPermissionsResponse,
};
use codex_protocol::protocol::ReviewDecision;
```

### App Events Emitted

On approval (`y`):
```rust
AppEvent::SubmitThreadOp {
    op: Op::RequestPermissionsResponse {
        call_id: "test".to_string(),
        response: RequestPermissionsResponse {
            permissions: /* granted permissions */,
            scope: PermissionGrantScope::Turn,
        }
    }
}
```

On session approval (`a`):
```rust
// Same event but with scope: PermissionGrantScope::Session
```

On deny (`n`):
```rust
// Same event but with empty permissions
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Potential Risks

1. **Permission Creep**: Users may grant session permissions without understanding the scope
2. **Confusion with Command Approval**: Users might not distinguish between permission-only and command+permission approvals
3. **Scope Misunderstanding**: "Turn" vs "Session" may not be clear to all users

### Edge Cases

1. **Empty Permissions**: Request with no permissions is handled gracefully
2. **All Denied**: User can continue without any permissions granted
3. **Cross-thread**: Works with thread_label for cross-thread scenarios
4. **Missing Reason**: Component handles reason: None gracefully

### Snapshot Content Analysis

The snapshot shows:
```
Would you like to grant these permissions?

Reason: need workspace access

Permission rule: network; read `/tmp/readme.txt`; write `/tmp/out.txt`

› 1. Yes, grant these permissions (y)
  2. Yes, grant these permissions for this session (a)
  3. No, continue without permissions (n)

Press enter to confirm or esc to cancel
```

Key differences from Exec approval:
- ✅ Title asks about "grant these permissions" not "run command"
- ✅ No command snippet shown (this is permission-only)
- ✅ Three options instead of two (adds session-scoped option)
- ✅ Options use "grant" terminology instead of "proceed"

### Improvement Suggestions

1. **Scope Explanation**: Add tooltip/help explaining "Turn" vs "Session"
2. **Permission Icons**: Visual indicators for different permission types
3. **Impact Preview**: Show what operations will be enabled by these permissions
4. **Remember Choice**: Option to remember this preference for future similar requests
5. **Grouped Display**: Group related permissions (all read paths together, etc.)
6. **Risk Indicators**: Highlight high-risk permissions (write access to system files)

### Related Tests

- `permissions_options_use_expected_labels` - Label verification
- `permissions_session_shortcut_submits_session_scope` - Session scope handling
- `additional_permissions_prompt_snapshot` - Command + permissions variant
