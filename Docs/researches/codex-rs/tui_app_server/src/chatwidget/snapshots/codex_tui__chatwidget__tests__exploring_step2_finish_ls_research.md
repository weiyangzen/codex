# Research: Exploring Step 2 - Finish LS

## 1. 场景与职责 (Scene and Responsibility)

This snapshot captures the **completion state of the first exploration command** (`ls -la`). The command has finished executing, and the exploring group has transitioned from "Exploring" (active) to "Explored" (completed).

**Scene Context:**
- The `ls -la` command has completed execution
- The exploring group remains open but now shows completion status
- The UI reflects that the exploration phase is done but the group may still be extended
- This is part of a multi-step exploration sequence

**Responsibilities:**
- Indicate command completion while maintaining group context
- Preserve the command history within the exploration group
- Prepare the UI for potential additional exploration commands

## 2. 功能点目的 (Functional Purpose)

The explored state rendering serves to:

1. **Completion Signaling**: Clearly indicate that the exploration command has finished
2. **Group Continuity**: Maintain the exploration group for potential additional commands
3. **Visual Feedback**: Change from active (•) to completed (•) with status text change
4. **History Integration**: Ensure completed explorations are properly tracked

**Key Behavior:**
- Header changes from "Exploring" to "Explored" when all commands in group complete
- The group remains "active" in the active_cell until a new unrelated command starts
- Subsequent related commands will extend this group rather than creating new history entries

## 3. 具体技术实现 (Technical Implementation)

### Key Data Structures

```rust
// From codex_protocol::protocol
pub struct ExecCommandEndEvent {
    pub id: String,
    pub output: String,
    pub exit_code: i32,
}

// Internal tracking
pub struct ExecBeginHandle {
    pub call_id: String,
    pub proc_id: Option<String>,
}
```

### Rendering Format

```
• Explored
  └ List ls -la
```

**Visual Elements:**
- `•`: Bullet point (same as active, but header text indicates completion)
- `Explored`: Group header indicating completed exploration
- `└`: Tree connector
- `List ls -la`: Completed command description

**Comparison with Step 1:**
| Aspect | Step 1 (Start) | Step 2 (Finish) |
|--------|---------------|-----------------|
| Header | "Exploring" | "Explored" |
| State | Active/running | Completed |
| Visual | Same bullet | Same bullet |

### Key Processes

1. **Command Completion** (from test):
```rust
// 2) Finish "ls -la"
end_exec(&mut chat, begin_ls, "", "", 0);
assert_snapshot!("exploring_step2_finish_ls", active_blob(&chat));
```

2. **End Event Handling**:
```rust
fn end_exec(
    chat: &mut ChatWidget,
    handle: ExecBeginHandle,
    stdout: &str,
    stderr: &str,
    exit_code: i32,
) {
    // Sends ExecCommandEndEvent
    // Updates active_cell state from Exploring to Explored
}
```

3. **State Transition**:
```rust
// When all commands in group complete:
// - Header changes: "Exploring" → "Explored"
// - Group remains in active_cell for potential extension
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files

| File | Description |
|------|-------------|
| `codex-rs/tui/src/chatwidget/tests.rs` | Test `exec_history_extends_previous_when_consecutive` (line ~8199) |
| `codex-rs/tui/src/chatwidget/mod.rs` | ChatWidget event handling |
| `codex-rs/tui/src/history_cell.rs` | HistoryCell state management |

### Key Functions

```rust
// Test helper - ends an exec command
fn end_exec(
    chat: &mut ChatWidget,
    handle: ExecBeginHandle,
    stdout: &str,
    stderr: &str,
    exit_code: i32,
)

// Gets active cell content
fn active_blob(chat: &ChatWidget) -> String  // tests.rs:3652
```

### Protocol Events

```rust
Event {
    id: "call-ls",
    msg: EventMsg::ExecCommandEnd(ExecCommandEndEvent {
        id: "call-ls",
        output: "",
        exit_code: 0,
    }),
}
```

### Related Snapshots
- `exploring_step1_start_ls.snap` - Initial state
- `exploring_step2_finish_ls.snap` - This file (after ls completes)
- `exploring_step3_start_cat_foo.snap` - Adding second command

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Internal Dependencies

- `ExecBeginHandle`: Tracks the association between begin and end events
- `ChatWidget::active_cell`: Holds the current exploration group state
- `ExecCommandEndEvent`: Protocol event signaling command completion

### State Machine

```
Exploring (has running commands)
    ↓ (last command ends)
Explored (no running commands, group still active)
    ↓ (new exploring command starts)
Exploring (extended with new command)
    ↓ (unrelated command or flush)
History (group flushed to permanent history)
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks

1. **State Desync**: If end events arrive without matching begin events, tracking fails
2. **Premature Flushing**: Group might flush to history before user sees the "Explored" state
3. **Empty Output**: Commands with no output (like this ls) may confuse users about completion

### Edge Cases

1. **Failed Commands**: Commands with non-zero exit codes should still transition to "Explored"
2. **Partial Output**: Commands that produce output before failing
3. **Orphaned End Events**: End events without matching begin events
4. **Rapid Start/End**: Commands that complete instantly may skip the "Exploring" state

### Improvement Suggestions

1. **Exit Code Indicator**: Show ✓ or ✗ next to commands based on exit code
2. **Output Preview**: Show first N lines of output even in exploring view
3. **Time Tracking**: Display duration from start to finish
4. **Expand on Complete**: Auto-expand group when exploration completes to show full output
5. **Visual Distinction**: Use different colors/icons for "Exploring" vs "Explored"
6. **Output Persistence**: Option to view full command output after group flushes to history
