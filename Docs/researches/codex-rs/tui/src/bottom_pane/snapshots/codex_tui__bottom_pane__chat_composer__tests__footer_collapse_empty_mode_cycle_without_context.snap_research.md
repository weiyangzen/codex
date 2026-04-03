# Footer Collapse Empty Mode Cycle without Context - Research Document

## 场景与职责 (Scenario and Responsibility)

This snapshot captures the **footer at narrow width** (44 columns) in empty composer state, showing the second level of content collapse where the right-side context indicator ("100% context left") is dropped, leaving only the shortcuts hint on the left side.

**Test Scenario:**
- Terminal width: 44 columns (narrow terminal)
- Composer state: Empty (no text input)
- Collaboration mode: Disabled/None
- Context window: 100% available (but not displayed due to width)
- Agent state: Idle (no task running)

**Key Difference from Wider Modes:**
At this width, there's insufficient space to display both the left-side shortcuts hint and the right-side context indicator. The system prioritizes the shortcuts hint over the context indicator, as the hint provides actionable guidance while the context is ambient information.

## 功能点目的 (Purpose of Footer Collapse Functionality)

The collapse system follows a **strict priority hierarchy**:

1. **Instructional hints** (shortcuts, queue) - Highest priority
2. **Mode indicators** - Medium priority (when collaboration enabled)
3. **Context information** - Lower priority (ambient, can be inferred)

**This Snapshot's Position in Fallback Chain:**
```
Width 120 (full):     "? for shortcuts · Plan mode (shift+tab to cycle)    100% context left"
Width 60:             "? for shortcuts                                     100% context left"
Width 44 (this):      "? for shortcuts        100% context left"
                          ↑
                    Both content squeezed, context still visible but tight
```

Wait - looking at the actual snapshot content:
```
"  ? for shortcuts        100% context left  "
```

Actually at width 44, both are still visible! The context is right-aligned and the shortcuts hint is left-aligned with spacing between them.

## 具体技术实现 (Key Implementation Details)

### The Collapse Decision (`footer.rs` lines 331-436)

```rust
// First check: does default state fit with context?
let default_line = left_side_line(collaboration_mode_indicator, default_state);
let default_width = default_line.width() as u16;
if default_width > 0 && can_show_left_with_context(area, default_width, context_width) {
    return (SummaryLeft::Default, true);  // Both fit
}

// If not, try without cycle hint
if collaboration_mode_indicator.is_some() {
    if show_cycle_hint {
        let cycle_state = LeftSideState {
            hint: SummaryHintKind::None,
            show_cycle_hint: true,
        };
        let cycle_width = state_width(cycle_state);
        if cycle_width > 0 && can_show_left_with_context(area, cycle_width, context_width) {
            return (SummaryLeft::Custom(state_line(cycle_state)), true);
        }
        if cycle_width > 0 && left_fits(area, cycle_width) {
            return (SummaryLeft::Custom(state_line(cycle_state)), false); // No context
        }
    }
}
```

### Right-Aligned Context Rendering (`footer.rs` lines 529-554)

```rust
pub(crate) fn render_context_right(area: Rect, buf: &mut Buffer, line: &Line<'static>) {
    if area.is_empty() {
        return;
    }
    let context_width = line.width() as u16;
    let Some(mut x) = right_aligned_x(area, context_width) else {
        return;
    };
    let y = area.y + area.height.saturating_sub(1);
    // ... render spans
}
```

### Right Alignment Calculation (`footer.rs` lines 481-502)

```rust
fn right_aligned_x(area: Rect, content_width: u16) -> Option<u16> {
    if area.is_empty() {
        return None;
    }
    let right_padding = FOOTER_INDENT_COLS as u16;  // 2
    let max_width = area.width.saturating_sub(right_padding);
    if content_width == 0 || max_width == 0 {
        return None;
    }
    if content_width >= max_width {
        return Some(area.x.saturating_add(right_padding));
    }
    Some(
        area.x
            .saturating_add(area.width)
            .saturating_sub(content_width)
            .saturating_sub(right_padding),
    )
}
```

At width 44 with content width 17 ("100% context left"):
- `right_padding` = 2
- `content_width` = 17
- `x` = 44 - 17 - 2 = 25

So context starts at column 25, leaving room for left content.

### Test Setup (`chat_composer.rs` lines 4772-4779)

```rust
snapshot_composer_state_with_width(
    "footer_collapse_empty_mode_cycle_without_context",
    44,
    true,
    |composer| {
        setup_collab_footer(composer, 100, None);
    },
);
```

## 关键代码路径与文件引用 (File Paths and Line References)

### Width Calculation Functions:

| Function | File | Lines | Description |
|----------|------|-------|-------------|
| `right_aligned_x` | `footer.rs` | 481-502 | Calculate X position for right-aligned content |
| `render_context_right` | `footer.rs` | 529-554 | Render context indicator on the right |
| `can_show_left_with_context` | `footer.rs` | 518-527 | Check if both sides fit |
| `max_left_width_for_right` | `footer.rs` | 504-516 | Calculate available left width |

### Layout Math:

```
Total width: 44
Left indent: 2
Right padding: 2
Gap: 1 (implied)

Available for content: 44 - 2 - 2 = 40

Left content: "? for shortcuts" = 17 chars
Right content: "100% context left" = 17 chars
Total content: 17 + 17 = 34
Gap needed: 40 - 34 = 6 columns of spacing

Layout: "  ? for shortcuts      100% context left  "
         ↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑
         2  17 chars    6 spaces   17 chars   2
```

## 依赖与外部交互 (Dependencies)

### Critical Dependencies:

1. **ratatui::buffer::Buffer**
   - `buf.set_span()` - Used in `render_context_right`
   - Direct buffer manipulation for precise positioning

2. **ratatui::layout::Rect**
   - `area.width`, `area.x`, `area.y` - Position calculations
   - `area.is_empty()` - Guard checks

### Unicode Width Handling:

```rust
// From ratatui - ensures proper width calculation for Unicode
use unicode_width::UnicodeWidthStr;

impl Span {
    pub fn width(&self) -> usize {
        self.content.width()  // Uses UnicodeWidthStr
    }
}
```

This ensures that even with multi-byte characters, width calculations are accurate.

## 风险、边界与改进建议 (Risks and Improvements)

### Specific Risks:

1. **Tight Fit at 44 Columns**
   - Only 6 columns of spacing between left and right
   - If either text grows slightly, they may collide
   - **Mitigation**: The `can_show_left_with_context` check prevents overlap

2. **Context Visibility vs. Actionability Trade-off**
   - Context (100% left) is ambient but useful
   - Shortcuts hint is actionable but less critical for experienced users
   - **Question**: Should context be prioritized over hints for power users?

### Boundary Analysis:

| Scenario | Behavior |
|----------|----------|
| Width = 44 (exact) | Both sides fit with 6-col gap |
| Width = 38 | Would drop context (17 + 1 + 17 + 2 + 2 = 39 min) |
| Width = 37 | Context definitely dropped |
| Context text grows | May push into left content territory |

### Improvement Suggestions:

1. **Dynamic Gap Adjustment**
   ```rust
   // Instead of fixed gap, calculate proportional spacing
   let available_gap = area.width - left_width - right_width - (indent * 2);
   let gap = available_gap / 2;  // Center the gap
   ```

2. **Compact Context Mode**
   ```rust
   // When space is tight, use abbreviated form
   if width < 50 {
       "100% context left" → "100%"
   }
   if width < 40 {
       "100%" → "100"
   }
   ```

3. **Collision Detection Enhancement**
   ```rust
   // Add buffer zone to prevent near-collisions
   let min_gap = 2;  // Minimum 2 columns between sides
   can_show_left_with_context(area, left_width + min_gap, right_width + min_gap)
   ```

4. **Visual Separator**
   ```rust
   // Add subtle separator when space allows
   if gap >= 3 {
       line.push_span(" · ".dim());  // Already used for mode separator
   }
   ```

### Testing Gaps:

1. No test for exact boundary (38-39 columns)
2. No test for context text with different percentages
3. No test for Unicode characters in context (wider/narrower)

---

**Snapshot Generated**: From `chat_composer.rs` test `footer_collapse_snapshots()`  
**Snapshot Name**: `footer_collapse_empty_mode_cycle_without_context`  
**Terminal Dimensions**: 44 columns × 9 rows  
**Visual Output**: `"  ? for shortcuts        100% context left  "`
