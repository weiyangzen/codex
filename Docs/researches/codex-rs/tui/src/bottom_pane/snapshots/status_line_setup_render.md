# status_line_setup_render

## Source Information
- **Source File**: codex-rs/tui/src/bottom_pane/status_line_setup.rs
- **Snapshot File**: codex_tui__bottom_pane__status_line_setup__tests__setup_view_snapshot_uses_runtime_preview_values.snap
- **Test Function**: setup_view_snapshot_uses_runtime_preview_values

## Purpose
Tests the StatusLineSetupView rendering with runtime preview values. This snapshot validates the UI for configuring which items appear in the TUI status bar, showing both the configuration list and a live preview of the configured status line.

## Source Code Context
```rust
// From status_line_setup.rs
pub(crate) struct StatusLineSetupView {
    picker: MultiSelectPicker,
}

pub(crate) enum StatusLineItem {
    ModelName,
    ModelWithReasoning,
    CurrentDir,
    ProjectRoot,
    GitBranch,
    ContextRemaining,
    ContextUsed,
    FiveHourLimit,
    WeeklyLimit,
    CodexVersion,
    ContextWindowSize,
    UsedTokens,
    TotalInputTokens,
    TotalOutputTokens,
    SessionId,
    FastMode,
}

impl StatusLinePreviewData {
    fn line_for_items(&self, items: &[MultiSelectItem]) -> Option<Line<'static>> {
        let preview = items
            .iter()
            .filter(|item| item.enabled)
            .filter_map(|item| item.id.parse::<StatusLineItem>().ok())
            .filter_map(|item| self.values.get(&item).cloned())
            .collect::<Vec<_>>()
            .join(" · ");
        if preview.is_empty() {
            None
        } else {
            Some(Line::from(preview))
        }
    }
}
```

## UI Components Involved
- `StatusLineSetupView`: Main configuration view
- `MultiSelectPicker`: Underlying picker widget with ordering support
- `StatusLineItem`: Enum of 16 configurable items
- `StatusLinePreviewData`: Runtime values for preview
- `MultiSelectItem`: Individual picker items

## Key Rendering Logic
The view renders:
1. **Title**: "Configure Status Line"
2. **Description**: "Select which items to display in the status line."
3. **Search area**: "Type to search" with ">" prompt
4. **Item list** (with checkboxes and descriptions):
   - `[x] model-name` - "Current model name"
   - `[x] current-dir` - "Current working directory"
   - `[x] git-branch` - "Current Git branch (omitted when unavailable)"
   - `[ ] model-with-reasoning` - "Current model name with reasoning level"
   - And more items...
5. **Live preview**: Shows actual runtime values (e.g., "gpt-5-codex · ~/codex-rs · jif/statusline-preview")
6. **Instructions**: Navigation and selection key hints

## Test Setup Details
```rust
#[test]
fn setup_view_snapshot_uses_runtime_preview_values() {
    let (tx_raw, _rx) = unbounded_channel::<AppEvent>();
    let view = StatusLineSetupView::new(
        Some(&[
            StatusLineItem::ModelName.to_string(),
            StatusLineItem::CurrentDir.to_string(),
            StatusLineItem::GitBranch.to_string(),
        ]),
        StatusLinePreviewData::from_iter([
            (StatusLineItem::ModelName, "gpt-5-codex".to_string()),
            (StatusLineItem::CurrentDir, "~/codex-rs".to_string()),
            (StatusLineItem::GitBranch, "jif/statusline-preview".to_string()),
            (StatusLineItem::WeeklyLimit, "weekly 82%".to_string()),
        ]),
        AppEventSender::new(tx_raw),
    );
    assert_snapshot!(render_lines(&view, 72));
}
```

## Dependencies
- `MultiSelectPicker`: Reusable multi-select widget
- `StatusLineItem::description()`: User-friendly descriptions
- `strum_macros`: Enum iteration and string serialization
- `BTreeMap`: Ordered storage of preview values

## Notes
- Items can be reordered using left/right arrow keys
- Preview shows real runtime values, not placeholders
- Items serialize to kebab-case for config storage
- Some items are conditionally displayed (e.g., git branch only in repos)
- The preview updates as items are toggled
