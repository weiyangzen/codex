# feedback_view_safety_check

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/feedback_view.rs
- **Snapshot File**: codex_tui__bottom_pane__feedback_view__tests__feedback_view_safety_check.snap
- **Test Function**: feedback_view_safety_check

## Purpose
This snapshot tests the `FeedbackNoteView` rendering when the user selects "safety check" as the feedback category. It displays a text input area specifically for reporting false positives in safety/refusal checks.

## Source Code Context
The snapshot is generated from the `FeedbackNoteView::render()` method with `FeedbackCategory::SafetyCheck`:

```rust
#[test]
fn feedback_view_safety_check() {
    let view = make_view(FeedbackCategory::SafetyCheck);
    let rendered = render(&view, 60);
    insta::assert_snapshot!("feedback_view_safety_check", rendered);
}

fn feedback_title_and_placeholder(category: FeedbackCategory) -> (String, String) {
    match category {
        FeedbackCategory::SafetyCheck => (
            "Tell us more (safety check)".to_string(),
            "(optional) Share what was refused and why it should have been allowed".to_string(),
        ),
        // ...
    }
}
```

The safety check category description from `feedback_selection_params()`:
```rust
make_feedback_item(
    app_event_tx.clone(),
    "safety check",
    "Benign usage blocked due to safety checks or refusals.",
    FeedbackCategory::SafetyCheck,
),
```

## UI Components Involved
- `FeedbackNoteView` - Main view component for note entry
- `TextArea` - Multi-line text input widget
- `gutter()` - Cyan "▌ " prefix span

## Key Rendering Logic
The view renders:
1. A title line with cyan gutter: "▌ Tell us more (safety check)"
2. An empty input area with cyan gutter
3. A specific placeholder hint: "(optional) Share what was refused and why it should have b" (truncated in 60-char width)
4. Footer hint: "Press enter to confirm or esc to go back"

## Test Setup Details
The test creates a `FeedbackNoteView` with:
- Category: `FeedbackCategory::SafetyCheck`
- Empty feedback snapshot
- No rollout path
- External audience
- Include logs: true

## Dependencies
- `FeedbackNoteView` - Note entry component
- `FeedbackCategory::SafetyCheck` - Safety feedback category
- `TextArea` - Text input component

## Notes
- Safety check feedback has a unique placeholder that specifically asks about what was refused
- This category generates a follow-up issue URL for tracking
- Classification is stored as "safety_check" in the feedback system
- The placeholder text is tailored to help users provide actionable feedback about false positives
