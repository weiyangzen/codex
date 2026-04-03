# Research: render_wrapped_message Snapshot

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates text wrapping behavior for queued messages that exceed the available width. It ensures long messages are properly wrapped with correct indentation for continuation lines.

**Usage Scenario:**
- User types a long message that doesn't fit on a single line
- The message needs to be wrapped while maintaining visual hierarchy
- Wrapped lines should be indented differently from the first line to show continuation
- Multiple messages with varying lengths can be displayed together

## 2. 功能点目的 (Feature Purpose)

The test verifies that:
1. Long messages are wrapped at appropriate boundaries (adaptive wrapping)
2. First line has "↳" prefix, continuation lines have 4-space indent
3. Wrapped content maintains the same styling (DIM + ITALIC)
4. Multiple messages with different lengths render correctly together
5. Height calculation accounts for wrapped lines (4 rows total)

## 3. 具体技术实现 (Technical Implementation)

**Test Setup:**
```rust
let mut queue = PendingInputPreview::new();
queue.queued_messages.push("This is a longer message that should be wrapped".to_string());
queue.queued_messages.push("This is another message".to_string());
let width = 40;
let height = queue.desired_height(width);
```

**Rendering Output Structure:**
```
Row 0: "  ↳ This is a longer message that should" (DIM prefix + DIM|ITALIC text)
Row 1: "    be wrapped                          " (4-space indent + DIM|ITALIC text)
Row 2: "  ↳ This is another message             " (DIM prefix + DIM|ITALIC text)
Row 3: "    alt + ↑ edit                        " (DIM hint)
```

**Wrapping Implementation:**
- Uses `adaptive_wrap_lines()` from `crate::wrapping` module
- `RtOptions` configures wrapping behavior:
  - `initial_indent`: `"  ↳ "` (dimmed) - for first line
  - `subsequent_indent`: `"    "` (4 spaces) - for wrapped lines
- Text is styled with `.dim().italic()` before wrapping

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

**Source Files:**
- `codex-rs/tui/src/bottom_pane/pending_input_preview.rs` - Main widget implementation
- `codex-rs/tui/src/wrapping.rs` - Text wrapping utilities (adaptive_wrap_lines)

**Snapshot Location:**
- `codex-rs/tui_app_server/src/bottom_pane/snapshots/codex_tui__bottom_pane__message_queue__tests__render_wrapped_message.snap`

**Key Functions:**
```rust
// From pending_input_preview.rs
fn push_truncated_preview_lines(
    lines: &mut Vec<Line<'static>>,
    wrapped: Vec<Line<'static>>,
    overflow_line: Line<'static>,
) {
    let wrapped_len = wrapped.len();
    lines.extend(wrapped.into_iter().take(PREVIEW_LINE_LIMIT));
    if wrapped_len > PREVIEW_LINE_LIMIT {
        lines.push(overflow_line);
    }
}
```

**Wrapping Options:**
```rust
RtOptions::new(width as usize)
    .initial_indent(Line::from("  ↳ ".dim()))
    .subsequent_indent(Line::from("    "))
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

**Dependencies:**
- `ratatui::text::Line` - Line construction
- `ratatui::style::Stylize` - Styling traits
- `textwrap` (via wrapping module) - Text wrapping algorithm

**Wrapping Module Interface:**
- `adaptive_wrap_lines()` - Wraps lines with configurable indentation
- `RtOptions` - Builder for wrapping options
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
1. **Very Long Words:** URLs or long tokens without spaces (tested separately in `long_url_like_message`)
2. **Exact Width:** Message exactly matching width boundary
3. **Zero-Width Joiners:** Emoji and complex scripts
4. **Newlines in Message:** Multi-line input with explicit newlines

**Notable Test:**
The `long_url_like_message_does_not_expand_into_wrapped_ellipsis_rows` test specifically validates that URL-like tokens don't create unwanted ellipsis rows when wrapped.

**Improvement Suggestions:**
1. **Parameterized Width Testing:** Test wrapping at multiple widths (20, 40, 80, 120)
2. **Unicode Testing:** Add tests for CJK characters, emoji, RTL text
3. **Edge Case Coverage:**
   - Message exactly one character over width
   - Message with only whitespace
   - Message with tab characters
4. **Performance:** Consider caching wrapped output if width hasn't changed
5. **Visual Clarity:** Consider adding visual indicator (like "↳") to wrapped continuation lines

**Code Quality Notes:**
- The `adaptive_wrap_lines` function is shared across the TUI codebase
- Consider documenting the wrapping behavior in the module-level docs
- The 4-space indent for wrapped lines is hardcoded; could be configurable
