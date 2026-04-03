# Research: large Snapshot Test

## 1. 场景与职责 (Scenario and Responsibility)

This snapshot test validates the **large paste placeholder rendering** in the chat composer. When a user pastes content exceeding a certain character threshold, it is replaced with a compact placeholder to keep the UI responsive and readable.

**Scenario**: When the user pastes content larger than `LARGE_PASTE_CHAR_THRESHOLD` (1000 characters), the composer displays a placeholder like `[Pasted Content 1005 chars]` instead of the actual text.

**Responsibility**: The test ensures that:
- Large pastes are automatically converted to placeholders
- The placeholder shows the actual character count
- The original content is preserved for submission
- The UI remains responsive with large content

## 2. 功能点目的 (Purpose of the Feature)

Large paste placeholders serve to:
- Prevent UI slowdown from rendering massive text in the terminal
- Keep the composer input area clean and manageable
- Avoid accidental submission of unexpectedly large content
- Provide visual feedback about the paste size
- Allow users to review large content before submission

The snapshot captures the visual output when:
- Content exceeding 1000 characters is pasted
- Placeholder `[Pasted Content 1005 chars]` appears in composer
- Original content is stored in `pending_pastes` for later expansion

## 3. 具体技术实现 (Technical Implementation)

### Key Code Flow:

1. **Test Setup** (`ui_snapshots` test in `chat_composer.rs`):
```rust
let test_cases = vec![
    ("empty", None),
    ("small", Some("short".to_string())),
    ("large", Some("z".repeat(LARGE_PASTE_CHAR_THRESHOLD + 5))),  // 1005 chars
    // ...
];
```

2. **Paste Handling** (`handle_paste` in chat_composer.rs:776-798):
```rust
pub fn handle_paste(&mut self, pasted: String) -> bool {
    let pasted = pasted.replace("\r\n", "\n").replace('\r', "\n");
    let char_count = pasted.chars().count();
    
    if char_count > LARGE_PASTE_CHAR_THRESHOLD {
        // Large paste: create placeholder
        let placeholder = self.next_large_paste_placeholder(char_count);
        self.textarea.insert_element(&placeholder);
        self.pending_pastes.push((placeholder, pasted));
    } else if char_count > 1 && self.image_paste_enabled() && self.handle_paste_image_path(pasted.clone()) {
        // Image path paste
        self.textarea.insert_str(" ");
    } else {
        // Normal paste
        self.insert_str(&pasted);
    }
    // ...
}
```

3. **Placeholder Generation** (`next_large_paste_placeholder` in chat_composer.rs:1278-1287):
```rust
fn next_large_paste_placeholder(&mut self, char_count: usize) -> String {
    let base = format!("[Pasted Content {char_count} chars]");
    let next_suffix = self.large_paste_counters.entry(char_count).or_insert(0);
    *next_suffix += 1;
    if *next_suffix == 1 {
        base
    } else {
        format!("{base} #{next_suffix}")
    }
}
```

4. **Threshold Constant** (chat_composer.rs:240):
```rust
const LARGE_PASTE_CHAR_THRESHOLD: usize = 1000;
```

5. **Pending Pastes Storage** (chat_composer.rs:364):
```rust
pending_pastes: Vec<(String, String)>,
// Stores (placeholder, actual_content) pairs
```

### Data Flow:
```
User pastes large text → handle_paste() → Create placeholder → Store in pending_pastes
                                                    ↓
                                              Render placeholder
                                                    ↓
User submits → expand_pending_pastes() → Replace placeholder with actual content
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files:

| File | Purpose |
|------|---------|
| `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs` | Main composer, test at line ~6359 |

### Key Functions:

1. **Test Definition** (chat_composer.rs:6356-6360):
```rust
let test_cases = vec![
    ("empty", None),
    ("small", Some("short".to_string())),
    ("large", Some("z".repeat(LARGE_PASTE_CHAR_THRESHOLD + 5))),
    // ...
];
```

2. **`handle_paste()`** (chat_composer.rs:776-798):
```rust
pub fn handle_paste(&mut self, pasted: String) -> bool {
    // ... normalization ...
    let char_count = pasted.chars().count();
    if char_count > LARGE_PASTE_CHAR_THRESHOLD {
        let placeholder = self.next_large_paste_placeholder(char_count);
        self.textarea.insert_element(&placeholder);
        self.pending_pastes.push((placeholder, pasted));
    }
    // ...
}
```

3. **`expand_pending_pastes()`** (chat_composer.rs:1885-1951):
```rust
pub(crate) fn expand_pending_pastes(
    text: &str,
    mut elements: Vec<TextElement>,
    pending_pastes: &[(String, String)],
) -> (String, Vec<TextElement>) {
    // Stage 1: Index pending paste payloads
    // Stage 2: Walk elements and rebuild text
    // Stage 3: Inline actual paste payloads
    // Stage 4: Keep non-paste elements
    // Stage 5: Append trailing text
}
```

4. **Placeholder Counter** (chat_composer.rs:365):
```rust
large_paste_counters: HashMap<usize, usize>,
// Tracks suffix counters for duplicate-size pastes
```

### Snapshot Output:
```
"› [Pasted Content 1005 chars]                                                                       "
...
"                                                                                 100% context left  "
```

Note: The placeholder shows the exact character count (1005 = 1000 threshold + 5).

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Dependencies:
- `ratatui` - Terminal UI rendering
- `insta` - Snapshot testing

### Related State:
- `pending_pastes: Vec<(String, String)>` - Stores placeholder-to-content mapping
- `large_paste_counters: HashMap<usize, usize>` - Tracks duplicate placeholders
- `textarea` - Manages placeholder elements

### Submission Flow:
1. Placeholder is displayed in UI
2. On submit, `prepare_submission_text()` is called
3. `expand_pending_pastes()` replaces placeholders with actual content
4. Final text is sent to the model

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### Risks:
1. **Memory Usage**: Large pastes are stored twice (placeholder + actual content)
2. **Lost Content**: If placeholder is deleted, the pending paste is also removed
3. **Character Count Accuracy**: Unicode characters may have different byte/char counts

### Edge Cases:
1. **Exactly at Threshold**: Content with exactly 1000 chars is not treated as large
2. **Multiple Large Pastes**: Each gets a numbered placeholder (`#2`, `#3`, etc.)
3. **Editing Placeholder**: Users can delete the placeholder to remove the paste
4. **History Navigation**: Pastes should be restored correctly when navigating history

### Improvement Suggestions:

1. **Configurable Threshold**: Make `LARGE_PASTE_CHAR_THRESHOLD` user-configurable

2. **Preview Option**: Allow users to expand/collapse the placeholder to preview content

3. **Size Warning**: Show a warning when paste exceeds a certain size

4. **Line Count Alternative**: Consider using line count in addition to character count

5. **Compression**: For very large pastes, consider compression to reduce memory usage

6. **Test Coverage**: Add tests for:
   - Exactly at threshold boundary
   - Multiple large pastes with same size
   - Deleting and restoring large paste placeholders
   - Unicode content with multi-byte characters
   - History navigation with large pastes

7. **Visual Enhancement**: Consider different styling for large paste placeholders vs. image placeholders

8. **Statistics**: Show total pending paste size in footer
