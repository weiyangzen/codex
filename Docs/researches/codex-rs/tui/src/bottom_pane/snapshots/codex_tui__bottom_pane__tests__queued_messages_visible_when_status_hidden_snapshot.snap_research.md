# Queued Messages Visible When Status Hidden Snapshot

## 1. 场景与职责 (Scene and Responsibility)

### 测试场景
Tests that queued messages remain visible even when the status indicator is hidden, ensuring users can still see pending input previews.

### 组件职责
该快照测试针对 Codex TUI 的 **BottomPane** 组件，负责验证：
- Status indicator can be hidden independently of other UI elements
- Queued messages (pending input preview) remain visible without status
- Layout adapts correctly when status is removed
- Composer and footer remain functional

## 2. 功能点目的 (Feature Purpose)

### 测试目标
Validates that queued messages are still displayed when `hide_status_indicator()` is called while a task is running.

### 验证要点
1. Status indicator is hidden after calling `hide_status_indicator()`
2. Queued messages section remains visible with proper formatting
3. Composer input area is still present
4. Footer with shortcuts and context info remains visible
5. Layout spacing is correct without status row

## 3. 具体技术实现 (Technical Implementation)

### 核心数据结构
```rust
pub(crate) struct BottomPane {
    composer: ChatComposer,
    view_stack: Vec<Box<dyn BottomPaneView>>,
    status: Option<StatusIndicatorWidget>,
    unified_exec_footer: UnifiedExecFooter,
    pending_input_preview: PendingInputPreview,
    pending_thread_approvals: PendingThreadApprovals,
    // ... other fields
}

/// Preview of pending steers and queued drafts
pub(crate) struct PendingInputPreview {
    pending_steers: Vec<String>,
    queued_messages: Vec<String>,
}
```

### 渲染逻辑
- `as_renderable()` builds flex layout with conditional elements
- When status is hidden, `unified_exec_footer` may still render if processes exist
- `pending_input_preview` always renders if it has content
- Spacer lines are added conditionally based on which elements are present
- Layout order: status (optional) → unified_exec_footer (optional) → spacer → pending_thread_approvals → spacer → pending_input_preview → spacer → composer

### 关键算法
1. **Conditional Rendering**: `has_status_or_footer = self.status.is_some() || !self.unified_exec_footer.is_empty()`
2. **Spacer Logic**: Empty line added between status/footer and pending previews when both exist
3. **Height Calculation**: `desired_height()` sums heights of all visible elements

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 源文件
- **主文件**: `codex-rs/tui/src/bottom_pane/mod.rs`

### 关键函数/方法
| 函数/方法 | 描述 |
|-----------|------|
| `hide_status_indicator()` | Hides the status widget while keeping other UI intact |
| `set_pending_input_preview()` | Updates queued messages and pending steers |
| `as_renderable()` | Builds the renderable layout structure |
| `render()` | Renders the bottom pane to buffer |

### 测试代码位置
- Test: `queued_messages_visible_when_status_hidden_snapshot` (lines 1563-1588)
- Sets task running, adds queued message, then hides status
- Verifies queued messages section is still visible in output

## 5. 依赖与外部交互 (Dependencies)

### 外部 Crates
| Crate | 用途 |
|-------|------|
| `ratatui` | TUI rendering framework |
| `insta` | Snapshot testing |
| `tokio` | Async runtime for event channels |

### 内部模块依赖
- `StatusIndicatorWidget` - Task status display with spinner
- `PendingInputPreview` - Queued messages and pending steers display
- `ChatComposer` - Input composer widget
- `UnifiedExecFooter` - Background process summary

### 协议依赖
- `codex_protocol` - Protocol types for operations

## 6. 风险、边界与改进建议 (Risks, Edge Cases, Improvements)

### 潜在风险
1. **Layout shifts**: Hiding status may cause jarring layout changes
2. **Missing context**: Users may not realize task is still running without status
3. **Spacing issues**: Conditional spacer logic may produce inconsistent gaps

### 边界情况
- Both status hidden and no queued messages (minimal layout)
- Status hidden but unified_exec_footer visible
- Very long queued messages with hidden status
- Terminal height too small for queued messages

### 改进建议
1. **Visual indicator**: Show subtle indicator that task is still running when status is hidden
2. **Animation**: Smooth transition when hiding/showing status
3. **Persistent hint**: Option to keep minimal status hint even when "hidden"
4. **Layout stability**: Reserve space for status to prevent layout shifts

### 相关文档
- `codex-rs/tui/styles.md` - TUI styling conventions
- `AGENTS.md` - Project agent guidelines
