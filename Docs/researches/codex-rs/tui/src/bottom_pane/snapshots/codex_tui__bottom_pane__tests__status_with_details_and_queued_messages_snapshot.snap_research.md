# Status With Details and Queued Messages Snapshot

## 1. 场景与职责 (Scene and Responsibility)

### 测试场景
Tests the complex layout with status indicator showing detailed information alongside queued messages, representing a busy multi-element UI state.

### 组件职责
该快照测试针对 Codex TUI 的 **BottomPane** 组件，负责验证：
- Status indicator with multi-line details rendering
- Coexistence of detailed status and queued messages
- Proper vertical spacing and visual hierarchy
- All elements remain readable and accessible

## 2. 功能点目的 (Feature Purpose)

### 测试目标
Validates the layout when status has detailed output, queued messages are present, and composer is still accessible.

### 验证要点
1. Status header "Working" with interrupt hint
2. Multi-line details displayed with tree-like indentation
3. Queued messages section with header and content
4. Proper spacing between all sections
5. Composer footer visible at bottom
6. No visual overlap or truncation

## 3. 具体技术实现 (Technical Implementation)

### 核心数据结构
```rust
pub(crate) struct BottomPane {
    status: Option<StatusIndicatorWidget>,
    pending_input_preview: PendingInputPreview,
    composer: ChatComposer,
    // ... other fields
}

pub(crate) struct StatusIndicatorWidget {
    header: String,
    details: Option<String>,
    details_capitalization: StatusDetailsCapitalization,
    details_max_lines: usize,
    // ... other fields
}
```

### 渲染逻辑
- Status renders header with spinner and timer
- Details lines rendered with "└" prefix for tree visualization
- Details capitalization applied per line
- Empty spacer separates status from queued messages
- Queued messages render with bullet header and arrow-indented items
- Another spacer before composer
- Footer shows shortcuts and context

### 关键算法
1. **Details Rendering**: Split by newline, each line prefixed with "└" or "  "
2. **Capitalization**: `CapitalizeFirst` capitalizes first letter of first line
3. **Max Lines Enforcement**: Details truncated to `details_max_lines`
4. **Section Spacing**: Spacer rows between major sections

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 源文件
- **主文件**: `codex-rs/tui/src/bottom_pane/mod.rs`

### 关键函数/方法
| 函数/方法 | 描述 |
|-----------|------|
| `update_status()` | Updates header, details, and capitalization |
| `set_pending_input_preview()` | Sets queued messages |
| `StatusIndicatorWidget::render()` | Renders status with details |
| `as_renderable()` | Builds complete layout |

### 测试代码位置
- Test: `status_with_details_and_queued_messages_snapshot` (lines 1529-1560)
- Sets status with two detail lines
- Adds queued message
- Verifies complex layout renders correctly

## 5. 依赖与外部交互 (Dependencies)

### 外部 Crates
| Crate | 用途 |
|-------|------|
| `ratatui` | TUI rendering framework |
| `insta` | Snapshot testing |
| `tokio` | Async runtime |

### 内部模块依赖
- `StatusIndicatorWidget` - Status with details support
- `PendingInputPreview` - Queued messages
- `StatusDetailsCapitalization` - Text formatting option
- `ChatComposer` - Input with footer

### 协议依赖
- `codex_protocol` - Protocol types

## 6. 风险、边界与改进建议 (Risks, Edge Cases, Improvements)

### 潜在风险
1. **Information overload**: Too many details may overwhelm users
2. **Height explosion**: Many detail lines + queued messages may exceed screen
3. **Scrolling confusion**: Users may not realize content is above viewport

### 边界情况
- Very long detail lines (wrapping)
- Many detail lines (truncation)
- Special characters in details
- Combined with unified exec footer

### 改进建议
1. **Collapsible details**: Allow users to expand/collapse detail sections
2. **Detail prioritization**: Show most important details first
3. **Scroll integration**: Better integration with main chat scroll
4. **Detail types**: Different styling for different detail types (errors, warnings, info)
5. **Copy functionality**: Allow copying details text

### 相关文档
- `codex-rs/tui/styles.md` - TUI styling conventions
- `AGENTS.md` - Project agent guidelines
