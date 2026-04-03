# Research: render_multiline_pending_steer_uses_single_prefix_and_truncates Snapshot

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the rendering of multiline "pending steers" - messages that will be submitted after the next tool call completes. Pending steers are distinct from queued messages and have their own section with different styling and behavior.

**Usage Scenario:**
- AI is executing a tool (e.g., running a command)
- User wants to provide guidance that should only be sent after the tool completes
- User types a steer message with multiple lines
- The steer is displayed in a separate section above queued messages
- User can press Esc to interrupt and send immediately

## 2. 功能点目的 (Feature Purpose)

The test verifies that:
1. Pending steers are rendered in their own labeled section
2. Section header explains the behavior and interrupt option
3. Multiline steers use single "↳" prefix (not per line)
4. Content is truncated to `PREVIEW_LINE_LIMIT` (3 lines)
5. Ellipsis ("…") indicates truncated content
6. Styling differs from queued messages (DIM only, no ITALIC)
7. No edit hint for steers (only for queued messages)

## 3. 具体技术实现 (Technical Implementation)

**Test Setup:**
```rust
let mut queue = PendingInputPreview::new();
queue.pending_steers.push("First line\nSecond line\nThird line\nFourth line".to_string());
let width = 48;
let height = queue.desired_height(width);  // Returns 6
```

**Rendering Output Structure:**
```
Row 0: "• Messages to be submitted after next tool call " (DIM bullet + header)
Row 1: "  (press esc to interrupt and send immediately) " (DIM continuation)
Row 2: "  ↳ First line                                  " (DIM prefix + DIM text)
Row 3: "    Second line                                 " (4-space indent + DIM text)
Row 4: "    Third line                                  " (4-space indent + DIM text)
Row 5: "    …                                           " (DIM ellipsis)
```

**Key Differences from Queued Messages:**
1. **Styling:** Steers use `.dim()` only; queued messages use `.dim().italic()`
2. **Header:** Steers have explanatory header with Esc hint
3. **No Edit Hint:** Only queued messages show the "edit last" hint
4. **Section Separator:** Empty line between steers and queued messages sections

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

**Source Files:**
- `codex-rs/tui/src/bottom_pane/pending_input_preview.rs` - Main implementation

**Snapshot Location:**
- `codex-rs/tui_app_server/src/bottom_pane/snapshots/codex_tui__bottom_pane__pending_input_preview__tests__render_multiline_pending_steer_uses_single_prefix_and_truncates.snap`

**Key Code Sections:**

**Pending Steers Rendering:**
```rust
if !self.pending_steers.is_empty() {
    Self::push_section_header(
        &mut lines,
        width,
        Line::from(vec![
            "Messages to be submitted after next tool call".into(),
            " (press ".dim(),
            key_hint::plain(KeyCode::Esc).into(),
            " to interrupt and send immediately)".dim(),
        ]),
    );

    for steer in &self.pending_steers {
        let wrapped = adaptive_wrap_lines(
            steer.lines().map(|line| Line::from(line.dim())),  // Note: no .italic()
            RtOptions::new(width as usize)
                .initial_indent(Line::from("  ↳ ".dim()))
                .subsequent_indent(Line::from("    ")),
        );
        Self::push_truncated_preview_lines(&mut lines, wrapped, Line::from("    …".dim()));
    }
}
```

**Section Separator:**
```rust
if !self.queued_messages.is_empty() {
    if !lines.is_empty() {
        lines.push(Line::from(""));  // Empty line separator
    }
    // ... queued messages rendering
}
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

**Dependencies:**
- `crossterm::event::KeyCode` - For Esc key reference in header
- `ratatui` - Terminal UI components

**Internal Dependencies:**
- `crate::key_hint::plain()` - Formats key name for display
- `crate::wrapping::adaptive_wrap_lines` - Text wrapping

**Integration Points:**
- Used by `BottomPane::set_pending_input_preview()` to display steers
- Steers are sent from the application logic when tool execution completes
- Esc key handling is done at the `ChatWidget` level, not in this widget

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvements)

**Potential Risks:**
1. **Esc Key Confusion:** Header mentions Esc to interrupt, but Esc is also used for other actions
2. **No Visual Distinction:** Steers and queued messages look similar (both use DIM)
3. **No Individual Steer Control:** Can't edit or delete individual steers

**Edge Cases:**
1. **Both Sections Empty:** Widget returns empty renderable
2. **Only Steers, No Queued Messages:** No edit hint shown (correct behavior)
3. **Only Queued Messages, No Steers:** No steer header shown
4. **Many Steers:** Like queued messages, no limit on steer count
5. **Steer with Only Newlines:** Empty content handling

**Improvement Suggestions:**

1. **Visual Distinction:**
   - Use different colors for steers vs queued messages
   - Add icons (e.g., ⏳ for steers, 💬 for queued)
   - Different indentation or prefix symbols

2. **Better Esc Indication:**
   - Make "esc" in header use key hint styling (like "⌥ + ↑")
   - Consider showing the actual keybinding configured

3. **Steer Management:**
   - Allow viewing full steer content (expand)
   - Allow deleting individual steers
   - Show steer count if multiple

4. **Test Coverage:**
   - Test with both steers AND queued messages together
   - Test empty steer content
   - Test very long single-line steer
   - Test steer that wraps naturally (no explicit newlines)

5. **Documentation:**
   - Clarify the difference between "steer" and "queued message" in user docs
   - Explain when each type is used

**Code Quality:**
- The header text is split across multiple spans for styling
- Consider extracting the header text to a constant
- The "esc" display uses `key_hint::plain(KeyCode::Esc)` which may show as "esc" or similar

**UX Consideration:**
The test name emphasizes "uses_single_prefix" - this is important because it confirms that even with multiple lines, there's only one "↳" at the start, not per line. This creates a cleaner visual hierarchy.
