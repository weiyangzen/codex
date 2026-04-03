# Research: Plugin Mention Popup

## Snapshot File
- **File**: `codex-rs/tui/src/bottom_pane/snapshots/codex_tui__bottom_pane__chat_composer__tests__plugin_mention_popup.snap`
- **Source**: `codex-rs/tui/src/bottom_pane/chat_composer.rs`
- **Description**: Shows Sample Plugin mention popup

## Snapshot Content
```
"                                                                                                    "
"› $sa                                                                                               "
"                                                                                                    "
"                                                                                                    "
"                                                                                                    "
"                                                                                                    "
"  Sample Plugin  [Plugin] Plugin that includes the Figma MCP server and Skills for common workflows "
"                                                                                                    "
"  Press enter to insert or esc to close                                                             "
```

## UI State Description
This snapshot captures the mention popup (SkillPopup) displaying a plugin mention when the user types `$sa` in the composer. The popup shows a single "Sample Plugin" entry with its category tag [Plugin] and a description of its capabilities (includes Figma MCP server and Skills).

## Component Hierarchy
- `ChatComposer` - Main composer component
  - `TextArea` - Input field with `$sa` typed
  - `SkillPopup` - Mention selection popup
    - Single plugin mention item
    - Hint line at bottom

## Key Props / State
- `active_popup`: `ActivePopup::Skill(SkillPopup)`
- `query`: "sa"
- `mentions`: List containing the Sample Plugin `MentionItem`
- `category_tag`: Some("[Plugin]")
- `sort_rank`: 0 (plugins have higher priority than skills)

## Visual Elements
| Element | Type | Description |
|---------|------|-------------|
| `›` | Indicator | Prompt prefix character |
| `$sa` | Input | User-typed mention query |
| Plugin row | List item | Sample Plugin with [Plugin] tag and description |
| Hint | Text | "Press enter to insert or esc to close" |

### Mention Entry Details
| Field | Value |
|-------|-------|
| Display Name | Sample Plugin |
| Category | [Plugin] |
| Description | Plugin that includes the Figma MCP server and Skills for common workflows |
| Insert Text | `$Sample` (or plugin name) |
| Path | `plugin://{config_name}` |

## Related Code References

### Plugin Mention Item Creation (`chat_composer.rs`)
```rust
if let Some(plugins) = self.plugins.as_ref() {
    for plugin in plugins {
        let (plugin_name, marketplace_name) = plugin
            .config_name
            .split_once('@')
            .unwrap_or((plugin.config_name.as_str(), ""));
        
        let mut capability_labels = Vec::new();
        if plugin.has_skills {
            capability_labels.push("skills".to_string());
        }
        if !plugin.mcp_server_names.is_empty() {
            let mcp_server_count = plugin.mcp_server_names.len();
            capability_labels.push(if mcp_server_count == 1 {
                "1 MCP server".to_string()
            } else {
                format!("{mcp_server_count} MCP servers")
            });
        }
        if !plugin.app_connector_ids.is_empty() {
            let app_count = plugin.app_connector_ids.len();
            capability_labels.push(if app_count == 1 {
                "1 app".to_string()
            } else {
                format!("{app_count} apps")
            });
        }
        
        let description = plugin.description.clone().or_else(|| {
            Some(if capability_labels.is_empty() {
                "Plugin".to_string()
            } else {
                format!("Plugin · {}", capability_labels.join(" · "))
            })
        });
        
        let mut search_terms = vec![plugin_name.to_string(), plugin.config_name.clone()];
        if plugin.display_name != plugin_name {
            search_terms.push(plugin.display_name.clone());
        }
        if !marketplace_name.is_empty() {
            search_terms.push(marketplace_name.to_string());
        }
        
        mentions.push(MentionItem {
            display_name: plugin.display_name.clone(),
            description,
            insert_text: format!("${plugin_name}"),
            search_terms,
            path: Some(format!("plugin://{}", plugin.config_name)),
            category_tag: Some("[Plugin]".to_string()),
            sort_rank: 0,  // Plugins sort before skills (lower rank = higher priority)
        });
    }
}
```

### MentionItem Structure (`skill_popup.rs`)
```rust
#[derive(Clone, Debug)]
pub(crate) struct MentionItem {
    pub(crate) display_name: String,
    pub(crate) description: Option<String>,
    pub(crate) insert_text: String,
    pub(crate) search_terms: Vec<String>,
    pub(crate) path: Option<String>,
    pub(crate) category_tag: Option<String>,
    pub(crate) sort_rank: u8,
}
```

### Popup Filtering (`skill_popup.rs`)
```rust
fn filtered(&self) -> Vec<(usize, Option<Vec<usize>>, i32)> {
    let filter = self.query.trim();
    let mut out: Vec<(usize, Option<Vec<usize>>, i32)> = Vec::new();

    for (idx, mention) in self.mentions.iter().enumerate() {
        if filter.is_empty() {
            out.push((idx, None, 0));
            continue;
        }

        let mut best_match: Option<(Option<Vec<usize>>, i32)> = None;

        // Match against display name
        if let Some((indices, score)) = fuzzy_match(&mention.display_name, filter) {
            best_match = Some((Some(indices), score));
        }

        // Match against search terms
        for term in &mention.search_terms {
            if term == &mention.display_name {
                continue;
            }
            if let Some((_indices, score)) = fuzzy_match(term, filter) {
                // Update best match if this score is better
            }
        }

        if let Some((indices, score)) = best_match {
            out.push((idx, indices, score));
        }
    }

    // Sort by sort_rank, then score, then name
    out.sort_by(|a, b| {
        self.mentions[a.0]
            .sort_rank
            .cmp(&self.mentions[b.0].sort_rank)
            .then_with(|| a.2.cmp(&b.2))
            .then_with(|| {
                let an = self.mentions[a.0].display_name.as_str();
                let bn = self.mentions[b.0].display_name.as_str();
                an.cmp(bn)
            })
    });

    out
}
```

### Key Event Handling for Skill Popup (`chat_composer.rs`)
```rust
fn handle_key_event_with_skill_popup(&mut self, key_event: KeyEvent) -> (InputResult, bool) {
    if self.handle_shortcut_overlay_key(&key_event) {
        return (InputResult::None, true);
    }
    self.footer_mode = reset_mode_after_activity(self.footer_mode);

    let ActivePopup::Skill(popup) = &mut self.active_popup else {
        unreachable!();
    };

    let mut selected_mention: Option<(String, Option<String>)> = None;
    let mut close_popup = false;

    let result = match key_event {
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
            if let Some(tok) = self.current_mention_token() {
                self.dismissed_mention_popup_token = Some(tok);
            }
            self.active_popup = ActivePopup::None;
            (InputResult::None, true)
        }
        KeyEvent { code: KeyCode::Tab, .. }
        | KeyEvent { code: KeyCode::Enter, modifiers: KeyModifiers::NONE, .. } => {
            if let Some(mention) = popup.selected_mention() {
                selected_mention = Some((mention.insert_text.clone(), mention.path.clone()));
            }
            close_popup = true;
            (InputResult::None, true)
        }
        input => self.handle_input_basic(input),
    };

    if close_popup {
        if let Some((insert_text, path)) = selected_mention {
            self.insert_selected_mention(&insert_text, path.as_deref());
        }
        self.active_popup = ActivePopup::None;
    }

    result
}
```

## Behavior
1. User types `$` followed by `sa` in the composer
2. `current_mention_token()` extracts the token "sa"
3. `sync_mention_popup()` creates a SkillPopup with plugin mentions
4. The popup filters mentions where "sa" matches the plugin name or search terms
5. The Sample Plugin is displayed with its [Plugin] category tag and description
6. User can:
   - Press Enter to insert the mention as an element
   - Press Esc to dismiss the popup
   - Use Up/Down arrows to navigate if multiple matches exist

## Test Context
This snapshot is generated by the test `plugin_mention_popup` which verifies that:
- Plugin mentions are correctly displayed in the popup
- The plugin description shows capability information (MCP servers, skills, apps)
- The [Plugin] category tag is displayed
- The popup hint line is shown at the bottom
