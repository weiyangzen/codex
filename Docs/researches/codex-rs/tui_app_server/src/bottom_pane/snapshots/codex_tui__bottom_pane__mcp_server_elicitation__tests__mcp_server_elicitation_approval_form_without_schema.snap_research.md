# Research: mcp_server_elicitation_approval_form_without_schema Snapshot Test

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the rendering of a basic MCP (Model Context Protocol) server tool approval form when no JSON schema is provided. The test ensures that the UI falls back to a simple approval/cancel interface when the tool doesn't specify a detailed input schema.

**Usage Scenario:**
- Simple tool calls that don't require complex user input
- Binary approve/deny decisions without parameters
- Fallback UI when schema parsing fails or is absent
- Quick approval flows for trusted operations

## 2. 功能点目的 (Purpose of the Feature)

The approval form without schema serves to:

1. **Simplicity**: Provide a minimal interface for straightforward approvals
2. **Fallback Behavior**: Handle cases where detailed schema is unavailable
3. **Quick Decisions**: Enable rapid approval for low-risk operations
4. **Universal Compatibility**: Work with any MCP server regardless of schema complexity

The test validates that:
- A simple "Allow" and "Cancel" option are presented
- The form shows "Field 1/1" indicating a single decision point
- Descriptions explain what each option does
- The layout is clean and uncluttered

## 3. 具体技术实现 (Technical Implementation)

### Key Implementation Details:

**Schema Detection (`McpServerElicitationFormRequest::from_parts`, lines 274-282):**
```rust
let is_empty_object_schema = requested_schema.as_object().is_some_and(|schema| {
    schema.get("type").and_then(Value::as_str) == Some("object")
        && schema
            .get("properties")
            .and_then(Value::as_object)
            .is_some_and(serde_json::Map::is_empty)
});
let is_tool_approval_action =
    is_tool_approval && (requested_schema.is_null() || is_empty_object_schema);
```

**Fallback Option Generation (lines 293-356):**
```rust
} else if requested_schema.is_null() || (is_tool_approval && is_empty_object_schema) {
    let mut options = vec![McpServerElicitationOption {
        label: "Allow".to_string(),
        description: Some("Run the tool and continue.".to_string()),
        value: Value::String(APPROVAL_ACCEPT_ONCE_VALUE.to_string()),
    }];
    
    if is_tool_approval_action {
        options.push(McpServerElicitationOption {
            label: "Cancel".to_string(),
            description: Some("Cancel this tool call".to_string()),
            value: Value::String(APPROVAL_CANCEL_VALUE.to_string()),
        });
    } else {
        options.extend([
            McpServerElicitationOption {
                label: "Deny".to_string(),
                description: Some("Decline this tool call and continue.".to_string()),
                value: Value::String(APPROVAL_DECLINE_VALUE.to_string()),
            },
            McpServerElicitationOption {
                label: "Cancel".to_string(),
                description: Some("Cancel this tool call".to_string()),
                value: Value::String(APPROVAL_CANCEL_VALUE.to_string()),
            },
        ]);
    }
    // ...
}
```

**Response Mode:**
```rust
McpServerElicitationResponseMode::ApprovalAction
```

This mode indicates the response should be an approval action rather than form content.

### Test Setup:
- Creates an approval request with `Value::Null` schema (no schema)
- Includes tool approval metadata to trigger approval form
- No persistence options enabled
- Renders at 120x16
- Expects 2 options: Allow and Cancel

**Test Code:**
```rust
#[test]
fn approval_form_tool_approval_snapshot() {
    let (tx, _rx) = test_sender();
    let request = McpServerElicitationFormRequest::from_event(
        ThreadId::default(),
        form_request(
            "Allow this request?",
            empty_object_schema(),  // Returns {"type": "object", "properties": {}}
            tool_approval_meta(&[], None, None),
        ),
    )
    .expect("expected approval fallback");
    let overlay = McpServerElicitationOverlay::new(request, tx, true, false, false);

    insta::assert_snapshot!(
        "mcp_server_elicitation_approval_form_without_schema",
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
   - Detects null or empty schema
   - Falls back to `ApprovalAction` response mode
   - Generates simple Allow/Cancel options

2. **`McpServerElicitationFormRequest::from_event()`** (lines 236-257)
   - Entry point for creating form requests from events
   - Delegates to `from_parts()` for processing

3. **`McpServerElicitationOverlay::render()`** (lines 1380-1452)
   - Renders the approval form
   - Shows field progress and options

4. **`McpServerElicitationOverlay::submit_answers()`** (lines 1146-1213)
   - Handles approval action submission
   - Maps selection to `ElicitationAction`

### Test Location:
- **Test Function:** `approval_form_tool_approval_snapshot()`
- **File:** `codex-rs/tui_app_server/src/bottom_pane/mcp_server_elicitation.rs` (lines 2387-2404)
- **Snapshot:** `codex_tui__bottom_pane__mcp_server_elicitation__tests__mcp_server_elicitation_approval_form_without_schema.snap`

### Related Tests:
- `approval_form_tool_approval_with_persist_options_snapshot()`: Tests with persistence
- `approval_form_tool_approval_with_param_summary_snapshot()`: Tests with parameters
- `missing_schema_uses_approval_actions()`: Unit test for null schema

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Dependencies:

```rust
// External crates
serde_json::Value

// Internal modules
codex_protocol::approvals::ElicitationAction
codex_protocol::approvals::ElicitationRequest
codex_protocol::mcp::RequestId as McpRequestId
```

### Schema Values That Trigger This UI:

1. `Value::Null` - No schema provided
2. `{"type": "object", "properties": {}}` - Empty object schema

### Response Actions:

```rust
match selected_value {
    APPROVAL_ACCEPT_ONCE_VALUE => (ElicitationAction::Accept, None),
    APPROVAL_DECLINE_VALUE => (ElicitationAction::Decline, None),
    APPROVAL_CANCEL_VALUE => (ElicitationAction::Cancel, None),
    _ => (ElicitationAction::Cancel, None),
}
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks and Edge Cases:

1. **Ambiguous Approvals**: Without parameter visibility, users may approve unknown actions
2. **Missing Context**: Simple Allow/Cancel may not provide enough information for informed decisions
3. **Schema Parsing Failures**: If schema parsing fails silently, this fallback may hide important input requirements
4. **Tool Misrepresentation**: Tools might intentionally omit schemas to get simpler approval UI

### Current Limitations:

1. **No Parameter Visibility**: Users cannot see what data will be sent
2. **No Tool Information**: Limited context about what the tool does
3. **Binary Choice**: No "Ask again later" or conditional approval options
4. **No Details Expansion**: Cannot view raw request details

### Improvement Suggestions:

1. **Raw Request Viewer**: Allow viewing raw request details:
   ```rust
   KeyCode::Char('d') => {
       show_raw_request_details(&request);
   }
   ```

2. **Tool Information Display**: Show tool name and description:
   ```rust
   Line::from(vec![
       "Tool: ".dim(),
       request.server_name.bold(),
       " - ".dim(),
       tool_description.dim(),
   ])
   ```

3. **Warn on Missing Schema**: Indicate when schema is absent:
   ```rust
   if requested_schema.is_null() {
       lines.push(Line::from("⚠ No parameter information available".yellow()));
   }
   ```

4. **Require Explicit Confirmation**: For null schema, require double-confirmation:
   ```rust
   if is_first_approval_from_tool {
       show_warning("First time using this tool. Review carefully.");
   }
   ```

5. **Audit Logging**: Log approvals without schema for security review:
   ```rust
   if requested_schema.is_null() {
       audit_log::warn("Approval granted without parameter visibility");
   }
   ```

6. **Test Coverage**:
   - Test with `Value::Null` vs empty object schema
   - Test submission with Allow, Cancel, and Deny (non-tool case)
   - Test behavior when schema parsing fails
   - Test with very long approval messages

### Maintenance Notes:

- The snapshot shows the minimal approval form layout
- Only 2 options compared to 4 in the persistence-enabled version
- The "Deny" option is not shown for tool approvals (only Allow/Cancel)
- Changes to option labels or descriptions will require snapshot updates
- This is the simplest form of MCP elicitation UI

### Comparison with Other Forms:

**Without Schema (this test):**
```
Field 1/1
Allow this request?

› 1. Allow   Run the tool and continue.
  2. Cancel  Cancel this tool call
```

**With Persistence:**
```
Field 1/1
Allow this request?

› 1. Allow                   Run the tool and continue.
  2. Allow for this session  Run the tool and remember...
  3. Always allow            Run the tool and remember...
  4. Cancel                  Cancel this tool call
```

**With Parameters:**
```
Field 1/1
Allow Calendar to create an event

Calendar: primary
Title: Roadmap review

› 1. Allow   Run the tool and continue.
  2. Cancel  Cancel this tool call
```
