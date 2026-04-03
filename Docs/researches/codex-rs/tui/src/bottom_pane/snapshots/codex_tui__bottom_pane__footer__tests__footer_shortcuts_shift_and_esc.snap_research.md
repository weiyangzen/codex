# Research: footer_shortcuts_shift_and_esc

## 1. Feature Overview

This snapshot tests the shortcut overlay with two specific feature flags enabled: `use_shift_enter_hint: true` and `esc_backtrack_hint: true`. These flags change how certain shortcuts are displayed in the help overlay. When `use_shift_enter_hint` is true, the newline shortcut shows "shift + enter for newline" instead of "ctrl + j for newline". When `esc_backtrack_hint` is true, the edit previous message shortcut shows "esc again to edit previous message" instead of "esc esc to edit previous message". This test verifies the overlay adapts its content based on these state flags.

## 2. Code Structure

### Test Function
- **File**: `codex-rs/tui/src/bottom_pane/footer.rs`
- **Test**: `footer_snapshots()` (lines 1259-1667)
- **Specific test case**: Lines 1279-1295

```rust
snapshot_footer(
    "footer_shortcuts_shift_and_esc",
    FooterProps {
        mode: FooterMode::ShortcutOverlay,
        esc_backtrack_hint: true,      // Changes Esc hint display
        use_shift_enter_hint: true,    // Changes newline shortcut display
        is_task_running: false,
        collaboration_modes_enabled: false,
        is_wsl: false,
        quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),
        context_window_percent: None,
        context_window_used_tokens: None,
        status_line_value: None,
        status_line_enabled: false,
        active_agent_label: None,
    },
);
```

### Key Components

1. **`SHORTCUTS` array** (lines 943-1057): Defines shortcuts with conditional bindings
   - `InsertNewline` (lines 962-976): Has two bindings with conditions
   - `EditPrevious` (lines 1021-1029): Special handling in `overlay_entry()`

2. **`DisplayCondition` enum** (lines 889-896): Controls when shortcuts appear
   - `WhenShiftEnterHint` (line 892)
   - `WhenNotShiftEnterHint` (line 893)

3. **`ShortcutDescriptor::overlay_entry()`** (lines 922-940): Builds shortcut lines with special handling for `EditPrevious`

## 3. Behavior Analysis

### Input Parameters
- **FooterMode**: `ShortcutOverlay`
- **esc_backtrack_hint**: `true`
- **use_shift_enter_hint**: `true`
- **is_wsl**: `false`
- **collaboration_modes_enabled**: `false`

### Conditional Shortcut Bindings

#### Newline Shortcut (lines 962-976)
```rust
ShortcutDescriptor {
    id: ShortcutId::InsertNewline,
    bindings: &[
        ShortcutBinding {
            key: key_hint::shift(KeyCode::Enter),
            condition: DisplayCondition::WhenShiftEnterHint,  // Used when true
        },
        ShortcutBinding {
            key: key_hint::ctrl(KeyCode::Char('j')),
            condition: DisplayCondition::WhenNotShiftEnterHint,  // Used when false
        },
    ],
    prefix: "",
    label: " for newline",
}
```

With `use_shift_enter_hint: true`, the first binding matches → "shift + enter for newline"

#### Edit Previous Shortcut (lines 1021-1029, 926-936)
```rust
ShortcutId::EditPrevious => {
    if state.esc_backtrack_hint {
        line.push_span(" again to edit previous message");  // "esc again..."
    } else {
        line.extend(vec![
            " ".into(),
            key_hint::plain(KeyCode::Esc).into(),
            " to edit previous message".into(),  // "esc esc..."
        ]);
    }
}
```

With `esc_backtrack_hint: true`, shows "esc again to edit previous message"

### Output Comparison

| Flag | `footer_shortcuts_default` | `footer_shortcuts_shift_and_esc` |
|------|---------------------------|----------------------------------|
| Newline | `ctrl + j for newline` | `shift + enter for newline` |
| Edit Prev | `esc esc to edit...` | `esc again to edit...` |

### Full Output
```
"  / for commands                             ! for shell commands               "
"  shift + enter for newline                  tab to queue message               "
"  @ for file paths                           ctrl + v to paste images           "
"  ctrl + g to edit in external editor        esc again to edit previous message "
"  ctrl + c to exit                                                              "
"  ctrl + t to view transcript                                                   "
```

## 4. Layout Differences

Notice the layout changes between default and this test:

**Default** (`footer_shortcuts_default`):
- 6 rows with "ctrl + t to view transcript" on row 6 (right column)

**This test**:
- 6 rows but different distribution
- Row 5: Only "ctrl + c to exit" (left column)
- Row 6: Only "ctrl + t to view transcript" (left column)

This happens because:
1. "shift + enter for newline" is longer than "ctrl + j for newline"
2. Column width calculations change based on content length
3. `build_columns()` redistributes items to balance column widths

## 5. Test Coverage

### What This Test Verifies
1. Shortcut overlay adapts to `use_shift_enter_hint` flag
2. Shortcut overlay adapts to `esc_backtrack_hint` flag
3. Column layout dynamically adjusts to content width
4. All shortcuts remain visible with alternative text

### State Transitions
These flags typically change based on user interaction:
- `esc_backtrack_hint: true`: User has pressed Esc once, pressing again will edit
- `use_shift_enter_hint: true`: Terminal supports Shift+Enter for newlines

## 6. Related Tests

- `footer_shortcuts_default`: Default shortcuts without special flags
- `footer_shortcuts_collaboration_modes_enabled`: With collaboration modes
- `footer_esc_hint_idle` / `footer_esc_hint_primed`: Esc hint behavior in footer
