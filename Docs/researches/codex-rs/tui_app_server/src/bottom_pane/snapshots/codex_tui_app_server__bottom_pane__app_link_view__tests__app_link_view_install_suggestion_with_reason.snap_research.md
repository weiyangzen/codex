# App Link View - Install Suggestion with Reason Snapshot

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the UI rendering of the `AppLinkView` component when displaying an **install suggestion** for an app that is not yet installed. This scenario occurs when:

- The user attempts to use functionality that requires an app they don't have installed
- The system suggests installing the app (e.g., Google Calendar) to fulfill the request
- A reason is provided explaining why installing would be helpful

The component serves as an interactive dialog that guides users through the app installation flow, from discovery to confirmation.

## 2. 功能点目的 (Purpose of the Feature)

The feature being tested serves several key purposes:

1. **App Discovery & Installation**: Introduces users to apps they don't have and guides installation
2. **Contextual Reasoning**: Displays why the app would be useful ("Plan and reference events from your calendar")
3. **Installation Flow**: Two-step process: open ChatGPT link → confirm installation
4. **Usage Instructions**: Educates users on post-installation usage ("After installed, use $ to insert this app")
5. **Elicitation Resolution**: When triggered by a tool suggestion, resolves with Accept/Decline based on user action

## 3. 具体技术实现 (Technical Implementation)

### Core Data Structures

```rust
// From app_link_view.rs
pub(crate) struct AppLinkView {
    app_id: String,
    title: String,
    description: Option<String>,
    instructions: String,
    url: String,
    is_installed: bool,        // false for install suggestion
    is_enabled: bool,
    suggest_reason: Option<String>,
    suggestion_type: Option<AppLinkSuggestionType>,
    elicitation_target: Option<AppLinkElicitationTarget>,
    screen: AppLinkScreen,     // Tracks Link vs InstallConfirmation
    // ... other fields
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum AppLinkSuggestionType {
    Install,
    Enable,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum AppLinkScreen {
    Link,
    InstallConfirmation,
}
```

### Screen State Machine

```
[Link Screen] --"Install on ChatGPT"--> [InstallConfirmation Screen]
      |                                        |
      |--"Back"--> (close)                     |--"I already Installed it"--> (resolve + close)
                                                |--"Back"--> [Link Screen]
```

### Key Rendering Methods

```rust
fn link_content_lines(&self, width: u16) -> Vec<Line<'static>> {
    // For uninstalled apps:
    // - Title (bold)
    // - Description (dim)
    // - Suggest reason (italic)
    // - Instructions
    // - Note about installation delay
    // - Post-install usage hint
}

fn action_labels(&self) -> Vec<&'static str> {
    match self.screen {
        AppLinkScreen::Link => {
            if self.is_installed {
                vec!["Manage on ChatGPT", "Enable/Disable app", "Back"]
            } else {
                vec!["Install on ChatGPT", "Back"]  // <-- Shown in snapshot
            }
        }
        AppLinkScreen::InstallConfirmation => {
            vec!["I already Installed it", "Back"]
        }
    }
}
```

### Action Handling

```rust
fn open_chatgpt_link(&mut self) {
    self.app_event_tx.send(AppEvent::OpenUrlInBrowser {
        url: self.url.clone(),
    });
    if !self.is_installed {
        // Transition to confirmation screen after opening browser
        self.screen = AppLinkScreen::InstallConfirmation;
        self.selected_action = 0;
    }
}

fn refresh_connectors_and_close(&mut self) {
    self.app_event_tx.send(AppEvent::RefreshConnectors {
        force_refetch: true,
    });
    if self.is_tool_suggestion() {
        self.resolve_elicitation(ElicitationAction::Accept);
    }
    self.complete = true;
}
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Source File
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/app_link_view.rs`

### Test Function
```rust
#[test]
fn install_suggestion_with_reason_snapshot() {
    // Lines ~892-916 in app_link_view.rs
    let view = AppLinkView::new(
        AppLinkViewParams {
            app_id: "connector_google_calendar".to_string(),
            title: "Google Calendar".to_string(),
            description: Some("Plan events and schedules.".to_string()),
            instructions: "Install this app in your browser, then return here.".to_string(),
            url: "https://example.test/google-calendar".to_string(),
            is_installed: false,  // Key difference from enable suggestion
            is_enabled: false,
            suggest_reason: Some("Plan and reference events from your calendar".to_string()),
            suggestion_type: Some(AppLinkSuggestionType::Install),
            elicitation_target: Some(suggestion_target()),
        },
        tx,
    );
    assert_snapshot!(
        "app_link_view_install_suggestion_with_reason",
        render_snapshot(&view, Rect::new(0, 0, 72, view.desired_height(72)))
    );
}
```

### Related Test for Flow Completion
```rust
#[test]
fn install_tool_suggestion_resolves_elicitation_after_confirmation() {
    // Lines ~742-798 in app_link_view.rs
    // Tests the full flow: Enter -> OpenUrl -> Enter -> Refresh + ResolveElicitation
}
```

### Key Dependencies
- `super::selection_popup_common::{GenericDisplayRow, measure_rows_height, render_rows}`
- `crate::wrapping::{RtOptions, adaptive_wrap_lines}` - For URL wrapping in confirmation screen

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### External Dependencies

| Dependency | Purpose |
|------------|---------|
| `ratatui` | Terminal UI rendering |
| `textwrap` | Text content wrapping |
| `crossterm` | Keyboard input handling |
| `codex_protocol` | Protocol types for elicitation |
| `tokio::sync::mpsc` | Event channel communication |

### App Events Emitted

| Event | Trigger |
|-------|---------|
| `OpenUrlInBrowser { url }` | User selects "Install on ChatGPT" |
| `RefreshConnectors { force_refetch: true }` | User confirms "I already Installed it" |
| `SubmitThreadOp { op: ResolveElicitation { decision: Accept } }` | Successful completion |
| `SubmitThreadOp { op: ResolveElicitation { decision: Decline } }` | User selects "Back" or presses Esc |

### Protocol Integration

The component uses `AppLinkElicitationTarget` to resolve tool elicitations:
```rust
fn resolve_elicitation(&self, decision: ElicitationAction) {
    let Some(target) = self.elicitation_target.as_ref() else { return };
    self.app_event_tx.resolve_elicitation(
        target.thread_id,
        target.server_name.clone(),
        target.request_id.clone(),
        decision,
        /*content*/ None,
        /*meta*/ None,
    );
}
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Potential Risks

1. **Browser Opening Failure**: If `OpenUrlInBrowser` fails silently, user may wait indefinitely
2. **Installation Timing**: Apps "can take a few minutes to appear" - users may get impatient
3. **State Desync**: User confirms installation but app isn't actually ready yet
4. **Elicitation Timeout**: Long installation times may cause elicitation to expire

### Edge Cases

1. **Very Long URLs**: The confirmation screen uses `adaptive_wrap_lines` to handle long URLs gracefully
2. **Missing Description**: Component handles `description: None` by skipping that section
3. **Empty Instructions**: Empty instructions are filtered out via `trim().is_empty()` check
4. **Narrow Terminals**: Height calculation accounts for wrapped content

### Specific Test Coverage

The snapshot captures:
- ✅ Title: "Google Calendar"
- ✅ Description: "Plan events and schedules."
- ✅ Reason: "Plan and reference events from your calendar"
- ✅ Instructions for installation
- ✅ Delay warning: "Newly installed apps can take a few minutes..."
- ✅ Post-install hint: "After installed, use $ to insert this app..."
- ✅ Action buttons: "Install on ChatGPT" and "Back"
- ✅ Navigation hint at bottom

### Improvement Suggestions

1. **Progress Indicator**: Show a spinner while waiting for connector refresh
2. **Retry Mechanism**: Allow users to retry if installation confirmation fails
3. **Deep Linking**: Use deep links to open directly to app installation page
4. **Polling**: Auto-detect when app becomes available instead of requiring manual confirmation
5. **Cancel Option**: Add explicit "Cancel installation" option during confirmation
6. **Time Estimate**: Provide more specific time estimate than "a few minutes"

### Related Tests in File

- `install_confirmation_does_not_split_long_url_like_token_without_scheme` - URL display
- `install_confirmation_render_keeps_url_tail_visible_when_narrow` - Narrow width handling
- `install_tool_suggestion_resolves_elicitation_after_confirmation` - Full flow test
- `declined_tool_suggestion_resolves_elicitation_decline` - Decline path
