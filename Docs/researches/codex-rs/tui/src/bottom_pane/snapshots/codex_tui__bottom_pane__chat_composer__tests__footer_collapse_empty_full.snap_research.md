# Footer Collapse Empty Full Mode - Research Document

## 场景与职责 (Scenario and Responsibility)

This snapshot captures the **footer rendering in full width mode** (120 columns) when the chat composer is in an empty state with no active collaboration mode. It represents the "ideal" footer display where all elements have sufficient space to be shown.

**Test Scenario:**
- Terminal width: 120 columns (wide terminal)
- Composer state: Empty (no text input)
- Collaboration mode: Disabled/None
- Context window: 100% available
- Agent state: Idle (no task running)

**UI Component Responsibility:**
The footer serves as a contextual help area at the bottom of the chat composer, providing:
1. Shortcut hints to guide users (e.g., "? for shortcuts")
2. Context information (e.g., "100% context left")
3. Mode indicators when collaboration features are active
4. Queue hints when tasks are running

## 功能点目的 (Purpose of Footer Collapse Functionality)

The footer collapse system is designed to **gracefully degrade** the footer content as terminal width decreases, following a priority-based fallback chain:

1. **Primary Goal**: Always show the most important information first
2. **Secondary Goal**: Maintain context awareness (context window usage)
3. **Tertiary Goal**: Show collaboration mode indicators when applicable

**Fallback Priority Chain (for empty composer, idle state):**
```
Full: "? for shortcuts" + " · " + "Plan mode (shift+tab to cycle)" + "100% context left"
  ↓ (width 60)
Mode Cycle + Context: "? for shortcuts" + context (no cycle hint)
  ↓ (width 44)
Mode Cycle without Context: "? for shortcuts" only
  ↓ (width 26)
Mode Only: Just context indicator
```

This specific snapshot (`footer_collapse_empty_full`) represents the **fullest possible footer state** with all elements visible.

## 具体技术实现 (Key Implementation Details)

### 1. FooterProps Structure (`footer.rs` lines 66-87)
```rust
pub(crate) struct FooterProps {
    pub(crate) mode: FooterMode,
    pub(crate) esc_backtrack_hint: bool,
    pub(crate) use_shift_enter_hint: bool,
    pub(crate) is_task_running: bool,
    pub(crate) collaboration_modes_enabled: bool,
    pub(crate) is_wsl: bool,
    pub(crate) quit_shortcut_key: KeyBinding,
    pub(crate) context_window_percent: Option<i64>,
    pub(crate) context_window_used_tokens: Option<i64>,
    pub(crate) status_line_value: Option<Line<'static>>,
    pub(crate) status_line_enabled: bool,
    pub(crate) active_agent_label: Option<String>,
}
```

### 2. FooterMode Enum (`footer.rs` lines 132-146)
```rust
pub(crate) enum FooterMode {
    QuitShortcutReminder,
    ShortcutOverlay,
    EscHint,
    ComposerEmpty,    // <-- This snapshot uses this mode
    ComposerHasDraft,
}
```

### 3. Context Window Line Generation (`footer.rs` lines 848-860)
```rust
pub(crate) fn context_window_line(percent: Option<i64>, used_tokens: Option<i64>) -> Line<'static> {
    if let Some(percent) = percent {
        let percent = percent.clamp(0, 100);
        return Line::from(vec![Span::from(format!("{percent}% context left")).dim()]);
    }
    if let Some(tokens) = used_tokens {
        let used_fmt = format_tokens_compact(tokens);
        return Line::from(vec![Span::from(format!("{used_fmt} used")).dim()]);
    }
    Line::from(vec![Span::from("100% context left").dim()])
}
```

### 4. Left Side Line Construction (`footer.rs` lines 271-300)
```rust
fn left_side_line(
    collaboration_mode_indicator: Option<CollaborationModeIndicator>,
    state: LeftSideState,
) -> Line<'static> {
    let mut line = Line::from("");
    match state.hint {
        SummaryHintKind::None => {}
        SummaryHintKind::Shortcuts => {
            line.push_span(key_hint::plain(KeyCode::Char('?')));
            line.push_span(" for shortcuts".dim());
        }
        // ... other variants
    };
    // ... mode indicator handling
}
```

### 5. Test Setup (`chat_composer.rs` lines 4761-4763)
```rust
snapshot_composer_state_with_width("footer_collapse_empty_full", 120, true, |composer| {
    setup_collab_footer(composer, 100, None);  // 100% context, no mode indicator
});
```

## 关键代码路径与文件引用 (File Paths and Line References)

### Core Files:

| File | Lines | Purpose |
|------|-------|---------|
| `codex-rs/tui/src/bottom_pane/footer.rs` | 1-1058 | Footer rendering logic, collapse algorithms |
| `codex-rs/tui/src/bottom_pane/chat_composer.rs` | 4749-4921 | Test definitions for footer collapse |
| `codex-rs/tui/src/bottom_pane/chat_composer.rs` | 4657-4687 | `snapshot_composer_state_with_width` helper |

### Key Functions:

| Function | File | Lines | Description |
|----------|------|-------|-------------|
| `single_line_footer_layout` | `footer.rs` | 310-472 | Main collapse logic, decides what fits |
| `left_side_line` | `footer.rs` | 271-300 | Builds left-side footer content |
| `context_window_line` | `footer.rs` | 848-860 | Builds right-side context indicator |
| `render_footer_from_props` | `footer.rs` | 229-250 | Renders footer from props |
| `footer_height` | `footer.rs` | 187-210 | Calculates footer height |
| `footer_props` | `chat_composer.rs` | 3179-3206 | Constructs FooterProps from composer state |
| `footer_mode` | `chat_composer.rs` | 3214-3235 | Determines current footer mode |

### Constants:

| Constant | File | Line | Value | Purpose |
|----------|------|------|-------|---------|
| `FOOTER_INDENT_COLS` | `ui_consts.rs` | - | 2 | Left indentation for footer |
| `FOOTER_CONTEXT_GAP_COLS` | `footer.rs` | 99 | 1 | Gap between left and right content |
| `MODE_CYCLE_HINT` | `footer.rs` | 98 | "shift+tab to cycle" | Mode cycle hint text |

## 依赖与外部交互 (Dependencies)

### External Crates:

1. **ratatui** (v0.29+)
   - `Line`, `Span`, `Buffer` - Terminal rendering primitives
   - `Rect` - Area calculations
   - `Stylize` trait - Color and style application (`.dim()`, `.magenta()`, etc.)
   - `Paragraph` - Widget for rendering text

2. **crossterm** (v0.28+)
   - `KeyCode`, `KeyEvent` - Key binding representations for hints

### Internal Dependencies:

1. **key_hint module** (`key_hint.rs`)
   - `KeyBinding` - Represents keyboard shortcuts visually
   - `plain()`, `ctrl()`, `shift()` - Key binding constructors

2. **ui_consts module** (`ui_consts.rs`)
   - `FOOTER_INDENT_COLS` - Standard footer indentation
   - `LIVE_PREFIX_COLS` - Prefix space for live indicator

3. **status module** (`status.rs`)
   - `format_tokens_compact()` - Token count formatting

### Dependency Graph:
```
chat_composer.rs
    ├── footer.rs
    │   ├── ratatui (Line, Span, Buffer, Rect, Stylize)
    │   ├── crossterm (KeyCode)
    │   ├── key_hint.rs
    │   ├── ui_consts.rs
    │   └── status.rs
    └── [other modules]
```

## 风险、边界与改进建议 (Risks and Improvements)

### Current Risks:

1. **Hardcoded Width Thresholds**
   - Width values (120, 60, 44, 26) are empirically determined
   - May break if text content changes (e.g., localization)
   - **Mitigation**: Tests will catch regressions via snapshot failures

2. **Context Window Percentage Edge Cases**
   - `context_window_line` clamps percentage to 0-100 range
   - Negative or >100 values from backend are silently corrected
   - **Risk**: User might not see actual out-of-range values for debugging

3. **Race Conditions in Footer Flash**
   - Footer flash uses `Instant::now()` comparisons
   - System time changes could cause unexpected behavior
   - **Mitigation**: Time-based rendering is idempotent

### Boundary Conditions:

| Condition | Behavior |
|-----------|----------|
| Width < 26 | Only context indicator shown (right-aligned) |
| Context = 0% | Shows "0% context left" (clamped) |
| Context = None | Shows "100% context left" (default) |
| Empty composer + typing | Footer switches from `ComposerEmpty` to `ComposerHasDraft` |
| Task running | Queue hint replaces shortcuts hint |

### Potential Improvements:

1. **Dynamic Width Calculation**
   ```rust
   // Instead of hardcoded widths, calculate based on actual content
   let min_width = left_side_line(...).width() + context_window_line(...).width() + gap;
   ```

2. **Configurable Footer Elements**
   - Allow users to customize which hints appear
   - Priority-based user preferences

3. **Localization Support**
   - Current implementation uses English-only strings
   - Extract strings to resource files for i18n

4. **Accessibility Enhancements**
   - High contrast mode for footer hints
   - Configurable color schemes for colorblind users

5. **Performance Optimization**
   - Cache `footer_line_width` calculations when props haven't changed
   - Current implementation recalculates on every render

### Testing Gaps:

1. No tests for extreme context values (< 0, > 100)
2. No tests for terminal widths < 20 columns
3. No tests for rapid width changes (resize stress testing)

---

**Snapshot Generated**: From `chat_composer.rs` test `footer_collapse_snapshots()`  
**Snapshot Name**: `footer_collapse_empty_full`  
**Terminal Dimensions**: 120 columns × 9 rows (8 + footer)
