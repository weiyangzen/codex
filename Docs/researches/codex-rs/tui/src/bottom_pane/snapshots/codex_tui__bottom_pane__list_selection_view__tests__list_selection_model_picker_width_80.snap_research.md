# Research: list_selection_model_picker_width_80

## 1. Feature Overview

This snapshot tests the `ListSelectionView` rendering of a model picker interface at 80 columns width. It demonstrates the component's ability to display complex selection items with long descriptions that wrap across multiple lines, simulating a real-world model selection UI (like `/model` command).

## 2. Code Location

- **Test Function**: `snapshot_model_picker_width_80` in `list_selection_view.rs` (line ~1480)
- **Source Module**: `codex-rs/tui/src/bottom_pane/list_selection_view.rs`
- **Related Feature**: Model picker (`/model` command)

## 3. Snapshot Description

The snapshot shows a model selection popup at 80 columns width containing three GPT model options:

**Header:**
- Title: "Select Model and Effort"

**Model Options:**

1. **gpt-5.1-codex** (current)
   - Description wraps to 2 lines:
     - "Optimized for Codex. Balance of reasoning"
     - "quality and coding ability."

2. **gpt-5.1-codex-mini**
   - Description wraps to 2 lines:
     - "Optimized for Codex. Cheaper, faster, but less"
     - "capable."

3. **gpt-4.1-codex**
   - Description wraps to 2 lines:
     - "Legacy model. Use when you need compatibility"
     - "with older automations."

The selected item (gpt-5.1-codex) is marked with `›` and styled in cyan/bold.

## 4. Key Concepts

### SelectionItem Structure

```rust
pub(crate) struct SelectionItem {
    pub name: String,
    pub description: Option<String>,
    pub is_current: bool,  // Marks as "(current)"
    pub is_default: bool,  // Marks as "(default)"
    pub dismiss_on_select: bool,
    // ...
}
```

### Description Wrapping

The description column uses `wrap_row_lines` which:
1. Calculates the description column position based on content
2. Wraps long descriptions to fit the available right-column space
3. Indents wrapped lines to align with the description start column

### Current/Default Markers

```rust
let marker = if item.is_current {
    " (current)"
} else if item.is_default {
    " (default)"
} else {
    ""
};
```

## 5. Test Setup

```rust
#[test]
fn snapshot_model_picker_width_80() {
    let items = vec![
        SelectionItem {
            name: "gpt-5.1-codex".to_string(),
            description: Some(
                "Optimized for Codex. Balance of reasoning quality and coding ability."
                    .to_string(),
            ),
            is_current: true,
            dismiss_on_select: true,
            ..Default::default()
        },
        SelectionItem {
            name: "gpt-5.1-codex-mini".to_string(),
            description: Some(
                "Optimized for Codex. Cheaper, faster, but less capable.".to_string(),
            ),
            dismiss_on_select: true,
            ..Default::default()
        },
        SelectionItem {
            name: "gpt-4.1-codex".to_string(),
            description: Some(
                "Legacy model. Use when you need compatibility with older automations."
                    .to_string(),
            ),
            dismiss_on_select: true,
            ..Default::default()
        },
    ];
    let view = ListSelectionView::new(
        SelectionViewParams {
            title: Some("Select Model and Effort".to_string()),
            items,
            ..Default::default()
        },
        tx,
    );
    assert_snapshot!(
        "list_selection_model_picker_width_80",
        render_lines_with_width(&view, 80)
    );
}
```

## 6. Dependencies

- `SelectionItem` - Data model for selectable items
- `SelectionViewParams` - Configuration for the selection view
- `ColumnWidthMode::AutoVisible` (default) - Dynamic column sizing
- `wrap_row_lines` - Multi-line description wrapping

## 7. Related Snapshots

| Snapshot | Description |
|----------|-------------|
| `list_selection_narrow_width_preserves_rows` | Same content at 24 columns (extreme narrow) |
| `width_changes_do_not_hide_rows` | Unit test verifying all options visible across widths 60-90 |

## 8. Real-World Usage

This snapshot represents the actual UI shown when users run the `/model` command:
- Lists available AI models
- Shows which model is currently active via `(current)` marker
- Provides descriptive text explaining each model's characteristics
- Handles varying description lengths through text wrapping

The 80-column width is a common terminal width that balances readability with space efficiency.
