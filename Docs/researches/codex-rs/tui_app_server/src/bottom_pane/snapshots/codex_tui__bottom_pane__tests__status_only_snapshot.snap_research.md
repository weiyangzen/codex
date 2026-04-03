# Bottom Pane - Status Only Snapshot Research

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot captures the bottom pane when a task is running but there are **no queued messages**, **no pending approvals**, and **no other auxiliary content**. This represents the "clean" active state where:

- The AI is processing a request (status indicator visible)
- The user has not queued any follow-up messages
- The composer is ready for new input
- The layout is at its most minimal active state

This scenario is common during:
- Initial task execution
- Single-turn interactions
- Long-running tasks where the user is waiting

## 2. 功能点目的 (Feature Purpose)

The test validates the clean layout showing:

- **Status indicator prominence**: Clear visibility of "Working" state
- **Interrupt accessibility**: Esc shortcut clearly displayed
- **Elapsed time tracking**: Shows "0s" indicating task duration
- **Composer availability**: Input area ready for immediate use
- **Context awareness**: Token usage still displayed
- **Minimal spacing**: No extra gaps when no queued content

This ensures users have a clean, uncluttered view during simple active tasks.

## 3. 具体技术实现 (Technical Implementation)

### Layout Without Queued Content
When `pending_input_preview` is empty and `pending_thread_approvals` is empty:

```rust
// Simplified layout logic
let mut flex = FlexRenderable::new();

// 1. Status indicator
if let Some(status) = &self.status {
    flex.push(/*flex*/ 0, RenderableItem::Borrowed(status));
}

// 2. No pending thread approvals (empty)
// 3. No pending input preview (empty)

// 4. Spacer before composer (since status is visible)
if !has_inline_previews && has_status_or_footer {
    flex.push(/*flex*/ 0, RenderableItem::Owned("".into()));
}

// 5. Composer
let mut flex2 = FlexRenderable::new();
flex2.push(/*flex*/ 1, RenderableItem::Owned(flex.into()));
flex2.push(/*flex*/ 0, RenderableItem::Borrowed(&self.composer));
```

### StatusIndicatorWidget Components
```rust
pub(crate) struct StatusIndicatorWidget {
    header: String,              // "Working"
    elapsed_seconds: u64,        // 0s
    interrupt_hint_visible: bool, // true when running
    inline_message: Option<String>, // For unified exec summary
    // ... animation fields
}
```

### Visual Structure
```
┌─────────────────────────────────────────────┐
│ • Working (0s • esc to interrupt)           │ ← Status (1 line)
│                                             │ ← Spacer
│                                             │ ← Spacer (details area)
│ › Ask Codex to do anything                  │ ← Composer input
│                                             │ ← Composer spacer
│   ? for shortcuts      100% context left    │ ← Footer
└─────────────────────────────────────────────┘
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Source File
- `/codex-rs/tui_app_server/src/bottom_pane/mod.rs` (lines 1-1967)

### Key Functions
| Function | Line | Purpose |
|----------|------|---------|
| `set_task_running()` | 716-740 | Activates status indicator |
| `as_renderable()` | 1123-1167 | Builds layout based on state |
| `StatusIndicatorWidget::render()` | (external) | Renders status line |

### Test Function
- `status_only_snapshot()` at lines 1471-1491

### Test Setup
```rust
let mut pane = BottomPane::new(BottomPaneParams { /* ... */ });
pane.set_task_running(true);  // Creates and shows status
// No set_pending_input_preview() called - queue is empty
// No set_pending_thread_approvals() called - no approvals

let width = 48;
let height = pane.desired_height(width);
let area = Rect::new(0, 0, width, height);
assert_snapshot!("status_only_snapshot", render_snapshot(&pane, area));
```

### Related Components
- `StatusIndicatorWidget` at line 176
- `ChatComposer` at line 161

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### State Dependencies
| State | Value | Effect on Layout |
|-------|-------|------------------|
| `is_task_running` | `true` | Status visible |
| `status` | `Some(...)` | Status widget rendered |
| `queued_messages` | `[]` | No queue section |
| `pending_steers` | `[]` | No steer section |
| `pending_threads` | `[]` | No approvals section |

### Animation System
The status indicator includes:
- **Spinner animation**: Rotating character (•, ○, etc.)
- **Elapsed time**: Updates every second
- **Interrupt hint**: "esc to interrupt" when running

Animation is controlled by:
```rust
pub(crate) const ANIMATION_INTERVAL: Duration = Duration::from_millis(100);
```

### Event Communication
When user presses Esc during this state:
```rust
// handle_key_event routes to status.interrupt()
status.interrupt();
// Emits AppEvent::CodexOp(Op::Interrupt)
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Potential Risks

1. **Silent Activity**: Users may not notice the status indicator
   - Current: Spinner animation helps draw attention
   - Risk: Static view might be missed

2. **No Progress Indication**: "Working" doesn't show what or how much
   - Current: Generic message
   - Risk: Users uncertain if progress is being made

3. **Interrupt Accidents**: Easy to accidentally interrupt
   - Current: Single Esc press interrupts
   - Risk: Accidental keypress loses work

### Edge Cases Handled

1. **Status with details**: Can show additional detail lines
2. **Status with inline message**: Unified exec summary appears inline
3. **Status timer pause**: Paused during modal overlays
4. **Status resume**: Continues after modal dismissed

### Improvement Suggestions

1. **Progress Indication**: Show operation type or progress percentage
   ```
   • Working: Generating code... (45%)
   ```

2. **Interrupt Confirmation**: Require double-press or confirmation
   ```
   • Working (0s • esc again to interrupt)
   ```

3. **Idle Timeout**: Show warning if task appears stuck
   ```
   • Working (30s • may be stuck)
   ```

4. **Compact Mode Option**: Allow hiding status for minimal UI
   - Keyboard toggle to show/hide
   - Remember preference

5. **Sound/Notification**: Optional audio cue when task completes
   - Current: Visual only
   - Improvement: Configurable notification

6. **Status History**: Briefly show completion status
   ```
   • Done (took 5s)                    [fades after 2s]
   ```

### Testing Coverage
- Status only rendering (this snapshot)
- Status with queued messages
- Status hidden scenarios

Consider adding tests for:
- Status with long running time (displays minutes/hours)
- Status with details
- Status with inline unified exec message
- Animation frame progression

### Related Snapshots
- `status_and_queued_messages_snapshot` - With queue visible
- `status_with_details_and_queued_messages_snapshot` - With details expanded
- `queued_messages_visible_when_status_hidden_snapshot` - Status hidden
