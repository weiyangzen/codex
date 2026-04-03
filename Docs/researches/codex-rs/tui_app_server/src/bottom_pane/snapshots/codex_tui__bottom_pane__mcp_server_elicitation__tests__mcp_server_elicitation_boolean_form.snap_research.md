# Research: mcp_server_elicitation_boolean_form Snapshot Test

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the rendering of an MCP (Model Context Protocol) server elicitation form for boolean input. The test ensures that when a tool requires a boolean confirmation (true/false), the UI presents a clear selection interface with labeled options.

**Usage Scenario:**
- Tools requiring simple yes/no or true/false confirmation
- Binary decision points in tool workflows
- Safety confirmations ("Are you sure you want to delete?")
- Feature toggles or enablement questions

## 2. 功能点目的 (Purpose of the Feature)

The boolean form feature serves to:

1. **Binary Input**: Collect true/false values from users
2. **Clear Labeling**: Present "True" and "False" as selectable options
3. **Schema Compliance**: Support JSON Schema boolean types
4. **Default Values**: Respect schema-specified defaults

The test validates that:
- Boolean fields are rendered as a selection list (not text input)
- Options are labeled "True" and "False"
- The field shows as "required" when specified in schema
- Progress indicator shows "(1 required unanswered)" when no selection made

## 3. 具体技术实现 (Technical Implementation)

### Key Implementation Details:

**Boolean Schema Parsing (`parse_field`, lines 579-621):**
```rust
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

**Schema Structure:**
```json
{
    "type": "object",
    "properties": {
        "confirmed": {
            "type": "boolean",
            "title": "Confirm",
            "description": "Approve the pending action."
        }
    },
    "required": ["confirmed"]
}
```

**Field State Management (`McpServerElicitationAnswerState`):**
```rust
#[derive(Default)]
struct McpServerElicitationAnswerState {
    selection: ScrollState,
    draft: ComposerDraft,
    answer_committed: bool,
}
```

For boolean/select fields, `selection.selected_idx` tracks the chosen option.

### Test Setup:
- Creates a form request with a single boolean field "confirmed"
- Field has title "Confirm" and description "Approve the pending action."
- Field is marked as required
- No default value specified
- Renders at 120x16
- Expects "True" and "False" options with no pre-selection

**Test Code:**
```rust
#[test]
fn boolean_form_snapshot() {
    let (tx, _rx) = test_sender();
    let request = McpServerElicitationFormRequest::from_event(
        ThreadId::default(),
        form_request(
            "Allow this request?",
            serde_json::json!({
                "type": "object",
                "properties": {
                    "confirmed": {
                        "type": "boolean",
                        "title": "Confirm",
                        "description": "Approve the pending action.",
                    }
                },
                "required": ["confirmed"],
            }),
            None,
        ),
    )
    .expect("expected supported form");
    let overlay = McpServerElicitationOverlay::new(request, tx, true, false, false);

    insta::assert_snapshot!(
        "mcp_server_elicitation_boolean_form",
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

1. **`parse_field()`** (lines 579-660)
   - Parses boolean schema into `McpServerElicitationField`
   - Creates True/False options
   - Handles default value

2. **`parse_fields_from_schema()`** (lines 552-577)
   - Iterates over schema properties
   - Delegates to type-specific parsers

3. **`McpServerElicitationOverlay::option_rows()`** (lines 923-945)
   - Generates display rows for selection options
   - Adds number prefixes and selection indicators

4. **`McpServerElicitationOverlay::render_input()`** (lines 1291-1313)
   - Renders selection options using `render_rows()`

5. **`McpServerElicitationOverlay::submit_answers()`** (lines 1146-1213)
   - Validates required fields are answered
   - Submits boolean value as JSON

### Test Location:
- **Test Function:** `boolean_form_snapshot()`
- **File:** `codex-rs/tui_app_server/src/bottom_pane/mcp_server_elicitation.rs` (lines 2357-2384)
- **Snapshot:** `codex_tui__bottom_pane__mcp_server_elicitation__tests__mcp_server_elicitation_boolean_form.snap`

### Related Tests:
- `parses_boolean_form_request()`: Unit test for boolean parsing
- `submit_sends_accept_with_typed_content()`: Tests form submission

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Dependencies:

```rust
// External crates
serde_json::Value

// Internal modules
codex_app_server_protocol::McpElicitationPrimitiveSchema
codex_app_server_protocol::McpServerElicitationRequest
```

### Schema Types Supported:

From `McpElicitationPrimitiveSchema`:
- `String` - Text input
- `Boolean` - True/False selection (this test)
- `Enum` - Single/Multi-select
- `Number` - Not supported (returns None)

### Response Format:

When user selects "True":
```rust
Op::ResolveElicitation {
    server_name: "server-1".to_string(),
    request_id: McpRequestId::String("request-1".to_string()),
    decision: ElicitationAction::Accept,
    content: Some(serde_json::json!({
        "confirmed": true,
    })),
    meta: None,
}
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks and Edge Cases:

1. **Ambiguous Defaults**: When no default is specified, nothing is pre-selected
2. **Required Field Validation**: Form cannot submit until a selection is made
3. **Boolean Semantics**: "True"/"False" labels may not match user intent (e.g., "Enable" vs "Disable")
4. **Schema Evolution**: Changing a field from boolean to enum breaks compatibility

### Current Limitations:

1. **Fixed Labels**: Always "True" and "False", not customizable
2. **No Description**: Boolean options don't have individual descriptions
3. **No Toggle UI**: Uses selection list instead of checkbox/toggle switch
4. **Single Boolean Only**: No support for boolean arrays

### Improvement Suggestions:

1. **Custom Labels**: Support schema-defined option labels:
   ```json
   {
       "type": "boolean",
       "enumNames": ["Enable Feature", "Disable Feature"]
   }
   ```

2. **Checkbox UI**: For single boolean fields, use a checkbox:
   ```rust
   if fields.len() == 1 && matches!(fields[0].input, Boolean(_)) {
       render_checkbox(&fields[0]);
   } else {
       render_selection_list(&fields);
   }
   ```

3. **Default Selection**: Auto-select first option for required fields:
   ```rust
   if field.required && default_idx.is_none() {
       default_idx = Some(0);  // Select "True" by default
   }
   ```

4. **Confirmation Style**: For confirmation dialogs, use Yes/No:
   ```rust
   let options = if schema.confirmation_style {
       vec!["Yes".to_string(), "No".to_string()]
   } else {
       vec!["True".to_string(), "False".to_string()]
   };
   ```

5. **Visual Toggle**: Consider a visual toggle switch for boolean fields:
   ```
   [ON]  OFF    (selected)
    ON  [OFF]   (unselected)
   ```

6. **Test Coverage**:
   - Test with default value (true and false)
   - Test with optional boolean field
   - Test submission with both values
   - Test multiple boolean fields in one form
   - Test boolean with enumNames

### Maintenance Notes:

- The snapshot shows "Field 1/1 (1 required unanswered)" indicating required field
- No selection indicator (›) appears because no default is set
- Changes to option labels or field rendering will require snapshot updates
- Boolean is the simplest form input type after approval actions

### Comparison with Other Input Types:

**Boolean (this test):**
```
Field 1/1 (1 required unanswered)
Allow this request?

Confirm
Approve the pending action.
  1. True
  2. False
```

**String Input:**
```
Field 1/1 (1 required unanswered)
Enter your name:

[Text input field]
```

**Enum Selection:**
```
Field 1/1
Choose priority:

  1. Low
  2. Medium
  3. High
```
