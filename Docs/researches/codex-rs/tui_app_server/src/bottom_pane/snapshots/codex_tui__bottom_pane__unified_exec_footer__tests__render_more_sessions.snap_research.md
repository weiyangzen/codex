# Unified Exec Footer - Render More Sessions (Single Session) Snapshot Research

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot captures the `UnifiedExecFooter` component when there is **exactly one background terminal session** running. This represents the minimal active state of the unified exec system where:

- A single background process is executing (e.g., `rg "foo" src`)
- The user needs awareness of this background activity
- The footer provides guidance on how to view or stop the process
- Space is limited (50 characters width)

This is the most common unified exec scenario - typically users have 1-3 background terminals running at any given time during active development work.

## 2. 功能点目的 (Feature Purpose)

The test validates:

- **Singular form handling**: Correctly uses "terminal" (not "terminals") for single process
- **Complete message visibility**: With only 1 process, the full message fits in 50 chars
- **Visual consistency**: Same dimmed styling as multi-process case
- **Command hints**: Both `/ps` and `/stop` commands are visible
- **Indentation**: Proper 2-space indentation for alignment

The snapshot shows the complete message: "1 background terminal running · /ps to view · /c" (truncated at width limit).

## 3. 具体技术实现 (Technical Implementation)

### Pluralization Logic
```rust
let count = self.processes.len();
let plural = if count == 1 { "" } else { "s" };
Some(format!(
    "{count} background terminal{plural} running · /ps to view · /stop to close"
))
```

### Rendering with Width Constraints
```rust
fn render_lines(&self, width: u16) -> Vec<Line<'static>> {
    if width < 4 {
        return Vec::new();
    }
    let Some(summary) = self.summary_text() else {
        return Vec::new();
    };
    
    // 2-space indentation for visual alignment
    let message = format!("  {summary}");
    
    // Truncate to available width
    let (truncated, _, _) = take_prefix_by_width(&message, width as usize);
    
    // Apply dim styling for non-critical info
    vec![Line::from(truncated.dim())]
}
```

### Buffer Output Format
The snapshot uses `format!("{buf:?}")` which outputs the ratatui `Buffer` debug format:
```
Buffer {
    area: Rect { x: 0, y: 0, width: 50, height: 1 },
    content: [
        "  1 background terminal running · /ps to view · /c",
    ],
    styles: [
        x: 0, y: 0, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
    ]
}
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Source File
- `/codex-rs/tui_app_server/src/bottom_pane/unified_exec_footer.rs` (lines 1-117)

### Key Functions
| Function | Line | Purpose |
|----------|------|---------|
| `summary_text()` | 45-55 | Generates message with correct pluralization |
| `render_lines()` | 57-67 | Handles width constraints and styling |
| `desired_height()` | 79-81 | Returns 1 if processes exist, 0 otherwise |

### Test Function
- `render_more_sessions()` at lines 97-105

### Test Setup
```rust
let mut footer = UnifiedExecFooter::new();
footer.set_processes(vec!["rg \"foo\" src".to_string()]);
let width = 50;
let height = footer.desired_height(width);
let mut buf = Buffer::empty(Rect::new(0, 0, width, height));
footer.render(Rect::new(0, 0, width, height), &mut buf);
assert_snapshot!("render_more_sessions", format!("{buf:?}"));
```

### Related Files
- `/codex-rs/tui_app_server/src/live_wrap.rs` - Text truncation utilities
- `/codex-rs/tui_app_server/src/bottom_pane/mod.rs` - Integration point

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Bottom Pane Integration
The footer appears in the bottom pane layout when:
1. No status indicator is visible (avoids duplication)
2. At least one background process exists

```rust
// From mod.rs as_renderable()
if self.status.is_none() && !self.unified_exec_footer.is_empty() {
    flex.push(
        /*flex*/ 0,
        RenderableItem::Borrowed(&self.unified_exec_footer),
    );
}
```

### State Change Detection
```rust
pub(crate) fn set_processes(&mut self, processes: Vec<String>) -> bool {
    if self.processes == processes {
        return false;  // No change, no redraw needed
    }
    self.processes = processes;
    true  // Redraw required
}
```

### User Commands
The footer references two slash commands:

| Command | Action | When to Use |
|---------|--------|-------------|
| `/ps` | List all background processes | View details, check status |
| `/stop` | Stop/close processes | Clean up, free resources |

### Event Flow
```
User runs command in unified exec → Process spawned →
Process manager updates → set_unified_exec_processes() →
Footer rendered with "1 background terminal running" →
User types /stop → Processes terminated → Footer hidden
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Potential Risks

1. **Width Sensitivity**: At 50 chars, message is truncated
   - Full message: "  1 background terminal running · /ps to view · /stop to close"
   - Visible: "  1 background terminal running · /ps to view · /c"
   - Risk: `/stop` command not fully visible

2. **Command Discovery**: Users may not know what `/ps` and `/stop` do
   - Current: Command names only
   - Risk: New users confused by abbreviations

3. **Stale Information**: Footer may not update immediately on process exit
   - Current: Depends on process manager updates
   - Risk: Brief display of incorrect count

### Edge Cases Handled

1. **Zero processes**: `is_empty()` returns true, nothing rendered
2. **Single process**: Correct singular grammar
3. **Empty strings in list**: Still counted as processes
4. **Rapid changes**: Change detection prevents unnecessary redraws

### Boundary Values

| Process Count | Plural | Example Output |
|---------------|--------|----------------|
| 0 | N/A | (nothing rendered) |
| 1 | "" | "1 background terminal running" |
| 2 | "s" | "2 background terminals running" |
| 123 | "s" | "123 background terminals running" |

### Improvement Suggestions

1. **Tooltip/Expansion**: Hover or keypress to see full command descriptions
   ```
   /ps  → list processes
   /stop → stop all background processes
   ```

2. **Smart Width Allocation**: Use more width when available
   ```rust
   fn render_lines(&self, width: u16) -> Vec<Line<'static>> {
       let message = if width >= 60 {
           format!("  {summary} (use /ps to view, /stop to close)")
       } else {
           format!("  {summary}")
       };
       // ...
   }
   ```

3. **Process Name Display**: For single process, show the command
   ```
   "  rg \"foo\" src running · /ps · /stop"
   ```

4. **Status Indicator**: Different color for active vs. completing
   ```rust
   if all_processes_healthy {
       style.dim()
   } else {
       style.yellow()  // Warning
   }
   ```

5. **Clickable Commands**: Terminal hyperlink escape sequences
   ```
   \e]8;;/ps\e\\/ps\e]8;;\e\\
   ```

6. **Auto-dismiss**: Hide after period of inactivity
   - Fade out when processes idle for N minutes
   - Reappear on new activity

7. **Count Badge**: Show count in status bar instead of separate line
   - Save vertical space
   - Icon with number badge

### Testing Coverage
- Single session (this snapshot)
- Many sessions (123) - `render_many_sessions` snapshot
- Empty footer - `desired_height_empty` test

Consider adding tests for:
- Exactly 2 processes (plural boundary)
- Process with very long command string
- Unicode command names
- Width of exactly message length
- Width of message length - 1

### Related Snapshots
- `render_many_sessions` - Many processes case (123)
- `status_only_snapshot` - When status visible (footer hidden)
