# feedback_view_bug

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/feedback_view.rs
- **Snapshot File**: codex_tui__bottom_pane__feedback_view__tests__feedback_view_bug.snap
- **Test Function**: feedback_view_bug

## Purpose
This snapshot tests the `FeedbackNoteView` rendering when the user selects "bug" as the feedback category. It displays a text input area for describing crashes, errors, hangs, or broken UI/behavior.

## Source Code Context
The snapshot is generated from the `FeedbackNoteView::render()` method with `FeedbackCategory::Bug`:

```rust
#[test]
fn feedback_view_bug() {
    let view = make_view(FeedbackCategory::Bug);
    let rendered = render(&view, 60);
    insta::assert_snapshot!("feedback_view_bug", rendered);
}

fn feedback_title_and_placeholder(category: FeedbackCategory) -> (String, String) {
    match category {
        FeedbackCategory::Bug => (
            "Tell us more (bug)".to_string(),
            "(optional) Write a short description to help us further".to_string(),
        ),
        // ...
    }
}
```

The bug category description from `feedback_selection_params()`:
```rust
make_feedback_item(
    app_event_tx.clone(),
    "bug",
    "Crash, error message, hang, or broken UI/behavior.",
    FeedbackCategory::Bug,
),
```

## UI Components Involved
- `FeedbackNoteView` - Main view component for note entry
- `TextArea` - Multi-line text input widget
- `gutter()` - Cyan "▌ " prefix span

## Key Rendering Logic
The view renders:
1. A title line with cyan gutter: "▌ Tell us more (bug)"
2. An empty input area with cyan gutter
3. A placeholder hint: "(optional) Write a short description to help us further"
4. Footer hint: "Press enter to confirm or esc to go back"

## Test Setup Details
The test creates a `FeedbackNoteView` with:
- Category: `FeedbackCategory::Bug`
- Empty feedback snapshot
- No rollout path
- External audience
- Include logs: true

## Dependencies
- `FeedbackNoteView` - Note entry component
- `FeedbackCategory::Bug` - Bug report category
- `TextArea` - Text input component

## Notes
- Bug reports generate a follow-up issue URL for GitHub issue creation
- For external users: Links to `github.com/openai/codex/issues/new`
- For OpenAI employees: Links to internal Slack channel via `http://go/codex-feedback-internal`
- The thread ID is included in the URL for reference
- Bug classification is stored as "bug" in the feedback system
