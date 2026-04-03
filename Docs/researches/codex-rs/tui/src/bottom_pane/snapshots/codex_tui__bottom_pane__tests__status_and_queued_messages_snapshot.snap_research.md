# Status and Queued Messages Snapshot

## 1. 场景与职责 (Scene and Responsibility)

### 测试场景
Tests the combined display of status indicator and queued messages, showing how multiple UI elements coexist in the bottom pane.

### 组件职责
该快照测试针对 Codex TUI 的 **BottomPane** 组件，负责验证：
- Status indicator and queued messages display together
- Proper spacing between status and pending input preview
- Visual hierarchy with clear section separation
- Composer remains accessible below queued content

## 2. 功能点目的 (Feature Purpose)

### 测试目标
Validates the layout when both status indicator (task running) and queued messages are present simultaneously.

### 验证要点
1. Status indicator shows "Working" with interrupt hint
2. Queued messages section displays with proper header
3. Individual queued messages are indented with arrow indicator
4. Edit hint (⌥ + ↑) is shown for last queued message
5. Empty spacer separates sections appropriately
6. Composer input area is visible below

## 3. 具体技术实现 (Technical Implementation)

### 核心数据结构
```rust
pub(crate) struct BottomPane {
    status: Option<StatusIndicatorWidget>,
    pending_input_preview: PendingInputPreview,
    composer: ChatComposer,
    // ... other fields
}

pub(crate) struct PendingInputPreview {
    pending_steers: Vec<String>,
    queued_messages: Vec<String>,
    edit_binding: KeyBinding, // For edit hint display
}
```

### 渲染逻辑
- Status renders first (if present)
- Spacer row added when both status and pending previews exist
- `PendingInputPreview` renders header "Queued follow-up messages" with bullet
- Each queued message indented with "↳" arrow
- Edit hint shown on last message line
- Composer renders at bottom with footer

### 关键算法
1. **Section Detection**: `has_inline_previews = has_pending_thread_approvals || has_pending_input`
2. **Spacer Insertion**: Empty line added between status and previews when both present
3. **Message Formatting**: Queued messages prefixed with "↳", edit hint appended to last

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 源文件
- **主文件**: `codex-rs/tui/src/bottom_pane/mod.rs`

### 关键函数/方法
| 函数/方法 | 描述 |
|-----------|------|
| `set_task_running(true)` | Activates status indicator |
| `set_pending_input_preview()` | Sets queued messages to display |
| `as_renderable()` | Builds layout with proper section ordering |
| `PendingInputPreview::render()` | Renders queued messages with formatting |

### 测试代码位置
- Test: `status_and_queued_messages_snapshot` (lines 1591-1615)
- Sets task running and adds one queued message
- Verifies combined layout in snapshot

## 5. 依赖与外部交互 (Dependencies)

### 外部 Crates
| Crate | 用途 |
|-------|------|
| `ratatui` | TUI rendering framework |
| `insta` | Snapshot testing |
| `tokio` | Async runtime |

### 内部模块依赖
- `StatusIndicatorWidget` - Task status display
- `PendingInputPreview` - Queued messages rendering
- `ChatComposer` - Input composer
- `KeyBinding` - For edit hint formatting

### 协议依赖
- None directly

## 6. 风险、边界与改进建议 (Risks, Edge Cases, Improvements)

### 潜在风险
1. **Visual clutter**: Multiple sections may overwhelm users
2. **Height overflow**: Many queued messages may push composer off-screen
3. **Conflicting states**: Status may obscure important queued messages

### 边界情况
- Many queued messages (truncation needed)
- Long message text (wrapping required)
- Both pending steers and queued messages present
- Terminal height too small for all sections

### 改进建议
1. **Collapsible sections**: Allow users to collapse queued messages
2. **Priority indicators**: Highlight urgent queued messages
3. **Scroll integration**: Integrate with main scroll for tall content
4. **Compact mode**: Reduce spacing when screen space is limited
5. **Message count badge**: Show count in header when collapsed

### 相关文档
- `codex-rs/tui/styles.md` - TUI styling conventions
- `AGENTS.md` - Project agent guidelines
