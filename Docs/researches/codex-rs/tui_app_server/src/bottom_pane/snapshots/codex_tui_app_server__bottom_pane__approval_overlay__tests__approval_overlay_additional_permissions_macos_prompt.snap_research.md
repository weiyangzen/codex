# Approval Overlay - Additional Permissions (macOS) Prompt Snapshot

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the UI rendering of the `ApprovalOverlay` component when requesting user approval for a command that requires **macOS-specific permissions**. This scenario occurs when:

- A command needs elevated macOS privileges (e.g., using `osascript` for automation)
- The command requires specific macOS permissions like:
  - Accessibility access
  - Calendar access
  - Reminders access
  - Automation permissions for specific apps (Calendar, Notes)
  - Preferences read/write access

The component serves as a security gate, ensuring users understand and explicitly approve potentially sensitive system-level operations.

## 2. 功能点目的 (Purpose of the Feature)

The feature being tested serves critical security and transparency purposes:

1. **Security Gate**: Prevents unauthorized execution of sensitive macOS commands
2. **Permission Transparency**: Clearly displays all macOS permissions being requested
3. **Command Visibility**: Shows the exact command that will execute
4. **User Control**: Provides Yes/No options with keyboard shortcuts
5. **Audit Trail**: Records approval decisions for security review

## 3. 具体技术实现 (Technical Implementation)

### Core Data Structures

```rust
// From approval_overlay.rs
pub(crate) enum ApprovalRequest {
    Exec {
        thread_id: ThreadId,
        thread_label: Option<String>,
        id: String,
        command: Vec<String>,
        reason: Option<String>,
        available_decisions: Vec<ReviewDecision>,
        network_approval_context: Option<NetworkApprovalContext>,
        additional_permissions: Option<PermissionProfile>,  // Key field for this test
    },
    // ... other variants
}

// From codex_protocol::models
pub struct MacOsSeatbeltProfileExtensions {
    pub macos_preferences: MacOsPreferencesPermission,
    pub macos_automation: MacOsAutomationPermission,
    pub macos_launch_services: bool,
    pub macos_accessibility: bool,
    pub macos_calendar: bool,
    pub macos_reminders: bool,
    pub macos_contacts: MacOsContactsPermission,
}
```

### Permission Formatting

```rust
pub(crate) fn format_additional_permissions_rule(
    additional_permissions: &PermissionProfile,
) -> Option<String> {
    let mut parts = Vec::new();
    
    // macOS permissions
    if let Some(macos) = additional_permissions.macos.as_ref() {
        // Preferences
        if !matches!(macos.macos_preferences, MacOsPreferencesPermission::ReadOnly) {
            parts.push(format!("macOS preferences {value}"));
        }
        
        // Automation
        match &macos.macos_automation {
            MacOsAutomationPermission::All => parts.push("macOS automation all"),
            MacOsAutomationPermission::BundleIds(bundle_ids) => {
                parts.push(format!("macOS automation {}", bundle_ids.join(", ")));
            }
            _ => {}
        }
        
        // Boolean flags
        if macos.macos_accessibility { parts.push("macOS accessibility"); }
        if macos.macos_calendar { parts.push("macOS calendar"); }
        if macos.macos_reminders { parts.push("macOS reminders"); }
        // ... contacts handling
    }
    
    Some(parts.join("; "))
}
```

### Header Construction

```rust
fn build_header(request: &ApprovalRequest) -> Box<dyn Renderable> {
    match request {
        ApprovalRequest::Exec { reason, command, additional_permissions, .. } => {
            let mut header: Vec<Line<'static>> = Vec::new();
            
            // Reason line (italic)
            if let Some(reason) = reason {
                header.push(Line::from(vec!["Reason: ".into(), reason.clone().italic()]));
            }
            
            // Permission rule line (cyan)
            if let Some(additional_permissions) = additional_permissions
                && let Some(rule_line) = format_additional_permissions_rule(additional_permissions)
            {
                header.push(Line::from(vec![
                    "Permission rule: ".into(),
                    rule_line.cyan(),
                ]));
            }
            
            // Command snippet with syntax highlighting
            let full_cmd = strip_bash_lc_and_escape(command);
            let mut full_cmd_lines = highlight_bash_to_lines(&full_cmd);
            // ...
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
fn additional_permissions_macos_prompt_snapshot() {
    // Lines ~1393-1427 in approval_overlay.rs
    let exec_request = ApprovalRequest::Exec {
        thread_id: ThreadId::new(),
        thread_label: None,
        id: "test".into(),
        command: vec!["osascript".into(), "-e".into(), "tell application".into()],
        reason: Some("need macOS automation".into()),
        available_decisions: vec![ReviewDecision::Approved, ReviewDecision::Abort],
        network_approval_context: None,
        additional_permissions: Some(PermissionProfile {
            macos: Some(MacOsSeatbeltProfileExtensions {
                macos_preferences: MacOsPreferencesPermission::ReadWrite,
                macos_automation: MacOsAutomationPermission::BundleIds(vec![
                    "com.apple.Calendar".to_string(),
                    "com.apple.Notes".to_string(),
                ]),
                macos_launch_services: false,
                macos_accessibility: true,
                macos_calendar: true,
                macos_reminders: true,
                macos_contacts: MacOsContactsPermission::None,
            }),
            ..Default::default()
        }),
    };

    let view = ApprovalOverlay::new(exec_request, tx, Features::with_defaults());
    assert_snapshot!(
        "approval_overlay_additional_permissions_macos_prompt",
        render_overlay_lines(&view, 120)
    );
}
```

### Rendering Helper
```rust
fn render_overlay_lines(view: &ApprovalOverlay, width: u16) -> String {
    // Lines ~911-925 in approval_overlay.rs
    let height = view.desired_height(width);
    let mut buf = Buffer::empty(Rect::new(0, 0, width, height));
    view.render(Rect::new(0, 0, width, height), &mut buf);
    // ... convert buffer to string
}
```

### Related Functions
- `format_additional_permissions_rule()` - Lines 736-813
- `build_header()` - Lines 502-622
- `exec_options()` - Lines 646-734

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### External Dependencies

| Dependency | Purpose |
|------------|---------|
| `ratatui` | Terminal UI rendering |
| `codex_protocol` | Permission models and review decisions |
| `codex_core::features::Features` | Feature flag checking |
| `crossterm` | Keyboard input handling |

### Protocol Types Used

```rust
// From codex_protocol
use codex_protocol::models::{
    MacOsAutomationPermission,
    MacOsContactsPermission,
    MacOsPreferencesPermission,
    MacOsSeatbeltProfileExtensions,
    PermissionProfile,
};
use codex_protocol::protocol::ReviewDecision;
```

### App Events Emitted

On approval (`y` or Enter):
```rust
AppEvent::SubmitThreadOp {
    op: Op::ExecApproval {
        id: "test".to_string(),
        decision: ReviewDecision::Approved,
    }
}
```

On abort (`n` or Esc):
```rust
AppEvent::SubmitThreadOp {
    op: Op::ExecApproval {
        id: "test".to_string(),
        decision: ReviewDecision::Abort,
    }
}
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Potential Risks

1. **Permission Escalation**: Users may not understand the scope of macOS permissions
2. **Automation Abuse**: Malicious commands could exploit automation permissions
3. **Decision Fatigue**: Frequent prompts may lead to users approving without reading

### Edge Cases

1. **Multiple Permission Types**: The formatter handles combinations (network + macOS + filesystem)
2. **Empty Permissions**: Returns `None` when no additional permissions requested
3. **Very Long Bundle ID Lists**: Could overflow display width
4. **Unicode in Bundle IDs**: Not explicitly handled, may affect display

### Snapshot Content Analysis

The snapshot shows:
```
Would you like to run the following command?

Reason: need macOS automation

Permission rule: macOS preferences readwrite; 
  macOS automation com.apple.Calendar, com.apple.Notes; 
  macOS accessibility; macOS calendar; macOS reminders

$ osascript -e 'tell application'

› 1. Yes, proceed (y)
  2. No, and tell Codex what to do differently (esc)

Press enter to confirm or esc to cancel
```

Key elements:
- ✅ Title clearly states action required
- ✅ Reason shown in italic
- ✅ Permission rule in cyan color for visibility
- ✅ Command displayed with bash syntax highlighting
- ✅ Action options with keyboard shortcuts
- ✅ Footer hint for confirmation

### Improvement Suggestions

1. **Permission Icons**: Add visual icons for different permission types
2. **Expandable Details**: Collapse detailed permissions behind an expandable section
3. **Risk Indicators**: Color-code permissions by risk level (red for high-risk)
4. **Remember Choice**: Option to "always allow this command pattern"
5. **Help Text**: Add `?` shortcut to explain what each permission means
6. **Bundle ID Translation**: Show human-readable app names instead of bundle IDs

### Related Tests

- `additional_permissions_prompt_snapshot` - Non-macOS permissions
- `additional_permissions_exec_options_hide_execpolicy_amendment` - Option filtering
- `permissions_options_use_expected_labels` - Permission-only approvals
- `permissions_session_shortcut_submits_session_scope` - Session scoping
