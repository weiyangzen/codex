# Research: footer_context_tokens_used Snapshot Test

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer rendering when displaying **context token usage** in absolute numbers (as opposed to percentage). This scenario occurs when:
- The system tracks actual token consumption rather than just percentage remaining
- Users want precise understanding of their context window usage
- The `context_window_used_tokens` field is populated in `FooterProps`

This is an alternative display mode to the more common percentage-based context display.

## 2. 功能点目的 (Purpose of the Feature)

The token-based context display serves these purposes:
- **Precision**: Shows exact token count rather than rounded percentage
- **Power User Feature**: Developers may prefer raw numbers for debugging
- **Cost Awareness**: Helps users understand token consumption patterns
- **Debugging**: Useful for diagnosing context window issues

Key behaviors:
- When `context_window_used_tokens` is `Some(tokens)`, displays "{formatted} used"
- When `context_window_percent` is `Some(percent)`, displays "{percent}% context left"
- When neither is set, defaults to "100% context left"
- Token count is formatted compactly (e.g., "123K" for 123,456)

## 3. 具体技术实现 (Technical Implementation Details)

### FooterProps Configuration
```rust
let props = FooterProps {
    mode: FooterMode::ComposerEmpty,
    esc_backtrack_hint: false,
    use_shift_enter_hint: false,
    is_task_running: false,
    collaboration_modes_enabled: false,
    is_wsl: false,
    quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),
    context_window_percent: None,  // Not using percentage
    context_window_used_tokens: Some(123_456),  // Using token count
    status_line_value: None,
    status_line_enabled: false,
    active_agent_label: None,
};
```

### Context Window Line Generation
The `context_window_line()` function handles both display modes:
```rust
pub(crate) fn context_window_line(percent: Option<i64>, used_tokens: Option<i64>) -> Line<'static> {
    // Priority: percentage if available
    if let Some(percent) = percent {
        let percent = percent.clamp(0, 100);
        return Line::from(vec![Span::from(format!("{percent}% context left")).dim()]);
    }

    // Fallback to token count
    if let Some(tokens) = used_tokens {
        let used_fmt = format_tokens_compact(tokens);
        return Line::from(vec![Span::from(format!("{used_fmt} used")).dim()]);
    }

    // Default when no data available
    Line::from(vec![Span::from("100% context left").dim()])
}
```

### Token Formatting
The `format_tokens_compact()` function (from `crate::status`) formats large numbers:
- 123_456 → "123K"
- 1_234_567 → "1.2M" (depending on implementation)
- Uses SI suffixes for readability

### Rendering
The context line is rendered on the right side of the footer:
```rust
let right_line = Some(context_window_line(
    props.context_window_percent,
    props.context_window_used_tokens,
));
render_context_right(area, f.buffer_mut(), line);
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Source File
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/footer.rs`

### Key Functions
- `footer_snapshots()` test (line 1260-1667) - Test case around line 1405-1421
- `context_window_line()` (line 848-860) - Generates context display line
- `draw_footer_frame()` (line 1074-1234) - Renders footer with context
- `render_context_right()` (line 529-554) - Right-aligns context info

### Snapshot File Location
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/snapshots/codex_tui__bottom_pane__footer__tests__footer_context_tokens_used.snap`

### Related Module
- `crate::status::format_tokens_compact` - Token number formatting utility

### Display Priority
```rust
// Priority order in context_window_line:
1. context_window_percent (Some) → "{percent}% context left"
2. context_window_used_tokens (Some) → "{formatted} used"
3. Both None → "100% context left"
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Internal Dependencies
- `ratatui`: Terminal UI framework (`Line`, `Span`)
- `crate::status`: Token formatting utilities

### Data Sources
Context token data typically comes from:
- OpenAI API responses (usage information)
- Local token counting heuristics
- Session state tracking

### Layout Integration
The context display appears on the right side of the footer:
- Right-aligned with `FOOTER_INDENT_COLS` padding
- Separated from left content by `FOOTER_CONTEXT_GAP_COLS`
- May be hidden if left content is too wide

### Related Snapshots
- `footer_shortcuts_context_running` - Shows percentage-based context ("72% context left")

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks
1. **User Confusion**: "123K used" doesn't indicate total capacity (unlike percentage)
2. **Inconsistent Display**: Switching between percentage and tokens may confuse users
3. **Overflow**: Very large token counts may not fit in compact format
4. **Accuracy**: Local token counting may differ from API's actual usage

### Edge Cases
1. **Zero Tokens**: `Some(0)` would show "0 used" (unclear if good or bad)
2. **Negative Values**: No explicit handling (would format as negative)
3. **Very Large Values**: Millions of tokens - formatting may break
4. **Both Values Set**: Percentage takes priority, tokens ignored
5. **Token Limit Changes**: If model changes, "used" number may be misleading

### Improvement Suggestions
1. **Dual Display**: Show both "123K / 128K used" for clarity
2. **Visual Indicator**: Progress bar or color coding for usage level
3. **Warning Thresholds**: Yellow/red color when approaching limits
4. **User Preference**: Allow users to choose percentage vs tokens
5. **Tooltip**: Show exact number on hover (if terminal supports it)
6. **Consistent Default**: Standardize on one display mode across the app
7. **Test Coverage**:
   - Test with 0 tokens
   - Test with very large token counts
   - Test when both percent and tokens are set
   - Test formatting edge cases (999, 1000, 999999, etc.)
