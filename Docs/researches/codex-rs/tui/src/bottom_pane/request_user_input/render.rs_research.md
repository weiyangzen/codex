# Research Document: codex-rs/tui/src/bottom_pane/request_user_input/render.rs

## 1. 场景与职责

### 1.1 文件定位

`render.rs` 是 Codex TUI（Terminal User Interface）中 Request User Input 功能的渲染模块，负责将用户输入请求（`RequestUserInputEvent`）以交互式弹窗形式渲染到终端界面。

### 1.2 核心职责

该模块实现了 `RequestUserInputOverlay` 结构的渲染逻辑，主要承担以下职责：

1. **多问题问卷渲染**：支持渲染包含多个问题的输入请求，每个问题可以是选项型（单选）或自由文本型
2. **动态布局计算**：根据终端宽度和内容动态计算各区域（进度条、问题文本、选项列表、备注输入框、底部提示）的尺寸
3. **交互状态可视化**：
   - 当前问题高亮显示
   - 已回答/未回答状态区分（通过颜色：已回答为默认色，未回答为青色）
   - 选项选择状态（`›` 标记当前选中项）
4. **备注输入框渲染**：复用 `ChatComposer` 组件，支持密码型输入（`is_secret` 时显示 `*` 掩码）
5. **未回答确认弹窗**：当用户尝试提交但存在未回答问题时，渲染确认弹窗
6. **光标位置计算**：为终端光标定位提供精确坐标（用于备注输入框的文本编辑）

### 1.3 业务场景

该模块用于以下典型场景：

- **Agent 工具调用请求用户输入**：当 Codex Agent 执行工具（如 `request_user_input`）需要向用户收集信息时
- **配置确认流程**：如协作模式选择、权限确认等需要用户明确选择的场景
- **多步骤向导**：支持多个相关问题的顺序回答，如先选择类别再填写详情

---

## 2. 功能点目的

### 2.1 主要功能模块

| 功能模块 | 目的 | 关键实现 |
|---------|------|---------|
| `desired_height` | 计算渲染所需高度，用于父组件布局 | 根据问题类型、选项数量、备注可见性等计算最小高度 |
| `render_ui` | 主渲染入口，渲染完整问卷界面 | 协调各子区域渲染：进度条、问题、选项、备注、底部提示 |
| `render_unanswered_confirmation` | 渲染未回答确认弹窗 | 当用户提交不完整问卷时显示确认选项 |
| `render_notes_input` | 渲染备注输入框 | 复用 `ChatComposer`，支持密码掩码 |
| `cursor_pos_impl` | 计算光标位置 | 返回相对于屏幕的 (x, y) 坐标 |
| `render_rows_bottom_aligned` | 底部对齐渲染选项列表 | 保持选项列表与底部间距稳定 |
| `truncate_line_word_boundary_with_ellipsis` | 智能截断长文本 | 优先在单词边界截断，添加省略号 |

### 2.2 设计决策与目的

#### 2.2.1 高度计算与布局分离

```rust
// render.rs 中调用 layout.rs 的方法
let sections = self.layout_sections(content_area);
```

**目的**：将布局计算（`layout.rs`）与渲染执行（`render.rs`）分离，使代码更清晰，便于测试和维护。

#### 2.2.2 选项列表底部对齐

```rust
fn render_rows_bottom_aligned(...)
```

**目的**：当选项区域高度大于选项列表实际高度时，将选项列表锚定到底部，保持与底部提示的间距稳定，避免界面跳动。

#### 2.2.3 智能文本截断

```rust
fn truncate_line_word_boundary_with_ellipsis(line: Line<'static>, max_width: usize)
```

**目的**：在有限宽度内显示长文本时，优先在单词边界截断（而非字符边界），并添加省略号，提升可读性。

#### 2.2.4 密码输入支持

```rust
if is_secret {
    self.composer.render_with_mask(area, buf, Some('*'));
} else {
    self.composer.render(area, buf);
}
```

**目的**：支持敏感信息输入（如 API 密钥），通过 `*` 掩码保护用户隐私。

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 `UnansweredConfirmationData`

```rust
struct UnansweredConfirmationData {
    title_line: Line<'static>,      // "Submit with unanswered questions?"
    subtitle_line: Line<'static>,   // "{n} unanswered question(s)"
    hint_line: Line<'static>,       // 操作提示
    rows: Vec<GenericDisplayRow>,   // 确认选项（Proceed / Go back）
    state: ScrollState,             // 选择状态
}
```

用于存储未回答确认弹窗的渲染数据。

#### 3.1.2 `UnansweredConfirmationLayout`

```rust
struct UnansweredConfirmationLayout {
    header_lines: Vec<Line<'static>>,    // 标题和副标题（可能多行）
    hint_lines: Vec<Line<'static>>,     // 提示文本（可能多行）
    rows: Vec<GenericDisplayRow>,       // 选项行
    state: ScrollState,                 // 滚动/选择状态
}
```

用于存储确认弹窗的布局信息。

### 3.2 关键流程

#### 3.2.1 主渲染流程 (`render_ui`)

1. 检查 area 有效性（width/height > 0）
2. 如果处于未回答确认状态 → 调用 render_unanswered_confirmation
3. 渲染菜单背景（render_menu_surface）获取内容区域
4. 计算布局分区（layout_sections）
5. 渲染进度条（Question {idx}/{total}）
6. 渲染问题文本（根据回答状态设置颜色）
7. 如果有选项 → 渲染选项列表（底部对齐）
8. 如果备注可见 → 渲染备注输入框
9. 渲染底部提示（footer tips）

#### 3.2.2 高度计算流程 (`desired_height`)

1. 如果处于未回答确认状态 → 返回 unanswered_confirmation_height
2. 计算内部区域宽度（考虑 menu_surface_inset）
3. 计算各部分高度：
   - 问题文本高度（wrapped_question_lines）
   - 选项高度（options_preferred_height，如果有选项）
   - 备注高度（notes_input_height，如果可见）
   - 底部提示高度（footer_required_height）
   - 进度条高度（PROGRESS_ROW_HEIGHT）
   - 间距（根据是否有选项和备注动态调整）
4. 加上菜单内边距（menu_surface_padding_height）
5. 返回 max(计算高度, MIN_OVERLAY_HEIGHT)

#### 3.2.3 光标位置计算流程 (`cursor_pos_impl`)

1. 如果处于未回答确认状态 → 返回 None（无文本输入）
2. 如果焦点不在备注 → 返回 None
3. 如果有选项但备注不可见 → 返回 None
4. 计算内容区域（menu_surface_inset）
5. 计算布局分区（layout_sections）
6. 返回 composer.cursor_pos(notes_area)

### 3.3 渲染辅助函数

#### 3.3.1 `render_rows_bottom_aligned`

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

**实现细节**：
1. 创建临时 scratch Buffer
2. 复制原 buffer 内容到 scratch
3. 在 scratch 上调用 `render_rows` 渲染选项
4. 计算实际渲染高度
5. 将 scratch 内容复制回原 buffer，y 轴偏移（实现底部对齐）

#### 3.3.2 `truncate_line_word_boundary_with_ellipsis`

**实现细节**：
1. 如果行宽小于等于 max_width，直接返回
2. 计算省略号宽度
3. 遍历字符，跟踪最后一个适合宽度的字符位置和最后一个单词边界
4. 优先在单词边界截断，否则在最后一个适合字符处截断
5. 添加省略号，样式继承自最后一个可见 span

---

## 4. 关键代码路径与文件引用

### 4.1 同模块文件依赖

| 文件 | 依赖内容 | 用途 |
|-----|---------|------|
| `mod.rs` | `RequestUserInputOverlay` 结构定义、状态管理、事件处理 | 渲染目标结构定义 |
| `layout.rs` | `layout_sections`、`LayoutSections` | 布局计算 |

### 4.2 跨模块依赖

| 文件 | 依赖内容 | 用途 |
|-----|---------|------|
| `selection_popup_common.rs` | `GenericDisplayRow`、`render_rows`、`measure_rows_height`、`menu_surface_inset`、`menu_surface_padding_height`、`render_menu_surface`、`wrap_styled_line` | 通用选项列表渲染 |
| `popup_consts.rs` | `standard_popup_hint_line` | 标准弹窗提示 |
| `scroll_state.rs` | `ScrollState` | 滚动/选择状态管理 |
| `chat_composer.rs` | `ChatComposer` | 备注输入框组件 |
| `render/renderable.rs` | `Renderable` trait | 统一渲染接口 |

### 4.3 协议层依赖

| 文件 | 依赖内容 | 用途 |
|-----|---------|------|
| `protocol/src/request_user_input.rs` | `RequestUserInputEvent`、`RequestUserInputQuestion`、`RequestUserInputQuestionOption`、`RequestUserInputAnswer`、`RequestUserInputResponse` | 数据结构定义 |

### 4.4 关键代码路径示例

```rust
// 从 BottomPane 到 render.rs 的调用链

// 1. BottomPane::push_user_input_request (mod.rs:924)
pub fn push_user_input_request(&mut self, request: RequestUserInputEvent) {
    // ...
    let modal = RequestUserInputOverlay::new(...);
    self.push_view(Box::new(modal));
}

// 2. Renderable trait 调用 (render.rs:61-114)
impl Renderable for RequestUserInputOverlay {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        self.render_ui(area, buf);
    }
    
    fn desired_height(&self, width: u16) -> u16 {
        // ... 高度计算逻辑
    }
}

// 3. 渲染流程 (render.rs:248-384)
fn render_ui(&self, area: Rect, buf: &mut Buffer) {
    // ... 主渲染逻辑
}
```

---

## 5. 依赖与外部交互

### 5.1 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `ratatui` | 终端 UI 渲染框架（Buffer、Rect、Line、Span、Paragraph、Widget 等） |
| `unicode_width` | 计算 Unicode 字符和字符串的显示宽度 |
| `std::borrow::Cow` | 字符串内容的借用/拥有抽象 |

### 5.2 与 ChatComposer 的交互

`render.rs` 通过以下方式与 `ChatComposer` 交互：

1. **渲染备注输入框**：
   ```rust
   self.composer.render(area, buf);  // 普通文本
   self.composer.render_with_mask(area, buf, Some('*'));  // 密码输入
   ```

2. **获取光标位置**：
   ```rust
   self.composer.cursor_pos(input_area)
   ```

3. **高度计算**：
   ```rust
   self.composer.desired_height(width.max(1))
   ```

### 5.3 与 selection_popup_common 的交互

复用通用的选项列表渲染逻辑：

```rust
// 渲染选项列表
render_rows_bottom_aligned(
    sections.options_area,
    buf,
    &option_rows,
    &options_state,
    option_rows.len().max(1),
    "No options",
);

// 计算选项高度
measure_rows_height(&rows, &state, rows.len(), width.max(1))
```

### 5.4 与 layout.rs 的交互

```rust
let sections = self.layout_sections(content_area);
// 返回 LayoutSections {
//     progress_area, question_area, question_lines,
//     options_area, notes_area, footer_lines
// }
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 布局计算与渲染不一致风险

**风险描述**：`desired_height` 和 `render_ui` 分别计算布局，如果两者逻辑不一致可能导致渲染溢出或留白。

**缓解措施**：
- 两者都通过 `layout_sections` 统一计算布局
- 使用 `saturating_add` 等安全算术操作避免溢出

#### 6.1.2 光标位置计算延迟

**风险描述**：`cursor_pos_impl` 依赖 `layout_sections` 计算，如果布局状态与渲染时不一致，光标可能错位。

**缓解措施**：
- 确保在每次渲染后更新光标位置
- 返回 `Option<(u16, u16)>` 允许在无效状态下隐藏光标

#### 6.1.3 长文本截断边界情况

**风险描述**：`truncate_line_word_boundary_with_ellipsis` 处理复杂 Unicode 文本时可能出现宽度计算错误。

**缓解措施**：
- 使用 `unicode_width` crate 计算显示宽度
- 单元测试覆盖边界情况

### 6.2 边界条件

| 边界条件 | 处理逻辑 |
|---------|---------|
| area.width == 0 或 area.height == 0 | 提前返回，不渲染 |
| 无问题（question_count == 0） | 显示 "No questions" |
| 无选项（options.is_empty()） | 隐藏选项区域，显示自由文本输入 |
| 备注不可见 | 调整间距，使用 DESIRED_SPACERS_BETWEEN_SECTIONS |
| 终端高度不足 | 通过 layout.rs 的 tight layout 处理 |
| 选项文本过长 | 通过 wrap_styled_line 自动换行 |
| 底部提示过长 | 通过 wrap_footer_tips 自动换行 |

### 6.3 改进建议

#### 6.3.1 性能优化

**建议**：`render_rows_bottom_aligned` 使用临时 Buffer 复制，可以考虑使用更高效的渲染方式。

```rust
// 当前实现：创建完整 scratch Buffer
let mut scratch = Buffer::empty(scratch_area);
// ... 复制和渲染 ...

// 优化方向：直接计算偏移量，避免复制
let y_offset = area.height.saturating_sub(rendered_height);
// 直接在目标位置渲染
```

#### 6.3.2 代码复用

**建议**：`line_to_owned` 函数在 `render.rs` 和 `selection_popup_common.rs` 中重复定义，可以提取到公共模块。

#### 6.3.3 测试覆盖

**建议**：增加以下边界条件的测试：
- 极窄终端（宽度 < 20）
- 极短终端（高度 < MIN_OVERLAY_HEIGHT）
- 包含多字节 Unicode 字符的问题文本
- 包含特殊控制字符的选项描述

#### 6.3.4 可访问性改进

**建议**：
- 增加高对比度模式支持
- 为色盲用户提供非颜色区分方式（如已回答问题添加图标标记）
- 支持屏幕阅读器的 aria 标签（如果终端模拟器支持）

#### 6.3.5 功能扩展

**建议**：
- 支持问题分组/分页（当问题数量很多时）
- 支持问题搜索/过滤
- 支持默认值高亮显示
- 支持富文本问题描述（如代码块、链接）

---

## 7. 附录

### 7.1 相关测试文件

| 测试文件 | 测试内容 |
|---------|---------|
| `mod.rs` (tests 模块) | 功能测试、交互测试、快照测试 |
| `snapshots/` | UI 快照文件（`.snap`） |

### 7.2 相关文档

| 文档 | 内容 |
|-----|------|
| `AGENTS.md` | 项目级编码规范 |
| `docs/tui-chat-composer.md` | ChatComposer 详细文档 |

### 7.3 常量定义

| 常量 | 值 | 说明 |
|-----|-----|------|
| `MIN_OVERLAY_HEIGHT` | 8 | 最小弹窗高度 |
| `PROGRESS_ROW_HEIGHT` | 1 | 进度条行高 |
| `SPACER_ROWS_WITH_NOTES` | 1 | 有备注时的间距 |
| `SPACER_ROWS_NO_OPTIONS` | 0 | 无选项时的间距 |
| `DESIRED_SPACERS_BETWEEN_SECTIONS` | 2 | 默认区块间距 |
| `TIP_SEPARATOR` | " \| " | 底部提示分隔符 |

