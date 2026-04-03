# Research: footer_shortcuts_context_running

## 1. Feature Overview

This snapshot tests the footer's behavior when a task is running (`is_task_running: true`) and context window percentage is provided (`context_window_percent: Some(72)`). In this state, the footer shows the shortcuts hint on the left ("? for shortcuts") and the context window percentage on the right ("72% context left"). The mode cycle hint is suppressed because mode switching is not allowed during task execution. This represents the typical footer state during active AI task processing.

## 2. Code Structure

### Test Function
- **File**: `codex-rs/tui/src/bottom_pane/footer.rs`
- **Test**: `footer_snapshots()` (lines 1259-1667)
- **Specific test case**: Lines 1387-1403

```rust
snapshot_footer(
    "footer_shortcuts_context_running",
    FooterProps {
        mode: FooterMode::ComposerEmpty,
        esc_backtrack_hint: false,
        use_shift_enter_hint: false,
        is_task_running: true,  // Task is running
        collaboration_modes_enabled: false,
        is_wsl: false,
        quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),
        context_window_percent: Some(72),  // Context at 72%
        context_window_used_tokens: None,
        status_line_value: None,
        status_line_enabled: false,
        active_agent_label: None,
    },
);
```

### Key Components

1. **`context_window_line()`** (lines 848-860): Formats context window display
   - Line 849-852: Shows percentage if available
   - Line 854-857: Falls back to tokens if percentage not available
   - Line 859: Default to "100% context left"

2. **`draw_footer_frame()`** (lines 1074-1234): Test rendering helper
   - Line 1146-1150: Creates right-side context line

## 3. Behavior Analysis

### Input Parameters
- **FooterMode**: `ComposerEmpty`
- **is_task_running**: `true` (task is active)
- **context_window_percent**: `Some(72)`
- **collaboration_modes_enabled**: `false`
- **show_cycle_hint**: `false` (suppressed when running)
- **show_shortcuts_hint**: `true` (ComposerEmpty mode)
- **show_queue_hint**: `false`

### Context Window Display Logic

In `context_window_line()` (lines 848-860):
```rust
pub(crate) fn context_window_line(percent: Option<i64>, used_tokens: Option<i64>) -> Line<'static> {
    if let Some(percent) = percent {
        let percent = percent.clamp(0, 100);
        return Line::from(vec![Span::from(format!("{percent}% context left")).dim()]);
    }
    // ... token fallback ...
    // ... default ...
}
```

With `context_window_percent: Some(72)`, the output is:
- Text: "72% context left"
- Style: Dim

### Rendering Flow

1. **Right-side content creation** (`draw_footer_frame`, lines 1146-1150):
   ```rust
   Some(context_window_line(
       props.context_window_percent,      // Some(72)
       props.context_window_used_tokens,  // None
   ))
   ```
   Result: "72% context left"

2. **Left-side content**:
   - Mode: `ComposerEmpty` → show shortcuts hint
   - "? for shortcuts" rendered

3. **Layout**:
   - Both sides fit at default width (80 columns)
   - Left content aligned left with indent
   - Right content aligned right with indent

### Output
```
"  ? for shortcuts                                             72% context left  "
```

## 4. Visual Structure

```
[indent][shortcuts hint][padding][context percent][indent]
  2      17              ~42      17                2
```

### Styling
- "?": Bold (key hint)
- " for shortcuts": Dim
- "72% context left": Dim

## 5. Test Coverage

### What This Test Verifies
1. Context window percentage is displayed when provided
2. Footer shows shortcuts hint during task execution
3. Mode indicator is NOT shown (collaboration_modes_enabled: false)
4. Proper spacing between left and right content

### Business Context
This represents the UI state when:
- User has submitted a task to the AI
- Task is actively being processed
- Context window usage is at 72%
- User can see both available shortcuts and resource usage

## 6. Related Tests

- `footer_context_tokens_used`: Shows token count instead of percentage
- `footer_mode_indicator_running_hides_hint`: Shows mode indicator when collaboration enabled
- `footer_composer_has_draft_queue_hint_enabled`: Shows queue hint when draft exists during task
