# Research: `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs`

## 1. 场景与职责

### 1.1 模块定位

`request_user_input/mod.rs` 是 Codex TUI（Terminal User Interface）中处理**用户输入请求**的核心状态机模块。它实现了 `BottomPaneView` trait，作为底部面板的模态覆盖层（overlay），用于向用户展示交互式问卷并收集答案。

### 1.2 核心场景

该模块处理以下业务场景：

1. **多问题问卷**：支持单个或多个问题的顺序回答，每个问题可以有选项或自由文本输入
2. **选项选择**：提供带描述的选项列表，支持数字快捷键（1-9）、方向键、Vim键（j/k）导航
3. **备注输入**：允许为选中的选项添加文本备注（notes），使用 `ChatComposer` 组件
4. **自由文本问题**：支持无选项的纯文本输入问题
5. **"其他"选项**：支持 `is_other` 标记的问题，自动添加 "None of the above" 选项
6. **未回答确认**：当用户尝试提交未回答的问题时，显示确认对话框
7. **请求队列**：支持多个输入请求的 FIFO 队列处理

### 1.3 架构位置

```
ChatWidget (主UI)
  └── BottomPane (底部面板)
       └── RequestUserInputOverlay (本模块)
            ├── layout.rs (布局计算)
            └── render.rs (渲染实现)
```

---

## 2. 功能点目的

### 2.1 主要功能组件

| 功能 | 目的 | 关键常量/配置 |
|------|------|--------------|
| 选项导航 | 让用户通过键盘选择选项 | `OTHER_OPTION_LABEL`, `OTHER_OPTION_DESCRIPTION` |
| 备注输入 | 为选项添加额外说明 | `NOTES_PLACEHOLDER`, `ANSWER_PLACEHOLDER` |
| 问题切换 | 在多问题间导航 | `←/→` 或 `Ctrl+P/Ctrl+N` |
| 提交确认 | 防止意外提交未回答的问题 | `UNANSWERED_CONFIRM_TITLE` |
| 焦点管理 | 在选项和备注间切换焦点 | `Focus` 枚举 |

### 2.2 交互设计原则

1. **快速输入**：在选项聚焦时直接输入字符不会进入备注，保持选择流程清晰
2. **Tab切换**：选中选项后按 Tab 进入备注输入，再次按 Tab 或 Esc 返回选项
3. **Enter提交**：在选项上按 Enter 提交当前答案并进入下一问题
4. **数字快捷键**：直接按数字键（1-9）选择对应选项并自动提交
5. **空答案处理**：自由文本问题允许空答案提交

---

## 3. 具体技术实现

### 3.1 核心数据结构

#### 3.1.1 焦点状态

```rust
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Focus {
    Options,  // 选项列表聚焦
    Notes,    // 备注输入聚焦
}
```

#### 3.1.2 答案状态

```rust
struct AnswerState {
    options_state: ScrollState,      // 选项滚动/选择状态
    draft: ComposerDraft,            // 备注草稿
    answer_committed: bool,          // 是否已提交答案
    notes_visible: bool,             // 备注UI是否可见
}
```

#### 3.1.3 草稿数据

```rust
#[derive(Default, Clone, PartialEq)]
struct ComposerDraft {
    text: String,                    // 文本内容
    text_elements: Vec<TextElement>, // 文本元素（如mention）
    local_image_paths: Vec<PathBuf>, // 本地图片路径
    pending_pastes: Vec<(String, String)>, // 待处理的粘贴内容
}
```

#### 3.1.4 主结构体

```rust
pub(crate) struct RequestUserInputOverlay {
    app_event_tx: AppEventSender,                    // 应用事件发送器
    request: RequestUserInputEvent,                  // 当前请求
    queue: VecDeque<RequestUserInputEvent>,          // 请求队列
    composer: ChatComposer,                          // 复用的聊天编辑器
    answers: Vec<AnswerState>,                       // 每个问题的答案状态
    current_idx: usize,                              // 当前问题索引
    focus: Focus,                                    // 当前焦点
    done: bool,                                      // 是否完成
    pending_submission_draft: Option<ComposerDraft>, // 待提交的草稿
    confirm_unanswered: Option<ScrollState>,         // 未回答确认对话框状态
}
```

### 3.2 关键流程

#### 3.2.1 初始化流程 (`new`)

1. 创建配置为纯文本模式的 `ChatComposer`（禁用弹窗、斜杠命令、图片附件）
2. 设置空的页脚提示覆盖
3. 调用 `reset_for_request()` 初始化答案状态
4. 调用 `ensure_focus_available()` 确保焦点有效
5. 调用 `restore_current_draft()` 恢复当前草稿

#### 3.2.2 答案提交流程 (`submit_answers`)

```rust
fn submit_answers(&mut self) {
    // 1. 关闭确认对话框
    // 2. 保存当前草稿
    // 3. 遍历所有问题构建答案映射
    //    - 对于有选项的问题：获取选中的选项标签
    //    - 对于所有问题：如果有备注则添加 "user_note: <text>"
    // 4. 发送 Op::UserInputAnswer 事件
    // 5. 发送 InsertHistoryCell 事件记录结果
    // 6. 处理队列中的下一个请求或标记完成
}
```

#### 3.2.3 键盘事件处理 (`handle_key_event`)

事件处理优先级：

1. **KeyRelease**：直接返回
2. **确认对话框激活**：路由到 `handle_confirm_unanswered_key_event`
3. **Esc键**：
   - 如果在备注模式且有选项：清除备注并返回选项
   - 否则：发送中断信号
4. **问题导航**：Ctrl+P/N 或 PageUp/Down 切换问题
5. **选项模式下的左右导航**：h/l 或 ←/→ 切换问题（仅在选项聚焦时）
6. **焦点特定处理**：
   - `Focus::Options`：处理选项导航、选择、Tab进入备注
   - `Focus::Notes`：处理文本输入、Tab返回选项

#### 3.2.4 布局计算流程 (`layout_sections`)

布局计算分为两种情况：

**有选项的问题** (`layout_with_options`):
1. 计算问题文本高度（带截断）
2. 计算选项区域高度（首选 vs 完整）
3. 分配页脚和进度条空间
4. 如果备注可见，分配备注区域
5. 调整间隔以优化空间使用

**无选项的问题** (`layout_without_options`):
1. 计算问题文本高度
2. 如果空间紧张，截断问题文本
3. 分配备注输入区域
4. 分配页脚和进度条空间

### 3.3 协议与命令

#### 3.3.1 输入协议类型（来自 `codex_protocol::request_user_input`）

```rust
// 请求事件
pub struct RequestUserInputEvent {
    pub call_id: String,                    // Responses API调用ID
    pub turn_id: String,                    // 所属Turn ID
    pub questions: Vec<RequestUserInputQuestion>,
}

// 问题定义
pub struct RequestUserInputQuestion {
    pub id: String,                         // 问题唯一ID
    pub header: String,                     // 标题
    pub question: String,                   // 问题文本
    pub is_other: bool,                     // 是否显示"其他"选项
    pub is_secret: bool,                    // 是否密码输入（掩码显示）
    pub options: Option<Vec<RequestUserInputQuestionOption>>,
}

// 选项定义
pub struct RequestUserInputQuestionOption {
    pub label: String,                      // 选项标签
    pub description: String,                // 选项描述
}

// 答案
pub struct RequestUserInputAnswer {
    pub answers: Vec<String>,               // 答案列表（选项标签 + 可选备注）
}

// 响应
pub struct RequestUserInputResponse {
    pub answers: HashMap<String, RequestUserInputAnswer>, // question_id -> answer
}
```

#### 3.3.2 输出命令

通过 `AppEventSender` 发送：

1. **`AppEvent::CodexOp(Op::UserInputAnswer { id, response })`**：提交用户答案
2. **`AppEvent::InsertHistoryCell(Box::new(RequestUserInputResultCell { ... }))`**：记录到历史

---

## 4. 关键代码路径与文件引用

### 4.1 模块内文件

| 文件 | 职责 | 关键函数/结构 |
|------|------|--------------|
| `mod.rs` | 状态机核心 | `RequestUserInputOverlay`, `handle_key_event`, `submit_answers` |
| `layout.rs` | 布局计算 | `layout_sections`, `LayoutPlan`, `OptionsLayoutArgs` |
| `render.rs` | 渲染实现 | `render_ui`, `render_unanswered_confirmation`, `Renderable` trait |

### 4.2 依赖文件

| 文件 | 依赖类型 | 用途 |
|------|---------|------|
| `../bottom_pane_view.rs` | Trait定义 | 实现 `BottomPaneView` trait |
| `../scroll_state.rs` | 状态管理 | `ScrollState` 用于选项滚动 |
| `../selection_popup_common.rs` | 渲染工具 | `GenericDisplayRow`, `render_menu_surface` |
| `../chat_composer.rs` | 组件复用 | `ChatComposer` 用于备注输入 |
| `../../history_cell.rs` | 历史记录 | `RequestUserInputResultCell` |
| `../../../protocol/src/request_user_input.rs` | 协议类型 | 请求/响应数据结构 |

### 4.3 调用链

```
# 请求入口
ChatWidget::handle_request_user_input
  └── BottomPane::push_user_input_request
       └── RequestUserInputOverlay::new

# 键盘处理
BottomPane::handle_key_event
  └── BottomPaneView::handle_key_event (dyn dispatch)
       └── RequestUserInputOverlay::handle_key_event
            ├── handle_confirm_unanswered_key_event (确认对话框)
            ├── move_question (问题导航)
            ├── select_current_option (选项选择)
            └── composer.handle_key_event (备注输入)

# 提交流程
RequestUserInputOverlay::submit_answers
  ├── AppEvent::CodexOp(Op::UserInputAnswer) → 发送到后端
  └── AppEvent::InsertHistoryCell → 记录到UI历史

# 渲染流程
Renderable::render (dyn dispatch)
  └── RequestUserInputOverlay::render_ui
       ├── render_menu_surface (背景)
       ├── layout_sections (布局计算)
       ├── render_rows_bottom_aligned (选项列表)
       ├── render_notes_input (备注输入框)
       └── footer_tip_lines (页脚提示)
```

---

## 5. 依赖与外部交互

### 5.1 外部依赖

```rust
// 协议层
codex_protocol::protocol::Op
codex_protocol::request_user_input::RequestUserInputAnswer
codex_protocol::request_user_input::RequestUserInputEvent
codex_protocol::request_user_input::RequestUserInputResponse
codex_protocol::user_input::TextElement

// UI框架
ratatui::buffer::Buffer
ratatui::layout::Rect
ratatui::style::Stylize
ratatui::text::Line
ratatui::widgets::Paragraph
ratatui::widgets::Widget

// 终端输入
crossterm::event::KeyCode
crossterm::event::KeyEvent
crossterm::event::KeyEventKind
crossterm::event::KeyModifiers

// 文本处理
textwrap::wrap
unicode_width::UnicodeWidthStr
```

### 5.2 与 ChatComposer 的集成

`RequestUserInputOverlay` 复用 `ChatComposer` 作为备注输入组件，但进行了特殊配置：

```rust
let mut composer = ChatComposer::new_with_config(
    has_input_focus,
    app_event_tx.clone(),
    enhanced_keys_supported,
    ANSWER_PLACEHOLDER.to_string(),
    disable_paste_burst,
    ChatComposerConfig::plain_text(), // 纯文本模式
);
composer.set_footer_hint_override(Some(Vec::new())); // 禁用默认页脚
```

### 5.3 与 BottomPaneView Trait 的交互

```rust
impl BottomPaneView for RequestUserInputOverlay {
    fn prefer_esc_to_handle_key_event(&self) -> bool { true } // Esc优先路由到handle_key_event
    fn handle_key_event(&mut self, key_event: KeyEvent) { ... }
    fn is_complete(&self) -> bool { self.done }
    fn on_ctrl_c(&mut self) -> CancellationEvent { ... }
    fn handle_paste(&mut self, pasted: String) -> bool { ... }
    fn flush_paste_burst_if_due(&mut self) -> bool { ... }
    fn is_in_paste_burst(&self) -> bool { ... }
    fn try_consume_user_input_request(&mut self, request: RequestUserInputEvent) -> Option<RequestUserInputEvent> {
        self.queue.push_back(request);
        None // 消费请求，加入队列
    }
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 中断处理不完整

代码中有多个 TODO 注释指出中断处理的问题：

```rust
// TODO: Emit interrupted request_user_input results (including committed answers)
// once core supports persisting them reliably without follow-up turn issues.
```

**风险**：用户按 Esc 中断时，已提交的部分答案不会被保存到历史记录中。

#### 6.1.2 数字快捷键限制

```rust
fn option_index_for_digit(&self, ch: char) -> Option<usize> {
    let digit = ch.to_digit(10)?;
    if digit == 0 { return None; } // 不支持0
    let idx = (digit - 1) as usize;
    (idx < self.options_len()).then_some(idx)
}
```

**风险**：仅支持1-9，对于超过9个选项的问题，数字10+无法通过快捷键选择。

#### 6.1.3 粘贴处理焦点切换

```rust
fn handle_paste(&mut self, pasted: String) -> bool {
    if matches!(self.focus, Focus::Options) {
        self.focus = Focus::Notes; // 自动切换到备注模式
    }
    ...
}
```

**风险**：在选项聚焦时粘贴内容会自动切换到备注模式，可能不符合用户预期。

### 6.2 边界情况

| 边界情况 | 处理逻辑 |
|---------|---------|
| 空问题列表 | `question_count() == 0` 时显示 "No questions" |
| 空间极度紧张 | `layout_without_options_tight` 截断问题文本 |
| 选项数量变化 | `clamp_selection` 确保选中索引在有效范围内 |
| 快速问题切换 | `save_current_draft` + `restore_current_draft` 保持每问题的草稿 |
| 大文本粘贴 | `pending_pastes` 机制处理异步粘贴内容 |

### 6.3 改进建议

#### 6.3.1 支持更多数字快捷键

```rust
// 建议：支持双数字（10-99）或字母快捷键
fn option_index_for_input(&self, input: &str) -> Option<usize> {
    // 支持 "10", "11" 等
    input.parse::<usize>().ok()
        .and_then(|n| if n > 0 { Some(n - 1) } else { None })
        .filter(|&idx| idx < self.options_len())
}
```

#### 6.3.2 完善中断处理

建议实现部分答案保存：

```rust
fn emit_interrupted_result(&mut self) {
    let partial_answers = self.build_partial_answers();
    self.app_event_tx.send(AppEvent::InsertHistoryCell(Box::new(
        history_cell::RequestUserInputResultCell {
            questions: self.request.questions.clone(),
            answers: partial_answers,
            interrupted: true, // 标记为中断
        }
    )));
}
```

#### 6.3.3 添加搜索/过滤功能

对于选项较多的问题，建议添加实时过滤：

```rust
fn filter_options(&self, query: &str) -> Vec<&GenericDisplayRow> {
    self.option_rows()
        .iter()
        .filter(|row| row.name.to_lowercase().contains(&query.to_lowercase()))
        .collect()
}
```

#### 6.3.4 优化布局计算

当前布局计算较为复杂，建议：

1. 将布局计算提取为独立的 `LayoutEngine` 结构
2. 添加布局缓存（当尺寸不变时复用）
3. 支持响应式布局（根据终端宽度调整选项显示方式）

#### 6.3.5 增强可访问性

1. 添加屏幕阅读器支持（通过 ANSI 转义序列）
2. 为选项添加快捷键提示（如 `Alt+1`, `Alt+2`）
3. 支持鼠标点击选择（通过 crossterm 的鼠标事件）

### 6.4 测试覆盖

当前测试覆盖良好，包括：

- 单元测试：~60个测试用例
- 快照测试：使用 `insta` 验证UI渲染
- 边界测试：空答案、大粘贴、多问题导航

**建议补充**：

1. 性能测试：大量选项（100+）的渲染性能
2. 并发测试：快速连续请求的处理
3. 可访问性测试：屏幕阅读器兼容性

---

## 7. 附录

### 7.1 相关快照文件

测试快照位于：`codex-rs/tui/src/bottom_pane/request_user_input/snapshots/`

- `request_user_input_options.snap` - 选项显示
- `request_user_input_options_notes_visible.snap` - 备注可见
- `request_user_input_freeform.snap` - 自由文本
- `request_user_input_unanswered_confirmation.snap` - 未回答确认
- 等共11个快照文件

### 7.2 配置常量

```rust
const NOTES_PLACEHOLDER: &str = "Add notes";
const ANSWER_PLACEHOLDER: &str = "Type your answer (optional)";
const MIN_COMPOSER_HEIGHT: u16 = 3;
const SELECT_OPTION_PLACEHOLDER: &str = "Select an option to add notes";
pub(super) const TIP_SEPARATOR: &str = " | ";
pub(super) const DESIRED_SPACERS_BETWEEN_SECTIONS: u16 = 2;
const OTHER_OPTION_LABEL: &str = "None of the above";
const OTHER_OPTION_DESCRIPTION: &str = "Optionally, add details in notes (tab).";
```

### 7.3 页脚提示规则

| 场景 | 提示内容 |
|------|---------|
| 选项已选，备注隐藏 | "tab to add notes" (高亮) |
| 选项已选，备注可见 | "tab or esc to clear notes" |
| 单问题 | "enter to submit answer" (高亮) |
| 最后问题 | "enter to submit all" (高亮) |
| 非最后问题 | "enter to submit answer" |
| 多问题（选项模式） | "←/→ to navigate questions" |
| 多问题（自由文本模式） | "ctrl + p / ctrl + n change question" |
| 常规 | "esc to interrupt" |
