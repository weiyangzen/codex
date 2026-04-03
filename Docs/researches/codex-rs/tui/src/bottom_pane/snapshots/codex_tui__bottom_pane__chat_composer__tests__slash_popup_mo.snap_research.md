# Research: Slash Popup Mo (/model command autocomplete)

## Snapshot File
- **File**: `codex-rs/tui/src/bottom_pane/snapshots/codex_tui__bottom_pane__chat_composer__tests__slash_popup_mo.snap`
- **Source**: `codex-rs/tui/src/bottom_pane/chat_composer.rs`
- **Description**: Shows /model command autocomplete

## Snapshot Content
```
"                                                            "
"› /mo                                                       "
"                                                            "
"                                                            "
"  /model  choose what model and reasoning effort to use     "
```

## UI State Description
This snapshot captures the command popup (CommandPopup) displayed when the user types `/mo` in the composer. The popup shows the `/model` command as the first (and in this case, only visible) suggestion, with its description. This demonstrates the slash command autocomplete functionality that helps users discover and complete available commands.

## Component Hierarchy
- `ChatComposer` - Main composer component
  - `TextArea` - Input field with `/mo` typed
  - `CommandPopup` - Slash command selection popup
    - Filtered command suggestions

## Key Props / State
- `active_popup`: `ActivePopup::Command(CommandPopup)`
- `command_filter`: "mo"
- `builtins`: List of available built-in commands
- `prompts`: User-defined custom prompts (filtered out if they collide with builtins)

## Visual Elements
| Element | Type | Description |
|---------|------|-------------|
| `›` | Indicator | Prompt prefix character |
| `/mo` | Input | User-typed command prefix |
| `/model` | Command | Highlighted command name |
| Description | Text | "choose what model and reasoning effort to use" |

## Related Code References

### Command Popup Filter Logic (`command_popup.rs`)
```rust
fn filtered(&self) -> Vec<(CommandItem, Option<Vec<usize>>)> {
    let filter = self.command_filter.trim();
    let mut out: Vec<(CommandItem, Option<Vec<usize>>)> = Vec::new();
    if filter.is_empty() {
        // Built-ins first, in presentation order
        for (_, cmd) in self.builtins.iter() {
            if ALIAS_COMMANDS.contains(cmd) {
                continue;
            }
            out.push((CommandItem::Builtin(*cmd), None));
        }
        // Then prompts, already sorted by name
        for idx in 0..self.prompts.len() {
            out.push((CommandItem::UserPrompt(idx), None));
        }
        return out;
    }

    let filter_lower = filter.to_lowercase();
    let filter_chars = filter.chars().count();
    let mut exact: Vec<(CommandItem, Option<Vec<usize>>)> = Vec::new();
    let mut prefix: Vec<(CommandItem, Option<Vec<usize>>)> = Vec::new();
    // ... exact and prefix matching logic

    out.extend(exact);
    out.extend(prefix);
    out
}
```

### Command Popup Text Change Handler (`command_popup.rs`)
```rust
/// Update the filter string based on the current composer text.
pub(crate) fn on_composer_text_change(&mut self, text: String) {
    let first_line = text.lines().next().unwrap_or("");

    if let Some(stripped) = first_line.strip_prefix('/') {
        // Extract the *first* token after the slash
        let token = stripped.trim_start();
        let cmd_token = token.split_whitespace().next().unwrap_or("");

        // Update the filter keeping the original case
        self.command_filter = cmd_token.to_string();
    } else {
        // The composer no longer starts with '/'. Reset the filter.
        self.command_filter.clear();
    }

    // Reset or clamp selected index based on new filtered list
    let matches_len = self.filtered_items().len();
    self.state.clamp_selection(matches_len);
    self.state.ensure_visible(matches_len, MAX_POPUP_ROWS.min(matches_len));
}
```

### Command Popup Row Generation (`command_popup.rs`)
```rust
fn rows_from_matches(
    &self,
    matches: Vec<(CommandItem, Option<Vec<usize>>)>,
) -> Vec<GenericDisplayRow> {
    matches
        .into_iter()
        .map(|(item, indices)| {
            let (name, description) = match item {
                CommandItem::Builtin(cmd) => {
                    (format!("/ {}", cmd.command()), cmd.description().to_string())
                }
                CommandItem::UserPrompt(i) => {
                    let prompt = &self.prompts[i];
                    let description = prompt
                        .description
                        .clone()
                        .unwrap_or_else(|| "send saved prompt".to_string());
                    (
                        format!("/{PROMPTS_CMD_PREFIX}:{}", prompt.name),
                        description,
                    )
                }
            };
            GenericDisplayRow {
                name,
                name_prefix_spans: Vec::new(),
                match_indices: indices.map(|v| v.into_iter().map(|i| i + 1).collect()),
                display_shortcut: None,
                description: Some(description),
                category_tag: None,
                wrap_indent: None,
                is_disabled: false,
                disabled_reason: None,
            }
        })
        .collect()
}
```

### Sync Command Popup (`chat_composer.rs`)
```rust
fn sync_command_popup(&mut self, allow: bool) {
    if !allow {
        if matches!(self.active_popup, ActivePopup::Command(_)) {
            self.active_popup = ActivePopup::None;
        }
        return;
    }
    
    // Determine whether the caret is inside the initial '/name' token
    let text = self.textarea.text();
    let first_line_end = text.find('\n').unwrap_or(text.len());
    let first_line = &text[..first_line_end];
    let cursor = self.textarea.cursor();
    let caret_on_first_line = cursor <= first_line_end;

    let is_editing_slash_command_name = caret_on_first_line
        && Self::slash_command_under_cursor(first_line, cursor)
            .is_some_and(|(name, rest)| self.looks_like_slash_prefix(name, rest));

    match &mut self.active_popup {
        ActivePopup::Command(popup) => {
            if is_editing_slash_command_name {
                popup.on_composer_text_change(first_line.to_string());
            } else {
                self.active_popup = ActivePopup::None;
            }
        }
        _ => {
            if is_editing_slash_command_name {
                let mut command_popup = CommandPopup::new(
                    self.custom_prompts.clone(),
                    CommandPopupFlags { /* ... */ },
                );
                command_popup.on_composer_text_change(first_line.to_string());
                self.active_popup = ActivePopup::Command(command_popup);
            }
        }
    }
}
```

### Key Event Handling for Slash Popup (`chat_composer.rs`)
```rust
fn handle_key_event_with_slash_popup(&mut self, key_event: KeyEvent) -> (InputResult, bool) {
    // ... shortcut overlay handling
    
    let ActivePopup::Command(popup) = &mut self.active_popup else {
        unreachable!();
    };

    match key_event {
        KeyEvent { code: KeyCode::Up, .. }
        | KeyEvent { code: KeyCode::Char('p'), modifiers: KeyModifiers::CONTROL, .. } => {
            popup.move_up();
            (InputResult::None, true)
        }
        KeyEvent { code: KeyCode::Down, .. }
        | KeyEvent { code: KeyCode::Char('n'), modifiers: KeyModifiers::CONTROL, .. } => {
            popup.move_down();
            (InputResult::None, true)
        }
        KeyEvent { code: KeyCode::Esc, .. } => {
            // Dismiss the slash popup; keep the current input untouched
            self.active_popup = ActivePopup::None;
            (InputResult::None, true)
        }
        KeyEvent { code: KeyCode::Tab, .. } => {
            // Apply completion
            let first_line = self.textarea.text().lines().next().unwrap_or("");
            popup.on_composer_text_change(first_line.to_string());
            if let Some(sel) = popup.selected_item() {
                match sel {
                    CommandItem::Builtin(cmd) => {
                        if cmd == SlashCommand::Skills {
                            self.textarea.set_text_clearing_elements("");
                            return (InputResult::Command(cmd), true);
                        }
                        // Set text to "/{command} "
                        self.textarea.set_text_clearing_elements(&format!("/{} ", cmd.command()));
                    }
                    // ... handle UserPrompt
                }
            }
            (InputResult::None, true)
        }
        KeyEvent { code: KeyCode::Enter, modifiers: KeyModifiers::NONE, .. } => {
            // Execute selected command or submit
            // ...
        }
        input => self.handle_input_basic(input),
    }
}
```

## Behavior
1. User types `/` followed by `mo` in the composer
2. `sync_command_popup()` detects the slash prefix and creates a CommandPopup
3. `on_composer_text_change()` extracts "mo" as the filter token
4. `filtered()` finds commands matching the prefix:
   - `/model` matches because "mo" is a prefix of "model"
   - Other commands like `/mention`, `/mcp` also match but `/model` ranks first
5. The popup displays `/model` with its description
6. User can:
   - Press Tab to complete the command to `/model `
   - Press Enter to execute the command immediately
   - Use Up/Down to navigate between matching commands
   - Press Esc to dismiss the popup

## Command Ranking
For the prefix "mo", commands are ranked by:
1. Exact matches first (none in this case)
2. Prefix matches in presentation order
3. The `/model` command appears before `/mention` and `/mcp` in the builtin ordering

## Test Context
This snapshot is generated by the test `slash_popup_mo` which verifies that:
- Typing `/mo` shows the `/model` command as the first suggestion
- The command description is displayed correctly
- The popup filtering works for command prefixes
