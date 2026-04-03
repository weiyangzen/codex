# Research: Forked Thread History Line (With Name)

## 1. 场景与职责 (Scene and Responsibility)

This snapshot captures the **history line displayed when a thread is forked from a named parent thread**. When a user creates a new thread from an existing conversation, this indicator shows the relationship to the source thread.

**Scene Context:**
- A new thread has been created by forking from an existing thread
- The parent thread has a name ("named-thread") and ID
- The session index contains metadata about the parent thread
- The UI displays lineage information to help users track conversation history

**Responsibilities:**
- Display the parent thread relationship clearly
- Show both the human-readable name and unique ID
- Help users understand conversation lineage
- Provide context for forked conversations

## 2. 功能点目的 (Functional Purpose)

The forked thread history line serves to:

1. **Lineage Tracking**: Help users understand where a conversation originated
2. **Context Preservation**: Maintain awareness of parent conversation context
3. **Navigation Aid**: Potentially allow navigation back to parent thread
4. **Audit Trail**: Provide visibility into conversation branching

**Key Information Displayed:**
- Thread fork indicator (•)
- Parent thread name ("named-thread")
- Parent thread ID (UUID format)

## 3. 具体技术实现 (Technical Implementation)

### Key Data Structures

```rust
// From codex_protocol
pub struct ThreadId(String);

// Session index entry
pub struct SessionIndexEntry {
    pub id: ThreadId,
    pub thread_name: Option<String>,
    pub updated_at: DateTime<Utc>,
}

// Fork event
pub struct SessionConfiguredEvent {
    pub session_id: ThreadId,
    pub forked_from_id: Option<ThreadId>,
    pub thread_name: Option<String>,
    // ...
}
```

### Rendering Format

```
• Thread forked from named-thread (e9f18a88-8081-4e51-9d4e-8af5cde2d8dd)
```

**Visual Elements:**
- `•`: Bullet point indicator
- `Thread forked from`: Descriptive text
- `named-thread`: Human-readable thread name (from session index)
- `(e9f18a88-8081-4e51-9d4e-8af5cde2d8dd)`: Unique thread ID

### Key Processes

1. **Test Setup** (from test):
```rust
let forked_from_id =
    ThreadId::from_string("e9f18a88-8081-4e51-9d4e-8af5cde2d8dd").expect("forked id");

// Create session index entry with thread name
let session_index_entry = format!(
    "{{\"id\":\"{forked_from_id}\",\"thread_name\":\"named-thread\",\"updated_at\":\"2024-01-02T00:00:00Z\"}}\n"
);
std::fs::write(temp.path().join("session_index.jsonl"), session_index_entry)
    .expect("write session index");

// Emit fork event
chat.emit_forked_thread_event(forked_from_id);
```

2. **History Cell Generation**:
```rust
// AppEvent::InsertHistoryCell emitted with fork information
let history_cell = tokio::time::timeout(std::time::Duration::from_secs(2), async {
    loop {
        match rx.recv().await {
            Some(AppEvent::InsertHistoryCell(cell)) => break cell,
            // ...
        }
    }
}).await;
```

3. **Display Rendering**:
```rust
let combined = lines_to_single_string(&history_cell.display_lines(80));
// Renders: "• Thread forked from named-thread (e9f18a88-8081-4e51-9d4e-8af5cde2d8dd)"
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files

| File | Description |
|------|-------------|
| `codex-rs/tui/src/chatwidget/tests.rs` | Test `forked_thread_history_line_includes_name_and_id_snapshot` (line ~563) |
| `codex-rs/tui/src/chatwidget/mod.rs` | `emit_forked_thread_event` implementation |
| `codex-rs/tui/src/history_cell.rs` | History cell rendering |

### Key Functions

```rust
// Test function
async fn forked_thread_history_line_includes_name_and_id_snapshot()

// Emit fork event
fn emit_forked_thread_event(&mut self, forked_from_id: ThreadId)

// Display rendering
fn display_lines(&self, width: u16) -> Vec<Line>

// Session index lookup
fn lookup_thread_name(&self, thread_id: &ThreadId) -> Option<String>
```

### File Locations

```
~/.codex/
└── session_index.jsonl   # Contains thread metadata including names
```

### Related Snapshots
- `forked_thread_history_line.snap` - This file (with name)
- `forked_thread_history_line_without_name.snap` - Without name case

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Internal Dependencies

- `SessionIndexEntry`: Thread metadata storage
- `ThreadId`: Unique thread identifier
- `HistoryCell`: UI component for history display
- `AppEvent::InsertHistoryCell`: Event for adding history line

### External Dependencies

- **Session Index File**: `~/.codex/session_index.jsonl` for thread name lookup
- **File System**: Reading session index from disk

### Data Flow

```
Thread fork initiated
    ↓
SessionConfiguredEvent with forked_from_id
    ↓
Lookup thread name in session_index.jsonl
    ↓
AppEvent::InsertHistoryCell emitted
    ↓
HistoryCell rendered with name and ID
    ↓
Display: "Thread forked from {name} ({id})"
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks

1. **File I/O**: Reading session index on every fork could be slow
2. **Stale Data**: Session index may not have latest thread names
3. **Privacy**: Thread names may contain sensitive information

### Edge Cases

1. **Missing Session Index**: File doesn't exist or is corrupted
2. **Thread Not Found**: Parent thread ID not in session index
3. **Empty Name**: Thread name is empty string
4. **Very Long Name**: Thread name exceeds display width
5. **Special Characters**: Thread names with unicode or control characters
6. **Concurrent Forks**: Multiple forks happening simultaneously

### Improvement Suggestions

1. **Caching**: Cache session index in memory to avoid repeated reads
2. **Click Navigation**: Make thread ID clickable to jump to parent
3. **Fork Tree**: Show visual tree of fork relationships
4. **Timestamp**: Include when the fork occurred
5. **Truncation**: Handle long names gracefully with ellipsis
6. **Anonymous Fallback**: Better display when name is unavailable
7. **Fork Count**: Show how many times a thread has been forked
8. **Visual Indicator**: Distinct icon or color for fork events
