# mcp_server_elicitation_approval_form_with_param_summary

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/mcp_server_elicitation.rs
- **Snapshot File**: codex_tui__bottom_pane__mcp_server_elicitation__tests__mcp_server_elicitation_approval_form_with_param_summary.snap
- **Test Function**: mcp_server_elicitation_approval_form_with_param_summary

## Purpose
Tests the MCP tool approval form that displays tool call parameters in a summary format. This snapshot validates the UI when an MCP tool call requires approval and includes parameter display information for user review.

## Source Code Context
```rust
// From format_tool_approval_display_message()
fn format_tool_approval_display_message(
    message: &str,
    approval_display_params: &[McpToolApprovalDisplayParam],
) -> String {
    let message = message.trim();
    if approval_display_params.is_empty() {
        return message.to_string();
    }

    let mut sections = Vec::new();
    if !message.is_empty() {
        sections.push(message.to_string());
    }
    let param_lines = approval_display_params
        .iter()
        .take(APPROVAL_TOOL_PARAM_DISPLAY_LIMIT)
        .map(format_tool_approval_display_param_line)
        .collect::<Vec<_>>();
    if !param_lines.is_empty() {
        sections.push(param_lines.join("\n"));
    }
    let mut message = sections.join("\n\n");
    message.push('\n');
    message
}
```

## UI Components Involved
- `McpServerElicitationOverlay`: Main overlay container
- `McpToolApprovalDisplayParam`: Parameter display metadata
- `format_tool_approval_display_param_line()`: Formats param name/value pairs
- `truncate_text()`: Truncates long parameter values
- Select input with Allow/Cancel options

## Key Rendering Logic
The approval form renders:
1. Field counter "Field 1/1"
2. Approval message "Allow Calendar to create an event"
3. Parameter summary block showing:
   - Calendar: primary
   - Title: Roadmap review
   - Notes: Truncated long text with "..."
4. Selection options with descriptions:
   - "Allow" - "Run the tool and continue."
   - "Cancel" - "Cancel this tool call"
5. Footer hints for submission

## Test Setup Details
The test creates an overlay with approval display parameters and renders it at 120x16 resolution, demonstrating how tool parameters are displayed to users for informed approval decisions.

## Dependencies
- `format_json_compact`: For formatting parameter values
- `truncate_text`: For truncating long values (60 graphemes limit)
- `APPROVAL_TOOL_PARAM_DISPLAY_LIMIT`: Max 3 parameters displayed
- `APPROVAL_TOOL_PARAM_VALUE_TRUNCATE_GRAPHEMES`: 60 char truncation

## Notes
- Parameter values are truncated with "..." if they exceed 60 graphemes
- Parameters are formatted as "DisplayName: Value" pairs
- The approval form provides context about what the tool will do
- Users can see key parameters before deciding to allow or cancel
