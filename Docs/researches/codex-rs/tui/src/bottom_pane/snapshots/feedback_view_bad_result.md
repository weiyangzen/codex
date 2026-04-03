# feedback_view_bad_result

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/feedback_view.rs
- **Snapshot File**: codex_tui__bottom_pane__feedback_view__tests__feedback_view_bad_result.snap
- **Test Function**: feedback_view_bad_result

## Purpose
This snapshot tests the `FeedbackNoteView` rendering when the user selects "bad result" as the feedback category. It displays a text input area for providing additional details about an unsatisfactory response.

## Source Code Context
The snapshot is generated from the `FeedbackNoteView::render()` method with `FeedbackCategory::BadResult`:

```rust
#[test]
fn feedback_view_bad_result() {
    let view = make_view(FeedbackCategory::BadResult);
    let rendered = render(&view, 60);
    insta::assert_snapshot!("feedback_view_bad_result", rendered);
}

fn make_view(category: FeedbackCategory) -> FeedbackNoteView {
    let (tx_raw, _rx) = tokio::sync::mpsc::unbounded_channel::<AppEvent>();
    let tx = AppEventSender::new(tx_raw);
    let snapshot = codex_feedback::CodexFeedback::new().snapshot(None);
    FeedbackNoteView::new(
        category,
        snapshot,
        None,
        tx,
        true,
        FeedbackAudience::External,
    )
}
```

The title and placeholder are determined by:
```rust
fn feedback_title_and_placeholder(category: FeedbackCategory) -> (String, String) {
    match category {
        FeedbackCategory::BadResult => (
            "Tell us more (bad result)".to_string(),
            "(optional) Write a short description to help us further".to_string(),
        ),
        // ...
    }
}
```

## UI Components Involved
- `FeedbackNoteView` - Main view component for note entry
- `TextArea` - Multi-line text input widget
- `TextAreaState` - State management for textarea
- `gutter()` - Cyan "▌ " prefix span

## Key Rendering Logic
The view renders:
1. A title line with cyan gutter: "▌ Tell us more (bad result)"
2. An empty input area with cyan gutter
3. A placeholder hint: "(optional) Write a short description to help us further"
4. Footer hint: "Press enter to confirm or esc to go back"

The title is bold, and the placeholder is dimmed to indicate it's optional.

## Test Setup Details
The test creates a `FeedbackNoteView` with:
- Category: `FeedbackCategory::BadResult`
- Empty feedback snapshot
- No rollout path
- External audience
- Include logs: true

## Dependencies
- `FeedbackNoteView` - Note entry component
- `FeedbackCategory` - Enum for feedback types
- `FeedbackAudience` - OpenAiEmployee vs External routing
- `TextArea` - Text input component
- `standard_popup_hint_line()` - Footer hint

## Notes
- This view appears after the user consents to upload logs
- The note is optional - user can press Enter immediately to submit without additional text
- Pressing Esc cancels the feedback submission
- The view uses a cyan "▌ " gutter as a visual indicator for the input area
- The placeholder text encourages users to provide helpful context about the bad result
