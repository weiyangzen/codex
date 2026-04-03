# Research: footer_mode_indicator_wide Snapshot Test

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer rendering in an ideal, wide terminal scenario (120 characters). This represents the optimal user experience where all footer elements can be displayed without compromise. This scenario occurs when:

- The terminal is sufficiently wide (120 characters)
- The collaboration mode indicator is active (Plan mode)
- The shortcuts hint is enabled
- Context information is available

**Responsibility**: Ensures the footer displays the complete, uncompressed layout when space permits, providing users with maximum information density.

## 2. 功能点目的 (Feature Purpose)

The wide footer layout serves to:
- Display all relevant information simultaneously
- Show the full collaboration mode indicator with cycle hint
- Include the shortcuts hint for discoverability
- Display context usage percentage on the right side
- Demonstrate the intended design without width constraints

**Test Purpose**: Verify that at 120-character width, the footer shows the complete layout: shortcuts hint, mode indicator with cycle hint, and context percentage.

## 3. 具体技术实现 (Technical Implementation)

### Test Configuration
```rust
let props = FooterProps {
    mode: FooterMode::ComposerEmpty,
    esc_backtrack_hint: false,
    use_shift_enter_hint: false,
    is_task_running: false,  // Idle state
    collaboration_modes_enabled: true,  // Enables mode cycling
    is_wsl: false,
    quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),
    context_window_percent: None,  // Uses default 100%
    context_window_used_tokens: None,
    status_line_value: None,
    status_line_enabled: false,
    active_agent_label: None,
};

snapshot_footer_with_mode_indicator(
    "footer_mode_indicator_wide",
    120,  // Wide terminal
    &props,
    Some(CollaborationModeIndicator::Plan),
);
```

### Rendering Flow
1. `single_line_footer_layout()` called with 120-character width
2. Calculates widths for all components:
   - Shortcuts hint: ~17 chars ("? for shortcuts")
   - Separator: 3 chars (" · ")
   - Mode indicator: ~38 chars ("Plan mode (shift+tab to cycle)")
   - Gap: 1 char
   - Context: ~18 chars ("100% context left")
3. Total: ~77 chars < 120 available → Everything fits
4. Returns `SummaryLeft::Default` with `show_context: true`

### Key Code Path
```rust
// footer.rs:308-333
pub(crate) fn single_line_footer_layout(
    area: Rect,
    context_width: u16,
    collaboration_mode_indicator: Option<CollaborationModeIndicator>,
    show_cycle_hint: bool,  // true when !is_task_running
    show_shortcuts_hint: bool,  // true for ComposerEmpty
    show_queue_hint: bool,
) -> (SummaryLeft, bool) {
    // First check if default layout fits
    if default_width > 0 && can_show_left_with_context(area, default_width, context_width) {
        return (SummaryLeft::Default, true);  // This path taken
    }
    // ... fallback logic
}
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files
- `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - Lines 308-333: Primary layout logic (fast path)
  - Lines 101-125: `CollaborationModeIndicator` implementation
  - Lines 1456-1461: Test definition

### Related Functions
- `CollaborationModeIndicator::label()` - Generates mode text with optional cycle hint
- `CollaborationModeIndicator::styled_span()` - Applies magenta color to Plan mode
- `left_side_line()` - Assembles left-side components
- `context_window_line()` - Generates right-side context (defaults to "100% context left")

### Snapshot Output
```
"  ? for shortcuts · Plan mode (shift+tab to cycle)                                                   100% context left  "
```

### Layout Breakdown
```
[2 spaces indent][? for shortcuts][ · ][Plan mode (shift+tab to cycle)][52 spaces gap][100% context left][2 spaces]
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Dependencies
- `ratatui::style::Stylize` - For `.magenta()`, `.dim()` styling
- `key_hint::plain(KeyCode::Char('?'))` - Styled key representation
- `FOOTER_INDENT_COLS` (2) - Left padding
- `FOOTER_CONTEXT_GAP_COLS` (1) - Minimum gap

### Styling Applied
| Element | Style | Color |
|---------|-------|-------|
| "?" | Bold | Default |
| " for shortcuts" | Dim | Default |
| " · " | Dim | Default |
| "Plan mode (shift+tab to cycle)" | Normal | Magenta |
| "100% context left" | Dim | Default |

### Related Components
- `ChatComposer` - Sets `FooterMode::ComposerEmpty`
- Mode cycle logic - Provides `show_cycle_hint: true` when idle
- Context tracking - Provides percentage/used tokens

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks
1. **Over-reliance on Width**: Design assumes 120 chars is common; many users use smaller terminals
2. **Information Density**: Too much information may overwhelm new users
3. **Color Accessibility**: Magenta may not be visible in all terminal themes

### Edge Cases
- **Extremely wide terminals (> 200 chars)**: Excessive gap between left and right
- **Narrow but not too narrow (80-100 chars)**: May trigger different layout paths
- **Resizing during use**: Layout changes may disorient users

### Width Comparison
| Test | Width | Shows Cycle Hint | Shows Context | Result |
|------|-------|------------------|---------------|--------|
| footer_mode_indicator_wide | 120 | Yes | Yes | Full layout |
| footer_mode_indicator_narrow_overlap_hides | 50 | No | No | Mode only |

### Improvement Suggestions
1. **Dynamic Gap**: Adjust gap size based on terminal width rather than fixed spacing
2. **Progressive Disclosure**: Show simplified layout by default, expand on hover/keypress
3. **User Preference**: Allow users to customize which elements appear
4. **Responsive Breakpoints**: Add more granular width thresholds (90, 100, 110 chars)
5. **Alignment Options**: Allow right-align vs center-align for context

### Test Coverage
- This test establishes the "ideal" layout baseline
- `footer_mode_indicator_narrow_overlap_hides` shows degradation at 50 chars
- Together they verify the responsive design works across the width spectrum
