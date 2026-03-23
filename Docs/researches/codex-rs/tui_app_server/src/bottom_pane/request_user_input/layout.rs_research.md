# Research: `layout.rs` - Request User Input Overlay Layout Engine

## 1. 场景与职责

### 1.1 文件定位

`layout.rs` 是 `codex-rs/tui_app_server/src/bottom_pane/request_user_input/` 模块的子模块，负责 **RequestUserInputOverlay** 的布局计算。该 overlay 是 TUI 应用中用于向用户展示问题并收集答案的模态弹窗组件。

### 1.2 核心职责

该文件的核心职责是：**根据可用空间动态计算并分配 UI 各区域的位置和尺寸**，确保在不同终端大小下都能合理展示：

- **问题文本 (Question)**：支持自动换行
- **选项列表 (Options)**：支持滚动和选择
- **备注输入区 (Notes)**：基于 ChatComposer 的文本输入
- **页脚提示 (Footer)**：操作指引和快捷键提示
- **进度指示 (Progress)**：多问题场景下的进度显示

### 1.3 使用场景

1. **单问题 + 选项**：用户从预定义选项中选择答案
2. **单问题 + 自由输入**：用户直接输入文本回答
3. **多问题向导**：多个问题按顺序或导航方式回答
4. **紧凑空间**：终端高度受限时的自适应布局
5. **未回答确认**：用户尝试提交时检查未回答问题

---

## 2. 功能点目的

### 2.1 布局计算主入口

```rust
pub(super) fn layout_sections(&self, area: Rect) -> LayoutSections
```

这是布局计算的统一入口，根据当前问题类型（有选项/无选项）分发到不同的布局策略。

### 2.2 有选项布局 (`layout_with_options`)

处理包含选项列表的问题布局：

- **空间优先级**：问题文本 → 选项列表 → 页脚 → 进度条 → 备注区
- **动态调整**：当空间不足时，优先保证选项列表至少显示1行
- **备注区可见性控制**：根据 `notes_visible` 状态决定是否分配空间

### 2.3 无选项布局 (`layout_without_options`)

处理纯文本输入问题：

- **紧凑模式**：当空间极度受限时，仅显示问题文本（截断）
- **正常模式**：分配空间给问题、备注输入、页脚和进度条

### 2.4 区域构建 (`build_layout_areas`)

将计算出的高度转换为具体的 `Rect` 区域，按从上到下的顺序排列：

1. Progress Area (进度指示)
2. Question Area (问题文本)
3. Options Area (选项列表)
4. Notes Area (备注输入)

### 2.5 关键设计决策

| 设计点 | 决策 | 理由 |
|--------|------|------|
| 选项最小高度 | 1行 | 确保用户至少能看到一个选项 |
| 问题文本截断 | 截断并添加省略号 | 防止超长问题占用全部空间 |
| 备注区扩展 | 吸收剩余空间 | 鼓励用户输入详细备注 |
| 页脚优先级 | 高 | 确保操作提示始终可见 |

---

## 3. 具体技术实现

### 3.1 数据结构

#### LayoutSections (布局结果)

```rust
pub(super) struct LayoutSections {
    pub(super) progress_area: Rect,      // 进度指示区域
    pub(super) question_area: Rect,      // 问题文本区域
    pub(super) question_lines: Vec<String>, // 换行后的问题文本行
    pub(super) options_area: Rect,       // 选项列表区域
    pub(super) notes_area: Rect,         // 备注输入区域
    pub(super) footer_lines: u16,        // 页脚行数
}
```

#### LayoutPlan (内部布局计划)

```rust
#[derive(Clone, Copy, Debug)]
struct LayoutPlan {
    progress_height: u16,
    question_height: u16,
    spacer_after_question: u16,
    options_height: u16,
    spacer_after_options: u16,
    notes_height: u16,
    footer_lines: u16,
}
```

#### 布局参数结构

```rust
// 有选项布局参数
struct OptionsLayoutArgs {
    available_height: u16,
    width: u16,
    question_height: u16,
    notes_pref_height: u16,
    footer_pref: u16,
    notes_visible: bool,
}

// 选项高度信息
struct OptionsHeights {
    preferred: u16,  // 首选高度（显示所有选项）
    full: u16,       // 完整高度（包含换行）
}
```

### 3.2 核心算法流程

#### 主布局分发流程

```
layout_sections(area)
├── 计算基础信息
│   ├── has_options: 当前问题是否有选项
│   ├── notes_visible: 备注区是否可见
│   ├── footer_pref: 页脚所需高度
│   ├── notes_pref_height: 备注区首选高度
│   └── question_lines: 换行后的问题文本
│
├── 分支选择
│   ├── 有选项 → layout_with_options()
│   └── 无选项 → layout_without_options()
│
└── 构建最终区域
    └── build_layout_areas(area, layout_plan)
```

#### 有选项正常布局算法 (`layout_with_options_normal`)

```
1. 计算最大选项高度 = 可用高度 - 问题高度
2. 选项高度 = min(首选高度, 最大高度).max(最小高度1)
3. 计算已用空间 = 问题高度 + 选项高度
4. 计算剩余空间 = 可用高度 - 已用空间

5. 空间不足时的调整
   ├── 计算所需额外空间 = 页脚 + 进度条 + 间隔
   ├── 如果剩余 < 所需额外空间
   │   └── 缩减选项高度以腾出空间
   └── 重新计算剩余空间

6. 分配进度条高度 (1行，如果有空间)

7. 根据备注区可见性分配空间
   ├── 备注区隐藏: 分配间隔 + 页脚
   └── 备注区可见: 分配间隔 + 备注区 + 页脚
```

### 3.3 空间分配优先级

从高到低的优先级：

1. **问题文本**：必须显示，但可能截断
2. **选项列表**：至少1行，尽可能显示更多
3. **页脚提示**：确保操作指引可见
4. **进度指示**：1行，如果有空间
5. **间隔**：保持视觉分隔
6. **备注区**：吸收剩余空间

### 3.4 关键计算细节

#### 问题文本换行

```rust
pub(super) fn wrapped_question_lines(&self, width: u16) -> Vec<String> {
    self.current_question()
        .map(|q| {
            textwrap::wrap(&q.question, width.max(1) as usize)
                .into_iter()
                .map(|line| line.to_string())
                .collect::<Vec<_>>()
        })
        .unwrap_or_default()
}
```

使用 `textwrap` crate 进行自动换行，确保问题文本在指定宽度内正确显示。

#### 选项高度计算

选项高度通过 `selection_popup_common::measure_rows_height` 计算，考虑：
- 选项标签长度
- 描述文本换行
- 选择状态指示器

#### 备注区高度计算

```rust
fn notes_input_height(&self, width: u16) -> u16 {
    let min_height = MIN_COMPOSER_HEIGHT; // 3
    self.composer
        .desired_height(width.max(1))
        .clamp(min_height, min_height.saturating_add(5))
}
```

备注区高度基于 ChatComposer 的期望高度，限制在 3-8 行之间。

---

## 4. 关键代码路径与文件引用

### 4.1 文件关系图

```
layout.rs
├── 依赖输入
│   ├── mod.rs: RequestUserInputOverlay 结构体定义
│   │   ├── has_options()
│   │   ├── notes_ui_visible()
│   │   ├── wrapped_question_lines()
│   │   ├── options_preferred_height()
│   │   ├── options_required_height()
│   │   ├── footer_required_height()
│   │   └── notes_input_height()
│   │
│   └── render.rs: 渲染实现
│       ├── render_ui() 调用 layout_sections()
│       └── cursor_pos_impl() 调用 layout_sections()
│
├── 外部依赖
│   ├── selection_popup_common.rs
│   │   └── measure_rows_height() - 选项高度测量
│   │
│   └── scroll_state.rs
│       └── ScrollState - 选项滚动状态
│
└── 输出
    └── LayoutSections - 布局结果供渲染使用
```

### 4.2 调用链

#### 渲染路径

```
Renderable::render(area, buf)
└── render_ui(area, buf)
    ├── 如果确认未回答弹窗激活
    │   └── render_unanswered_confirmation()
    └── 正常渲染
        ├── layout_sections(content_area) → LayoutSections
        ├── 渲染进度条
        ├── 渲染问题文本
        ├── 渲染选项列表
        ├── 渲染备注输入
        └── 渲染页脚
```

#### 光标位置路径

```
cursor_pos(area)
└── cursor_pos_impl(area)
    ├── layout_sections(content_area)
    └── 返回 notes_area 内的光标位置
```

### 4.3 测试路径

```
mod.rs tests
├── layout_allocates_all_wrapped_options_when_space_allows
│   └── 验证选项区高度等于测量高度
│
├── desired_height_keeps_spacers_and_preferred_options_visible
│   └── 验证间隔和首选高度正确
│
└── 多个快照测试验证渲染结果
```

---

## 5. 依赖与外部交互

### 5.1 直接依赖

| 依赖 | 来源 | 用途 |
|------|------|------|
| `ratatui::layout::Rect` | ratatui crate | 区域定义 |
| `RequestUserInputOverlay` | mod.rs | 父结构体，提供状态和方法 |
| `DESIRED_SPACERS_BETWEEN_SECTIONS` | mod.rs | 常量 (值为2) |
| `measure_rows_height` | selection_popup_common.rs | 选项高度测量 |

### 5.2 协议类型

定义在 `codex_protocol::request_user_input`：

```rust
// protocol/src/request_user_input.rs
pub struct RequestUserInputQuestion {
    pub id: String,
    pub header: String,
    pub question: String,
    pub is_other: bool,
    pub is_secret: bool,
    pub options: Option<Vec<RequestUserInputQuestionOption>>,
}

pub struct RequestUserInputQuestionOption {
    pub label: String,
    pub description: String,
}
```

### 5.3 相关模块交互

```
request_user_input/
├── mod.rs          - 状态管理和事件处理
├── layout.rs       - 布局计算 (本文件)
└── render.rs       - 渲染实现

依赖的兄弟模块:
├── selection_popup_common.rs - 通用选择列表渲染
├── scroll_state.rs           - 滚动状态管理
└── chat_composer.rs          - 文本输入组件
```

---

## 6. 风险、边界与改进建议

### 6.1 已知边界条件

#### 高度极端情况

| 场景 | 行为 | 风险 |
|------|------|------|
| 高度 < 问题文本高度 | 截断问题文本 | 用户可能看不到完整问题 |
| 高度 = 最小值 (8行) | 触发紧凑布局 | 备注区可能被完全隐藏 |
| 宽度 = 1 | 所有文本换行为单列字符 | 可用性极差 |

#### 宽度极端情况

```rust
// 代码中多处使用 width.max(1) 防止除以零
let inner_width = inner.width.max(1);
```

### 6.2 潜在风险

#### 风险1：布局与渲染不一致

**问题**：`layout.rs` 计算的高度与 `render.rs` 实际渲染的高度可能不一致，导致视觉错位。

**缓解**：测试用例 `layout_allocates_all_wrapped_options_when_space_allows` 验证一致性。

#### 风险2：选项高度测量性能

**问题**：`measure_rows_height` 需要遍历所有选项并计算换行，选项数量大时可能影响性能。

**当前状态**：选项数量通常较少（<20），风险可控。

#### 风险3：状态同步

**问题**：`layout_sections` 被多次调用（渲染、光标位置），如果状态在两次调用间变化，可能导致闪烁。

**缓解**：布局计算不修改状态，仅读取。

### 6.3 改进建议

#### 建议1：缓存布局结果

```rust
// 当前：每次渲染都重新计算
// 建议：添加布局缓存
struct RequestUserInputOverlay {
    // ...
    cached_layout: Option<(Rect, LayoutSections)>,
}

fn layout_sections(&mut self, area: Rect) -> &LayoutSections {
    if let Some((cached_area, cached)) = &self.cached_layout {
        if cached_area == &area {
            return cached;
        }
    }
    let sections = self.compute_layout_sections(area);
    self.cached_layout = Some((area, sections));
    &self.cached_layout.as_ref().unwrap().1
}
```

#### 建议2：更智能的问题文本截断

当前实现直接截断问题文本行，可以考虑：
- 添加 "..." 指示截断
- 提供滚动查看完整问题的方式

#### 建议3：响应式间隔调整

当前 `DESIRED_SPACERS_BETWEEN_SECTIONS` 是固定值2，可以根据终端高度动态调整：

```rust
fn desired_spacers(available_height: u16) -> u16 {
    match available_height {
        0..=10 => 0,  // 紧凑：无间隔
        11..=20 => 1, // 中等：1行间隔
        _ => 2,       // 宽松：2行间隔
    }
}
```

#### 建议4：提取布局常量

当前常量分散在代码中，建议集中管理：

```rust
// layout.rs
pub mod constants {
    pub const MIN_OVERLAY_HEIGHT: u16 = 8;
    pub const MIN_OPTIONS_HEIGHT: u16 = 1;
    pub const PROGRESS_HEIGHT: u16 = 1;
    pub const DEFAULT_SPACERS: u16 = 2;
    pub const MIN_COMPOSER_HEIGHT: u16 = 3;
    pub const MAX_COMPOSER_HEIGHT: u16 = 8;
}
```

### 6.4 测试覆盖建议

当前测试主要集中在 `mod.rs` 中，建议为 `layout.rs` 添加专门单元测试：

```rust
#[cfg(test)]
mod layout_tests {
    use super::*;
    
    #[test]
    fn layout_with_zero_height() {
        // 验证零高度不panic
    }
    
    #[test]
    fn layout_with_zero_width() {
        // 验证零宽度不panic
    }
    
    #[test]
    fn layout_sections_sum_equals_area() {
        // 验证各部分高度之和等于输入区域
    }
}
```

---

## 7. 总结

`layout.rs` 是 RequestUserInputOverlay 的核心布局引擎，通过精心设计的算法在有限空间内平衡多个 UI 元素的需求。其主要特点：

1. **自适应性强**：支持有选项/无选项两种模式，自动适应不同终端尺寸
2. **优先级明确**：确保核心信息（问题、选项）优先显示
3. **与渲染分离**：纯计算逻辑，便于测试和维护
4. **防御性编程**：多处使用 `saturating_add/sub` 和 `max(1)` 防止溢出

理解该文件需要熟悉 ratatui 的布局模型、textwrap 的换行算法，以及整个 request_user_input 模块的状态管理设计。
