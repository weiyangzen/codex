# Research: feedback_view_safety_check Snapshot Test

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the rendering of the `FeedbackNoteView` component for the **Safety Check** feedback category. This specific scenario occurs when:
- A user's legitimate request was blocked by Codex's safety/refusal mechanisms
- Users want to report false positives in safety filtering
- Users believe their benign usage was incorrectly refused

This is a critical feedback path for improving the safety system's accuracy and reducing false positives.

## 2. 功能点目的 (Purpose of the Feature)

The Safety Check feedback feature serves specific purposes:
- **False Positive Reporting**: Allows users to report when legitimate usage is blocked
- **Context Collection**: Gathers details about what was refused and why it should be allowed
- **Safety System Improvement**: Provides data to refine safety check algorithms
- **User Advocacy**: Gives users a voice when they disagree with automated decisions

Category-specific content:
- **Title**: "Tell us more (safety check)"
- **Placeholder**: "(optional) Share what was refused and why it should have been allowed"

The specialized placeholder guides users to provide actionable information for safety team review.

## 3. 具体技术实现 (Technical Implementation Details)

### Category Definition
```rust
FeedbackCategory::SafetyCheck => (
    "Tell us more (safety check)".to_string(),
    "(optional) Share what was refused and why it should have been allowed".to_string(),
)
```

### Rendering Pipeline
1. **Test Setup** (`make_view()` line 628-640):
   - Creates `FeedbackNoteView` with `FeedbackCategory::SafetyCheck`
   - Uses `FeedbackAudience::External` for public user experience
   - Sets `include_logs: true` for comprehensive feedback

2. **Rendering** (`render()` line 598-626):
   - Calculates height based on content
   - Renders to ratatui `Buffer`
   - Converts buffer to string for snapshot comparison

3. **Visual Elements**:
   - Cyan gutter prefix: `▌ `
   - Bold title: "Tell us more (safety check)"
   - Dim placeholder text (truncated in snapshot due to width)
   - Standard hint footer

### Classification Mapping
```rust
fn feedback_classification(category: FeedbackCategory) -> &'static str {
    match category {
        FeedbackCategory::SafetyCheck => "safety_check",
        // ... other variants
    }
}
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Source File
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/feedback_view.rs`

### Key Functions
- `feedback_view_safety_check()` test (line 671-675)
- `feedback_title_and_placeholder()` (line 360-383)
- `FeedbackNoteView::render()` (line 244-333)
- `feedback_classification()` (line 385-393)
- `issue_url_for_category()` (line 395-415) - Returns issue URL for follow-up

### Snapshot File Location
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/snapshots/codex_tui__bottom_pane__feedback_view__tests__feedback_view_safety_check.snap`

### Issue URL Generation
Safety check feedback gets a follow-up URL (unlike GoodResult):
```rust
FeedbackCategory::Bug
| FeedbackCategory::BadResult
| FeedbackCategory::SafetyCheck
| FeedbackCategory::Other => Some(issue_url),
FeedbackCategory::GoodResult => None,
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Internal Dependencies
- `codex_feedback::CodexFeedback` - Core feedback functionality
- `ratatui` - Terminal UI rendering
- `tokio::sync::mpsc` - Async channel for event transmission

### External Services
- **Feedback Upload**: `snapshot.upload_feedback()` with classification "safety_check"
- **GitHub Issues**: External users get directed to `github.com/openai/codex/issues/new`
- **Internal Routing**: OpenAI employees see internal Slack feedback URL

### Data Flow
1. User selects "safety check" category from selection popup
2. System shows upload consent dialog
3. User provides optional note in `FeedbackNoteView`
4. On submit, feedback uploads with:
   - Classification: "safety_check"
   - Optional user note
   - Session logs (if consented)
   - Thread ID for correlation

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks
1. **Sensitive Content**: Users might paste the actual refused content (potentially sensitive) in the feedback
2. **Abuse Vector**: Malicious users could use this to test safety system boundaries
3. **Privacy Leak**: Safety check context might reveal user intent even when refused
4. **Placeholder Truncation**: At 60 chars width, the placeholder is truncated mid-word

### Edge Cases
1. **Empty Feedback**: Users can submit without notes (optional field)
2. **Very Long Explanations**: Textarea clamps at 8 lines, may lose long explanations
3. **Unicode/Emoji**: Not tested in snapshot; may cause rendering issues
4. **Concurrent Safety Events**: Multiple refusals in one session - which one is being reported?

### Improvement Suggestions
1. **Context Auto-Capture**: Automatically include the refused request text (with user consent)
2. **Safety Category Sub-types**: Allow users to categorize false positives (e.g., "medical", "legal", "creative")
3. **Follow-up Communication**: Option for safety team to request more info (with user consent)
4. **Severity Indicator**: Let users indicate if the false positive is blocking critical work
5. **Response Feedback Loop**: Notify users when their safety feedback leads to improvements
6. **Enhanced Testing**:
   - Test with actual refused content samples
   - Test Unicode and special character handling
   - Test accessibility (screen reader compatibility)
   - Test color contrast for the cyan gutter
