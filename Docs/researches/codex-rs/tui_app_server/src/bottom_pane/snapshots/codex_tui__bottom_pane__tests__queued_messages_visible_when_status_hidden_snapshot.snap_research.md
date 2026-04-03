# Bottom Pane - Queued Messages Visible When Status Hidden Snapshot Research

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot captures a specific UI state where:
- A task was running (status indicator was visible)
- The status indicator has been explicitly hidden via `hide_status_indicator()`
- Queued messages are still visible above the composer

This scenario demonstrates the bottom pane's ability to maintain visibility of pending user input (queued messages) even when the status indicator is not displayed. This is important for user experience - users should always see their pending input regardless of task status visibility.

## 2. 功能点目的 (Feature Purpose)

The test validates that:

- **Queued messages remain visible** when the status indicator is hidden
- **Layout adapts correctly** without the status row taking up space
- **Composer remains functional** at the bottom of the pane
- **Context information** ("100% context left") is still displayed
- **No empty gaps** appear where the status indicator was

This ensures users don't lose sight of their queued follow-up questions when the status indicator is dismissed.

## 3. 具体技术实现 (Technical Implementation)

### Layout Composition (from `as_renderable()`)
The bottom pane uses a `FlexRenderable` stack with conditional elements:

```rust
// Simplified layout logic
let mut flex = FlexRenderable::new();

// Status indicator (optional, can be hidden)
if let Some(status) = &self.status {
    flex.push(/*flex*/ 0, RenderableItem::Borrowed(status));
}

// Unified exec footer (only if no status)
if self.status.is_none() && !self.unified_exec_footer.is_empty() {
    flex.push(/*flex*/ 0, RenderableItem::Borrowed(&self.unified_exec_footer));
}

// Pending thread approvals
flex.push(/*flex*/ 1, RenderableItem::Borrowed(&self.pending_thread_approvals));

// Pending input preview (queued messages)
flex.push(/*flex*/ 1, RenderableItem::Borrowed(&self.pending_input_preview));

// Spacer logic for visual separation
if has_inline_previews && has_status_or_footer {
    flex.push(/*flex*/ 0, RenderableItem::Owned("".into()));
}

// Composer at bottom
flex2.push(/*flex*/ 0, RenderableItem::Borrowed(&self.composer));
```

### Key Components
1. **PendingInputPreview**: Displays queued messages and pending steers
2. **StatusIndicatorWidget**: Can be shown/hidden independently
3. **FlexRenderable**: Flexible layout system with flex weights

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Source File
- `/codex-rs/tui_app_server/src/bottom_pane/mod.rs` (lines 1-1967)

### Key Functions
| Function | Line | Purpose |
|----------|------|---------|
| `hide_status_indicator()` | 743-747 | Hides status while keeping other UI |
| `as_renderable()` | 1123-1167 | Constructs the layout stack |
| `set_pending_input_preview()` | 815-823 | Updates queued messages |

### Test Function
- `queued_messages_visible_when_status_hidden_snapshot()` at lines 1556-1581

### Test Setup
```rust
pane.set_task_running(true);  // Creates status indicator
pane.set_pending_input_preview(
    vec!["Queued follow-up question".to_string()], 
    Vec::new()
);
pane.hide_status_indicator();  // Hide status but keep queued messages
```

### Related Components
- `PendingInputPreview` at lines 183, 820-821
- `StatusIndicatorWidget` at line 176

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### State Management
| Component | State | Visibility Logic |
|-----------|-------|------------------|
| Status indicator | `Option<StatusIndicatorWidget>` | Hidden when `None` |
| Queued messages | `Vec<String>` in `PendingInputPreview` | Always visible if non-empty |
| Composer | Always present | Bottom of stack |

### Layout Dependencies
- `FlexRenderable`: Manages vertical stacking with flex weights
- Flex weight `0`: Fixed size elements
- Flex weight `1`: Expandable elements

### Visual Hierarchy
```
┌─────────────────────────────────────────────┐
│ • Queued follow-up messages                 │ ← PendingInputPreview
│   ↳ Queued follow-up question               │
│     ⌥ + ↑ edit last queued message          │
│                                             │ ← Spacer (conditional)
│ › Ask Codex to do anything                  │ ← ChatComposer
│                                             │
│   ? for shortcuts      100% context left    │ ← Footer
└─────────────────────────────────────────────┘
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Potential Risks

1. **Layout Jump**: When status is hidden, the queued messages may "jump" up
   - Current: Spacer logic tries to maintain visual rhythm
   - Risk: Could be disorienting to users

2. **Empty Space**: Without status, there might be awkward empty space
   - Current: Unified exec footer can fill this space
   - Risk: Visual inconsistency

3. **Focus Management**: Hiding status doesn't affect input focus
   - Current: Focus remains on composer
   - Risk: Users may think the task stopped

### Edge Cases Handled

1. **No queued messages**: Only composer and footer visible
2. **No status + no queued messages**: Minimal bottom pane
3. **Status hidden mid-task**: Task continues, just UI hidden
4. **Multiple hide calls**: Idempotent (no-op if already hidden)

### Improvement Suggestions

1. **Visual Indicator**: Show a subtle indicator that a task is still running even when status is hidden
   - Could be a small dot or color change in the composer

2. **Animation**: Smooth transition when status appears/disappears
   - Current: Immediate show/hide
   - Improvement: Fade or slide animation

3. **Auto-show on completion**: When task completes, briefly show status
   - Current: Status stays hidden
   - Improvement: Flash completion status

4. **Persistent Queue Hint**: Always show queue count in footer
   - Current: Queue only visible in preview area
   - Improvement: "3 messages queued" in status bar

5. **Keyboard Shortcut**: Dedicated shortcut to toggle status visibility
   - Current: Programmatic control only
   - Improvement: User-controlled visibility

### Testing Coverage
- Queued messages visible without status (this snapshot)
- Status with queued messages
- Status hidden with queued messages

Consider adding tests for:
- Rapid show/hide transitions
- Status hidden with unified exec footer visible
- Status hidden with pending thread approvals
