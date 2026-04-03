# skills_toggle_view_basic

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/skills_toggle_view.rs
- **Snapshot File**: codex_tui__bottom_pane__skills_toggle_view__tests__skills_toggle_basic.snap
- **Test Function**: renders_basic_popup

## Purpose
Tests the SkillsToggleView popup rendering with multiple skills in different states (enabled/disabled). This snapshot validates the UI for the skill management interface where users can enable or disable skills.

## Source Code Context
```rust
// From skills_toggle_view.rs
pub(crate) struct SkillsToggleView {
    items: Vec<SkillsToggleItem>,
    state: ScrollState,
    complete: bool,
    app_event_tx: AppEventSender,
    header: Box<dyn Renderable>,
    footer_hint: Line<'static>,
    search_query: String,
    filtered_indices: Vec<usize>,
}

pub(crate) struct SkillsToggleItem {
    pub name: String,
    pub skill_name: String,
    pub description: String,
    pub enabled: bool,
    pub path: PathBuf,
}

fn build_rows(&self) -> Vec<GenericDisplayRow> {
    self.filtered_indices
        .iter()
        .enumerate()
        .filter_map(|(visible_idx, actual_idx)| {
            self.items.get(*actual_idx).map(|item| {
                let is_selected = self.state.selected_idx == Some(visible_idx);
                let prefix = if is_selected { '›' } else { ' ' };
                let marker = if item.enabled { 'x' } else { ' ' };
                let item_name = truncate_skill_name(&item.name);
                let name = format!("{prefix} [{marker}] {item_name}");
                GenericDisplayRow {
                    name,
                    description: Some(item.description.clone()),
                    ..Default::default()
                }
            })
        })
        .collect()
}
```

## UI Components Involved
- `SkillsToggleView`: Main popup widget
- `SkillsToggleItem`: Individual skill data
- `ScrollState`: Selection and scroll position
- `GenericDisplayRow`: Row rendering format
- `render_rows_single_line()`: Renders the skill list
- `truncate_skill_name()`: Truncates long skill names

## Key Rendering Logic
The popup renders:
1. **Header** (bold):
   - "Enable/Disable Skills"
   - "Turn skills on or off. Your changes are saved automatically." (dimmed)
2. **Search area**:
   - Placeholder: "Type to search skills" (dimmed)
   - Input prompt: ">"
3. **Skill list**:
   - Selected item marked with "›"
   - Checkbox: "[x]" for enabled, "[ ]" for disabled
   - Skill name and description
4. **Footer hint**: "Press space or enter to toggle; esc to close"

## Test Setup Details
```rust
#[test]
fn renders_basic_popup() {
    let (tx_raw, _rx) = unbounded_channel::<AppEvent>();
    let tx = AppEventSender::new(tx_raw);
    let items = vec![
        SkillsToggleItem {
            name: "Repo Scout".to_string(),
            skill_name: "repo_scout".to_string(),
            description: "Summarize the repo layout".to_string(),
            enabled: true,
            path: PathBuf::from("/tmp/skills/repo_scout.toml"),
        },
        SkillsToggleItem {
            name: "Changelog Writer".to_string(),
            skill_name: "changelog_writer".to_string(),
            description: "Draft release notes".to_string(),
            enabled: false,
            path: PathBuf::from("/tmp/skills/changelog_writer.toml"),
        },
    ];
    let view = SkillsToggleView::new(items, tx);
    assert_snapshot!("skills_toggle_basic", render_lines(&view, 72));
}
```

## Dependencies
- `crate::skills_helpers::match_skill`: Fuzzy search matching
- `crate::skills_helpers::truncate_skill_name`: Name truncation
- `super::popup_consts::MAX_POPUP_ROWS`: Maximum visible rows
- `super::selection_popup_common`: Row rendering utilities
- `strum` for enum iteration

## Notes
- Skills are displayed with checkboxes showing enabled state
- The first skill is selected by default (marked with "›")
- Users can search/filter skills by typing
- Changes are saved automatically when toggled
- Supports fuzzy matching for skill search
