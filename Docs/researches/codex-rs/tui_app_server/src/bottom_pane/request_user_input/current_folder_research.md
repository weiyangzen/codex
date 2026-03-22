# Request User Input 模块研究文档

## 1. 场景与职责

### 1.1 模块定位

`request_user_input` 是 Codex TUI 应用服务器中 `bottom_pane` 子系统的一个核心模块，负责处理**交互式用户输入请求**的 UI 渲染与状态管理。当 Codex 核心需要向用户询问问题（如选择选项、填写表单、确认操作等）时，该模块提供一个模态覆盖层（Modal Overlay）来收集用户输入。

### 1.2 核心职责

- **问题展示**: 显示来自核心层的问题列表，支持单选、多选和自由文本输入
- **选项导航**: 提供键盘驱动的选项选择（上下箭头、Vim键位、数字快捷键）
- **笔记输入**: 允许用户为选中的选项添加补充说明（Notes）
- **多问题管理**: 支持顺序回答多个问题，显示进度指示器
- **响应提交**: 将用户答案格式化为协议消息发送回核心层
- **中断处理**: 支持用户通过 Esc 中断输入流程

### 1.3 使用场景

1. **工具调用确认**: 当 Codex 需要用户确认某个工具调用参数时
2. **配置选择**: 让用户从预定义选项中选择（如选择模型、审批策略等）
3. **信息收集**: 收集用户偏好、环境信息或任务细节
4. **多步骤向导**: 引导用户完成一系列相关问题的回答

---

## 2. 功能点目的

### 2.1 问题类型支持

| 类型 | 描述 | 交互方式 |
|------|------|----------|
| **选项问题** | 提供预定义选项列表 | 方向键/数字键选择，Enter确认 |
| **自由文本** | 无选项，直接文本输入 | 直接输入，Enter提交 |
| **混合模式** | 选项+补充笔记 | 先选选项，Tab进入笔记输入 |
| **Other选项** | 支持"以上都不是"+自定义输入 | 选择Other后输入自定义内容 |

### 2.2 关键交互特性

- **快速数字选择**: 数字键 1-9 直接选择对应选项并提交
- **Vim风格导航**: 支持 `j/k` 上下移动，`h/l` 切换问题
- **笔记切换**: Tab 键在选项和笔记输入间切换
- **自动保存草稿**: 切换问题时自动保存当前输入内容
- **未回答确认**: 尝试提交时检测未回答问题，提示确认

### 2.3 视觉反馈

- **进度指示**: 显示 "Question X/Y" 进度
- **未回答计数**: 实时显示剩余未回答问题数量
- **选项高亮**: 当前选中选项使用青色高亮
- **已回答标记**: 已提交答案的问题有特殊视觉标识

---

## 3. 具体技术实现

### 3.1 核心数据结构

#### 3.1.1 RequestUserInputOverlay (主状态机)

```rust
pub(crate) struct RequestUserInputOverlay {
    app_event_tx: AppEventSender,           // 事件发送通道
    request: RequestUserInputEvent,         // 当前请求
    queue: VecDeque<RequestUserInputEvent>, // 待处理请求队列
    composer: ChatComposer,                 // 复用的聊天输入组件
    answers: Vec<AnswerState>,              // 各问题的回答状态
    current_idx: usize,                     // 当前问题索引
    focus: Focus,                           // 当前焦点（选项/笔记）
    done: bool,                             // 是否完成
    confirm_unanswered: Option<ScrollState>, // 未回答确认对话框状态
}
```

#### 3.1.2 AnswerState (单问题状态)

```rust
struct AnswerState {
    options_state: ScrollState,     // 选项滚动/选择状态
    draft: ComposerDraft,           // 笔记草稿内容
    answer_committed: bool,         // 是否已提交答案
    notes_visible: bool,            // 笔记输入区是否可见
}
```

#### 3.1.3 ComposerDraft (草稿内容)

```rust
#[derive(Default, Clone, PartialEq)]
struct ComposerDraft {
    text: String,                           // 文本内容
    text_elements: Vec<TextElement>,        // 富文本元素
    local_image_paths: Vec<PathBuf>,        // 本地图片附件
    pending_pastes: Vec<(String, String)>,  // 待处理粘贴内容
}
```

### 3.2 关键流程

#### 3.2.1 初始化流程

1. **接收请求**: 通过 `BottomPane::push_user_input_request()` 接收 `RequestUserInputEvent`
2. **创建覆盖层**: 调用 `RequestUserInputOverlay::new()` 初始化状态
3. **配置Composer**: 使用 `ChatComposerConfig::plain_text()` 禁用弹窗和斜杠命令
4. **初始化答案状态**: 为每个问题创建 `AnswerState`，设置默认选中第一项
5. **暂停底层输入**: 禁用主Composer输入，显示占位提示

#### 3.2.2 键盘事件处理流程

```
handle_key_event()
├── 确认对话框激活？
│   └── 处理确认对话框输入（Proceed/Go back）
├── Esc键？
│   ├── 笔记模式且有内容 → 清除笔记
│   └── 否则 → 发送中断信号，标记完成
├── 问题导航（Ctrl+P/N, PageUp/Down, ←/→）
│   └── move_question() 切换问题并保存/恢复草稿
└── 根据焦点分发
    ├── Focus::Options
    │   ├── ↑/↓/k/j → 移动选项选择
    │   ├── Space → 确认选择
    │   ├── Enter → 确认并进入下一题/提交
    │   ├── Tab → 进入笔记模式（需先选择选项）
    │   └── 数字键 → 快速选择并提交
    └── Focus::Notes
        ├── Tab → 返回选项模式
        ├── Backspace（空内容）→ 返回选项模式
        ├── ↑/↓ → 调整选项选择（不切换焦点）
        └── 其他 → 转发给Composer处理
```

#### 3.2.3 答案提交流程

```rust
fn submit_answers(&mut self) {
    // 1. 保存当前草稿
    self.save_current_draft();
    
    // 2. 构建答案映射
    let mut answers = HashMap::new();
    for (idx, question) in self.request.questions.iter().enumerate() {
        let answer_state = &self.answers[idx];
        
        // 提取选中选项标签
        let selected_label = answer_state.options_state.selected_idx
            .and_then(|idx| Self::option_label_for_index(question, idx));
        
        // 提取笔记内容
        let notes = if answer_state.answer_committed {
            answer_state.draft.text_with_pending().trim().to_string()
        } else {
            String::new()
        };
        
        // 组装答案列表（选项标签 + user_note前缀的笔记）
        let mut answer_list = selected_label.into_iter().collect::<Vec<_>>();
        if !notes.is_empty() {
            answer_list.push(format!("user_note: {notes}"));
        }
        
        answers.insert(question.id.clone(), RequestUserInputAnswer { answers: answer_list });
    }
    
    // 3. 发送答案到核心层
    self.app_event_tx.user_input_answer(self.request.turn_id.clone(), RequestUserInputResponse { answers });
    
    // 4. 插入历史记录单元格
    self.app_event_tx.send(AppEvent::InsertHistoryCell(Box::new(
        history_cell::RequestUserInputResultCell { questions, answers, interrupted: false }
    )));
    
    // 5. 处理队列中的下一个请求或标记完成
    if let Some(next) = self.queue.pop_front() {
        self.request = next;
        self.reset_for_request();
    } else {
        self.done = true;
    }
}
```

### 3.3 布局算法

布局模块 (`layout.rs`) 实现了一个自适应的空间分配算法：

#### 3.3.1 布局区域（从上到下）

```
┌─────────────────────────────┐
│ Progress (Question X/Y)     │  ← 进度行（1行）
├─────────────────────────────┤
│ Question Text               │  ← 问题文本（动态高度）
├─────────────────────────────┤
│ Options List                │  ← 选项列表（动态高度，可滚动）
├─────────────────────────────┤
│ Notes Input                 │  ← 笔记输入区（条件显示）
├─────────────────────────────┤
│ Footer Hints                │  ← 底部提示（动态行数）
└─────────────────────────────┘
```

#### 3.3.2 布局策略

- **有选项问题**: 优先保证选项区域可见，笔记区域可折叠
- **自由文本问题**: 最大化笔记输入区域
- **空间不足时**: 选项区域可滚动，笔记区域最小高度限制为3行
- **间距控制**: 使用 `DESIRED_SPACERS_BETWEEN_SECTIONS` (2行) 保持视觉分隔

### 3.4 渲染实现

渲染模块 (`render.rs`) 使用 `ratatui` 进行终端UI渲染：

#### 3.4.1 主要渲染组件

| 组件 | 函数 | 说明 |
|------|------|------|
| 菜单表面 | `render_menu_surface()` | 共享的背景块样式 |
| 进度行 | `Paragraph::new(progress_line)` | 显示问题进度和未回答计数 |
| 问题文本 | `wrapped_question_lines()` + 逐行渲染 | 自动换行的问题文本 |
| 选项列表 | `render_rows_bottom_aligned()` | 底部对齐的选项列表 |
| 笔记输入 | `render_notes_input()` | 复用Composer渲染，支持密码掩码 |
| 底部提示 | `footer_tip_lines()` | 动态换行的提示文本 |

#### 3.4.2 特殊渲染处理

- **密码输入**: 当 `question.is_secret` 为 true 时，使用 `render_with_mask('*')`
- **选中状态**: 使用 `›` 前缀和青色粗体高亮
- **底部对齐**: 选项列表采用底部对齐，保持页脚位置稳定
- **文本截断**: 使用 `truncate_line_word_boundary_with_ellipsis()` 智能截断

### 3.5 协议集成

#### 3.5.1 输入协议 (RequestUserInputEvent)

```rust
pub struct RequestUserInputEvent {
    pub call_id: String,                    // 关联的工具调用ID
    pub turn_id: String,                    // 所属回合ID
    pub questions: Vec<RequestUserInputQuestion>, // 问题列表
}

pub struct RequestUserInputQuestion {
    pub id: String,                         // 问题唯一标识
    pub header: String,                     // 标题（简短）
    pub question: String,                   // 问题文本（详细）
    pub is_other: bool,                     // 是否显示"Other"选项
    pub is_secret: bool,                    // 是否密码输入
    pub options: Option<Vec<RequestUserInputQuestionOption>>, // 选项列表
}

pub struct RequestUserInputQuestionOption {
    pub label: String,                      // 选项标签
    pub description: String,                // 选项描述
}
```

#### 3.5.2 输出协议 (RequestUserInputResponse)

```rust
pub struct RequestUserInputResponse {
    pub answers: HashMap<String, RequestUserInputAnswer>, // 问题ID -> 答案
}

pub struct RequestUserInputAnswer {
    pub answers: Vec<String>, // 答案列表（选中标签 + user_note:前缀的笔记）
}
```

#### 3.5.3 与核心层交互

```
┌─────────────┐     RequestUserInputEvent      ┌─────────────────────┐
│  Codex Core │ ───────────────────────────────→ │ RequestUserInputOverlay │
│             │                                  │     (tui_app_server)    │
│             │ ←─────────────────────────────── │                         │
│             │     Op::UserInputAnswer          │                         │
└─────────────┘                                  └─────────────────────┘
                                                        │
                                                        ↓
                                               ┌─────────────────────┐
                                               │  HistoryCell插入    │
                                               │ (RequestUserInputResultCell) │
                                               └─────────────────────┘
```

---

## 4. 关键代码路径与文件引用

### 4.1 模块文件结构

```
codex-rs/tui_app_server/src/bottom_pane/request_user_input/
├── mod.rs           # 主状态机实现 (2923行，含测试)
├── layout.rs        # 布局计算 (363行)
├── render.rs        # 渲染逻辑 (582行)
└── snapshots/       # insta快照测试文件
    ├── codex_tui_app_server__bottom_pane__request_user_input__tests__*.snap
    └── codex_tui__bottom_pane__request_user_input__tests__*.snap
```

### 4.2 核心代码路径

| 功能 | 文件 | 行号范围 | 关键函数/结构体 |
|------|------|----------|-----------------|
| 状态机定义 | `mod.rs` | 122-137 | `RequestUserInputOverlay` |
| 初始化 | `mod.rs` | 139-175 | `new()`, `reset_for_request()` |
| 键盘处理 | `mod.rs` | 988-1060 | `handle_key_event()` |
| 选项导航 | `mod.rs` | 1082-1136 | Focus::Options 分支 |
| 笔记输入 | `mod.rs` | 1138-1218 | Focus::Notes 分支 |
| 答案提交 | `mod.rs` | 715-770 | `submit_answers()` |
| 布局计算 | `layout.rs` | 17-60 | `layout_sections()` |
| 渲染入口 | `render.rs` | 61-114 | `Renderable` trait实现 |
| UI渲染 | `render.rs` | 248-384 | `render_ui()` |
| 未回答确认 | `render.rs` | 117-169 | `unanswered_confirmation_*` |

### 4.3 依赖文件

| 文件 | 用途 |
|------|------|
| `../mod.rs` | BottomPane主模块，管理覆盖层生命周期 |
| `../bottom_pane_view.rs` | `BottomPaneView` trait定义 |
| `../chat_composer.rs` | 复用的文本输入组件 |
| `../scroll_state.rs` | 滚动状态管理 `ScrollState` |
| `../selection_popup_common.rs` | 通用选择列表渲染工具 |
| `../../app_event_sender.rs` | 应用事件发送器 |
| `../../history_cell.rs` | 历史记录单元格定义 |
| `../../../protocol/src/request_user_input.rs` | 协议数据结构定义 |

### 4.4 测试覆盖

模块包含全面的单元测试（约 60+ 测试用例），覆盖：

- **基础功能**: 初始化、导航、选择、提交
- **边界情况**: 空选项、长文本、空间不足
- **交互流程**: 多问题切换、笔记输入、中断处理
- **视觉回归**: 使用 insta 进行快照测试

---

## 5. 依赖与外部交互

### 5.1 内部依赖

```
request_user_input/
├── 依赖: bottom_pane/mod.rs
│   └── 提供: BottomPaneView trait, 覆盖层管理
├── 依赖: bottom_pane/chat_composer.rs
│   └── 提供: ChatComposer, InputResult, ChatComposerConfig
├── 依赖: bottom_pane/scroll_state.rs
│   └── 提供: ScrollState (滚动/选择状态)
├── 依赖: bottom_pane/selection_popup_common.rs
│   └── 提供: GenericDisplayRow, render_rows, menu_surface_inset
├── 依赖: app_event_sender.rs
│   └── 提供: AppEventSender, user_input_answer(), interrupt()
└── 依赖: history_cell.rs
    └── 提供: RequestUserInputResultCell
```

### 5.2 协议依赖

```
codex-rs/protocol/src/request_user_input.rs
├── RequestUserInputEvent      # 输入事件
├── RequestUserInputQuestion   # 问题定义
├── RequestUserInputQuestionOption # 选项定义
├── RequestUserInputResponse   # 响应结构
└── RequestUserInputAnswer     # 答案结构
```

### 5.3 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `ratatui` | 终端UI渲染框架 |
| `crossterm` | 键盘事件处理 |
| `textwrap` | 文本自动换行 |
| `unicode-width` | Unicode字符宽度计算 |
| `insta` | 快照测试（dev） |

### 5.4 生命周期交互

```
1. 创建阶段
   BottomPane::push_user_input_request()
   └── RequestUserInputOverlay::new()
       └── ChatComposer::new_with_config(plain_text)

2. 活跃阶段
   BottomPane::handle_key_event()
   └── RequestUserInputOverlay::handle_key_event()
       └── 更新内部状态 / 发送AppEvent

3. 渲染阶段
   BottomPane::render()
   └── RequestUserInputOverlay::render()
       └── layout_sections() + render_ui()

4. 完成阶段
   submit_answers()
   ├── app_event_tx.user_input_answer()  → 发送给Core
   ├── app_event_tx.send(InsertHistoryCell) → 插入历史记录
   └── done = true / 处理队列中的下一个请求

5. 清理阶段
   BottomPane 检测到 is_complete() = true
   └── pop_view() + on_active_view_complete()
       └── 恢复主Composer输入
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 中断数据丢失风险

**问题**: 当前实现中，用户按 Esc 中断时，已回答的问题数据会丢失（注释显示 TODO）。

```rust
// TODO: Emit interrupted request_user_input results (including committed answers)
// once core supports persisting them reliably without follow-up turn issues.
```

**影响**: 用户在回答多个问题过程中中断，已填写的答案无法恢复。

**缓解**: 考虑在本地缓存已回答内容，或推动核心层支持中断结果持久化。

#### 6.1.2 粘贴内容丢失风险

**问题**: 大段粘贴内容在问题切换时依赖 `pending_pastes` 机制，如果用户快速切换问题可能丢失。

**相关测试**: `large_paste_is_preserved_when_switching_questions`

#### 6.1.3 队列堆积风险

**问题**: `try_consume_user_input_request()` 将新请求加入队列，如果核心层发送过多请求，用户需要顺序处理，可能造成体验问题。

### 6.2 边界情况

| 场景 | 当前行为 | 潜在问题 |
|------|----------|----------|
| 零问题请求 | 显示 "No questions" | 无实质问题可回答 |
| 超宽选项文本 | 自动换行，可能占用大量垂直空间 | 小屏幕体验差 |
| 超多选项 (>9) | 数字键仅支持1-9 | 无法快速选择第10+选项 |
| 终端高度极小 (<8) | 使用 MIN_OVERLAY_HEIGHT 限制 | 可能超出实际可用空间 |
| 密码输入 | 使用 `*` 掩码 | 无视觉反馈输入长度 |

### 6.3 改进建议

#### 6.3.1 功能增强

1. **支持多选问题**
   - 当前仅支持单选，可扩展 `RequestUserInputQuestion` 添加 `allow_multiple` 字段
   - 使用空格键切换选中状态，Enter提交所有选中项

2. **搜索/过滤选项**
   - 当选项数量超过一定阈值（如20个）时，显示搜索框
   - 实时过滤选项列表

3. **历史答案复用**
   - 记录常见问题的历史答案
   - 提供快速填充建议

4. **富文本问题支持**
   - 当前问题文本为纯文本
   - 可扩展支持 Markdown 渲染

#### 6.3.2 体验优化

1. **动画过渡**
   - 问题切换时添加平滑滚动动画
   - 选项选择时添加视觉反馈

2. **快捷键提示**
   - 根据当前上下文动态显示可用快捷键
   - 添加 `?` 键显示帮助面板

3. **自动保存**
   - 定期自动保存草稿到本地存储
   - 应用崩溃后可恢复

#### 6.3.3 代码质量

1. **状态机重构**
   - 当前使用多个布尔标志和Option组合
   - 可考虑使用状态机模式明确状态转换

2. **布局算法优化**
   - 当前布局计算较为复杂，可提取为独立LayoutEngine
   - 支持响应式布局策略

3. **测试覆盖**
   - 添加更多边界情况测试
   - 添加集成测试验证与核心层的协议交互

#### 6.3.4 可访问性

1. **屏幕阅读器支持**
   - 添加适当的ARIA标签（终端模拟器支持的情况下）
   - 优化焦点管理

2. **高对比度模式**
   - 支持高对比度配色方案
   - 避免仅依赖颜色传达信息

---

## 7. 总结

`request_user_input` 模块是 Codex TUI 中处理交互式用户输入的核心组件，通过清晰的职责分离（状态管理、布局计算、渲染）实现了复杂的多问题输入流程。模块复用 `ChatComposer` 作为文本输入基础，同时通过 `BottomPaneView` trait 无缝集成到底层面板的生命周期管理中。

模块的主要优势在于：
- **灵活的输入模式**: 支持选项选择、自由文本、混合模式
- **高效的键盘交互**: Vim风格导航、数字快捷键、Tab切换
- **健壮的状态管理**: 草稿自动保存、问题间导航、未回答检测
- **完善的测试覆盖**: 单元测试 + 快照测试确保视觉稳定性

主要改进空间在于中断数据持久化、多选支持、以及更智能的选项过滤机制。
