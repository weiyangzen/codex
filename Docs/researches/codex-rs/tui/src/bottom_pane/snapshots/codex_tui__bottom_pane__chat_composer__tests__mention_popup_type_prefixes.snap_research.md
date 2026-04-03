# Research: Mention Popup Type Prefixes

## Snapshot File
- **File**: `codex-rs/tui/src/bottom_pane/snapshots/codex_tui__bottom_pane__chat_composer__tests__mention_popup_type_prefixes.snap`
- **Source**: `codex-rs/tui/src/bottom_pane/chat_composer.rs`
- **Description**: Shows Google Calendar mention popup with type prefixes ([Plugin], [Skill], [App])

## Snapshot Content
```
"                                                                        "
"› $goog                                                                 "
"                                                                        "
"                                                                        "
"  Google Calendar  [Plugin] Connect Google Calendar for scheduling, ava…"
"  Google Calendar  [Skill] Find availability and plan event changes     "
"  Google Calendar  [App] Look up events and availability                "
"                                                                        "
"  Press enter to insert or esc to close                                 "
```

## UI State Description
This snapshot captures the mention popup (SkillPopup) displayed when the user types `$goog` in the composer. The popup shows three Google Calendar mentions from different sources: a Plugin, a Skill, and an App connector. Each entry displays the type prefix in brackets to help users distinguish between different mention types.

## Component Hierarchy
- `ChatComposer` - Main composer component
  - `TextArea` - Input field with `$goog` typed
  - `SkillPopup` - Mention selection popup
    - Filtered mention items with category tags
    - Hint line at bottom

## Key Props / State
- `active_popup`: `ActivePopup::Skill(SkillPopup)`
- `query`: "goog"
- `mentions`: List of `MentionItem` with Google Calendar entries
- `category_tag`: Some("[Plugin]"), Some("[Skill]"), Some("[App]")

## Visual Elements
| Element | Type | Description |
|---------|------|-------------|
| `›` | Indicator | Prompt prefix character |
| `$goog` | Input | User-typed mention query |
| Popup rows | List | 3 Google Calendar mentions with type prefixes |
| Hint | Text | "Press enter to insert or esc to close" |

### Mention Entries
| Display Name | Category | Description |
|--------------|----------|-------------|
| Google Calendar | [Plugin] | Connect Google Calendar for scheduling, ava… |
| Google Calendar | [Skill] | Find availability and plan event changes |
| Google Calendar | [App] | Look up events and availability |

## Related Code References

### Mention Token Detection (`chat_composer.rs`)
```rust
fn current_mention_token(&self) -> Option<String> {
    if !self.mentions_enabled() {
        return None;
    }
    Self::current_prefixed_token(&self.textarea, '$', /*allow_empty*/ true)
}
```

### Mention Popup Synchronization (`chat_composer.rs`)
```rust
fn sync_mention_popup(&mut self, query: String) {
    if self.dismissed_mention_popup_token.as_ref() == Some(&query) {
        return;
    }

    let mentions = self.mention_items();
    if mentions.is_empty() {
        self.active_popup = ActivePopup::None;
        return;
    }

    match &mut self.active_popup {
        ActivePopup::Skill(popup) => {
            popup.set_query(&query);
            popup.set_mentions(mentions);
        }
        _ => {
            let mut popup = SkillPopup::new(mentions);
            popup.set_query(&query);
            self.active_popup = ActivePopup::Skill(popup);
        }
    }
}
```

### Mention Items Generation (`chat_composer.rs`)
```rust
fn mention_items(&self) -> Vec<MentionItem> {
    let mut mentions = Vec::new();

    // Add skills
    if let Some(skills) = self.skills.as_ref() {
        for skill in skills {
            mentions.push(MentionItem {
                display_name: skill_display_name(skill).to_string(),
                description: skill_description(skill),
                insert_text: format!("${skill_name}"),
                search_terms,
                path: Some(skill.path_to_skills_md.to_string_lossy().into_owned()),
                category_tag: Some("[Skill]".to_string()),
                sort_rank: 1,
            });
        }
    }

    // Add plugins
    if let Some(plugins) = self.plugins.as_ref() {
        for plugin in plugins {
            mentions.push(MentionItem {
                display_name: plugin.display_name.clone(),
                description,
                insert_text: format!("${plugin_name}"),
                search_terms,
                path: Some(format!("plugin://{}", plugin.config_name)),
                category_tag: Some("[Plugin]".to_string()),
                sort_rank: 0,
            });
        }
    }

    // Add connectors (apps)
    if self.connectors_enabled && let Some(snapshot) = self.connectors_snapshot.as_ref() {
        for connector in &snapshot.connectors {
            mentions.push(MentionItem {
                display_name: connectors::connector_display_label(connector),
                description: Some(Self::connector_brief_description(connector)),
                insert_text: format!("${slug}"),
                search_terms,
                path: Some(format!("app://{connector_id}")),
                category_tag: Some("[App]".to_string()),
                sort_rank: 1,
            });
        }
    }

    mentions
}
```

### SkillPopup Rendering (`skill_popup.rs`)
```rust
fn rows_from_matches(
    &self,
    matches: Vec<(usize, Option<Vec<usize>>, i32)>,
) -> Vec<GenericDisplayRow> {
    matches
        .into_iter()
        .map(|(idx, indices, _score)| {
            let mention = &self.mentions[idx];
            let name = truncate_text(&mention.display_name, MENTION_NAME_TRUNCATE_LEN);
            let description = match (
                mention.category_tag.as_deref(),
                mention.description.as_deref(),
            ) {
                (Some(tag), Some(description)) if !description.is_empty() => {
                    Some(format!("{tag} {description}"))
                }
                (Some(tag), _) => Some(tag.to_string()),
                (None, Some(description)) if !description.is_empty() => {
                    Some(description.to_string())
                }
                _ => None,
            };
            GenericDisplayRow {
                name,
                name_prefix_spans: Vec::new(),
                match_indices: indices,
                display_shortcut: None,
                description,
                category_tag: None,
                // ...
            }
        })
        .collect()
}
```

### SkillPopup Hint Line (`skill_popup.rs`)
```rust
fn skill_popup_hint_line() -> Line<'static> {
    Line::from(vec![
        "Press ".into(),
        key_hint::plain(KeyCode::Enter).into(),
        " to insert or ".into(),
        key_hint::plain(KeyCode::Esc).into(),
        " to close".into(),
    ])
}
```

## Behavior
1. User types `$` followed by `goog` in the composer
2. `current_mention_token()` detects the `$` prefixed token
3. `sync_mention_popup()` is called with the query "goog"
4. `mention_items()` aggregates mentions from skills, plugins, and connectors
5. The popup filters and displays matching Google Calendar entries
6. Each entry shows its category tag ([Plugin], [Skill], [App]) to distinguish sources
7. User can navigate with Up/Down arrows and select with Enter, or dismiss with Esc

## Test Context
This snapshot is generated by the test `mention_popup_type_prefixes` which verifies that:
- The mention popup correctly displays items from different sources (skills, plugins, apps)
- Each mention type shows the appropriate category prefix tag
- The popup filters mentions based on the typed query
- The hint line is displayed at the bottom
