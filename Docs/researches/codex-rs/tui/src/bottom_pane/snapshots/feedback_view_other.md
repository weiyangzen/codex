# feedback_view_other

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/feedback_view.rs
- **Snapshot File**: codex_tui__bottom_pane__feedback_view__tests__feedback_view_other.snap
- **Test Function**: feedback_view_other

## Purpose
This snapshot tests the `FeedbackNoteView` rendering when the user selects "other" as the feedback category. It displays a text input area for general feedback including slowness, feature suggestions, or UX feedback.

## Source Code Context
The snapshot is generated from the `FeedbackNoteView::render()` method with `FeedbackCategory::Other`:

```rust
#[test]
fn feedback_view_other() {
    let view = make_view(FeedbackCategory::Other);
    let rendered = render(&view, 60);
    insta::assert_snapshot!("feedback_view_other", rendered);
}

fn feedback_title_and_placeholder(category: FeedbackCategory) -> (String, String) {
    match category {
        FeedbackCategory::Other => (
            "Tell us more (other)".to_string(),
            "(optional) Write a short description to help us further".to_string(),
        ),
        // ...
    }
}
```

The other category description from `feedback_selection_params()`:
```rust
make_feedback_item(
    app_event_tx,
    "other",
    "Slowness, feature suggestion, UX feedback, or anything else.",
    FeedbackCategory::Other,
),
```

## UI Components Involved
- `FeedbackNoteView` - Main view component for note entry
- `TextArea` - Multi-line text input widget
- `gutter()` - Cyan "▌ " prefix span

## Key Rendering Logic
The view renders:
1. A title line with cyan gutter: "▌ Tell us more (other)"
2. An empty input area with cyan gutter
3. A placeholder hint: "(optional) Write a short description to help us further"
4. Footer hint: "Press enter to confirm or esc to go back"

## Test Setup Details
The test creates a `FeedbackNoteView` with:
- Category: `FeedbackCategory::Other`
- Empty feedback snapshot
- No rollout path
- External audience
- Include logs: true

## Dependencies
- `FeedbackNoteView` - Note entry component
- `FeedbackCategory::Other` - General feedback category
- `TextArea` - Text input component

## Notes
- "Other" feedback generates a follow-up issue URL like bug reports
- This is the catch-all category for feedback that doesn't fit other categories
- Classification is stored as "other" in the feedback system
- Users can report slowness, feature suggestions, or general UX feedback
