# Research: footer_esc_hint_primed Snapshot Test

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer rendering when the user presses the Escape key while the "esc_backtrack_hint" flag is enabled. This scenario occurs when:

- The user has already pressed Esc once to initiate the "edit previous message" flow
- The system is now showing a primed/confirmation hint that pressing Esc again will actually trigger the edit action
- The footer displays a simplified hint "esc again to edit previous message" instead of the full "esc esc" instruction

**Responsibility**: Ensures the footer correctly displays the primed Esc hint state, providing clear user guidance for the two-step Esc interaction pattern.

## 2. 功能点目的 (Feature Purpose)

The Esc hint feature serves to:
- Prevent accidental triggering of the "edit previous message" action
- Provide progressive disclosure: first press primes the action, second press executes it
- Show different hint text based on whether the user has already pressed Esc once (`esc_backtrack_hint: true`)
- Maintain consistent footer styling (dimmed text) for transient hints

**Test Purpose**: Verify that when `esc_backtrack_hint` is `true` and mode is `FooterMode::EscHint`, the footer renders the simplified "esc again" message instead of the "esc esc" variant.

## 3. 具体技术实现 (Technical Implementation)

### Test Configuration
```rust
FooterProps {
    mode: FooterMode::EscHint,
    esc_backtrack_hint: true,  // Key difference from footer_esc_hint_idle
    use_shift_enter_hint: false,
    is_task_running: false,
    collaboration_modes_enabled: false,
    is_wsl: false,
    quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),
    context_window_percent: None,
    context_window_used_tokens: None,
    status_line_value: None,
    status_line_enabled: false,
    active_agent_label: None,
}
```

### Rendering Flow
1. `footer_from_props_lines()` matches on `FooterMode::EscHint`
2. Calls `esc_hint_line(props.esc_backtrack_hint)` with `true`
3. Since `esc_backtrack_hint` is `true`, returns:
   ```rust
   Line::from(vec![esc.into(), " again to edit previous message".into()]).dim()
   ```
4. The line is rendered with dim styling via `.dim()`

### Key Code Path
```rust
// footer.rs:735-748
fn esc_hint_line(esc_backtrack_hint: bool) -> Line<'static> {
    let esc = key_hint::plain(KeyCode::Esc);
    if esc_backtrack_hint {
        Line::from(vec![esc.into(), " again to edit previous message".into()]).dim()
    } else {
        // "esc esc" variant...
    }
}
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files
- `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
  - Lines 735-748: `esc_hint_line()` function
  - Lines 616: `FooterMode::EscHint` handling in `footer_from_props_lines()`
  - Lines 1369-1385: Test definition

### Related Types
- `FooterMode::EscHint` - Enum variant for Esc hint state
- `FooterProps.esc_backtrack_hint` - Boolean flag tracking primed state

### Snapshot Output
```
"  esc again to edit previous message                                            "
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Dependencies
- `key_hint::plain(KeyCode::Esc)` - Generates the styled "esc" key representation
- `ratatui::text::Line` - Text container for footer content
- `.dim()` styling - Applied to transient hints for visual hierarchy

### Related Components
- `ChatComposer` - Determines when to show `FooterMode::EscHint`
- State machine tracking `esc_backtrack_hint` - Set on first Esc press, cleared on second press or other activity

### Interaction Flow
1. User presses Esc → `ChatComposer` sets mode to `EscHint`, sets `esc_backtrack_hint: false`
2. Footer shows "esc esc to edit previous message"
3. User presses Esc again (within timeout) → `esc_backtrack_hint` set to `true`
4. Footer updates to "esc again to edit previous message" (this snapshot)
5. User presses Esc third time → Previous message editing triggered

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks
1. **Timeout Handling**: If the hint times out between presses, the user may be confused about the expected behavior
2. **Visual Consistency**: The dim styling might be too subtle in some terminal color schemes
3. **Accessibility**: Users with motor impairments may find the double-press pattern challenging

### Edge Cases
- **Rapid Esc presses**: Multiple quick presses should still behave predictably
- **Interleaved input**: If user types between Esc presses, the hint should disappear
- **Terminal width**: Very narrow terminals may truncate the hint (80 char width tested)

### Improvement Suggestions
1. **Configurable timeout**: Allow users to customize the Esc hint timeout duration
2. **Visual indicator**: Consider adding a subtle timer/progress indicator for the hint timeout
3. **Alternative trigger**: Provide a single-key alternative (e.g., Ctrl+E) for accessibility
4. **Documentation**: Ensure the two-step Esc pattern is documented in help text

### Test Coverage
- Complementary test `footer_esc_hint_idle` covers the `esc_backtrack_hint: false` case
- Both tests use 80-character terminal width
- Tests verify the exact string content and styling
