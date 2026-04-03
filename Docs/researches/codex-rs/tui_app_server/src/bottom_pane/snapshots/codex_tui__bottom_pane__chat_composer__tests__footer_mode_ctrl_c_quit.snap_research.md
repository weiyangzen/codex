# Research: Footer Mode - Ctrl+C Quit

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer rendering behavior when:
- The user presses **Ctrl+C** while the composer is **idle** (no task running)
- The composer shows the **"ctrl + c again to quit"** reminder
- The terminal width is **100 columns**
- The composer is in **quit shortcut reminder mode**

This tests the standard quit confirmation behavior - when idle, Ctrl+C requires a second press to confirm application exit, preventing accidental quits.

## 2. 功能点目的 (Feature Purpose)

The Ctrl+C quit mode serves to:
1. **Accidental Quit Prevention**: Require confirmation before exiting
2. **Shell Convention**: Match Unix shell behavior (Ctrl+C to interrupt/quit)
3. **Visual Feedback**: Confirm that quit signal was received
4. **Graceful Exit**: Allow users to change their mind by not pressing again

This is the standard quit flow when no task is active - the first Ctrl+C shows the hint, the second actually quits.

## 3. 具体技术实现 (Technical Implementation)

### Mode State Machine
```
ComposerEmpty → Ctrl+C → QuitShortcutReminder → Ctrl+C → Quit Application
                     ↓
                Timeout → ComposerEmpty
```

### Implementation Details

**Timeout Mechanism**:
```rust
self.quit_shortcut_expires_at = Instant::now()
    .checked_add(super::QUIT_SHORTCUT_TIMEOUT)
    .unwrap_or_else(|| Instant::now());
```

**Mode Transition**:
```rust
self.footer_mode = FooterMode::QuitShortcutReminder;
```

**Key Storage**:
```rust
self.quit_shortcut_key = key_hint::ctrl(KeyCode::Char('c'));
```

### Rendering
The hint is rendered with dim styling:
```rust
Line::from(vec![key.into(), " again to quit".into()]).dim()
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Test Implementation
**`codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`** (lines 4723-4726):

```rust
snapshot_composer_state("footer_mode_ctrl_c_quit", true, |composer| {
    composer.show_quit_shortcut_hint(key_hint::ctrl(KeyCode::Char('c')), true);
});
```

Note: Unlike the interrupt test, this doesn't call `set_task_running(true)`, so `is_task_running` remains `false` (default).

### Core Functions

1. **`show_quit_shortcut_hint()`** (chat_composer.rs, lines 1247-1259):
```rust
/// Show the transient "press again to quit" hint for `key`.
///
/// The owner (`BottomPane`/`ChatWidget`) is responsible for scheduling a
/// redraw after [`super::QUIT_SHORTCUT_TIMEOUT`] so the hint can disappear
/// even when the UI is otherwise idle.
pub fn show_quit_shortcut_hint(&mut self, key: KeyBinding, has_focus: bool) {
    self.quit_shortcut_expires_at = Instant::now()
        .checked_add(super::QUIT_SHORTCUT_TIMEOUT)
        .or_else(|| Some(Instant::now()));
    self.quit_shortcut_key = key;
    self.footer_mode = FooterMode::QuitShortcutReminder;
    self.set_has_focus(has_focus);
}
```

2. **`quit_shortcut_reminder_line()`** (footer.rs, lines 731-733):
```rust
fn quit_shortcut_reminder_line(key: KeyBinding) -> Line<'static> {
    Line::from(vec![key.into(), " again to quit".into()]).dim()
}
```

3. **`reset_mode_after_activity()`** (footer.rs, lines 177-185):
```rust
pub(crate) fn reset_mode_after_activity(current: FooterMode) -> FooterMode {
    match current {
        FooterMode::EscHint
        | FooterMode::ShortcutOverlay
        | FooterMode::QuitShortcutReminder
        | FooterMode::ComposerHasDraft => FooterMode::ComposerEmpty,
        other => other,
    }
}
```

### Footer Props Structure
**`FooterProps`** (footer.rs, lines 66-87):
```rust
pub(crate) struct FooterProps {
    pub(crate) mode: FooterMode,
    pub(crate) quit_shortcut_key: KeyBinding,  // Ctrl+C in this case
    // ... other fields
}
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### State Machine
| State | Trigger | Next State |
|-------|---------|------------|
| `ComposerEmpty` | Ctrl+C | `QuitShortcutReminder` |
| `QuitShortcutReminder` | Ctrl+C (within timeout) | Application Exit |
| `QuitShortcutReminder` | Timeout | `ComposerEmpty` |
| `QuitShortcutReminder` | Any other key | Reset to base mode |

### External Integration
1. **ChatWidget**: Calls `show_quit_shortcut_hint()` on first Ctrl+C
2. **BottomPane**: Schedules redraw for timeout expiration
3. **AppEvent**: `AppEvent::Quit` sent on second Ctrl+C
4. **Timer**: UI tick checks `quit_shortcut_hint_visible()`

### Constants
- `QUIT_SHORTCUT_TIMEOUT`: Typically 2-3 seconds
- Default width: 100 columns for this test

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvements)

### Risk Analysis

#### 1. Timeout Too Short
- **Risk**: Users don't see hint before it disappears
- **Current**: Fixed timeout may not suit all reading speeds
- **Impact**: Users confused why first Ctrl+C didn't quit

#### 2. No Visual Distinction from Interrupt
- **Issue**: Same hint text whether interrupting or quitting
- **Impact**: Users may not realize no task is running
- **Suggestion**: Different hint text or styling

#### 3. Focus Management
- **Risk**: Hint shown but composer loses focus
- **Impact**: Second Ctrl+C may not register correctly
- **Mitigation**: Focus check before processing second press

### Edge Cases

1. **Double-Timing**: User presses Ctrl+C twice within timeout
2. **Slow Response**: Application lag between hint and second press
3. **Modal Dialogs**: Hint visible when modal appears
4. **Window Minimized**: Hint expires while window minimized

### Improvement Suggestions

#### 1. Persistent Quit Option
```rust
// Allow users to disable the confirmation
if config.quick_quit_enabled {
    quit_immediately_on_ctrl_c();
} else {
    show_quit_confirmation_hint();
}
```

#### 2. Visual Countdown
```rust
// Show remaining time in hint
let remaining = quit_shortcut_expires_at - Instant::now();
format!("ctrl + c again to quit ({}s)", remaining.as_secs())
```

#### 3. Alternative Quit Keys
```rust
// Support Ctrl+D as alternative quit key
if key == KeyCode::Char('d') && modifiers == CONTROL {
    show_quit_shortcut_hint(key_hint::ctrl(KeyCode::Char('d')));
}
```

#### 4. Session Persistence Warning
```rust
// Warn if unsaved changes before quit
if has_unsaved_changes() {
    show_hint("ctrl + c again to quit (unsaved changes will be lost)");
}
```

#### 5. Accessibility
```rust
// Screen reader announcement
if quit_hint_visible {
    announce_to_screen_reader("Press Control C again to quit application");
}
```

### Related Snapshots
| Snapshot | Task Running | Key | Description |
|----------|--------------|-----|-------------|
| `footer_mode_ctrl_c_quit` | No | Ctrl+C | This test - standard quit |
| `footer_mode_ctrl_c_interrupt` | Yes | Ctrl+C | Interrupt mode |
| `footer_ctrl_c_quit_idle` | No | Ctrl+C | Footer.rs test variant |
| `footer_ctrl_c_quit_running` | Yes | Ctrl+C | Footer.rs test variant |

### Testing Notes
- The snapshot shows: `"  ctrl + c again to quit"`
- The 2-space indent comes from `FOOTER_INDENT_COLS`
- The key styling shows "ctrl + c" with key highlighting
- The text is dimmed (`.dim()`) to indicate transient state
