# ListSelectionView 研究文档

## 文件信息

- **目标文件**: `codex-rs/tui/src/bottom_pane/list_selection_view.rs`
- **文件行数**: 1834 行（含测试代码）
- **主要语言**: Rust
- **所属模块**: `codex-tui` crate 的 bottom_pane 子模块

---

## 1. 场景与职责

### 1.1 定位

`ListSelectionView` 是 Codex TUI（终端用户界面）中**通用的列表选择弹窗组件**，属于 bottom pane（底部面板）视图栈的一部分。它提供可交互的列表选择体验，支持搜索过滤、键盘导航、侧边内容预览等高级功能。

### 1.2 核心职责

| 职责 | 说明 |
|------|------|
| **列表渲染** | 渲染可选择的项目列表，支持标题、描述、快捷键提示 |
| **键盘导航** | 支持 ↑/↓、Ctrl+P/N、j/k 等快捷键进行项目选择 |
| **搜索过滤** | 可选的实时搜索功能，根据 `search_value` 过滤项目 |
| **数字快捷键** | 非搜索模式下支持数字键（1-9）快速选择 |
| **侧边内容** | 支持并排（side-by-side）或堆叠（stacked）的富内容预览 |
| **回调机制** | 选择变更、确认、取消时触发回调函数 |
| **响应式布局** | 根据终端宽度自动调整布局（列表/并排/堆叠） |

### 1.3 使用场景

该组件被广泛用于以下场景：

1. **主题选择器** (`/theme`) - 带实时预览的语法主题选择
2. **审批弹窗** (ApprovalOverlay) - 命令执行、权限申请、补丁应用的确认
3. **反馈收集** - 用户反馈类别选择、上传同意确认
4. **模型选择** - AI 模型和推理 effort 的选择
5. **技能选择** - `/skills` 命令的技能开关
6. **连接器选择** - 连接器（connectors）配置选择
7. **状态栏设置** - 自定义状态栏项目选择

---

## 2. 功能点目的

### 2.1 主要功能模块

```
┌─────────────────────────────────────────────────────────────┐
│                    ListSelectionView                         │
├─────────────────────────────────────────────────────────────┤
│  Header (标题/副标题)                                        │
├─────────────────────────────────────────────────────────────┤
│  Search Bar (可选搜索栏)                                     │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────────────┐  ┌─────────────────────────────┐  │
│  │                      │  │                             │  │
│  │   List Items         │  │   Side Content (可选)       │  │
│  │   - Item 1           │  │   - 预览面板                │  │
│  │   - Item 2 (selected)│  │   - 语法高亮                │  │
│  │   - Item 3           │  │   - 自定义内容              │  │
│  │                      │  │                             │  │
│  └──────────────────────┘  └─────────────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│  Footer Note (可选备注)                                      │
│  Footer Hint (操作提示，如 "Press Enter to confirm")        │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 各功能点详细说明

#### 2.2.1 项目选择 (SelectionItem)

每个列表项 `SelectionItem` 包含：

| 字段 | 类型 | 用途 |
|------|------|------|
| `name` | `String` | 显示名称 |
| `name_prefix_spans` | `Vec<Span>` | 名称前的样式化前缀（如选择指示器） |
| `display_shortcut` | `Option<KeyBinding>` | 显示的快捷键提示 |
| `description` | `Option<String>` | 项目描述（灰色显示） |
| `selected_description` | `Option<String>` | 选中时的替代描述 |
| `is_current` | `bool` | 标记当前已选中的项目 |
| `is_default` | `bool` | 标记默认项目 |
| `is_disabled` | `bool` | 禁用状态 |
| `actions` | `Vec<SelectionAction>` | 确认时执行的动作 |
| `dismiss_on_select` | `bool` | 选择后是否关闭弹窗 |
| `search_value` | `Option<String>` | 搜索时匹配的文本 |
| `disabled_reason` | `Option<String>` | 禁用原因说明 |

#### 2.2.2 搜索过滤

- 通过 `is_searchable` 启用/禁用搜索
- 实时过滤：输入时立即更新列表
- 匹配逻辑：对 `search_value` 进行大小写不敏感的子串匹配
- 搜索占位符：支持 `search_placeholder` 提示文本

#### 2.2.3 侧边内容 (Side Content)

支持两种布局模式：

**Side-by-Side 模式**（宽终端）：
- 列表和预览并排显示
- 通过 `SideContentWidth` 控制宽度（`Fixed` 或 `Half`）
- 最小宽度阈值：`MIN_LIST_WIDTH_FOR_SIDE` (40列)

**Stacked 模式**（窄终端）：
- 预览内容显示在列表下方
- 支持独立的 `stacked_side_content` 渲染器

#### 2.2.4 列宽模式 (ColumnWidthMode)

控制名称和描述列的宽度分配：

| 模式 | 说明 |
|------|------|
| `AutoVisible` | 仅根据可见行计算列宽（默认） |
| `AutoAllRows` | 根据所有行计算列宽（滚动时列宽稳定） |
| `Fixed` | 固定 30%/70% 分割 |

---

## 3. 具体技术实现

### 3.1 关键数据结构

```rust
// 运行时状态结构
pub(crate) struct ListSelectionView {
    view_id: Option<&'static str>,           // 视图标识，用于外部刷新
    footer_note: Option<Line<'static>>,      // 底部备注
    footer_hint: Option<Line<'static>>,      // 底部操作提示
    items: Vec<SelectionItem>,               // 原始项目列表
    state: ScrollState,                      // 滚动/选择状态
    complete: bool,                          // 是否完成（关闭弹窗）
    app_event_tx: AppEventSender,            // 应用事件发送器
    is_searchable: bool,                     // 是否可搜索
    search_query: String,                    // 当前搜索查询
    search_placeholder: Option<String>,      // 搜索占位符
    col_width_mode: ColumnWidthMode,         // 列宽计算模式
    filtered_indices: Vec<usize>,            // 过滤后的索引映射
    last_selected_actual_idx: Option<usize>, // 最后选中的实际索引
    header: Box<dyn Renderable>,             // 头部渲染器
    initial_selected_idx: Option<usize>,     // 初始选中索引
    side_content: Box<dyn Renderable>,       // 侧边内容渲染器
    side_content_width: SideContentWidth,    // 侧边内容宽度模式
    side_content_min_width: u16,             // 侧边内容最小宽度
    stacked_side_content: Option<Box<dyn Renderable>>, // 堆叠模式侧边内容
    preserve_side_content_bg: bool,          // 是否保留侧边内容背景色
    on_selection_changed: OnSelectionChangedCallback, // 选择变更回调
    on_cancel: OnCancelCallback,             // 取消回调
}
```

### 3.2 关键流程

#### 3.2.1 初始化流程 (`new`)

```rust
pub fn new(params: SelectionViewParams, app_event_tx: AppEventSender) -> Self {
    // 1. 构建头部（合并 title/subtitle 到 header）
    let mut header = params.header;
    if params.title.is_some() || params.subtitle.is_some() {
        header = Box::new(ColumnRenderable::with([...]));
    }
    
    // 2. 初始化状态
    let mut s = Self { ... };
    
    // 3. 应用初始过滤
    s.apply_filter();
    s
}
```

#### 3.2.2 过滤流程 (`apply_filter`)

```rust
fn apply_filter(&mut self) {
    // 1. 保存当前选择
    let previously_selected = self.selected_actual_idx()
        .or_else(|| ... /* is_current */)
        .or_else(|| self.initial_selected_idx.take());
    
    // 2. 执行过滤
    if self.is_searchable && !self.search_query.is_empty() {
        self.filtered_indices = self.items.iter()
            .positions(|item| item.search_value
                .as_ref()
                .is_some_and(|v| v.to_lowercase().contains(&query_lower)))
            .collect();
    } else {
        self.filtered_indices = (0..self.items.len()).collect();
    }
    
    // 3. 恢复选择状态
    self.state.selected_idx = ...;
    
    // 4. 触发选择变更回调
    if new_actual != previously_selected {
        self.fire_selection_changed();
    }
}
```

#### 3.2.3 键盘事件处理 (`handle_key_event`)

```rust
fn handle_key_event(&mut self, key_event: KeyEvent) {
    match key_event {
        // 向上导航：↑, Ctrl+P, ^P, k (非搜索模式)
        KeyEvent { code: KeyCode::Up, .. } 
        | KeyEvent { code: KeyCode::Char('p'), modifiers: CONTROL, .. }
        | KeyEvent { code: KeyCode::Char('\u{0010}'), .. } => self.move_up(),
        
        // 向下导航：↓, Ctrl+N, ^N, j (非搜索模式)
        KeyEvent { code: KeyCode::Down, .. }
        | KeyEvent { code: KeyCode::Char('n'), modifiers: CONTROL, .. }
        | KeyEvent { code: KeyCode::Char('\u{000e}'), .. } => self.move_down(),
        
        // 搜索输入
        KeyEvent { code: KeyCode::Char(c), .. } if self.is_searchable 
            && !modifiers.contains(CONTROL | ALT) => {
            self.search_query.push(c);
            self.apply_filter();
        }
        
        // 数字快捷键（非搜索模式）
        KeyEvent { code: KeyCode::Char(c), .. } if !self.is_searchable => {
            if let Some(idx) = c.to_digit(10).map(|d| d as usize - 1) {
                self.state.selected_idx = Some(idx);
                self.accept();
            }
        }
        
        // 确认选择
        KeyEvent { code: KeyCode::Enter, .. } => self.accept(),
        
        // 取消/关闭
        KeyEvent { code: KeyCode::Esc, .. } => self.on_ctrl_c(),
        
        // 退格（搜索模式）
        KeyEvent { code: KeyCode::Backspace, .. } if self.is_searchable => {
            self.search_query.pop();
            self.apply_filter();
        }
    }
}
```

#### 3.2.4 确认选择流程 (`accept`)

```rust
fn accept(&mut self) {
    // 1. 获取选中的项目
    let selected_item = self.state.selected_idx
        .and_then(|idx| self.filtered_indices.get(idx))
        .and_then(|actual_idx| self.items.get(*actual_idx));
    
    // 2. 检查是否可用
    if let Some(item) = selected_item
        && item.disabled_reason.is_none()
        && !item.is_disabled 
    {
        // 3. 保存选择索引
        self.last_selected_actual_idx = Some(*actual_idx);
        
        // 4. 执行所有动作
        for act in &item.actions {
            act(&self.app_event_tx);
        }
        
        // 5. 根据配置关闭弹窗
        if item.dismiss_on_select {
            self.complete = true;
        }
    } else if selected_item.is_none() {
        // 无匹配项时触发取消回调
        if let Some(cb) = &self.on_cancel {
            cb(&self.app_event_tx);
        }
        self.complete = true;
    }
}
```

#### 3.2.5 渲染流程 (`render`)

```rust
fn render(&self, area: Rect, buf: &mut Buffer) {
    // 1. 分割区域：内容区 + 底部区
    let [content_area, footer_area] = Layout::vertical([...]).areas(area);
    
    // 2. 渲染菜单表面（背景+边框）
    let content_area = render_menu_surface(outer_content_area, buf);
    
    // 3. 计算布局参数
    let inner_width = popup_content_width(outer_content_area.width);
    let side_w = self.side_layout_width(inner_width);
    let effective_rows_width = ...;
    
    // 4. 垂直布局：header + gap + search + list + gap + stacked_side
    let [header_area, _, search_area, list_area, _, stacked_side_area] = 
        Layout::vertical([...]).areas(content_area);
    
    // 5. 渲染头部
    self.header.render(header_area, buf);
    
    // 6. 渲染搜索栏
    if self.is_searchable { ... }
    
    // 7. 渲染列表行
    match self.col_width_mode {
        ColumnWidthMode::AutoVisible => render_rows(...),
        ColumnWidthMode::AutoAllRows => render_rows_stable_col_widths(...),
        ColumnWidthMode::Fixed => render_rows_with_col_width_mode(...),
    }
    
    // 8. 渲染侧边内容
    if let Some(sw) = side_w {
        // Side-by-side 模式
        self.side_content.render(side_area, buf);
    } else if stacked_side_area.height > 0 {
        // Stacked 模式
        self.stacked_side_content().render(stacked_side_area, buf);
    }
    
    // 9. 渲染底部备注和提示
    ...
}
```

### 3.3 布局算法

#### 3.3.1 并排布局宽度计算

```rust
pub(crate) fn side_by_side_layout_widths(
    content_width: u16,
    side_content_width: SideContentWidth,
    side_content_min_width: u16,
) -> Option<(u16, u16)> {
    let side_width = match side_content_width {
        SideContentWidth::Fixed(0) => return None,
        SideContentWidth::Fixed(width) => width,
        SideContentWidth::Half => content_width.saturating_sub(SIDE_CONTENT_GAP) / 2,
    };
    
    // 检查侧边宽度是否满足最小要求
    if side_width < side_content_min_width {
        return None;
    }
    
    // 检查剩余列表宽度是否可用
    let list_width = content_width.saturating_sub(SIDE_CONTENT_GAP + side_width);
    (list_width >= MIN_LIST_WIDTH_FOR_SIDE).then_some((list_width, side_width))
}
```

#### 3.3.2 高度计算

```rust
fn desired_height(&self, width: u16) -> u16 {
    let inner_width = popup_content_width(width);
    
    // 根据布局模式计算有效行宽度
    let effective_rows_width = if let Some(side_w) = self.side_layout_width(inner_width) {
        Self::rows_width(width).saturating_sub(SIDE_CONTENT_GAP + side_w)
    } else {
        Self::rows_width(width)
    };
    
    // 计算各部分高度
    let rows_height = match self.col_width_mode { ... };
    let mut height = self.header.desired_height(inner_width);
    height = height.saturating_add(rows_height + 3);
    if self.is_searchable { height += 1; }
    
    // 堆叠侧边内容高度（如适用）
    if self.side_layout_width(inner_width).is_none() {
        height += self.stacked_side_content().desired_height(inner_width);
    }
    
    // 底部备注和提示
    if let Some(note) = &self.footer_note { ... }
    if self.footer_hint.is_some() { height += 1; }
    
    height
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 直接依赖文件

| 文件路径 | 用途 |
|----------|------|
| `codex-rs/tui/src/bottom_pane/bottom_pane_view.rs` | `BottomPaneView` trait 定义 |
| `codex-rs/tui/src/bottom_pane/scroll_state.rs` | `ScrollState` 滚动状态管理 |
| `codex-rs/tui/src/bottom_pane/selection_popup_common.rs` | 通用渲染函数和 `GenericDisplayRow` |
| `codex-rs/tui/src/bottom_pane/popup_consts.rs` | 弹窗常量（如 `MAX_POPUP_ROWS`） |
| `codex-rs/tui/src/render/renderable.rs` | `Renderable` trait 定义 |
| `codex-rs/tui/src/app_event_sender.rs` | `AppEventSender` 事件发送器 |

### 4.2 调用方文件

| 文件路径 | 使用场景 |
|----------|----------|
| `codex-rs/tui/src/theme_picker.rs` | 主题选择器（带实时预览） |
| `codex-rs/tui/src/bottom_pane/approval_overlay.rs` | 审批弹窗（命令、权限、补丁） |
| `codex-rs/tui/src/bottom_pane/feedback_view.rs` | 反馈收集弹窗 |
| `codex-rs/tui/src/bottom_pane/mod.rs` | BottomPane 容器（`show_selection_view` 方法） |
| `codex-rs/tui/src/chatwidget.rs` | 主聊天组件（各种选择弹窗） |
| `codex-rs/tui/src/chatwidget/skills.rs` | 技能选择 |
| `codex-rs/tui/src/app.rs` | 应用层（如 connectors 选择） |

### 4.3 关键代码引用

**类型定义和导出**（`bottom_pane/mod.rs` 第 88-92 行）：
```rust
pub(crate) use list_selection_view::ColumnWidthMode;
pub(crate) use list_selection_view::SelectionViewParams;
pub(crate) use list_selection_view::SideContentWidth;
pub(crate) use list_selection_view::popup_content_width;
pub(crate) use list_selection_view::side_by_side_layout_widths;
```

**BottomPane 集成**（`bottom_pane/mod.rs` 第 783-813 行）：
```rust
pub(crate) fn show_selection_view(&mut self, params: list_selection_view::SelectionViewParams) {
    let view = list_selection_view::ListSelectionView::new(params, self.app_event_tx.clone());
    self.push_view(Box::new(view));
}

pub(crate) fn replace_selection_view_if_active(
    &mut self,
    view_id: &'static str,
    params: list_selection_view::SelectionViewParams,
) -> bool {
    // 如果当前活动视图匹配 view_id，则替换它
    ...
}
```

**主题选择器使用示例**（`theme_picker.rs` 第 314-407 行）：
```rust
pub(crate) fn build_theme_picker_params(...) -> SelectionViewParams {
    // 构建 SelectionItem 列表
    let items: Vec<SelectionItem> = entries.iter().map(|entry| {
        SelectionItem {
            name: display_name,
            is_current,
            dismiss_on_select: true,
            search_value: Some(entry.name.clone()),
            actions: vec![Box::new(move |tx| {
                tx.send(AppEvent::SyntaxThemeSelected { ... });
            })],
            ..Default::default()
        }
    }).collect();
    
    SelectionViewParams {
        title: Some("Select Syntax Theme".to_string()),
        side_content: Box::new(ThemePreviewWideRenderable),
        side_content_width: SideContentWidth::Half,
        on_selection_changed: Some(Box::new(|idx, _tx| { ... })),
        on_cancel: Some(Box::new(|_tx| { ... })),
        preserve_side_content_bg: true,
        ...
    }
}
```

---

## 5. 依赖与外部交互

### 5.1 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `crossterm` | 键盘事件处理（`KeyCode`, `KeyEvent`, `KeyModifiers`） |
| `ratatui` | TUI 渲染（`Buffer`, `Rect`, `Layout`, `Paragraph`, `Line`, `Span` 等） |
| `unicode_width` | Unicode 字符串宽度计算（`UnicodeWidthStr`） |
| `itertools` | 迭代器工具（`positions` 方法） |
| `textwrap` | 文本自动换行 |

### 5.2 内部模块依赖

```rust
// 同级模块
use super::selection_popup_common::{...};
use super::bottom_pane_view::BottomPaneView;
use super::popup_consts::MAX_POPUP_ROWS;
use super::scroll_state::ScrollState;
use super::CancellationEvent;

// 其他模块
use crate::app_event_sender::AppEventSender;
use crate::key_hint::KeyBinding;
use crate::render::renderable::{ColumnRenderable, Renderable};
```

### 5.3 外部交互接口

#### 5.3.1 BottomPaneView trait 实现

```rust
impl BottomPaneView for ListSelectionView {
    fn handle_key_event(&mut self, key_event: KeyEvent) { ... }
    fn is_complete(&self) -> bool { self.complete }
    fn view_id(&self) -> Option<&'static str> { self.view_id }
    fn selected_index(&self) -> Option<usize> { self.selected_actual_idx() }
    fn on_ctrl_c(&mut self) -> CancellationEvent { ... }
}
```

#### 5.3.2 Renderable trait 实现

```rust
impl Renderable for ListSelectionView {
    fn desired_height(&self, width: u16) -> u16 { ... }
    fn render(&self, area: Rect, buf: &mut Buffer) { ... }
}
```

#### 5.3.3 回调类型定义

```rust
/// 选择动作回调
pub(crate) type SelectionAction = Box<dyn Fn(&AppEventSender) + Send + Sync>;

/// 选择变更回调（用于实时预览）
pub(crate) type OnSelectionChangedCallback = 
    Option<Box<dyn Fn(usize, &AppEventSender) + Send + Sync>>;

/// 取消回调（用于恢复状态）
pub(crate) type OnCancelCallback = 
    Option<Box<dyn Fn(&AppEventSender) + Send + Sync>>;
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险与边界

#### 6.1.1 性能边界

| 风险点 | 说明 | 缓解措施 |
|--------|------|----------|
| **大列表过滤** | 搜索过滤使用线性扫描，大数据集可能卡顿 | 当前限制 `MAX_POPUP_ROWS = 8`，实际渲染受限 |
| **高度计算** | `desired_height` 需要遍历所有可见行计算换行 | 使用 `AutoVisible` 模式减少计算量 |
| **回调分配** | 每个 `SelectionItem` 的动作是 Box 分配 | 通常项目数量少，影响不大 |

#### 6.1.2 布局边界

```rust
// 最小列表宽度阈值
const MIN_LIST_WIDTH_FOR_SIDE: u16 = 40;

// 最大弹窗行数
const MAX_POPUP_ROWS: usize = 8;

// 水平间距
const SIDE_CONTENT_GAP: u16 = 2;

// 菜单表面水平内边距
const MENU_SURFACE_HORIZONTAL_INSET: u16 = 4;
```

**边界情况处理**：
- 终端宽度 < 40 列：强制使用堆叠布局
- 侧边内容宽度 < `side_content_min_width`：回退到堆叠布局
- 搜索无结果：显示 "no matches" 占位符

#### 6.1.3 状态管理风险

| 风险 | 说明 |
|------|------|
| **索引映射错误** | `filtered_indices` 和 `items` 之间的映射必须保持一致 |
| **选择状态丢失** | 过滤后需要恢复选择状态，否则用户体验差 |
| **并发回调** | 回调使用 `AppEventSender` 发送事件，需确保线程安全 |

### 6.2 测试覆盖

文件包含 29 个单元测试，覆盖：

| 测试类别 | 测试数量 | 说明 |
|----------|----------|------|
| 布局/间距 | 2 | 标题/副标题间距验证（snapshot） |
| 主题选择器集成 | 2 | 副标题回退、背景保留 |
| 底部备注 | 1 | 备注文本换行（snapshot） |
| 搜索功能 | 2 | 搜索栏渲染、无匹配时取消回调 |
| 回调机制 | 2 | 选择变更回调、无变化时不触发 |
| 文本换行 | 1 | 长选项换行对齐 |
| 宽度适配 | 3 | 不同宽度下的行保留、列位置稳定 |
| 列宽模式 | 6 | 三种模式的滚动行为（snapshot） |
| 侧边内容 | 5 | 布局计算、堆叠回退、背景清除 |

### 6.3 改进建议

#### 6.3.1 性能优化

1. **虚拟列表**：当前限制 `MAX_POPUP_ROWS = 8`，如果未来需要支持大列表，可考虑虚拟滚动
2. **增量过滤**：对于大列表，可使用 trie 或索引结构加速搜索
3. **缓存高度计算**：相同宽度下的高度计算可缓存，避免重复计算

#### 6.3.2 功能扩展

1. **多选支持**：当前仅支持单选，可考虑扩展为多选模式
2. **分组/分类**：支持项目分组显示（当前 `category_tag` 仅显示标签）
3. **排序选项**：支持按名称、相关性等排序
4. **键盘快捷键自定义**：当前快捷键硬编码，可考虑配置化

#### 6.3.3 代码质量

1. **状态机重构**：当前 `complete` 布尔值可扩展为更明确的状态机
2. **错误处理**：部分 `unwrap` 可替换为更安全的错误处理
3. **文档完善**：复杂布局算法可增加更多内联注释

#### 6.3.4 可访问性

1. **屏幕阅读器支持**：增加 ARIA 标签（如果终端模拟器支持）
2. **高对比度模式**：当前样式依赖颜色，可增加更多视觉指示器

### 6.4 相关 Issue 模式

基于代码分析，潜在问题模式：

1. **布局抖动**：`AutoVisible` 模式下滚动可能导致列宽变化，已提供 `AutoAllRows` 作为稳定替代
2. **背景色泄漏**：侧边内容可能污染背景，已通过 `preserve_side_content_bg` 和 `clear_to_terminal_bg` 处理
3. **终端兼容性**：C0 控制字符处理（`^P`, `^N`）确保在旧终端正常工作

---

## 7. 总结

`ListSelectionView` 是 Codex TUI 中一个**高度通用、功能丰富**的列表选择组件。它通过精心设计的配置参数（`SelectionViewParams`）支持从简单的确认弹窗到复杂的主题选择器等各种场景。

**核心设计亮点**：
1. **响应式布局**：自动适应终端宽度，支持并排/堆叠两种模式
2. **实时反馈**：选择变更回调支持实时预览（如主题切换）
3. **完整的键盘导航**：支持多种快捷键，符合 TUI 用户习惯
4. **灵活的渲染系统**：通过 `Renderable` trait 支持自定义头部和侧边内容
5. **健壮的状态管理**：过滤、选择、滚动状态保持一致

**维护注意事项**：
- 修改过滤逻辑时需确保 `filtered_indices` 和 `state.selected_idx` 同步
- 新增键盘快捷键需考虑与搜索模式的冲突
- 修改布局常量需测试极端终端尺寸
