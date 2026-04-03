# Research: Footer Mode - Ctrl+C then Esc Hint

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer rendering behavior when:
- The user presses **Ctrl+C** (showing quit hint)
- Then presses **Esc** (switching to Esc hint mode)
- The composer shows **"esc esc to edit previous message"**
- The terminal width is **100 columns**

This tests the interaction between two different footer modes - when a quit hint is active but the user presses Esc instead, the footer transitions to show the Esc hint for editing previous messages.

## 2. 功能点目的 (Feature Purpose)

The Ctrl+C → Esc sequence demonstrates:
1. **Mode Preemption**: Esc hint takes precedence over quit hint
2. **Alternative Actions**: Users can change their mind and choose a different action
3. **Edit Previous Message**: The Esc hint informs users about the backtrack/edit feature
4. **Graceful Transitions**: Footer modes transition smoothly without jarring changes

This shows how the footer adapts when user input changes the intended action mid-flow.

## 3. 具体技术实现 (Technical Implementation)

### Mode Transition Flow
```
ComposerEmpty → Ctrl+C → QuitShortcutReminder ("ctrl + c again to quit")
                      ↓
                   Esc → EscHint ("esc esc to edit previous message")
```

### Key Handling Logic
When Esc is pressed while `QuitShortcutReminder` is active:

```rust
if key_event.code == KeyCode::Esc {
    let next_mode = esc_hint_mode(self.footer_mode, self.is_task_running);
    if next_mode != self.footer_mode {
        self.footer_mode = next_mode;
        return (InputResult::None, true);
    }
}
```

### Esc Hint Construction
**`esc_hint_line()`** (footer.rs, lines 735-748):
```rust
fn esc_hint_line(esc_backtrack_hint: bool) -> Line<'static> {
    let esc = key_hint::plain(KeyCode::Esc);
    if esc_backtrack_hint {
        Line::from(vec![esc.into(), " again to edit previous message".into()]).dim()
    } else {
        Line::from(vec![
            esc.into(),
            " ".into(),
            esc.into(),
            " to edit previous message".into(),
        ])
        .dim()
    }
}
```

Note: In this test, `esc_backtrack_hint` is `false` (default), so it shows "esc esc" format.

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Test Implementation
**`codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`** (lines 4732-4735):

```rust
snapshot_composer_state("footer_mode_ctrl_c_then_esc_hint", true, |composer| {
    composer.show_quit_shortcut_hint(key_hint::ctrl(KeyCode::Char('c')), true);
    let _ = composer.handle_key_event(KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE));
});
```

### Mode Transition Functions

1. **`esc_hint_mode()`** (footer.rs, lines 169-175):
```rust
pub(crate) fn esc_hint_mode(current: FooterMode, is_task_running: bool) -> FooterMode {
    if is_task_running {
        current  // Don't change mode if task is running
    } else {
        FooterMode::EscHint
    }
}
```

2. **Key Event Handling** (chat_composer.rs, lines 2751-2761):
```rust
if key_event.code == KeyCode::Esc {
    if self.is_empty() {
        let next_mode = esc_hint_mode(self.footer_mode, self.is_task_running);
        if next_mode != self.footer_mode {
            self.footer_mode = next_mode;
            return (InputResult::None, true);
        }
    }
} else {
    self.footer_mode = reset_mode_after_activity(self.footer_mode);
}
```

### Footer Rendering for EscHint
**`footer_from_props_lines()`** (footer.rs, lines 616):
```rust
FooterMode::EscHint => vec![esc_hint_line(props.esc_backtrack_hint)],
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### State Transitions
| Initial State | Input | Next State | Condition |
|---------------|-------|------------|-----------|
| `ComposerEmpty` | Ctrl+C | `QuitShortcutReminder` | Always |
| `QuitShortcutReminder` | Esc | `EscHint` | `!is_task_running` |
| `QuitShortcutReminder` | Esc | `QuitShortcutReminder` | `is_task_running` |

### Configuration
| Field | Value | Description |
|-------|-------|-------------|
| `esc_backtrack_hint` | `false` | Shows "esc esc" format |
| `is_task_running` | `false` (default) | Allows Esc hint transition |
| `is_empty()` | `true` | Required for Esc hint |

### Rendering Components
- **Key hint styling**: `key_hint::plain(KeyCode::Esc)` for visual key representation
- **Dim styling**: `.dim()` applied to entire hint line
- **Double Esc**: Shows "esc esc" when `esc_backtrack_hint` is false

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvements)

### Risk Analysis

#### 1. Mode Confusion
- **Risk**: Users may not understand why footer changed from quit to edit hint
- **Impact**: Confusion about what action will occur on next keypress
- **Mitigation**: Clear, distinct hint text for each mode

#### 2. Task Running State
- **Risk**: If task starts between Ctrl+C and Esc, behavior changes
- **Current**: `esc_hint_mode()` checks `is_task_running`
- **Impact**: Esc hint won't show if task is running

#### 3. Hint Timeout Interaction
- **Risk**: Quit hint timeout expires while Esc hint is showing
- **Current**: Each mode has its own timeout logic
- **Impact**: May cause unexpected mode transitions

### Edge Cases

1. **Rapid Key Sequence**: Ctrl+C, Esc, Esc - second Esc edits previous message
2. **Other Keys Between**: Ctrl+C, 'a', Esc - 'a' resets mode first
3. **Task Starts**: Ctrl+C, [task starts], Esc - Esc behavior changes
4. **Non-Empty Composer**: Ctrl+C with draft, then Esc - different behavior

### Improvement Suggestions

#### 1. Mode History Indicator
```rust
// Show that mode changed recently
if mode_changed_within(Duration::milliseconds(500)) {
    show_subtle_transition_indicator();
}
```

#### 2. Unified Cancel Action
```rust
// Consistent way to cancel any pending action
if key == KeyCode::Esc && pending_action_exists() {
    cancel_pending_action();
    reset_footer_mode();
}
```

#### 3. Contextual Hint Enhancement
```rust
// Show different hint based on available history
let hint = if has_previous_messages() {
    "esc esc to edit previous message"
} else {
    "esc to cancel"  // No history to edit
};
```

#### 4. Visual Mode Indicator
```rust
// Subtle color coding for different modes
let mode_color = match footer_mode {
    FooterMode::QuitShortcutReminder => Color::Yellow,  // Warning
    FooterMode::EscHint => Color::Cyan,                 // Info
    _ => Color::Gray,
};
```

#### 5. Accessibility Improvements
```rust
// Screen reader announcements for mode changes
if footer_mode_changed {
    announce(format!("Footer mode changed to {mode_description}"));
}
```

### Related Snapshots
| Snapshot | Sequence | Final Hint |
|----------|----------|------------|
| `footer_mode_ctrl_c_quit` | Ctrl+C | "ctrl + c again to quit" |
| `footer_mode_ctrl_c_then_esc_hint` | Ctrl+C, Esc | This test - "esc esc to edit..." |
| `footer_mode_esc_hint_from_overlay` | ?, Esc | Esc hint from shortcut overlay |
| `footer_mode_esc_hint_backtrack` | Esc | Esc hint with backtrack enabled |

### Test Notes
- The snapshot shows: `"  esc esc to edit previous message"`
- The double "esc" appears because `esc_backtrack_hint` is `false`
- If `esc_backtrack_hint` were `true`, it would show "esc again to edit..."
- The 2-space indent is from `FOOTER_INDENT_COLS`
- The entire line is dimmed to indicate transient state
