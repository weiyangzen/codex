# feedback_view_with_connectivity_diagnostics

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/feedback_view.rs
- **Snapshot File**: codex_tui__bottom_pane__feedback_view__tests__feedback_view_with_connectivity_diagnostics.snap
- **Test Function**: feedback_view_with_connectivity_diagnostics

## Purpose
This snapshot tests the `FeedbackNoteView` rendering when connectivity diagnostics are included with the feedback. It demonstrates how network/connection diagnostic information is displayed in the feedback flow.

## Source Code Context
The snapshot is generated from a test that creates a `FeedbackNoteView` with diagnostic data:

```rust
#[test]
fn feedback_view_with_connectivity_diagnostics() {
    let (tx_raw, _rx) = tokio::sync::mpsc::unbounded_channel::<AppEvent>();
    let tx = AppEventSender::new(tx_raw);
    let diagnostics = FeedbackDiagnostics::new(vec![
        FeedbackDiagnostic {
            headline: "Proxy environment variables are set and may affect connectivity."
                .to_string(),
            details: vec!["HTTP_PROXY = http://proxy.example.com:8080".to_string()],
        },
        FeedbackDiagnostic {
            headline: "OPENAI_BASE_URL is set and may affect connectivity.".to_string(),
            details: vec!["OPENAI_BASE_URL = https://example.com/v1".to_string()],
        },
    ]);
    let snapshot = codex_feedback::CodexFeedback::new()
        .snapshot(None)
        .with_feedback_diagnostics(diagnostics);
    let view = FeedbackNoteView::new(
        FeedbackCategory::Bug,
        snapshot,
        None,
        tx,
        false,  // Note: include_logs is false in this test
        FeedbackAudience::External,
    );
    let rendered = render(&view, 60);
    insta::assert_snapshot!("feedback_view_with_connectivity_diagnostics", rendered);
}
```

The diagnostics display logic:
```rust
pub(crate) fn should_show_feedback_connectivity_details(
    category: FeedbackCategory,
    diagnostics: &FeedbackDiagnostics,
) -> bool {
    category != FeedbackCategory::GoodResult && !diagnostics.is_empty()
}
```

## UI Components Involved
- `FeedbackNoteView` - Main view component
- `FeedbackDiagnostics` - Container for diagnostic information
- `FeedbackDiagnostic` - Individual diagnostic entry with headline and details
- `TextArea` - Text input widget

## Key Rendering Logic
The view renders the standard `FeedbackNoteView` UI:
1. Title line: "▌ Tell us more (bug)"
2. Empty input area
3. Placeholder hint
4. Footer hint

Note: The diagnostics are primarily shown in the upload consent view (`feedback_upload_consent_params`), not in the note view itself. The diagnostics are attached to the feedback snapshot for submission.

## Test Setup Details
The test creates a `FeedbackNoteView` with:
- Category: `FeedbackCategory::Bug`
- Feedback snapshot with connectivity diagnostics (proxy vars, OPENAI_BASE_URL)
- No rollout path
- External audience
- Include logs: false (unlike other tests)

## Dependencies
- `FeedbackNoteView` - Note entry component
- `FeedbackDiagnostics` - Diagnostic data container
- `FeedbackDiagnostic` - Individual diagnostic item
- `codex_feedback::CodexFeedback` - Feedback snapshot builder

## Notes
- Connectivity diagnostics are shown in the upload consent dialog, not the note view
- Diagnostics are only shown for non-GoodResult categories
- The test verifies that diagnostics can be attached to feedback without errors
- The `include_logs: false` setting is notable - this test specifically checks diagnostics without log upload
- Diagnostics help troubleshoot connection issues that may be causing problems
