# app_link_view_install_suggestion_with_reason

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/app_link_view.rs
- **Snapshot File**: codex_tui__bottom_pane__app_link_view__tests__app_link_view_install_suggestion_with_reason.snap
- **Test Function**: install_suggestion_with_reason_snapshot

## Purpose
This snapshot tests the rendering of the `AppLinkView` component when displaying an app installation suggestion with a reason. It captures the UI state for a tool suggestion flow where the user is prompted to install the Google Calendar app, including the app title, description, suggestion reason, instructions, and available action buttons.

## Source Code Context

### Test Function
```rust
#[test]
fn install_suggestion_with_reason_snapshot() {
    let (tx_raw, _rx) = unbounded_channel::<AppEvent>();
    let tx = AppEventSender::new(tx_raw);
    let view = AppLinkView::new(
        AppLinkViewParams {
            app_id: "connector_google_calendar".to_string(),
            title: "Google Calendar".to_string(),
            description: Some("Plan events and schedules.".to_string()),
            instructions: "Install this app in your browser, then return here.".to_string(),
            url: "https://example.test/google-calendar".to_string(),
            is_installed: false,
            is_enabled: false,
            suggest_reason: Some("Plan and reference events from your calendar".to_string()),
            suggestion_type: Some(AppLinkSuggestionType::Install),
            elicitation_target: Some(suggestion_target()),
        },
        tx,
    );

    assert_snapshot!(
        "app_link_view_install_suggestion_with_reason",
        render_snapshot(&view, Rect::new(0, 0, 72, view.desired_height(72)))
    );
}
```

### Key Structs/Components
- `AppLinkView`: Main view struct for app linking UI
- `AppLinkViewParams`: Parameters including app metadata (title, description, instructions, URL)
- `AppLinkSuggestionType::Install`: Indicates this is an install suggestion flow
- `AppLinkElicitationTarget`: Target for resolving the elicitation (thread_id, server_name, request_id)

## UI Components Involved
- `AppLinkView` (main container)
- Title display (bold text)
- Description text (dimmed)
- Suggestion reason (italicized)
- Instructions text
- Action buttons/list ("Install on ChatGPT", "Back")
- Keyboard hint footer

## Key Rendering Logic
The view renders different content based on the screen state (`AppLinkScreen::Link` vs `AppLinkScreen::InstallConfirmation`):

1. **Link Screen** (shown in this snapshot):
   - Displays app title in bold
   - Shows description (if provided) in dimmed text
   - Shows suggestion reason (if provided) in italics
   - Displays instructions for installation
   - Shows action buttons: "Install on ChatGPT" and "Back"

2. **Action Labels** (from `action_labels()` method):
   - For non-installed apps: `["Install on ChatGPT", "Back"]`
   - For installed apps: `["Manage on ChatGPT", "Enable/Disable app", "Back"]`

3. **Selection indicator**: The `›` character marks the currently selected action

## Test Setup Details
- Creates an `AppLinkView` with Google Calendar app parameters
- Sets `is_installed: false` and `is_enabled: false`
- Provides a `suggest_reason` explaining why the app is being suggested
- Sets `suggestion_type` to `Install` with an elicitation target
- Renders the view at width 72 pixels

## Dependencies
- `codex_protocol::ThreadId`
- `codex_protocol::approvals::ElicitationAction`
- `codex_protocol::mcp::RequestId`
- `ratatui` for rendering
- `textwrap` for text wrapping
- `AppEventSender` for event handling

## Notes
- This snapshot captures the "Link" screen of the two-screen flow (Link → InstallConfirmation)
- The elicitation target indicates this is part of an MCP (Model Context Protocol) tool suggestion flow
- The UI provides clear instructions about using `$` to insert the app into prompts after installation
- The hint line at the bottom shows keyboard navigation options (Tab/↑/↓ to move, Enter to select, Esc to close)
