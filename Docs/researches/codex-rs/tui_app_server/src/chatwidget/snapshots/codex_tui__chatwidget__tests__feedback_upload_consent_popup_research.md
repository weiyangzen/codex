# Research: Feedback Upload Consent Popup

## 1. 场景与职责 (Scene and Responsibility)

This snapshot captures the **log upload consent popup for bug feedback**. After a user selects a feedback category (in this case, likely "bug"), this popup requests explicit consent to upload session logs to help with debugging.

**Scene Context:**
- User has selected a feedback category (Bug)
- The system is requesting permission to upload diagnostic information
- Connectivity diagnostics are displayed to provide context
- User must explicitly opt-in before any data leaves their machine

**Responsibilities:**
- Obtain explicit user consent for log upload
- Transparently display what files will be uploaded
- Show relevant diagnostics that might affect the issue
- Provide clear options for user choice

## 2. 功能点目的 (Functional Purpose)

The upload consent popup serves to:

1. **Privacy Compliance**: Ensure users explicitly consent to data sharing
2. **Debugging Support**: Collect logs that help reproduce and fix issues
3. **Context Awareness**: Include diagnostics that explain the environment
4. **User Empowerment**: Give users control over their data

**Key Features Shown:**
- **Files to Upload**: `codex-logs.log`, `codex-connectivity-diagnostics.txt`
- **Diagnostics Section**: Shows OPENAI_BASE_URL configuration that may affect connectivity
- **Clear Options**: "Yes" with explanation, or "No"
- **Keyboard Navigation**: Enter to confirm, Esc to go back

## 3. 具体技术实现 (Technical Implementation)

### Key Data Structures

```rust
// From codex_feedback crate
pub struct FeedbackDiagnostics {
    diagnostics: Vec<FeedbackDiagnostic>,
}

pub struct FeedbackDiagnostic {
    pub headline: String,
    pub details: Vec<String>,
}

// Consent parameters
pub struct FeedbackUploadConsentParams {
    pub category: FeedbackCategory,
    pub rollout_path: Option<PathBuf>,
    pub diagnostics: FeedbackDiagnostics,
}
```

### Rendering Format

```
  Upload logs?

  The following files will be sent:
    • codex-logs.log
    • codex-connectivity-diagnostics.txt

  Connectivity diagnostics
    - OPENAI_BASE_URL is set and may affect connectivity.
      - OPENAI_BASE_URL = hello

› 1. Yes  Share the current Codex session logs with the team for
          troubleshooting.
  2. No

  Press enter to confirm or esc to go back
```

**Visual Elements:**
- Title: "Upload logs?"
- File list with bullet points (•)
- Diagnostics section with headline and indented details
- Numbered options with the first option selected (›)
- Multi-line option descriptions
- Footer with keyboard shortcuts

### Key Processes

1. **Popup Creation** (from test):
```rust
chat.show_selection_view(crate::bottom_pane::feedback_upload_consent_params(
    chat.app_event_tx.clone(),
    crate::app_event::FeedbackCategory::Bug,  // Bug category
    chat.current_rollout_path.clone(),
    &codex_feedback::feedback_diagnostics::FeedbackDiagnostics::new(vec![
        codex_feedback::feedback_diagnostics::FeedbackDiagnostic {
            headline: "OPENAI_BASE_URL is set and may affect connectivity.".to_string(),
            details: vec!["OPENAI_BASE_URL = hello".to_string()],
        },
    ]),
));
```

2. **User Selection Flow**:
```
Feedback category selected
    ↓
Diagnostics collected from system
    ↓
Consent popup displayed with files and diagnostics
    ↓
User selects Yes or No
    ↓
Feedback submitted (with or without logs)
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files

| File | Description |
|------|-------------|
| `codex-rs/tui/src/chatwidget/tests.rs` | Test `feedback_upload_consent_popup_snapshot` (line ~8132) |
| `codex-rs/tui/src/bottom_pane/mod.rs` | `feedback_upload_consent_params` function |
| `codex-rs/feedback/src/feedback_diagnostics.rs` | Diagnostics collection |

### Key Functions

```rust
// Bottom pane function
pub fn feedback_upload_consent_params(
    app_event_tx: AppEventSender,
    category: FeedbackCategory,
    rollout_path: Option<PathBuf>,
    diagnostics: &FeedbackDiagnostics,
) -> SelectionViewParams

// Test helper
fn render_bottom_popup(chat: &ChatWidget, width: u16) -> String
```

### Related Snapshots
- `feedback_selection_popup.snap` - Category selection (previous step)
- `feedback_upload_consent_popup.snap` - This file (Bug category)
- `feedback_good_result_consent_popup.snap` - Good result category variant

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Internal Dependencies

- `FeedbackDiagnostics`: System information collection
- `current_rollout_path`: Session log file location
- `FeedbackCategory`: Determines the feedback context
- `SelectionView`: UI component for consent dialog

### File Dependencies

```
~/.codex/
├── codex-logs.log                    # Main session logs
└── codex-connectivity-diagnostics.txt # Connectivity diagnostics
```

### Data Flow

```
Feedback category selected
    ↓
Collect diagnostics:
  - Check environment variables
  - Check network connectivity
  - Gather system info
    ↓
Build consent popup
    ↓
Display files and diagnostics
    ↓
User consent decision
    ↓
If Yes: Read files → Upload to feedback service
If No: Submit feedback without logs
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks

1. **Sensitive Data Exposure**: Logs may contain API keys, file paths, or code
2. **Large File Uploads**: Session logs can grow very large
3. **Network Privacy**: Upload reveals IP address and timestamp
4. **User Deterrence**: Asking for consent may reduce feedback volume

### Edge Cases

1. **Missing Files**: Log files deleted or never created
2. **Permission Errors**: Cannot read log files due to permissions
3. **Very Long Diagnostics**: Diagnostics exceed display capacity
4. **Upload Failures**: Network errors during upload
5. **Concurrent Sessions**: Multiple Codex instances writing logs

### Improvement Suggestions

1. **Log Sanitization**: Automatically redact API keys and sensitive paths
2. **Size Limits**: Warn if logs exceed reasonable size (e.g., >10MB)
3. **Preview Mode**: Allow users to review logs before uploading
4. **Selective Upload**: Choose which log segments to include
5. **Anonymous Upload**: Strip identifying information option
6. **Local Copy**: Save feedback locally if upload fails
7. **Progress Indicator**: Show upload progress for large files
8. **Success Confirmation**: Clear confirmation when upload completes
9. **Retry Logic**: Allow retry if upload fails
10. **Opt-out Memory**: Remember user preference for future feedback
