# Research: render_wrapped_message Snapshot

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates text wrapping behavior for queued messages in the `PendingInputPreview` widget. It ensures that messages exceeding the available width are properly wrapped with correct indentation for continuation lines.

**Usage Scenario:**
- User types a long message that doesn't fit on a single line
- The message needs to wrap while maintaining visual hierarchy
- First line has "↳" prefix, continuation lines have 4-space indent
- Multiple messages with different lengths can be displayed together

## 2. 功能点目的 (Feature Purpose)

The test verifies that:
1. Long messages are wrapped using adaptive text wrapping
2. First line has "↳" prefix with DIM styling
3. Wrapped continuation lines have 4-space indentation
4. All lines maintain DIM + ITALIC styling for message content
5. Multiple messages with different lengths render correctly together
6. Total height accounts for wrapped lines (5 rows total)

## 3. 具体技术实现 (Technical Implementation)

**Test Setup:**
```rust
#[test]
fn render_wrapped_message() {
    let mut queue = PendingInputPreview::new();
    queue.queued_messages.push("This is a longer message that should be wrapped".to_string());
    queue.queued_messages.push("This is another message".to_string());
    let width = 40;
    let height = queue.desired_height(width);
    let mut buf = Buffer::empty(Rect::new(0, 0, width, height));
    queue.render(Rect::new(0, 0, width, height), &mut buf);
    assert_snapshot!("render_wrapped_message", format!("{buf:?}"));
}
```

**Rendering Output Structure:**
```
Row 0: "• Queued follow-up messages             " (DIM bullet + header)
Row 1: "  ↳ This is a longer message that should" (DIM prefix + DIM|ITALIC)
Row 2: "    be wrapped                          " (4-space indent + DIM|ITALIC)
Row 3: "  ↳ This is another message             " (DIM prefix + DIM|ITALIC)
Row 4: "    ⌥ + ↑ edit last queued message      " (DIM hint)
```

**Wrapping Configuration:**
```rust
RtOptions::new(width as usize)
    .initial_indent(Line::from("  ↳ ".dim()))    // First line: "  ↳ "
    .subsequent_indent(Line::from("    "))        // Wrapped lines: "    "
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

**Source Files:**
- `codex-rs/tui/src/bottom_pane/pending_input_preview.rs` - Main widget implementation
- `codex-rs/tui/src/wrapping.rs` - Text wrapping utilities

**Snapshot Location:**
- `codex-rs/tui_app_server/src/bottom_pane/snapshots/codex_tui__bottom_pane__pending_input_preview__tests__render_wrapped_message.snap`

**Key Functions:**
```rust
// Text wrapping with indentation
fn adaptive_wrap_lines(
    lines: impl Iterator<Item = Line<'static>>,
    options: RtOptions,
) -> Vec<Line<'static>>;

// Wrapper that applies truncation
fn push_truncated_preview_lines(
    lines: &mut Vec<Line<'static>>,
    wrapped: Vec<Line<'static>>,
    overflow_line: Line<'static>,
);
```

**Related Test:**
- `long_url_like_message_does_not_expand_into_wrapped_ellipsis_rows` - Tests URL-like tokens

## 5. 依赖与外部交互 (Dependencies and External Interactions)

**Dependencies:**
- `ratatui::text::Line` - Line construction
- `ratatui::style::Stylize` - Styling traits
- `textwrap` (via wrapping module) - Text wrapping algorithm

**Wrapping Module Interface:**
- `adaptive_wrap_lines()` - Wraps lines with configurable indentation
- `RtOptions` - Builder for wrapping options:
  - `new(width)` - Sets maximum width
  - `initial_indent()` - Indent for first line
  - `subsequent_indent()` - Indent for continuation lines

**Styling Chain:**
```rust
message.lines().map(|line| Line::from(line.dim().italic()))
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvements)

**Potential Risks:**
1. **Wrapping Algorithm Changes:** Updates to textwrap or adaptive_wrap_lines could change output
2. **Width Sensitivity:** Test is fixed at 40 chars; real terminals vary
3. **Unicode Width:** Complex Unicode characters may have incorrect width calculations

**Edge Cases:**
1. **Very Long Words:** URLs or long tokens without spaces
   - Handled separately in `long_url_like_message_does_not_expand_into_wrapped_ellipsis_rows`
2. **Exact Width:** Message exactly matching width boundary
3. **Zero-Width Joiners:** Emoji and complex scripts
4. **Newlines in Message:** Multi-line input with explicit newlines

**Notable Related Test:**
The `long_url_like_message_does_not_expand_into_wrapped_ellipsis_rows` test validates that URL-like tokens (long strings without spaces) don't create unwanted ellipsis rows when wrapped.

**Improvement Suggestions:**

1. **Parameterized Width Testing:**
   ```rust
   #[test_case(20)]
   #[test_case(40)]
   #[test_case(80)]
   fn render_wrapped_message_at_width(width: u16) { ... }
   ```

2. **Unicode Testing:**
   - Add tests for CJK characters (wider than Latin)
   - Add tests for emoji (width varies by terminal)
   - Add tests for RTL text

3. **Edge Case Coverage:**
   - Message exactly one character over width
   - Message with only whitespace
   - Message with tab characters
   - Message with consecutive spaces at wrap point

4. **Visual Clarity:**
   - Consider adding continuation indicator (like "↳") to wrapped lines
   - Or use different styling for wrapped portions
   - Consider hanging indent vs block indent options

5. **Performance:**
   - Consider caching wrapped output if width hasn't changed
   - For many messages, wrapping can be expensive

**Code Quality Notes:**
- The `adaptive_wrap_lines` function is shared across the TUI codebase
- The 4-space indent is hardcoded; could be made configurable
- The wrapping behavior should be documented in module-level docs

**Comparison with Legacy `message_queue` Test:**
Both versions test similar wrapping behavior, but the `pending_input_preview` version:
- Includes the section header
- Has one additional row (header)
- Otherwise identical wrapping logic
