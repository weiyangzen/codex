# Research: footer_shortcuts_context_running Snapshot Test

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer rendering when a task is running and context usage is at 72%. This scenario occurs when:

- The user has initiated a task that is currently executing (`is_task_running: true`)
- The context window usage is at 72% (`context_window_percent: Some(72)`)
- The composer is in empty state (`FooterMode::ComposerEmpty`)

**Responsibility**: Ensures the footer displays the appropriate hints and context information during task execution, helping users understand both available actions and resource usage.

## 2. 功能点目的 (Feature Purpose)

The running task footer with context serves to:
- Show the shortcuts hint for general discoverability
- Display current context usage percentage (72% in this case)
- Maintain visibility of available actions even during task execution
- Provide resource awareness to help users manage context limits

**Test Purpose**: Verify that when a task is running with 72% context usage, the footer correctly displays the shortcuts hint and the context percentage on the right side.

## 3. 具体技术实现 (Technical Implementation)

### Test Configuration
```rust
FooterProps {
    mode: FooterMode::ComposerEmpty,
    esc_backtrack_hint: false,
    use_shift_enter_hint: false,
    is_task_running: true,  // Task is running
    collaboration_modes_enabled: false,
    is_wsl: false,
    quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),
    context_window_percent: Some(72),  // 72% context remaining
    context_window_used_tokens: None,
    status_line_value: None,
    status_line_enabled: false,
    active_agent_label: None,
}
```

### Rendering Flow
1. `draw_footer_frame()` evaluates `show_shortcuts_hint` based on mode
2. For `ComposerEmpty`, `show_shortcuts_hint` is `true`
3. `context_window_line()` is called with `percent: Some(72)`
4. The percentage is clamped to 0-100 range
5. Right-side line is generated: "72% context left"
6. `single_line_footer_layout()` determines both sides fit at 80 chars
7. Both left (shortcuts) and right (context) are rendered

### Key Code Path
```rust
// footer.rs:848-860
pub(crate) fn context_window_line(percent: Option<i64>, used_tokens: Option<i64>) -> Line<'static> {
    if let Some(percent) = percent {
        let percent = percent.clamp(0, 100);  // Clamp to valid range
        return Line::from(vec![Span::from(format!("{percent}% context left")).dim()]);
    }
    // ... fallback to used_tokens or default
}
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files
- `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - Lines 848-860: `context_window_line()` function
  - Lines 1146-1150: Right-side context generation in tests
  - Lines 1387-1403: Test definition

### Related Functions
- `single_line_footer_layout()` - Determines layout based on widths
- `can_show_left_with_context()` - Checks if both sides fit
- `render_context_right()` - Renders right-aligned context

### Snapshot Output
```
"  ? for shortcuts                                             72% context left  "
```

### Layout Analysis
```
[2 spaces][? for shortcuts][45 spaces][72% context left][2 spaces]
Total: 80 characters
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Dependencies
- `context_window_percent` from `FooterProps`
- `format!("{percent}% context left")` - String formatting
- `.dim()` styling for context information
- `clamp(0, 100)` for bounds checking

### Context Information Sources
The context line can display:
1. **Percentage remaining**: "72% context left" (this test)
2. **Tokens used**: "123k used" (when `context_window_used_tokens` is set)
3. **Default**: "100% context left" (when neither is set)

### Related Components
- Token usage tracker - Calculates percentage/used tokens
- `ChatWidget` - Provides running state
- Context window manager - Monitors and reports usage

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks
1. **Accuracy**: Reported percentage may not reflect actual token usage
2. **Performance**: Frequent updates to context percentage could cause flickering
3. **Misinterpretation**: Users may confuse "context left" with "time remaining"

### Edge Cases
- **0% context**: Should show warning or different styling
- **Over 100%**: Clamped to 100%, but may indicate a problem
- **Very high usage (>90%)**: Should use warning color (red/yellow)
- **Token count vs percentage**: Inconsistent display modes

### Context Display Matrix
| Input | Display |
|-------|---------|
| `percent: Some(72)` | "72% context left" |
| `percent: Some(0)` | "0% context left" |
| `percent: Some(150)` | "100% context left" (clamped) |
| `used_tokens: Some(123456)` | "123k used" |
| Both None | "100% context left" |

### Improvement Suggestions
1. **Color Coding**: Use yellow for < 30%, red for < 10% context remaining
2. **Tooltip**: Show exact token counts on hover
3. **Trend Indicator**: Show ↑/↓ arrow if context usage is changing
4. **Context Bar**: Visual progress bar instead of text
5. **Alert Threshold**: Warn user when approaching context limit
6. **Compression Hint**: Suggest summarizing when context is low

### Test Coverage
- `footer_shortcuts_default` - Default 100% context
- `footer_context_tokens_used` - Token-based display (123k used)
- This test - Percentage-based display (72%)
- Together they cover all context display modes
