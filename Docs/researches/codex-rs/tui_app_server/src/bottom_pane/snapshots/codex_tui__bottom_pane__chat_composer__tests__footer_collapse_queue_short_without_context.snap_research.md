# Research: Footer Collapse - Queue Short without Context

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer rendering behavior when:
- The composer has **draft content** ("Test" in the textarea)
- A **task is running** (queue mode active)
- The terminal width is **30 columns** - narrow
- **No collaboration mode** is active
- The **short queue hint** ("tab to queue") is displayed
- **Context information is hidden**

This tests a more aggressive collapse state where context is sacrificed to maintain the queue hint visibility in narrower terminals.

## 2. 功能点目的 (Feature Purpose)

The "queue short without context" variant serves to:
1. **Prioritize Actions Over Status**: Ensure queue functionality remains discoverable
2. **Support Narrow Terminals**: Work in constrained display environments
3. **Progressive Disclosure**: Hide less critical information (context) before essential hints
4. **Maintain Usability**: Even at 30 columns, users can discover the Tab key functionality

This represents a step down from the "with context" variants, accepting information loss for space efficiency.

## 3. 具体技术实现 (Technical Implementation)

### Collapse State
At 30 columns:
- **Hint**: `SummaryHintKind::QueueShort` ("tab to queue")
- **Context**: Hidden (`show_context = false`)
- **Mode**: None

### Width Analysis
```
Total width: 30 columns
Indent: 2 columns
Available: 28 columns

"tab to queue": ~12 characters
Remaining: ~16 columns (unused, provides breathing room)
```

### Algorithm Path
1. Try "tab to queue message" with context → fails (too wide)
2. Try "tab to queue" with context → fails (context too wide)
3. Try "tab to queue message" without context → would fit, but...
4. Try "tab to queue" without context → selected (more compact)

Actually, the algorithm prefers the shortest variant that fits, so "tab to queue" is chosen.

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Test Implementation
**`codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`** (lines 4864-4873):

```rust
snapshot_composer_state_with_width(
    "footer_collapse_queue_short_without_context",
    30,  // Narrow width
    true,
    |composer| {
        setup_collab_footer(composer, 98, None);
        composer.set_task_running(true);
        composer.set_text_content("Test".to_string(), Vec::new(), Vec::new());
    },
);
```

### Collapse Logic
**`codex-rs/tui_app_server/src/bottom_pane/footer.rs`**:

1. **Two-Pass Approach** (lines 365-395):
```rust
// Pass 1: Try with context
for state in queue_states {
    if can_show_left_with_context(area, width, context_width) {
        return (SummaryLeft::Custom(state_line(state)), true);
    }
}

// Pass 2: Drop context
for state in queue_states {
    if left_fits(area, width) {
        return (SummaryLeft::Custom(state_line(state)), false);  // No context
    }
}
```

2. **State Selection**:
The algorithm iterates through states in order:
- `QueueMessage` with cycle hint
- `QueueMessage` without cycle hint  
- `QueueShort` without cycle hint ← Selected at 30 cols

### Helper Functions
- **`left_fits()`**: Validates left content fits without context
- **`can_show_left_with_context()`**: Validates left + gap + context fit
- **`state_line()`**: Generates the Line for rendering

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### State Configuration
| State | Value | Effect |
|-------|-------|--------|
| Terminal width | 30 | Forces context to be hidden |
| `is_task_running` | `true` | Enables queue mode |
| `context_window_percent` | 98 | Would show if space allowed |
| `collaboration_mode_indicator` | `None` | No mode label |

### Rendering Chain
1. Test calls `snapshot_composer_state_with_width()`
2. Composer renders with `footer_props()`
3. `single_line_footer_layout()` determines collapse state
4. `render_footer_line()` renders the final output

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvements)

### Risk Analysis

#### 1. Information Loss
- **Context hidden**: Users lose visibility into token usage
- **Impact**: May unexpectedly hit context limits
- **Mitigation**: Alternative warnings or periodic context announcements

#### 2. Width Precision
- **30 columns**: Well below the context threshold
- **Boundary**: Context disappears around 40-45 columns
- **Safety margin**: 30 cols provides comfortable margin

#### 3. Translated Strings
- **Risk**: "to queue" translations may be longer
- **Example**: German "zur Warteschlange" is much longer
- **Impact**: Could overflow even at 30 columns

### Edge Cases

1. **Rapid Resizing**: Frequent resizing around 30-40 cols causes footer changes
2. **Mobile Terminals**: Phone SSH clients often default to ~30-40 cols
3. **Split Screen**: Tmux/vim splits can create narrow panes

### Improvement Suggestions

#### 1. Compact Context Indicator
```rust
// Show minimal context when space is tight
if width < 40 && width >= 25 {
    render_compact_context("98%");  // Just the percentage
}
```

#### 2. Context Warning System
```rust
// Warn when context is low, even if hidden
if context_percent < 10 && width < 40 {
    flash_status_bar();
}
```

#### 3. Responsive Font Suggestions
```rust
// Suggest smaller font for narrow terminals
if width < 40 && session_time > Duration::minutes(1) {
    show_subtle_hint("Tip: Resize terminal or reduce font for full UI");
}
```

#### 4. Expand on Focus
```rust
// Temporarily expand footer when user focuses on input
if composer_focused && width < 40 {
    show_expanded_footer_temporarily();
}
```

#### 5. Test Coverage
- Add test with collaboration mode at 30 cols
- Add test with different context percentages
- Add test at exact boundary where context disappears

### Related Snapshots
| Snapshot | Width | Context | Hint | Description |
|----------|-------|---------|------|-------------|
| `footer_collapse_queue_full` | 120 | Yes | Full | Complete |
| `footer_collapse_queue_short_with_context` | 50 | Yes | Short | Balanced |
| `footer_collapse_queue_message_without_context` | 40 | No | Full | Full hint, no context |
| `footer_collapse_queue_short_without_context` | 30 | No | Short | This test |
| `footer_collapse_queue_mode_only` | 20 | No | Short | Ultra-minimal |
