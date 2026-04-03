# Research: Forked Thread History Line (Without Name)

## 1. 场景与职责 (Scene and Responsibility)

This snapshot captures the **history line displayed when a thread is forked from an unnamed parent thread**. When the parent thread doesn't have a custom name, only the thread ID is displayed.

**Scene Context:**
- A new thread has been created by forking from an existing thread
- The parent thread does NOT have a custom name (unnamed)
- No session index entry exists for the parent thread
- The UI displays only the thread ID as the identifier

**Responsibilities:**
- Display fork lineage even when parent thread has no name
- Avoid showing duplicate information (ID only, no name)
- Maintain consistent formatting with named thread case
- Provide minimal but sufficient context

## 2. 功能点目的 (Functional Purpose)

The unnamed fork history line serves to:

1. **Universal Coverage**: Handle all fork cases, not just named threads
2. **ID Deduplication**: Don't show ID twice when there's no name
3. **Consistent Formatting**: Similar structure to named thread display
4. **Minimal Clutter**: Show only essential information

**Key Difference from Named Case:**
- Named: `Thread forked from {name} ({id})`
- Unnamed: `Thread forked from {id}` (ID shown only once)

## 3. 具体技术实现 (Technical Implementation)

### Key Data Structures

```rust
// From codex_protocol
pub struct ThreadId(String);

// Session index entry (may not exist)
pub struct SessionIndexEntry {
    pub id: ThreadId,
    pub thread_name: Option<String>,  // None in this case
    pub updated_at: DateTime<Utc>,
}
```

### Rendering Format

```
• Thread forked from 019c2d47-4935-7423-a190-05691f566092
```

**Visual Elements:**
- `•`: Bullet point indicator
- `Thread forked from`: Descriptive text
- `019c2d47-4935-7423-a190-05691f566092`: Thread ID (shown only once)

**Comparison:**
| Case | Format |
|------|--------|
| With Name | `Thread forked from {name} ({id})` |
| Without Name | `Thread forked from {id}` |

### Key Processes

1. **Test Setup** (from test):
```rust
let forked_from_id =
    ThreadId::from_string("019c2d47-4935-7423-a190-05691f566092").expect("forked id");

// NO session index entry written - simulating unnamed thread

// Emit fork event
chat.emit_forked_thread_event(forked_from_id);
```

2. **Name Lookup (fails)**:
```rust
// Attempt to look up thread name in session index
// No entry found → returns None
let thread_name = lookup_thread_name(&forked_from_id); // None
```

3. **Conditional Rendering**:
```rust
// Format based on whether name exists
let display = if let Some(name) = thread_name {
    format!("Thread forked from {} ({})", name, id)
} else {
    format!("Thread forked from {}", id)  // This case
};
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files

| File | Description |
|------|-------------|
| `codex-rs/tui/src/chatwidget/tests.rs` | Test `forked_thread_history_line_without_name_shows_id_once_snapshot` (line ~600) |
| `codex-rs/tui/src/chatwidget/mod.rs` | `emit_forked_thread_event` and lookup logic |
| `codex-rs/tui/src/history_cell.rs` | Conditional rendering logic |

### Key Functions

```rust
// Test function
async fn forked_thread_history_line_without_name_shows_id_once_snapshot()

// Emit fork event
fn emit_forked_thread_event(&mut self, forked_from_id: ThreadId)

// Name lookup (returns None in this case)
fn lookup_thread_name(&self, thread_id: &ThreadId) -> Option<String>

// Conditional display formatting
fn format_fork_line(id: &ThreadId, name: Option<String>) -> String
```

### Related Snapshots
- `forked_thread_history_line.snap` - With name case
- `forked_thread_history_line_without_name.snap` - This file (without name)

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Internal Dependencies

- `ThreadId`: Unique identifier (only available info)
- `lookup_thread_name`: Returns None when no session index entry
- `HistoryCell`: Renders the fork line

### Lookup Behavior

```
emit_forked_thread_event(forked_from_id)
    ↓
lookup_thread_name(forked_from_id)
    ↓
Read session_index.jsonl
    ↓
No entry found for ID
    ↓
Return None
    ↓
Format without name: "Thread forked from {id}"
```

### Edge Case Handling

| Scenario | Behavior |
|----------|----------|
| Named thread | Show name and ID |
| Unnamed thread | Show ID only (this case) |
| Missing index file | Show ID only |
| Corrupted index | Show ID only |

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks

1. **Uninformative**: ID alone doesn't help users identify the parent thread
2. **ID Fatigue**: Many unnamed forks create a sea of UUIDs
3. **Index Dependency**: Relies on session index which may not be reliable

### Edge Cases

1. **Empty Session Index**: File exists but is empty
2. **Partial Write**: Index entry partially written (corrupted JSON)
3. **Concurrent Access**: Thread forked while index is being written
4. **Old Threads**: Parent thread from old session, no longer in index
5. **ID Collision**: Extremely unlikely but theoretically possible

### Improvement Suggestions

1. **Auto-Naming**: Generate descriptive names for unnamed threads (e.g., "Thread from Jan 15")
2. **Message Preview**: Show first few words of parent thread's first message
3. **Timestamp**: Include when parent thread was created
4. **Default Names**: Auto-name threads based on first user message
5. **Index Rebuild**: Option to rebuild session index from history files
6. **Visual Hash**: Color-code or icon-code based on ID for easier recognition
7. **Recent Threads**: Show "Recent unnamed threads" list when forking
8. **Search**: Allow searching threads by content to identify unnamed ones
