# Footer Collapse Empty Mode Only - Research Document

## 场景与职责 (Scenario and Responsibility)

This snapshot captures the **footer at very narrow width** (26 columns) in empty composer state, showing the final level of content collapse where only the context indicator ("100% context left") is displayed, right-aligned. The shortcuts hint has been completely dropped due to insufficient space.

**Test Scenario:**
- Terminal width: 26 columns (very narrow terminal)
- Composer state: Empty (no text input)
- Collaboration mode: Disabled/None
- Context window: 100% available
- Agent state: Idle (no task running)

**Key Characteristic:**
At this extreme narrow width, the system makes a hard choice: preserve the ambient context information (which requires minimal space and provides ongoing awareness) over the instructional hint (which, while helpful, is not critical for basic operation).

## 功能点目的 (Purpose of Footer Collapse Functionality)

This represents the **minimum viable footer** - the last resort when terminal space is severely constrained:

**Fallback Chain Completion:**
```
Width 120 (full):     "? for shortcuts · Plan mode (shift+tab to cycle)    100% context left"
Width 60:             "? for shortcuts                                     100% context left"
Width 44:             "? for shortcuts        100% context left"
Width 26 (this):      "       100% context left"
                          ↑
                    Only context remains, right-aligned
```

**Design Rationale:**
1. **Context is ambient** - Users need to know their token usage at all times
2. **Hints are discoverable** - Users can learn shortcuts through other means
3. **Right alignment preserves visual anchor** - Context stays in predictable location

## 具体技术实现 (Key Implementation Details)

### Final Fallback Logic (`footer.rs` lines 437-471)

```rust
// Final fallback: if queue variants (or other earlier states) could not fit
// at all, drop every hint and try to show just the mode label.
if let Some(collaboration_mode_indicator) = collaboration_mode_indicator {
    let mode_only_state = LeftSideState {
        hint: SummaryHintKind::None,
        show_cycle_hint: false,
    };
    let mode_only_width =
        left_side_line(Some(collaboration_mode_indicator), mode_only_state).width() as u16;
    if !context_requires_cycle_hint
        && can_show_left_with_context(area, mode_only_width, context_width)
    {
        return (
            SummaryLeft::Custom(left_side_line(...)),
            true, // show_context
        );
    }
    if left_fits(area, mode_only_width) {
        return (
            SummaryLeft::Custom(left_side_line(...)),
            false, // show_context
        );
    }
}

// Absolute last resort
(SummaryLeft::None, true)  // No left content, but try to show context
```

### SummaryLeft Enum (`footer.rs` lines 302-306)

```rust
pub(crate) enum SummaryLeft {
    Default,           // Use default footer_from_props_lines
    Custom(Line<'static>),  // Use custom pre-built line
    None,              // No left content at all <-- This case
}
```

### Rendering with No Left Content (`footer.rs` lines 1201-1209)

```rust
match summary_left {
    SummaryLeft::Default => {
        render_footer_from_props(...);
    }
    SummaryLeft::Custom(line) => {
        render_footer_line(area, f.buffer_mut(), line);
    }
    SummaryLeft::None => {
        // Nothing rendered on left side
    }
}
if show_context && let Some(line) = &right_line {
    render_context_right(area, f.buffer_mut(), line);  // Context still shown
}
```

### Test Setup (`chat_composer.rs` lines 4780-4787)

```rust
snapshot_composer_state_with_width(
    "footer_collapse_empty_mode_only",
    26,
    true,
    |composer| {
        setup_collab_footer(composer, 100, None);
    },
);
```

## 关键代码路径与文件引用 (File Paths and Line References)

### Collapse Resolution:

| Function | File | Lines | Description |
|----------|------|-------|-------------|
| `single_line_footer_layout` | `footer.rs` | 310-472 | Returns `(SummaryLeft::None, true)` for this case |
| `left_fits` | `footer.rs` | 252-255 | Returns false for shortcuts hint at this width |
| `can_show_left_with_context` | `footer.rs` | 518-527 | Determines context can still show |

### Rendering Path:

| Function | File | Lines | Description |
|----------|------|-------|-------------|
| `render_footer_line` | `footer.rs` | 213-220 | Not called (SummaryLeft::None) |
| `render_context_right` | `footer.rs` | 529-554 | Still called to show context |
| `render_footer_from_props` | `footer.rs` | 229-250 | Not called in this path |

### Layout Calculation at 26 Columns:

```
Total width: 26
Left indent: 2
Right padding: 2

Available for right content: 26 - 2 - 2 = 22
Context content: "100% context left" = 17 chars
Fits: 17 <= 22 ✓

Left content: "? for shortcuts" = 17 chars
Plus indent: 17 + 2 = 19
Would need gap + right content: 19 + 1 + 17 = 37 > 26 ✗

Layout: "       100% context left  "
         ↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑
         7 spaces  17 chars    2 padding
         (26 - 17 - 2 = 7 leading spaces)
```

## 依赖与外部交互 (Dependencies)

### Rendering Dependencies:

1. **ratatui::buffer::Buffer::set_span**
   - Used in `render_context_right` for precise span placement
   - Handles the right-aligned positioning

2. **ratatui::widgets::Paragraph**
   - Not used in this path (no left content)
   - Would be used for `SummaryLeft::Default` or `Custom`

### Layout Dependencies:

```rust
// From footer.rs - critical for this narrow case
pub(crate) fn left_fits(area: Rect, left_width: u16) -> bool {
    let max_width = area.width.saturating_sub(FOOTER_INDENT_COLS as u16);
    left_width <= max_width  // 17 <= 24 (26-2), technically true...
}
```

Wait - `left_fits` would return true (17 <= 24), but the issue is fitting **both** sides.

The real check is in `single_line_footer_layout`:
```rust
let default_width = default_line.width() as u16;  // 17
if default_width > 0 && can_show_left_with_context(area, default_width, context_width) {
    // 17 + 2 (indent) + 1 (gap) + 17 (context) + 2 (right pad) = 39 > 26
    // Returns false, so we fall through to SummaryLeft::None
}
```

## 风险、边界与改进建议 (Risks and Improvements)

### Critical Risks:

1. **Complete Loss of Discoverability**
   - New users won't see "? for shortcuts" at this width
   - May not know how to access help
   - **Mitigation**: Show hint on first launch regardless of width

2. **Context Truncation Risk**
   - At width < 21 (17 + 2 + 2), context itself would be truncated
   - Current code doesn't handle this gracefully
   - **Risk**: "100% context left" → "100% context le" (incomplete)

3. **Minimum Usable Width**
   - Below ~20 columns, the UI becomes essentially unusable
   - No warning or graceful degradation

### Boundary Analysis:

| Width | Behavior |
|-------|----------|
| 26 | Context fully visible, no left content |
| 21-25 | Context partially visible (truncated) |
| 20 | Context barely fits (17 + 2 + 1 = 20, no right pad) |
| < 20 | Context overflows or is cut off |

### Improvement Suggestions:

1. **Ultra-Narrow Mode**
   ```rust
   if area.width < 20 {
       // Show minimal indicator: ">" or "…"
       // Or hide footer entirely to maximize content area
       return (SummaryLeft::None, false);
   }
   ```

2. **Truncation with Ellipsis for Context**
   ```rust
   // In context_window_line or render_context_right
   if content_width > available_width {
       let truncated = truncate_with_ellipsis(content, available_width);
       // "100% context left" → "100% conte…"
   }
   ```

3. **First-Run Hint Override**
   ```rust
   if is_first_run && area.width < 44 {
       // Force show shortcuts hint, hide context
       // "? for shortcuts" is more valuable for new users
       return (SummaryLeft::Default, false);
   }
   ```

4. **Visual Indicator for Narrow Mode**
   ```rust
   // When in ultra-narrow mode, show subtle indicator
   // that content is being hidden
   if summary_left == SummaryLeft::None && !show_context {
       render_footer_line(area, buf, Line::from("…".dim()));
   }
   ```

### Testing Gaps:

1. No test for width < 26
2. No test for context truncation
3. No test for behavior when context is None
4. No test for resize from 120→26→120 (state restoration)

---

**Snapshot Generated**: From `chat_composer.rs` test `footer_collapse_snapshots()`  
**Snapshot Name**: `footer_collapse_empty_mode_only`  
**Terminal Dimensions**: 26 columns × 9 rows  
**Visual Output**: `"       100% context left  "` (7 leading spaces, context right-aligned)
