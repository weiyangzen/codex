# RequestUserInputOverlay 深度研究文档

## 1. 场景与职责

### 1.1 功能定位

`RequestUserInputOverlay` 是 Codex TUI 应用服务器 (`tui_app_server`) 中负责处理**用户输入请求**的核心 UI 组件。它实现了一个模态覆盖层（modal overlay），用于向用户展示结构化问题并收集答案。

该组件位于 `bottom_pane` 模块中，作为 `BottomPaneView` trait 的实现者，与 `ApprovalOverlay`、`McpServerElicitationOverlay` 等并列为底部面板的模态视图。

### 1.2 核心使用场景

1. **Agent 向用户提问**：当 Codex Agent 需要向用户询问决策信息时（例如选择代码重构策略、确认执行计划等），通过 `request_user_input` 工具调用触发
2. **多问题向导**：支持一次性展示多个相关问题，用户按顺序回答
3. **选项选择 + 备注**：每个问题可以是：
   - 纯选项选择（单选）
   - 纯自由文本输入
   - 选项选择 + 可添加备注

### 1.3 架构位置

```
ChatWidget (主 UI 容器)
  └── BottomPane (底部面板)
       └── view_stack: Vec<Box<dyn BottomPaneView>>
            └── RequestUserInputOverlay (本组件)
                 ├── layout.rs  (布局计算)
                 └── render.rs  (渲染实现)
```

---

## 2. 功能点目的

### 2.1 核心功能清单

| 功能 | 目的 | 用户价值 |
|------|------|----------|
| **选项导航** | 通过 ↑/↓ 或 j/k 在选项间移动 | 快速浏览可选答案 |
| **数字快捷键** | 按 1-9 直接选择对应选项 | 高效选择，无需多次按键 |
| **备注输入** | Tab 键进入备注编辑模式 | 为选项添加补充说明 |
| **问题间导航** | ←/→ 或 Ctrl+P/Ctrl+N 切换问题 | 在多问题表单中自由移动 |
| **未回答确认** | 提交时检测未回答问题，显示确认对话框 | 防止意外提交不完整答案 |
| **队列处理** | 支持多个输入请求排队 | 连续处理多个 Agent 提问 |
| **粘贴支持** | 支持大段文本粘贴到备注 | 方便输入复杂内容 |
| **密文输入** | 支持 `is_secret` 问题的密码掩码 | 保护敏感信息 |

### 2.2 交互设计原则

根据代码注释，该组件遵循以下 UX 原则：

1. **快速输入**：在选项焦点时直接打字自动跳转到备注输入
2. **明确提交**：Enter 键提交当前问题答案，最后一个问题提交全部
3. **自由形式**：纯文本问题允许空答案提交
4. **可中断**：Esc 键可随时中断整个输入流程

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 核心状态结构

```rust
pub(crate) struct RequestUserInputOverlay {
    app_event_tx: AppEventSender,                    // 应用事件发送器
    request: RequestUserInputEvent,                  // 当前请求
    queue: VecDeque<RequestUserInputEvent>,         // 请求队列
    composer: ChatComposer,                          // 复用的聊天编辑器
    answers: Vec<AnswerState>,                       // 每个问题的答案状态
    current_idx: usize,                              // 当前问题索引
    focus: Focus,                                    // 焦点位置 (Options/Notes)
    done: bool,                                      // 是否完成
    pending_submission_draft: Option<ComposerDraft>, // 待提交的草稿
    confirm_unanswered: Option<ScrollState>,        // 未回答确认对话框状态
}
```

#### 3.1.2 答案状态

```rust
struct AnswerState {
    options_state: ScrollState,      // 选项滚动/选择状态
    draft: ComposerDraft,            // 备注草稿
    answer_committed: bool,          // 是否已明确提交
    notes_visible: bool,             // 备注 UI 是否可见
}

#[derive(Default, Clone, PartialEq)]
struct ComposerDraft {
    text: String,
    text_elements: Vec<TextElement>,
    local_image_paths: Vec<PathBuf>,
    pending_pastes: Vec<(String, String)>, // (placeholder, content)
}
```

#### 3.1.3 焦点枚举

```rust
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Focus {
    Options,  // 选项列表焦点
    Notes,    // 备注输入焦点
}
```

### 3.2 关键流程

#### 3.2.1 初始化流程 (`new`)

```rust
pub(crate) fn new(
    request: RequestUserInputEvent,
    app_event_tx: AppEventSender,
    has_input_focus: bool,
    enhanced_keys_supported: bool,
    disable_paste_burst: bool,
) -> Self {
    // 1. 创建专用的 ChatComposer（禁用 popup/slash-command）
    let mut composer = ChatComposer::new_with_config(
        has_input_focus,
        app_event_tx.clone(),
        enhanced_keys_supported,
        ANSWER_PLACEHOLDER.to_string(),
        disable_paste_burst,
        ChatComposerConfig::plain_text(),  // 纯文本模式
    );
    composer.set_footer_hint_override(Some(Vec::new())); // 自定义 footer
    
    // 2. 初始化 overlay 状态
    // 3. 调用 reset_for_request() 初始化 answers 数组
    // 4. 确保焦点可用性
    // 5. 恢复当前草稿
}
```

#### 3.2.2 答案提交流程 (`submit_answers`)

```rust
fn submit_answers(&mut self) {
    // 1. 关闭未回答确认对话框
    // 2. 保存当前草稿
    // 3. 遍历所有问题构建答案映射
    let mut answers = HashMap::new();
    for (idx, question) in self.request.questions.iter().enumerate() {
        let answer_state = &self.answers[idx];
        
        // 确定选项选择
        let selected_idx = if 有选项且已提交 {
            answer_state.options_state.selected_idx
        } else { None };
        
        // 获取备注文本
        let notes = if answer_state.answer_committed {
            answer_state.draft.text_with_pending().trim().to_string()
        } else { String::new() };
        
        // 构建答案列表
        let selected_label = selected_idx.and_then(|idx| 获取选项标签);
        let mut answer_list = selected_label.into_iter().collect::<Vec<_>>();
        if !notes.is_empty() {
            answer_list.push(format!("user_note: {notes}"));
        }
        
        answers.insert(question.id.clone(), RequestUserInputAnswer { answers: answer_list });
    }
    
    // 4. 发送 UserInputAnswer Op
    self.app_event_tx.user_input_answer(self.request.turn_id.clone(), RequestUserInputResponse { answers });
    
    // 5. 插入历史记录单元格
    self.app_event_tx.send(AppEvent::InsertHistoryCell(...));
    
    // 6. 处理队列中的下一个请求或标记完成
    if let Some(next) = self.queue.pop_front() {
        self.request = next;
        self.reset_for_request();
    } else {
        self.done = true;
    }
}
```

#### 3.2.3 键盘事件处理流程 (`handle_key_event`)

```rust
fn handle_key_event(&mut self, key_event: KeyEvent) {
    // 1. 忽略 Release 事件
    // 2. 如果未回答确认对话框激活，路由到专用处理器
    if self.confirm_unanswered_active() {
        self.handle_confirm_unanswered_key_event(key_event);
        return;
    }
    
    // 3. Esc 键处理
    if matches!(key_event.code, KeyCode::Esc) {
        if 有选项 && 备注可见 {
            self.clear_notes_and_focus_options(); // 清除备注返回选项
            return;
        }
        // 否则中断并退出
        self.app_event_tx.interrupt();
        self.done = true;
        return;
    }
    
    // 4. 问题导航（Ctrl+P/N, PageUp/Down, ←/→, h/l）
    // 5. 根据焦点路由到选项或备注处理器
    match self.focus {
        Focus::Options => { /* 选项导航逻辑 */ }
        Focus::Notes => { /* 备注编辑逻辑 */ }
    }
}
```

#### 3.2.4 布局计算流程 (`layout_sections`)

布局计算分为两种情况：

**有选项的问题** (`layout_with_options`):
```
可用空间分配优先级：
1. 问题文本 (question_height)
2. 选项列表 (options_height)
3. 进度指示器 (progress_height = 1)
4. 备注输入 (notes_height) - 仅当 notes_visible 时
5. Footer 提示 (footer_lines)
6. 间隔 (spacers)
```

**无选项的问题** (`layout_without_options`):
```
可用空间分配：
1. 问题文本
2. 备注输入（作为主要输入区域）
3. Footer 提示
4. 进度指示器
```

### 3.3 协议与数据模型

#### 3.3.1 协议类型定义

来自 `codex_protocol::request_user_input`:

```rust
// 问题定义
pub struct RequestUserInputQuestion {
    pub id: String,
    pub header: String,
    pub question: String,
    pub is_other: bool,           // 是否显示"None of the above"选项
    pub is_secret: bool,          // 是否密码输入（掩码显示）
    pub options: Option<Vec<RequestUserInputQuestionOption>>,
}

pub struct RequestUserInputQuestionOption {
    pub label: String,            // 选项标签（提交值）
    pub description: String,      // 选项描述（UI 展示）
}

// 事件请求
pub struct RequestUserInputEvent {
    pub call_id: String,          // Responses API 调用 ID
    pub turn_id: String,          // 所属 Turn ID
    pub questions: Vec<RequestUserInputQuestion>,
}

// 答案响应
pub struct RequestUserInputAnswer {
    pub answers: Vec<String>,     // 答案列表（选项标签 + 可选 user_note）
}

pub struct RequestUserInputResponse {
    pub answers: HashMap<String, RequestUserInputAnswer>, // question.id -> answer
}
```

#### 3.3.2 与 Core 的交互

通过 `AppEventSender` 发送 `Op::UserInputAnswer`:

```rust
// AppEventSender::user_input_answer
pub(crate) fn user_input_answer(&self, id: String, response: RequestUserInputResponse) {
    self.send(AppEvent::CodexOp(
        AppCommand::user_input_answer(id, response).into_core()
    ));
}

// 最终转换为 Op::UserInputAnswer
pub(crate) fn user_input_answer(id: String, response: RequestUserInputResponse) -> Self {
    Self(Op::UserInputAnswer { id, response })
}
```

### 3.4 渲染实现

渲染代码位于 `render.rs`，主要实现：

1. **`render_ui`**：主渲染函数
   - 渲染菜单背景 (`render_menu_surface`)
   - 渲染进度指示器 ("Question 1/3 (1 unanswered)")
   - 渲染问题文本（支持自动换行）
   - 渲染选项列表（底对齐，支持滚动）
   - 渲染备注输入区（复用 `ChatComposer`）
   - 渲染 Footer 提示

2. **`render_rows_bottom_aligned`**：选项列表底对齐渲染
   - 保持 Footer 间距稳定
   - 确保选中项可见

3. **`render_unanswered_confirmation`**：未回答确认对话框
   - 标题："Submit with unanswered questions?"
   - 选项："Proceed" / "Go back"
   - 标准弹出提示样式

4. **`truncate_line_word_boundary_with_ellipsis`**：智能截断
   - 优先在单词边界截断
   - 添加省略号
   - 保留样式信息

---

## 4. 关键代码路径与文件引用

### 4.1 主要文件结构

```
codex-rs/tui_app_server/src/bottom_pane/request_user_input/
├── mod.rs      (主实现，约 2900 行，含测试)
├── layout.rs   (布局计算，约 360 行)
└── render.rs   (渲染实现，约 580 行)
```

### 4.2 关键代码路径

| 功能 | 文件 | 函数/行号 |
|------|------|----------|
| 组件初始化 | `mod.rs` | `impl RequestUserInputOverlay::new` (L140-175) |
| 答案提交 | `mod.rs` | `submit_answers` (L715-770) |
| 键盘处理 | `mod.rs` | `handle_key_event` (L993-1219) |
| 选项导航 | `mod.rs` | Focus::Options 分支 (L1078-1136) |
| 备注编辑 | `mod.rs` | Focus::Notes 分支 (L1138-1217) |
| 未回答确认 | `mod.rs` | `handle_confirm_unanswered_key_event` (L945-985) |
| 布局计算 | `layout.rs` | `layout_sections` (L19-60) |
| 渲染主入口 | `render.rs` | `render_ui` (L248-384) |
| 选项渲染 | `render.rs` | `render_rows_bottom_aligned` (L439-474) |
| 高度计算 | `render.rs` | `desired_height` (L62-105) |

### 4.3 依赖文件

| 依赖 | 路径 | 用途 |
|------|------|------|
| `BottomPaneView` trait | `../bottom_pane_view.rs` | 视图接口定义 |
| `ChatComposer` | `../chat_composer.rs` | 文本输入组件 |
| `ScrollState` | `../scroll_state.rs` | 滚动状态管理 |
| `GenericDisplayRow` | `../selection_popup_common.rs` | 通用行渲染 |
| `AppEventSender` | `../../app_event_sender.rs` | 事件发送 |
| 协议类型 | `codex_protocol::request_user_input` | 数据结构定义 |
| `history_cell` | `../../history_cell.rs` | 历史记录单元格 |

---

## 5. 依赖与外部交互

### 5.1 输入依赖

1. **`RequestUserInputEvent`**：来自 Core 层的用户输入请求事件
   - 通过 `BottomPane::push_user_input_request` 方法入栈

2. **键盘事件**：来自终端输入
   - 通过 `BottomPaneView::handle_key_event` 接口接收

3. **粘贴事件**：来自系统剪贴板
   - 通过 `BottomPaneView::handle_paste` 接口接收

### 5.2 输出交互

1. **答案提交**：
   ```rust
   app_event_tx.user_input_answer(turn_id, response)
   ```
   发送 `Op::UserInputAnswer` 到 Core 层

2. **历史记录**：
   ```rust
   app_event_tx.send(AppEvent::InsertHistoryCell(...))
   ```
   插入 `RequestUserInputResultCell` 到对话历史

3. **中断信号**：
   ```rust
   app_event_tx.interrupt()
   ```
   用户按 Esc 退出时发送

### 5.3 与 `tui` crate 的关系

`tui_app_server` 是 `tui` 的并行实现（用于应用服务器模式）。两者代码结构高度相似：

```
codex-rs/tui/src/bottom_pane/request_user_input/       (桌面 TUI 版本)
codex-rs/tui_app_server/src/bottom_pane/request_user_input/  (应用服务器版本)
```

根据 AGENTS.md 规范：
> "When a change lands in `codex-rs/tui` and `codex-rs/tui_app_server` has a parallel implementation of the same behavior, reflect the change in `codex-rs/tui_app_server` too unless there is a documented reason not to."

### 5.4 依赖 Crate

| Crate | 用途 |
|-------|------|
| `ratatui` | TUI 渲染框架 |
| `crossterm` | 跨平台终端控制（键盘事件） |
| `codex_protocol` | 协议类型定义 |
| `unicode_width` | Unicode 字符宽度计算 |
| `textwrap` | 文本自动换行 |

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 中断时丢失已提交答案

```rust
// mod.rs L1008-1010
// TODO: Emit interrupted request_user_input results (including committed answers)
// once core supports persisting them reliably without follow-up turn issues.
self.app_event_tx.interrupt();
self.done = true;
```

**风险**：用户回答了部分问题后按 Esc 中断，已提交答案会丢失。
**状态**：已知问题，待 Core 层支持可靠持久化后修复。

#### 6.1.2 队列请求在中断时丢失

```rust
// 测试用例：interrupt_discards_queued_requests_and_emits_interrupt
// 中断时 queue 中的所有未处理请求都会被丢弃
```

**风险**：多个输入请求排队时，用户中断会导致后续请求丢失。

#### 6.1.3 粘贴内容过大时的内存使用

```rust
// 测试用例：large_paste_is_preserved_when_switching_questions
// 使用 1500 字符的粘贴内容测试
```

**风险**：大段粘贴内容存储在 `pending_pastes` 中，可能占用较多内存。

### 6.2 边界条件

| 边界 | 处理逻辑 |
|------|----------|
| 空问题列表 | 显示 "No questions"，可正常提交空答案 |
| 零选项问题 | 自动进入 Notes 焦点模式 |
| 单问题表单 | Enter 直接提交，不显示 "submit all" 提示 |
| 最后一个问题 | Enter 提交全部，显示 "enter to submit all" |
| 窄终端 (< 30 列) | 布局压缩，优先保证选项可见性 |
| 矮终端 (< 8 行) | 使用 `MIN_OVERLAY_HEIGHT` 保证基本显示 |
| 超长选项标签 | 自动换行，保持缩进对齐 |
| 数字键超出选项数 | 忽略输入 |

### 6.3 改进建议

#### 6.3.1 短期改进

1. **持久化中断时的部分答案**
   - 在 `interrupt()` 前发送部分答案到 Core
   - 需要协议支持 `partial_user_input_answer` 或类似机制

2. **队列通知**
   - 在 UI 中显示队列长度（如 "Question 1/2 (2 more requests queued)"）
   - 帮助用户了解后续还有输入请求

3. **搜索/过滤选项**
   - 当选项数量 > 10 时，添加搜索过滤功能
   - 类似 `/model` 命令的模糊搜索

#### 6.3.2 中期改进

1. **多选支持**
   - 当前仅支持单选，可扩展为多选（checkbox 模式）
   - 需要协议层支持 `max_selections` 字段

2. **选项分组**
   - 支持选项分类（如 "Recommended" / "Advanced"）
   - 使用 `category_tag` 字段（已在 `GenericDisplayRow` 中预留）

3. **富文本问题描述**
   - 当前仅支持纯文本问题
   - 可扩展支持 Markdown 渲染（代码块、链接等）

#### 6.3.3 长期改进

1. **可复用表单模板**
   - 将常见表单模式（如 "Yes/No/Skip with reason"）预定义为模板
   - 减少 Agent 重复构造相同表单

2. **答案验证**
   - 客户端实时验证（如邮箱格式、数字范围）
   - 需要协议层支持 `validation_rules` 字段

3. **表单历史**
   - 记住用户对类似问题的回答
   - 提供 "Use previous answer" 快捷选项

### 6.4 测试覆盖

当前测试覆盖良好，包括：

- **单元测试**：约 60+ 个测试用例
- **快照测试**：使用 `insta` 验证 UI 渲染
- **边界测试**：空问题、长文本、窄窗口等

**测试文件位置**：
```
codex-rs/tui_app_server/src/bottom_pane/request_user_input/
└── mod.rs (测试代码位于文件末尾，约 1500 行)
```

**关键测试场景**：
- 队列 FIFO 行为
- 中断处理
- 选项选择/清除
- 备注输入/清除
- 数字快捷键
- Vim 键绑定 (j/k/h/l)
- 未回答确认对话框
- 粘贴内容保持
- 多问题导航

---

## 7. 总结

`RequestUserInputOverlay` 是一个功能完善、设计精良的用户输入收集组件。它通过复用 `ChatComposer` 实现了与主输入框一致的编辑体验，同时通过精心设计的布局算法确保在各种终端尺寸下都能良好展示。

代码质量高，测试覆盖充分，遵循了项目的编码规范（如使用 `Stylize` trait、避免大模块等）。主要风险在于中断时的答案丢失问题，这需要协议层的支持才能彻底解决。
