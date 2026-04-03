# Research: Footer Collapse - Queue Full

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the footer rendering behavior when:
- The composer has **draft content** ("Test" in the textarea)
- A **task is running** (queue mode active)
- The terminal width is **wide (120 columns)** - no collapse needed
- **No collaboration mode** is active (pure queue mode without Plan/Execute indicator)
- Full **context window information** is displayed

This represents the "gold standard" footer display for queue mode when screen space is abundant, showing all available information without any compromises.

## 2. 功能点目的 (Feature Purpose)

The "queue full" variant demonstrates:
1. **Complete Information Display**: Show everything - queue hint, context, and available shortcuts
2. **Queue Mode Priority**: When a task is running, the queue hint takes precedence over other hints
3. **Context Awareness**: Display "98% context left" to inform users of token usage
4. **Baseline Reference**: Serve as the reference snapshot for comparing collapsed variants

This test establishes the maximum information density the footer can display in queue mode.

## 3. 具体技术实现 (Technical Implementation)

### Footer Composition
At full width, the footer consists of:
```
[indent] tab to queue message                                      98% context left
```

### Technical Details
- **Left side**: "tab to queue message" with Tab key styling
- **Right side**: "98% context left" context indicator (dimmed)
- **Width**: 120 columns provides ample space for full content
- **Mode**: `FooterMode::ComposerHasDraft` with `is_task_running = true`

### Key Differences from Plan Mode
Unlike the Plan mode variants, this test:
- Has **no collaboration mode indicator** (no "Plan mode" text)
- Shows the **full queue hint** ("tab to queue message" vs "tab to queue")
- Uses **default styling** without magenta mode coloring

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Test Implementation
**`codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`** (lines 4839-4843):

```rust
snapshot_composer_state_with_width("footer_collapse_queue_full", 120, true, |composer| {
    setup_collab_footer(composer, 98, None);  // None = no collaboration mode
    composer.set_task_running(true);
    composer.set_text_content("Test".to_string(), Vec::new(), Vec::new());
});
```

### Setup Function
**`setup_collab_footer()`** (lines 4765-4773):
```rust
fn setup_collab_footer(
    composer: &mut ChatComposer,
    context_percent: i64,
    indicator: Option<CollaborationModeIndicator>,  // None in this test
) {
    composer.set_collaboration_modes_enabled(true);
    composer.set_collaboration_mode_indicator(indicator);  // No mode indicator
    composer.set_context_window(Some(context_percent), None);
}
```

### Footer Rendering Logic
**`codex-rs/tui_app_server/src/bottom_pane/footer.rs`**:

1. **Hint Selection** (lines 318-324):
```rust
let hint_kind = if show_queue_hint {
    SummaryHintKind::QueueMessage  // Full hint when space allows
} else if show_shortcuts_hint {
    SummaryHintKind::Shortcuts
} else {
    SummaryHintKind::None
};
```

2. **Left Side Construction** (lines 271-300):
```rust
fn left_side_line(
    collaboration_mode_indicator: Option<CollaborationModeIndicator>,  // None
    state: LeftSideState,
) -> Line<'static>
```

3. **Context Rendering** (lines 529-554):
```rust
pub(crate) fn render_context_right(area: Rect, buf: &mut Buffer, line: &Line<'static>)
```

### Footer Mode Logic
**`footer_from_props_lines()`** (lines 580-631):
```rust
FooterMode::ComposerHasDraft => {
    let state = LeftSideState {
        hint: if show_queue_hint {
            SummaryHintKind::QueueMessage  // This branch taken
        } else if show_shortcuts_hint {
            SummaryHintKind::Shortcuts
        } else {
            SummaryHintKind::None
        },
        show_cycle_hint,
    };
    vec![left_side_line(collaboration_mode_indicator, state)]
}
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### State Configuration
| Component | Value | Effect |
|-----------|-------|--------|
| `collaboration_mode_indicator` | `None` | No mode label shown |
| `is_task_running` | `true` | Queue hint enabled |
| `context_window_percent` | `98` | Context indicator shows "98% context left" |
| `textarea.has_content()` | `true` | `ComposerHasDraft` mode |
| Terminal width | `120` | Full display, no collapse |

### Rendering Dependencies
1. **ratatui**: `Line`, `Span`, `Buffer`, `Rect` for terminal rendering
2. **key_hint**: `key_hint::plain(KeyCode::Tab)` for styled key display
3. **Stylize**: `.dim()` for context indicator styling

### Test Infrastructure
```rust
fn snapshot_composer_state_with_width<F>(
    name: &str,
    width: u16,  // 120
    enhanced_keys_supported: bool,
    setup: F,
)
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvements)

### Risk Analysis

#### 1. Context Window Accuracy
- **Risk**: The "98% context left" is hardcoded in the test; real context calculation may differ
- **Impact**: Test validates rendering, not actual context calculation
- **Mitigation**: Separate tests exist for context calculation logic

#### 2. String Changes
- **Risk**: Changing "tab to queue message" would require snapshot updates
- **Impact**: All queue-related snapshots would need regeneration
- **Mitigation**: String constants should be centralized

#### 3. Width Assumptions
- **Risk**: 120 columns assumes modern terminal sizes
- **Impact**: Legacy terminals or split-screen setups may never see this view
- **Mitigation**: Most users have 80+ column terminals

### Edge Cases

1. **Rapid Task State Changes**: Task starting/stopping quickly could cause footer flicker
2. **Context Percentage Boundaries**: At 100% vs 99%, the message changes subtly
3. **Empty Queue**: Even with no queued messages, hint still shows (correct behavior)

### Improvement Suggestions

#### 1. Dynamic Hint Text
```rust
// Show different text based on queue state
let queue_hint = if queued_messages.is_empty() {
    "tab to queue message"
} else {
    "tab to queue (N pending)"
};
```

#### 2. Context Warning Colors
```rust
// Change color based on context availability
let context_style = match context_percent {
    0..=10 => Style::default().red().bold(),    // Critical
    11..=25 => Style::default().yellow(),        // Warning
    _ => Style::default().dim(),                 // Normal
};
```

#### 3. Alternative Context Display
```rust
// Show tokens used instead of percentage when available
let context_text = if let Some(tokens) = context_window_used_tokens {
    format_tokens_compact(tokens)
} else {
    format!("{percent}% context left")
};
```

#### 4. Keyboard Shortcut Discovery
```rust
// Add subtle hint about Shift+Enter for newline in queue mode
let hint = if show_queue_hint && width > 100 {
    "tab to queue message  ·  shift+enter for newline"
} else {
    "tab to queue message"
};
```

#### 5. Test Coverage
- Add test for `context_window_used_tokens` variant
- Add test for boundary width where collapse begins (around 50-60 cols)
- Add test for rapid task state transitions

### Related Snapshots
| Snapshot | Mode | Width | Context | Description |
|----------|------|-------|---------|-------------|
| `footer_collapse_queue_full` | None | 120 | Yes | This test - baseline |
| `footer_collapse_queue_short_with_context` | None | 50 | Yes | Short hint |
| `footer_collapse_queue_message_without_context` | None | 40 | No | No context |
| `footer_collapse_queue_short_without_context` | None | 30 | No | Short, no context |
| `footer_collapse_queue_mode_only` | None | 20 | No | Minimal |
| `footer_collapse_plan_queue_full` | Plan | 120 | Yes | With Plan mode |
