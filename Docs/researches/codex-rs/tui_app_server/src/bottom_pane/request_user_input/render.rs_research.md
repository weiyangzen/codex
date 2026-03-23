# Research: `codex-rs/tui_app_server/src/bottom_pane/request_user_input/render.rs`

## 1. 场景与职责

### 1.1 模块定位

`render.rs` 是 `tui_app_server` crate 中 `request_user_input` 模块的渲染子模块，负责实现用户输入请求弹窗的终端 UI 渲染逻辑。该文件与 `mod.rs`（状态机与输入处理）和 `layout.rs`（布局计算）共同构成完整的用户输入交互组件。

### 1.2 核心职责

- **Renderable Trait 实现**: 为 `RequestUserInputOverlay` 实现 `Renderable` trait，提供 `desired_height()`、`render()` 和 `cursor_pos()` 三个核心方法
- **双模式渲染**: 支持正常问答模式与"未回答问题确认"模式两种 UI 渲染路径
- **复杂布局渲染**: 处理进度指示器、问题文本、选项列表、备注输入框、页脚提示等多区域协调渲染
- **光标管理**: 计算并返回文本输入光标的屏幕坐标位置

### 1.3 业务场景

当 Agent 需要向用户收集结构化输入时（如多选题、开放式问答），通过 MCP 工具调用触发 `RequestUserInputEvent`，此时 TUI 会弹出该覆盖层，支持：
- 单选/多选问题的选项展示与选择
- 每个问题附加备注（notes）的输入
- 多问题间的导航与批量提交
- 未回答问题确认机制

---

## 2. 功能点目的

### 2.1 高度计算 (`desired_height`)

**目的**: 在渲染前计算组件所需的最小高度，供父级布局系统分配空间。

**逻辑要点**:
- 区分"未回答确认模式"与正常模式
- 正常模式下累加：问题高度 + 选项高度 + 间距 + 备注高度 + 页脚高度 + 进度行高度 + 菜单内边距
- 使用 `MIN_OVERLAY_HEIGHT = 8` 保证最小显示区域

### 2.2 主渲染逻辑 (`render_ui`)

**目的**: 将完整的问答界面绘制到终端缓冲区。

**渲染区域（从上到下）**:
1. **进度行**: 显示 "Question {idx}/{total}" 及未回答计数
2. **问题文本**: 自动换行的问题描述，已回答显示默认色，未回答显示青色
3. **选项列表**: 带选择标记的选项，支持底部对齐渲染 (`render_rows_bottom_aligned`)
4. **备注输入区**: 复用 `ChatComposer` 的渲染逻辑，支持密码掩码（`is_secret`）
5. **页脚提示**: 动态生成的操作提示，支持溢出截断与省略号

### 2.3 未回答确认模式 (`render_unanswered_confirmation`)

**目的**: 当用户尝试提交但存在未回答问题时，显示确认对话框。

**UI 结构**:
- 标题: "Submit with unanswered questions?"
- 副标题: 显示未回答问题数量
- 选项行: "Proceed"（提交）与 "Go back"（返回）
- 标准提示行: Enter 确认 / Esc 返回

### 2.4 光标定位 (`cursor_pos_impl`)

**目的**: 返回文本输入光标的屏幕坐标，供终端设置光标位置。

**逻辑**:
- 仅在焦点在备注区且备注可见时返回位置
- 委托给 `ChatComposer::cursor_pos()` 计算实际坐标

---

## 3. 具体技术实现

### 3.1 关键数据结构

```rust
// 未回答确认模式的数据准备
struct UnansweredConfirmationData {
    title_line: Line<'static>,      // 标题行（加粗）
    subtitle_line: Line<'static>,   // 副标题（dim 样式）
    hint_line: Line<'static>,       // 标准提示
    rows: Vec<GenericDisplayRow>,   // 选项行数据
    state: ScrollState,             // 滚动/选择状态
}

struct UnansweredConfirmationLayout {
    header_lines: Vec<Line<'static>>,
    hint_lines: Vec<Line<'static>>,
    rows: Vec<GenericDisplayRow>,
    state: ScrollState,
}
```

### 3.2 核心渲染流程

```rust
impl Renderable for RequestUserInputOverlay {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        self.render_ui(area, buf);
    }
}

impl RequestUserInputOverlay {
    pub(super) fn render_ui(&self, area: Rect, buf: &mut Buffer) {
        // 1. 检查未回答确认模式
        if self.confirm_unanswered_active() {
            return self.render_unanswered_confirmation(area, buf);
        }
        
        // 2. 渲染菜单表面（背景）
        let content_area = render_menu_surface(area, buf);
        
        // 3. 计算布局分区
        let sections = self.layout_sections(content_area);
        
        // 4. 依次渲染各区域
        // 4.1 进度行
        // 4.2 问题文本（带颜色区分已/未回答）
        // 4.3 选项列表（底部对齐）
        // 4.4 备注输入框
        // 4.5 页脚提示
    }
}
```

### 3.3 底部对齐选项渲染

```rust
fn render_rows_bottom_aligned(
    area: Rect,
    buf: &mut Buffer,
    rows: &[GenericDisplayRow],
    state: &ScrollState,
    max_results: usize,
    empty_message: &str,
)
```

**实现技巧**:
- 使用临时 `Buffer` 预渲染内容
- 计算实际渲染高度与可用高度的差值作为 y 偏移
- 将预渲染内容复制到目标区域，实现底部对齐效果

### 3.4 智能文本截断

```rust
fn truncate_line_word_boundary_with_ellipsis(
    line: Line<'static>,
    max_width: usize,
) -> Line<'static>
```

**算法**:
1. 遍历所有 span 的字符，计算显示宽度
2. 记录最后一个适合的位置（`last_fit`）和最后一个词边界（`last_word_break`）
3. 溢出时优先在词边界截断，否则在字符边界截断
4. 移除尾部空白，追加省略号（样式与最后可见 span 一致）

### 3.5 样式应用规范

遵循项目 `styles.md` 规范：
- 使用 `Stylize` trait 的辅助方法：`.dim()`, `.cyan()`, `.bold()`, `.red()` 等
- 避免硬编码白色（`.white()`）
- 优先使用 `"text".into()` 创建简单 span
- 使用 `vec![...].into()` 创建 Line

---

## 4. 关键代码路径与文件引用

### 4.1 模块依赖图

```
render.rs
├── mod.rs (RequestUserInputOverlay 定义与状态管理)
├── layout.rs (LayoutSections, layout_plan 计算)
├── ../selection_popup_common.rs
│   ├── GenericDisplayRow (选项行数据结构)
│   ├── render_menu_surface() (菜单背景渲染)
│   ├── render_rows() (通用行列表渲染)
│   ├── measure_rows_height() (高度测量)
│   └── wrap_styled_line() (样式保持换行)
├── ../popup_consts.rs
│   └── standard_popup_hint_line() (标准提示)
├── ../scroll_state.rs
│   └── ScrollState (选择/滚动状态)
├── ../../render/renderable.rs
│   └── Renderable trait
└── ../chat_composer.rs
    └── ChatComposer (备注输入框复用)
```

### 4.2 关键文件路径

| 文件 | 职责 |
|------|------|
| `codex-rs/tui_app_server/src/bottom_pane/request_user_input/render.rs` | 本文件，渲染实现 |
| `codex-rs/tui_app_server/src/bottom_pane/request_user_input/mod.rs` | 状态机、输入处理、测试 |
| `codex-rs/tui_app_server/src/bottom_pane/request_user_input/layout.rs` | 布局计算 |
| `codex-rs/tui_app_server/src/bottom_pane/selection_popup_common.rs` | 通用选择列表渲染工具 |
| `codex-rs/tui_app_server/src/bottom_pane/popup_consts.rs` | 弹窗常量 |
| `codex-rs/tui_app_server/src/bottom_pane/scroll_state.rs` | 滚动状态管理 |
| `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs` | 聊天输入组件（被复用） |
| `codex-rs/tui_app_server/src/bottom_pane/bottom_pane_view.rs` | BottomPaneView trait 定义 |
| `codex-rs/protocol/src/request_user_input.rs` | 协议数据结构 |

### 4.3 外部协议依赖

```rust
// codex-protocol crate
codex_protocol::request_user_input::RequestUserInputEvent
codex_protocol::request_user_input::RequestUserInputQuestion
codex_protocol::request_user_input::RequestUserInputQuestionOption
codex_protocol::request_user_input::RequestUserInputAnswer
codex_protocol::request_user_input::RequestUserInputResponse
```

---

## 5. 依赖与外部交互

### 5.1 第三方依赖

| Crate | 用途 |
|-------|------|
| `ratatui` | 终端 UI 渲染核心（Buffer, Rect, Line, Span, Paragraph, Widget） |
| `unicode-width` | 字符宽度计算（UnicodeWidthChar, UnicodeWidthStr） |
| `textwrap` | 文本自动换行 |

### 5.2 内部模块交互

**与 `mod.rs` 的交互**:
- 读取 `RequestUserInputOverlay` 的状态字段（`current_idx`, `answers`, `composer`, `confirm_unanswered` 等）
- 调用方法：`has_options()`, `notes_ui_visible()`, `option_rows()`, `footer_tip_lines()` 等

**与 `layout.rs` 的交互**:
- 调用 `layout_sections()` 获取各区域 Rect 分配

**与 `selection_popup_common.rs` 的交互**:
- 调用 `render_menu_surface()` 绘制菜单背景
- 调用 `render_rows()` 渲染选项列表
- 调用 `measure_rows_height()` 计算选项高度
- 使用 `GenericDisplayRow` 作为选项数据载体

**与 `ChatComposer` 的交互**:
- 调用 `render()` / `render_with_mask()` 渲染备注输入框
- 调用 `cursor_pos()` 获取光标位置

### 5.3 事件输出

通过 `AppEventSender` 发送事件（在 `mod.rs` 中实现）：
```rust
// 提交答案
app_event_tx.user_input_answer(turn_id, RequestUserInputResponse { answers });
app_event_tx.send(AppEvent::InsertHistoryCell(...));

// 中断请求
app_event_tx.interrupt();
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 高度计算与渲染不一致
- **风险**: `desired_height()` 与 `render_ui()` 中的高度计算逻辑分散，可能导致父级分配空间与实际渲染需求不匹配
- **缓解**: 两者共享 `layout_sections()` 和 `options_required_height()` 等辅助方法，但仍需人工保持同步

#### 6.1.2 宽字符处理
- **风险**: `truncate_line_word_boundary_with_ellipsis` 中手动遍历字符计算宽度，可能对某些 Unicode 组合字符处理不当
- **代码位置**: 第 514-531 行的字符遍历逻辑

#### 6.1.3 临时 Buffer 复制开销
- **风险**: `render_rows_bottom_aligned` 创建临时 Buffer 并逐 cell 复制，在大量选项时可能影响性能
- **代码位置**: 第 451-473 行

### 6.2 边界情况

| 场景 | 处理逻辑 |
|------|----------|
| 区域宽度/高度为 0 | 多处早期返回（第 249-251, 259-261, 414-416, 447-449 行） |
| 空选项列表 | 显示 "No options" 占位符 |
| 超长选项文本 | `wrap_row_lines()` 自动换行，支持缩进对齐 |
| 页脚提示溢出 | `truncate_line_word_boundary_with_ellipsis` 截断并加省略号 |
| 秘密输入 | 通过 `is_secret` 标志使用 `render_with_mask('*')` |

### 6.3 改进建议

#### 6.3.1 架构层面
1. **统一高度计算**: 考虑将 `desired_height` 实现委托给 `layout.rs` 的单一入口，消除分散计算
2. **渲染缓存**: 对于静态内容（如选项行）可考虑缓存渲染结果，避免每帧重新计算

#### 6.3.2 代码层面
1. **魔法值提取**: 第 26-29 行的常量（`MIN_OVERLAY_HEIGHT`, `PROGRESS_ROW_HEIGHT` 等）已定义良好，但部分局部魔法值（如第 207 行的 `+ 1` 间距）可增加注释说明
2. **错误处理**: 多处使用 `unwrap_or(0)` 或 `unwrap_or_default()`，在极端情况下可能导致静默失败，建议增加 debug_assert

#### 6.3.3 测试覆盖
- 当前测试集中在 `mod.rs`，建议将渲染相关测试（如快照测试）明确归属到 `render.rs` 的测试模块
- 考虑增加边界情况测试：
  - 极窄终端宽度（< 10 列）
  - 极多选项（> 100 个）的性能表现
  - 包含控制字符的问题文本渲染

#### 6.3.4 可访问性
- 当前依赖颜色区分已/未回答状态（青色 vs 默认色），建议增加文本标记（如 `[ ]` / `[x]`）支持色盲用户

### 6.4 相关 TODO（代码中发现）

在 `mod.rs` 中发现相关 TODO，虽不直接属于本文件但影响整体功能：
```rust
// TODO: Emit interrupted request_user_input results (including committed answers)
// once core supports persisting them reliably without follow-up turn issues.
```

这表明中断时的部分提交结果持久化功能尚未完全实现。

---

## 7. 附录：代码统计

- **文件行数**: 582 行
- **主要结构体**: 2 个（`UnansweredConfirmationData`, `UnansweredConfirmationLayout`）
- **主要函数**: 10+ 个（`desired_height`, `render_ui`, `render_unanswered_confirmation`, `cursor_pos_impl`, `render_notes_input`, `render_rows_bottom_aligned`, `truncate_line_word_boundary_with_ellipsis` 等）
- **依赖模块**: 8+ 个

---

*研究文档生成时间: 2026-03-23*
*基于 commit: 当前工作目录状态*
