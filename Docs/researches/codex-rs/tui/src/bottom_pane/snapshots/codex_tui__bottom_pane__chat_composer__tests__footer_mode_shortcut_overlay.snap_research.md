# Research: Footer Mode Shortcut Overlay

## Snapshot File
- **File**: `codex-rs/tui/src/bottom_pane/snapshots/codex_tui__bottom_pane__chat_composer__tests__footer_mode_shortcut_overlay.snap`
- **Source**: `codex-rs/tui/src/bottom_pane/chat_composer.rs`
- **Description**: Shows multi-line shortcut overlay with all keyboard shortcuts

## Snapshot Content
```
"                                                                                                    "
"› Ask Codex to do anything                                                                          "
"                                                                                                    "
"                                                                                                    "
"                                                                                                    "
"                                                                                                    "
"                                                                                                    "
"                                                                                                    "
"  / for commands                             ! for shell commands                                   "
"  shift + enter for newline                  tab to queue message                                   "
"  @ for file paths                           ctrl + v to paste images                               "
"  ctrl + g to edit in external editor        esc again to edit previous message                     "
"  ctrl + c to exit                                                                                  "
"  ctrl + t to view transcript                                                                       "
```

## UI State Description
This snapshot captures the multi-line shortcut overlay displayed when the user presses `?` in an empty composer. The overlay shows all available keyboard shortcuts organized in a two-column layout. This is a transient instructional state that helps users discover available commands and shortcuts.

## Component Hierarchy
- `ChatComposer` - Main composer component
  - `TextArea` - Input field with placeholder
  - `Footer` - Bottom hint area
    - Footer mode: `ShortcutOverlay`
    - Multi-line shortcut display

## Key Props / State
- `footer_mode`: `FooterMode::ShortcutOverlay`
- `use_shift_enter_hint`: `true` (shows "shift + enter for newline")
- `esc_backtrack_hint`: `true` (shows "esc again to edit previous message")
- `is_empty`: `true` (composer has no text)

## Visual Elements
| Element | Type | Description |
|---------|------|-------------|
| `›` | Indicator | Prompt prefix character |
| Placeholder | Text | "Ask Codex to do anything" (dimmed) |
| Shortcuts | Multi-line | 6 rows of keyboard shortcuts in 2 columns |

### Shortcut Rows
| Left Column | Right Column |
|-------------|--------------|
| `/ for commands` | `! for shell commands` |
| `shift + enter for newline` | `tab to queue message` |
| `@ for file paths` | `ctrl + v to paste images` |
| `ctrl + g to edit in external editor` | `esc again to edit previous message` |
| `ctrl + c to exit` | |
| `ctrl + t to view transcript` | |

## Related Code References

### Shortcut Overlay Toggle (`chat_composer.rs`)
```rust
fn handle_shortcut_overlay_key(&mut self, key_event: &KeyEvent) -> bool {
    if key_event.kind != KeyEventKind::Press {
        return false;
    }

    let toggles = matches!(key_event.code, KeyCode::Char('?'))
        && !has_ctrl_or_alt(key_event.modifiers)
        && self.is_empty()
        && !self.is_in_paste_burst();

    if !toggles {
        return false;
    }

    let next = toggle_shortcut_mode(
        self.footer_mode,
        self.quit_shortcut_hint_visible(),
        self.is_empty(),
    );
    let changed = next != self.footer_mode;
    self.footer_mode = next;
    changed
}
```

### Shortcut Mode Toggle (`footer.rs`)
```rust
pub(crate) fn toggle_shortcut_mode(
    current: FooterMode,
    ctrl_c_hint: bool,
    is_empty: bool,
) -> FooterMode {
    if ctrl_c_hint && matches!(current, FooterMode::QuitShortcutReminder) {
        return current;
    }

    let base_mode = if is_empty {
        FooterMode::ComposerEmpty
    } else {
        FooterMode::ComposerHasDraft
    };

    match current {
        FooterMode::ShortcutOverlay | FooterMode::QuitShortcutReminder => base_mode,
        _ => FooterMode::ShortcutOverlay,
    }
}
```

### Shortcut Overlay Lines Generation (`footer.rs`)
```rust
fn shortcut_overlay_lines(state: ShortcutsState) -> Vec<Line<'static>> {
    let mut commands = Line::from("");
    let mut shell_commands = Line::from("");
    let mut newline = Line::from("");
    let mut queue_message_tab = Line::from("");
    let mut file_paths = Line::from("");
    let mut paste_image = Line::from("");
    let mut external_editor = Line::from("");
    let mut edit_previous = Line::from("");
    let mut quit = Line::from("");
    let mut show_transcript = Line::from("");
    let mut change_mode = Line::from("");

    for descriptor in SHORTCUTS {
        if let Some(text) = descriptor.overlay_entry(state) {
            match descriptor.id {
                ShortcutId::Commands => commands = text,
                // ... etc
            }
        }
    }
    // ... build columns
}
```

### Column Building (`footer.rs`)
```rust
fn build_columns(entries: Vec<Line<'static>>) -> Vec<Line<'static>> {
    const COLUMNS: usize = 2;
    const COLUMN_PADDING: [usize; COLUMNS] = [4, 4];
    const COLUMN_GAP: usize = 4;
    // ... arranges entries in two columns
}
```

## Behavior
1. User presses `?` when the composer is empty
2. `handle_shortcut_overlay_key` detects the key press and toggles the mode
3. Footer mode changes to `ShortcutOverlay`
4. The overlay renders all available shortcuts in a two-column layout
5. User can press `?` again or `Esc` to dismiss the overlay

## Test Context
This snapshot is generated by the test `footer_mode_shortcut_overlay` which verifies that:
- Pressing `?` in an empty composer shows the full shortcut overlay
- The overlay displays all expected shortcuts in the correct two-column format
- The shortcuts include commands, shell commands, newline, queue, file paths, paste, external editor, edit previous, quit, and transcript
