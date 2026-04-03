# approval_overlay_additional_permissions_macos_prompt

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/approval_overlay.rs
- **Snapshot File**: codex_tui__bottom_pane__approval_overlay__tests__approval_overlay_additional_permissions_macos_prompt.snap
- **Test Function**: additional_permissions_macos_prompt_snapshot

## Purpose
This snapshot tests the rendering of the `ApprovalOverlay` when requesting approval for a command that requires macOS-specific permissions. It displays the permission rule line showing macOS automation, preferences, accessibility, calendar, and reminders permissions.

## Source Code Context

### Test Function
```rust
#[test]
fn additional_permissions_macos_prompt_snapshot() {
    let (tx, _rx) = unbounded_channel::<AppEvent>();
    let tx = AppEventSender::new(tx);
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

### Key Structs/Components
- `ApprovalOverlay`: Modal overlay for user approval
- `ApprovalRequest::Exec`: Execution approval request variant
- `PermissionProfile`: Contains macOS-specific permissions
- `MacOsSeatbeltProfileExtensions`: macOS permission extensions
- `format_additional_permissions_rule()`: Formats permission rules for display

## UI Components Involved
- `ApprovalOverlay` (modal container)
- `ListSelectionView` (for action options)
- Title: "Would you like to run the following command?"
- Reason line (italics)
- Permission rule line (cyan colored)
- Command snippet with bash highlighting
- Action options with keyboard shortcuts
- Footer hint with key bindings

## Key Rendering Logic
1. **Header Generation** (`build_header()`):
   - Shows thread label if present
   - Shows reason if provided (in italics)
   - Shows permission rule line from `format_additional_permissions_rule()`
   - Displays command with bash syntax highlighting

2. **Permission Rule Formatting**:
   - macOS preferences: shows "readwrite" or "readonly"
   - macOS automation: lists bundle IDs or "all"
   - macOS accessibility: shown when enabled
   - macOS calendar/reminders: shown when enabled
   - macOS contacts: shows permission level

3. **Action Options** (`exec_options()`):
   - "Yes, proceed" (y)
   - "No, and tell Codex what to do differently" (esc)

## Test Setup Details
- Creates an `ApprovalRequest::Exec` for an `osascript` command
- Sets `reason` to "need macOS automation"
- Provides extensive macOS permissions including:
  - ReadWrite preferences access
  - Automation for Calendar and Notes apps
  - Accessibility access
  - Calendar and Reminders access
- Renders at width 120 pixels

## Dependencies
- `codex_protocol::models::MacOsSeatbeltProfileExtensions`
- `codex_protocol::models::MacOsPreferencesPermission`
- `codex_protocol::models::MacOsAutomationPermission`
- `codex_protocol::models::MacOsContactsPermission`
- `ratatui` for rendering
- `ListSelectionView` for option selection

## Notes
- This snapshot shows macOS-specific permission handling
- The permission rule line can be quite long and wraps appropriately
- Compare with `approval_overlay_additional_permissions_prompt` for non-macOS permissions
- The `execpolicy_amendment` option is hidden when additional permissions are present
