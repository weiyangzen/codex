# app_link_view_enable_suggestion_with_reason

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/app_link_view.rs
- **Snapshot File**: codex_tui__bottom_pane__app_link_view__tests__app_link_view_enable_suggestion_with_reason.snap
- **Test Function**: enable_suggestion_with_reason_snapshot

## Purpose
This snapshot tests the rendering of the `AppLinkView` component when displaying an app enable suggestion with a reason. It captures the UI state for a tool suggestion flow where the user is prompted to enable an already-installed Google Calendar app, showing the different action buttons available for installed apps.

## Source Code Context

### Test Function
```rust
#[test]
fn enable_suggestion_with_reason_snapshot() {
    let (tx_raw, _rx) = unbounded_channel::<AppEvent>();
    let tx = AppEventSender::new(tx_raw);
    let view = AppLinkView::new(
        AppLinkViewParams {
            app_id: "connector_google_calendar".to_string(),
            title: "Google Calendar".to_string(),
            description: Some("Plan events and schedules.".to_string()),
            instructions: "Enable this app to use it for the current request.".to_string(),
            url: "https://example.test/google-calendar".to_string(),
            is_installed: true,
            is_enabled: false,
            suggest_reason: Some("Plan and reference events from your calendar".to_string()),
            suggestion_type: Some(AppLinkSuggestionType::Enable),
            elicitation_target: Some(suggestion_target()),
        },
        tx,
    );

    assert_snapshot!(
        "app_link_view_enable_suggestion_with_reason",
        render_snapshot(&view, Rect::new(0, 0, 72, view.desired_height(72)))
    );
}
```

### Key Structs/Components
- `AppLinkView`: Main view struct for app linking UI
- `AppLinkViewParams`: Parameters including app metadata
- `AppLinkSuggestionType::Enable`: Indicates this is an enable suggestion flow
- `AppLinkElicitationTarget`: Target for resolving the elicitation

## UI Components Involved
- `AppLinkView` (main container)
- Title display (bold text)
- Description text (dimmed)
- Suggestion reason (italicized)
- Usage hint about `$` prefix
- Instructions text
- Action buttons/list ("Manage on ChatGPT", "Enable app", "Back")
- Keyboard hint footer

## Key Rendering Logic
The view renders different content and actions based on installation state:

1. **For Installed Apps** (shown in this snapshot):
   - Action labels include: "Manage on ChatGPT", "Enable app", "Back"
   - Shows hint about using `$` to insert the app into prompts
   - Instructions focus on enabling for current use

2. **Content Rendering** (from `link_content_lines()` method):
   - Title in bold
   - Description (dimmed) if provided
   - Suggestion reason (italics) if provided
   - Usage hint: "Use $ to insert this app into the prompt."
   - Instructions with note about `/apps` command

3. **Selection indicator**: The `›` character marks the currently selected action

## Test Setup Details
- Creates an `AppLinkView` with Google Calendar app parameters
- Sets `is_installed: true` and `is_enabled: false` (app needs enabling)
- Provides a `suggest_reason` explaining why the app is being suggested
- Sets `suggestion_type` to `Enable` with an elicitation target
- Renders the view at width 72 pixels

## Dependencies
- `codex_protocol::ThreadId`
- `codex_protocol::approvals::ElicitationAction`
- `codex_protocol::mcp::RequestId`
- `ratatui` for rendering
- `textwrap` for text wrapping
- `AppEventSender` for event handling

## Notes
- This snapshot demonstrates the UI for an already-installed app that needs to be enabled
- Compare with `app_link_view_install_suggestion_with_reason` to see the difference between install vs enable flows
- The third action button ("Enable app") is only shown when `is_installed: true`
- Selecting "Enable app" will toggle the enabled state and resolve the elicitation with `ElicitationAction::Accept`
