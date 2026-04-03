# mcp_server_elicitation_approval_form_without_schema

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/mcp_server_elicitation.rs
- **Snapshot File**: codex_tui__bottom_pane__mcp_server_elicitation__tests__mcp_server_elicitation_approval_form_without_schema.snap
- **Test Function**: mcp_server_elicitation_approval_form_without_schema

## Purpose
Tests the MCP tool approval form when no JSON schema is provided (null or empty schema). This snapshot validates the simplified UI for basic tool approvals that don't require parameter input or complex form fields.

## Source Code Context
```rust
// From McpServerElicitationFormRequest::from_event()
let is_tool_approval_action =
    is_tool_approval && (requested_schema.is_null() || is_empty_object_schema);

if requested_schema.is_null() || (is_tool_approval && is_empty_object_schema) {
    let mut options = vec![McpServerElicitationOption {
        label: "Allow".to_string(),
        description: Some("Run the tool and continue.".to_string()),
        value: Value::String(APPROVAL_ACCEPT_ONCE_VALUE.to_string()),
    }];
    // ... add Cancel option
    (
        McpServerElicitationResponseMode::ApprovalAction,
        vec![McpServerElicitationField {
            id: APPROVAL_FIELD_ID.to_string(),
            label: String::new(),
            prompt: String::new(),
            required: true,
            input: McpServerElicitationFieldInput::Select {
                options,
                default_idx: Some(0),
            },
        }],
    )
}
```

## UI Components Involved
- `McpServerElicitationOverlay`: Main overlay container
- `McpServerElicitationResponseMode::ApprovalAction`: Response mode for approvals
- `APPROVAL_FIELD_ID`: "__approval" internal field ID
- Select input with Allow/Cancel options only

## Key Rendering Logic
The simplified approval form renders:
1. Field counter "Field 1/1"
2. Generic prompt "Allow this request?"
3. Two selection options:
   - **Allow** - "Run the tool and continue."
   - **Cancel** - "Cancel this tool call"
4. Footer hints for submission

No parameter summary is shown since there's no schema with parameter definitions.

## Test Setup Details
The test creates an overlay with a null or empty schema, triggering the simplified approval flow that only requires basic Allow/Cancel decisions without additional context.

## Dependencies
- `APPROVAL_ACCEPT_ONCE_VALUE`: "accept" for one-time approval
- `APPROVAL_CANCEL_VALUE`: "cancel"
- `is_empty_object_schema`: Checks for empty object schema

## Notes
- This is the most basic approval form with minimal UI
- Used when tools don't need to collect additional input
- The "Allow" option defaults to selected
- No session persistence options are shown unless explicitly supported
