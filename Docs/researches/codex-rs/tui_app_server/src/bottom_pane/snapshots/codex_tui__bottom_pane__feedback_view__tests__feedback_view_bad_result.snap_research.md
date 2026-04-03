# Feedback View Bad Result Snapshot Research

## 1. 场景与职责 (Usage Scenario and Responsibility)

This snapshot test validates the **feedback collection UI for "bad result" category**. It tests the `FeedbackNoteView` component when a user selects the "bad result" feedback option, which allows users to report when Codex output was off-target, incorrect, incomplete, or unhelpful.

**Responsibilities:**
- Display feedback category-specific title and placeholder
- Provide text input area for optional detailed description
- Show keyboard hints for submission (Enter) or cancellation (Esc)
- Style the view consistently with TUI design system

## 2. 功能点目的 (Feature Purpose)

The feedback view serves to:
1. **Collect User Feedback**: Gather qualitative feedback about Codex performance
2. **Categorize Issues**: Route feedback to appropriate channels based on category
3. **Optional Details**: Allow users to provide additional context without requiring it
4. **Low Friction**: Simple UI with clear keyboard shortcuts

For "bad result" specifically:
- Title: "Tell us more (bad result)"
- Placeholder: "(optional) Write a short description to help us further"
- Follow-up: Links to GitHub issues for external users, internal channels for employees

## 3. 具体技术实现 (Technical Implementation)

### Component Structure

**`FeedbackNoteView` struct** (lines 49-61):
```rust
pub(crate) struct FeedbackNoteView {
    category: FeedbackCategory,
    snapshot: codex_feedback::FeedbackSnapshot,
    rollout_path: Option<PathBuf>,
    app_event_tx: AppEventSender,
    include_logs: bool,
    feedback_audience: FeedbackAudience,
    
    // UI state
    textarea: TextArea,
    textarea_state: RefCell<TextAreaState>,
    complete: bool,
}
```

### Category Configuration

**`feedback_title_and_placeholder()`** (lines 360-383):
```rust
fn feedback_title_and_placeholder(category: FeedbackCategory) -> (String, String) {
    match category {
        FeedbackCategory::BadResult => (
            "Tell us more (bad result)".to_string(),
            "(optional) Write a short description to help us further".to_string(),
        ),
        FeedbackCategory::GoodResult => /* ... */,
        FeedbackCategory::Bug => /* ... */,
        // ...
    }
}
```

### Rendering

**`render()` method** (lines 244-333):
```rust
impl Renderable for FeedbackNoteView {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        // 1. Render intro lines with title
        let intro_lines = self.intro_lines(area.width);
        for (offset, line) in intro_lines.iter().enumerate() {
            Paragraph::new(line.clone()).render(/* ... */);
        }
        
        // 2. Render input area with gutter
        let input_area = Rect { /* ... */ };
        for row in 0..input_area.height {
            Paragraph::new(Line::from(vec![gutter()])).render(/* ... */);
        }
        
        // 3. Render textarea
        let textarea_rect = Rect { /* ... */ };
        StatefulWidgetRef::render_ref(&(&self.textarea), textarea_rect, buf, &mut state);
        
        // 4. Render placeholder if empty
        if self.textarea.text().is_empty() {
            Paragraph::new(Line::from(placeholder.dim())).render(textarea_rect, buf);
        }
        
        // 5. Render hint line
        Paragraph::new(standard_popup_hint_line()).render(hint_rect, buf);
    }
}
```

### Visual Elements

**Gutter** (lines 356-358):
```rust
fn gutter() -> Span<'static> {
    "▌ ".cyan()
}
```

**Intro lines** (lines 343-347):
```rust
fn intro_lines(&self, _width: u16) -> Vec<Line<'static>> {
    let (title, _) = feedback_title_and_placeholder(self.category);
    vec![Line::from(vec![gutter(), title.bold()])]
}
```

### Expected Output

```
▌ Tell us more (bad result)
▌
▌ (optional) Write a short description to help us further

Press enter to confirm or esc to go back
```

Visual breakdown:
- `▌ ` - Cyan gutter indicator
- `Tell us more (bad result)` - Bold title with category
- `(optional) Write a short description...` - Dim placeholder
- `Press enter to confirm or esc to go back` - Standard popup hint

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary File

| File | Purpose |
|------|---------|
| `codex-rs/tui_app_server/src/bottom_pane/feedback_view.rs` | FeedbackNoteView implementation |

### Key Methods

| Method | Line Range | Purpose |
|--------|------------|---------|
| `new()` | 64-83 | Constructor with category configuration |
| `render()` | 244-333 | Main rendering logic |
| `intro_lines()` | 343-347 | Generates title line |
| `input_height()` | 337-341 | Calculates input area height |
| `feedback_title_and_placeholder()` | 360-383 | Category-specific text |
| `gutter()` | 356-358 | Visual gutter element |

### Test Code

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

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Dependencies

```rust
use codex_feedback::feedback_diagnostics::FeedbackDiagnostics;
use codex_protocol::protocol::SessionSource;
use ratatui::style::Stylize;
```

### External Systems

| System | Interaction |
|--------|-------------|
| `codex_feedback` | Uploads feedback with classification |
| `AppEventSender` | Sends `InsertHistoryCell` events |
| GitHub Issues | External users get issue creation link |
| Internal Slack | OpenAI employees get internal go/link |

### Feedback Upload

**`submit()` method** (lines 85-173):
```rust
fn submit(&mut self) {
    let note = self.textarea.text().trim().to_string();
    let reason_opt = if note.is_empty() { None } else { Some(note.as_str()) };
    
    let result = self.snapshot.upload_feedback(
        classification,      // "bad_result"
        reason_opt,          // Optional user description
        self.include_logs,   // Whether to include logs
        &attachment_paths,
        Some(SessionSource::Cli),
        /*logs_override*/ None,
    );
    
    // Send success/error message to history
    match result {
        Ok(()) => {
            self.app_event_tx.send(AppEvent::InsertHistoryCell(
                history_cell::PlainHistoryCell::new(lines)
            ));
        }
        Err(e) => {
            self.app_event_tx.send(AppEvent::InsertHistoryCell(
                history_cell::new_error_event(format!("Failed to upload feedback: {e}"))
            ));
        }
    }
    self.complete = true;
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
            FeedbackAudience::OpenAiEmployee => slack_feedback_url(thread_id),
            FeedbackAudience::External => {
                format!("{BASE_CLI_BUG_ISSUE_URL}&steps=Uploaded%20thread:%20{thread_id}")
            }
        }),
        FeedbackCategory::GoodResult => None, // No issue for positive feedback
    }
}
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvements)

### Risks

1. **Privacy**: Users may include sensitive info in descriptions
2. **Log Size**: Including logs may create large uploads
3. **Rate Limiting**: Frequent feedback could hit API limits

### Edge Cases

| Case | Handling |
|------|----------|
| Empty description | Submits with `reason_opt: None` |
| Very long description | Textarea limits to reasonable height (max 8 lines) |
| Network failure | Error shown in history, feedback not lost locally |
| Upload in progress | No indication of progress (could add spinner) |

### Category Comparison

| Category | Title | Issue URL |
|----------|-------|-----------|
| BadResult | "Tell us more (bad result)" | Yes |
| GoodResult | "Tell us more (good result)" | No |
| Bug | "Tell us more (bug)" | Yes |
| SafetyCheck | "Tell us more (safety check)" | Yes |
| Other | "Tell us more (other)" | Yes |

### Current Limitations

1. **No Character Limit**: Description could be very long
2. **No Rich Text**: Plain text only
3. **No Attachments**: Can't attach screenshots
4. **No Preview**: Can't review before submitting

### Improvement Suggestions

1. **Character Counter**: Show remaining characters
2. **Markdown Support**: Allow basic formatting
3. **Screenshot Attachment**: Allow image uploads
4. **Preview Mode**: Show what will be submitted
5. **Draft Saving**: Save partial feedback if interrupted
6. **Sentiment Analysis**: Auto-categorize based on description
7. **Follow-up Questions**: Ask clarifying questions for "Other" category

### Testing Considerations

- Test with empty description
- Test with very long description
- Test network failure scenarios
- Test with and without logs
- Test both External and OpenAiEmployee audiences
- Test submission while task is running

### Accessibility

- Gutter color (cyan) may not be visible on all terminals
- No audio feedback on submission
- Keyboard-only interaction (no mouse support)
- Placeholder text may not be read by all screen readers
