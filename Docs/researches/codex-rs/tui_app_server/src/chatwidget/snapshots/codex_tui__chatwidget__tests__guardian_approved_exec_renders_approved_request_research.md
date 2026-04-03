# Research: Guardian Approved Exec Renders Approved Request

## 1. 场景与职责 (Scene and Responsibility)

This snapshot captures the **rendering of a Guardian-approved execution request**. The Guardian system reviews potentially risky operations and either approves or rejects them. This snapshot shows the UI when a command has been approved by the Guardian auto-reviewer.

**Scene Context:**
- A shell command (`rm -f /tmp/guardian-approved.sqlite`) was submitted for execution
- The Guardian system assessed the command as low risk (risk score: 14)
- The Guardian approved the execution with rationale
- The UI displays the approval status and command details

**Responsibilities:**
- Display Guardian approval status clearly
- Show the approved command for user visibility
- Present the Guardian's rationale for the decision
- Maintain trust through transparency of the review process

## 2. 功能点目的 (Functional Purpose)

The Guardian approval rendering serves to:

1. **Transparency**: Show users when and why commands are approved
2. **Trust Building**: Demonstrate that safety checks are active
3. **Audit Trail**: Provide visibility into approved operations
4. **User Awareness**: Inform users of commands being executed

**Key Information Displayed:**
- Approval status (✔ Auto-reviewer approved)
- Command being executed
- Risk level and score (Low, 14)
- Guardian's rationale for approval

## 3. 具体技术实现 (Technical Implementation)

### Key Data Structures

```rust
// From codex_protocol::protocol
pub struct GuardianAssessmentEvent {
    pub id: String,
    pub turn_id: String,
    pub status: GuardianAssessmentStatus,
    pub risk_score: Option<i32>,
    pub risk_level: Option<GuardianRiskLevel>,
    pub rationale: Option<String>,
    pub action: Option<serde_json::Value>,
}

pub enum GuardianAssessmentStatus {
    Approved,
    Rejected,
    Pending,
}

pub enum GuardianRiskLevel {
    Low,
    Medium,
    High,
    Critical,
}
```

### Rendering Format

```





✔ Auto-reviewer approved codex to run rm -f /tmp/guardian-approved.sqlite this
  time


› Ask Codex to do anything

  ? for shortcuts                                                                                    100% context left
```

**Visual Elements:**
- `✔`: Checkmark indicating approval
- `Auto-reviewer approved`: Approval source
- Command: `rm -f /tmp/guardian-approved.sqlite`
- `this time`: Indicates one-time approval
- Footer with prompt and context indicator

### Key Processes

1. **Event Handling** (from test):
```rust
chat.handle_codex_event(Event {
    id: "guardian-assessment".into(),
    msg: EventMsg::GuardianAssessment(GuardianAssessmentEvent {
        id: "thread:child-thread:guardian-1".into(),
        turn_id: "turn-1".into(),
        status: GuardianAssessmentStatus::Approved,
        risk_score: Some(14),
        risk_level: Some(GuardianRiskLevel::Low),
        rationale: Some("Narrowly scoped to the requested file.".into()),
        action: Some(serde_json::json!({
            "tool": "shell",
            "command": "rm -f /tmp/guardian-approved.sqlite",
        })),
    }),
});
```

2. **Rendering**:
```rust
let width: u16 = 120;
let ui_height: u16 = chat.desired_height(width);
let vt_height: u16 = 12;
let viewport = Rect::new(0, vt_height - ui_height - 1, width, ui_height);

let backend = VT100Backend::new(width, vt_height);
let mut term = crate::custom_terminal::Terminal::with_options(backend).expect("terminal");
term.set_viewport_area(viewport);

// Insert history lines
for lines in drain_insert_history(&mut rx) {
    crate::insert_history::insert_history_lines(&mut term, lines)
        .expect("Failed to insert history lines in test");
}

// Draw the chat widget
term.draw(|f| {
    chat.render(f.area(), f.buffer_mut());
}).expect("draw guardian approval history");
```

3. **Snapshot Capture**:
```rust
assert_snapshot!(
    "guardian_approved_exec_renders_approved_request",
    term.backend().vt100().screen().contents()
);
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files

| File | Description |
|------|-------------|
| `codex-rs/tui/src/chatwidget/tests.rs` | Test `guardian_approved_exec_renders_approved_request` (line ~9555) |
| `codex-rs/tui/src/chatwidget/mod.rs` | Guardian event handling |
| `codex-rs/protocol/src/protocol.rs` | Guardian event definitions |
| `codex-rs/tui/src/test_backend.rs` | VT100Backend for testing |

### Key Functions

```rust
// Test function
async fn guardian_approved_exec_renders_approved_request()

// Event handler
fn handle_codex_event(&mut self, event: Event)

// History insertion
fn insert_history_lines(term: &mut Terminal, lines: Vec<Line>) -> Result<()>

// VT100 backend for snapshot testing
VT100Backend::new(width, height)
```

### Protocol Events

```rust
EventMsg::GuardianAssessment(GuardianAssessmentEvent {
    id: "thread:child-thread:guardian-1",
    turn_id: "turn-1",
    status: Approved,
    risk_score: Some(14),
    risk_level: Some(Low),
    rationale: Some("Narrowly scoped to the requested file."),
    action: Some({
        "tool": "shell",
        "command": "rm -f /tmp/guardian-approved.sqlite"
    }),
})
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Internal Dependencies

- `GuardianAssessmentEvent`: Approval/rejection information
- `GuardianRiskLevel`: Risk classification
- `VT100Backend`: Terminal emulation for testing
- `insert_history`: History line management

### Guardian System Flow

```
Command submitted for execution
    ↓
Guardian assessment requested
    ↓
Guardian analyzes command:
  - Risk scoring (14 = Low)
  - Scope analysis
  - Policy checks
    ↓
GuardianAssessmentEvent (Approved)
    ↓
UI renders approval with details
    ↓
Command executed (if approved)
```

### Risk Levels

| Level | Score Range | Description |
|-------|-------------|-------------|
| Low | 0-25 | Safe to auto-approve |
| Medium | 26-50 | May require user confirmation |
| High | 51-75 | Requires explicit approval |
| Critical | 76-100 | Blocked by default |

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks

1. **False Confidence**: Users may trust auto-approval too much
2. **Attack Surface**: Malicious commands might achieve low risk scores
3. **Rationale Quality**: Poor rationales reduce trust in the system
4. **Bypass Attempts**: Users may try to craft commands that evade detection

### Edge Cases

1. **Missing Rationale**: Approval without explanation
2. **Unknown Risk Level**: Assessment without risk classification
3. **Malformed Action**: Action JSON that doesn't match expected format
4. **Concurrent Assessments**: Multiple commands assessed simultaneously
5. **Assessment Delay**: Long-running assessment blocking UI
6. **Reversal**: Assessment changes after initial display

### Improvement Suggestions

1. **Detailed Rationale**: Expandable section with full reasoning
2. **Risk Breakdown**: Show score components (file scope, command type, etc.)
3. **Similar Commands**: Show "Commands like this are usually approved/rejected"
4. **User Override**: Allow users to cancel even approved commands
5. **Learning Feedback**: "Was this approval correct?" feedback button
6. **Policy Link**: Link to documentation about Guardian policies
7. **Audit Log**: View all Guardian decisions for the session
8. **Risk Trend**: Show if risk scores are increasing/decreasing
9. **Command Preview**: Show full command with syntax highlighting
10. **Time Limit**: Auto-execute after delay unless user cancels
