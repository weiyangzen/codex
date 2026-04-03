# Small Input Snapshot Research

## 1. 场景与职责 (Usage Scenario and Responsibility)

This snapshot test validates the **basic chat composer rendering** with a small amount of text input ("short"). It tests the fundamental UI layout and styling when the composer contains minimal content, serving as a baseline for composer appearance.

**Responsibilities:**
- Render the composer with basic text content
- Display the prompt prefix ("›")
- Show footer with context information
- Maintain proper spacing and layout

## 2. 功能点目的 (Feature Purpose)

This test establishes the baseline appearance:
1. **Visual Regression**: Detect unintended UI changes
2. **Layout Validation**: Ensure consistent rendering across changes
3. **Styling Verification**: Confirm text styling and colors
4. **Footer Display**: Verify context window indicator shows correctly

The "small" test specifically uses short text to test:
- Single-line textarea rendering
- Minimal content layout
- Standard footer display with context percentage

## 3. 具体技术实现 (Technical Implementation)

### Test Implementation

```rust
#[test]
fn ui_snapshots() {
    let test_cases = vec![
        ("empty", None),
        ("small", Some("short".to_string())), // This test
        ("large", Some("z".repeat(LARGE_PASTE_CHAR_THRESHOLD + 5))),
        ("multiple_pastes", None),
        ("backspace_after_pastes", None),
    ];
    
    for (name, input) in test_cases {
        let mut composer = ChatComposer::new(
            true, sender.clone(), false,
            "Ask Codex to do anything".to_string(),
            false,
        );
        
        if let Some(text) = input {
            composer.handle_paste(text);
        }
        
        terminal.draw(|f| composer.render(f.area(), f.buffer_mut())).unwrap();
        insta::assert_snapshot!(name, terminal.backend());
    }
}
```

### Rendering Flow

**`render()` method** (lines 4184-4187):
```rust
impl Renderable for ChatComposer {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        self.render_with_mask(area, buf, /*mask_char*/ None);
    }
}
```

**`render_with_mask()` method** (lines 4189-4451):
```rust
pub(crate) fn render_with_mask(&self, area: Rect, buf: &mut Buffer, mask_char: Option<char>) {
    // 1. Calculate layout areas
    let [composer_rect, remote_images_rect, textarea_rect, popup_rect] =
        self.layout_areas(area);
    
    // 2. Render popup if active
    match &self.active_popup {
        ActivePopup::Command(popup) => popup.render_ref(popup_rect, buf),
        // ...
        ActivePopup::None => {
            // 3. Render footer hints
            self.render_footer(popup_rect, buf);
        }
    }
    
    // 4. Render composer block border
    let style = user_message_style();
    Block::default().style(style).render_ref(composer_rect, buf);
    
    // 5. Render remote images (if any)
    if !remote_images_rect.is_empty() {
        Paragraph::new(self.remote_images_lines(remote_images_rect.width))
            .style(style)
            .render_ref(remote_images_rect, buf);
    }
    
    // 6. Render prompt prefix
    if !textarea_rect.is_empty() {
        let prompt = if self.input_enabled { "›".bold() } else { "›".dim() };
        buf.set_span(
            textarea_rect.x - LIVE_PREFIX_COLS,
            textarea_rect.y,
            &prompt,
            textarea_rect.width,
        );
    }
    
    // 7. Render textarea content
    let mut state = self.textarea_state.borrow_mut();
    StatefulWidgetRef::render_ref(&(&self.textarea), textarea_rect, buf, &mut state);
    
    // 8. Render placeholder if empty
    if self.textarea.text().is_empty() {
        let text = if self.input_enabled {
            self.placeholder_text.as_str().to_string()
        } else {
            self.input_disabled_placeholder.as_deref().unwrap_or("Input disabled.")
        };
        let placeholder = Span::from(text).dim();
        Line::from(vec![placeholder]).render_ref(textarea_rect, buf);
    }
}
```

### Layout Calculation

**`layout_areas()` method** (lines 658-700):
```rust
fn layout_areas(&self, area: Rect) -> [Rect; 4] {
    // Calculate footer height
    let footer_props = self.footer_props();
    let footer_hint_height = footer_height(&footer_props);
    let footer_spacing = Self::footer_spacing(footer_hint_height);
    let footer_total_height = footer_hint_height + footer_spacing;
    
    // Split area into composer and popup/footer
    let [composer_rect, popup_rect] =
        Layout::vertical([Constraint::Min(3), popup_constraint]).areas(area);
    
    // Calculate textarea rect with margins
    let mut textarea_rect = composer_rect.inset(Insets::tlbr(
        /*top*/ 1,
        LIVE_PREFIX_COLS,
        /*bottom*/ 1,
        /*right*/ 1,
    ));
    
    // Adjust for remote images
    let remote_images_height = /* calculate */;
    // ... adjust textarea_rect
    
    [composer_rect, remote_images_rect, textarea_rect, popup_rect]
}
```

### Expected Output

```
"                                                                                                    "
"› short                                                                                             "
"                                                                                                    "
"                                                                                                    "
"                                                                                                    "
"                                                                                                    "
"                                                                                                    "
"                                                                                                    "
"                                                                                                    "
"                                                                                 100% context left  "
```

Key elements:
- Line 1: Empty padding
- Line 2: "›" prefix + "short" text
- Lines 3-9: Empty space for textarea
- Line 10: Footer with "100% context left"

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files

| File | Purpose |
|------|---------|
| `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs` | Main composer implementation |
| `codex-rs/tui_app_server/src/bottom_pane/textarea.rs` | TextArea widget |
| `codex-rs/tui_app_server/src/bottom_pane/footer.rs` | Footer rendering |

### Key Methods

| Method | Line Range | Purpose |
|--------|------------|---------|
| `render_with_mask()` | 4189-4451 | Main rendering logic |
| `layout_areas()` | 658-700 | Calculates layout rectangles |
| `footer_props()` | 3193-3220 | Builds footer properties |
| `footer_height()` | (footer.rs) | Calculates footer height |

### Styling

**`user_message_style()`**:
```rust
fn user_message_style() -> Style {
    Style::default().fg(Color::Cyan)
}
```

**Prompt styling**:
```rust
let prompt = if self.input_enabled { "›".bold() } else { "›".dim() };
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Dependencies

```rust
use ratatui::buffer::Buffer;
use ratatui::layout::{Constraint, Layout, Margin, Rect};
use ratatui::style::Stylize;
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Paragraph, StatefulWidgetRef};
```

### Layout Constants

```rust
const LIVE_PREFIX_COLS: u16 = 2; // Width of "› " prefix
const FOOTER_INDENT_COLS: usize = 2;
const FOOTER_SPACING_HEIGHT: u16 = 0;
```

### Footer Context

The footer displays context window usage:
```rust
fn context_window_line(percent: Option<i64>, used_tokens: Option<i64>) -> Line<'static> {
    // Renders "X% context left" or similar
}
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvements)

### Baseline Test Risks

1. **Fragile Snapshots**: Any UI change breaks this test
2. **Terminal Width**: Snapshot is width-specific (100 columns)
3. **Color Codes**: Terminal color handling may vary

### Edge Cases

| Case | Handling |
|------|----------|
| Empty text | Shows placeholder ("Ask Codex to do anything") |
| Single character | Renders correctly with prefix |
| Very long text | Wraps or truncates based on textarea logic |
| Unicode text | Should render multi-byte chars correctly |

### Comparison with Other UI Tests

| Test | Input | Purpose |
|------|-------|---------|
| `empty` | None | Baseline with placeholder |
| `small` | "short" | Minimal content (this test) |
| `large` | 1000+ chars | Large paste placeholder |
| `multiple_pastes` | Multiple | Multiple placeholder handling |
| `backspace_after_pastes` | Edited | Placeholder deletion |

### Improvement Suggestions

1. **Parameterized Width**: Test at multiple terminal widths
2. **Theme Testing**: Test with different color schemes
3. **Unicode Coverage**: Include emoji and CJK characters
4. **Accessibility**: Test with screen reader output
5. **Performance**: Benchmark rendering speed

### Testing Best Practices

1. **Review Changes**: Carefully review snapshot diffs
2. **Intentional Updates**: Only update when changes are intentional
3. **Cross-Platform**: Verify snapshots match across OSes
4. **Documentation**: Document intentional visual changes

### Potential Visual Issues

1. **Alignment**: Prefix alignment with text
2. **Spacing**: Consistent padding around elements
3. **Colors**: Visibility on different terminal backgrounds
4. **Contrast**: Footer text readability
