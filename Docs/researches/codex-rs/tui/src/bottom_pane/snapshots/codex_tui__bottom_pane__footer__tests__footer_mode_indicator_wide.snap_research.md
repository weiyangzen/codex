# Research: footer_mode_indicator_wide

## 1. Feature Overview

This snapshot tests the footer's behavior at a wide terminal width (120 columns) with collaboration modes enabled and no task running. At this width, all footer elements can be displayed: the shortcuts hint ("? for shortcuts"), the collaboration mode indicator with cycle hint ("Plan mode (shift+tab to cycle)"), and the right-side context window indicator ("100% context left"). This represents the "full" footer state with all informational elements visible.

## 2. Code Structure

### Test Function
- **File**: `codex-rs/tui/src/bottom_pane/footer.rs`
- **Test**: `footer_snapshots()` (lines 1259-1667)
- **Specific test case**: Lines 1441-1461

```rust
let props = FooterProps {
    mode: FooterMode::ComposerEmpty,
    esc_backtrack_hint: false,
    use_shift_enter_hint: false,
    is_task_running: false,  // No task running
    collaboration_modes_enabled: true,
    is_wsl: false,
    quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),
    context_window_percent: None,
    context_window_used_tokens: None,
    status_line_value: None,
    status_line_enabled: false,
    active_agent_label: None,
};

snapshot_footer_with_mode_indicator(
    "footer_mode_indicator_wide",
    120,  // Wide width - everything fits!
    &props,
    Some(CollaborationModeIndicator::Plan),
);
```

### Key Components

1. **`left_side_line()`** (lines 271-300): Constructs left footer content
   - Adds shortcuts hint (lines 278-281)
   - Adds separator " · " (line 294)
   - Adds mode indicator with cycle hint (line 296)

2. **`single_line_footer_layout()`** (lines 310-472): Layout decisions
   - Line 331: Checks if default content fits with context

3. **`render_context_right()`** (lines 529-554): Renders right-aligned context

## 3. Behavior Analysis

### Input Parameters
- **Terminal width**: 120 columns (wide)
- **FooterMode**: `ComposerEmpty`
- **is_task_running**: `false` (idle state)
- **collaboration_mode_indicator**: `Some(CollaborationModeIndicator::Plan)`
- **show_cycle_hint**: `true` (because `!is_task_running`)
- **show_shortcuts_hint**: `true` (because mode is `ComposerEmpty`)
- **show_queue_hint**: `false`

### Rendering Flow

1. **Layout calculation** (`single_line_footer_layout`):
   - Default state: shortcuts hint + mode with cycle hint
   - Width calculation:
     - "? for shortcuts": ~17 chars
     - " · ": 3 chars
     - "Plan mode (shift+tab to cycle)": ~32 chars
     - Total left: ~52 chars
     - Context: ~18 chars ("100% context left")
     - Total with gap: ~71 chars
   - At 120 columns, this fits easily
   - Returns `(SummaryLeft::Default, true)` - show context

2. **Final rendering**:
   - Left side: "? for shortcuts · Plan mode (shift+tab to cycle)"
   - Right side: "100% context left"

### Output
```
"  ? for shortcuts · Plan mode (shift+tab to cycle)                                                   100% context left  "
```

## 4. Visual Structure

```
[indent][shortcuts][separator][mode with cycle hint][padding][context][padding]
  2      17          3          32                    ~67       18        2
```

Total: ~120 columns

### Styling
- "?": Bold (key hint styling via `key_hint::plain()`)
- " for shortcuts": Dim
- " · ": Dim separator
- "Plan mode (shift+tab to cycle)": Magenta (Plan mode color)
- "100% context left": Dim

## 5. Test Coverage

### What This Test Verifies
1. Full footer content displays at wide terminal widths
2. All three elements coexist: shortcuts hint, mode indicator, context
3. Mode cycle hint is shown when not running a task
4. Proper spacing and alignment between elements

### Comparison with Narrow Width
| Width | Shortcuts Hint | Mode Cycle Hint | Context |
|-------|---------------|-----------------|---------|
| 120   | Yes           | Yes             | Yes     |
| 50    | No            | Yes             | No      |

## 6. Related Tests

- `footer_mode_indicator_narrow_overlap_hides`: Same setup at 50 columns
- `footer_mode_indicator_running_hides_hint`: Same width but `is_task_running: true`
- `footer_shortcuts_default`: No collaboration mode indicator
