# Research: Full Access Confirmation Popup

## 1. 场景与职责 (Scene and Responsibility)

This snapshot captures the **full access permission confirmation popup**. When a user attempts to enable "full access" mode (which allows the agent to edit any file and run commands without approval), this safety dialog requests explicit confirmation.

**Scene Context:**
- User is attempting to enable full access permissions
- This is a high-risk configuration that bypasses safety checks
- The system requires explicit confirmation before proceeding
- User can choose to apply for this session only or persist the choice

**Responsibilities:**
- Warn users about the risks of full access mode
- Require explicit confirmation before enabling
- Provide options for session-only vs persistent enablement
- Allow users to cancel and maintain current safety settings

## 2. 功能点目的 (Functional Purpose)

The full access confirmation popup serves to:

1. **Safety Warning**: Clearly communicate the risks of full access mode
2. **Informed Consent**: Ensure users understand what they're enabling
3. **Accident Prevention**: Prevent accidental enablement of dangerous mode
4. **Choice Persistence**: Allow users to choose session-only or permanent

**Risk Warnings Displayed:**
- Can edit any file on the computer
- Can run commands with network access without approval
- Increases risk of data loss, leaks, or unexpected behavior
- Recommends exercising caution

## 3. 具体技术实现 (Technical Implementation)

### Key Data Structures

```rust
// Approval preset
pub struct ApprovalPreset {
    pub id: String,           // "full-access"
    pub name: String,
    pub description: String,
    pub approval_policy: AskForApproval,
    pub sandbox_policy: SandboxPolicy,
}

// From codex_core::config
pub enum AskForApproval {
    Never,      // Full access - no approval needed
    Sometimes,  // Partial approval
    Always,     // Always ask
}
```

### Rendering Format

```
  Enable full access?
  When Codex runs with full access, it can edit any file on your computer and
  run commands with network, without your approval. Exercise caution when
  enabling full access. This significantly increases the risk of data loss,
  leaks, or unexpected behavior.

› 1. Yes, continue anyway      Apply full access for this session
  2. Yes, and don't ask again  Enable full access and remember this choice
  3. Cancel                    Go back without enabling full access

  Press enter to confirm or esc to go back
```

**Visual Elements:**
- Title: "Enable full access?"
- Warning text: Multi-line risk description
- Three numbered options with descriptions:
  1. Session-only enablement
  2. Persistent enablement (saved to config)
  3. Cancel
- Selected option highlighted with `›`
- Footer with keyboard instructions

### Key Processes

1. **Popup Creation** (from test):
```rust
let preset = builtin_approval_presets()
    .into_iter()
    .find(|preset| preset.id == "full-access")
    .expect("full access preset");
chat.open_full_access_confirmation(preset, false);

let popup = render_bottom_popup(&chat, 80);
assert_snapshot!("full_access_confirmation_popup", popup);
```

2. **User Selection Handling**:
```rust
match selection {
    1 => {
        // Enable for this session only
        chat.set_approval_policy(AskForApproval::Never);
    }
    2 => {
        // Enable and save to config
        chat.set_approval_policy(AskForApproval::Never);
        chat.save_config();
    }
    3 | Esc => {
        // Cancel - no changes
    }
}
```

3. **Safety Checks**:
```rust
// Additional warnings may be shown based on:
// - Current notice settings
// - Previous user choices
// - Platform-specific risks
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files

| File | Description |
|------|-------------|
| `codex-rs/tui/src/chatwidget/tests.rs` | Test `full_access_confirmation_popup_snapshot` (line ~7950) |
| `codex-rs/tui/src/chatwidget/mod.rs` | `open_full_access_confirmation` implementation |
| `codex-rs/core/src/config/mod.rs` | `AskForApproval` enum |
| `codex-rs/utils/approval_presets/src/lib.rs` | Built-in approval presets |

### Key Functions

```rust
// Open confirmation popup
fn open_full_access_confirmation(&mut self, preset: ApprovalPreset, hide_warning: bool)

// Get built-in presets
fn builtin_approval_presets() -> Vec<ApprovalPreset>

// Set approval policy
fn set_approval_policy(&mut self, policy: AskForApproval)

// Test helper
fn render_bottom_popup(chat: &ChatWidget, width: u16) -> String
```

### Configuration

```rust
// Config settings affected
pub struct Config {
    pub approval_policy: AskForApproval,
    pub notices: NoticesConfig,
}

pub struct NoticesConfig {
    pub hide_full_access_warning: Option<bool>,
}
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Internal Dependencies

- `ApprovalPreset`: Full-access preset definition
- `AskForApproval::Never`: The policy being enabled
- `Config`: For persisting user choice
- `SelectionView`: UI component for option display

### Safety System Integration

```
User selects "Full Access" from approvals popup
    ↓
Check if warning should be shown
    ↓
Show confirmation popup (this snapshot)
    ↓
User makes selection
    ↓
If Yes (session): Enable for current session only
If Yes (persist): Enable and save to config.toml
If Cancel: No changes
```

### Platform Considerations

| Platform | Additional Considerations |
|----------|--------------------------|
| macOS | Seatbelt sandbox implications |
| Linux | Docker/container implications |
| Windows | Windows Sandbox implications |

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks

1. **Warning Fatigue**: Users may become desensitized to warnings
2. **Misunderstanding**: Users may not fully understand the risks
3. **Persistent Enablement**: "Don't ask again" could lead to forgotten risk
4. **Social Engineering**: Malicious instructions could trick users into enabling

### Edge Cases

1. **Already Enabled**: User tries to enable when already enabled
2. **Config Write Failure**: Choice to persist fails due to permissions
3. **Nested Confirmation**: Multiple confirmation dialogs stacking
4. **Terminal Resize**: Popup display on very narrow terminals
5. **Non-Interactive Mode**: Confirmation in scripted/automated usage

### Improvement Suggestions

1. **Risk Examples**: Show concrete examples of what could go wrong
2. **Time Delay**: Require waiting 5 seconds before confirming
3. **Type to Confirm**: Require typing "FULL ACCESS" to confirm
4. **Periodic Reminders**: Re-confirm periodically even with "don't ask again"
5. **Visual Warning**: Red border or warning icon for dangerous mode
6. **Status Indicator**: Always-visible indicator when in full access mode
7. **Undo Capability**: Easy way to revert to safe mode
8. **Scope Limiting**: Allow full access only in specific directories
9. **Audit Log**: Log all actions taken in full access mode
10. **Two-Person Rule**: Require confirmation from second user for critical operations
