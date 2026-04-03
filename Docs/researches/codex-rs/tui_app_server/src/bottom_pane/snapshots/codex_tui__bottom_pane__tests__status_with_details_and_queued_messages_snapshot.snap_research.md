# Bottom Pane - Status with Details and Queued Messages Snapshot Research

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot captures the most complex bottom pane layout scenario where:
- A task is actively running with detailed status information
- Multiple detail lines are displayed below the status header
- The user has queued follow-up messages
- All major bottom pane components are visible simultaneously

This represents a **full-featured active state** during complex multi-turn interactions. The UI must effectively communicate:
- Current operation status with details
- Detailed progress or context information
- User's pending input queue
- Available actions and shortcuts

## 2. 功能点目的 (Feature Purpose)

The test validates the comprehensive layout showing:

- **Status with header and details**: Multi-line status display
- **Detail line formatting**: Tree-style indentation (└, spaces)
- **Queued messages integration**: Queue visible alongside detailed status
- **Visual hierarchy**: Clear separation between status, details, queue, and composer
- **Context preservation**: Footer hints and context info remain visible

This ensures the UI remains usable and informative even with maximum content density.

## 3. 具体技术实现 (Technical Implementation)

### Status with Details
```rust
pub(crate) fn update_status(
    &mut self,
    header: String,                    // "Working"
    details: Option<String>,          // "First detail line\nSecond detail line"
    details_capitalization: StatusDetailsCapitalization,
    details_max_lines: usize,
) {
    if let Some(status) = self.status.as_mut() {
        status.update_header(header);
        status.update_details(details, details_capitalization, details_max_lines.max(1));
    }
}
```

### Detail Formatting
The `StatusIndicatorWidget` formats details with:
- **First line**: `└ ` prefix (tree corner)
- **Subsequent lines**: `  ` prefix (indentation)
- **Capitalization**: `CapitalizeFirst` or `AsIs`

```rust
// Example output:
// • Working (0s • esc to interrupt)
//   └ First detail line
//     Second detail line
```

### Complete Layout Stack
```
┌─────────────────────────────────────────────┐
│ • Working (0s • esc to interrupt)           │ ← Status header
│   └ First detail line                       │ ← Detail line 1
│     Second detail line                      │ ← Detail line 2
│                                             │ ← Spacer
│ • Queued follow-up messages                 │ ← Queue header
│   ↳ Queued follow-up question               │ ← Queue item
│     ⌥ + ↑ edit last queued message          │ ← Edit hint
│                                             │ ← Spacer
│ › Ask Codex to do anything                  │ ← Composer
│                                             │ ← Composer spacer
│   ? for shortcuts      100% context left    │ ← Footer
└─────────────────────────────────────────────┘
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Source File
- `/codex-rs/tui_app_server/src/bottom_pane/mod.rs` (lines 1-1967)

### Key Functions
| Function | Line | Purpose |
|----------|------|---------|
| `update_status()` | 635-647 | Updates header and details |
| `set_pending_input_preview()` | 815-823 | Sets queued messages |
| `as_renderable()` | 1123-1167 | Builds complete layout |

### Test Function
- `status_with_details_and_queued_messages_snapshot()` at lines 1523-1553

### Test Setup
```rust
pane.set_task_running(true);
pane.update_status(
    "Working".to_string(),
    Some("First detail line\nSecond detail line".to_string()),
    StatusDetailsCapitalization::CapitalizeFirst,
    STATUS_DETAILS_DEFAULT_MAX_LINES,  // Typically 3
);
pane.set_pending_input_preview(
    vec!["Queued follow-up question".to_string()],
    Vec::new()
);
```

### Related Components
- `StatusIndicatorWidget` - Status with details rendering
- `PendingInputPreview` - Queued messages
- `StatusDetailsCapitalization` - Detail text formatting

### Constants
```rust
// From status_indicator_widget.rs
pub const STATUS_DETAILS_DEFAULT_MAX_LINES: usize = 3;
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Data Sources for Details
Status details typically come from:
- **Tool execution**: Command being run, file being edited
- **API progress**: Streaming response indicators
- **File operations**: Paths and operation types
- **Network requests**: Endpoints and status

Example detail sources:
```rust
// File edit in progress
"editing src/main.rs"

// Command execution
"running: cargo build"

// Multi-step operation
"Step 1 of 3: Analyzing codebase"
```

### Layout Interactions
When both details and queue are present:
1. Status header + details render first
2. Spacer line for separation
3. Queue section renders below
4. Another spacer
5. Composer at bottom

### Visual Hierarchy
```
Priority (top to bottom):
1. Status header (most important - system state)
2. Status details (context for status)
3. Queue section (user's pending input)
4. Composer (input interface)
5. Footer (auxiliary info)
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Potential Risks

1. **Vertical Space Exhaustion**: Details + queue may push composer off-screen
   - Current: `STATUS_DETAILS_DEFAULT_MAX_LINES` limits details
   - Risk: Small terminals still overflow

2. **Detail Truncation**: Important info may be cut
   - Current: Max lines limit with no scroll
   - Risk: Critical context lost

3. **Visual Clutter**: Too many elements reduce readability
   - Current: Spacers help separate sections
   - Risk: Information overload

### Edge Cases Handled

1. **Empty details**: Renders without detail lines
2. **Single detail**: Only one indented line
3. **Multi-line details**: Up to max_lines displayed
4. **Long detail lines**: Truncated with ellipsis
5. **Details with newlines**: Split and formatted individually

### Improvement Suggestions

1. **Scrollable Details**: Allow scrolling when details exceed max_lines
   ```
   • Working
     └ Line 1
       Line 2
       Line 3... (↓ 2 more)
   ```

2. **Collapsible Details**: Toggle detail visibility
   - Shortcut to expand/collapse
   - Remember user preference

3. **Detail Categories**: Color-code different detail types
   - Commands: Blue
   - File operations: Green
   - Warnings: Yellow
   - Errors: Red

4. **Smart Truncation**: Preserve most important part of detail
   - Current: End truncation
   - Improvement: Middle truncation for paths
   ```
   "editing .../src/main.rs"  // instead of "editing /very/long/path...
   ```

5. **Detail History**: Show last N status messages
   - Current: Only current status
   - Improvement: Brief history of recent operations

6. **Queue Integration**: Show queue count in status
   ```
   • Working (2 messages queued)
   ```

7. **Responsive Detail Limit**: Adjust max_lines based on terminal height
   ```rust
   let max_lines = if height > 10 { 3 } else { 1 };
   ```

### Testing Coverage
- Status with details and queue (this snapshot)
- Status with details only
- Status with queue only

Consider adding tests for:
- Maximum detail lines (3+)
- Very long individual detail lines
- Details with special characters
- Unicode in details
- Rapid status updates

### Related Snapshots
- `status_only_snapshot` - Minimal status
- `status_and_queued_messages_snapshot` - Status + queue, no details
- `queued_messages_visible_when_status_hidden_snapshot` - Queue without status
