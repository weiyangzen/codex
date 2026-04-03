# Research: Slash Popup Res (/resume command autocomplete)

## Snapshot File
- **File**: `codex-rs/tui/src/bottom_pane/snapshots/codex_tui__bottom_pane__chat_composer__tests__slash_popup_res.snap`
- **Source**: `codex-rs/tui/src/bottom_pane/chat_composer.rs`
- **Description**: Shows /resume command autocomplete

## Snapshot Content
```
"                                                            "
"› /res                                                      "
"                                                            "
"                                                            "
"                                                            "
"  /resume  resume a saved chat                              "
```

## UI State Description
This snapshot captures the command popup (CommandPopup) displayed when the user types `/res` in the composer. The popup shows the `/resume` command as a suggestion, with its description "resume a saved chat". This demonstrates the slash command autocomplete functionality for the resume command, which allows users to restore previous chat sessions.

## Component Hierarchy
- `ChatComposer` - Main composer component
  - `TextArea` - Input field with `/res` typed
  - `CommandPopup` - Slash command selection popup
    - Filtered command suggestions

## Key Props / State
- `active_popup`: `ActivePopup::Command(CommandPopup)`
- `command_filter`: "res"
- `builtins`: List of available built-in commands including `/resume`
- `prompts`: User-defined custom prompts

## Visual Elements
| Element | Type | Description |
|---------|------|-------------|
| `›` | Indicator | Prompt prefix character |
| `/res` | Input | User-typed command prefix |
| `/resume` | Command | Highlighted command name |
| Description | Text | "resume a saved chat" |

## Related Code References

### Slash Commands Definition
The `/resume` command is defined as a built-in slash command that allows users to resume saved chat sessions. It is part of the standard command set available in the CommandPopup.

### Command Popup Filtering (`command_popup.rs`)
```rust
fn filtered(&self) -> Vec<(CommandItem, Option<Vec<usize>>)> {
    let filter = self.command_filter.trim();
    let mut out: Vec<(CommandItem, Option<Vec<usize>>)> = Vec::new();
    if filter.is_empty() {
        // Return all non-alias builtins and prompts
        for (_, cmd) in self.builtins.iter() {
            if ALIAS_COMMANDS.contains(cmd) {
                continue;
            }
            out.push((CommandItem::Builtin(*cmd), None));
        }
        for idx in 0..self.prompts.len() {
            out.push((CommandItem::UserPrompt(idx), None));
        }
        return out;
    }

    let filter_lower = filter.to_lowercase();
    let filter_chars = filter.chars().count();
    let mut exact: Vec<(CommandItem, Option<Vec<usize>>)> = Vec::new();
    let mut prefix: Vec<(CommandItem, Option<Vec<usize>>)> = Vec::new();
    let indices_for = |offset| Some((offset..offset + filter_chars).collect());

    let mut push_match =
        |item: CommandItem, display: &str, name: Option<&str>, name_offset: usize| {
            let display_lower = display.to_lowercase();
            let name_lower = name.map(str::to_lowercase);
            let display_exact = display_lower == filter_lower;
            let name_exact = name_lower.as_deref() == Some(filter_lower.as_str());
            if display_exact || name_exact {
                let offset = if display_exact { 0 } else { name_offset };
                exact.push((item, indices_for(offset)));
                return;
            }
            let display_prefix = display_lower.starts_with(&filter_lower);
            let name_prefix = name_lower
                .as_ref()
                .is_some_and(|name| name.starts_with(&filter_lower));
            if display_prefix || name_prefix {
                let offset = if display_prefix { 0 } else { name_offset };
                prefix.push((item, indices_for(offset)));
            }
        };

    for (_, cmd) in self.builtins.iter() {
        push_match(CommandItem::Builtin(*cmd), cmd.command(), None, 0);
    }
    // ... prompts handling

    out.extend(exact);
    out.extend(prefix);
    out
}
```

### Command Item Selection (`command_popup.rs`)
```rust
/// Return currently selected command, if any.
pub(crate) fn selected_item(&self) -> Option<CommandItem> {
    let matches = self.filtered_items();
    self.state
        .selected_idx
        .and_then(|idx| matches.get(idx).copied())
}
```

### Command Popup Movement (`command_popup.rs`)
```rust
/// Move the selection cursor one step up.
pub(crate) fn move_up(&mut self) {
    let len = self.filtered_items().len();
    self.state.move_up_wrap(len);
    self.state.ensure_visible(len, MAX_POPUP_ROWS.min(len));
}

/// Move the selection cursor one step down.
pub(crate) fn move_down(&mut self) {
    let matches_len = self.filtered_items().len();
    self.state.move_down_wrap(matches_len);
    self.state.ensure_visible(matches_len, MAX_POPUP_ROWS.min(matches_len));
}
```

### Popup Rendering (`command_popup.rs`)
```rust
impl WidgetRef for CommandPopup {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        let rows = self.rows_from_matches(self.filtered());
        render_rows(
            area.inset(Insets::tlbr(
                /*top*/ 0, /*left*/ 2, /*bottom*/ 0, /*right*/ 0,
            )),
            buf,
            &rows,
            &self.state,
            MAX_POPUP_ROWS,
            "no matches",
        );
    }
}
```

### Row Generation with Match Highlighting (`command_popup.rs`)
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

### Generic Display Row Rendering (`selection_popup_common.rs`)
The `GenericDisplayRow` structure is used across different popups (CommandPopup, FileSearchPopup, SkillPopup) for consistent rendering:

```rust
pub(crate) struct GenericDisplayRow {
    pub(crate) name: String,
    pub(crate) name_prefix_spans: Vec<Span<'static>>,
    pub(crate) match_indices: Option<Vec<usize>>,
    pub(crate) display_shortcut: Option<String>,
    pub(crate) description: Option<String>,
    pub(crate) category_tag: Option<String>,
    pub(crate) is_disabled: bool,
    pub(crate) disabled_reason: Option<String>,
    pub(crate) wrap_indent: Option<String>,
}
```

## Behavior
1. User types `/` followed by `res` in the composer
2. `sync_command_popup()` detects the slash prefix and creates/updates the CommandPopup
3. `on_composer_text_change()` extracts "res" as the filter token
4. `filtered()` performs prefix matching:
   - "res" matches the prefix of "resume"
   - The match is added to the prefix matches list
5. The popup displays `/resume` with its description "resume a saved chat"
6. The matched characters "res" are highlighted in the command name
7. User can:
   - Press Tab to complete to `/resume `
   - Press Enter to execute the resume command
   - Continue typing to refine the filter
   - Press Esc to dismiss the popup

## Command Execution
When the user selects `/resume`:
1. If Enter is pressed, the command is dispatched via `InputResult::Command(SlashCommand::Resume)`
2. The chat widget handles the command to show the resume/saved chats interface
3. The composer text is cleared after command dispatch

## Test Context
This snapshot is generated by the test `slash_popup_res` which verifies that:
- Typing `/res` shows the `/resume` command in the popup
- The command description is displayed correctly
- The popup filtering works for partial command prefixes
- The layout includes proper spacing for the command and description
