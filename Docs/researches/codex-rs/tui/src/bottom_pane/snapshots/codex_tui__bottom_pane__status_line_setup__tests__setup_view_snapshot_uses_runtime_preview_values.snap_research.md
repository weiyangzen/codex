# Setup View Snapshot Uses Runtime Preview Values

## 1. 场景与职责 (Scene and Responsibility)

### 测试场景
Tests the status line configuration view with live preview functionality, showing how selected items appear in the status bar.

### 组件职责
该快照测试针对 Codex TUI 的 **StatusLineSetupView** 组件，负责验证：
- Status line item selection and ordering UI
- Live preview of configured status line with runtime values
- Interactive picker with navigation, selection, and reordering capabilities
- Visual feedback for enabled/disabled items

## 2. 功能点目的 (Feature Purpose)

### 测试目标
Validates the status line configuration view renders correctly with live preview of selected items using runtime preview values.

### 验证要点
1. Multi-select picker displays all available status line items
2. Selected items (model-name, current-dir, git-branch) are marked with [x]
3. Unselected items are marked with [ ]
4. Live preview shows actual runtime values (gpt-5-codex, ~/codex-rs, jif/statusline-preview)
5. Navigation instructions are clearly displayed
6. Item descriptions are properly truncated for narrow widths

## 3. 具体技术实现 (Technical Implementation)

### 核心数据结构
```rust
/// Available items that can be displayed in the status line
#[derive(EnumIter, EnumString, Display, Debug, Clone, Eq, PartialEq, Ord, PartialOrd)]
#[strum(serialize_all = "kebab_case")]
pub(crate) enum StatusLineItem {
    ModelName,
    ModelWithReasoning,
    CurrentDir,
    ProjectRoot,
    GitBranch,
    ContextRemaining,
    ContextUsed,
    FiveHourLimit,
    WeeklyLimit,
    CodexVersion,
    ContextWindowSize,
    UsedTokens,
    TotalInputTokens,
    TotalOutputTokens,
    SessionId,
    FastMode,
}

/// Runtime values used to preview the current status-line selection
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub(crate) struct StatusLinePreviewData {
    values: BTreeMap<StatusLineItem, String>,
}

/// Interactive view for configuring status line items
pub(crate) struct StatusLineSetupView {
    picker: MultiSelectPicker,
}
```

### 渲染逻辑
- Uses `MultiSelectPicker` builder pattern with title, description, and instructions
- Items are pre-populated from current configuration with enabled/disabled state
- Preview callback generates live status line preview using `StatusLinePreviewData::line_for_items()`
- Items joined with " · " separator in preview
- Navigation via ↑↓, reordering via ←→, selection via space

### 关键算法
1. **Item Ordering**: Selected items appear first in configured order, followed by unselected items
2. **Preview Generation**: Filters enabled items, maps to runtime values, joins with separator
3. **Event Handling**: Confirms with Enter (emits `AppEvent::StatusLineSetup`), cancels with Esc

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 源文件
- **主文件**: `codex-rs/tui/src/bottom_pane/status_line_setup.rs`

### 关键函数/方法
| 函数/方法 | 描述 |
|-----------|------|
| `StatusLineSetupView::new()` | Creates the setup view with pre-populated items and preview data |
| `line_for_items()` | Generates preview line from enabled items and runtime values |
| `status_line_select_item()` | Converts StatusLineItem to MultiSelectItem |
| `description()` | Returns user-visible description for each item |
| `render()` | Renders the multi-select picker interface |

### 测试代码位置
- Test: `setup_view_snapshot_uses_runtime_preview_values` (lines 349-370)
- Uses `render_lines()` helper to capture rendered output
- Preview data includes: ModelName="gpt-5-codex", CurrentDir="~/codex-rs", GitBranch="jif/statusline-preview", WeeklyLimit="weekly 82%"

## 5. 依赖与外部交互 (Dependencies)

### 外部 Crates
| Crate | 用途 |
|-------|------|
| `ratatui` | TUI rendering framework |
| `strum` | Enum iteration and string conversion |
| `insta` | Snapshot testing |
| `tokio` | Async runtime for event channel |

### 内部模块依赖
- `MultiSelectPicker` - Reusable multi-selection widget with ordering support
- `BottomPaneView` - Trait for views that can be displayed in bottom pane
- `AppEvent` - Events for status line configuration changes
- `AppEventSender` - Event dispatch mechanism

### 协议依赖
- None directly

## 6. 风险、边界与改进建议 (Risks, Edge Cases, Improvements)

### 潜在风险
1. **Preview staleness**: Runtime values may become stale if not refreshed
2. **Truncated descriptions**: Long descriptions may be truncated, losing important information
3. **Item ordering persistence**: Order changes must be persisted correctly

### 边界情况
- Empty selection (preview shows empty line)
- Items without runtime values are omitted from preview
- Very long runtime values may overflow preview area
- All items disabled (preview is None)

### 改进建议
1. **Real-time preview updates**: Refresh preview when runtime values change
2. **Tooltip on hover**: Show full description on focus
3. **Search/filter**: Add ability to search through many items
4. **Keyboard shortcuts**: Add shortcuts for select-all/deselect-all
5. **Preview customization**: Allow users to customize preview separator

### 相关文档
- `codex-rs/tui/styles.md` - TUI styling conventions
- `AGENTS.md` - Project agent guidelines
