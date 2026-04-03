# Research: render_one_pending_steer Snapshot

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the rendering of a single pending steer message. Pending steers represent guidance messages that will be automatically submitted after the next tool call completes, unless the user interrupts with Esc.

**Usage Scenario:**
- AI is executing a tool (running a shell command, file operation, etc.)
- User wants to provide follow-up guidance but only after the tool finishes
- User types a steer message like "Please continue" or "Check the output"
- The steer is queued and displayed in a dedicated section
- User can press Esc at any time to interrupt and send immediately

## 2. 功能点目的 (Feature Purpose)

The test verifies that:
1. Pending steers section has a descriptive header explaining the behavior
2. Header includes the Esc key hint for interrupting
3. Single steer renders with "↳" prefix and DIM styling (no ITALIC)
4. No edit hint is shown (steers are not editable like queued messages)
5. Total height is 3 rows (2 header lines + 1 steer line)
6. Width of 48 characters accommodates the full header text

## 3. 具体技术实现 (Technical Implementation)

**Test Setup:**
```rust
#[test]
fn render_one_pending_steer() {
    let mut queue = PendingInputPreview::new();
    queue.pending_steers.push("Please continue.".to_string());
    let width = 48;
    let height = queue.desired_height(width);
    let mut buf = Buffer::empty(Rect::new(0, 0, width, height));
    queue.render(Rect::new(0, 0, width, height), &mut buf);
    assert_snapshot!("render_one_pending_steer", format!("{buf:?}"));
}
```

**Rendering Output Structure:**
```
Row 0: "• Messages to be submitted after next tool call "
       [DIM bullet][header part 1]
Row 1: "  (press esc to interrupt and send immediately) "
       [DIM continuation][key hint][DIM closing]
Row 2: "  ↳ Please continue.                            "
       [DIM prefix][DIM message]
```

**Key Differences from Queued Messages:**
| Aspect | Pending Steers | Queued Messages |
|--------|---------------|-----------------|
| Header | Yes (2 lines) | Yes (1 line) |
| Styling | DIM only | DIM + ITALIC |
| Edit Hint | No | Yes |
| Purpose | Post-tool guidance | Follow-up questions |
| Interrupt | Esc to send now | Alt+Up to edit |

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

**Source Files:**
- `codex-rs/tui/src/bottom_pane/pending_input_preview.rs` - Main implementation

**Snapshot Location:**
- `codex-rs/tui_app_server/src/bottom_pane/snapshots/codex_tui__bottom_pane__pending_input_preview__tests__render_one_pending_steer.snap`

**Key Code Section:**
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
            steer.lines().map(|line| Line::from(line.dim())),
            RtOptions::new(width as usize)
                .initial_indent(Line::from("  ↳ ".dim()))
                .subsequent_indent(Line::from("    ")),
        );
        Self::push_truncated_preview_lines(&mut lines, wrapped, Line::from("    …".dim()));
    }
}
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

**Dependencies:**
- `crossterm::event::KeyCode::Esc` - For key reference
- `ratatui` - Terminal UI components
- `insta` - Snapshot testing

**Internal Dependencies:**
- `crate::key_hint::plain()` - Formats key name
- `crate::wrapping::adaptive_wrap_lines` - Text wrapping

**Integration with Application:**
- Steers are set via `BottomPane::set_pending_input_preview(queued, pending_steers)`
- Esc key handling is performed by `ChatWidget`, not this widget
- The widget is purely for display; it doesn't handle input

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvements)

**Potential Risks:**
1. **Esc Key Ambiguity:** User might press Esc expecting to cancel the steer, but it actually sends it immediately (opposite of intuition)
2. **No Edit Capability:** Unlike queued messages, steers cannot be edited once queued
3. **Header Length:** The header is very long and may wrap on narrow terminals

**Edge Cases:**
1. **Both Sections Present:** When both steers and queued messages exist, they're separated by an empty line
2. **Empty Steer:** Not tested - behavior with empty string
3. **Very Long Steer:** Would be truncated after 3 lines
4. **Narrow Terminal:** Header text would wrap significantly at width < 48

**Improvement Suggestions:**

1. **Header Optimization:**
   - Shorten header text: "Will send after next tool (Esc to send now)"
   - Or make it configurable/composable

2. **Visual Distinction:**
   - Use different color for steers (e.g., yellow vs white)
   - Add icon: ⏳ or → for steers
   - Make the distinction from queued messages clearer

3. **UX Clarification:**
   - Consider "Send now" vs "Interrupt and send" wording
   - The current wording might be confusing

4. **Test Coverage:**
   - Test with narrow width (header wrapping)
   - Test with both steers and queued messages
   - Test empty steer string
   - Test steer that exceeds 3 lines

5. **Feature Additions:**
   - Allow editing steers (like queued messages)
   - Show steer count if multiple
   - Allow deleting individual steers
   - Timestamp when steer was added

**Documentation Notes:**
- The widget docstring explains: "Pending steers explain that they will be submitted after the next tool/result boundary unless the user presses Esc to interrupt and send them immediately"
- This behavior is specific to the Codex TUI application flow
- Steers are typically generated by the application, not directly user-typed

**Code Quality:**
- The header construction uses `vec![]` with mixed styled and unstyled spans
- Consider extracting to a helper function or constant
- The width 48 was chosen to fit the full header; this is somewhat arbitrary
