# Research: feedback_view_with_connectivity_diagnostics Snapshot Test

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the `FeedbackNoteView` rendering when **connectivity diagnostics** are included in the feedback snapshot. This scenario occurs when:
- User reports a bug or connectivity issue
- The system has collected diagnostic information about network/proxy configuration
- Diagnostics help troubleshoot environment-specific connectivity problems

The test specifically uses `FeedbackCategory::Bug` with diagnostics, demonstrating how technical diagnostic data is presented in the feedback UI.

## 2. 功能点目的 (Purpose of the Feature)

The connectivity diagnostics feature serves critical troubleshooting purposes:
- **Environment Detection**: Identifies proxy settings that may affect connectivity
- **Configuration Analysis**: Detects custom `OPENAI_BASE_URL` overrides
- **Root Cause Analysis**: Helps support team understand if issues are environment-specific
- **Proactive Debugging**: Captures relevant info before user submits feedback

Diagnostic data is attached to the feedback snapshot and displayed in the upload consent dialog (not the `FeedbackNoteView` itself, but this test validates the view still renders correctly with diagnostics present).

## 3. 具体技术实现 (Technical Implementation Details)

### Diagnostics Structure
```rust
pub struct FeedbackDiagnostic {
    pub headline: String,  // Summary of the diagnostic finding
    pub details: Vec<String>,  // Detailed information (e.g., env var values)
}

pub struct FeedbackDiagnostics {
    diagnostics: Vec<FeedbackDiagnostic>,
}
```

### Test Setup
The test creates diagnostics with two common connectivity issues:
```rust
let diagnostics = FeedbackDiagnostics::new(vec![
    FeedbackDiagnostic {
        headline: "Proxy environment variables are set and may affect connectivity.".to_string(),
        details: vec!["HTTP_PROXY = http://proxy.example.com:8080".to_string()],
    },
    FeedbackDiagnostic {
        headline: "OPENAI_BASE_URL is set and may affect connectivity.".to_string(),
        details: vec!["OPENAI_BASE_URL = https://example.com/v1".to_string()],
    },
]);
```

### Snapshot Attachment
```rust
let snapshot = codex_feedback::CodexFeedback::new()
    .snapshot(None)
    .with_feedback_diagnostics(diagnostics);
```

### Display Logic
Diagnostics are shown in the upload consent dialog when:
```rust
pub(crate) fn should_show_feedback_connectivity_details(
    category: FeedbackCategory,
    diagnostics: &FeedbackDiagnostics,
) -> bool {
    category != FeedbackCategory::GoodResult && !diagnostics.is_empty()
}
```

Note: Diagnostics are NOT shown for "Good Result" feedback since they're irrelevant for positive feedback.

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Source File
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/feedback_view.rs`

### Key Functions
- `feedback_view_with_connectivity_diagnostics()` test (line 678-706)
- `should_show_feedback_connectivity_details()` (line 349-354)
- `feedback_upload_consent_params()` (line 501-588) - Shows diagnostics in consent dialog
- `FeedbackDiagnostics::new()` - Constructor for diagnostics collection
- `FeedbackSnapshot::with_feedback_diagnostics()` - Attaches diagnostics to snapshot

### Snapshot File Location
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/snapshots/codex_tui__bottom_pane__feedback_view__tests__feedback_view_with_connectivity_diagnostics.snap`

### Related Test
- `should_show_feedback_connectivity_details_only_for_non_good_result_with_diagnostics` (line 709-731)

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Internal Dependencies
- `codex_feedback::feedback_diagnostics::FeedbackDiagnostic` - Diagnostic data structure
- `codex_feedback::feedback_diagnostics::FeedbackDiagnostics` - Diagnostics collection
- `codex_feedback::feedback_diagnostics::FEEDBACK_DIAGNOSTICS_ATTACHMENT_FILENAME` - "feedback-diagnostics.json"

### External Data Sources
Diagnostics are collected from:
- Environment variables (`HTTP_PROXY`, `HTTPS_PROXY`, `OPENAI_BASE_URL`, etc.)
- Network configuration
- Codex configuration state

### File Attachments
When user consents to upload:
1. `codex-logs.log` - Session logs
2. Rollout file (if exists)
3. `feedback-diagnostics.json` - Diagnostics data

### Privacy Considerations
- Diagnostics may contain sensitive network configuration
- Users can opt out by selecting "No" on upload consent
- File list is displayed transparently before upload

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks
1. **Sensitive Data Exposure**: Proxy URLs may contain credentials (e.g., `http://user:pass@proxy:8080`)
2. **Corporate Policy Violation**: Uploading proxy configs may violate corporate security policies
3. **False Positives**: Diagnostics may suggest connectivity issues that aren't actually problems
4. **Information Overload**: Too many diagnostics may overwhelm users

### Edge Cases
1. **Empty Details**: Diagnostics with headlines but no details
2. **Very Long Values**: Environment variables with very long values may break UI
3. **Special Characters**: URLs with special characters may not render correctly
4. **Multiple Proxies**: Both HTTP_PROXY and HTTPS_PROXY set - both should be captured
5. **GoodResult Category**: Diagnostics are intentionally hidden for positive feedback

### Improvement Suggestions
1. **Credential Redaction**: Automatically redact credentials from proxy URLs before display/upload
2. **Diagnostic Categories**: Group diagnostics by type (Proxy, Custom URL, SSL, etc.)
3. **Severity Levels**: Indicate if diagnostics are warnings or just informational
4. **User Education**: Add links to documentation about proxy configuration
5. **Selective Upload**: Allow users to uncheck specific diagnostics before upload
6. **Real-time Detection**: Show connectivity warnings in status bar, not just in feedback
7. **Test Enhancements**:
   - Test credential redaction
   - Test with empty diagnostics
   - Test with very long diagnostic values
   - Test diagnostics with Unicode content
   - Test all feedback categories with diagnostics
