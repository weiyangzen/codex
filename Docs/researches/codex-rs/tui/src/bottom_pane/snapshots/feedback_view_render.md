# feedback_view_render

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/feedback_view.rs
- **Snapshot File**: codex_tui__bottom_pane__feedback_view__tests__feedback_view_render.snap
- **Test Function**: feedback_view_render (implied from the main feedback flow)

## Purpose
This snapshot tests the log upload consent view for feedback submission. It displays a confirmation dialog asking the user whether they want to upload session logs before reporting an issue, with details about what data will be shared.

## Source Code Context
The snapshot is generated from `feedback_upload_consent_params()` function which creates a `SelectionViewParams` with:
- Header showing files to be uploaded (codex-logs.log, rollout file if present)
- Yes/No/Cancel options with descriptions
- Connectivity diagnostics display when applicable

```rust
pub(crate) fn feedback_upload_consent_params(
    app_event_tx: AppEventSender,
    category: FeedbackCategory,
    rollout_path: Option<std::path::PathBuf>,
    feedback_diagnostics: &FeedbackDiagnostics,
) -> super::SelectionViewParams {
    // Builds header with file list
    let mut header_lines: Vec<Box<dyn crate::render::renderable::Renderable>> = vec![
        Line::from("Upload logs?".bold()).into(),
        Line::from("").into(),
        Line::from("The following files will be sent:".dim()).into(),
        Line::from(vec!["  • ".into(), "codex-logs.log".into()]).into(),
    ];
    // ... adds rollout path and diagnostics if present
}
```

## UI Components Involved
- `SelectionViewParams` - Configuration for the selection popup
- `SelectionItem` - Yes/No/Cancel options
- `ColumnRenderable` - Header content with file list
- `standard_popup_hint_line()` - Footer hint line

## Key Rendering Logic
The view renders:
1. A bold title "Upload logs?"
2. Explanation text about log retention (90 days)
3. List of files to be uploaded (codex-logs.log, optional rollout file)
4. Three selectable options:
   - Yes: Share logs for troubleshooting
   - No: Submit without logs
   - Cancel: Abort feedback submission
5. Standard popup hint at the bottom

## Test Setup Details
The test creates a feedback upload consent dialog with:
- A log path placeholder (`<LOG_PATH>`)
- Standard file list (codex-logs.log)
- Yes/No/Cancel selection items
- Footer hint line

## Dependencies
- `codex_feedback::FeedbackDiagnostics` - For connectivity diagnostics
- `super::SelectionViewParams` - Popup configuration
- `super::popup_consts::standard_popup_hint_line` - Footer hint
- `crate::render::renderable::ColumnRenderable` - Header rendering

## Notes
- This is the first step in the feedback flow after category selection
- The view is created by `feedback_upload_consent_params()` function
- If connectivity diagnostics are present and category is not GoodResult, they are displayed
- The "Yes" option triggers `OpenFeedbackNote` with `include_logs: true`
- The "No" option triggers `OpenFeedbackNote` with `include_logs: false`
