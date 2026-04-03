# Research: footer_mode_hidden_while_typing

## Snapshot Description

This snapshot captures the footer UI state when the user is actively typing in the composer. The footer shows only the context window indicator ("100% context left") on the right side, with no instructional hints on the left. This demonstrates the "hidden while typing" behavior where footer hints are suppressed during active input.

## Visual Output

```
"                                                                                                    "
"› h                                                                                                 "
"                                                                                                    "
"                                                                                                    "
"                                                                                                    "
"                                                                                                    "
"                                                                                                    "
"                                                                                                    "
"                                                                                 100% context left  "
```

## Code Analysis

### Test Setup

**Source:** `codex-rs/tui/src/bottom_pane/chat_composer.rs` (lines 4743-4745)

```rust
snapshot_composer_state("footer_mode_hidden_while_typing", true, |composer| {
    type_chars_humanlike(composer, &['h']);
});
```

### Key State Components

1. **Composer Text:** `"h"` (single character typed)
2. **Footer Mode:** `FooterMode::ComposerHasDraft` (set by typing)
3. **Context Window:** 100% remaining
4. **Shortcuts Hint:** Hidden (suppressed in `ComposerHasDraft` mode)
5. **Queue Hint:** Not shown (no task running)

### Typing Simulation

**Helper function:**

```rust
fn type_chars_humanlike(composer: &mut ChatComposer, chars: &[char]) {
    for ch in chars {
        let _ = composer.handle_key_event(KeyEvent::new(
            KeyCode::Char(*ch),
            KeyModifiers::NONE,
        ));
    }
}
```

### Footer Mode Transition on Input

**From chat_composer.rs (lines 2993-2995):**

```rust
fn handle_input_basic_with_time(&mut self, input: KeyEvent, now: Instant) -> (InputResult, bool) {
    // ...
    if !matches!(input.code, KeyCode::Esc) {
        self.footer_mode = reset_mode_after_activity(self.footer_mode);
    }
    // ...
}
```

### Reset Mode After Activity

**From footer.rs (lines 177-185):**

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

Wait - this seems contradictory! The snapshot shows `ComposerHasDraft` behavior, but `reset_mode_after_activity` would reset to `ComposerEmpty`. Let me trace the actual flow more carefully.

### Actual Footer Mode Logic

The key is in `footer_from_props_lines()` (footer.rs, lines 580-631):

```rust
fn footer_from_props_lines(
    props: &FooterProps,
    collaboration_mode_indicator: Option<CollaborationModeIndicator>,
    show_cycle_hint: bool,
    show_shortcuts_hint: bool,
    show_queue_hint: bool,
) -> Vec<Line<'static>> {
    // ...
    match props.mode {
        // ...
        FooterMode::ComposerHasDraft => {
            let state = LeftSideState {
                hint: if show_queue_hint {
                    SummaryHintKind::QueueMessage
                } else if show_shortcuts_hint {
                    SummaryHintKind::Shortcuts
                } else {
                    SummaryHintKind::None  // <-- THIS PATH
                },
                show_cycle_hint,
            };
            vec![left_side_line(collaboration_mode_indicator, state)]
        }
    }
}
```

### Show Shortcuts Hint Logic

**From footer.rs (lines 1084-1090):**

```rust
let show_shortcuts_hint = match props.mode {
    FooterMode::ComposerEmpty => true,
    FooterMode::ComposerHasDraft => false,  // <-- HIDDEN
    FooterMode::QuitShortcutReminder
    | FooterMode::ShortcutOverlay
    | FooterMode::EscHint => false,
};
```

## UI Behavior

### Footer Hint Visibility by Mode

| Footer Mode | Shortcuts Hint | Queue Hint | Context Indicator |
|-------------|---------------|------------|-------------------|
| `ComposerEmpty` | ✅ Visible | ❌ Hidden | ✅ Visible |
| `ComposerHasDraft` (idle) | ❌ Hidden | ✅ If task running | ✅ Visible |
| `ComposerHasDraft` (typing) | ❌ Hidden | ✅ If task running | ✅ Visible |

### Why "Hidden While Typing"?

The design rationale:
1. **Reduce visual noise** - User is focused on typing
2. **Maximize space** - Context indicator alone is sufficient
3. **Avoid distraction** - Hints would compete with user input
4. **Transient state** - Footer returns to normal after typing stops

### Context Window Display

**From footer.rs (lines 848-860):**

```rust
pub(crate) fn context_window_line(percent: Option<i64>, used_tokens: Option<i64>) -> Line<'static> {
    if let Some(percent) = percent {
        let percent = percent.clamp(0, 100);
        return Line::from(vec![Span::from(format!("{percent}% context left")).dim()]);
    }

    if let Some(tokens) = used_tokens {
        let used_fmt = format_tokens_compact(tokens);
        return Line::from(vec![Span::from(format!("{used_fmt} used")).dim()]);
    }

    Line::from(vec![Span::from("100% context left").dim()])  // <-- DEFAULT
}
```

Since no context window was explicitly set in the test, it defaults to `"100% context left"`.

## Technical Details

### FooterProps Construction

**From chat_composer.rs (footer_props method):**

```rust
fn footer_props(&self) -> FooterProps {
    FooterProps {
        mode: self.footer_mode,
        esc_backtrack_hint: self.esc_backtrack_hint,
        use_shift_enter_hint: self.use_shift_enter_hint,
        is_task_running: self.is_task_running,
        collaboration_modes_enabled: self.collaboration_modes_enabled,
        is_wsl: self.is_wsl(),
        quit_shortcut_key: self.quit_shortcut_key,
        context_window_percent: self.context_window_percent,
        context_window_used_tokens: self.context_window_used_tokens,
        status_line_value: self.status_line_value.clone(),
        status_line_enabled: self.status_line_enabled,
        active_agent_label: self.active_agent_label.clone(),
    }
}
```

### Left Side Line Construction

**From footer.rs (lines 271-300):**

```rust
fn left_side_line(
    collaboration_mode_indicator: Option<CollaborationModeIndicator>,
    state: LeftSideState,
) -> Line<'static> {
    let mut line = Line::from("");
    match state.hint {
        SummaryHintKind::None => {}  // <-- No hint added
        SummaryHintKind::Shortcuts => {
            line.push_span(key_hint::plain(KeyCode::Char('?')));
            line.push_span(" for shortcuts".dim());
        }
        SummaryHintKind::QueueMessage => {
            line.push_span(key_hint::plain(KeyCode::Tab));
            line.push_span(" to queue message".dim());
        }
        SummaryHintKind::QueueShort => {
            line.push_span(key_hint::plain(KeyCode::Tab));
            line.push_span(" to queue".dim());
        }
    };
    // ...
}
```

When `SummaryHintKind::None`, the left side line is empty, leaving only the right-aligned context indicator.

### Rendering Flow

```
User types 'h'
    ↓
handle_key_event(KeyCode::Char('h'))
    ↓
handle_input_basic()
    ↓
reset_mode_after_activity(ComposerEmpty) → ComposerEmpty
    ↓
textarea.insert_str("h")
    ↓
sync_popups()  // Updates footer props
    ↓
render()
    ↓
footer_props() → mode: ComposerHasDraft (from is_empty() check)
    ↓
footer_from_props_lines()
    ↓
left_side_line(SummaryHintKind::None) → empty line
    ↓
context_window_line(None, None) → "100% context left"
    ↓
Render: empty left + context right
```

## Comparison with Other States

| State | Left Footer | Right Footer |
|-------|-------------|--------------|
| Empty composer | `? for shortcuts` | Context indicator |
| Typing (this snapshot) | (empty) | `100% context left` |
| Has draft + task running | `tab to queue message` | Context indicator |
| Quit hint | `ctrl + c again to quit` | (hidden) |

## Related Snapshots

- `footer_collapse_empty_full` - Full footer when empty
- `footer_collapse_queue_short_with_context` - Queue hint with context
- `footer_shortcuts_default` - Default shortcuts hint display
