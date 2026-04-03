# Slash Popup "res" Snapshot Research

## 1. 场景与职责 (Usage Scenario and Responsibility)

This snapshot test validates the **slash command popup filtering and ranking** for the input "/res". It tests that when a user types "/res", the popup correctly shows "/resume" as the first (selected) command, demonstrating the fuzzy matching and ranking algorithm prioritizing the resume command.

**Responsibilities:**
- Filter and rank slash commands based on partial input
- Prioritize "/resume" for "res" prefix (common workflow)
- Display command description: "resume a saved chat"
- Provide visual confirmation of selected command

## 2. 功能点目的 (Feature Purpose)

The "/res" → "/resume" completion serves to:
1. **Quick Resume**: Allow users to quickly access the resume functionality
2. **Command Discovery**: Help users discover the resume command
3. **Efficient Input**: Minimize typing for common operations
4. **Consistent UX**: Match user expectations for command completion

For "/res" specifically:
- Should match "/resume" (resume saved chat command)
- Should rank "/resume" above other potential matches
- Should be ready for execution on Enter key

## 3. 具体技术实现 (Technical Implementation)

### Test Implementation

```rust
#[test]
fn slash_popup_resume_for_res_ui() {
    let (tx, _rx) = unbounded_channel::<AppEvent>();
    let sender = AppEventSender::new(tx);
    
    let mut composer = ChatComposer::new(
        true, sender, false,
        "Ask Codex to do anything".to_string(),
        false,
    );
    
    // Type "/res" character by character
    type_chars_humanlike(&mut composer, &['/', 'r', 'e', 's']);
    
    // Render and capture snapshot
    let mut terminal = Terminal::new(TestBackend::new(60, 6)).expect("terminal");
    terminal.draw(|f| composer.render(f.area(), f.buffer_mut())).expect("draw composer");
    
    // Snapshot should show /resume as the first entry for /res
    insta::assert_snapshot!("slash_popup_res", terminal.backend());
}
```

### Companion Logic Test

```rust
#[test]
fn slash_popup_resume_for_res_logic() {
    let (tx, _rx) = unbounded_channel::<AppEvent>();
    let sender = AppEventSender::new(tx);
    let mut composer = ChatComposer::new(
        true, sender, false,
        "Ask Codex to do anything".to_string(),
        false,
    );
    
    type_chars_humanlike(&mut composer, &['/', 'r', 'e', 's']);
    
    match &composer.active_popup {
        ActivePopup::Command(popup) => match popup.selected_item() {
            Some(CommandItem::Builtin(cmd)) => {
                assert_eq!(cmd.command(), "resume")
            }
            Some(CommandItem::UserPrompt(_)) => {
                panic!("unexpected prompt selected for '/res'")
            }
            None => panic!("no selected command for '/res'"),
        },
        _ => panic!("slash popup not active after typing '/res'"),
    }
}
```

### Command Matching

The matching logic uses fuzzy matching:
```rust
// In command_popup.rs
fn matches_query(item: &CommandItem, query: &str) -> bool {
    let name = match item {
        CommandItem::Builtin(cmd) => cmd.command(),
        CommandItem::UserPrompt(idx) => &self.prompts[*idx].name,
    };
    
    // Fuzzy match with scoring
    fuzzy_match(name, query).is_some()
}
```

For "/res":
- Query: "res"
- "/resume": matches "res" at start of "resume" → high score
- Other commands: scored lower if they don't start with "res"

### Command Description

Commands include descriptions for display:
```rust
// In slash_command.rs or similar
impl SlashCommand {
    fn description(&self) -> &'static str {
        match self {
            SlashCommand::Resume => "resume a saved chat",
            SlashCommand::Model => "choose what model and reasoning effort to use",
            // ...
        }
    }
}
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### Primary Files

| File | Purpose |
|------|---------|
| `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs` | Test implementation |
| `codex-rs/tui_app_server/src/bottom_pane/command_popup.rs` | Popup filtering and rendering |
| `codex-rs/tui_app_server/src/slash_command.rs` | SlashCommand enum and metadata |

### Key Methods

| Method | File | Purpose |
|--------|------|---------|
| `slash_popup_resume_for_res_ui()` | chat_composer.rs (tests) | UI snapshot test |
| `slash_popup_resume_for_res_logic()` | chat_composer.rs (tests) | Logic verification test |
| `selected_item()` | command_popup.rs | Returns selected CommandItem |
| `command()` | slash_command.rs | Returns command name string |

### CommandPopup Methods

```rust
// In command_popup.rs
impl CommandPopup {
    pub fn selected_item(&self) -> Option<&CommandItem> {
        self.filtered_indices.get(self.selected_idx)
            .map(|&idx| &self.items[idx])
    }
    
    pub fn move_up(&mut self) {
        if self.selected_idx > 0 {
            self.selected_idx -= 1;
        }
    }
    
    pub fn move_down(&mut self) {
        if self.selected_idx + 1 < self.filtered_indices.len() {
            self.selected_idx += 1;
        }
    }
}
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### Test Dependencies

```rust
use ratatui::Terminal;
use ratatui::backend::TestBackend;
use tokio::sync::mpsc::unbounded_channel;
```

### Command Dependencies

The test depends on:
- `SlashCommand::Resume` being available
- Command having description "resume a saved chat"
- Fuzzy matching working for "res" → "resume"

### Popup State

```rust
enum ActivePopup {
    None,
    Command(CommandPopup),
    File(FileSearchPopup),
    Skill(SkillPopup),
}
```

When "/res" is typed:
1. `sync_command_popup()` detects slash command context
2. Creates `ActivePopup::Command` with filtered results
3. `CommandPopup` contains "/resume" as first item

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvements)

### Ranking Risks

1. **Overlap with Other Commands**: Could conflict with "/reset" or other "res*" commands
2. **Custom Prompts**: User-defined prompts named "res*" might interfere
3. **Future Commands**: New commands starting with "res" could affect ranking

### Edge Cases

| Input | Expected |
|-------|----------|
| "/res" | Select "/resume" |
| "/resu" | Select "/resume" |
| "/resum" | Select "/resume" |
| "/resume" | Select "/resume" (exact) |
| "/r" | May show multiple, "/resume" among them |
| "/re" | Filter to 're' commands |

### Comparison with "/mo" Test

| Aspect | "/mo" | "/res" |
|--------|-------|--------|
| Target command | /model | /resume |
| Description | model selection | chat resumption |
| Input length | 3 chars | 4 chars |
| Potential conflicts | /models | /reset (if exists) |
| Usage frequency | High | Medium |

### Improvement Suggestions

1. **Command Aliases**: Allow "/r" as alias for "/resume"
2. **Recent Commands**: Show recently used commands at top
3. **Contextual Hiding**: Hide resume if no saved chats exist
4. **Tab Completion**: Tab after "/res" completes to "/resume "
5. **Command History**: Remember last used command per session

### Testing Gaps

- Test with "/reset" command (if it exists) to verify ranking
- Test with custom prompt named "research"
- Test with disabled resume command
- Test popup at narrow terminal widths
- Test with many filtered results (scrolling)

### UI/UX Considerations

1. **Visual Distinction**: Should "/resume" look different from other commands?
2. **Keyboard Shortcut**: Should Ctrl+R trigger resume directly?
3. **Confirmation**: Should resume require confirmation if unsaved changes exist?
4. **Preview**: Show which chat will be resumed?

### Performance

- Fuzzy matching is fast for small command sets
- Consider caching filtered results for common prefixes
- No async operations in popup filtering
