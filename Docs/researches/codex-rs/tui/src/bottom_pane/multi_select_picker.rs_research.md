# Multi-Select Picker 研究文档

## 文件信息
- **文件路径**: `codex-rs/tui/src/bottom_pane/multi_select_picker.rs`
- **代码行数**: 795 行
- **所属模块**: `codex-tui` crate 的底部面板子模块

---

## 一、场景与职责

### 1.1 核心定位

`MultiSelectPicker` 是一个**多选列表组件**，用于在 TUI 中提供可模糊搜索、可多选、可排序的项目选择界面。它是 `BottomPaneView` trait 的实现者之一，可以被压入底部面板的视图栈中显示。

### 1.2 典型使用场景

1. **技能选择**: 启用/禁用多个技能
2. **功能开关**: 批量启用/禁用实验性功能
3. **配置选项**: 多选配置项管理
4. **优先级排序**: 通过左右箭头调整项目顺序

### 1.3 架构位置

```
BottomPane
    └── view_stack: Vec<Box<dyn BottomPaneView>>
            └── MultiSelectPicker (本组件)
                    ├── ScrollState (滚动状态)
                    ├── ColumnRenderable (标题渲染)
                    └── 回调函数 (on_change, on_confirm, on_cancel)
```

---

## 二、功能点目的

### 2.1 主要功能

| 功能 | 描述 | 触发方式 |
|-----|------|---------|
| **模糊搜索** | 实时过滤列表项目 | 输入字符 |
| **多选切换** | 启用/禁用项目 | Space 键 |
| **导航** | 上下移动选择 | ↑/↓ 或 Ctrl+P/N 或 Ctrl+K/J |
| **排序** | 调整项目顺序 | ←/→ 键（需启用） |
| **确认** | 提交选择结果 | Enter 键 |
| **取消** | 关闭不保存 | Esc 键 |
| **实时预览** | 显示当前选择摘要 | 可选回调 |

### 2.2 关键数据结构

#### `MultiSelectItem` - 列表项

```rust
#[derive(Default)]
pub(crate) struct MultiSelectItem {
    pub id: String,                    // 唯一标识符（回调返回）
    pub name: String,                  // 显示名称（可能被截断）
    pub description: Option<String>,   // 可选描述（灰色显示）
    pub enabled: bool,                 // 是否启用/选中
}
```

#### `MultiSelectPicker` - 选择器主体

```rust
pub(crate) struct MultiSelectPicker {
    items: Vec<MultiSelectItem>,              // 所有项目
    state: ScrollState,                       // 滚动和选择状态
    complete: bool,                           // 是否已完成（关闭）
    app_event_tx: AppEventSender,             // 事件发送器
    header: Box<dyn Renderable>,              // 标题组件
    footer_hint: Line<'static>,               // 底部提示
    search_query: String,                     // 搜索查询
    filtered_indices: Vec<usize>,             // 过滤后的索引
    ordering_enabled: bool,                   // 是否启用排序
    preview_builder: Option<PreviewCallback>, // 预览生成回调
    preview_line: Option<Line<'static>>,      // 缓存的预览行
    on_change: Option<ChangeCallBack>,        // 变更回调
    on_confirm: Option<ConfirmCallback>,      // 确认回调
    on_cancel: Option<CancelCallback>,        // 取消回调
}
```

#### `MultiSelectPickerBuilder` - 构建器

```rust
pub(crate) struct MultiSelectPickerBuilder {
    title: String,
    subtitle: Option<String>,
    instructions: Vec<Span<'static>>,  // 自定义底部提示
    items: Vec<MultiSelectItem>,
    ordering_enabled: bool,
    app_event_tx: AppEventSender,
    preview_builder: Option<PreviewCallback>,
    on_change: Option<ChangeCallBack>,
    on_confirm: Option<ConfirmCallback>,
    on_cancel: Option<CancelCallback>,
}
```

### 2.3 回调类型定义

```rust
/// 变更回调：项目状态改变时调用（切换或排序）
pub type ChangeCallBack = Box<dyn Fn(&[MultiSelectItem], &AppEventSender) + Send + Sync>;

/// 确认回调：用户按下 Enter 时调用，返回所有启用项目的 ID
pub type ConfirmCallback = Box<dyn Fn(&[String], &AppEventSender) + Send + Sync>;

/// 取消回调：用户按下 Esc 时调用
pub type CancelCallback = Box<dyn Fn(&AppEventSender) + Send + Sync>;

/// 预览回调：生成预览行
pub type PreviewCallback = Box<dyn Fn(&[MultiSelectItem]) -> Option<Line<'static>> + Send + Sync>;
```

---

## 三、具体技术实现

### 3.1 模糊搜索实现

```rust
fn apply_filter(&mut self) {
    let previously_selected = self.state.selected_idx
        .and_then(|visible_idx| self.filtered_indices.get(visible_idx).copied());

    let filter = self.search_query.trim();
    if filter.is_empty() {
        // 空查询：显示所有项目
        self.filtered_indices = (0..self.items.len()).collect();
    } else {
        // 使用 codex_utils_fuzzy_match 进行模糊匹配
        let mut matches: Vec<(usize, i32)> = Vec::new();
        for (idx, item) in self.items.iter().enumerate() {
            if let Some((_indices, score)) = match_item(filter, &item.name, &item.name) {
                matches.push((idx, score));
            }
        }
        // 按分数排序，分数相同按名称排序
        matches.sort_by(|a, b| a.1.cmp(&b.1).then_with(|| ...));
        self.filtered_indices = matches.into_iter().map(|(idx, _)| idx).collect();
    }
    
    // 恢复选择位置
    self.state.selected_idx = previously_selected
        .and_then(|actual_idx| self.filtered_indices.iter().position(|idx| *idx == actual_idx))
        .or_else(|| (len > 0).then_some(0));
}
```

### 3.2 键盘事件处理

```rust
impl BottomPaneView for MultiSelectPicker {
    fn handle_key_event(&mut self, key_event: KeyEvent) {
        match key_event {
            // 排序键（需启用 ordering_enabled）
            KeyEvent { code: KeyCode::Left, .. } if self.ordering_enabled => {
                self.move_selected_item(Direction::Up);
            }
            KeyEvent { code: KeyCode::Right, .. } if self.ordering_enabled => {
                self.move_selected_item(Direction::Down);
            }
            // 导航键：多种绑定方式
            KeyEvent { code: KeyCode::Up, .. }
            | KeyEvent { code: KeyCode::Char('p'), modifiers: KeyModifiers::CONTROL, .. }
            | KeyEvent { code: KeyCode::Char('k'), modifiers: KeyModifiers::CONTROL, .. }
            | KeyEvent { code: KeyCode::Char('\u{0010}'), .. } /* ^P */ => self.move_up(),
            
            KeyEvent { code: KeyCode::Down, .. }
            | KeyEvent { code: KeyCode::Char('j'), modifiers: KeyModifiers::CONTROL, .. }
            | KeyEvent { code: KeyCode::Char('n'), modifiers: KeyModifiers::CONTROL, .. }
            | KeyEvent { code: KeyCode::Char('\u{000e}'), .. } /* ^N */ => self.move_down(),
            
            // 搜索编辑
            KeyEvent { code: KeyCode::Backspace, .. } => {
                self.search_query.pop();
                self.apply_filter();
            }
            // 切换选择
            KeyEvent { code: KeyCode::Char(' '), modifiers: KeyModifiers::NONE, .. } => {
                self.toggle_selected();
            }
            // 确认
            KeyEvent { code: KeyCode::Enter, .. } => self.confirm_selection(),
            // 取消
            KeyEvent { code: KeyCode::Esc, .. } => self.close(),
            // 输入字符添加到搜索
            KeyEvent { code: KeyCode::Char(c), modifiers, .. } 
                if !modifiers.contains(KeyModifiers::CONTROL) 
                && !modifiers.contains(KeyModifiers::ALT) => {
                self.search_query.push(c);
                self.apply_filter();
            }
            _ => {}
        }
    }
}
```

### 3.3 项目排序实现

```rust
fn move_selected_item(&mut self, direction: Direction) {
    // 搜索状态下禁用排序
    if !self.search_query.is_empty() {
        return;
    }

    let Some(visible_idx) = self.state.selected_idx else { return };
    let Some(actual_idx) = self.filtered_indices.get(visible_idx).copied() else { return };

    let len = self.items.len();
    let new_idx = match direction {
        Direction::Up if actual_idx > 0 => actual_idx - 1,
        Direction::Down if actual_idx + 1 < len => actual_idx + 1,
        _ => return,
    };

    // 交换项目位置
    self.items.swap(actual_idx, new_idx);
    
    // 更新预览和触发回调
    self.update_preview_line();
    if let Some(on_change) = &self.on_change {
        on_change(&self.items, &self.app_event_tx);
    }

    // 重建过滤索引并恢复选择
    self.apply_filter();
    if let Some(new_visible_idx) = self.filtered_indices.iter().position(|idx| *idx == new_idx) {
        self.state.selected_idx = Some(new_visible_idx);
    }
}
```

### 3.4 渲染实现

```rust
impl Renderable for MultiSelectPicker {
    fn desired_height(&self, width: u16) -> u16 {
        let rows = self.build_rows();
        let rows_height = self.rows_height(&rows);
        let preview_height = if self.preview_line.is_some() { 1 } else { 0 };

        let mut height = self.header.desired_height(width.saturating_sub(4));
        height = height.saturating_add(rows_height + 3); // 搜索区域
        height = height.saturating_add(2);               // 边框
        height.saturating_add(1 + preview_height)        // 页脚 + 预览
    }

    fn render(&self, area: Rect, buf: &mut Buffer) {
        // 布局：内容区 + 页脚
        let [content_area, footer_area] = Layout::vertical([...]).areas(area);
        
        // 渲染菜单背景
        Block::default().style(user_message_style()).render(content_area, buf);
        
        // 内部分区：标题 + 搜索 + 列表
        let [header_area, _, search_area, list_area] = Layout::vertical([...])
            .areas(content_area.inset(Insets::vh(1, 2)));
        
        // 渲染标题
        self.header.render(header_area, buf);
        
        // 渲染搜索提示（模仿作曲家样式）
        // "> " 前缀 + 查询文本
        
        // 渲染列表行
        render_rows_single_line(list_area, buf, &rows, &self.state, ...);
        
        // 渲染预览（如果有）和页脚提示
    }
}
```

### 3.5 行构建

```rust
fn build_rows(&self) -> Vec<GenericDisplayRow> {
    self.filtered_indices
        .iter()
        .enumerate()
        .filter_map(|(visible_idx, actual_idx)| {
            self.items.get(*actual_idx).map(|item| {
                let is_selected = self.state.selected_idx == Some(visible_idx);
                let prefix = if is_selected { '›' } else { ' ' };  // 光标指示器
                let marker = if item.enabled { 'x' } else { ' ' }; // 复选框
                let item_name = truncate_text(&item.name, ITEM_NAME_TRUNCATE_LEN);
                let name = format!("{prefix} [{marker}] {item_name}");
                GenericDisplayRow {
                    name,
                    description: item.description.clone(),
                    ..Default::default()
                }
            })
        })
        .collect()
}
```

---

## 四、关键代码路径与文件引用

### 4.1 核心依赖

| 文件路径 | 用途 |
|---------|------|
| `bottom_pane_view.rs` | `BottomPaneView` trait 实现 |
| `scroll_state.rs` | `ScrollState` 滚动状态管理 |
| `selection_popup_common.rs` | `GenericDisplayRow`, `render_rows_single_line` |
| `popup_consts.rs` | `MAX_POPUP_ROWS` 常量 |
| `render/renderable.rs` | `Renderable`, `ColumnRenderable` trait |

### 4.2 外部依赖

| Crate/模块 | 用途 |
|-----------|------|
| `codex_utils_fuzzy_match` | `fuzzy_match` 模糊匹配算法 |
| `ratatui` | TUI 渲染（Buffer, Rect, Layout, Widget, Line, Span） |
| `crossterm` | 键盘事件（KeyCode, KeyEvent, KeyModifiers） |

### 4.3 关键方法调用链

#### 构建和显示
```
MultiSelectPicker::builder(title, subtitle, app_event_tx)
    .items(items)
    .enable_ordering()          // 可选
    .on_preview(callback)       // 可选
    .on_confirm(callback)       // 可选
    .on_cancel(callback)        // 可选
    .build()
        └── MultiSelectPickerBuilder::build()
                ├── ColumnRenderable::new()  // 创建标题
                ├── apply_filter()           // 初始化过滤
                └── update_preview_line()    // 初始化预览
```

#### 用户交互
```
handle_key_event(key)
    ├── 导航键 → move_up/move_down → ScrollState 操作
    ├── Space → toggle_selected() → on_change 回调
    ├── Enter → confirm_selection() → on_confirm 回调
    ├── Esc → close() → on_cancel 回调
    └── 字符 → search_query.push() → apply_filter()
```

---

## 五、依赖与外部交互

### 5.1 实现的 Trait

```rust
impl BottomPaneView for MultiSelectPicker {
    fn is_complete(&self) -> bool { self.complete }
    fn on_ctrl_c(&mut self) -> CancellationEvent { self.close(); Handled }
    fn handle_key_event(&mut self, key_event: KeyEvent) { ... }
}

impl Renderable for MultiSelectPicker {
    fn desired_height(&self, width: u16) -> u16 { ... }
    fn render(&self, area: Rect, buf: &mut Buffer) { ... }
}
```

### 5.2 使用的外部类型

```rust
// 来自 codex_utils_fuzzy_match
use codex_utils_fuzzy_match::fuzzy_match;

// 来自 crossterm
use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};

// 来自 ratatui
use ratatui::buffer::Buffer;
use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::style::Stylize;
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Widget};

// 来自本模块
use crate::bottom_pane::scroll_state::ScrollState;
use crate::bottom_pane::selection_popup_common::{GenericDisplayRow, render_rows_single_line};
use crate::bottom_pane::popup_consts::MAX_POPUP_ROWS;
use crate::bottom_pane::bottom_pane_view::BottomPaneView;
use crate::bottom_pane::CancellationEvent;
```

---

## 六、风险、边界与改进建议

### 6.1 已知风险

1. **搜索状态下的排序禁用**
   - 当用户正在搜索时，左右箭头不会触发排序
   - 这可能导致用户困惑，因为没有视觉反馈说明排序被禁用
   - 建议：在搜索状态下显示提示或禁用左右箭头提示

2. **项目名称截断**
   - `ITEM_NAME_TRUNCATE_LEN = 21` 可能对于某些语言（如中文）过短
   - 截断使用 `truncate_text`，可能在多字节字符处截断

3. **回调 panic 风险**
   - 回调函数是 `Box<dyn Fn(...)>`，如果回调 panic 可能导致 TUI 崩溃
   - 建议：在调用回调前添加 `catch_unwind` 保护

### 6.2 边界情况

1. **空列表处理**
   - `apply_filter()` 正确处理空列表，设置 `selected_idx` 为 `None`
   - 渲染时显示 "no matches" 占位符

2. **所有项目被过滤掉**
   - 当搜索无匹配时，`filtered_indices` 为空
   - `selected_idx` 被设置为 `None`，渲染显示空状态

3. **快速输入处理**
   - 每次字符输入都触发 `apply_filter()`，对于大列表可能有性能问题
   - 当前没有防抖机制

4. **排序后选择恢复**
   - 排序后通过 `filtered_indices.iter().position()` 恢复选择位置
   - 如果过滤状态改变，可能无法找到原项目

### 6.3 改进建议

1. **性能优化**
   ```rust
   // 当前：每次按键都重建过滤列表
   // 建议：添加防抖或增量更新
   fn apply_filter_debounced(&mut self) {
       // 使用定时器延迟过滤，快速输入时只执行最后一次
   }
   ```

2. **可访问性增强**
   - 添加音频反馈选项（选中/取消时的提示音）
   - 支持高对比度模式
   - 添加选中项目的计数显示

3. **UX 改进**
   - 显示 "X/Y 已选择" 的计数器
   - 支持全选/取消全选快捷键（如 Ctrl+A）
   - 搜索框显示匹配数量

4. **代码改进**
   - `match_item` 函数是公有的，但只在模块内使用，可以改为私有
   - 一些魔法数字（如 `21` 截断长度）可以改为常量或配置
   - 考虑添加 `#[must_use]` 到 builder 方法

5. **测试覆盖**
   - 当前没有单元测试，建议添加：
     - 模糊搜索测试
     - 排序功能测试
     - 回调触发测试
     - 边界情况测试（空列表、全过滤等）

### 6.4 设计决策记录

1. **搜索时禁用排序**
   - 决策：当 `search_query` 非空时，左右箭头不触发排序
   - 理由：在过滤状态下排序会导致用户困惑，因为可见顺序和实际顺序不一致
   - 替代方案：可以允许排序，但需要在视觉上明确区分过滤和排序状态

2. **使用 `GenericDisplayRow` 共享渲染**
   - 决策：复用 `selection_popup_common` 的渲染逻辑
   - 好处：保持所有选择弹窗的视觉一致性
   - 权衡：牺牲了一些自定义渲染的灵活性

3. **Builder 模式**
   - 决策：使用 `MultiSelectPickerBuilder` 构建实例
   - 好处：清晰的配置 API，可选参数易于处理
   - 注意：所有回调都是 `Option`，需要在调用时检查

4. **模糊匹配算法**
   - 使用 `codex_utils_fuzzy_match::fuzzy_match`，支持字符级别的模糊匹配
   - 匹配结果包含分数用于排序，以及索引用于高亮（虽然当前未使用高亮）
