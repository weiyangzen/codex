# Research: list_selection_spacing_with_subtitle Snapshot Test

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the vertical spacing layout in `ListSelectionView` when both a title and subtitle are provided. The test ensures proper visual hierarchy and readability by maintaining consistent blank lines between the header section and the selection items.

**Usage Scenario:**
- Selection popups that need additional context beyond just a title
- Complex selection interfaces where the subtitle explains the purpose
- Theme picker, approval mode selector, and other multi-line header scenarios

## 2. 功能点目的 (Purpose of the Feature)

The spacing with subtitle feature serves to:

1. **Visual Separation**: Create clear visual distinction between header and content
2. **Information Hierarchy**: Present title → subtitle → items in descending importance
3. **Consistent Layout**: Maintain predictable spacing regardless of content
4. **Readability**: Prevent visual crowding that reduces comprehension

The test validates that:
- A blank line appears between the subtitle and the items
- The title is bold and prominent
- The subtitle is dimmed (less prominent)
- The overall layout follows the pattern: title → blank → subtitle → blank → items

## 3. 具体技术实现 (Technical Implementation)

### Key Implementation Details:

**Header Construction (`ListSelectionView::new`, lines 245-255):**
```rust
let mut header = params.header;
if params.title.is_some() || params.subtitle.is_some() {
    let title = params.title.map(|title| Line::from(title.bold()));
    let subtitle = params.subtitle.map(|subtitle| Line::from(subtitle.dim()));
    header = Box::new(ColumnRenderable::with([
        header,
        Box::new(title),
        Box::new(subtitle),
    ]));
}
```

**Layout Structure:**
```
┌────────────────────────────────────────┐
│                                        │
│  Title (bold)                          │  ← Line 0
│  Subtitle (dim)                        │  ← Line 1
│                                        │  ← Line 2 (blank separator)
│  › 1. Item 1 (current)  Description    │  ← Line 3+
│  2. Item 2              Description    │
│                                        │
│  Footer hint                           │
└────────────────────────────────────────┘
```

**Spacing Rules:**
1. Always one blank line between header (title/subtitle) and items
2. Title and subtitle are consecutive (no blank line between them)
3. The blank line is part of the standard menu surface padding

### Test Setup:
- Creates a selection view with title "Select Approval Mode"
- Adds subtitle "Switch between Codex approval presets"
- Two items: "Read Only" (current) and "Full Access"
- Uses default 48-column width

**Test Code:**
```rust
fn make_selection_view(subtitle: Option<&str>) -> ListSelectionView {
    let items = vec![
        SelectionItem {
            name: "Read Only".to_string(),
            description: Some("Codex can read files".to_string()),
            is_current: true,
            dismiss_on_select: true,
            ..Default::default()
        },
        SelectionItem {
            name: "Full Access".to_string(),
            description: Some("Codex can edit files".to_string()),
            dismiss_on_select: true,
            ..Default::default()
        },
    ];
    ListSelectionView::new(
        SelectionViewParams {
            title: Some("Select Approval Mode".to_string()),
            subtitle: subtitle.map(str::to_string),
            footer_hint: Some(standard_popup_hint_line()),
            items,
            ..Default::default()
        },
        tx,
    )
}
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files:

| File | Path | Description |
|------|------|-------------|
| `list_selection_view.rs` | `codex-rs/tui_app_server/src/bottom_pane/list_selection_view.rs` | Main component implementation |
| `renderable.rs` | `codex-rs/tui_app_server/src/render/renderable.rs` | `ColumnRenderable` implementation |

### Key Functions:

1. **`ListSelectionView::new()`** (lines 245-286)
   - Constructs header with title and subtitle
   - Uses `ColumnRenderable` to stack header elements

2. **`ColumnRenderable::with()`** in `renderable.rs`
   - Combines multiple renderables into a vertical column
   - Each element renders on consecutive lines

3. **`render_menu_surface()`** in `selection_popup_common.rs`
   - Renders the bordered popup container
   - Provides consistent padding around content

### Test Location:
- **Test Function:** `renders_blank_line_between_subtitle_and_items()`
- **File:** `codex-rs/tui_app_server/src/bottom_pane/list_selection_view.rs` (lines 1162-1165)
- **Snapshot:** `codex_tui__bottom_pane__list_selection_view__tests__list_selection_spacing_with_subtitle.snap`

### Related Tests:
- `renders_blank_line_between_title_and_items_without_subtitle()`: Tests spacing without subtitle

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Dependencies:

```rust
// External crates
ratatui::text::Line
ratatui::style::Stylize  // For .bold() and .dim()

// Internal modules
crate::render::renderable::ColumnRenderable
super::popup_consts::standard_popup_hint_line
```

### Styling:

```rust
// Title styling
Line::from(title.bold())

// Subtitle styling  
Line::from(subtitle.dim())
```

### Layout Components:

**`ColumnRenderable`:**
- Stacks child renderables vertically
- Each child occupies its own `Rect` within the column
- Total height is sum of child heights

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks and Edge Cases:

1. **Long Subtitles**: Very long subtitles may wrap, consuming more vertical space
2. **Empty Subtitle**: Passing empty string vs `None` may produce different spacing
3. **Unicode in Subtitle**: Special characters may affect line height calculations
4. **Screen Height**: With title + subtitle + many items, popup may exceed screen height

### Current Limitations:

1. **Fixed Spacing**: Always exactly one blank line; no customization option
2. **No Separator Line**: Visual separation is only whitespace, not a horizontal rule
3. **Subtitle Truncation**: Long subtitles wrap but don't truncate with "..."

### Improvement Suggestions:

1. **Configurable Spacing**: Allow customization of blank lines:
   ```rust
   pub struct SelectionViewParams {
       // ... existing fields
       pub header_spacing: u16,  // Number of blank lines after header
   }
   ```

2. **Separator Option**: Add optional horizontal separator:
   ```rust
   pub enum HeaderSeparator {
       None,       // Current behavior
       BlankLine,  // Current behavior (default)
       Rule,       // "────────────────────"
   }
   ```

3. **Subtitle Truncation**: Add max lines for subtitle:
   ```rust
   let subtitle = params.subtitle.map(|subtitle| {
       Line::from(truncate_to_lines(subtitle, MAX_SUBTITLE_LINES).dim())
   });
   ```

4. **Test Coverage**:
   - Test with very long subtitle (wrapping)
   - Test with empty subtitle string
   - Test with multiline subtitle (contains `\n`)
   - Test with CJK characters in subtitle

### Maintenance Notes:

- The snapshot shows the exact vertical spacing pattern
- Title appears on line 1, subtitle on line 2, blank on line 3, items start on line 4
- Changes to `ColumnRenderable` spacing or menu surface padding will affect this test
- This test is paired with the "without_subtitle" variant to ensure consistent behavior

### Visual Comparison:

**With Subtitle:**
```
  Select Approval Mode
  Switch between Codex approval presets
  
  › 1. Read Only (current)  Codex can read files
```

**Without Subtitle:**
```
  Select Approval Mode
  
  › 1. Read Only (current)  Codex can read files
```

The key difference is the presence of the subtitle line and the consistent blank line before items in both cases.
