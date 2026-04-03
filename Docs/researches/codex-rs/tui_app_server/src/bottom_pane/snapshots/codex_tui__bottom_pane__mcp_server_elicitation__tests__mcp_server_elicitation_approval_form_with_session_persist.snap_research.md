# Research: mcp_server_elicitation_approval_form_with_session_persist Snapshot Test

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the rendering of an MCP (Model Context Protocol) server tool approval form that includes session persistence options. The test ensures that when a tool supports persistent approval (remembering the user's choice), the UI presents options for one-time approval, session-scoped approval, and always-allow approval.

**Usage Scenario:**
- User is asked to approve a tool call from a trusted MCP server
- The tool supports remembering the approval decision
- User can choose to allow once, for the current session, or permanently
- Common for frequently-used tools like file system access, calendar integration, etc.

## 2. 功能点目的 (Purpose of the Feature)

The approval form with session persistence serves to:

1. **User Convenience**: Reduce repetitive approval prompts for trusted tools
2. **Granular Control**: Allow users to scope approvals appropriately (once/session/always)
3. **Security Balance**: Balance convenience with security by making persistence explicit
4. **Clear Communication**: Explain what each persistence option means

The test validates that:
- All four options are displayed: Allow, Allow for this session, Always allow, Cancel
- Each option has a descriptive explanation
- The options are numbered and selectable
- The form indicates this is "Field 1/1" (single-field form)

## 3. 具体技术实现 (Technical Implementation)

### Key Implementation Details:

**Persistence Mode Detection (`tool_approval_supports_persist_mode`, lines 431-447):**
```rust
fn tool_approval_supports_persist_mode(meta: Option<&Value>, expected_mode: &str) -> bool {
    let Some(persist) = meta
        .and_then(Value::as_object)
        .and_then(|meta| meta.get(APPROVAL_PERSIST_KEY))
    else {
        return false;
    };

    match persist {
        Value::String(value) => value == expected_mode,
        Value::Array(values) => values
            .iter()
            .filter_map(Value::as_str)
            .any(|value| value == expected_mode),
        _ => false,
    }
}
```

**Option Generation (`McpServerElicitationFormRequest::from_parts`, lines 293-356):**
```rust
let mut options = vec![McpServerElicitationOption {
    label: "Allow".to_string(),
    description: Some("Run the tool and continue.".to_string()),
    value: Value::String(APPROVAL_ACCEPT_ONCE_VALUE.to_string()),
}];

if is_tool_approval_action && tool_approval_supports_persist_mode(meta.as_ref(), APPROVAL_PERSIST_SESSION_VALUE) {
    options.push(McpServerElicitationOption {
        label: "Allow for this session".to_string(),
        description: Some("Run the tool and remember this choice for this session.".to_string()),
        value: Value::String(APPROVAL_ACCEPT_SESSION_VALUE.to_string()),
    });
}

if is_tool_approval_action && tool_approval_supports_persist_mode(meta.as_ref(), APPROVAL_PERSIST_ALWAYS_VALUE) {
    options.push(McpServerElicitationOption {
        label: "Always allow".to_string(),
        description: Some("Run the tool and remember this choice for future tool calls.".to_string()),
        value: Value::String(APPROVAL_ACCEPT_ALWAYS_VALUE.to_string()),
    });
}

options.push(McpServerElicitationOption {
    label: "Cancel".to_string(),
    description: Some("Cancel this tool call".to_string()),
    value: Value::String(APPROVAL_CANCEL_VALUE.to_string()),
});
```

**Constants:**
```rust
const APPROVAL_ACCEPT_ONCE_VALUE: &str = "accept";
const APPROVAL_ACCEPT_SESSION_VALUE: &str = "accept_session";
const APPROVAL_ACCEPT_ALWAYS_VALUE: &str = "accept_always";
const APPROVAL_CANCEL_VALUE: &str = "cancel";
const APPROVAL_PERSIST_KEY: &str = "persist";
const APPROVAL_PERSIST_SESSION_VALUE: &str = "session";
const APPROVAL_PERSIST_ALWAYS_VALUE: &str = "always";
```

### Test Setup:
- Creates an approval request with persistence metadata
- Metadata indicates support for both "session" and "always" persistence modes
- Renders at 120x16
- Expects 4 options: Allow, Allow for this session, Always allow, Cancel

**Test Code:**
```rust
#[test]
fn approval_form_tool_approval_with_persist_options_snapshot() {
    let (tx, _rx) = test_sender();
    let request = McpServerElicitationFormRequest::from_event(
        ThreadId::default(),
        form_request(
            "Allow this request?",
            empty_object_schema(),
            tool_approval_meta(
                &[
                    APPROVAL_PERSIST_SESSION_VALUE,
                    APPROVAL_PERSIST_ALWAYS_VALUE,
                ],
                None,
                None,
            ),
        ),
    )
    .expect("expected approval fallback");
    let overlay = McpServerElicitationOverlay::new(request, tx, true, false, false);

    insta::assert_snapshot!(
        "mcp_server_elicitation_approval_form_with_session_persist",
        render_snapshot(&overlay, Rect::new(0, 0, 120, 16))
    );
}
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files:

| File | Path | Description |
|------|------|-------------|
| `mcp_server_elicitation.rs` | `codex-rs/tui_app_server/src/bottom_pane/mcp_server_elicitation.rs` | Main component implementation |

### Key Functions:

1. **`McpServerElicitationFormRequest::from_parts()`** (lines 259-374)
   - Parses approval metadata
   - Determines which persistence options to show
   - Constructs the `McpServerElicitationField` with options

2. **`tool_approval_supports_persist_mode()`** (lines 431-447)
   - Checks if a specific persistence mode is supported
   - Handles both string and array formats in metadata

3. **`McpServerElicitationOverlay::render_input()`** (lines 1291-1313)
   - Renders the selection options
   - Uses `render_rows()` for consistent styling

4. **`McpServerElicitationOverlay::submit_answers()`** (lines 1146-1213)
   - Handles submission with persistence metadata
   - Sets appropriate `meta` field based on selection

### Test Location:
- **Test Function:** `approval_form_tool_approval_with_persist_options_snapshot()`
- **File:** `codex-rs/tui_app_server/src/bottom_pane/mcp_server_elicitation.rs` (lines 2407-2431)
- **Snapshot:** `codex_tui__bottom_pane__mcp_server_elicitation__tests__mcp_server_elicitation_approval_form_with_session_persist.snap`

### Related Tests:
- `approval_form_tool_approval_snapshot()`: Tests without persistence options
- `empty_tool_approval_schema_session_choice_sets_persist_meta()`: Tests submission with session persist
- `empty_tool_approval_schema_always_allow_sets_persist_meta()`: Tests submission with always persist

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Dependencies:

```rust
// External crates
serde_json::Value

// Internal modules
codex_protocol::approvals::ElicitationAction
codex_app_server_protocol::McpServerElicitationRequest
```

### Metadata Structure:

```json
{
    "codex_approval_kind": "mcp_tool_call",
    "persist": ["session", "always"]
}
```

Or with single value:
```json
{
    "codex_approval_kind": "mcp_tool_call",
    "persist": "session"
}
```

### Response Format:

When user selects "Allow for this session":
```rust
ElicitationAction::Accept,
Some(serde_json::json!({
    "persist": "session",
}))
```

When user selects "Always allow":
```rust
ElicitationAction::Accept,
Some(serde_json::json!({
    "persist": "always",
}))
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks and Edge Cases:

1. **Metadata Tampering**: Malicious servers could claim to support persistence inappropriately
2. **User Confusion**: Users may not understand the difference between "session" and "always"
3. **Accidental Always-Allow**: Users might select "always" without understanding the implications
4. **Revocation**: No UI for revoking previously granted "always" permissions

### Current Limitations:

1. **No Persistence Review**: Users cannot see what they've "always allowed"
2. **No Granularity**: "Always" applies to all calls from the tool, not specific operations
3. **No Time Limits**: No option for "allow for 1 hour" or similar time-based scopes
4. **Fixed Descriptions**: Option descriptions are hardcoded, not customizable per-tool

### Improvement Suggestions:

1. **Confirmation for Always-Allow**: Add extra confirmation for the most permissive option:
   ```rust
   if selected_value == APPROVAL_ACCEPT_ALWAYS_VALUE {
       show_confirmation_dialog(
           "Are you sure?",
           "This will allow all future calls from this tool without prompting."
       );
   }
   ```

2. **Permission Management UI**: Add a way to review and revoke persisted permissions:
   ```rust
   // New command
   /manage-permissions
   // Shows list of all "always allowed" tools with option to revoke
   ```

3. **Tool-Specific Descriptions**: Allow tools to provide custom persistence descriptions:
   ```json
   {
       "persist_descriptions": {
           "session": "Allow for this coding session",
           "always": "Always allow file reads (never for writes)"
       }
   }
   ```

4. **Scoped Persistence**: Support more granular persistence:
   ```rust
   enum PersistScope {
       Once,
       Session,
       Day,
       Week,
       Always,
   }
   ```

5. **Visual Hierarchy**: Emphasize the "Allow" (safest) option:
   ```rust
   // Make "Allow" bold or highlighted
   // Indent or de-emphasize "Always allow"
   ```

6. **Test Coverage**:
   - Test with only "session" persist (not "always")
   - Test with only "always" persist (not "session")
   - Test submission with each option selected
   - Test that "Cancel" doesn't set any persist metadata

### Maintenance Notes:

- The snapshot shows all four options in order
- Option descriptions explain the persistence behavior
- Changes to option labels or descriptions will require snapshot updates
- The test uses `tool_approval_meta(&["session", "always"], ...)` to enable both options
