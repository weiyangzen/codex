# Approval Overlay - Additional Permissions Prompt Snapshot

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the UI rendering of the `ApprovalOverlay` component when requesting user approval for **filesystem and network permissions**. This scenario occurs when:

- A command needs to read from or write to specific files
- Network access is required for the operation
- The user needs to grant these permissions explicitly for security

The component serves as a security checkpoint, ensuring users understand what file system access and network capabilities they're granting before command execution.

## 2. 功能点目的 (Purpose of the Feature)

The feature being tested serves several security and transparency purposes:

1. **Permission Transparency**: Clearly displays what files will be accessed and whether network is needed
2. **Granular Control**: Shows specific file paths for read and write operations
3. **Security Gate**: Prevents unauthorized file system and network access
4. **Informed Consent**: Provides reason context for why these permissions are needed
5. **Audit Trail**: Records permission grants for security review

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
        additional_permissions: Option<PermissionProfile>,  // Key field
    },
    // ...
}

// From codex_protocol::models
pub struct PermissionProfile {
    pub network: Option<NetworkPermissions>,
    pub file_system: Option<FileSystemPermissions>,
    pub macos: Option<MacOsSeatbeltProfileExtensions>,
}

pub struct FileSystemPermissions {
    pub read: Option<Vec<AbsolutePathBuf>>,
    pub write: Option<Vec<AbsolutePathBuf>>,
}

pub struct NetworkPermissions {
    pub enabled: Option<bool>,
}
```

### Permission Formatting

```rust
pub(crate) fn format_additional_permissions_rule(
    additional_permissions: &PermissionProfile,
) -> Option<String> {
    let mut parts = Vec::new();
    
    // Network permission
    if additional_permissions
        .network
        .as_ref()
        .and_then(|network| network.enabled)
        .unwrap_or(false)
    {
        parts.push("network".to_string());
    }
    
    // File system permissions
    if let Some(file_system) = additional_permissions.file_system.as_ref() {
        if let Some(read) = file_system.read.as_ref() {
            let reads = read
                .iter()
                .map(|path| format!("`{}`", path.display()))
                .collect::<Vec<_>>()
                .join(", ");
            parts.push(format!("read {reads}"));
        }
        if let Some(write) = file_system.write.as_ref() {
            let writes = write
                .iter()
                .map(|path| format!("`{}`", path.display()))
                .collect::<Vec<_>>()
                .join(", ");
            parts.push(format!("write {writes}"));
        }
    }
    
    // macOS permissions (handled in separate test)
    // ...
    
    if parts.is_empty() { None } else { Some(parts.join("; ")) }
}
```

### Header Construction

```rust
fn build_header(request: &ApprovalRequest) -> Box<dyn Renderable> {
    match request {
        ApprovalRequest::Exec {
            reason,
            command,
            additional_permissions,
            ..
        } => {
            let mut header: Vec<Line<'static>> = Vec::new();
            
            // Thread label (if cross-thread)
            if let Some(thread_label) = thread_label {
                header.push(Line::from(vec!["Thread: ".into(), thread_label.clone().bold()]));
                header.push(Line::from(""));
            }
            
            // Reason
            if let Some(reason) = reason {
                header.push(Line::from(vec!["Reason: ".into(), reason.clone().italic()]));
                header.push(Line::from(""));
            }
            
            // Permission rule line
            if let Some(additional_permissions) = additional_permissions
                && let Some(rule_line) = format_additional_permissions_rule(additional_permissions)
            {
                header.push(Line::from(vec![
                    "Permission rule: ".into(),
                    rule_line.cyan(),
                ]));
                header.push(Line::from(""));
            }
            
            // Command with syntax highlighting
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

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Source File
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/approval_overlay.rs`

### Test Function
```rust
#[test]
fn additional_permissions_prompt_snapshot() {
    // Lines ~1351-1380 in approval_overlay.rs
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

### Path Normalization Helper
```rust
fn normalize_snapshot_paths(rendered: String) -> String {
    // Lines ~927-936 in approval_overlay.rs
    [
        (absolute_path("/tmp/readme.txt"), "/tmp/readme.txt"),
        (absolute_path("/tmp/out.txt"), "/tmp/out.txt"),
    ]
    .into_iter()
    .fold(rendered, |rendered, (path, normalized)| {
        rendered.replace(&path.display().to_string(), normalized)
    })
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
| `codex_utils_absolute_path::AbsolutePathBuf` | Path handling |
| `crossterm` | Keyboard input handling |

### Protocol Types Used

```rust
use codex_protocol::models::{
    FileSystemPermissions,
    NetworkPermissions,
    PermissionProfile,
};
use codex_protocol::protocol::ReviewDecision;
use codex_utils_absolute_path::AbsolutePathBuf;
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

1. **Path Injection**: Malicious commands might try to access sensitive paths
2. **Permission Scope Creep**: Users may not notice when additional paths are added
3. **Path Display Truncation**: Long paths may be truncated in narrow terminals

### Edge Cases

1. **Many Files**: Lists with many files could exceed display height
2. **Special Characters**: Paths with special characters need proper escaping
3. **Absolute vs Relative**: The formatter uses absolute paths for clarity
4. **Non-existent Files**: The overlay doesn't verify file existence before display

### Snapshot Content Analysis

The snapshot shows:
```
Would you like to run the following command?

Reason: need filesystem access

Permission rule: network; read `/tmp/readme.txt`; write `/tmp/out.txt`

$ cat /tmp/readme.txt

› 1. Yes, proceed (y)
  2. No, and tell Codex what to do differently (esc)

Press enter to confirm or esc to cancel
```

Key elements:
- ✅ Clear title asking for approval
- ✅ Reason shown in italic
- ✅ Permission rule with cyan highlighting
- ✅ Backtick-wrapped paths for clarity
- ✅ Command displayed with `$` prefix
- ✅ Two action options with keyboard shortcuts
- ✅ Footer hint for confirmation

### Improvement Suggestions

1. **Path Grouping**: Group read and write permissions visually
2. **File Type Icons**: Show icons indicating file types
3. **Path Validation**: Show warnings if paths don't exist
4. **Wildcard Detection**: Highlight and explain wildcard patterns
5. **Directory Indicators**: Clearly mark directory vs file access
6. **Permission Summary**: Show a summary count ("3 files to read, 1 to write")

### Related Tests

- `additional_permissions_macos_prompt_snapshot` - macOS-specific permissions
- `additional_permissions_prompt_shows_permission_rule_line` - Rule line presence
- `additional_permissions_exec_options_hide_execpolicy_amendment` - Option filtering
- `exec_history_cell_wraps_with_two_space_indent` - History cell formatting
