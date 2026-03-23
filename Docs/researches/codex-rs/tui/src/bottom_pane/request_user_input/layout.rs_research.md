# Research: `codex-rs/tui/src/bottom_pane/request_user_input/layout.rs`

## 1. 场景与职责

### 1.1 文件定位

`layout.rs` 是 `request_user_input` 模块的私有子模块，负责 **RequestUserInputOverlay** 组件的布局计算。该组件是 Codex TUI 中用于向用户请求输入的模态弹窗界面，支持两种问题类型：

1. **选项型问题（Options）**：用户从预定义选项中选择，可附加备注
2. **自由文本问题（Freeform）**：用户直接输入文本回答

### 1.2 核心职责

该模块的核心职责是**计算自适应布局**，确保：

- 在有限的高度空间内合理分配各区域（进度、问题、选项、备注输入、页脚）
- 当空间紧张时优雅地折叠/截断内容
- 保持视觉层次和可读性
- 支持选项的滚动视图和文本换行

### 1.3 调用上下文

```
BottomPane (mod.rs)
  └── push_user_input_request()
        └── RequestUserInputOverlay::new()
              └── layout.rs (布局计算)

渲染流程：
render.rs::render_ui()
  └── layout_sections()  // 计算布局
        └── build_layout_areas()  // 生成 Rect 区域
```

---

## 2. 功能点目的

### 2.1 布局区域划分

布局将可用空间划分为五个主要区域（从上到下）：

| 区域 | 说明 | 高度计算 |
|------|------|----------|
| `progress_area` | 问题进度指示器（Question 1/3） | 固定 1 行 |
| `question_area` | 问题文本显示区 | 根据换行后行数动态计算 |
| `options_area` | 选项列表区（仅选项型问题） | 根据选项数量和宽度动态计算 |
| `notes_area` | 备注输入区（ChatComposer） | 最小 3 行，最大 8 行 |
| 页脚 | 操作提示（Enter 提交、Tab 添加备注等） | 根据提示文本和宽度动态换行 |

### 2.2 布局策略

#### 2.2.1 有选项布局（`layout_with_options`）

```rust
// 核心逻辑：
// 1. 确保选项区域至少有 1 行高度
// 2. 问题文本过长时截断
// 3. 优先保证进度条 + 页脚 + 间隔的空间
// 4. 剩余空间分配给选项和备注
```

**空间分配优先级**：
1. 问题文本（必需，可截断）
2. 进度条（1 行，如果有空间）
3. 页脚（必需）
4. 选项（至少 1 行，可收缩）
5. 备注（可选，占用剩余空间）

#### 2.2.2 无选项布局（`layout_without_options`）

```rust
// 核心逻辑：
// 1. 空间极度紧张时进入 "tight" 模式，截断问题文本
// 2. 正常模式下：问题 + 备注 + 页脚 + 进度条
// 3. 备注区域可占用所有剩余空间
```

### 2.3 关键布局参数

```rust
// 来自 mod.rs 的共享常量
const DESIRED_SPACERS_BETWEEN_SECTIONS: u16 = 2;  // 期望的段落间距
const MIN_COMPOSER_HEIGHT: u16 = 3;               // 备注输入最小高度

// layout.rs 本地常量
const MIN_OVERLAY_HEIGHT: usize = 8;              // 弹窗最小高度
const PROGRESS_ROW_HEIGHT: usize = 1;             // 进度条固定高度
const SPACER_ROWS_WITH_NOTES: usize = 1;          // 有备注时的间距
const SPACER_ROWS_NO_OPTIONS: usize = 0;          // 无选项时的间距
```

---

## 3. 具体技术实现

### 3.1 数据结构

#### 3.1.1 LayoutSections（布局结果）

```rust
pub(super) struct LayoutSections {
    pub(super) progress_area: Rect,      // 进度条区域
    pub(super) question_area: Rect,      // 问题文本区域
    pub(super) question_lines: Vec<String>, // 换行后的问题文本
    pub(super) options_area: Rect,       // 选项列表区域
    pub(super) notes_area: Rect,         // 备注输入区域
    pub(super) footer_lines: u16,        // 页脚行数
}
```

#### 3.1.2 LayoutPlan（布局计划）

```rust
#[derive(Clone, Copy, Debug)]
struct LayoutPlan {
    progress_height: u16,
    question_height: u16,
    spacer_after_question: u16,  // 问题与选项间的间距
    options_height: u16,
    spacer_after_options: u16,   // 选项与备注间的间距
    notes_height: u16,
    footer_lines: u16,
}
```

#### 3.1.3 布局参数结构体

```rust
// 选项布局参数
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
    preferred: u16,  // 选项首选高度（完整显示所有选项）
    full: u16,       // 选项所需高度（考虑换行）
}
```

### 3.2 核心算法流程

#### 3.2.1 主入口：`layout_sections`

```rust
pub(super) fn layout_sections(&self, area: Rect) -> LayoutSections {
    // 1. 判断当前问题类型
    let has_options = self.has_options();
    let notes_visible = !has_options || self.notes_ui_visible();
    
    // 2. 计算各区域首选高度
    let footer_pref = self.footer_required_height(area.width);
    let notes_pref_height = self.notes_input_height(area.width);
    let mut question_lines = self.wrapped_question_lines(area.width);
    let question_height = question_lines.len() as u16;
    
    // 3. 根据问题类型选择布局策略
    let layout = if has_options {
        self.layout_with_options(...)
    } else {
        self.layout_without_options(...)
    };
    
    // 4. 根据计划构建实际 Rect 区域
    let (progress_area, question_area, options_area, notes_area) =
        self.build_layout_areas(area, layout);
    
    LayoutSections { ... }
}
```

#### 3.2.2 有选项布局算法

```rust
fn layout_with_options(&self, args: OptionsLayoutArgs, question_lines: &mut Vec<String>) -> LayoutPlan {
    // 步骤 1: 确保至少有 1 行给选项
    let min_options_height = available_height.min(1);
    let max_question_height = available_height.saturating_sub(min_options_height);
    
    // 步骤 2: 问题文本过长时截断
    if question_height > max_question_height {
        question_height = max_question_height;
        question_lines.truncate(question_height as usize);
    }
    
    // 步骤 3: 计算选项高度（首选 vs 最小）
    let max_options_height = available_height.saturating_sub(question_height);
    let mut options_height = options.preferred.min(max_options_height).max(min_options_height);
    
    // 步骤 4: 计算剩余空间
    let used = question_height.saturating_add(options_height);
    let mut remaining = available_height.saturating_sub(used);
    
    // 步骤 5: 确保页脚和进度条的空间
    let desired_spacers = if notes_visible { 1 } else { DESIRED_SPACERS_BETWEEN_SECTIONS };
    let required_extra = footer_pref.saturating_add(1).saturating_add(desired_spacers);
    
    if remaining < required_extra {
        // 空间不足：收缩选项区域
        let deficit = required_extra.saturating_sub(remaining);
        let reducible = options_height.saturating_sub(min_options_height);
        let reduce_by = deficit.min(reducible);
        options_height = options_height.saturating_sub(reduce_by);
        remaining = remaining.saturating_add(reduce_by);
    }
    
    // 步骤 6: 分配进度条（1 行，如果有空间）
    let mut progress_height = 0;
    if remaining > 0 {
        progress_height = 1;
        remaining = remaining.saturating_sub(1);
    }
    
    // 步骤 7: 分配页脚和间距
    // ...（根据 notes_visible 状态决定布局）
}
```

#### 3.2.3 区域构建：`build_layout_areas`

```rust
fn build_layout_areas(&self, area: Rect, heights: LayoutPlan) -> (Rect, Rect, Rect, Rect) {
    let mut cursor_y = area.y;
    
    // 从上到下依次构建区域
    let progress_area = Rect { x: area.x, y: cursor_y, width: area.width, height: heights.progress_height };
    cursor_y = cursor_y.saturating_add(heights.progress_height);
    
    let question_area = Rect { x: area.x, y: cursor_y, width: area.width, height: heights.question_height };
    cursor_y = cursor_y.saturating_add(heights.question_height);
    cursor_y = cursor_y.saturating_add(heights.spacer_after_question);
    
    let options_area = Rect { x: area.x, y: cursor_y, width: area.width, height: heights.options_height };
    cursor_y = cursor_y.saturating_add(heights.options_height);
    cursor_y = cursor_y.saturating_add(heights.spacer_after_options);
    
    let notes_area = Rect { x: area.x, y: cursor_y, width: area.width, height: heights.notes_height };
    
    (progress_area, question_area, options_area, notes_area)
}
```

### 3.3 与渲染的协作

布局计算的结果被 `render.rs` 使用：

```rust
// render.rs::render_ui()
fn render_ui(&self, area: Rect, buf: &mut Buffer) {
    // 1. 渲染菜单背景
    let content_area = render_menu_surface(area, buf);
    
    // 2. 计算布局
    let sections = self.layout_sections(content_area);
    
    // 3. 在各区域渲染内容
    Paragraph::new(progress_line).render(sections.progress_area, buf);
    // ... 渲染问题、选项、备注、页脚
}
```

### 3.4 依赖的外部计算

布局模块依赖 `mod.rs` 提供的以下方法：

```rust
// 问题文本换行
pub(super) fn wrapped_question_lines(&self, width: u16) -> Vec<String> {
    textwrap::wrap(&q.question, width.max(1) as usize)
        .into_iter()
        .map(|line| line.to_string())
        .collect()
}

// 选项首选高度（完整显示）
pub(super) fn options_preferred_height(&self, width: u16) -> u16 {
    let rows = self.option_rows();
    measure_rows_height(&rows, &state, rows.len(), width.max(1))
}

// 选项所需高度（最小）
pub(super) fn options_required_height(&self, width: u16) -> u16 {
    // 类似 preferred，但用于空间紧张时
}

// 备注输入高度
fn notes_input_height(&self, width: u16) -> u16 {
    let min_height = MIN_COMPOSER_HEIGHT;  // 3
    self.composer.desired_height(width.max(1))
        .clamp(min_height, min_height.saturating_add(5))  // 3-8 行
}

// 页脚所需高度
pub(super) fn footer_required_height(&self, width: u16) -> u16 {
    self.footer_tip_lines(width).len() as u16
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 文件结构

```
codex-rs/tui/src/bottom_pane/request_user_input/
├── mod.rs          # 主模块：状态管理、输入处理、测试
├── layout.rs       # 布局计算（本研究对象）
├── render.rs       # 渲染实现
└── snapshots/      # insta 快照测试
```

### 4.2 关键代码路径

#### 初始化路径

```
codex-rs/tui/src/bottom_pane/mod.rs:924
    pub fn push_user_input_request(&mut self, request: RequestUserInputEvent)
        └── RequestUserInputOverlay::new(...)
            └── codex-rs/tui/src/bottom_pane/request_user_input/mod.rs:139
                fn reset_for_request()  // 初始化答案状态
```

#### 布局计算路径

```
codex-rs/tui/src/bottom_pane/request_user_input/layout.rs:19
    pub(super) fn layout_sections(&self, area: Rect) -> LayoutSections
        ├── line 27-47: 判断问题类型，选择布局策略
        ├── line 63-95: layout_with_options()
        │   └── line 99-196: layout_with_options_normal()
        ├── line 203-222: layout_without_options()
        │   ├── line 225-244: layout_without_options_tight()
        │   └── line 247-279: layout_without_options_normal()
        ├── line 282-326: build_layout_areas()
        └── 返回 LayoutSections
```

#### 渲染路径

```
codex-rs/tui/src/bottom_pane/request_user_input/render.rs:248
    pub(super) fn render_ui(&self, area: Rect, buf: &mut Buffer)
        ├── line 258: render_menu_surface(area, buf)
        ├── line 262: self.layout_sections(content_area)
        ├── line 267-279: 渲染进度条
        ├── line 282-305: 渲染问题文本
        ├── line 308-328: 渲染选项列表
        ├── line 330-332: 渲染备注输入
        └── line 334-383: 渲染页脚提示
```

### 4.3 外部依赖

#### 协议定义

```
codex-rs/protocol/src/request_user_input.rs
    ├── RequestUserInputEvent    # 输入请求事件
    ├── RequestUserInputQuestion # 问题定义
    ├── RequestUserInputQuestionOption # 选项定义
    └── RequestUserInputResponse # 响应格式
```

#### 共享组件

```
codex-rs/tui/src/bottom_pane/selection_popup_common.rs
    ├── GenericDisplayRow        # 选项行数据结构
    ├── measure_rows_height()    # 测量选项高度
    ├── render_rows()            # 渲染选项列表
    └── menu_surface_inset()     # 菜单内边距计算

codex-rs/tui/src/bottom_pane/scroll_state.rs
    └── ScrollState              # 滚动/选择状态

codex-rs/tui/src/bottom_pane/chat_composer.rs
    └── ChatComposer             # 备注输入组件
```

---

## 5. 依赖与外部交互

### 5.1 输入依赖

| 来源 | 方法/字段 | 用途 |
|------|----------|------|
| `mod.rs` | `has_options()` | 判断是否有选项 |
| `mod.rs` | `notes_ui_visible()` | 判断备注 UI 是否可见 |
| `mod.rs` | `wrapped_question_lines()` | 获取换行后的问题文本 |
| `mod.rs` | `options_preferred_height()` | 获取选项首选高度 |
| `mod.rs` | `options_required_height()` | 获取选项最小高度 |
| `mod.rs` | `notes_input_height()` | 获取备注输入高度 |
| `mod.rs` | `footer_required_height()` | 获取页脚所需高度 |
| `popup_consts.rs` | `DESIRED_SPACERS_BETWEEN_SECTIONS` | 段落间距常量 |

### 5.2 输出消费

| 消费者 | 使用方法 | 用途 |
|--------|---------|------|
| `render.rs` | `layout_sections()` | 获取各区域 Rect 进行渲染 |
| `render.rs` | `LayoutSections.question_lines` | 渲染问题文本 |
| `render.rs` | `LayoutSections.footer_lines` | 计算页脚位置 |

### 5.3 协议交互

布局模块本身不直接与协议层交互，但依赖的数据结构来自协议定义：

```rust
// codex-rs/protocol/src/request_user_input.rs
pub struct RequestUserInputQuestion {
    pub id: String,
    pub header: String,
    pub question: String,
    pub is_other: bool,      // 是否显示"None of the above"选项
    pub is_secret: bool,     // 备注输入是否掩码显示
    pub options: Option<Vec<RequestUserInputQuestionOption>>,
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知边界情况

#### 6.1.1 空间极度紧张（Tight Layout）

当可用高度不足以显示所有内容时，布局会进入 "tight" 模式：

```rust
// layout.rs:225-244
fn layout_without_options_tight(...) -> LayoutPlan {
    // 截断问题文本以适应可用空间
    let adjusted_question_height = question_height.min(max_question_height);
    question_lines.truncate(adjusted_question_height as usize);
    
    LayoutPlan {
        question_height: adjusted_question_height,
        progress_height: 0,  // 隐藏进度条
        footer_lines: 0,     // 隐藏页脚
        // ...
    }
}
```

**风险**：当高度小于 8（`MIN_OVERLAY_HEIGHT`）时，用户体验可能严重受损。

#### 6.1.2 选项文本过长

当选项标签或描述过长时，`selection_popup_common.rs` 中的 `wrap_two_column_row` 会处理换行：

```rust
// 两列布局：标签左对齐，描述右对齐
// 如果标签过长，会占用描述列的空间
```

**风险**：极端情况下，描述列可能被完全挤压。

#### 6.1.3 页脚提示换行

页脚提示使用自定义的 `wrap_footer_tips` 算法，确保单个提示不会被分割：

```rust
// mod.rs:481-520
fn wrap_footer_tips(&self, width: u16, tips: Vec<FooterTip>) -> Vec<Vec<FooterTip>> {
    // 只在提示分隔符处换行，不分割单个提示
}
```

### 6.2 潜在风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 整数溢出 | 大量使用 `saturating_add`/`saturating_sub` | 已使用饱和运算，但需确保逻辑正确 |
| 布局抖动 | 频繁调整窗口大小可能导致布局不稳定 | 布局计算是确定性的，无状态依赖 |
| 测试覆盖 | 复杂布局场景的测试可能不足 | 已有 12 个 insta 快照测试覆盖主要场景 |
| 多字节字符 | Unicode 宽度计算可能不准确 | 使用 `unicode-width` crate |

### 6.3 改进建议

#### 6.3.1 代码结构优化

1. **提取布局策略模式**：
   当前 `layout_with_options` 和 `layout_without_options` 有大量重复逻辑，可考虑使用策略模式统一。

2. **增加布局调试工具**：
   添加 `#[cfg(feature = "debug-layout")]` 的调试输出，帮助开发者理解布局决策过程。

#### 6.3.2 功能增强

1. **响应式布局阈值**：
   当前 `DESIRED_SPACERS_BETWEEN_SECTIONS = 2` 是硬编码，可考虑根据终端 DPI 或字体大小动态调整。

2. **选项区域最小高度配置**：
   当前 `min_options_height = available_height.min(1)` 确保至少 1 行，但在极端情况下可能需要可配置。

#### 6.3.3 测试增强

1. **边界值测试**：
   添加以下场景的测试：
   - 高度 = 0, 1, 2, ... 的渐进测试
   - 宽度 = 0, 1, ... 的渐进测试
   - 超长问题文本（>1000 字符）
   - 超多选项（>100 个）

2. **布局一致性测试**：
   验证 `layout_sections` 返回的区域总和等于输入区域：
   ```rust
   #[test]
   fn layout_areas_sum_to_input() {
       // 验证 progress + question + spacers + options + notes + footer = area.height
   }
   ```

#### 6.3.4 文档改进

1. **添加布局示意图**：
   在代码注释中添加 ASCII 布局图，帮助理解区域划分。

2. **记录布局不变量**：
   明确记录以下不变量：
   - `options_area.height >= 1`（当有选项时）
   - `notes_area.height >= MIN_COMPOSER_HEIGHT`（当备注可见时）
   - 所有区域宽度相等

### 6.4 相关 TODO

代码中存在的相关 TODO：

```rust
// mod.rs:1008-1009
// TODO: Emit interrupted request_user_input results (including committed answers)
// once core supports persisting them reliably without follow-up turn issues.
```

此 TODO 与布局无关，但表明该功能仍在演进中。

---

## 7. 总结

`layout.rs` 是 RequestUserInputOverlay 的核心布局引擎，负责在有限的空间内合理分配各 UI 区域。其设计特点：

1. **自适应**：根据内容动态调整各区域高度
2. **容错性**：在空间紧张时优雅降级
3. **分离性**：布局计算与渲染分离，便于测试和维护
4. **一致性**：与其他 bottom-pane 弹窗共享布局工具（`selection_popup_common.rs`）

理解该模块需要同时熟悉 `mod.rs` 的状态管理和 `render.rs` 的渲染逻辑，三者协同工作构成完整的用户输入交互体验。
