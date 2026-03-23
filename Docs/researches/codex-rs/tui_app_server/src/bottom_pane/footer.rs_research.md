# footer.rs 深度研究文档

## 文件位置
`codex-rs/tui_app_server/src/bottom_pane/footer.rs`

---

## 1. 场景与职责

### 1.1 模块定位
`footer.rs` 是 Codex TUI（Terminal User Interface）应用中 **底部面板（Bottom Pane）** 的页脚渲染模块。它负责在聊天输入框（Chat Composer）下方渲染各种提示信息、快捷键帮助和上下文状态指示器。

### 1.2 核心职责

| 职责 | 说明 |
|------|------|
| **纯渲染** | 将 `FooterProps` 格式化为 `Line`，不修改任何状态 |
| **提示渲染** | 显示快捷键提示（`? for shortcuts`）、队列提示（`Tab to queue`）等 |
| **模式指示** | 显示协作模式（Plan/Pair Programming/Execute）指示器 |
| **上下文显示** | 显示上下文窗口使用情况（`72% context left` 或 `123K used`） |
| **状态行** | 支持可配置的 `/statusline` 项目（模型、Git 分支、上下文使用等） |
| **响应式布局** | 根据终端宽度自适应折叠/截断内容 |

### 1.3 关键术语

- **Status Line（状态行）**：可配置的上下文行，显示模型、Git 分支、上下文使用等信息
- **Instructional Footer（指令页脚）**：告诉用户下一步操作的行（如退出确认、快捷键帮助、队列提示）
- **Contextual Footer（上下文页脚）**：显示环境上下文而非操作指令（如状态行、Agent 标签）

---

## 2. 功能点目的

### 2.1 FooterMode（页脚模式）

```rust
pub(crate) enum FooterMode {
    QuitShortcutReminder,   // 临时"再按一次退出"提示
    ShortcutOverlay,        // 多行快捷键覆盖层（按 ? 触发）
    EscHint,               // 临时"再按 Esc"提示
    ComposerEmpty,         // 编辑器为空时的基础单行页脚
    ComposerHasDraft,      // 编辑器有草稿时的基础单行页脚
}
```

**设计意图**：
- 区分不同的用户交互状态
- 优先级：`QuitShortcutReminder` > `ShortcutOverlay` > `EscHint` > 基础模式
- 由 `ChatComposer` 拥有并管理状态转换

### 2.2 响应式折叠逻辑（Single-line Collapse）

当终端宽度不足时，页脚内容按以下优先级折叠：

1. **队列提示模式**：优先保留队列提示，先移除右侧上下文
2. **模式循环提示**：先移除 `? for shortcuts`，再移除 `(shift+tab to cycle)`
3. **仅模式标签**：如果循环提示放不下，只显示模式标签
4. **完全隐藏**：如果什么都放不下，左侧完全隐藏

### 2.3 快捷键覆盖层（Shortcut Overlay）

按 `?` 键触发的多行帮助界面，显示：

| 快捷键 | 功能 |
|--------|------|
| `/` | 命令 |
| `!` | Shell 命令 |
| `Shift+Enter` / `Ctrl+J` | 换行 |
| `Tab` | 队列消息 |
| `@` | 文件路径 |
| `Ctrl+V` / `Ctrl+Alt+V` (WSL) | 粘贴图片 |
| `Ctrl+G` | 外部编辑器 |
| `Esc` / `Esc Esc` | 编辑上一条消息 |
| `Ctrl+C` | 退出 |
| `Ctrl+T` | 查看转录 |
| `Shift+Tab` | 切换模式（协作模式启用时） |

### 2.4 上下文窗口显示

```rust
pub(crate) fn context_window_line(percent: Option<i64>, used_tokens: Option<i64>) -> Line<'static>
```

- 优先显示百分比（如 `72% context left`）
- 其次显示已使用 token 数（如 `123K used`）
- 默认显示 `100% context left`

---

## 3. 具体技术实现

### 3.1 核心数据结构

#### FooterProps（渲染输入）

```rust
pub(crate) struct FooterProps {
    pub(crate) mode: FooterMode,
    pub(crate) esc_backtrack_hint: bool,
    pub(crate) use_shift_enter_hint: bool,
    pub(crate) is_task_running: bool,
    pub(crate) collaboration_modes_enabled: bool,
    pub(crate) is_wsl: bool,
    pub(crate) quit_shortcut_key: KeyBinding,
    pub(crate) context_window_percent: Option<i64>,
    pub(crate) context_window_used_tokens: Option<i64>,
    pub(crate) status_line_value: Option<Line<'static>>,
    pub(crate) status_line_enabled: bool,
    pub(crate) active_agent_label: Option<String>,
}
```

**设计原则**：
- 纯数据输入，无业务逻辑
- 调用方（`ChatComposer`、`BottomPane`、`ChatWidget`）负责构造
- 页脚模块不推断缺失状态

#### CollaborationModeIndicator（协作模式指示器）

```rust
pub(crate) enum CollaborationModeIndicator {
    Plan,
    #[allow(dead_code)]
    PairProgramming,  // 当前被过滤，保留供未来使用
    #[allow(dead_code)]
    Execute,          // 当前被过滤，保留供未来使用
}
```

样式：
- `Plan`：洋红色（magenta）
- `PairProgramming`：青色（cyan）
- `Execute`：暗淡（dim）

### 3.2 关键渲染流程

#### 单行布局计算

```rust
pub(crate) fn single_line_footer_layout(
    area: Rect,
    context_width: u16,
    collaboration_mode_indicator: Option<CollaborationModeIndicator>,
    show_cycle_hint: bool,
    show_shortcuts_hint: bool,
    show_queue_hint: bool,
) -> (SummaryLeft, bool)
```

返回：
- `SummaryLeft`：左侧内容（默认、自定义行、或无）
- `bool`：是否显示右侧上下文

**算法步骤**：

1. 计算默认状态的行宽
2. 如果能容纳左侧+右侧，返回 `(Default, true)`
3. 如果是队列提示模式，尝试缩短提示文本
4. 如果是协作模式，尝试移除循环提示
5. 最后尝试仅显示模式标签
6. 如果都失败，返回 `(None, true)`

#### 页脚高度计算

```rust
pub(crate) fn footer_height(props: &FooterProps) -> u16
```

根据模式返回行数：
- `ShortcutOverlay`：多行（由 `build_columns` 决定）
- 其他：单行

### 3.3 被动页脚状态行

```rust
pub(crate) fn passive_footer_status_line(props: &FooterProps) -> Option<Line<'static>>
```

当页脚不忙时显示上下文信息：
- 如果 `status_line_enabled` 为 true，显示配置的状态行
- 如果 `active_agent_label` 存在，追加到状态行（用 ` · ` 分隔）

```rust
pub(crate) fn shows_passive_footer_line(props: &FooterProps) -> bool
```

判断条件：
- `ComposerEmpty`：总是 true
- `ComposerHasDraft`：仅当 `!is_task_running`
- 其他模式：false

### 3.4 快捷键定义

```rust
struct ShortcutDescriptor {
    id: ShortcutId,
    bindings: &'static [ShortcutBinding],
    prefix: &'static str,
    label: &'static str,
}

struct ShortcutBinding {
    key: KeyBinding,
    condition: DisplayCondition,
}

enum DisplayCondition {
    Always,
    WhenShiftEnterHint,
    WhenNotShiftEnterHint,
    WhenUnderWSL,
    WhenCollaborationModesEnabled,
}
```

**WSL 特殊处理**：
粘贴图片快捷键在 WSL 下显示 `Ctrl+Alt+V`（因为终端经常拦截普通的 `Ctrl+V`）

### 3.5 列布局构建

```rust
fn build_columns(entries: Vec<Line<'static>>) -> Vec<Line<'static>>
```

将快捷键列表格式化为两列布局：
- 计算每列最大宽度
- 添加列内边距（4 字符）和列间距（4 字符）
- 使用暗淡样式（dim）

---

## 4. 关键代码路径与文件引用

### 4.1 调用链

```
ChatWidget::draw_bottom_pane
  └── BottomPane::render
        └── ChatComposer::render
              ├── footer_height()                    [计算高度]
              ├── single_line_footer_layout()        [布局决策]
              ├── render_footer_line()               [渲染预计算行]
              └── render_footer_from_props()         [渲染默认映射]
```

### 4.2 相关文件

| 文件 | 关系 |
|------|------|
| `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs` | 主要调用方，管理 `FooterMode` 状态 |
| `codex-rs/tui_app_server/src/bottom_pane/mod.rs` | 模块导出，定义 `QUIT_SHORTCUT_TIMEOUT` |
| `codex-rs/tui_app_server/src/bottom_pane/bottom_pane_view.rs` | `BottomPaneView` trait 定义 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | 高层状态管理，设置状态行值 |
| `codex-rs/tui_app_server/src/key_hint.rs` | 按键绑定显示格式 |
| `codex-rs/tui_app_server/src/render/line_utils.rs` | `prefix_lines` 工具函数 |
| `codex-rs/tui_app_server/src/line_truncation.rs` | 行截断工具 |
| `codex-rs/tui_app_server/src/status/helpers.rs` | `format_tokens_compact` 函数 |
| `codex-rs/tui_app_server/src/ui_consts.rs` | `FOOTER_INDENT_COLS` 常量 |

### 4.3 测试快照文件

位于 `codex-rs/tui_app_server/src/bottom_pane/snapshots/`：

- `codex_tui_app_server__bottom_pane__footer__tests__footer_*.snap`
- 覆盖场景：默认快捷键、Shift+Enter 提示、Ctrl+C 退出提示、Esc 提示、上下文显示、队列提示、协作模式指示器、状态行等

---

## 5. 依赖与外部交互

### 5.1 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `ratatui` | TUI 渲染框架（`Buffer`, `Rect`, `Line`, `Span`, `Paragraph`, `Widget`） |
| `crossterm` | 终端事件（`KeyCode`） |

### 5.2 内部模块依赖

```rust
use crate::key_hint;
use crate::key_hint::KeyBinding;
use crate::render::line_utils::prefix_lines;
use crate::status::format_tokens_compact;
use crate::ui_consts::FOOTER_INDENT_COLS;
```

### 5.3 与 tui crate 的关系

`codex-rs/tui/src/bottom_pane/footer.rs` 与 `tui_app_server` 版本几乎完全相同，这是有意为之的代码共享设计。根据 `AGENTS.md`：

> "When a change lands in `codex-rs/tui` and `codex-rs/tui_app_server` has a parallel implementation of the same behavior, reflect the change in `codex-rs/tui_app_server` too unless there is a documented reason not to."

### 5.4 状态流

```
ChatWidget (owns quit/interrupt state machine)
    ↓
BottomPane (schedules redraws for time-based hints)
    ↓
ChatComposer (owns FooterMode, constructs FooterProps)
    ↓
footer.rs (pure rendering from FooterProps)
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 代码重复
`tui` 和 `tui_app_server` 两个 crate 中存在几乎相同的 `footer.rs` 实现。这增加了维护负担，需要确保两个版本保持同步。

**缓解措施**：
- 遵循 `AGENTS.md` 的约定，修改时同时更新两个版本
- 使用 snapshot 测试捕获渲染差异

#### 6.1.2 宽度计算精度
使用 `line.width()` 计算显示宽度，对于某些 Unicode 字符（如宽字符、零宽字符）可能不准确。

**相关代码**：
```rust
let default_width = default_line.width() as u16;
```

**建议**：考虑使用 `unicode-width` crate 进行更精确的宽度计算。

#### 6.1.3 硬编码常量
多处使用硬编码的间距和阈值：

```rust
const FOOTER_CONTEXT_GAP_COLS: u16 = 1;
const COLUMN_PADDING: [usize; COLUMNS] = [4, 4];
const COLUMN_GAP: usize = 4;
```

这些值在代码中被分散定义，不易统一管理。

### 6.2 边界情况

#### 6.2.1 极窄终端
当终端宽度小于最小内容宽度时：
- `left_fits()` 返回 false
- `single_line_footer_layout()` 最终返回 `(SummaryLeft::None, true)`
- 左侧完全隐藏，仅保留右侧上下文（如果放得下）

#### 6.2.2 状态行截断
当状态行过长时：
```rust
truncate_line_with_ellipsis_if_overflow(line, max_left as usize)
```
使用省略号截断，保留模式指示器可见。

#### 6.2.3 WSL 检测
粘贴图片快捷键的条件显示依赖运行时 WSL 检测：
```rust
#[cfg(target_os = "linux")]
{
    crate::clipboard_paste::is_probably_wsl()
}
```

### 6.3 改进建议

#### 6.3.1 统一代码库
考虑将 `footer.rs` 提取到共享 crate（如 `codex-tui-common`），消除 `tui` 和 `tui_app_server` 之间的代码重复。

#### 6.3.2 配置化常量
将硬编码的间距、阈值提取到配置结构体：

```rust
struct FooterLayoutConfig {
    context_gap_cols: u16,
    column_padding: usize,
    column_gap: usize,
}
```

#### 6.3.3 增强测试覆盖
当前测试主要依赖 snapshot 测试。建议添加：
- 单元测试验证布局算法边界条件
- 属性测试（property-based testing）验证各种宽度组合
- 模拟不同 Unicode 字符的宽度计算

#### 6.3.4 性能优化
`single_line_footer_layout` 在每次渲染时都会重新计算多次行宽。可以考虑：
- 缓存行宽计算结果
- 使用增量更新避免完整重新布局

#### 6.3.5 可访问性
当前页脚仅依赖颜色区分状态（如洋红色表示 Plan 模式）。建议：
- 添加图标或文本前缀作为颜色之外的区分方式
- 支持高对比度模式

### 6.4 技术债务

1. **死代码**：`PairProgramming` 和 `Execute` 模式被标记为 `#[allow(dead_code)]`，需要决定是启用还是移除
2. **TODO 注释**：代码中缺少 TODO/FIXME 注释，但存在实验性功能（如 `DOUBLE_PRESS_QUIT_SHORTCUT_ENABLED` 被硬编码为 `false`）
3. **平台特定代码**：WSL 检测和平台特定的快捷键显示增加了复杂性

---

## 7. 总结

`footer.rs` 是一个设计良好的纯渲染模块，职责清晰，与状态管理分离。其核心复杂度在于响应式布局算法，需要在有限宽度内智能地折叠和截断内容。主要维护挑战在于与 `tui` crate 的代码同步，以及处理各种终端宽度和 Unicode 字符的边界情况。
