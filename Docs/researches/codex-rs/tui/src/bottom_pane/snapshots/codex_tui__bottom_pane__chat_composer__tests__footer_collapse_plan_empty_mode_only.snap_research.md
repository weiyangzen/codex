# Footer Collapse Plan Empty Mode Only - Research Document

## 场景与职责 (Scenario and Responsibility)

This snapshot captures the **footer at very narrow width with Plan collaboration mode active** (26 columns), showing the minimum viable display where only the mode name is shown without the cycle hint. This represents the absolute minimum information needed to convey the active collaboration mode.

**Test Scenario:**
- Terminal width: 26 columns (very narrow terminal)
- Composer state: Empty (no text input)
- Collaboration mode: **Plan** (via `CollaborationModeIndicator::Plan`)
- Context window: 100% available (not displayed)
- Agent state: Idle (no task running)

**Key Visual Elements:**
- Left: "Plan mode" (magenta color, 9 characters)
- Right: None
- Cycle hint: Dropped (would be: " (shift+tab to cycle)")

**Design Philosophy:**
This is the **bare minimum mode indication** - users know which mode is active, but not how to change it or their context usage. It's a compromise for extremely constrained terminal environments.

## 功能点目的 (Purpose of Footer Collapse Functionality)

This snapshot represents the **final fallback** in the collapse chain:

**Complete Collapse Progression for Plan Mode:**
```
Width 120: "? for shortcuts · Plan mode (shift+tab to cycle)    100% context left"
Width 60:  "Plan mode (shift+tab to cycle)         100% context left"
Width 44:  "Plan mode (shift+tab to cycle)"
Width 26:  "Plan mode"
                ↑
            Minimum viable: mode name only
```

**Why Mode Name is Preserved Last:**
1. **Critical information** - Users must know the active mode
2. **Short text** - "Plan mode" is only 9 characters
3. **Color-coded** - Even without text, color indicates mode
4. **Foundation for expansion** - If width increases, more info is added

## 具体技术实现 (Key Implementation Details)

### Final Fallback Logic (`footer.rs` lines 413-436)

```rust
// Next fallback: mode label only. If the cycle hint is applicable but
// cannot fit, we also suppress context so the right side does not
// outlive "(shift+tab to cycle)" on the left.
let mode_only_state = LeftSideState {
    hint: SummaryHintKind::None,
    show_cycle_hint: false,  // Drop cycle hint
};
let mode_only_width = state_width(mode_only_state);

// Try with context first (if cycle hint wasn't required)
if !context_requires_cycle_hint
    && mode_only_width > 0
    && can_show_left_with_context(area, mode_only_width, context_width)
{
    return (
        SummaryLeft::Custom(state_line(mode_only_state)),
        true, // show_context
    );
}

// Without context
if mode_only_width > 0 && left_fits(area, mode_only_width) {
    return (
        SummaryLeft::Custom(state_line(mode_only_state)),
        false, // show_context ← This case
    );
}
```

### Mode-Only State Construction (`footer.rs` lines 271-300)

```rust
fn left_side_line(
    collaboration_mode_indicator: Option<CollaborationModeIndicator>,
    state: LeftSideState,
) -> Line<'static> {
    let mut line = Line::from("");
    
    // No hint (SummaryHintKind::None)
    match state.hint {
        SummaryHintKind::None => {}  // Skip hint entirely
        // ...
    };

    // Add mode indicator (no separator needed since no hint)
    if let Some(collaboration_mode_indicator) = collaboration_mode_indicator {
        // No separator check needed - no hint present
        line.push_span(collaboration_mode_indicator.styled_span(state.show_cycle_hint));
        // styled_span with show_cycle_hint=false returns just "Plan mode"
    }

    line
}
```

### Mode Label Generation (`footer.rs` lines 102-115)

```rust
fn label(self, show_cycle_hint: bool) -> String {
    let suffix = if show_cycle_hint {
        format!(" ({MODE_CYCLE_HINT})")  // " (shift+tab to cycle)"
    } else {
        String::new()  // Empty suffix ← This case
    };
    match self {
        CollaborationModeIndicator::Plan => format!("Plan mode{suffix}"),
        // ...
    }
}
```

With `show_cycle_hint=false`: Returns just "Plan mode" (9 chars)
With `show_cycle_hint=true`: Returns "Plan mode (shift+tab to cycle)" (32 chars)

### Width Calculation at 26 Columns

```
Total width: 26
Left indent: 2
Available for content: 26 - 2 = 24

Mode only: "Plan mode" = 9 chars
With indent: 9 + 2 = 11
11 <= 24 ✓ (comfortable fit)

Mode with cycle: "Plan mode (shift+tab to cycle)" = 32 chars
With indent: 32 + 2 = 34
34 > 24 ✗ (doesn't fit)
```

### Test Setup (`chat_composer.rs` lines 4814-4821)

```rust
snapshot_composer_state_with_width(
    "footer_collapse_plan_empty_mode_only",
    26,
    true,
    |composer| {
        setup_collab_footer(composer, 100, Some(CollaborationModeIndicator::Plan));
    },
);
```

## 关键代码路径与文件引用 (File Paths and Line References)

### Collapse Decision Tree:

```
single_line_footer_layout(area=26, mode=Plan)
├── Default state with context? → No
├── Try with cycle hint
│   ├── can_show_left_with_context(32, 17)? → No
│   └── left_fits(32)? → No (34 > 24)
├── Try mode only
│   ├── can_show_left_with_context(9, 17)? → No (12 > 7)
│   └── left_fits(9)? → Yes (11 <= 24) ← This case
│       └── Return (Custom(mode_only_line), false)
└── ...
```

### Key Code Sections:

| Function | File | Lines | Description |
|----------|------|-------|-------------|
| `single_line_footer_layout` | `footer.rs` | 413-435 | Mode-only fallback logic |
| `CollaborationModeIndicator::label` | `footer.rs` | 102-115 | Generates mode text |
| `CollaborationModeIndicator::styled_span` | `footer.rs` | 117-125 | Applies magenta color |
| `left_side_line` | `footer.rs` | 271-300 | Builds mode-only line |
| `left_fits` | `footer.rs` | 252-255 | Width check |

### Constants:

| Constant | Value | Description |
|----------|-------|-------------|
| `MODE_CYCLE_HINT` | "shift+tab to cycle" | 18 characters |
| `FOOTER_INDENT_COLS` | 2 | Left padding |

## 依赖与外部交互 (Dependencies)

### Core Dependencies:

1. **ratatui::text::Span**
   - `Span::from("Plan mode").magenta()` - Styled text
   - Color application via `Stylize` trait

2. **ratatui::text::Line**
   - `Line::from(vec![span])` - Container for styled span
   - `line.width()` - Returns 9 (Unicode-aware)

### Color System:

```rust
// From ratatui::style::Stylize
impl Span {
    fn magenta(self) -> Self {
        self.fg(Color::Magenta)
    }
}
```

The magenta color is critical for mode identification when text is minimal.

## 风险、边界与改进建议 (Risks and Improvements)

### Critical Risks:

1. **Complete Loss of Mode Switching Discovery**
   - Users won't see "(shift+tab to cycle)"
   - May not know how to exit Plan mode
   - **High impact** for users who accidentally enter a mode

2. **Context Blindness**
   - No indication of token usage
   - Users may hit limits unexpectedly
   - **Mitigation**: Show warning dialog when context is critical

3. **Color Dependency**
   - Mode identification relies heavily on magenta color
   - Terminals without color support lose information
   - **Risk**: Monochrome terminals show just "Plan mode" with no context

### Boundary Analysis:

| Width | Display | Notes |
|-------|---------|-------|
| 26 | "Plan mode" | This snapshot - minimum viable |
| 20 | "Plan mode" | Still fits (9 + 2 = 11 <= 18) |
| 12 | "Plan mode" | Barely fits (11 <= 10) - edge case |
| 11 | "Plan mode" | Truncated or overflow |
| < 11 | ? | Undefined behavior |

### Improvement Suggestions:

1. **Abbreviated Mode Indicator**
   ```rust
   fn abbreviated_mode_label(mode: CollaborationModeIndicator) -> &'static str {
       match mode {
           Plan => "P",
           PairProgramming => "PP",
           Execute => "E",
       }
   }
   // At ultra-narrow: "[P]" in magenta
   ```

2. **Persistent Mode Indicator**
   ```rust
   // Always show mode, even if it means hiding everything else
   if area.width < 15 {
       // Show just "[P]" centered or left-aligned
       return (SummaryLeft::Custom(Line::from("[P]".magenta())), false);
   }
   ```

3. **Mode Change Notification**
   ```rust
   // Flash a message when mode changes, even in narrow terminals
   fn on_mode_change(new_mode: CollaborationModeIndicator) {
       show_footer_flash(format!("Switched to {new_mode:?}"), Duration::from_secs(2));
   }
   ```

4. **Fallback to Status Bar**
   ```rust
   // If footer can't show mode, ensure it's visible elsewhere
   if footer_cannot_show_mode() {
       update_window_title(format!("Codex - {mode:?} Mode"));
   }
   ```

5. **Minimum Terminal Width Warning**
   ```rust
   // Warn users when terminal is too narrow
   if area.width < 26 {
       // Show once per session
       show_warning("Terminal too narrow for full UI. Consider resizing.");
   }
   ```

6. **Tooltip/Help System**
   ```rust
   // Press '?' to see mode info even in narrow terminals
   if key == '?' {
       show_modal_dialog(format!(
           "Current Mode: Plan\n"
           "Context: 100% left\n"
           "Press shift+tab to change mode"
       ));
   }
   ```

### Testing Gaps:

1. No test for width < 26
2. No test for colorblind accessibility
3. No test for mode switching at minimum width
4. No test for all three modes at minimum width
5. No test for terminal without color support

### Documentation Needs:

1. Document minimum supported terminal width (currently implicit)
2. Document mode indicator colors and their meanings
3. Document how to switch modes when cycle hint is hidden

---

**Snapshot Generated**: From `chat_composer.rs` test `footer_collapse_snapshots()`  
**Snapshot Name**: `footer_collapse_plan_empty_mode_only`  
**Terminal Dimensions**: 26 columns × 9 rows  
**Visual Output**: `"  Plan mode               "`  
**Note**: 
- "Plan mode" appears in **magenta** color
- This is the minimum viable mode indication
- Cycle hint and context are both hidden
- 13 trailing spaces (26 - 2 - 9 - 2 = 13)
