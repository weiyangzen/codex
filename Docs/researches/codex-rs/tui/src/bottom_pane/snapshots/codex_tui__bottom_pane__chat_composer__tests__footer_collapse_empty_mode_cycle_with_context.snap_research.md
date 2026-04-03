# Footer Collapse Empty Mode Cycle with Context - Research Document

## 场景与职责 (Scenario and Responsibility)

This snapshot captures the **footer at medium width** (60 columns) in empty composer state, demonstrating the first level of content collapse where the footer still maintains both the shortcuts hint and context indicator, but drops the mode cycle hint.

**Test Scenario:**
- Terminal width: 60 columns (medium terminal)
- Composer state: Empty (no text input)
- Collaboration mode: Disabled/None
- Context window: 100% available
- Agent state: Idle (no task running)

**Key Difference from Full Mode:**
At this width, the footer can still display both left-side content (shortcuts hint) and right-side content (context indicator), but there's insufficient space for the collaboration mode cycle hint ("shift+tab to cycle").

## 功能点目的 (Purpose of Footer Collapse Functionality)

The collapse system implements a **progressive disclosure** strategy:

1. **Priority 1**: Always show shortcuts hint when composer is empty and idle
2. **Priority 2**: Show context window information (critical for user awareness)
3. **Priority 3**: Show collaboration mode indicators (only when enabled)
4. **Priority 4**: Show mode cycle hints (lowest priority, first to be dropped)

**This Snapshot's Position in Fallback Chain:**
```
Width 120 (full):     "? for shortcuts · Plan mode (shift+tab to cycle)    100% context left"
Width 60 (this):      "? for shortcuts                                     100% context left"
                          ↑
                    Mode cycle hint dropped, context preserved
```

## 具体技术实现 (Key Implementation Details)

### Collapse Logic (`footer.rs` lines 310-472)

The `single_line_footer_layout` function implements the width-based fallback:

```rust
pub(crate) fn single_line_footer_layout(
    area: Rect,
    context_width: u16,
    collaboration_mode_indicator: Option<CollaborationModeIndicator>,
    show_cycle_hint: bool,        // true when idle, false when running
    show_shortcuts_hint: bool,    // true when empty
    show_queue_hint: bool,        // false in this scenario
) -> (SummaryLeft, bool) {
    // Start with default state
    let hint_kind = if show_queue_hint {
        SummaryHintKind::QueueMessage
    } else if show_shortcuts_hint {
        SummaryHintKind::Shortcuts  // <-- Used in this snapshot
    } else {
        SummaryHintKind::None
    };
    
    let default_state = LeftSideState {
        hint: hint_kind,
        show_cycle_hint,  // true, but may be overridden
    };
    
    // Check if default fits with context
    let default_line = left_side_line(collaboration_mode_indicator, default_state);
    let default_width = default_line.width() as u16;
    if default_width > 0 && can_show_left_with_context(area, default_width, context_width) {
        return (SummaryLeft::Default, true);
    }
    // ... fallback logic continues
}
```

### Width Calculation (`footer.rs` lines 504-527)

```rust
pub(crate) fn can_show_left_with_context(area: Rect, left_width: u16, context_width: u16) -> bool {
    let Some(context_x) = right_aligned_x(area, context_width) else {
        return true;
    };
    if left_width == 0 {
        return true;
    }
    let left_extent = FOOTER_INDENT_COLS as u16 + left_width + FOOTER_CONTEXT_GAP_COLS;
    left_extent <= context_x.saturating_sub(area.x)
}
```

At width 60:
- Left content: "? for shortcuts" ≈ 17 chars
- Right content: "100% context left" ≈ 17 chars
- Gap: 1 char
- Indent: 2 chars
- Total: ~37 chars, well within 60 columns

### Test Setup (`chat_composer.rs` lines 4764-4771)

```rust
snapshot_composer_state_with_width(
    "footer_collapse_empty_mode_cycle_with_context",
    60,
    true,
    |composer| {
        setup_collab_footer(composer, 100, None);  // No mode indicator
    },
);
```

## 关键代码路径与文件引用 (File Paths and Line References)

### Core Logic:

| Function | File | Lines | Purpose |
|----------|------|-------|---------|
| `single_line_footer_layout` | `footer.rs` | 310-472 | Main collapse decision logic |
| `can_show_left_with_context` | `footer.rs` | 518-527 | Width fit check with context |
| `left_side_line` | `footer.rs` | 271-300 | Build left content line |
| `left_fits` | `footer.rs` | 252-255 | Basic width fit check |
| `right_aligned_x` | `footer.rs` | 481-502 | Calculate right content position |

### Layout Constants:

| Constant | Value | Purpose |
|----------|-------|---------|
| `FOOTER_INDENT_COLS` | 2 | Left margin padding |
| `FOOTER_CONTEXT_GAP_COLS` | 1 | Minimum gap between left/right |

### Test Infrastructure:

| Function | File | Lines | Purpose |
|----------|------|-------|---------|
| `snapshot_composer_state_with_width` | `chat_composer.rs` | 4657-4687 | Test helper for width-specific snapshots |
| `setup_collab_footer` | `chat_composer.rs` | 4750-4758 | Test setup helper |

## 依赖与外部交互 (Dependencies)

### Rendering Dependencies:

1. **ratatui::layout::Rect**
   - Used for area calculations
   - `width`, `height`, `x`, `y` properties

2. **ratatui::text::Line**
   - `Line::width()` - Critical for fit calculations
   - `Line::from()` - Content construction

3. **ratatui::style::Stylize**
   - `.dim()` - Applied to non-critical text
   - Makes hints less prominent than main content

### Key Trait Implementations:

```rust
// Line width calculation used in collapse logic
impl Line {
    pub fn width(&self) -> usize {
        self.spans.iter().map(|span| span.width()).sum()
    }
}

// Span width from ratatui
impl Span {
    pub fn width(&self) -> usize {
        self.content.width()  // Unicode-aware width
    }
}
```

## 风险、边界与改进建议 (Risks and Improvements)

### Specific Risks for This Collapse Level:

1. **Narrow Window for Context Preservation**
   - At exactly 44 columns, context is dropped (see `footer_collapse_empty_mode_cycle_without_context`)
   - Small width differences cause visible content changes
   - **Impact**: User might see flickering during terminal resize

2. **Hardcoded Width Thresholds**
   - The 60-column threshold is empirical
   - Depends on exact text: "? for shortcuts" (17 chars) + "100% context left" (17 chars) + gap (1) + indent (2) = 37 chars minimum
   - **Risk**: Text changes break the threshold

### Boundary Analysis:

| Width | Left Content | Right Content | Notes |
|-------|--------------|---------------|-------|
| 120 | Full with mode | Context | Full display |
| 60 | Shortcuts only | Context | **This snapshot** |
| 44 | Shortcuts only | None | Context dropped |
| 26 | None | Context | Only context |

### Improvement Opportunities:

1. **Smooth Transitions**
   ```rust
   // Instead of discrete thresholds, use progressive truncation
   if width < 60 {
       // Truncate context text: "100% context left" → "100%"
       // Or use compact form: "100%" instead of "100% context left"
   }
   ```

2. **Minimum Width Guarantee**
   - Define a `MIN_FOOTER_WIDTH` constant (e.g., 20)
   - Below this, show minimal indicator: ">"

3. **Resize Debouncing**
   - Current implementation recalculates on every render
   - Could cache layout decisions for N frames during resize

4. **Content-Aware Truncation**
   ```rust
   // Prioritize numeric information
   "100% context left" → "100%" → "100" → "…"
   ```

### Testing Considerations:

1. **Gap Testing**: Verify exactly 1-column gap is maintained
2. **Edge Case**: Test at exactly 37 columns (minimum for both)
3. **Resize Simulation**: Test rapid width changes 120→60→44→26→60→120

---

**Snapshot Generated**: From `chat_composer.rs` test `footer_collapse_snapshots()`  
**Snapshot Name**: `footer_collapse_empty_mode_cycle_with_context`  
**Terminal Dimensions**: 60 columns × 9 rows  
**Visual Output**: `"  ? for shortcuts                        100% context left  "`
