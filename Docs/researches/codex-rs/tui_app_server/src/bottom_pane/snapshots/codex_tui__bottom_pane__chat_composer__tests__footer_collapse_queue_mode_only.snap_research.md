# Research: Footer Collapse - Queue Mode Only

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer rendering behavior when:
- The composer has **draft content** ("Test" in the textarea)
- A **task is running** (queue mode active)
- The terminal width is **very narrow (20 columns)**
- **No collaboration mode** is active
- **Only the queue hint** can be displayed (no context, no mode indicator)

This tests the most minimal viable footer display in queue mode, ensuring that even in extremely constrained terminal widths, users still receive the essential "tab to queue" guidance.

## 2. 功能点目的 (Feature Purpose)

The "queue mode only" variant serves to:
1. **Absolute Minimum Display**: Show only the most critical information when space is severely limited
2. **Core Action Preservation**: Ensure users always know they can queue messages via Tab
3. **Graceful Degradation**: Demonstrate the final fallback in the collapse hierarchy
4. **Terminal Compatibility**: Support legacy terminals, split-screen setups, or embedded displays

This represents the last resort in footer collapse - if the terminal is any narrower, even this minimal hint may not fit.

## 3. 具体技术实现 (Technical Implementation)

### Collapse Hierarchy (Queue Mode)
The footer follows this collapse sequence for queue mode:

```
1. "tab to queue message · Plan mode" + context  (120 cols)
2. "tab to queue · Plan mode" + context          (50 cols)
3. "tab to queue message" only                   (40 cols, no mode)
4. "tab to queue" only                           (30 cols, no mode)
5. "tab to queue" only                           (20 cols, this test)
```

At 20 columns, even "tab to queue" (~12 chars) + indent (2) = 14 chars is tight but fits.

### Technical Constraints
- **Terminal width**: 20 columns
- **Indent**: 2 spaces (`FOOTER_INDENT_COLS`)
- **Available for content**: 18 columns
- **"tab to queue" length**: ~12 characters (including styled "tab")
- **Margin**: ~6 columns remaining

### Algorithm Path
The `single_line_footer_layout()` function:
1. Tries all queue hint variants with context → fails
2. Tries all queue hint variants without context → "tab to queue" succeeds
3. Returns `SummaryLeft::Custom(line)` with `show_context = false`

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Test Implementation
**`codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`** (lines 4874-4883):

```rust
snapshot_composer_state_with_width(
    "footer_collapse_queue_mode_only",
    20,  // Very narrow width
    true,
    |composer| {
        setup_collab_footer(composer, 98, None);  // No collaboration mode
        composer.set_task_running(true);
        composer.set_text_content("Test".to_string(), Vec::new(), Vec::new());
    },
);
```

### Footer Collapse Logic
**`codex-rs/tui_app_server/src/bottom_pane/footer.rs`**:

1. **Queue States Array** (lines 350-360):
```rust
let queue_states = [
    default_state,  // "tab to queue message" with cycle hint
    LeftSideState {
        hint: SummaryHintKind::QueueMessage,
        show_cycle_hint: false,
    },
    LeftSideState {
        hint: SummaryHintKind::QueueShort,  // "tab to queue"
        show_cycle_hint: false,
    },
];
```

2. **Pass 2: Without Context** (lines 382-395):
```rust
// Pass 2: if context cannot fit, drop it before dropping the queue hint
let mut previous_state: Option<LeftSideState> = None;
for state in queue_states {
    if previous_state == Some(state) {
        continue;
    }
    previous_state = Some(state);
    let width = state_width(state);
    if width > 0 && left_fits(area, width) {
        if state == default_state {
            return (SummaryLeft::Default, false);
        }
        return (SummaryLeft::Custom(state_line(state)), false);
    }
}
```

3. **Left Side Line Construction** (lines 271-300):
```rust
fn left_side_line(
    collaboration_mode_indicator: Option<CollaborationModeIndicator>,  // None
    state: LeftSideState,
) -> Line<'static> {
    let mut line = Line::from("");
    match state.hint {
        SummaryHintKind::None => {}
        SummaryHintKind::Shortcuts => { /* ... */ }
        SummaryHintKind::QueueMessage => { /* ... */ }
        SummaryHintKind::QueueShort => {
            line.push_span(key_hint::plain(KeyCode::Tab));
            line.push_span(" to queue".dim());
        }
    };
    // No mode indicator to append (collaboration_mode_indicator is None)
    line
}
```

### Width Validation
**`left_fits()`** (lines 252-255):
```rust
pub(crate) fn left_fits(area: Rect, left_width: u16) -> bool {
    let max_width = area.width.saturating_sub(FOOTER_INDENT_COLS as u16);
    left_width <= max_width
}
```
At 20 columns: `max_width = 20 - 2 = 18`, and "tab to queue" (~12) < 18, so it fits.

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### State Configuration
| State | Value | Effect |
|-------|-------|--------|
| Terminal width | 20 | Forces minimal display |
| `is_task_running` | `true` | Enables queue mode |
| `collaboration_mode_indicator` | `None` | No mode label |
| `context_window_percent` | 98 | Hidden due to width |
| Textarea content | "Test" | Triggers `ComposerHasDraft` |

### Rendering Components
1. **Key Hint Styling**: `key_hint::plain(KeyCode::Tab)` renders Tab key with visual styling
2. **Dim Styling**: The " to queue" text uses `.dim()` for subtle appearance
3. **Indentation**: `FOOTER_INDENT_COLS` (2) spaces prefix all footer content

### Test Infrastructure
```rust
fn snapshot_composer_state_with_width<F>(
    name: &str,
    width: u16,  // 20 in this test
    enhanced_keys_supported: bool,
    setup: F,
)
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvements)

### Risk Analysis

#### 1. Absolute Minimum Width
- **Current**: 20 columns is near the practical minimum
- **Risk**: At < 16 columns, even "tab to queue" won't fit
- **Behavior**: Footer would be completely hidden or overflow

#### 2. Information Loss
- **Context hidden**: Users can't see token usage
- **Mode hidden**: No collaboration mode indicator
- **Shortcuts hidden**: No hint about other keyboard shortcuts

#### 3. Internationalization
- **Risk**: Translated "to queue" text may be longer
- **Example**: Spanish "para encolar" is longer than "to queue"
- **Impact**: Could overflow even at 20 columns

### Edge Cases

1. **Terminal Resize to Zero**: What happens at 0-10 columns?
2. **Font Scaling**: High-DPI displays with scaled fonts may render differently
3. **Mobile Terminals**: Phone-based SSH clients often have narrow default widths

### Improvement Suggestions

#### 1. Emergency Fallback
```rust
// When even "tab to queue" won't fit
if !left_fits(area, min_hint_width) {
    // Show a simple indicator that footer content exists
    return (SummaryLeft::Custom(Line::from("...".dim())), false);
}
```

#### 2. Icon-Based Hints
```rust
// Use Unicode symbols when text won't fit
let hint = if width < 20 {
    "⭾ ⌨"  // Tab symbol + keyboard symbol
} else {
    "tab to queue"
};
```

#### 3. Expandable Footer
```rust
// Allow users to press a key to expand the footer temporarily
if key == KeyCode::Char('?') && width < 30 {
    show_expanded_footer_overlay();
}
```

#### 4. Minimum Width Warning
```rust
// Warn users when terminal is too narrow
if width < 20 {
    app_event_tx.send(AppEvent::ShowWarning(
        "Terminal too narrow - resize for full UI".to_string()
    ));
}
```

#### 5. Adaptive Font Hints
```rust
// Suggest smaller font if terminal is consistently narrow
if average_width < 30 && session_duration > Duration::minutes(5) {
    show_hint("Consider reducing font size for better experience");
}
```

### Related Snapshots
| Snapshot | Width | Context | Mode | Hint | Description |
|----------|-------|---------|------|------|-------------|
| `footer_collapse_queue_full` | 120 | Yes | No | Full | Complete display |
| `footer_collapse_queue_short_with_context` | 50 | Yes | No | Short | Balanced |
| `footer_collapse_queue_message_without_context` | 40 | No | No | Full | No context |
| `footer_collapse_queue_short_without_context` | 30 | No | No | Short | Minimal hint |
| `footer_collapse_queue_mode_only` | 20 | No | No | Short | This test - ultra-minimal |
