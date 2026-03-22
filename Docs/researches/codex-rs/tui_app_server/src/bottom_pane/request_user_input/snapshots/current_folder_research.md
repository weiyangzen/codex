# Research: `codex-rs/tui_app_server/src/bottom_pane/request_user_input/snapshots`

## 1. 场景与职责

### 1.1 目录定位

`snapshots/` 目录位于 `codex-rs/tui_app_server/src/bottom_pane/request_user_input/` 下，是 **insta snapshot testing** 的测试快照存储目录。该目录包含 12 个 `.snap` 文件，用于验证 `RequestUserInputOverlay` 组件的 UI 渲染输出。

### 1.2 所属功能模块

该目录属于 **TUI App Server** 的 **Bottom Pane** 子系统，具体负责：

- **Request User Input 功能**：当 Agent 需要向用户请求输入时（如选择选项、填写表单），显示交互式覆盖层（overlay）
- **用户输入收集**：支持单选/多选选项、自由文本输入、备注添加等多种输入模式
- **多问题向导**：支持连续多个问题的分步收集

### 1.3 与 TUI 的关系

根据 `AGENTS.md` 中的约定：
> "When a change lands in `codex-rs/tui` and `codex-rs/tui_app_server` has a parallel implementation of the same behavior, reflect the change in `codex-rs/tui_app_server` too"

`tui_app_server` 中的实现与 `tui` 中的实现保持平行，快照测试确保两者的 UI 输出一致性。

---

## 2. 功能点目的

### 2.1 Snapshot Testing 目的

| 目的 | 说明 |
|------|------|
| **UI 回归防护** | 捕获意外的 UI 变更，确保渲染输出稳定 |
| **视觉文档** | 快照文件本身就是 UI 状态的文档化记录 |
| **跨平台一致性** | 验证不同平台下的渲染输出一致 |
| **重构安全网** | 允许安全地重构代码，通过快照对比验证行为未变 |

### 2.2 测试覆盖场景

12 个快照文件覆盖以下场景：

| 快照文件 | 测试场景 | 关键验证点 |
|----------|----------|------------|
| `request_user_input_options.snap` | 基础选项选择界面 | 选项列表、选中标记、底部提示 |
| `request_user_input_freeform.snap` | 自由文本输入（无选项） | 文本输入框占位符、简洁布局 |
| `request_user_input_options_notes_visible.snap` | 选项+备注模式 | 备注输入框显示、Tab切换提示 |
| `request_user_input_multi_question_first.snap` | 多问题向导-第一题 | 进度指示、问题导航提示 |
| `request_user_input_multi_question_last.snap` | 多问题向导-最后一题 | "enter to submit all" 提示 |
| `request_user_input_tight_height.snap` | 紧凑高度布局 | 小高度下的布局适配 |
| `request_user_input_wrapped_options.snap` | 长文本选项换行 | 选项标签和描述的换行处理 |
| `request_user_input_long_option_text.snap` | 超长选项文本 | 极端长文本的截断和换行 |
| `request_user_input_scrolling_options.snap` | 选项滚动 | 超出视口时的滚动显示 |
| `request_user_input_hidden_options_footer.snap` | 选项隐藏时的底部栏 | 当前选项位置指示 |
| `request_user_input_footer_wrap.snap` | 底部提示换行 | 窄宽度下提示文本的换行 |
| `request_user_input_unanswered_confirmation.snap` | 未回答问题确认 | 确认对话框渲染 |

---

## 3. 具体技术实现

### 3.1 核心数据结构

#### 3.1.1 协议层数据类型 (`codex_protocol::request_user_input`)

```rust
// protocol/src/request_user_input.rs
#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq, JsonSchema, TS)]
pub struct RequestUserInputQuestion {
    pub id: String,
    pub header: String,
    pub question: String,
    pub is_other: bool,      // 是否显示"None of the above"选项
    pub is_secret: bool,     // 是否密码输入（掩码显示）
    pub options: Option<Vec<RequestUserInputQuestionOption>>,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq, JsonSchema, TS)]
pub struct RequestUserInputQuestionOption {
    pub label: String,
    pub description: String,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq, JsonSchema, TS)]
pub struct RequestUserInputEvent {
    pub call_id: String,
    pub turn_id: String,
    pub questions: Vec<RequestUserInputQuestion>,
}
```

#### 3.1.2 组件状态机

```rust
// tui_app_server/src/bottom_pane/request_user_input/mod.rs
struct RequestUserInputOverlay {
    app_event_tx: AppEventSender,
    request: RequestUserInputEvent,
    queue: VecDeque<RequestUserInputEvent>,  // 请求队列
    composer: ChatComposer,                   // 复用聊天输入组件
    answers: Vec<AnswerState>,               // 每个问题的答案状态
    current_idx: usize,                       // 当前问题索引
    focus: Focus,                            // 焦点：Options/Notes
    done: bool,
    confirm_unanswered: Option<ScrollState>, // 未回答问题确认状态
}

struct AnswerState {
    options_state: ScrollState,   // 选项滚动/选择状态
    draft: ComposerDraft,         // 备注/自由文本草稿
    answer_committed: bool,       // 是否已提交答案
    notes_visible: bool,          // 备注UI是否可见
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Focus {
    Options,
    Notes,
}
```

### 3.2 关键流程

#### 3.2.1 渲染流程

```
render_ui(area, buf)
├── 确认对话框模式？
│   └── render_unanswered_confirmation()
├── 正常模式
│   ├── render_menu_surface()           // 绘制菜单背景
│   ├── layout_sections()               // 计算布局分区
│   ├── 绘制进度头 (Question X/Y)
│   ├── 绘制问题文本
│   ├── 绘制选项列表 (render_rows_bottom_aligned)
│   ├── 绘制备注输入框 (render_notes_input)
│   └── 绘制底部提示 (footer_tip_lines)
```

#### 3.2.2 键盘事件处理流程

```
handle_key_event(key_event)
├── confirm_unanswered_active?
│   └── handle_confirm_unanswered_key_event()
├── KeyCode::Esc
│   ├── 有选项+备注可见 → 清除备注并返回选项
│   └── 否则 → 发送中断信号，标记完成
├── 问题导航 (Ctrl+P/N, PageUp/Down, ←/→, H/L)
│   └── move_question()
├── match focus
│   ├── Focus::Options
│   │   ├── ↑/↓/K/J → 移动选项选择
│   │   ├── Space → 选择当前选项
│   │   ├── Backspace/Delete → 清除选择
│   │   ├── Tab → 切换到备注输入
│   │   ├── Enter → 提交/下一题
│   │   └── 数字键 → 快速选择并提交
│   └── Focus::Notes
│       ├── Tab → 返回选项
│       ├── Backspace (空) → 返回选项
│       ├── Enter → 提交草稿
│       └── 其他 → 传递给 composer 处理
```

#### 3.2.3 答案提交流程

```
submit_answers()
├── 遍历所有问题
│   ├── 收集选项选择 (selected_idx → label)
│   ├── 收集备注文本 (draft.text_with_pending())
│   ├── 构建 answer_list: [label, "user_note: ..."]
│   └── 插入 answers HashMap
├── app_event_tx.user_input_answer()     // 发送答案到后端
├── app_event_tx.send(InsertHistoryCell) // 添加到历史记录
└── 检查队列中的下一个请求
    ├── 有 → 加载下一个请求
    └── 无 → 标记 done = true
```

### 3.3 布局算法

#### 3.3.1 布局分区计算 (`layout.rs`)

```rust
pub(super) fn layout_sections(&self, area: Rect) -> LayoutSections {
    // 1. 确定是否有选项
    // 2. 计算各区域高度需求：
    //    - question_height: 问题文本换行后的高度
    //    - options_height: 选项列表高度（measure_rows_height）
    //    - notes_height: 备注输入框高度（MIN_COMPOSER_HEIGHT=3）
    //    - footer_lines: 底部提示行数
    // 3. 空间分配策略：
    //    - 优先保证 footer + progress
    //    - 选项区域可压缩（保持至少1行）
    //    - 备注区域根据可见性动态分配
}
```

#### 3.3.2 关键布局常量

```rust
const MIN_COMPOSER_HEIGHT: u16 = 3;           // 备注输入框最小高度
const DESIRED_SPACERS_BETWEEN_SECTIONS: u16 = 2;  // 区域间理想间距
const MIN_OVERLAY_HEIGHT: usize = 8;          // 覆盖层最小高度
const PROGRESS_ROW_HEIGHT: usize = 1;         // 进度行高度
```

### 3.4 快照测试实现

#### 3.4.1 测试辅助函数

```rust
// mod.rs 测试模块
fn render_snapshot(overlay: &RequestUserInputOverlay, area: Rect) -> String {
    let mut buf = Buffer::empty(area);
    overlay.render(area, &mut buf);
    snapshot_buffer(&buf)  // 将 Buffer 转换为字符串
}

fn snapshot_buffer(buf: &Buffer) -> String {
    // 逐行提取符号，合并为带换行的字符串
}
```

#### 3.4.2 典型测试用例

```rust
#[test]
fn request_user_input_options_snapshot() {
    let (tx, _rx) = test_sender();
    let overlay = RequestUserInputOverlay::new(
        request_event("turn-1", vec![question_with_options("q1", "Area")]),
        tx, true, false, false
    );
    let area = Rect::new(0, 0, 120, 16);
    insta::assert_snapshot!("request_user_input_options", render_snapshot(&overlay, area));
}
```

#### 3.4.3 快照文件格式

```yaml
---
source: tui_app_server/src/bottom_pane/request_user_input/mod.rs
expression: "render_snapshot(&overlay, area)"
---
                                                                                                                        
  Question 1/1 (1 unanswered)                                                                                           
  Choose an option.                                                                                                     
                                                                                                                        
  › 1. Option 1  First choice.                                                                                          
    2. Option 2  Second choice.                                                                                         
    3. Option 3  Third choice.                                                                                          
                                                                                                                        
  tab to add notes | enter to submit answer | esc to interrupt
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心实现文件

| 文件 | 职责 | 关键函数/结构 |
|------|------|---------------|
| `mod.rs` | 主状态机实现 | `RequestUserInputOverlay`, `handle_key_event`, `submit_answers` |
| `layout.rs` | 布局计算 | `layout_sections`, `LayoutPlan` |
| `render.rs` | 渲染实现 | `render_ui`, `render_unanswered_confirmation`, `render_rows_bottom_aligned` |

### 4.2 依赖文件

| 文件 | 提供功能 |
|------|----------|
| `../selection_popup_common.rs` | `GenericDisplayRow`, `render_rows`, `measure_rows_height` |
| `../scroll_state.rs` | `ScrollState` - 滚动/选择状态管理 |
| `../chat_composer.rs` | `ChatComposer` - 文本输入组件复用 |
| `../bottom_pane_view.rs` | `BottomPaneView` trait 定义 |
| `../../app_event_sender.rs` | `AppEventSender` - 事件发送 |
| `../../history_cell.rs` | `RequestUserInputResultCell` - 历史记录单元 |

### 4.3 协议定义

| 文件 | 定义 |
|------|------|
| `protocol/src/request_user_input.rs` | `RequestUserInputEvent`, `RequestUserInputQuestion`, `RequestUserInputAnswer` |

### 4.4 调用链

```
Backend (codex_core)
    ↓ RequestUserInputEvent
AppEventSender::user_input_answer()
    ↓ AppEvent::CodexOp(Op::UserInputAnswer)
BottomPane::push_user_input_request()
    ↓ RequestUserInputOverlay::new()
        ↓ 用户交互
    ↓ submit_answers()
        ↓ AppEventSender::user_input_answer()
            ↓ Backend processing
```

---

## 5. 依赖与外部交互

### 5.1 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `ratatui` | TUI 渲染框架（Buffer, Rect, Line, Span, Paragraph 等） |
| `crossterm` | 键盘事件处理（KeyCode, KeyEvent, KeyModifiers） |
| `insta` | 快照测试框架 |
| `textwrap` | 文本换行处理 |
| `unicode_width` | Unicode 字符宽度计算 |
| `codex_protocol` | 协议类型定义 |

### 5.2 内部模块依赖

```
request_user_input/
├── mod.rs
│   ├── layout.rs (私有模块)
│   ├── render.rs (私有模块)
│   └── snapshots/ (测试数据)
├── 依赖 ../selection_popup_common.rs
├── 依赖 ../scroll_state.rs
├── 依赖 ../chat_composer.rs
├── 依赖 ../../app_event_sender.rs
└── 依赖 ../../history_cell.rs
```

### 5.3 与 TUI 的镜像关系

`tui/src/bottom_pane/request_user_input/` 目录结构与 `tui_app_server` 平行，包含：
- 相同的 `mod.rs`, `layout.rs`, `render.rs` 结构
- 独立的快照测试（`codex_tui__*` 前缀）
- 共享相同的协议类型

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险点 | 描述 | 缓解措施 |
|--------|------|----------|
| **TODO: 中断时答案丢失** | 代码中多处 TODO 注释提到中断时无法持久化部分答案 | 需要后端支持保存中断时的已提交答案 |
| **队列处理复杂性** | 请求队列 (`queue: VecDeque`) 增加了状态复杂度 | 当前实现通过 FIFO 处理，需确保边界测试覆盖 |
| **布局计算的舍入误差** | 高度计算涉及多次 `saturating_add`/`saturating_sub` | 快照测试覆盖多种尺寸组合 |
| **多字节字符宽度** | Unicode 字符宽度计算依赖 `unicode_width` crate | 测试覆盖 CJK 等宽字符场景 |

### 6.2 边界情况

| 边界 | 处理方式 |
|------|----------|
| 零问题请求 | `reset_for_request()` 创建空 `answers` Vec，正常处理 |
| 空选项列表 | `has_options()` 返回 false，进入自由文本模式 |
| 超长问题文本 | `wrapped_question_lines()` 使用 `textwrap::wrap` |
| 零高度区域 | 各渲染函数检查 `area.height == 0` 提前返回 |
| 快速连续提交 | `pending_submission_draft` 机制防止竞态 |

### 6.3 改进建议

#### 6.3.1 代码组织

1. **拆分过大模块**：`mod.rs` 超过 2900 行，建议按功能拆分为：
   - `state.rs` - 状态管理
   - `input_handler.rs` - 键盘事件处理
   - `submission.rs` - 答案提交逻辑

2. **提取共享常量**：
   - `OTHER_OPTION_LABEL` 和 `OTHER_OPTION_DESCRIPTION` 可考虑配置化
   - 占位符文本（`NOTES_PLACEHOLDER`, `ANSWER_PLACEHOLDER`）支持国际化

#### 6.3.2 测试覆盖

1. **增加边界测试**：
   - 100+ 个选项的性能测试
   - 极端窄宽度（<20列）的渲染测试
   - 混合方向文本（RTL）的渲染测试

2. **增加交互测试**：
   - 快速切换问题的状态保持
   - 粘贴大文本后的导航行为

#### 6.3.3 功能增强

1. **搜索/过滤选项**：当选项数量大时支持键盘搜索
2. **多选支持**：当前仅支持单选，协议层已预留扩展空间
3. **答案持久化**：解决 TODO 中提到的中断时答案丢失问题

#### 6.3.4 性能优化

1. **布局缓存**：`layout_sections()` 在每次渲染时重新计算，可考虑缓存
2. **增量渲染**：选项列表的滚动窗口计算可优化

### 6.4 维护注意事项

1. **快照更新流程**：
   ```bash
   cargo test -p codex-tui-app-server
   cargo insta review -p codex-tui-app-server
   ```

2. **与 TUI 同步**：修改时需同步检查 `tui/src/bottom_pane/request_user_input/`

3. **协议变更**：修改 `RequestUserInputQuestion` 等类型需同步更新：
   - `protocol/src/request_user_input.rs`
   - TypeScript schema 生成
   - 文档 (`docs/protocol_v1.md`)

---

## 附录：快照文件完整列表

```
codex-rs/tui_app_server/src/bottom_pane/request_user_input/snapshots/
├── codex_tui_app_server__bottom_pane__request_user_input__tests__request_user_input_footer_wrap.snap
├── codex_tui_app_server__bottom_pane__request_user_input__tests__request_user_input_freeform.snap
├── codex_tui_app_server__bottom_pane__request_user_input__tests__request_user_input_hidden_options_footer.snap
├── codex_tui_app_server__bottom_pane__request_user_input__tests__request_user_input_long_option_text.snap
├── codex_tui_app_server__bottom_pane__request_user_input__tests__request_user_input_multi_question_first.snap
├── codex_tui_app_server__bottom_pane__request_user_input__tests__request_user_input_multi_question_last.snap
├── codex_tui_app_server__bottom_pane__request_user_input__tests__request_user_input_options.snap
├── codex_tui_app_server__bottom_pane__request_user_input__tests__request_user_input_options_notes_visible.snap
├── codex_tui_app_server__bottom_pane__request_user_input__tests__request_user_input_scrolling_options.snap
├── codex_tui_app_server__bottom_pane__request_user_input__tests__request_user_input_tight_height.snap
├── codex_tui_app_server__bottom_pane__request_user_input__tests__request_user_input_unanswered_confirmation.snap
└── codex_tui_app_server__bottom_pane__request_user_input__tests__request_user_input_wrapped_options.snap
```

（注：目录中还包含 `codex_tui__*` 前缀的文件，这些是 `tui` crate 的平行实现快照）
