# Status Only Snapshot

## 1. 场景与职责 (Scene and Responsibility)

### 测试场景
Tests the bottom pane with only the status indicator active (no queued messages or other overlays), showing the cleanest running state UI.

### 组件职责
该快照测试针对 Codex TUI 的 **BottomPane** 组件，负责验证：
- Clean status-only layout when task is running
- Proper spacing between status and composer
- Footer visibility with shortcuts and context
- Interrupt hint visibility in status line

## 2. 功能点目的 (Feature Purpose)

### 测试目标
Validates the basic running state UI with status indicator and composer, without any additional overlays or pending content.

### 验证要点
1. Status indicator shows "Working" with spinner and timer
2. Interrupt hint "esc to interrupt" is visible
3. Empty spacer row separates status from composer
4. Composer input prompt is visible
5. Footer shows shortcuts hint and context percentage
6. Layout is clean and uncluttered

## 3. 具体技术实现 (Technical Implementation)

### 核心数据结构
```rust
pub(crate) struct BottomPane {
    composer: ChatComposer,
    status: Option<StatusIndicatorWidget>,
    pending_input_preview: PendingInputPreview,
    unified_exec_footer: UnifiedExecFooter,
    is_task_running: bool,
    // ... other fields
}

pub(crate) struct StatusIndicatorWidget {
    header: String,
    details: Option<String>,
    interrupt_hint_visible: bool,
    inline_message: Option<String>,
    // ... animation fields
}
```

### 渲染逻辑
- When `set_task_running(true)` is called, status widget is created
- Status renders with spinner animation, header "Working", and interrupt hint
- Spacer row added between status and composer
- Composer renders with placeholder and footer
- Footer shows "? for shortcuts" and "100% context left"

### 关键算法
1. **Status Creation**: `StatusIndicatorWidget::new()` called when task starts
2. **Interrupt Hint**: Controlled by `set_interrupt_hint_visible()`
3. **Spacer Logic**: Added when `has_inline_previews` is false but status exists
4. **Footer Content**: Context percentage from `context_window_percent`

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 源文件
- **主文件**: `codex-rs/tui/src/bottom_pane/mod.rs`

### 关键函数/方法
| 函数/方法 | 描述 |
|-----------|------|
| `set_task_running(true)` | Creates and shows status indicator |
| `StatusIndicatorWidget::new()` | Initializes status with animation |
| `as_renderable()` | Builds layout with status, spacer, composer |
| `render()` | Renders complete bottom pane |

### 测试代码位置
- Test: `status_only_snapshot` (lines 1478-1498)
- Creates pane, starts task, renders at calculated height
- Verifies clean status-composer layout

## 5. 依赖与外部交互 (Dependencies)

### 外部 Crates
| Crate | 用途 |
|-------|------|
| `ratatui` | TUI rendering framework |
| `insta` | Snapshot testing |
| `tokio` | Async runtime for status timer |

### 内部模块依赖
- `StatusIndicatorWidget` - Animated status display
- `ChatComposer` - Input composer with footer
- `FrameRequester` - For animation frame scheduling

### 协议依赖
- None directly

## 6. 风险、边界与改进建议 (Risks, Edge Cases, Improvements)

### 潜在风险
1. **Animation performance**: Spinner animation may cause unnecessary redraws
2. **Timer drift**: Status timer may drift over long-running tasks
3. **Focus confusion**: Users may not realize they can still type

### 边界情况
- Task starts with existing composer text
- Very long running task (timer display)
- Context window at 0%
- Status with details lines

### 改进建议
1. **Progress indication**: Show task progress when available
2. **Time formatting**: Human-readable duration (e.g., "2m 30s")
3. **Status history**: Show previous operation status
4. **Customizable hint**: Allow users to customize interrupt hint
5. **Idle detection**: Dim status when task appears idle

### 相关文档
- `codex-rs/tui/styles.md` - TUI styling conventions
- `AGENTS.md` - Project agent guidelines
