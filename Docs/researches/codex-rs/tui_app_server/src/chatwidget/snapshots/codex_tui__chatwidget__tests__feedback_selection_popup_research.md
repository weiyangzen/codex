# Research: Feedback Selection Popup

## 1. 场景与职责 (Scene and Responsibility)

This snapshot captures the **feedback category selection popup**. When a user triggers the feedback flow (typically via `/feedback` slash command), this popup allows them to categorize their feedback to help the team route it appropriately.

**Scene Context:**
- User has initiated the feedback submission process
- The system is asking the user to categorize their feedback
- Categories range from bugs to positive feedback
- Selection determines subsequent flow (e.g., whether to ask for log upload)

**Responsibilities:**
- Present clear feedback categories for user selection
- Provide descriptions to help users choose appropriately
- Capture the user's intent for routing to the right team
- Serve as the entry point for the feedback workflow

## 2. 功能点目的 (Functional Purpose)

The feedback selection popup serves to:

1. **Categorization**: Route feedback to appropriate teams (bugs, safety, etc.)
2. **User Guidance**: Help users understand what types of feedback are valuable
3. **Workflow Branching**: Different categories may trigger different follow-up flows
4. **Quality Improvement**: Structured feedback helps prioritize improvements

**Feedback Categories:**

| # | Category | Description |
|---|----------|-------------|
| 1 | bug | Crash, error message, hang, or broken UI/behavior |
| 2 | bad result | Output was off-target, incorrect, incomplete, or unhelpful |
| 3 | good result | Helpful, correct, high-quality, or delightful result |
| 4 | safety check | Benign usage blocked due to safety checks or refusals |
| 5 | other | Slowness, feature suggestion, UX feedback, or anything else |

## 3. 具体技术实现 (Technical Implementation)

### Key Data Structures

```rust
// From crate::app_event
pub enum FeedbackCategory {
    Bug,
    BadResult,
    GoodResult,
    SafetyCheck,
    Other,
}

// Selection view parameters
pub struct SelectionViewParams {
    pub title: String,
    pub options: Vec<SelectionOption>,
    pub on_select: Box<dyn Fn(usize) -> AppEvent>,
}

pub struct SelectionOption {
    pub label: String,
    pub description: String,
}
```

### Rendering Format

```
  How was this?

› 1. bug           Crash, error message, hang, or broken UI/behavior.
  2. bad result    Output was off-target, incorrect, incomplete, or unhelpful.
  3. good result   Helpful, correct, high‑quality, or delightful result worth
                   celebrating.
  4. safety check  Benign usage blocked due to safety checks or refusals.
  5. other         Slowness, feature suggestion, UX feedback, or anything
                   else.
```

**Visual Elements:**
- Title: "How was this?"
- Numbered options (1-5)
- Category name (left-aligned)
- Description (wrapped and indented)
- Current selection highlighted with `›`

### Key Processes

1. **Popup Trigger** (from test):
```rust
// Open the feedback category selection popup via slash command.
chat.dispatch_command(SlashCommand::Feedback);

let popup = render_bottom_popup(&chat, 80);
assert_snapshot!("feedback_selection_popup", popup);
```

2. **Selection Handling**:
```rust
// User navigates with arrow keys
// Presses Enter to select
// AppEvent::FeedbackCategorySelected emitted
```

3. **Category-Specific Flows**:
```rust
match category {
    Bug | BadResult | GoodResult | SafetyCheck => {
        // Show log upload consent popup
    }
    Other => {
        // May skip log upload or show different flow
    }
}
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files

| File | Description |
|------|-------------|
| `codex-rs/tui/src/chatwidget/tests.rs` | Test `feedback_selection_popup_snapshot` (line ~8122) |
| `codex-rs/tui/src/bottom_pane/mod.rs` | Feedback selection view implementation |
| `codex-rs/tui/src/app_event.rs` | `FeedbackCategory` enum definition |

### Key Functions

```rust
// Slash command handler
fn dispatch_command(&mut self, command: SlashCommand) {
    match command {
        SlashCommand::Feedback => {
            // Show feedback category selection
        }
        // ...
    }
}

// Selection view creation
fn show_feedback_selection(&mut self) {
    let options = vec![
        ("bug", "Crash, error message, hang, or broken UI/behavior."),
        ("bad result", "Output was off-target, incorrect, incomplete, or unhelpful."),
        // ...
    ];
    self.show_selection_view(/* ... */);
}
```

### Related Snapshots
- `feedback_selection_popup.snap` - This file (category selection)
- `feedback_upload_consent_popup.snap` - Log upload consent (after selection)
- `feedback_good_result_consent_popup.snap` - Good result specific consent

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Internal Dependencies

- `SlashCommand::Feedback`: Trigger for the popup
- `SelectionView`: UI component for option selection
- `FeedbackCategory`: Enum for category types
- `AppEventSender`: For emitting selection events

### Slash Command Integration

```
User types "/feedback"
    ↓
Slash command parsed
    ↓
dispatch_command(Feedback) called
    ↓
Feedback category popup shown
    ↓
User selects category
    ↓
Category-specific flow continues
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks

1. **Category Confusion**: Users may not know which category to choose
2. **Selection Fatigue**: Too many options may discourage feedback submission
3. **Miscategorization**: Important feedback routed to wrong team

### Edge Cases

1. **No Selection**: User opens popup but doesn't select anything
2. **Rapid Cancellation**: User opens and immediately closes
3. **Keyboard Navigation**: Accessibility concerns with arrow key navigation
4. **Terminal Width**: Long descriptions may wrap poorly on narrow terminals

### Improvement Suggestions

1. **Default Selection**: Pre-select most common category (e.g., "other")
2. **Recent History**: Show recent feedback categories for quick re-selection
3. **Search**: Allow typing to filter categories
4. **Icons**: Add visual icons for each category
5. **Examples**: Show examples of each category on hover/focus
6. **Satisfaction Score**: Add 1-5 star rating alongside category
7. **Quick Feedback**: One-click positive/negative buttons for common cases
8. **Follow-up Questions**: Dynamic questions based on selected category
