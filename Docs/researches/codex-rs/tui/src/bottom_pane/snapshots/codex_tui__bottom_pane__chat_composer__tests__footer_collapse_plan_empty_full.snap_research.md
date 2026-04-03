# Footer Collapse Plan Empty Full Mode - Research Document

## 场景与职责 (Scenario and Responsibility)

This snapshot captures the **footer in full width mode with Plan collaboration mode active** (120 columns). It demonstrates how the footer displays both the shortcuts hint and the active collaboration mode indicator with its cycle hint when sufficient space is available.

**Test Scenario:**
- Terminal width: 120 columns (wide terminal)
- Composer state: Empty (no text input)
- Collaboration mode: **Plan** (via `CollaborationModeIndicator::Plan`)
- Context window: 100% available
- Agent state: Idle (no task running)

**Key Visual Elements:**
- Left: "? for shortcuts" + separator (" · ") + "Plan mode (shift+tab to cycle)"
- Right: "100% context left"
- The "Plan mode" text is styled in **magenta** to distinguish it visually

## 功能点目的 (Purpose of Footer Collapse Functionality)

This snapshot demonstrates the **collaboration mode integration** in the footer:

1. **Mode Awareness**: Users can see which collaboration mode is active
2. **Mode Switching Discovery**: The "(shift+tab to cycle)" hint teaches users how to switch modes
3. **Visual Distinction**: Different modes have different colors (Plan = magenta)

**Available Collaboration Modes** (`footer.rs` lines 90-96):
```rust
pub(crate) enum CollaborationModeIndicator {
    Plan,              // Magenta
    PairProgramming,   // Cyan (currently unused)
    Execute,           // Dim (currently unused)
}
```

**Color Coding Purpose:**
- **Magenta (Plan)**: Suggests thoughtful, deliberate action
- **Cyan (Pair Programming)**: Suggests collaboration (not currently shown)
- **Dim (Execute)**: Suggests automated/background operation (not currently shown)

## 具体技术实现 (Key Implementation Details)

### Collaboration Mode Label (`footer.rs` lines 101-125)

```rust
impl CollaborationModeIndicator {
    fn label(self, show_cycle_hint: bool) -> String {
        let suffix = if show_cycle_hint {
            format!(" ({MODE_CYCLE_HINT})")  // " (shift+tab to cycle)"
        } else {
            String::new()
        };
        match self {
            CollaborationModeIndicator::Plan => format!("Plan mode{suffix}"),
            CollaborationModeIndicator::PairProgramming => {
                format!("Pair Programming mode{suffix}")
            }
            CollaborationModeIndicator::Execute => format!("Execute mode{suffix}"),
        }
    }

    fn styled_span(self, show_cycle_hint: bool) -> Span<'static> {
        let label = self.label(show_cycle_hint);
        match self {
            CollaborationModeIndicator::Plan => Span::from(label).magenta(),
            CollaborationModeIndicator::PairProgramming => Span::from(label).cyan(),
            CollaborationModeIndicator::Execute => Span::from(label).dim(),
        }
    }
}
```

### Left Side Line with Mode (`footer.rs` lines 271-300)

```rust
fn left_side_line(
    collaboration_mode_indicator: Option<CollaborationModeIndicator>,
    state: LeftSideState,
) -> Line<'static> {
    let mut line = Line::from("");
    
    // Add hint first
    match state.hint {
        SummaryHintKind::None => {}
        SummaryHintKind::Shortcuts => {
            line.push_span(key_hint::plain(KeyCode::Char('?')));
            line.push_span(" for shortcuts".dim());
        }
        // ... other variants
    };

    // Add mode indicator with separator
    if let Some(collaboration_mode_indicator) = collaboration_mode_indicator {
        if !matches!(state.hint, SummaryHintKind::None) {
            line.push_span(" · ".dim());  // Separator
        }
        line.push_span(collaboration_mode_indicator.styled_span(state.show_cycle_hint));
    }

    line
}
```

### Test Setup (`chat_composer.rs` lines 4790-4797)

```rust
snapshot_composer_state_with_width(
    "footer_collapse_plan_empty_full",
    120,
    true,
    |composer| {
        setup_collab_footer(composer, 100, Some(CollaborationModeIndicator::Plan));
    },
);
```

### Setup Helper (`chat_composer.rs` lines 4750-4758)

```rust
fn setup_collab_footer(
    composer: &mut ChatComposer,
    context_percent: i64,
    indicator: Option<CollaborationModeIndicator>,
) {
    composer.set_collaboration_modes_enabled(true);  // Enable modes
    composer.set_collaboration_mode_indicator(indicator);  // Set specific mode
    composer.set_context_window(Some(context_percent), None);
}
```

## 关键代码路径与文件引用 (File Paths and Line References)

### Mode Indicator System:

| Component | File | Lines | Purpose |
|-----------|------|-------|---------|
| `CollaborationModeIndicator` enum | `footer.rs` | 90-96 | Defines available modes |
| `label()` method | `footer.rs` | 102-115 | Generates mode text with optional cycle hint |
| `styled_span()` method | `footer.rs` | 117-125 | Applies color styling |
| `MODE_CYCLE_HINT` constant | `footer.rs` | 98 | "shift+tab to cycle" |

### Integration Points:

| Function | File | Lines | Description |
|----------|------|-------|-------------|
| `left_side_line` | `footer.rs` | 271-300 | Combines hint + mode + styling |
| `footer_from_props_lines` | `footer.rs` | 580-631 | Routes to appropriate line builder |
| `single_line_footer_layout` | `footer.rs` | 310-472 | Handles collapse with mode indicator |
| `mode_indicator_line` | `footer.rs` | 474-479 | Standalone mode line builder |

### Composer Integration:

| Function | File | Lines | Description |
|----------|------|-------|-------------|
| `set_collaboration_modes_enabled` | `chat_composer.rs` | 592-594 | Feature flag setter |
| `set_collaboration_mode_indicator` | `chat_composer.rs` | 604-608 | Mode indicator setter |
| `collaboration_mode_indicator` field | `chat_composer.rs` | 404 | State storage |
| `footer_props` | `chat_composer.rs` | 3179-3206 | Includes mode in props |

## 依赖与外部交互 (Dependencies)

### Color/Styling Dependencies:

1. **ratatui::style::Stylize trait**
   - `.magenta()` - Applied to Plan mode
   - `.cyan()` - Available for Pair Programming mode
   - `.dim()` - Applied to Execute mode and separators
   - Chainable: `Span::from(label).magenta()`

2. **ratatui::text::Span**
   - `Span::from()` - Creates span from string
   - Style applied via trait methods

### Key Binding Dependencies:

1. **key_hint module**
   - `plain(KeyCode::Char('?'))` - Renders "?" key visually
   - Used for shortcuts hint

### Mode Switching Dependencies:

```rust
// From footer.rs - the mode cycle hint
const MODE_CYCLE_HINT: &str = "shift+tab to cycle";
```

This hint is shown when:
- `show_cycle_hint` is true (idle state, not running)
- Sufficient width available

## 风险、边界与改进建议 (Risks and Improvements)

### Specific Risks:

1. **Color Accessibility**
   - Magenta may be hard to see on certain terminal color schemes
   - No fallback for colorblind users
   - **Risk**: Users may miss the mode indicator entirely

2. **Mode Discovery**
   - "shift+tab to cycle" only shown when width >= 60
   - Users on narrow terminals won't learn about mode switching
   - **Mitigation**: Include in shortcut overlay (`?`)

3. **Unused Modes**
   - `PairProgramming` and `Execute` are marked `#[allow(dead_code)]`
   - Code maintained but never exercised in production
   - **Risk**: Bit rot in unused code paths

### Boundary Analysis:

| Width | Plan Mode Display |
|-------|-------------------|
| 120 | Full: "? for shortcuts · Plan mode (shift+tab to cycle)" + context |
| 60 | "Plan mode (shift+tab to cycle)" + context |
| 44 | "Plan mode (shift+tab to cycle)" only |
| 26 | "Plan mode" only (no cycle hint) |

### Improvement Suggestions:

1. **Accessibility Enhancements**
   ```rust
   // Add text indicator alongside color
   CollaborationModeIndicator::Plan => {
       Span::from(format!("[PLAN] {label}")).magenta()
   }
   ```

2. **Configurable Colors**
   ```rust
   // Allow users to customize mode colors
   pub struct ModeColors {
       pub plan: Color,
       pub pair_programming: Color,
       pub execute: Color,
   }
   ```

3. **Icon/Emoji Support**
   ```rust
   // Visual indicator beyond color
   match self {
       Plan => Span::from("📋 "),  // Clipboard for planning
       PairProgramming => Span::from("👥 "),  // People for pairing
       Execute => Span::from("⚡ "),  // Bolt for execution
   }
   ```

4. **Mode-Specific Hints**
   ```rust
   // Different hints for different modes
   fn mode_specific_hint(mode: CollaborationModeIndicator) -> &'static str {
       match mode {
           Plan => "Planning mode: review before executing",
           PairProgramming => "Pair mode: collaborative editing",
           Execute => "Execute mode: automatic execution",
       }
   }
   ```

5. **Persistent Mode Indicator**
   ```rust
   // Always show mode, even in narrow terminals
   // Truncate other content first
   if width < 30 {
       // Show just "PLAN" in magenta, drop everything else
       return (SummaryLeft::Custom(Line::from("PLAN".magenta())), false);
   }
   ```

### Testing Gaps:

1. No test for color output verification (would need VT100 backend)
2. No test for mode switching interaction
3. No test for all three modes (only Plan is tested)
4. No test for mode indicator with queue hint

---

**Snapshot Generated**: From `chat_composer.rs` test `footer_collapse_snapshots()`  
**Snapshot Name**: `footer_collapse_plan_empty_full`  
**Terminal Dimensions**: 120 columns × 9 rows  
**Visual Output**: `"  ? for shortcuts · Plan mode (shift+tab to cycle)                   100% context left  "`  
**Note**: The "Plan mode" text appears in magenta color (not visible in plain text snapshot)
