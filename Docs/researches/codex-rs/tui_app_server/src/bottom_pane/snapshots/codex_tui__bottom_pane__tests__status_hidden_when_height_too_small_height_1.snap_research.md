# Bottom Pane - Status Hidden When Height Too Small (Height 1) Snapshot Research

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot captures an extreme edge case where the terminal height is limited to just **1 row**. In this scenario:
- The status indicator is hidden (due to insufficient space)
- Only the most essential UI element is shown: the composer input prompt
- The content is truncated to fit the available space

This demonstrates the bottom pane's **responsive design** and **graceful degradation** capabilities. When screen real estate is severely constrained, the UI prioritizes the most critical functionality (user input) over auxiliary information.

## 2. 功能点目的 (Feature Purpose)

The test validates:

- **Graceful degradation**: UI adapts to extreme size constraints
- **Priority rendering**: Composer takes precedence over status when space is limited
- **Content truncation**: Text is appropriately truncated with ellipsis
- **No panics**: The layout system handles edge cases without crashing
- **Minimum viable UI**: Users can still type and submit even in constrained environments

This is particularly important for:
- Users with small terminal windows
- Split-pane terminal setups
- Remote SSH sessions with limited display
- Accessibility scenarios with large font sizes

## 3. 具体技术实现 (Technical Implementation)

### Height Constraint Handling
The layout system uses `FlexRenderable` which distributes available space:

```rust
// When height = 1, only the most critical components render
let mut flex2 = FlexRenderable::new();
// Inner flex (status, queue, etc.) gets flex: 1 but may not render
flex2.push(/*flex*/ 1, RenderableItem::Owned(flex.into()));
// Composer gets flex: 0 (fixed) but is essential
flex2.push(/*flex*/ 0, RenderableItem::Borrowed(&self.composer));
```

### Truncation Logic
When content exceeds available width:
1. `take_prefix_by_width()` (from `live_wrap`) truncates text
2. Ellipsis or direct truncation applied
3. Priority given to input prompt visibility

### Component Rendering with Constraints
Each component checks available space before rendering:
```rust
if area.height == 0 || area.width == 0 {
    return;  // Skip rendering if no space
}
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Source File
- `/codex-rs/tui_app_server/src/bottom_pane/mod.rs` (lines 1-1967)

### Key Functions
| Function | Line | Purpose |
|----------|------|---------|
| `render()` | 1224-1226 | Main render with area constraints |
| `as_renderable()` | 1123-1167 | Layout composition |
| `snapshot_buffer()` | 1253-1263 | Test helper for buffer capture |

### Test Function
The test is in the test module but the specific function wasn't fully visible in the source. Based on the snapshot name, it tests height constraint handling.

### Related Components
- `FlexRenderable` - Handles space distribution
- `ChatComposer` - Minimum viable component to show
- `StatusIndicatorWidget` - Suppressed when space limited

### Truncation Utilities
- `live_wrap::take_prefix_by_width()` - Used for text truncation

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Layout Priority System
When space is constrained, components render in priority order:

| Priority | Component | Renders at Height=1? |
|----------|-----------|----------------------|
| 1 | ChatComposer (input) | Yes (truncated) |
| 2 | StatusIndicator | No |
| 3 | Queued messages | No |
| 4 | Footer hints | No |
| 5 | Context info | No |

### Space Allocation Algorithm
```
Available height: 1 row
1. Composer requires: min 1 row
2. Remaining: 0 rows
3. Status requires: 1+ rows → skipped
4. Other components: skipped
```

### User Experience Impact
- Users can still type and submit
- No visibility of task status
- No visibility of queued messages
- Context information hidden

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Potential Risks

1. **Critical Information Hidden**: Users can't see if a task is running
   - Current: Status completely hidden
   - Risk: Users may try to exit while task runs

2. **No Queue Visibility**: Queued messages not shown
   - Current: Queue hidden
   - Risk: Users forget they have pending input

3. **Input Confusion**: Truncated prompt may be unclear
   - Current: "› Ask Codex to do a" (truncated)
   - Risk: Users may not recognize input area

### Edge Cases Handled

1. **Height = 0**: No rendering at all (prevents panic)
2. **Height = 1**: Only composer (this snapshot)
3. **Width = 0**: No horizontal space
4. **Width < prompt length**: Extreme truncation

### Improvement Suggestions

1. **Minimal Status Indicator**: Show a single-character indicator when height=1
   ```
   ┌─────────────────────────────────────┐
   │ • › Ask Codex to do a...           │  ← Status dot + truncated composer
   └─────────────────────────────────────┘
   ```

2. **Compact Mode**: Special layout for height < 3
   - Single line combining status + input
   - Color coding for status (green=idle, yellow=working)

3. **Warning on Resize**: Notify users when entering extreme constraints
   - "Terminal too small - some features hidden"

4. **Priority Toggle**: Allow users to choose what's visible when constrained
   - Option: Prioritize queue over composer
   - Option: Prioritize status over input

5. **Horizontal Scrolling**: Instead of truncation, allow horizontal scroll
   - Current: Static truncation
   - Improvement: Cursor-based scroll

6. **Minimum Size Enforcement**: Set a practical minimum
   ```rust
   const MIN_RECOMMENDED_HEIGHT: u16 = 3;
   if height < MIN_RECOMMENDED_HEIGHT {
       // Show warning or enter compact mode
   }
   ```

### Testing Coverage
- Height = 1 rendering (this snapshot)
- Component suppression

Consider adding tests for:
- Height = 0 (no render)
- Height = 2 (minimal viable UI)
- Width = 1 (extreme narrow)
- Rapid resize sequences
- Recovery when size increases

### Related Scenarios
This test complements other layout tests:
- `status_and_composer_fill_height_without_bottom_padding` - Normal height
- `status_only_snapshot` - Status visible with adequate space
- `queued_messages_visible_when_status_hidden` - Queue prioritized
