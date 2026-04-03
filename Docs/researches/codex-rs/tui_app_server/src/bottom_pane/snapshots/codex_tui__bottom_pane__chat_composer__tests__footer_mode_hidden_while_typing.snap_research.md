# Research: footer_mode_hidden_while_typing Snapshot Test

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the **footer behavior when the user starts typing** in the chat composer. It ensures that the shortcuts hint is hidden once the user begins entering text, making room for the draft content indicator.

**Scenario**: When the composer is empty, the footer shows shortcuts hint (`? for shortcuts`). As soon as the user types any character, the hint should disappear and the footer should switch to showing context information.

**Responsibility**: The test verifies that:
- The footer transitions from `ComposerEmpty` to `ComposerHasDraft` mode when typing begins
- The shortcuts hint is suppressed while typing
- The context indicator ("100% context left") remains visible

## 2. 功能点目的 (Purpose of the Feature)

This feature provides a clean, context-aware UI that:
- Shows helpful shortcuts when the composer is idle and empty
- Removes distractions once the user starts typing
- Maintains useful context information (like context window usage) visible at all times
- Follows the principle of progressive disclosure in UI design

The snapshot captures the visual output when:
- User types a single character ('h')
- Footer mode transitions to `ComposerHasDraft`
- Shortcuts hint is hidden, context indicator remains

## 3. 具体技术实现 (Technical Implementation)

### Key Code Flow:

1. **Test Setup** (`footer_mode_snapshots` test in `chat_composer.rs`):
```rust
snapshot_composer_state("footer_mode_hidden_while_typing", true, |composer| {
    type_chars_humanlike(composer, &['h']);
});
```

2. **Character Input Handling** (`handle_input_basic_with_time` in chat_composer.rs:2998-3128):
```rust
fn handle_input_basic_with_time(&mut self, input: KeyEvent, now: Instant) -> (InputResult, bool) {
    // Flush any paste burst first
    self.handle_paste_burst_flush(now);
    
    // Reset footer mode after activity (unless it's Esc)
    if !matches!(input.code, KeyCode::Esc) {
        self.footer_mode = reset_mode_after_activity(self.footer_mode);
    }
    // ... handle character input
}
```

3. **Footer Mode Reset** (`reset_mode_after_activity` in footer.rs:177-185):
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

4. **Footer Mode Resolution** (`footer_mode()` in chat_composer.rs:3228-3249):
```rust
fn footer_mode(&self) -> FooterMode {
    let base_mode = if self.is_empty() {
        FooterMode::ComposerEmpty
    } else {
        FooterMode::ComposerHasDraft  // <-- Used when typing
    };
    // ... transient mode handling
}
```

5. **Shortcuts Hint Suppression** (chat_composer.rs:4207-4213):
```rust
let show_shortcuts_hint = match footer_props.mode {
    FooterMode::ComposerEmpty => !self.is_in_paste_burst(),
    FooterMode::ComposerHasDraft => false,  // <-- Hidden while typing
    FooterMode::QuitShortcutReminder
    | FooterMode::ShortcutOverlay
    | FooterMode::EscHint => false,
};
```

### Footer Mode Transition:
```
ComposerEmpty (with shortcuts hint) → ComposerHasDraft (no shortcuts hint)
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files:

| File | Purpose |
|------|---------|
| `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs` | Main composer logic, test at line ~4758-4760 |
| `codex-rs/tui_app_server/src/bottom_pane/footer.rs` | Footer mode definitions and reset logic |

### Key Functions:

1. **Test Definition** (chat_composer.rs:4758-4760):
```rust
snapshot_composer_state("footer_mode_hidden_while_typing", true, |composer| {
    type_chars_humanlike(composer, &['h']);
});
```

2. **`type_chars_humanlike()` Helper** (chat_composer.rs:6571-6588):
```rust
fn type_chars_humanlike(composer: &mut ChatComposer, chars: &[char]) {
    use crossterm::event::KeyCode;
    use crossterm::event::KeyEvent;
    use crossterm::event::KeyEventKind;
    use crossterm::event::KeyModifiers;
    for &ch in chars {
        let _ = composer.handle_key_event(KeyEvent::new(KeyCode::Char(ch), KeyModifiers::NONE));
        std::thread::sleep(ChatComposer::recommended_paste_flush_delay());
        let _ = composer.flush_paste_burst_if_due();
        if ch == ' ' {
            let _ = composer.handle_key_event(KeyEvent::new_with_kind(
                KeyCode::Char(' '),
                KeyModifiers::NONE,
                KeyEventKind::Release,
            ));
        }
    }
}
```

3. **`is_empty()` Check** (chat_composer.rs:725-729):
```rust
pub(crate) fn is_empty(&self) -> bool {
    self.textarea.is_empty()
        && self.attached_images.is_empty()
        && self.remote_image_urls.is_empty()
}
```

4. **Footer Rendering Decision** (chat_composer.rs:4190-4451):
   - Determines what to show based on `footer_props.mode`
   - Context window line is rendered separately from shortcuts hint

### Snapshot Output:
```
"› h                                                                                                 "
...
"                                                                                 100% context left  "
```

Note: The 'h' appears in the composer input area, and the footer shows only the context indicator without the shortcuts hint.

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Dependencies:
- `ratatui` - Terminal UI rendering
- `crossterm` - Key event handling
- `insta` - Snapshot testing

### State Dependencies:
- `textarea.is_empty()` - Determines if composer has content
- `attached_images` - Part of `is_empty()` check
- `remote_image_urls` - Part of `is_empty()` check
- `paste_burst.is_active()` - Affects shortcuts hint in empty mode

### Related Components:
- **PasteBurst system**: Prevents shortcuts hint from flickering during paste operations
- **Context window indicator**: Always shown regardless of footer mode (when space permits)

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks:
1. **Flickering**: If `reset_mode_after_activity` is called too aggressively, the footer might flicker between modes
2. **Paste Burst Interaction**: During paste operations, the shortcuts hint should remain hidden even if `is_empty()` temporarily returns true
3. **Performance**: Frequent mode transitions could cause unnecessary re-renders

### Edge Cases:
1. **Single Character Delete**: If user types then immediately deletes, the footer should transition back to showing shortcuts
2. **Paste Operations**: Large pastes should not trigger mode transitions for each character
3. **Image Attachments**: Attaching an image without typing should also hide shortcuts hint (since `is_empty()` becomes false)
4. **Remote Images**: Similar to local images, adding remote image URLs affects `is_empty()`

### Improvement Suggestions:

1. **Smooth Transitions**: Consider adding a brief delay before hiding the shortcuts hint to prevent flickering during accidental key presses

2. **Visual Feedback**: When the hint disappears, a subtle animation could help users understand the state change

3. **Alternative Hint Location**: Consider showing shortcuts in a different location (e.g., above the composer) so they remain visible during typing

4. **Smart Context**: The context indicator ("100% context left") could change color or style when the composer has draft content to provide additional visual distinction

5. **Test Coverage**: Add tests for:
   - Typing then deleting (should restore shortcuts hint)
   - Attaching images without typing (should hide shortcuts)
   - Paste burst during empty state (should suppress shortcuts hint)
   - Very rapid typing/deleting sequences

6. **Configuration**: Consider making this behavior configurable for users who prefer to always see shortcuts

7. **Documentation**: The relationship between `is_empty()`, `ComposerHasDraft` mode, and shortcuts hint visibility could be better documented in code comments
