# Footer Collapse Plan Empty Mode Cycle without Context - Research Document

## 场景与职责 (Scenario and Responsibility)

This snapshot captures the **footer at narrow width with Plan collaboration mode active** (44 columns), showing the collapse state where the context indicator is dropped, leaving only the Plan mode indicator with its cycle hint.

**Test Scenario:**
- Terminal width: 44 columns (narrow terminal)
- Composer state: Empty (no text input)
- Collaboration mode: **Plan** (via `CollaborationModeIndicator::Plan`)
- Context window: 100% available (but not displayed)
- Agent state: Idle (no task running)

**Key Visual Elements:**
- Left: "Plan mode (shift+tab to cycle)" (magenta color)
- Right: None (context dropped)
- Full width dedicated to mode awareness

**Priority Decision:**
At this width, the system prioritizes the **active mode indicator** over ambient context information. This makes sense because:
1. Mode affects system behavior significantly
2. Users need to know which mode they're in
3. Context can be checked via other means (commands, status line)

## 功能点目的 (Purpose of Footer Collapse Functionality)

This snapshot demonstrates **aggressive prioritization** when space is severely constrained:

**Collapse Progression for Plan Mode:**
```
Width 120: "? for shortcuts · Plan mode (shift+tab to cycle)    100% context left"
Width 60:  "Plan mode (shift+tab to cycle)         100% context left"
Width 44:  "Plan mode (shift+tab to cycle)"
                ↑
            Context dropped, mode preserved
```

**Design Philosophy:**
- **Mode is functional** - It changes how the system behaves
- **Context is informational** - Nice to know, but not critical for operation
- **When forced to choose, prefer functional over informational**

## 具体技术实现 (Key Implementation Details)

### Collapse Logic for Mode-Only Display (`footer.rs` lines 396-436)

```rust
} else if collaboration_mode_indicator.is_some() {
    if show_cycle_hint {
        // First fallback: drop shortcut hint but keep cycle hint
        let cycle_state = LeftSideState {
            hint: SummaryHintKind::None,
            show_cycle_hint: true,
        };
        let cycle_width = state_width(cycle_state);
        
        // Try to fit with context
        if cycle_width > 0 && can_show_left_with_context(area, cycle_width, context_width) {
            return (SummaryLeft::Custom(state_line(cycle_state)), true);  // With context
        }
        
        // Can't fit with context, try without
        if cycle_width > 0 && left_fits(area, cycle_width) {
            return (SummaryLeft::Custom(state_line(cycle_state)), false); // No context <-- This case
        }
    }
    // ... next fallback: mode without cycle hint
}
```

### Width Calculation at 44 Columns (`footer.rs` lines 252-255, 518-527)

```rust
pub(crate) fn left_fits(area: Rect, left_width: u16) -> bool {
    let max_width = area.width.saturating_sub(FOOTER_INDENT_COLS as u16);
    left_width <= max_width  // 32 <= 42 (44-2) ✓
}

pub(crate) fn can_show_left_with_context(area: Rect, left_width: u16, context_width: u16) -> bool {
    let Some(context_x) = right_aligned_x(area, context_width) else {
        return true;
    };
    if left_width == 0 {
        return true;
    }
    let left_extent = FOOTER_INDENT_COLS as u16 + left_width + FOOTER_CONTEXT_GAP_COLS;
    left_extent <= context_x.saturating_sub(area.x)  // 2 + 32 + 1 = 35 > 25 (context_x) ✗
}
```

At width 44:
- Left content: "Plan mode (shift+tab to cycle)" = 32 chars
- With indent: 32 + 2 = 34
- Context: "100% context left" = 17 chars
- Right-aligned context starts at: 44 - 17 - 2 = 25
- Left extent (35) > Context start (25), so they would overlap
- Result: Context is dropped

### Right-Aligned Position Calculation (`footer.rs` lines 481-502)

```rust
fn right_aligned_x(area: Rect, content_width: u16) -> Option<u16> {
    let right_padding = FOOTER_INDENT_COLS as u16;  // 2
    let max_width = area.width.saturating_sub(right_padding);  // 42
    
    if content_width >= max_width {
        return Some(area.x.saturating_add(right_padding));  // Start at column 2
    }
    
    Some(
        area.x
            .saturating_add(area.width)      // 44
            .saturating_sub(content_width)   // - 17 = 27
            .saturating_sub(right_padding),  // - 2 = 25
    )
}
```

### Test Setup (`chat_composer.rs` lines 4806-4813)

```rust
snapshot_composer_state_with_width(
    "footer_collapse_plan_empty_mode_cycle_without_context",
    44,
    true,
    |composer| {
        setup_collab_footer(composer, 100, Some(CollaborationModeIndicator::Plan));
    },
);
```

## 关键代码路径与文件引用 (File Paths and Line References)

### Decision Flow:

```
single_line_footer_layout(area=44, context_width=17, mode=Plan)
├── Check: default with context? → No (would overlap)
├── collaboration_mode_indicator.is_some()? → Yes
│   └── show_cycle_hint? → Yes
│       ├── Try cycle_state with context
│       │   └── can_show_left_with_context(32, 17)? → No (35 > 25)
│       └── Try cycle_state without context
│           └── left_fits(32)? → Yes (32 <= 42)
│               └── Return (Custom(cycle_line), false) ← This snapshot
└── ...
```

### Key Functions:

| Function | File | Lines | Description |
|----------|------|-------|-------------|
| `single_line_footer_layout` | `footer.rs` | 310-472 | Returns mode-only without context |
| `can_show_left_with_context` | `footer.rs` | 518-527 | Returns false at this width |
| `left_fits` | `footer.rs` | 252-255 | Returns true for mode text |
| `right_aligned_x` | `footer.rs` | 481-502 | Calculates context position |

### Layout Math:

```
Width: 44

Attempt 1: Both sides
- Left: "Plan mode (shift+tab to cycle)" = 32
- Left with indent: 2 + 32 = 34
- Right: "100% context left" = 17
- Right position: 44 - 17 - 2 = 25
- Gap: 25 - 34 = -9 (OVERLAP!)
- Result: REJECTED

Attempt 2: Mode only
- Left: 32 + 2 = 34
- Max left width: 44 - 2 = 42
- 34 <= 42 ✓
- Result: ACCEPTED

Final layout:
"  Plan mode (shift+tab to cycle)            "
 ↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑
 2  32 chars                       10 spaces
```

## 依赖与外部交互 (Dependencies)

### Critical Dependencies:

1. **ratatui::layout::Rect**
   - `area.width`, `area.x` - Position calculations
   - `saturating_sub` - Safe arithmetic for unsigned types

2. **ratatui::text::Line::width**
   - Accurate Unicode width calculation
   - Used for all fit checks

### Layout Constants:

| Constant | Value | Usage |
|----------|-------|-------|
| `FOOTER_INDENT_COLS` | 2 | Left padding |
| `FOOTER_CONTEXT_GAP_COLS` | 1 | Minimum gap |

## 风险、边界与改进建议 (Risks and Improvements)

### Specific Risks:

1. **Loss of Context Awareness**
   - Users can't see token usage at a glance
   - May unexpectedly hit context limits
   - **Mitigation**: Show warning when context is low (< 20%)

2. **Mode Text Truncation Risk**
   - "Plan mode (shift+tab to cycle)" = 32 chars
   - At width 34 (32 + 2 indent), it barely fits
   - **Risk**: Longer mode names would be truncated

3. **Inconsistent Experience**
   - Context appears/disappears based on terminal width
   - Users may be confused why context is sometimes missing
   - **Mitigation**: Subtle indicator that content is hidden

### Boundary Analysis:

| Width | Behavior |
|-------|----------|
| 60 | Mode + cycle + context |
| 44 | Mode + cycle only (this) |
| 35 | Mode + cycle barely fits |
| 26 | "Plan mode" only (no cycle) |
| < 26 | Mode text truncated or hidden |

### Improvement Suggestions:

1. **Context Warning Indicator**
   ```rust
   // When context is hidden but low, show warning
   if !show_context && context_percent < 20 {
       // Add ⚠️ or similar to mode indicator
       line.push_span(" ⚠️".yellow());
   }
   ```

2. **Abbreviated Cycle Hint**
   ```rust
   // Shorter version when space is tight
   if width < 50 {
       "Plan mode (↹)"  // Use tab symbol
   } else {
       "Plan mode (shift+tab to cycle)"
   }
   ```

3. **Hover/Focus Expansion**
   ```rust
   // If terminal supports it, expand on hover
   if mouse_over_footer && width < 60 {
       temporarily_expand_footer_to_show_context();
   }
   ```

4. **Status Line Fallback**
   ```rust
   // When footer can't show context, ensure status line does
   if !show_context && status_line_enabled {
       status_line_must_include_context();
   }
   ```

5. **Minimum Width Enforcement**
   ```rust
   // Advertise minimum supported width
   pub const MIN_RECOMMENDED_WIDTH: u16 = 60;
   
   if area.width < MIN_RECOMMENDED_WIDTH {
       // Show subtle warning or recommendation
   }
   ```

### Testing Gaps:

1. No test for context < 20% when hidden
2. No test for mode text at exact fit width (35)
3. No test for resize from 60→44→60 (state consistency)
4. No test for all mode types at this width

---

**Snapshot Generated**: From `chat_composer.rs` test `footer_collapse_snapshots()`  
**Snapshot Name**: `footer_collapse_plan_empty_mode_cycle_without_context`  
**Terminal Dimensions**: 44 columns × 9 rows  
**Visual Output**: `"  Plan mode (shift+tab to cycle)            "`  
**Note**: "Plan mode" appears in magenta color; context is completely hidden
