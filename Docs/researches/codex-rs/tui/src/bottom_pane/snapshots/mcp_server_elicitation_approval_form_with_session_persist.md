# mcp_server_elicitation_approval_form_with_session_persist

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/mcp_server_elicitation.rs
- **Snapshot File**: codex_tui__bottom_pane__mcp_server_elicitation__tests__mcp_server_elicitation_approval_form_with_session_persist.snap
- **Test Function**: mcp_server_elicitation_approval_form_with_session_persist

## Purpose
Tests the MCP tool approval form with session persistence options. This snapshot validates the UI when an MCP tool supports persisting the approval decision for the current session or permanently, giving users granular control over tool permissions.

## Source Code Context
```rust
// From McpServerElicitationFormRequest::from_event()
if is_tool_approval_action
    && tool_approval_supports_persist_mode(meta.as_ref(), APPROVAL_PERSIST_SESSION_VALUE)
{
    options.push(McpServerElicitationOption {
        label: "Allow for this session".to_string(),
        description: Some(
            "Run the tool and remember this choice for this session.".to_string(),
        ),
        value: Value::String(APPROVAL_ACCEPT_SESSION_VALUE.to_string()),
    });
}
if is_tool_approval_action
    && tool_approval_supports_persist_mode(meta.as_ref(), APPROVAL_PERSIST_ALWAYS_VALUE)
{
    options.push(McpServerElicitationOption {
        label: "Always allow".to_string(),
        description: Some(
            "Run the tool and remember this choice for future tool calls.".to_string(),
        ),
        value: Value::String(APPROVAL_ACCEPT_ALWAYS_VALUE.to_string()),
    });
}
```

## UI Components Involved
- `McpServerElicitationOverlay`: Main overlay container
- `tool_approval_supports_persist_mode()`: Checks if persist modes are available
- Select input with 4 options (Allow, Allow for session, Always allow, Cancel)
- `APPROVAL_ACCEPT_SESSION_VALUE`: "accept_session"
- `APPROVAL_ACCEPT_ALWAYS_VALUE`: "accept_always"

## Key Rendering Logic
The approval form renders four options with descriptions:
1. **Allow** - "Run the tool and continue."
2. **Allow for this session** - "Run the tool and remember this choice for this session."
3. **Always allow** - "Run the tool and remember this choice for future tool calls."
4. **Cancel** - "Cancel this tool call"

The "›" indicator shows the currently selected option (default: first option).

## Test Setup Details
The test creates an overlay with session persistence metadata enabled, demonstrating the full range of approval options available when the server supports persistent permissions.

## Dependencies
- `APPROVAL_PERSIST_KEY`: "persist" metadata key
- `APPROVAL_PERSIST_SESSION_VALUE`: "session"
- `APPROVAL_PERSIST_ALWAYS_VALUE`: "always"
- `tool_approval_supports_persist_mode()`: Validates persist mode support

## Notes
- Session persistence allows users to approve a tool once per session
- "Always allow" persists the decision across sessions
- The persist mode is determined by the `persist` field in approval metadata
- This UI reduces repetitive approval prompts for trusted tools
