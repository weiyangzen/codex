# Feedback View Bug Snapshot Research

## 1. 场景与职责 (Usage Scenario and Responsibility)

This snapshot test validates the **feedback collection UI for "bug" category**. It tests the `FeedbackNoteView` component when a user selects the "bug" feedback option, which allows users to report crashes, error messages, hangs, or broken UI/behavior.

**Responsibilities:**
- Display bug-specific title and placeholder text
- Collect optional detailed bug description
- Route to appropriate issue tracking (GitHub for external, internal for employees)
- Provide clear submission/cancellation controls

## 2. 功能点目的 (Feature Purpose)

The bug feedback view serves to:
1. **Bug Reporting**: Primary channel for users to report technical issues
2. **Context Collection**: Gather details about crashes, errors, or hangs
3. **Automatic Routing**: Direct bugs to GitHub issues (external) or internal channels (employees)
4. **Log Attachment**: Option to include session logs for debugging

For "bug" specifically:
- Title: "Tell us more (bug)"
- Placeholder: "(optional) Write a short description to help us further"
- Classification: "bug" for backend processing
- Always generates issue URL for follow-up

## 3. 具体技术实现 (Technical Implementation)

### Category Definition

**`FeedbackCategory` enum** (from `app_event.rs`):
```rust
pub enum FeedbackCategory {
    BadResult,
    GoodResult,
    Bug,           // This test
    SafetyCheck,
    Other,
}
```

### Title and Placeholder

**`feedback_title_and_placeholder()`** (lines 360-383 in feedback_view.rs):
```rust
fn feedback_title_and_placeholder(category: FeedbackCategory) -> (String, String) {
    match category {
        FeedbackCategory::Bug => (
            "Tell us more (bug)".to_string(),
            "(optional) Write a short description to help us further".to_string(),
        ),
        // ... other categories
    }
}
```

### Classification Mapping

**`feedback_classification()`** (lines 385-393):
```rust
fn feedback_classification(category: FeedbackCategory) -> &'static str {
    match category {
        FeedbackCategory::BadResult => "bad_result",
        FeedbackCategory::GoodResult => "good_result",
        FeedbackCategory::Bug => "bug",  // Used for upload
        FeedbackCategory::SafetyCheck => "safety_check",
        FeedbackCategory::Other => "other",
    }
}
```

### Issue URL Generation

**`issue_url_for_category()`** (lines 395-415):
```rust
fn issue_url_for_category(
    category: FeedbackCategory,
    thread_id: &str,
    feedback_audience: FeedbackAudience,
) -> Option<String> {
    match category {
        FeedbackCategory::Bug
        | FeedbackCategory::BadResult
        | FeedbackCategory::SafetyCheck
        | FeedbackCategory::Other => Some(match feedback_audience {
            FeedbackAudience::OpenAiEmployee => {
                "http://go/codex-feedback-internal".to_string()
            }
            FeedbackAudience::External => {
                format!(
                    "https://github.com/openai/codex/issues/new?template=3-cli.yml&steps=Uploaded%20thread:%20{thread_id}"
                )
            }
        }),
        FeedbackCategory::GoodResult => None,
    }
}
```

### Rendering

The rendering is identical to other feedback categories, with only the title changing:

```rust
fn intro_lines(&self, _width: u16) -> Vec<Line<'static>> {
    let (title, _) = feedback_title_and_placeholder(self.category);
    vec![Line::from(vec![
        gutter(),           // "▌ "
        title.bold(),       // "Tell us more (bug)"
    ])]
}
```

### Expected Output

```
▌ Tell us more (bug)
▌
▌ (optional) Write a short description to help us further

Press enter to confirm or esc to go back
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary File

| File | Purpose |
|------|---------|
| `codex-rs/tui_app_server/src/bottom_pane/feedback_view.rs` | Complete FeedbackNoteView implementation |

### Related Files

| File | Purpose |
|------|---------|
| `codex-rs/tui_app_server/src/app_event.rs` | FeedbackCategory enum |
| `codex-feedback/src/lib.rs` | Feedback upload functionality |

### Key Functions

| Function | Line Range | Purpose |
|----------|------------|---------|
| `feedback_title_and_placeholder()` | 360-383 | Category-specific UI text |
| `feedback_classification()` | 385-393 | Backend classification |
| `issue_url_for_category()` | 395-415 | Issue routing logic |
| `slack_feedback_url()` | 421-423 | Internal employee URL |

### Test Implementation

```rust
#[test]
fn feedback_view_bug() {
    let view = make_view(FeedbackCategory::Bug);
    let rendered = render(&view, 60);
    insta::assert_snapshot!("feedback_view_bug", rendered);
}
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### External Issue Trackers

| Audience | Destination | URL |
|----------|-------------|-----|
| External | GitHub Issues | `github.com/openai/codex/issues/new?template=3-cli.yml` |
| OpenAI Employee | Internal go/link | `http://go/codex-feedback-internal` |

### Feedback Upload

The `submit()` method handles upload:
```rust
let result = self.snapshot.upload_feedback(
    "bug",  // classification
    reason_opt,
    self.include_logs,
    &attachment_paths,
    Some(SessionSource::Cli),
    None,
);
```

### Post-Submission Flow

1. Upload feedback with classification
2. On success:
   - Generate issue URL based on audience
   - Insert history cell with instructions
   - Include thread ID for reference
3. On failure:
   - Insert error history cell
   - Preserve feedback locally if possible

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvements)

### Bug-Specific Risks

1. **Incomplete Information**: Optional description may lack debugging details
2. **Log Size**: Bug reports often need logs, which can be large
3. **Reproducibility**: Users may not know how to reproduce the bug
4. **Duplicate Reports**: Same bug reported multiple times

### Edge Cases

| Scenario | Handling |
|----------|----------|
| Crash during feedback | Feedback lost, no recovery |
| Empty thread ID | Issue URL still generated |
| Network unavailable | Error shown, can retry |
| Very old session | Logs may be rotated |

### Comparison: Bug vs Bad Result

| Aspect | Bug | Bad Result |
|--------|-----|------------|
| Use case | Crashes, errors | Incorrect output |
| Severity implication | Higher | Lower |
| Logs importance | Critical | Helpful |
| Follow-up urgency | Higher | Normal |
| Template | Same | Same |

### Improvement Suggestions

1. **Bug Template**: Specific prompts for bug reports:
   - "What were you doing when the bug occurred?"
   - "Can you reproduce it? If so, how?"
   - "What did you expect to happen?"
   - "What actually happened?"

2. **Auto-Attach Logs**: Always include logs for bug category
3. **System Info**: Auto-include OS, version, terminal info
4. **Screenshot Prompt**: Suggest attaching screenshot for UI bugs
5. **Severity Selection**: Allow users to indicate severity
6. **Related Issues**: Suggest similar existing issues

### Testing Matrix

| Test | Covered |
|------|---------|
| Basic rendering | ✓ (this test) |
| Empty description | ✗ |
| Long description | ✗ |
| With logs | ✗ |
| Without logs | ✗ |
| External audience | ✓ (default) |
| Employee audience | ✗ |
| Upload success | ✗ |
| Upload failure | ✗ |

### Security Considerations

1. **Log Sanitization**: Ensure logs don't contain sensitive data
2. **URL Safety**: Validate generated URLs
3. **Thread ID Exposure**: Thread IDs in URLs could be guessable
4. **Content Filtering**: Basic filtering of inappropriate content

### Documentation

Users should know:
- What constitutes a bug vs bad result
- That logs may be attached
- How to follow up on their report
- Expected response time
