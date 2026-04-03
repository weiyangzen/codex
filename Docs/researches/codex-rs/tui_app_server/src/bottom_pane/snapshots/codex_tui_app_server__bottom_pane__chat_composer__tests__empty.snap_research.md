# Snapshot Research: Chat Composer Empty State

## 1. 场景与职责 (Scene and Responsibility)

This snapshot tests the **ChatComposer** component in its initial empty state - when no text has been entered, no attachments are present, and no popups are active. This is the baseline rendering state that users see when they first open the TUI or after submitting a message.

**Key Responsibilities:**
- Display an editable textarea with proper placeholder text
- Render the footer with appropriate hints for the empty state
- Show the collaboration mode indicator if enabled
- Maintain proper cursor positioning and focus state

## 2. 功能点目的 (Functional Purpose)

The empty state serves as the "home" state of the chat composer, providing:

- **Visual affordances**: Shows users where to type and what shortcuts are available
- **Context awareness**: Displays mode indicators (Plan/Execute/Pair Programming) when collaboration modes are enabled
- **Accessibility**: Clear visual hierarchy with proper spacing and indentation

**Test Coverage:**
- Validates baseline rendering without any user input
- Ensures footer shows "? for shortcuts" hint in empty state
- Verifies proper height calculation and layout

## 3. 具体技术实现 (Technical Implementation)

### Core Data Structures

```rust
// From chat_composer.rs
pub(crate) struct ChatComposer {
    textarea: TextArea,
    textarea_state: RefCell<TextAreaState>,
    active_popup: ActivePopup,  // ActivePopup::None in empty state
    footer_mode: FooterMode,    // FooterMode::ComposerEmpty
    // ... other fields
}

enum ActivePopup {
    None,
    Command(CommandPopup),
    File(FileSearchPopup),
    Skill(SkillPopup),
}

// From footer.rs
pub(crate) enum FooterMode {
    ComposerEmpty,      // <- Used in this snapshot
    ComposerHasDraft,
    QuitShortcutReminder,
    ShortcutOverlay,
    EscHint,
}
```

### Rendering Flow

1. **Layout Calculation** (`layout_areas` method):
   - Calculates footer height based on `FooterProps`
   - Reserves space for remote image rows (if any)
   - Returns `[composer_rect, remote_images_rect, textarea_rect, popup_rect]`

2. **Footer Rendering** (`footer_from_props_lines`):
   - For `FooterMode::ComposerEmpty`, shows shortcuts hint
   - Applies width-based collapse logic via `single_line_footer_layout`

3. **TextArea Rendering**:
   - Uses `StatefulWidgetRef` pattern for ratatui integration
   - Cursor positioned at end of content (empty = position 0)

### Key Constants

```rust
const FOOTER_SPACING_HEIGHT: u16 = 0;
const LIVE_PREFIX_COLS: u16 = 2;  // Left indent for textarea
```

## 4. 关键代码路径与文件引用 (Key Code Paths)

### Primary Files

| File | Lines | Purpose |
|------|-------|---------|
| `chat_composer.rs` | 1-1000+ | Main composer implementation |
| `footer.rs` | 1-1000+ | Footer rendering and mode management |
| `textarea.rs` | (mod) | Text input widget |

### Critical Methods

```rust
// chat_composer.rs
impl ChatComposer {
    pub fn new(...) -> Self                    // Constructor, line ~452
    fn layout_areas(&self, area: Rect) -> [Rect; 4]  // Layout logic, line ~658
    pub fn render(&self, area: Rect, buf: &mut Buffer)  // Main render, line ~1000+
}

// footer.rs
pub(crate) fn footer_from_props_lines(...) -> Vec<Line<'static>>  // line ~580
pub(crate) fn single_line_footer_layout(...) -> (SummaryLeft, bool)  // line ~310
```

### Test Location

```rust
#[cfg(test)]
mod tests {
    #[test]
    fn empty() {  // Creates this snapshot
        let mut composer = make_composer();
        // ... render and snapshot
    }
}
```

## 5. 依赖与外部交互 (Dependencies)

### External Dependencies

- **ratatui**: Terminal UI framework for rendering
- **crossterm**: Key event handling
- **codex_protocol**: TextElement, user input types

### Internal Dependencies

```rust
use super::footer::{FooterProps, FooterMode, render_footer_from_props};
use super::textarea::{TextArea, TextAreaState};
use crate::app_event_sender::AppEventSender;
```

### Event Flow

```
User Input -> ChatComposer::handle_key_event()
    -> If popup active: route to popup
    -> Else: handle_key_event_without_popup()
    -> sync_popups() to update UI state
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, Improvements)

### Known Risks

1. **Width Collapse**: Footer hint text may be truncated on narrow terminals (< 40 cols)
2. **Focus State**: Empty state must properly indicate focus for accessibility
3. **Placeholder Text**: Long placeholder text may wrap unexpectedly

### Edge Cases

| Scenario | Handling |
|----------|----------|
| Terminal width < 20 | Footer falls back to minimal mode-only display |
| Remote images present | Empty text but non-empty composer (images shown above textarea) |
| Input disabled | Shows placeholder instead of editable textarea |

### Improvement Suggestions

1. **Responsive Design**: Consider dynamic placeholder text based on terminal width
2. **Accessibility**: Add screen reader announcements for mode changes
3. **Performance**: Cache footer layout calculations when state unchanged
4. **Testing**: Add snapshot tests for extreme aspect ratios (very tall/wide)

### Related Snapshots

- `footer_collapse_empty_*.snap` - Footer collapse behavior variants
- `footer_mode_*.snap` - Different footer mode states
- `large.snap`, `small.snap` - Size variant tests
