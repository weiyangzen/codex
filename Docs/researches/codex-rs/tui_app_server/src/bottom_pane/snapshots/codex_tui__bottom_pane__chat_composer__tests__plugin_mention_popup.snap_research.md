# Plugin Mention Popup Snapshot Research

## 1. 场景与职责 (Usage Scenario and Responsibility)

This snapshot test validates the **plugin mention popup UI** in the chat composer. It tests the scenario where a user types `$sa` to trigger the mention popup for plugins, which displays matching plugin capabilities that can be inserted into the chat input.

**Responsibilities:**
- Display plugin mentions with their display names, descriptions, and capability labels
- Allow users to select and insert plugin references (e.g., `$sample`) into the composer text
- Provide visual feedback for the selected plugin mention

## 2. 功能点目的 (Feature Purpose)

The plugin mention popup serves to:
1. **Discoverability**: Help users discover available plugins that extend Codex functionality
2. **Quick Insertion**: Allow users to quickly insert plugin references using `$` prefix
3. **Contextual Information**: Show plugin capabilities (skills, MCP servers, apps) to help users understand what each plugin offers
4. **Keyboard Navigation**: Support Up/Down arrow keys and Enter to select mentions

## 3. 具体技术实现 (Technical Implementation)

### Core Components

**SkillPopup (`skill_popup.rs`)**:
- Renders the mention popup with plugin items
- Handles fuzzy matching of query against plugin names
- Displays plugin metadata including display name, description, and capability labels

**MentionItem Structure**:
```rust
pub struct MentionItem {
    pub display_name: String,
    pub description: Option<String>,
    pub insert_text: String,        // e.g., "$sample"
    pub search_terms: Vec<String>,
    pub path: Option<String>,       // e.g., "plugin://sample@test"
    pub category_tag: Option<String>, // e.g., "[Plugin]"
    pub sort_rank: i32,
}
```

**PluginCapabilitySummary** (from `codex_core::plugins`):
- `config_name`: Plugin identifier (e.g., "sample@test")
- `display_name`: Human-readable name
- `description`: Optional plugin description
- `has_skills`: Whether plugin provides skills
- `mcp_server_names`: List of MCP servers provided
- `app_connector_ids`: List of app connectors

### Mention Generation Logic (`mention_items()` method in `chat_composer.rs`):

```rust
if let Some(plugins) = self.plugins.as_ref() {
    for plugin in plugins {
        let (plugin_name, marketplace_name) = plugin
            .config_name
            .split_once('@')
            .unwrap_or((plugin.config_name.as_str(), ""));
        
        // Build capability labels (skills, MCP servers, apps)
        let mut capability_labels = Vec::new();
        if plugin.has_skills { capability_labels.push("skills".to_string()); }
        if !plugin.mcp_server_names.is_empty() { 
            capability_labels.push(format!("{} MCP servers", plugin.mcp_server_names.len()));
        }
        if !plugin.app_connector_ids.is_empty() {
            capability_labels.push(format!("{} apps", plugin.app_connector_ids.len()));
        }
        
        mentions.push(MentionItem {
            display_name: plugin.display_name.clone(),
            description: /* capability labels or plugin.description */,
            insert_text: format!("${plugin_name}"),
            search_terms: vec![plugin_name.to_string(), plugin.config_name.clone()],
            path: Some(format!("plugin://{}", plugin.config_name)),
            category_tag: Some("[Plugin]".to_string()),
            sort_rank: 0, // Plugins sorted before skills
        });
    }
}
```

### Popup Trigger Mechanism

The mention popup is triggered when:
1. User types `$` followed by characters
2. `current_mention_token()` extracts the query after `$`
3. `sync_mention_popup()` creates/updates the `SkillPopup` with filtered mentions

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files

| File | Purpose |
|------|---------|
| `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs` | Main composer logic, mention popup integration |
| `codex-rs/tui_app_server/src/bottom_pane/skill_popup.rs` | Skill/Plugin mention popup implementation |
| `codex-core/src/plugins.rs` | PluginCapabilitySummary definition |

### Key Methods in `chat_composer.rs`

- **`mention_items()`** (lines 3591-3693): Generates mention items from skills, plugins, and connectors
- **`sync_mention_popup()`** (lines 3567-3589): Synchronizes popup state with current query
- **`handle_key_event_with_skill_popup()`** (lines 1766-1837): Handles keyboard navigation in mention popup
- **`insert_selected_mention()`**: Inserts the selected mention into the textarea

### Test Location

```rust
#[test]
fn plugin_mention_popup_snapshot() {
    snapshot_composer_state("plugin_mention_popup", false, |composer| {
        composer.set_text_content("$sa".to_string(), Vec::new(), Vec::new());
        composer.set_plugin_mentions(Some(vec![PluginCapabilitySummary {
            config_name: "sample@test".to_string(),
            display_name: "Sample Plugin".to_string(),
            description: Some("Plugin that includes the Figma MCP server and Skills for common workflows".to_string()),
            has_skills: true,
            mcp_server_names: vec!["sample".to_string()],
            app_connector_ids: vec![codex_core::plugins::AppConnectorId("calendar".to_string())],
        }]));
    });
}
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Dependencies

```rust
use codex_core::plugins::PluginCapabilitySummary;
use codex_core::skills::model::SkillMetadata;
use codex_chatgpt::connectors::AppInfo;
```

### External Interactions

| Component | Interaction |
|-----------|-------------|
| `PluginCapabilitySummary` | Provides plugin metadata from `codex-core` |
| `SkillPopup` | Renders the popup UI using `ratatui` |
| `TextArea` | Inserts selected mentions as elements |
| `AppEventSender` | Emits events for mention selection |

### Mention Binding

When a mention is selected, a `ComposerMentionBinding` is created:
```rust
struct ComposerMentionBinding {
    mention: String,  // e.g., "$sample"
    path: String,     // e.g., "plugin://sample@test"
}
```

These bindings are preserved in history and used during submission to resolve the actual plugin path.

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvements)

### Risks

1. **Plugin Name Collision**: Multiple plugins with similar names may cause confusion in fuzzy matching
2. **Large Plugin Lists**: Performance degradation with many plugins (no pagination currently)
3. **Stale Plugin Data**: Plugin capabilities may change after the popup is opened

### Edge Cases

| Case | Handling |
|------|----------|
| Empty plugin list | Popup doesn't open (`mentions_enabled()` returns false) |
| Disabled plugins | Excluded from mention list (filtered by `is_enabled`) |
| Special characters in plugin names | URL-encoded in `plugin://` path |
| Duplicate plugin names | Both shown with different config names |

### Current Limitations

1. **No Real-time Updates**: Plugin list is static after popup opens
2. **No Plugin Icons**: Only text-based display (no visual branding)
3. **Limited Description**: Truncated descriptions in popup row

### Improvement Suggestions

1. **Caching**: Cache plugin mentions to avoid rebuilding on every keystroke
2. **Favorites**: Show frequently used plugins at the top
3. **Search Enhancement**: Support searching by capability (e.g., "figma" finds plugins with Figma MCP)
4. **Async Loading**: Load plugin metadata asynchronously for better responsiveness
5. **Visual Indicators**: Add icons or colors to distinguish plugin types

### Testing Considerations

- Test with empty plugin list
- Test with plugins having no description
- Test with very long plugin names
- Test keyboard navigation (Up/Down/Enter/Esc)
- Test mention insertion and path resolution
