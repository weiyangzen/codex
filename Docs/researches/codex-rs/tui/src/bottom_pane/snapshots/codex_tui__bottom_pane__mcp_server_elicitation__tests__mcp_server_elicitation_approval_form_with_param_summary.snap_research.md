# Research: mcp_server_elicitation_approval_form_with_param_summary

## 1. Feature Overview

This snapshot tests the `McpServerElicitationOverlay` rendering for an MCP tool approval form that includes a parameter summary display. It demonstrates how tool call approvals present both the action message and key tool parameters to help users make informed decisions.

## 2. Code Location

- **Test Function**: `approval_form_tool_approval_with_param_summary_snapshot` in `mcp_server_elicitation.rs` (line ~2389)
- **Source Module**: `codex-rs/tui/src/bottom_pane/mcp_server_elicitation.rs`
- **Related Function**: `format_tool_approval_display_message`

## 3. Snapshot Description

The snapshot shows a 120x16 character approval form for a calendar tool:

```
  Field 1/1
  Allow Calendar to create an event

  Calendar: primary
  Title: Roadmap review
  Notes: This is a deliberately long note that should truncate bef...

  › 1. Allow   Run the tool and continue.
    2. Cancel  Cancel this tool call




  enter to submit | esc to cancel
```

**Layout Sections:**
1. **Progress indicator**: "Field 1/1"
2. **Action message**: "Allow Calendar to create an event"
3. **Parameter summary** (3 parameters displayed):
   - `Calendar: primary`
   - `Title: Roadmap review`
   - `Notes: This is a deliberately long note...` (truncated)
4. **Approval options**:
   - `› 1. Allow` (selected) - "Run the tool and continue."
   - `2. Cancel` - "Cancel this tool call"
5. **Footer hints**: "enter to submit | esc to cancel"

## 4. Key Concepts

### McpToolApprovalDisplayParam

```rust
struct McpToolApprovalDisplayParam {
    name: String,
    value: Value,
    display_name: String,
}
```

### Parameter Display Limit

```rust
const APPROVAL_TOOL_PARAM_DISPLAY_LIMIT: usize = 3;
const APPROVAL_TOOL_PARAM_VALUE_TRUNCATE_GRAPHEMES: usize = 60;
```

- Maximum 3 parameters displayed (4th parameter "ignored_after_limit" is omitted)
- Values longer than 60 graphemes are truncated with ellipsis

### Parameter Formatting

```rust
fn format_tool_approval_display_param_line(param: &McpToolApprovalDisplayParam) -> String {
    format!(
        "{}: {}",
        param.display_name,
        format_tool_approval_display_param_value(&param.value)
    )
}
```

### Approval Options

For tool approval actions, the form presents:
- **Allow**: Run the tool and continue
- **Cancel**: Cancel this tool call

(When persist modes are supported, additional options like "Allow for this session" and "Always allow" may appear.)

## 5. Test Setup

```rust
#[test]
fn approval_form_tool_approval_with_param_summary_snapshot() {
    let (tx, _rx) = test_sender();
    let request = McpServerElicitationFormRequest::from_event(
        ThreadId::default(),
        form_request(
            "Allow Calendar to create an event",
            empty_object_schema(),
            tool_approval_meta(
                &[],  // No persist modes
                Some(serde_json::json!({
                    "calendar_id": "primary",
                    "title": "Roadmap review",
                    "notes": "This is a deliberately long note...",
                    "ignored_after_limit": "fourth param",
                })),
                Some(vec![
                    ("calendar_id", Value::String("primary".to_string()), "Calendar"),
                    ("title", Value::String("Roadmap review".to_string()), "Title"),
                    ("notes", Value::String("This is a deliberately long note...".to_string()), "Notes"),
                    ("ignored_after_limit", Value::String("fourth param".to_string()), "Ignored"),
                ]),
            ),
        ),
    )
    .expect("expected approval fallback");
    let overlay = McpServerElicitationOverlay::new(request, tx, true, false, false);

    insta::assert_snapshot!(
        "mcp_server_elicitation_approval_form_with_param_summary",
        render_snapshot(&overlay, Rect::new(0, 0, 120, 16))
    );
}
```

## 6. Dependencies

- `McpServerElicitationFormRequest::from_event` - Parses elicitation request
- `tool_approval_meta` - Helper to construct approval metadata
- `format_tool_approval_display_message` - Formats message with params
- `parse_tool_approval_display_params` - Extracts display params from metadata
- `APPROVAL_TOOL_PARAMS_DISPLAY_KEY` - Metadata key for explicit display order

## 7. Related Snapshots

| Snapshot | Description |
|----------|-------------|
| `mcp_server_elicitation_approval_form_without_schema` | Basic approval without param summary |
| `mcp_server_elicitation_approval_form_with_session_persist` | Approval with persist options |
| `mcp_server_elicitation_boolean_form` | Boolean form (not approval) |

## 8. Security and UX Considerations

**Parameter Display Purpose:**
- Helps users understand exactly what action they're approving
- Shows critical parameters that affect the tool's behavior
- Truncates long values to prevent UI overflow
- Limits to 3 params to avoid overwhelming users

**Display Name vs. Internal Name:**
- Uses `display_name` for user-friendly labels (e.g., "Calendar" instead of "calendar_id")
- Falls back to internal name if display name not provided

**Truncation Behavior:**
- Long values are truncated with "..." suffix
- This prevents the approval dialog from becoming unreadable due to unexpectedly long parameter values
