# mcp_server_elicitation_boolean_form

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/mcp_server_elicitation.rs
- **Snapshot File**: codex_tui__bottom_pane__mcp_server_elicitation__tests__mcp_server_elicitation_boolean_form.snap
- **Test Function**: mcp_server_elicitation_boolean_form

## Purpose
Tests the MCP server elicitation overlay rendering for a boolean-type form field. This snapshot validates the UI when an MCP server requests a simple true/false confirmation from the user, showing the field counter, prompt message, and selectable boolean options.

## Source Code Context
```rust
// From parse_field() in mcp_server_elicitation.rs
McpElicitationPrimitiveSchema::Boolean(schema) => {
    let label = schema.title.unwrap_or_else(|| id.to_string());
    let prompt = schema.description.unwrap_or_else(|| label.clone());
    let default_idx = schema.default.map(|value| if value { 0 } else { 1 });
    let options = [true, false]
        .into_iter()
        .map(|value| {
            let label = if value { "True" } else { "False" }.to_string();
            McpServerElicitationOption {
                label,
                description: None,
                value: Value::Bool(value),
            }
        })
        .collect();
    Some(McpServerElicitationField {
        id: id.to_string(),
        label,
        prompt,
        required,
        input: McpServerElicitationFieldInput::Select {
            options,
            default_idx,
        },
    })
}
```

## UI Components Involved
- `McpServerElicitationOverlay`: Main overlay container
- `McpServerElicitationField`: Boolean field definition with Select input type
- `GenericDisplayRow`: Row rendering for selectable options
- `ScrollState`: Selection state management
- `render_menu_surface()`: Popup surface rendering

## Key Rendering Logic
The overlay renders:
1. Field counter showing "Field 1/1 (1 required unanswered)"
2. Prompt message "Allow this request?"
3. Selectable boolean options with "›" indicator for the selected option
4. Footer hints for submission ("enter to submit | esc to cancel")

Boolean fields are rendered as a Select input with "True" and "False" options, using the `option_rows()` method to format each option with a prefix and number.

## Test Setup Details
The test creates an overlay with a boolean schema field and renders it at 120x16 resolution:
```rust
let overlay = create_test_overlay_with_boolean_field();
render_snapshot(&overlay, Rect::new(0, 0, 120, 16))
```

## Dependencies
- `codex_app_server_protocol`: McpElicitationPrimitiveSchema types
- `codex_protocol`: approvals, ThreadId, McpRequestId
- `ratatui`: Buffer, Rect, rendering widgets
- `serde_json::Value`: For option values
- `selection_popup_common`: GenericDisplayRow, render_rows

## Notes
- Boolean fields use a Select input type rather than a text input
- The default value (if provided in schema) determines initial selection
- Options are numbered (1. True, 2. False) for keyboard navigation
- The field counter shows unanswered required fields count
