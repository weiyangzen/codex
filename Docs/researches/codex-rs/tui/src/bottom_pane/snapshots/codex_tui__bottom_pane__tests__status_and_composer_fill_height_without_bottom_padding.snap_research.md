# Status and Composer Fill Height Without Bottom Padding Snapshot

## 1. 场景与职责 (Scene and Responsibility)

### 测试场景
Tests that the bottom pane efficiently uses available height without unnecessary padding, ensuring status and composer fill the allocated space.

### 组件职责
该快照测试针对 Codex TUI 的 **BottomPane** 组件，负责验证：
- Height calculation is accurate and minimal
- No trailing padding rows at the bottom
- Status indicator and composer properly fill available height
- Spacer rows are used appropriately for separation

## 2. 功能点目的 (Feature Purpose)

### 测试目标
Validates that the bottom pane renders efficiently without bottom padding when using exactly the desired height.

### 验证要点
1. `desired_height()` returns minimum required height
2. Rendering at exact desired height shows all content without truncation
3. No extra empty rows at the bottom
4. Status row, spacer, and composer are properly positioned
5. Context indicator in footer is visible

## 3. 具体技术实现 (Technical Implementation)

### 核心数据结构
```rust
pub(crate) struct BottomPane {
    composer: ChatComposer,
    status: Option<StatusIndicatorWidget>,
    pending_input_preview: PendingInputPreview,
    pending_thread_approvals: PendingThreadApprovals,
    unified_exec_footer: UnifiedExecFooter,
    // ... other fields
}

/// FlexRenderable for dynamic layout
pub struct FlexRenderable<'a> {
    items: Vec<(u16, RenderableItem<'a>)>,
}
```

### 渲染逻辑
- `FlexRenderable` stacks elements with optional flex growth
- Status has flex 0 (fixed height)
- Composer has flex 1 (takes remaining space)
- Spacer rows (flex 0) added between sections for visual separation
- `desired_height()` queries each component for its minimum height

### 关键算法
1. **Height Aggregation**: Sum of all component `desired_height()` values plus spacer rows
2. **Flex Distribution**: Remaining space after fixed elements distributed to flex items
3. **No Trailing Space**: Layout exactly fills the allocated area without padding

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 源文件
- **主文件**: `codex-rs/tui/src/bottom_pane/mod.rs`

### 关键函数/方法
| 函数/方法 | 描述 |
|-----------|------|
| `desired_height()` | Calculates minimum height needed for all components |
| `as_renderable()` | Constructs flex layout with proper spacing |
| `render()` | Renders to buffer with exact area dimensions |
| `render_snapshot()` | Test helper to capture rendered output |

### 测试代码位置
- Test: `status_and_composer_fill_height_without_bottom_padding` (lines 1447-1475)
- Creates pane with task running
- Renders at exact `desired_height(30)`
- Verifies no trailing padding in snapshot

## 5. 依赖与外部交互 (Dependencies)

### 外部 Crates
| Crate | 用途 |
|-------|------|
| `ratatui` | TUI rendering framework |
| `insta` | Snapshot testing |
| `tokio` | Async runtime |

### 内部模块依赖
- `FlexRenderable` - Flexible layout container
- `StatusIndicatorWidget` - Task status with spinner
- `ChatComposer` - Input area with footer
- `Renderable` trait - Common rendering interface

### 协议依赖
- None directly

## 6. 风险、边界与改进建议 (Risks, Edge Cases, Improvements)

### 潜在风险
1. **Height miscalculation**: May cause truncation or excess space
2. **Resize handling**: Rapid resizing may cause flickering
3. **Content overflow**: Tall content may exceed calculated height

### 边界情况
- Height of 1 (minimal rendering)
- Height less than minimum (content truncation)
- Very wide terminal (layout may look sparse)
- Multiple pending previews increasing height

### 改进建议
1. **Minimum height enforcement**: Ensure area is never smaller than desired
2. **Scroll support**: Allow scrolling for content exceeding available height
3. **Responsive breakpoints**: Adjust layout at different size thresholds
4. **Debug mode**: Visual indicators showing component boundaries

### 相关文档
- `codex-rs/tui/styles.md` - TUI styling conventions
- `AGENTS.md` - Project agent guidelines
