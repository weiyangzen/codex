# footer.rs 深度研究文档

## 1. 场景与职责

### 1.1 模块定位

`footer.rs` 是 Codex TUI（Terminal User Interface）中负责底部状态栏渲染的核心模块，位于 `codex-rs/tui/src/bottom_pane/footer.rs`。它是纯渲染层组件，负责将 `FooterProps` 格式化为 `Line` 文本行，**不维护任何可变状态**。

### 1.2 核心职责

| 职责 | 说明 |
|------|------|
| **状态栏渲染** | 将 `FooterProps` 转换为 ratatui 的 `Line` 进行渲染 |
| **宽度自适应** | 根据终端宽度动态选择显示内容（single-line collapse 逻辑） |
| **快捷键提示** | 显示 `? for shortcuts`、队列提示、模式切换提示等 |
| **协作模式指示器** | 显示 Plan/PairProgramming/Execute 模式标签 |
| **上下文窗口信息** | 显示剩余上下文百分比或已使用 token 数 |
| **可配置状态行** | 支持 `/statusline` 自定义底部状态栏内容 |
| **Agent 标签显示** | 多 Agent 模式下显示当前查看的 Agent 标签 |

### 1.3 架构边界

```
┌─────────────────────────────────────────────────────────────┐
│  ChatWidget (高层状态机)                                      │
│  - 决定何时显示 quit/interrupt 提示                          │
│  - 管理 status line 数据计算                                 │
└───────────────────────┬─────────────────────────────────────┘
                        │ 传递 FooterProps
┌───────────────────────▼─────────────────────────────────────┐
│  ChatComposer (FooterMode 决策者)                            │
│  - 选择当前 FooterMode                                       │
│  - 设置 hint 标志位                                          │
└───────────────────────┬─────────────────────────────────────┘
                        │ 调用 footer 渲染函数
┌───────────────────────▼─────────────────────────────────────┐
│  footer.rs (纯渲染层)                                        │
│  - 格式化 FooterProps → Line                                 │
│  - 宽度自适应布局                                            │
└─────────────────────────────────────────────────────────────┘
```

**关键原则**：footer 模块**不决定**显示什么内容，只负责**如何渲染**传入的内容。

---

## 2. 功能点目的

### 2.1 FooterMode 枚举

定义底部栏的显示模式：

```rust
pub(crate) enum FooterMode {
    QuitShortcutReminder,   // "再次按下退出" 提示 (Ctrl+C/Ctrl+D)
    ShortcutOverlay,        // 多行快捷键帮助面板 (按下 ?)
    EscHint,                // "再次按下 Esc" 提示
    ComposerEmpty,          // 编辑器为空时的基础状态
    ComposerHasDraft,       // 编辑器有草稿时的基础状态
}
```

### 2.2 协作模式指示器

```rust
pub(crate) enum CollaborationModeIndicator {
    Plan,              // 紫色显示
    PairProgramming,   // 青色显示 (当前隐藏)
    Execute,           // 暗淡显示 (当前隐藏)
}
```

### 2.3 FooterProps 数据结构

```rust
pub(crate) struct FooterProps {
    pub(crate) mode: FooterMode,
    pub(crate) esc_backtrack_hint: bool,           // Esc 回退提示
    pub(crate) use_shift_enter_hint: bool,         // 使用 Shift+Enter 换行提示
    pub(crate) is_task_running: bool,              // 是否有任务运行中
    pub(crate) collaboration_modes_enabled: bool,  // 协作模式是否启用
    pub(crate) is_wsl: bool,                       // 是否在 WSL 环境
    pub(crate) quit_shortcut_key: KeyBinding,      // 退出快捷键
    pub(crate) context_window_percent: Option<i64>,      // 上下文剩余百分比
    pub(crate) context_window_used_tokens: Option<i64>,  // 已使用 token 数
    pub(crate) status_line_value: Option<Line<'static>>, // 自定义状态行内容
    pub(crate) status_line_enabled: bool,          // 状态行是否启用
    pub(crate) active_agent_label: Option<String>, // 当前 Agent 标签
}
```

### 2.4 宽度自适应策略

当终端宽度不足时，按优先级逐步降级显示：

1. **完整显示**：`? for shortcuts · Plan mode (shift+tab to cycle)` + 右侧上下文
2. **隐藏 cycle hint**：`? for shortcuts · Plan mode` + 右侧上下文
3. **仅模式标签**：`Plan mode` + 右侧上下文
4. **仅模式标签（无上下文）**：`Plan mode`
5. **队列模式优先**：当任务运行时，优先保留 `Tab to queue message` 提示

---

## 3. 具体技术实现

### 3.1 核心数据结构

#### SummaryHintKind

```rust
enum SummaryHintKind {
    None,
    Shortcuts,      // "? for shortcuts"
    QueueMessage,   // "Tab to queue message"
    QueueShort,     // "Tab to queue"
}
```

#### LeftSideState

```rust
struct LeftSideState {
    hint: SummaryHintKind,
    show_cycle_hint: bool,  // 是否显示 "(shift+tab to cycle)"
}
```

#### SummaryLeft

```rust
pub(crate) enum SummaryLeft {
    Default,            // 使用默认 FooterProps 映射
    Custom(Line<'static>),  // 使用自定义行
    None,               // 不显示左侧内容
}
```

### 3.2 关键渲染函数

#### `single_line_footer_layout`

核心宽度自适应函数，返回 `(SummaryLeft, bool)`：
- `SummaryLeft`：左侧显示内容
- `bool`：是否显示右侧上下文

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

**算法流程**：
1. 计算默认状态的行宽度
2. 检查是否能同时容纳左侧内容和右侧上下文
3. 根据 `show_queue_hint` 选择不同的降级路径
4. 依次尝试：完整显示 → 隐藏 cycle hint → 仅模式标签 → 无左侧内容

#### `footer_from_props_lines`

将 `FooterProps` 映射为 `Vec<Line>`，处理所有 `FooterMode`：

```rust
fn footer_from_props_lines(
    props: &FooterProps,
    collaboration_mode_indicator: Option<CollaborationModeIndicator>,
    show_cycle_hint: bool,
    show_shortcuts_hint: bool,
    show_queue_hint: bool,
) -> Vec<Line<'static>>
```

#### `render_footer_from_props`

直接渲染 `FooterProps` 为底部栏：

```rust
pub(crate) fn render_footer_from_props(
    area: Rect,
    buf: &mut Buffer,
    props: &FooterProps,
    collaboration_mode_indicator: Option<CollaborationModeIndicator>,
    show_cycle_hint: bool,
    show_shortcuts_hint: bool,
    show_queue_hint: bool,
)
```

### 3.3 快捷键覆盖层

#### ShortcutDescriptor

```rust
struct ShortcutDescriptor {
    id: ShortcutId,
    bindings: &'static [ShortcutBinding],
    prefix: &'static str,
    label: &'static str,
}
```

#### DisplayCondition

支持条件显示的快捷键：

```rust
enum DisplayCondition {
    Always,
    WhenShiftEnterHint,           // 仅在 use_shift_enter_hint 时显示
    WhenNotShiftEnterHint,        // 仅在非 use_shift_enter_hint 时显示
    WhenUnderWSL,                 // 仅在 WSL 环境下显示
    WhenCollaborationModesEnabled, // 仅在协作模式启用时显示
}
```

#### 快捷键列表 (SHORTCUTS)

| 快捷键 | 功能 | 条件 |
|--------|------|------|
| `/` | 命令 | Always |
| `!` | Shell 命令 | Always |
| `Shift+Enter` / `Ctrl+J` | 换行 | 根据终端能力 |
| `Tab` | 队列消息 | Always |
| `@` | 文件路径 | Always |
| `Ctrl+V` / `Ctrl+Alt+V` | 粘贴图片 | 非 WSL / WSL |
| `Ctrl+G` | 外部编辑器 | Always |
| `Esc` | 编辑上一条消息 | Always |
| `Ctrl+C` | 退出 | Always |
| `Ctrl+T` | 查看转录 | Always |
| `Shift+Tab` | 切换模式 | 协作模式启用 |

### 3.4 状态行 (Status Line)

#### 被动状态行逻辑

```rust
pub(crate) fn passive_footer_status_line(props: &FooterProps) -> Option<Line<'static>>
```

当满足以下条件时显示：
- `status_line_enabled` 为 true
- 当前模式允许被动显示（`ComposerEmpty` 或 `ComposerHasDraft` 且非任务运行中）

状态行内容与 Agent 标签合并显示，中间用 ` · ` 分隔。

#### 上下文窗口显示

```rust
pub(crate) fn context_window_line(
    percent: Option<i64>, 
    used_tokens: Option<i64>
) -> Line<'static>
```

优先级：
1. 如果有 `percent`，显示 `"{percent}% context left"`
2. 如果有 `used_tokens`，显示 `"{used_fmt} used"`
3. 默认显示 `"100% context left"`

---

## 4. 关键代码路径与文件引用

### 4.1 调用链

```
ChatComposer::render() 
  └── 构建 FooterProps
  └── 调用 single_line_footer_layout()  [footer.rs:310]
  └── 根据结果选择：
      ├── render_footer_line()          [footer.rs:213]
      ├── render_footer_from_props()    [footer.rs:229]
      └── render_context_right()        [footer.rs:529]
```

### 4.2 关键文件引用

| 文件 | 作用 |
|------|------|
| `codex-rs/tui/src/bottom_pane/footer.rs` | 本模块，纯渲染逻辑 |
| `codex-rs/tui/src/bottom_pane/chat_composer.rs` | 调用方，构建 FooterProps |
| `codex-rs/tui/src/bottom_pane/mod.rs` | BottomPane 模块，协调 footer 与上层 |
| `codex-rs/tui/src/chatwidget.rs` | 高层状态机，管理 status line 数据 |
| `codex-rs/tui/src/key_hint.rs` | 快捷键绑定和显示格式 |
| `codex-rs/tui/src/ui_consts.rs` | UI 常量（FOOTER_INDENT_COLS） |
| `codex-rs/tui/src/render/line_utils.rs` | 行工具函数（prefix_lines） |
| `codex-rs/tui/src/status/helpers.rs` | token 格式化工具 |
| `codex-rs/tui/src/bottom_pane/status_line_setup.rs` | 状态行配置界面 |

### 4.3 测试快照文件

位于 `codex-rs/tui/src/bottom_pane/snapshots/`：

- `footer_shortcuts_default.snap` - 默认快捷键提示
- `footer_mode_indicator_wide.snap` - 宽屏模式指示器
- `footer_status_line_*.snap` - 状态行各种场景
- `footer_collapse_*.snap` - 宽度自适应场景（在 chat_composer 测试中）

### 4.4 核心代码行号

```rust
// 数据结构定义
FooterProps:66-87
CollaborationModeIndicator:90-96
FooterMode:131-146

// 核心函数
single_line_footer_layout:310-472
footer_from_props_lines:580-631
render_footer_from_props:229-250
render_footer_line:213-220
render_context_right:529-554

// 快捷键相关
ShortcutId:862-875
DisplayCondition:889-896
SHORTCUTS:943-1057
shortcut_overlay_lines:750-799
build_columns:801-846

// 状态行相关
passive_footer_status_line:638-659
shows_passive_footer_line:665-673
uses_passive_footer_status_layout:680-682
context_window_line:848-860

// 工具函数
left_side_line:271-300
can_show_left_with_context:518-527
max_left_width_for_right:504-516
right_aligned_x:481-502
```

---

## 5. 依赖与外部交互

### 5.1 外部 crate 依赖

```rust
use crossterm::event::KeyCode;           // 键盘事件
use ratatui::buffer::Buffer;              // 渲染缓冲区
use ratatui::layout::Rect;                // 布局矩形
use ratatui::style::Stylize;              // 样式 trait
use ratatui::text::Line;                  // 文本行
use ratatui::text::Span;                  // 文本片段
use ratatui::widgets::Paragraph;          // 段落组件
use ratatui::widgets::Widget;             // Widget trait
```

### 5.2 内部模块依赖

```rust
use crate::key_hint;                      // 快捷键提示格式
use crate::key_hint::KeyBinding;          // 快捷键绑定
use crate::render::line_utils::prefix_lines;  // 行前缀工具
use crate::status::format_tokens_compact; // token 格式化
use crate::ui_consts::FOOTER_INDENT_COLS; // 缩进常量
```

### 5.3 与 ChatComposer 的交互

```rust
// chat_composer.rs 中构建 FooterProps
fn footer_props(&self) -> FooterProps {
    FooterProps {
        mode: self.footer_mode,
        esc_backtrack_hint: self.esc_backtrack_hint,
        use_shift_enter_hint: self.use_shift_enter_hint,
        is_task_running: self.is_task_running,
        collaboration_modes_enabled: self.collaboration_modes_enabled,
        is_wsl: self.is_wsl(),
        quit_shortcut_key: self.quit_shortcut_key,
        context_window_percent: self.context_window_percent,
        context_window_used_tokens: self.context_window_used_tokens,
        status_line_value: self.status_line_value.clone(),
        status_line_enabled: self.status_line_enabled,
        active_agent_label: self.active_agent_label.clone(),
    }
}
```

### 5.4 与 ChatWidget 的交互

```rust
// chatwidget.rs 中设置状态行
pub(crate) fn set_status_line(&mut self, status_line: Option<Line<'static>>) {
    self.bottom_pane.set_status_line(status_line);
}

// 设置 Agent 标签
pub(crate) fn set_active_agent_label(&mut self, active_agent_label: Option<String>) {
    self.bottom_pane.set_active_agent_label(active_agent_label);
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 宽度计算精度

**风险**：`single_line_footer_layout` 中的宽度计算依赖于 `Line::width()`，该函数返回的是显示宽度（考虑 Unicode 宽字符），但在某些极端情况下（如组合字符、零宽字符）可能与实际渲染宽度不一致。

**缓解**：测试覆盖了多种宽度场景，使用 snapshot 测试验证渲染结果。

#### 6.1.2 时间敏感的状态

**风险**：`QuitShortcutReminder` 和 `FooterFlash` 是时间敏感的状态，需要上层（ChatComposer/ChatWidget）调度重绘以确保提示过期后 UI 更新。

**缓解**：`BottomPane::show_quit_shortcut_hint` 中显式调度了 `QUIT_SHORTCUT_TIMEOUT` 后的重绘。

#### 6.1.3 WSL 检测

**风险**：`is_wsl` 标志影响快捷键显示（粘贴图片使用 `Ctrl+Alt+V` 而非 `Ctrl+V`），但检测可能不完全准确。

### 6.2 边界情况

#### 6.2.1 极窄终端

当终端宽度小于 20 列时：
- 左侧内容可能完全无法显示
- 右侧上下文信息会被隐藏
- 状态行会被截断（带省略号）

#### 6.2.2 状态行与模式指示器冲突

当 `status_line_enabled` 为 true 且存在 `CollaborationModeIndicator` 时：
- 状态行显示在左侧
- 模式指示器显示在右侧
- 状态行会被截断以保留模式指示器

#### 6.2.3 任务运行时的队列提示

当 `is_task_running=true` 且 `mode=ComposerHasDraft`：
- 显示 `Tab to queue message` 提示
- 此提示优先级高于其他所有左侧内容

### 6.3 改进建议

#### 6.3.1 代码组织

**建议**：将 `single_line_footer_layout` 中的复杂降级逻辑提取为独立的策略模式实现，提高可测试性。

```rust
// 建议的改进
trait FooterLayoutStrategy {
    fn select_layout(&self, available_width: u16) -> Option<LeftSideState>;
}

struct QueueHintStrategy { ... }
struct ModeOnlyStrategy { ... }
```

#### 6.3.2 性能优化

**建议**：缓存 `left_side_line` 的计算结果，避免在每次渲染时重复构建字符串。

#### 6.3.3 可访问性

**建议**：
- 为颜色编码的信息（如协作模式颜色）添加文本标识
- 考虑支持高对比度模式

#### 6.3.4 配置扩展

**建议**：当前 `status_line_enabled` 是布尔值，可考虑扩展为枚举以支持更多显示模式：

```rust
enum StatusLineMode {
    Disabled,
    Enabled,           // 当前行为
    Compact,           // 简化显示
    Full,              // 完整显示（包括更多字段）
}
```

#### 6.3.5 测试覆盖

**建议**：
- 添加更多边界宽度测试（如刚好能容纳/刚好不能容纳的临界值）
- 添加 Unicode 宽字符测试
- 添加多行状态行测试（当前假设状态行是单行）

### 6.4 技术债务

1. **`#[allow(dead_code)]`**：`CollaborationModeIndicator::PairProgramming` 和 `Execute` 被标记为 dead_code，未来 UI 重新启用时需要注意测试覆盖。

2. **硬编码常量**：`MODE_CYCLE_HINT`、`FOOTER_CONTEXT_GAP_COLS` 等常量在模块内硬编码，如果需要国际化或主题化，需要提取到配置中。

3. **平台特定代码**：WSL 检测逻辑分散在多个模块，建议集中到统一的平台检测模块。

---

## 7. 总结

`footer.rs` 是 Codex TUI 中一个设计良好的纯渲染模块，职责清晰，与上层状态管理解耦。其核心复杂度在于宽度自适应的降级逻辑，通过 `single_line_footer_layout` 函数实现了优雅的渐进式内容隐藏。

模块遵循了以下设计原则：
1. **单一职责**：只负责渲染，不维护状态
2. **渐进增强**：从完整显示逐步降级到最小显示
3. **可测试性**：通过 snapshot 测试覆盖各种场景
4. **可配置性**：支持自定义状态行和多种显示模式

未来的改进方向主要集中在代码组织优化、性能提升和可访问性增强。
