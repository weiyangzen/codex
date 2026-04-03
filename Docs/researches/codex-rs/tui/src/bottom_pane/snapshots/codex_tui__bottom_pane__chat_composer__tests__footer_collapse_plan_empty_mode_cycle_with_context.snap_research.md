# Footer Collapse Plan Empty Mode Cycle with Context - Research Document

## 场景与职责 (Scenario and Responsibility)

This snapshot captures the **footer at medium width with Plan collaboration mode active** (60 columns), showing the first level of collapse where the shortcuts hint is dropped, but the mode indicator with its cycle hint and the context information are preserved.

**Test Scenario:**
- Terminal width: 60 columns (medium terminal)
- Composer state: Empty (no text input)
- Collaboration mode: **Plan** (via `CollaborationModeIndicator::Plan`)
- Context window: 100% available
- Agent state: Idle (no task running)

**Key Visual Elements:**
- Left: "Plan mode (shift+tab to cycle)" (magenta color)
- Right: "100% context left"
- The shortcuts hint ("? for shortcuts") has been dropped to save space

**Priority Decision:**
When space is constrained, the system prioritizes:
1. **Active mode indicator** (most important - affects behavior)
2. **Context information** (ambient but critical)
3. **Shortcuts hint** (discoverable, lowest priority)

## 功能点目的 (Purpose of Footer Collapse Functionality)

This snapshot illustrates the **mode-aware collapse strategy**:

**Without Mode (empty):**
```
Width 60: "? for shortcuts                        100% context left"
```

**With Plan Mode (this snapshot):**
```
Width 60: "Plan mode (shift+tab to cycle)         100% context left"
```

**Key Insight:** When a collaboration mode is active, the mode indicator **replaces** the shortcuts hint rather than being added to it. This maintains a consistent left-side width budget.

## 具体技术实现 (Key Implementation Details)

### Collapse Logic with Mode (`footer.rs` lines 396-436)

```rust
} else if collaboration_mode_indicator.is_some() {
    if show_cycle_hint {
        // First fallback: drop shortcut hint but keep the cycle
        // hint on the mode label if it can fit.
        let cycle_state = LeftSideState {
            hint: SummaryHintKind::None,  // No shortcuts hint
            show_cycle_hint: true,        // But keep cycle hint
        };
        let cycle_width = state_width(cycle_state);
        if cycle_width > 0 && can_show_left_with_context(area, cycle_width, context_width) {
            return (SummaryLeft::Custom(state_line(cycle_state)), true);
        }
        if cycle_width > 0 && left_fits(area, cycle_width) {
            return (SummaryLeft::Custom(state_line(cycle_state)), false);
        }
    }
    // ... next fallback: mode only
}
```

### State Width Calculation (`footer.rs` lines 335-342)

```rust
let state_line = |state: LeftSideState| -> Line<'static> {
    if state == default_state {
        default_line.clone()
    } else {
        left_side_line(collaboration_mode_indicator, state)
    }
};
let state_width = |state: LeftSideState| -> u16 { state_line(state).width() as u16 };
```

For Plan mode with cycle hint:
- "Plan mode (shift+tab to cycle)" = 32 characters
- Plus styling overhead (negligible for width)
- Context: "100% context left" = 17 characters
- Total with spacing: ~32 + 1 + 17 + 2 + 2 = 54 < 60 ✓

### Left Side Construction (`footer.rs` lines 291-297)

```rust
if let Some(collaboration_mode_indicator) = collaboration_mode_indicator {
    if !matches!(state.hint, SummaryHintKind::None) {
        line.push_span(" · ".dim());  // Only add separator if there's a hint
    }
    line.push_span(collaboration_mode_indicator.styled_span(state.show_cycle_hint));
}
```

When `state.hint == SummaryHintKind::None`, no separator is added.

### Test Setup (`chat_composer.rs` lines 4798-4805)

```rust
snapshot_composer_state_with_width(
    "footer_collapse_plan_empty_mode_cycle_with_context",
    60,
    true,
    |composer| {
        setup_collab_footer(composer, 100, Some(CollaborationModeIndicator::Plan));
    },
);
```

## 关键代码路径与文件引用 (File Paths and Line References)

### Collapse Decision Tree:

```
single_line_footer_layout
├── show_queue_hint? → No (idle)
├── collaboration_mode_indicator.is_some()? → Yes
│   └── show_cycle_hint? → Yes
│       ├── Try: hint=None, show_cycle_hint=true
│       │   └── can_show_left_with_context? → Yes (this snapshot)
│       └── Fallback: hint=None, show_cycle_hint=true without context
└── ...
```

### Key Functions:

| Function | File | Lines | Description |
|----------|------|-------|-------------|
| `single_line_footer_layout` | `footer.rs` | 310-472 | Main collapse logic |
| `left_side_line` | `footer.rs` | 271-300 | Builds line with/without hint |
| `state_width` | `footer.rs` | 342 | Calculates width for state |
| `can_show_left_with_context` | `footer.rs` | 518-527 | Fit check |

### Width Budget at 60 Columns:

```
Total: 60
Left indent: 2
Right padding: 2
Gap: 1 (minimum)
Available for content: 60 - 2 - 2 - 1 = 55

Left content: "Plan mode (shift+tab to cycle)" = 32
Right content: "100% context left" = 17
Total needed: 32 + 17 = 49
Margin: 55 - 49 = 6 columns (comfortable fit)
```

## 依赖与外部交互 (Dependencies)

### Layout Dependencies:

1. **ratatui::layout::Rect**
   - `area.width` - Total available width
   - Used in all width calculations

2. **ratatui::text::Line**
   - `line.width()` - Unicode-aware width calculation
   - Critical for accurate fit assessment

### State Management:

```rust
// LeftSideState drives the content selection
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct LeftSideState {
    hint: SummaryHintKind,      // None, Shortcuts, QueueMessage, QueueShort
    show_cycle_hint: bool,      // Additional hint for mode cycling
}
```

### Color Dependencies:

- `Span::from(label).magenta()` - Plan mode styling
- Applied in `CollaborationModeIndicator::styled_span()`

## 风险、边界与改进建议 (Risks and Improvements)

### Specific Risks:

1. **Mode Text Length Variability**
   - "Plan mode (shift+tab to cycle)" = 32 chars
   - "Pair Programming mode (shift+tab to cycle)" = 44 chars
   - Same width (60) might not fit all modes equally
   - **Risk**: Inconsistent collapse behavior across modes

2. **Cycle Hint Truncation**
   - At width 44, cycle hint may be dropped
   - Users won't know how to switch modes
   - **Impact**: Reduced discoverability

3. **Context vs. Mode Priority**
   - Current: Keep both mode and context, drop hint
   - Alternative: Keep hint and context, drop mode cycle
   - **Question**: Is mode more important than shortcuts for new users?

### Boundary Analysis:

| Width | Plan Mode Display |
|-------|-------------------|
| 120 | Full with shortcuts hint + context |
| 60 | Mode with cycle + context (this) |
| 44 | Mode with cycle only |
| 26 | "Plan mode" only |

### Improvement Suggestions:

1. **Mode-Specific Width Thresholds**
   ```rust
   fn min_width_for_mode(mode: CollaborationModeIndicator) -> u16 {
       match mode {
           Plan => 32,
           PairProgramming => 44,  // Longer text
           Execute => 33,
       }
   }
   ```

2. **Abbreviated Mode Names**
   ```rust
   fn abbreviated_label(mode: CollaborationModeIndicator) -> &'static str {
       match mode {
           Plan => "PLAN",
           PairProgramming => "PAIR",
           Execute => "EXEC",
       }
   }
   // At narrow widths: "PLAN (shift+tab)" instead of full name
   ```

3. **Smart Cycle Hint**
   ```rust
   // Only show cycle hint if user hasn't switched modes recently
   if show_cycle_hint && !user_has_switched_modes {
       include_cycle_hint();
   }
   ```

4. **Tooltip on Hover** (if terminal supports mouse)
   ```rust
   // When mouse support available
   if mouse_over_mode_indicator {
       show_tooltip("Click or press shift+tab to change mode");
   }
   ```

5. **Consistent Minimum Width**
   ```rust
   // Ensure all modes fit at the same width
   const MIN_MODE_WIDTH: u16 = 44;  // Based on longest mode name
   ```

### Testing Gaps:

1. No test for `PairProgramming` mode collapse
2. No test for `Execute` mode collapse
3. No test for mode switching at boundary widths
4. No test for context window percentage display with mode

---

**Snapshot Generated**: From `chat_composer.rs` test `footer_collapse_snapshots()`  
**Snapshot Name**: `footer_collapse_plan_empty_mode_cycle_with_context`  
**Terminal Dimensions**: 60 columns × 9 rows  
**Visual Output**: `"  Plan mode (shift+tab to cycle)         100% context left  "`  
**Note**: "Plan mode" appears in magenta color
