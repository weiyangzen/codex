# Research: list_selection_footer_note_wraps Snapshot Test

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer note wrapping behavior in the `ListSelectionView` component. The test ensures that when a selection popup is rendered with a footer note (typically containing helpful hints or instructions), the text wraps correctly within the available width constraints.

**Usage Scenario:**
- Displaying selection popups with additional contextual information in the footer
- Ensuring long footer notes don't overflow the popup boundaries
- Maintaining readability of helper text in narrow terminal windows

## 2. 功能点目的 (Purpose of the Feature)

The footer note wrapping feature serves to:

1. **Display Contextual Help**: Show additional information or instructions below the selection list
2. **Handle Variable Widths**: Adapt to different terminal widths (tested at 40 columns)
3. **Preserve Styling**: Maintain text styling (colors, dimming) across wrapped lines
4. **Prevent Overflow**: Ensure text doesn't extend beyond the popup boundaries

The test specifically validates that a multi-span footer note with mixed styling (dim text + cyan command + dim continuation) wraps correctly and maintains visual hierarchy.

## 3. 具体技术实现 (Technical Implementation)

### Key Implementation Details:

**Footer Note Rendering Flow:**
1. Footer note is stored as `Option<Line<'static>>` in `ListSelectionView`
2. During `render()`, the note width is calculated: `note_width = area.width - 2`
3. `wrap_styled_line()` from `selection_popup_common` is called to wrap the styled line
4. Wrapped lines are rendered with proper indentation (x + 2 offset)

**Wrapping Logic (`selection_popup_common::wrap_styled_line`):**
```rust
pub(crate) fn wrap_styled_line(line: &Line, width: u16) -> Vec<Line> {
    // Uses textwrap to wrap while preserving style spans
    // Handles unicode width correctly
}
```

**Height Calculation:**
```rust
if let Some(note) = &self.footer_note {
    let note_width = width.saturating_sub(2);
    let note_lines = wrap_styled_line(note, note_width);
    height = height.saturating_add(note_lines.len() as u16);
}
```

### Test Setup:
- Creates a `ListSelectionView` with a styled footer note
- Note contains: `"Note: "` (dim) + `"/setup-default-sandbox"` (cyan) + `" to allow network access."` (dim)
- Renders at width 40 to force wrapping

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files:

| File | Path | Description |
|------|------|-------------|
| `list_selection_view.rs` | `codex-rs/tui_app_server/src/bottom_pane/list_selection_view.rs` | Main component implementation |
| `selection_popup_common.rs` | `codex-rs/tui_app_server/src/bottom_pane/selection_popup_common.rs` | Shared wrapping utilities |

### Key Functions:

1. **`ListSelectionView::desired_height()`** (lines 694-757)
   - Calculates total height including wrapped footer note lines

2. **`ListSelectionView::render()`** (lines 759-982)
   - Renders footer note area with proper wrapping
   - Lines 944-980: Footer rendering logic

3. **`wrap_styled_line()`** in `selection_popup_common.rs`
   - Wraps styled text while preserving formatting

### Test Location:
- **Test Function:** `snapshot_footer_note_wraps()`
- **File:** `codex-rs/tui_app_server/src/bottom_pane/list_selection_view.rs` (lines 1234-1263)
- **Snapshot:** `codex_tui__bottom_pane__list_selection_view__tests__list_selection_footer_note_wraps.snap`

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Dependencies:

```rust
// External crates
ratatui::text::Line
ratatui::style::Stylize
textwrap  // For text wrapping
unicode_width::UnicodeWidthStr  // For proper width calculation

// Internal modules
super::selection_popup_common::wrap_styled_line
```

### Related Components:

- **`SelectionViewParams`**: Configuration struct that accepts `footer_note: Option<Line<'static>>`
- **`standard_popup_hint_line()`**: Helper from `popup_consts` for default footer hints

### Styling Dependencies:
- Uses ratatui's `Stylize` trait for `.dim()` and `.cyan()` modifiers
- Styles are preserved through the wrapping process

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks and Edge Cases:

1. **Very Narrow Widths**: At extremely narrow widths (< 20 columns), the wrapping may produce poor results
2. **Unicode Characters**: Complex unicode (emoji, CJK) may not wrap at character boundaries correctly
3. **Style Loss**: If wrapping logic changes, styled spans might be lost or misaligned
4. **Memory**: Each wrapped line creates new `Line` objects; very long notes could allocate significantly

### Current Limitations:

1. **Fixed Indentation**: Wrapped lines don't have hanging indent - they start at the same position
2. **No Hyphenation**: Long words simply break at width boundary without hyphenation
3. **Single Column Layout**: Footer notes don't support multi-column layouts

### Improvement Suggestions:

1. **Hanging Indent**: Add support for indented continuation lines:
   ```rust
   // Current:
   Note: Use /setup-default-sandbox to
   allow network access.
   
   // Improved:
   Note: Use /setup-default-sandbox to
         allow network access.
   ```

2. **Minimum Width Enforcement**: Add a minimum viable width check to prevent rendering at unusable widths

3. **Truncation Indicator**: Add "..." when content is truncated due to height limits

4. **Test Coverage**: Add tests for:
   - Unicode content wrapping
   - Very long single words
   - Multiple styled spans in one note
   - Empty footer notes

### Maintenance Notes:

- The snapshot includes the visual output at 40-column width
- Any changes to wrapping logic or styling will require snapshot updates
- The test uses `render_lines_with_width(&view, 40)` to simulate narrow terminals
