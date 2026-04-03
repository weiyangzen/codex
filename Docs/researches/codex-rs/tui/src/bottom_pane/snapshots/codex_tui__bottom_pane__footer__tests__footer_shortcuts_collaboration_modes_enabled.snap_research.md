# Research: footer_shortcuts_collaboration_modes_enabled

## 1. Feature Overview

This snapshot tests the shortcut overlay (help screen) when collaboration modes are enabled. The shortcut overlay is a multi-line display that appears when the user presses `?`, showing all available keyboard shortcuts. When `collaboration_modes_enabled` is `true`, an additional shortcut entry appears: "shift + tab to change mode". This test verifies that the overlay correctly includes the mode change shortcut when the feature is enabled.

## 2. Code Structure

### Test Function
- **File**: `codex-rs/tui/src/bottom_pane/footer.rs`
- **Test**: `footer_snapshots()` (lines 1259-1667)
- **Specific test case**: Lines 1297-1313

```rust
snapshot_footer(
    "footer_shortcuts_collaboration_modes_enabled",
    FooterProps {
        mode: FooterMode::ShortcutOverlay,  // Show shortcut overlay
        esc_backtrack_hint: false,
        use_shift_enter_hint: false,
        is_task_running: false,
        collaboration_modes_enabled: true,  // Enable collaboration modes
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

1. **`shortcut_overlay_lines()`** (lines 750-799): Builds the shortcut overlay content
   - Iterates through `SHORTCUTS` array
   - Calls `overlay_entry()` for each shortcut
   - Organizes into two columns via `build_columns()`

2. **`ShortcutDescriptor::overlay_entry()`** (lines 922-940): Creates individual shortcut lines

3. **`SHORTCUTS` array** (lines 943-1057): Defines all available shortcuts
   - `ChangeMode` entry at lines 1048-1056 with `WhenCollaborationModesEnabled` condition

## 3. Behavior Analysis

### Input Parameters
- **FooterMode**: `ShortcutOverlay` - triggers multi-line overlay display
- **collaboration_modes_enabled**: `true` - enables mode change shortcut
- **use_shift_enter_hint**: `false` - shows "ctrl + j for newline" instead
- **esc_backtrack_hint**: `false` - shows "esc esc to edit previous message"

### Shortcut Display Logic

In `SHORTCUTS` array (lines 1048-1056):
```rust
ShortcutDescriptor {
    id: ShortcutId::ChangeMode,
    bindings: &[ShortcutBinding {
        key: key_hint::shift(KeyCode::Tab),
        condition: DisplayCondition::WhenCollaborationModesEnabled,
    }],
    prefix: "",
    label: " to change mode",
}
```

The `WhenCollaborationModesEnabled` condition (line 905) checks:
```rust
DisplayCondition::WhenCollaborationModesEnabled => state.collaboration_modes_enabled,
```

### Rendering Flow

1. **`footer_from_props_lines()`** (lines 580-631):
   - Matches `FooterMode::ShortcutOverlay`
   - Calls `shortcut_overlay_lines(state)`

2. **`shortcut_overlay_lines()`** (lines 750-799):
   - Creates `ShortcutsState` from props
   - Iterates through all `ShortcutDescriptor`s
   - Only includes shortcuts where `binding_for(state)` returns Some

3. **`build_columns()`** (lines 801-846):
   - Arranges shortcuts into 2 columns
   - Adds padding between columns
   - Applies dim styling to all lines

### Output
```
"  / for commands                             ! for shell commands               "
"  ctrl + j for newline                       tab to queue message               "
"  @ for file paths                           ctrl + v to paste images           "
"  ctrl + g to edit in external editor        esc esc to edit previous message   "
"  ctrl + c to exit                           shift + tab to change mode         "
"                                             ctrl + t to view transcript        "
```

## 4. Column Layout

### Column 1 (left)
- `/ for commands`
- `ctrl + j for newline`
- `@ for file paths`
- `ctrl + g to edit in external editor`
- `ctrl + c to exit`
- (empty)

### Column 2 (right)
- `! for shell commands`
- `tab to queue message`
- `ctrl + v to paste images`
- `esc esc to edit previous message`
- `shift + tab to change mode` ← Only when collaboration_modes_enabled
- `ctrl + t to view transcript`

## 5. Test Coverage

### What This Test Verifies
1. Shortcut overlay displays in 2-column format
2. "shift + tab to change mode" appears when collaboration modes are enabled
3. Proper key hint styling (bold keys, dim labels)
4. All standard shortcuts are present

### Comparison: Collaboration Modes Disabled
When `collaboration_modes_enabled: false` (see `footer_shortcuts_default` and `footer_shortcuts_shift_and_esc`):
- The "shift + tab to change mode" line is omitted
- Layout adjusts accordingly

## 6. Related Tests

- `footer_shortcuts_default`: Basic overlay without collaboration modes
- `footer_shortcuts_shift_and_esc`: Overlay with `use_shift_enter_hint: true` and `esc_backtrack_hint: true`
- `footer_mode_indicator_wide`: Shows mode indicator in single-line footer
