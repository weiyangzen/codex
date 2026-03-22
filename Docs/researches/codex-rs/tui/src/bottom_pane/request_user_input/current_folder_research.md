# Research: codex-rs/tui/src/bottom_pane/request_user_input

## 1. 场景与职责

`request_user_input` 模块是 Codex TUI（Terminal User Interface）中负责**交互式用户输入收集**的核心组件。它实现了一个模态覆盖层（overlay），用于在 Agent 执行过程中向用户展示问题并收集答案。

### 1.1 核心场景

- **MCP 工具调用确认**: 当 Agent 调用需要用户确认的工具时，通过此 UI 收集用户决策
- **多步骤表单填写**: 支持多问题（multi-question）的向导式交互流程
- **选项选择 + 备注**: 用户可以选择预定义选项，同时添加自由文本备注
- **纯自由文本输入**: 支持无选项的开放式问题（freeform）
- **敏感信息输入**: 支持 `is_secret` 模式，输入内容以掩码（mask）显示

### 1.2 职责边界

| 职责 | 说明 |
|------|------|
| 问题展示 | 渲染问题标题、描述、选项列表 |
| 答案收集 | 管理选项选择状态和自由文本输入 |
| 导航控制 | 支持多问题间的导航（←/→ 或 Ctrl+P/Ctrl+N） |
| 提交确认 | 未回答问题时显示确认对话框 |
| 历史记录 | 将问答结果写入对话历史（HistoryCell） |
| 中断处理 | 支持 Esc 中断并发送 `Op::Interrupt` |

---

## 2. 功能点目的

### 2.1 主要功能特性

#### 2.1.1 双模式问题支持

```rust
// 有选项的问题（单选）
question_with_options("q1", "Pick one")

// 无选项的自由文本问题
question_without_options("q2", "Share details")
```

#### 2.1.2 选项 + 备注组合模式

- **Options 焦点模式**: 使用 ↑/↓ 或 j/k 导航选项，Space/Enter 选择
- **Notes 焦点模式**: Tab 键进入备注输入，支持完整 Composer 功能（粘贴、编辑等）
- 备注以 `"user_note: <text>"` 格式附加到答案中

#### 2.1.3 多问题导航

```rust
// 有选项时：←/→ 或 h/l 切换问题
KeyCode::Left | KeyCode::Char('h') => move_question(false)
KeyCode::Right | KeyCode::Char('l') => move_question(true)

// 自由文本时：Ctrl+P / Ctrl+N 切换问题
KeyCode::Char('p') with CONTROL => move_question(false)
KeyCode::Char('n') with CONTROL => move_question(true)
```

#### 2.1.4 未回答确认机制

当用户尝试提交但存在未回答问题时，显示确认对话框：
- **选项 1**: "Proceed" - 继续提交（允许未回答）
- **选项 2**: "Go back" - 返回第一个未回答的问题

#### 2.1.5 "None of the above" 支持

当问题设置 `is_other: true` 时，自动添加额外选项：
```rust
const OTHER_OPTION_LABEL: &str = "None of the above";
const OTHER_OPTION_DESCRIPTION: &str = "Optionally, add details in notes (tab).";
```

#### 2.1.6 敏感信息掩码

当 `is_secret: true` 时，Composer 使用掩码渲染：
```rust
if is_secret {
    self.composer.render_with_mask(area, buf, Some('*'));
}
```

---

## 3. 具体技术实现

### 3.1 核心数据结构

#### 3.1.1 RequestUserInputOverlay（主状态机）

```rust
pub(crate) struct RequestUserInputOverlay {
    app_event_tx: AppEventSender,
    request: RequestUserInputEvent,
    queue: VecDeque<RequestUserInputEvent>,  // 请求队列（FIFO）
    composer: ChatComposer,                   // 复用主输入组件
    answers: Vec<AnswerState>,               // 每个问题的答案状态
    current_idx: usize,                      // 当前问题索引
    focus: Focus,                            // Options vs Notes
    done: bool,
    pending_submission_draft: Option<ComposerDraft>,
    confirm_unanswered: Option<ScrollState>, // 确认对话框状态
}
```

#### 3.1.2 AnswerState（单问题状态）

```rust
struct AnswerState {
    options_state: ScrollState,      // 选项导航/高亮状态
    draft: ComposerDraft,            // 备注/自由文本草稿
    answer_committed: bool,          // 是否已提交答案
    notes_visible: bool,             // 备注 UI 是否可见
}
```

#### 3.1.3 ComposerDraft（草稿内容）

```rust
#[derive(Default, Clone, PartialEq)]
struct ComposerDraft {
    text: String,
    text_elements: Vec<TextElement>,
    local_image_paths: Vec<PathBuf>,
    pending_pastes: Vec<(String, String)>,  // 支持大粘贴缓冲
}
```

### 3.2 关键流程

#### 3.2.1 初始化流程

```rust
impl RequestUserInputOverlay {
    pub(crate) fn new(
        request: RequestUserInputEvent,
        app_event_tx: AppEventSender,
        has_input_focus: bool,
        enhanced_keys_supported: bool,
        disable_paste_burst: bool,
    ) -> Self {
        // 1. 创建专用 Composer（禁用 popups/slash-commands）
        let mut composer = ChatComposer::new_with_config(
            has_input_focus,
            app_event_tx.clone(),
            enhanced_keys_supported,
            ANSWER_PLACEHOLDER.to_string(),
            disable_paste_burst,
            ChatComposerConfig::plain_text(),  // 纯文本模式
        );
        composer.set_footer_hint_override(Some(Vec::new()));  // 自定义 footer
        
        // 2. 初始化答案状态数组
        overlay.reset_for_request();
        overlay.ensure_focus_available();
        overlay.restore_current_draft();
    }
}
```

#### 3.2.2 键盘事件处理流程

```rust
fn handle_key_event(&mut self, key_event: KeyEvent) {
    // 1. 忽略 Release 事件
    if key_event.kind == KeyEventKind::Release { return; }
    
    // 2. 确认对话框优先处理
    if self.confirm_unanswered_active() {
        return self.handle_confirm_unanswered_key_event(key_event);
    }
    
    // 3. Esc 处理（清除备注或中断）
    if matches!(key_event.code, KeyCode::Esc) {
        if self.has_options() && self.notes_ui_visible() {
            return self.clear_notes_and_focus_options();
        }
        self.app_event_tx.send(AppEvent::CodexOp(Op::Interrupt));
        self.done = true;
        return;
    }
    
    // 4. 问题导航（Ctrl+P/N, PageUp/Down, ←/→, h/l）
    // ...
    
    // 5. 根据焦点模式分发
    match self.focus {
        Focus::Options => self.handle_options_key_event(key_event),
        Focus::Notes => self.handle_notes_key_event(key_event),
    }
}
```

#### 3.2.3 答案提交流程

```rust
fn submit_answers(&mut self) {
    self.save_current_draft();
    let mut answers = HashMap::new();
    
    for (idx, question) in self.request.questions.iter().enumerate() {
        let answer_state = &self.answers[idx];
        
        // 提取选项选择
        let selected_idx = if has_options && answer_state.answer_committed {
            answer_state.options_state.selected_idx
        } else { None };
        
        // 提取备注（以 user_note: 前缀标识）
        let notes = if answer_state.answer_committed {
            answer_state.draft.text_with_pending().trim().to_string()
        } else { String::new() };
        
        // 构建答案列表
        let mut answer_list = selected_label.into_iter().collect::<Vec<_>>();
        if !notes.is_empty() {
            answer_list.push(format!("user_note: {notes}"));
        }
        
        answers.insert(question.id.clone(), RequestUserInputAnswer { answers: answer_list });
    }
    
    // 发送答案到核心
    self.app_event_tx.send(AppEvent::CodexOp(Op::UserInputAnswer { ... }));
    
    // 写入历史记录
    self.app_event_tx.send(AppEvent::InsertHistoryCell(Box::new(
        history_cell::RequestUserInputResultCell { ... }
    )));
    
    // 处理队列中的下一个请求
    if let Some(next) = self.queue.pop_front() {
        self.request = next;
        self.reset_for_request();
    } else {
        self.done = true;
    }
}
```

### 3.3 布局算法

#### 3.3.1 布局区域划分

```rust
struct LayoutSections {
    progress_area: Rect,      // 问题进度（Question 1/3）
    question_area: Rect,      // 问题文本
    options_area: Rect,       // 选项列表（可滚动）
    notes_area: Rect,         // 备注输入区
    footer_lines: u16,        // 底部提示行数
}
```

#### 3.3.2 自适应高度计算

```rust
fn layout_with_options_normal(&self, args: OptionsNormalArgs, options: OptionsHeights) -> LayoutPlan {
    // 1. 优先分配 footer + progress
    // 2. 根据 notes_visible 决定 spacer 策略
    // 3. 动态调整 options 高度
    // 4. 剩余空间分配给 notes
}
```

### 3.4 渲染实现

#### 3.4.1 选项行渲染

使用 `GenericDisplayRow` 和共享的 `selection_popup_common` 渲染器：

```rust
pub(super) fn option_rows(&self) -> Vec<GenericDisplayRow> {
    options.iter().enumerate().map(|(idx, opt)| {
        let prefix = if selected { '›' } else { ' ' };
        let number = idx + 1;
        GenericDisplayRow {
            name: format!("{prefix} {number}. {label}"),
            description: Some(opt.description.clone()),
            wrap_indent: Some(UnicodeWidthStr::width(prefix_label.as_str())),
            ..Default::default()
        }
    }).collect()
}
```

#### 3.4.2 底部提示渲染

```rust
fn footer_tips(&self) -> Vec<FooterTip> {
    let mut tips = Vec::new();
    
    // 动态提示：tab to add notes / tab or esc to clear notes
    if self.selected_option_index().is_some() && !notes_visible {
        tips.push(FooterTip::highlighted("tab to add notes"));
    }
    
    // 动态提示：enter to submit answer / enter to submit all
    let enter_tip = if is_last_question {
        FooterTip::highlighted("enter to submit all")
    } else {
        FooterTip::new("enter to submit answer")
    };
    
    // 导航提示：←/→ to navigate questions / ctrl + p / ctrl + n
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件

| 文件 | 职责 |
|------|------|
| `mod.rs` | 主状态机、事件处理、答案提交逻辑（~2900 行） |
| `layout.rs` | 自适应布局计算（~363 行） |
| `render.rs` | 渲染实现、光标位置计算（~582 行） |

### 4.2 协议定义

| 文件 | 职责 |
|------|------|
| `codex-rs/protocol/src/request_user_input.rs` | 协议数据结构（Event、Question、Answer、Response） |
| `codex-rs/app-server-protocol/schema/*/ToolRequestUserInput*.json` | JSON Schema 定义 |

### 4.3 调用方（上游）

| 文件 | 调用点 |
|------|--------|
| `codex-rs/tui/src/bottom_pane/mod.rs` | `push_user_input_request()` 创建并推送 overlay |
| `codex-rs/tui/src/chatwidget.rs` | 处理 `RequestUserInputEvent` 事件 |
| `codex-rs/core/src/mcp_tool_call.rs` | MCP 工具调用时构建 request_user_input 参数 |

### 4.4 被调用方（下游）

| 文件 | 调用点 |
|------|--------|
| `codex-rs/tui/src/bottom_pane/chat_composer.rs` | 复用 Composer 进行文本输入 |
| `codex-rs/tui/src/bottom_pane/selection_popup_common.rs` | 共享选项列表渲染 |
| `codex-rs/tui/src/bottom_pane/scroll_state.rs` | 滚动/选择状态管理 |
| `codex-rs/tui/src/history_cell.rs` | `RequestUserInputResultCell` 历史记录渲染 |

### 4.5 关键代码路径

```
用户按键
  ↓
BottomPane::handle_key_event() [mod.rs:369]
  ↓
RequestUserInputOverlay::handle_key_event() [mod.rs:993]
  ↓
  ├─ 确认对话框处理 [mod.rs:945-985]
  ├─ Esc 处理（清除备注/中断） [mod.rs:1003-1013]
  ├─ 问题导航 [mod.rs:1015-1076]
  └─ 焦点分发
       ├─ Options 模式 [mod.rs:1078-1136]
       │    ├─ ↑/↓/j/k: 选项导航
       │    ├─ Space: 选择当前选项
       │    ├─ Tab: 切换到 Notes 模式
       │    ├─ Enter: 提交并进入下一题
       │    └─ 数字键 1-9: 快速选择并提交
       └─ Notes 模式 [mod.rs:1138-1218]
            ├─ Tab/Backspace: 返回 Options 模式
            ├─ Enter: 提交备注并进入下一题
            └─ 其他: 转发到 Composer

提交答案
  ↓
RequestUserInputOverlay::submit_answers() [mod.rs:714-770]
  ↓
AppEvent::CodexOp(Op::UserInputAnswer { ... }) → 发送到核心
  ↓
AppEvent::InsertHistoryCell(RequestUserInputResultCell { ... }) → 历史记录
```

---

## 5. 依赖与外部交互

### 5.1 依赖模块

```rust
// 内部依赖
use crate::bottom_pane::ChatComposer;           // 文本输入组件
use crate::bottom_pane::scroll_state::ScrollState;  // 滚动状态
use crate::bottom_pane::selection_popup_common::GenericDisplayRow;  // 选项行渲染
use crate::history_cell;                         // 历史记录单元格
use crate::render::renderable::Renderable;       // 渲染 trait

// 协议依赖
use codex_protocol::protocol::Op;
use codex_protocol::request_user_input::{
    RequestUserInputAnswer,
    RequestUserInputEvent,
    RequestUserInputResponse,
};
use codex_protocol::user_input::TextElement;
```

### 5.2 外部交互

#### 5.2.1 与核心层交互

通过 `AppEventSender` 发送事件：
- `AppEvent::CodexOp(Op::UserInputAnswer { id, response })` - 提交答案
- `AppEvent::CodexOp(Op::Interrupt)` - 用户中断
- `AppEvent::InsertHistoryCell(...)` - 记录历史

#### 5.2.2 与 MCP 工具调用集成

```rust
// codex-rs/core/src/mcp_tool_call.rs
fn build_mcp_tool_approval_question(...) -> RequestUserInputQuestion {
    RequestUserInputQuestion {
        id: "mcp_tool_approval".to_string(),
        header: "Tool Approval".to_string(),
        question: format!("Allow {tool_name}?"),
        is_other: false,
        is_secret: false,
        options: Some(vec![
            RequestUserInputQuestionOption { label: "Allow".to_string(), ... },
            RequestUserInputQuestionOption { label: "Deny".to_string(), ... },
        ]),
    }
}
```

#### 5.2.3 与历史记录集成

```rust
// codex-rs/tui/src/history_cell.rs
pub(crate) struct RequestUserInputResultCell {
    pub(crate) questions: Vec<RequestUserInputQuestion>,
    pub(crate) answers: HashMap<String, RequestUserInputAnswer>,
    pub(crate) interrupted: bool,
}

impl HistoryCell for RequestUserInputResultCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
        // 渲染问答结果到对话历史
    }
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 中断时答案丢失

```rust
// TODO: Emit interrupted request_user_input results (including committed answers)
// once core supports persisting them reliably without follow-up turn issues.
```

当前实现：用户按 Esc 中断时，已提交的部分答案会丢失，仅发送 `Op::Interrupt`。

#### 6.1.2 粘贴内容过大

虽然支持 `pending_pastes` 缓冲，但超大粘贴可能导致：
- 内存占用增加
- 渲染延迟

#### 6.1.3 多请求队列竞争

```rust
fn try_consume_user_input_request(&mut self, request: RequestUserInputEvent) -> Option<RequestUserInputEvent> {
    self.queue.push_back(request);  // 简单 FIFO 队列
    None
}
```

队列机制简单，如果核心层同时发送多个请求，可能产生竞争条件。

### 6.2 边界条件

| 边界条件 | 处理策略 |
|----------|----------|
| 零问题请求 | 显示 "No questions"，直接完成 |
| 空选项列表 | 视为自由文本问题（`notes_visible = true`） |
| 终端高度不足 | 使用 `layout_without_options_tight` 截断问题文本 |
| 终端宽度不足 | Footer tips 自动换行，选项描述换行缩进 |
| 数字键超出现有选项 | 忽略（`option_index_for_digit` 返回 None） |
| 快速连续提交 | `answer_committed` 标志防止重复提交 |

### 6.3 改进建议

#### 6.3.1 中断恢复机制

实现部分答案持久化：
```rust
// 建议添加
fn emit_partial_answers_on_interrupt(&mut self) {
    let partial_answers = self.answers.iter()
        .filter(|a| a.answer_committed)
        .collect();
    self.app_event_tx.send(AppEvent::CodexOp(
        Op::UserInputPartialAnswer { ... }
    ));
}
```

#### 6.3.2 搜索/过滤支持

对于大量选项（>20），添加过滤搜索：
```rust
// 类似其他 selection popup
fn filter_options(&mut self, query: &str) -> Vec<GenericDisplayRow> {
    self.option_rows().into_iter()
        .filter(|row| row.name.contains(query))
        .collect()
}
```

#### 6.3.3 多选支持

当前仅支持单选，可扩展为多选模式：
```rust
enum SelectionMode {
    Single,
    Multiple { min: usize, max: usize },
}
```

#### 6.3.4 验证反馈

添加输入验证和实时反馈：
```rust
fn validate_answer(&self, question: &RequestUserInputQuestion, answer: &AnswerState) -> ValidationResult {
    // 必填验证、格式验证等
}
```

#### 6.3.5 键盘快捷键可配置

当前快捷键硬编码，建议支持配置：
```rust
struct RequestUserInputKeymap {
    next_question: KeyBinding,
    prev_question: KeyBinding,
    submit: KeyBinding,
    // ...
}
```

---

## 7. 测试覆盖

模块包含全面的快照测试（snapshot tests）：

| 测试名称 | 覆盖场景 |
|----------|----------|
| `request_user_input_options` | 基础选项展示 |
| `request_user_input_options_notes_visible` | 备注区域可见 |
| `request_user_input_tight_height` | 紧凑高度布局 |
| `request_user_input_wrapped_options` | 长文本换行 |
| `request_user_input_long_option_text` | 超长选项文本 |
| `request_user_input_scrolling_options` | 选项滚动 |
| `request_user_input_hidden_options_footer` | 选项被截断提示 |
| `request_user_input_freeform` | 自由文本模式 |
| `request_user_input_multi_question_first` | 多问题首题 |
| `request_user_input_multi_question_last` | 多问题末题 |
| `request_user_input_unanswered_confirmation` | 未回答确认对话框 |
| `request_user_input_footer_wrap` | Footer 换行 |

---

## 8. 总结

`request_user_input` 模块是 Codex TUI 中一个**功能完整、设计精良**的交互组件。它通过复用 `ChatComposer` 实现了与主输入框一致的用户体验，同时通过独立的布局算法和状态管理支持复杂的多问题表单场景。

核心设计亮点：
1. **复用而非重写**: 复用 `ChatComposer` 处理文本输入，保持一致性
2. **清晰的焦点分离**: Options 和 Notes 两种焦点模式，避免状态混乱
3. **完善的边界处理**: 对终端尺寸、输入边界、提交状态都有细致处理
4. **队列支持**: 支持多请求排队，避免并发冲突
5. **丰富的测试**: 12 个快照测试覆盖主要 UI 场景

主要改进空间：
1. 中断时的部分答案持久化
2. 大量选项时的搜索过滤
3. 多选模式支持
4. 键盘快捷键可配置
