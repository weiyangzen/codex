# List Selection View - Model Picker Width 80 研究报告

## 1. 场景与职责

### UI场景
该快照展示了 **List Selection View** 组件在 **模型选择器** 场景下的渲染效果，终端宽度为 80 列。这是用户切换 AI 模型（如 gpt-5.1-codex、gpt-5.1-codex-mini 等）时显示的列表选择界面。

### 组件职责
- **模型列表展示**: 展示可用的 AI 模型选项
- **模型信息展示**: 显示每个模型的描述和特性
- **当前模型标记**: 标记当前正在使用的模型
- **键盘导航**: 支持键盘上下导航和选择

## 2. 功能点目的

### 核心功能
1. **模型切换**: 允许用户在不同 AI 模型间切换
2. **模型信息**: 展示每个模型的优化目标和特点
3. **当前状态**: 标记当前使用的模型（current）
4. **描述展示**: 提供模型的详细描述信息

### 用户体验目标
- 帮助用户选择最适合当前任务的模型
- 提供清晰的模型能力对比
- 保持界面在标准终端宽度（80列）下的可读性

## 3. 具体技术实现

### 关键数据结构

```rust
/// 选择项
#[derive(Default)]
pub(crate) struct SelectionItem {
    pub name: String,                    // 显示名称
    pub name_prefix_spans: Vec<Span<'static>>,
    pub display_shortcut: Option<KeyBinding>,
    pub description: Option<String>,     // 描述
    pub selected_description: Option<String>, // 选中时的描述
    pub is_current: bool,                // 是否是当前选中项
    pub is_default: bool,                // 是否是默认项
    pub is_disabled: bool,
    pub actions: Vec<SelectionAction>,
    pub dismiss_on_select: bool,
    pub search_value: Option<String>,
    pub disabled_reason: Option<String>,
}

/// 选择视图参数
pub(crate) struct SelectionViewParams {
    pub view_id: Option<&'static str>,
    pub title: Option<String>,           // 标题
    pub subtitle: Option<String>,        // 副标题
    pub footer_note: Option<Line<'static>>,
    pub footer_hint: Option<Line<'static>>,
    pub items: Vec<SelectionItem>,       // 选项列表
    pub is_searchable: bool,
    pub search_placeholder: Option<String>,
    pub col_width_mode: ColumnWidthMode, // 列宽模式
    pub header: Box<dyn Renderable>,
    pub initial_selected_idx: Option<usize>,
    pub side_content: Box<dyn Renderable>,
    pub side_content_width: SideContentWidth,
    pub side_content_min_width: u16,
    pub stacked_side_content: Option<Box<dyn Renderable>>,
    pub preserve_side_content_bg: bool,
    pub on_selection_changed: OnSelectionChangedCallback,
    pub on_cancel: OnCancelCallback,
}

/// 列表选择视图
pub(crate) struct ListSelectionView {
    view_id: Option<&'static str>,
    footer_note: Option<Line<'static>>,
    footer_hint: Option<Line<'static>>,
    items: Vec<SelectionItem>,
    state: ScrollState,                  // 滚动状态
    complete: bool,
    app_event_tx: AppEventSender,
    is_searchable: bool,
    search_query: String,
    search_placeholder: Option<String>,
    col_width_mode: ColumnWidthMode,
    filtered_indices: Vec<usize>,        // 过滤后的索引
    last_selected_actual_idx: Option<usize>,
    header: Box<dyn Renderable>,
    initial_selected_idx: Option<usize>,
    // ...
}

/// 列宽模式
pub(crate) enum ColumnWidthMode {
    AutoVisible,   // 仅测量可见行（默认）
    AutoAllRows,   // 测量所有行
    Fixed,         // 固定 30/70 分割
}
```

### 行构建

```rust
impl ListSelectionView {
    fn build_rows(&self) -> Vec<GenericDisplayRow> {
        self.filtered_indices
            .iter()
            .enumerate()
            .filter_map(|(visible_idx, actual_idx)| {
                self.items.get(*actual_idx).map(|item| {
                    let is_selected = self.state.selected_idx == Some(visible_idx);
                    let prefix = if is_selected { '›' } else { ' ' };
                    let name = item.name.as_str();
                    
                    // 标记当前/默认模型
                    let marker = if item.is_current {
                        " (current)"
                    } else if item.is_default {
                        " (default)"
                    } else {
                        ""
                    };
                    
                    let name_with_marker = format!("{name}{marker}");
                    let n = visible_idx + 1;
                    
                    // 前缀：选中标记 + 序号
                    let wrap_prefix = if self.is_searchable {
                        format!("{prefix} ")
                    } else {
                        format!("{prefix} {n}. ")
                    };
                    
                    let wrap_prefix_width = UnicodeWidthStr::width(wrap_prefix.as_str());
                    let mut name_prefix_spans = Vec::new();
                    name_prefix_spans.push(wrap_prefix.into());
                    name_prefix_spans.extend(item.name_prefix_spans.clone());
                    
                    // 描述：优先使用选中描述，否则使用默认描述
                    let description = is_selected
                        .then(|| item.selected_description.clone())
                        .flatten()
                        .or_else(|| item.description.clone());
                    
                    GenericDisplayRow {
                        name: name_with_marker,
                        name_prefix_spans,
                        display_shortcut: item.display_shortcut,
                        match_indices: None,
                        description,
                        category_tag: None,
                        wrap_indent: description.is_none().then_some(wrap_prefix_width),
                        is_disabled: item.is_disabled || item.disabled_reason.is_some(),
                        disabled_reason: item.disabled_reason.clone(),
                    }
                })
            })
            .collect()
    }
}
```

### 模型选择器参数构建示例

```rust
fn model_picker_params(current_model: &str) -> SelectionViewParams {
    let items = vec![
        SelectionItem {
            name: "gpt-5.1-codex".to_string(),
            description: Some("Optimized for Codex. Balance of reasoning quality and coding ability.".to_string()),
            is_current: current_model == "gpt-5.1-codex",
            ..Default::default()
        },
        SelectionItem {
            name: "gpt-5.1-codex-mini".to_string(),
            description: Some("Optimized for Codex. Cheaper, faster, but less capable.".to_string()),
            is_current: current_model == "gpt-5.1-codex-mini",
            ..Default::default()
        },
        SelectionItem {
            name: "gpt-4.1-codex".to_string(),
            description: Some("Legacy model. Use when you need compatibility with older automations.".to_string()),
            is_current: current_model == "gpt-4.1-codex",
            ..Default::default()
        },
    ];
    
    SelectionViewParams {
        title: Some("Select Model and Effort".to_string()),
        items,
        col_width_mode: ColumnWidthMode::AutoVisible,
        ..Default::default()
    }
}
```

### 渲染输出（80列宽度）

```
                                                                                
  Select Model and Effort                                                       
                                                                                
› 1. gpt-5.1-codex (current)  Optimized for Codex. Balance of reasoning         
                              quality and coding ability.                       
  2. gpt-5.1-codex-mini       Optimized for Codex. Cheaper, faster, but less   
                              capable.                                          
  3. gpt-4.1-codex            Legacy model. Use when you need compatibility     
                              with older automations.
```

## 4. 关键代码路径与文件引用

### 主要源文件
| 文件路径 | 职责 |
|---------|------|
| `/home/sansha/Github/codex/codex-rs/tui/src/bottom_pane/list_selection_view.rs` | ListSelectionView 完整实现 |

### 关键代码路径

1. **行构建**:
   ```
   list_selection_view.rs:357-406 -> build_rows()
   ```

2. **渲染实现**:
   ```
   list_selection_view.rs:759-982 -> impl Renderable for ListSelectionView
   ```

3. **高度计算**:
   ```
   list_selection_view.rs:693-758 -> desired_height()
   ```

4. **键盘导航**:
   ```
   list_selection_view.rs:575-691 -> impl BottomPaneView for ListSelectionView::handle_key_event()
   ```

## 5. 依赖与外部交互

### 内部依赖

| 依赖模块 | 用途 |
|---------|------|
| `crate::bottom_pane::selection_popup_common::GenericDisplayRow` | 通用显示行 |
| `crate::bottom_pane::scroll_state::ScrollState` | 滚动状态 |
| `unicode_width::UnicodeWidthStr` | Unicode 字符串宽度计算 |
| `ratatui::layout::Constraint` | 布局约束 |

### 外部交互

1. **模型切换事件**:
   ```rust
   SelectionAction -> AppEvent::SetModel { model_id }
   ```

2. **选择变更回调**:
   ```rust
   on_selection_changed: Option<Box<dyn Fn(usize, &AppEventSender) + Send + Sync>>
   ```

## 6. 风险、边界与改进建议

### 潜在风险

1. **描述截断**:
   - 风险: 80列宽度下长描述可能被截断
   - 缓解: 使用换行和缩进保持可读性

2. **模型名称冲突**:
   - 风险: 模型名称可能重复
   - 缓解: 使用唯一标识符区分

3. **列表过长**:
   - 风险: 模型过多时列表超出屏幕
   - 缓解: 使用滚动和分页

### 边界情况

1. **无当前模型**:
   - `is_current` 全为 false 时的处理

2. **所有模型禁用**:
   - 所有项 `is_disabled = true` 时的处理

3. **搜索过滤**:
   - `is_searchable = true` 时的过滤行为

### 改进建议

1. **模型分组**:
   - 建议: 按提供商或能力分组模型

2. **性能指标**:
   - 建议: 显示每个模型的速度和成本指标

3. **推荐标记**:
   - 建议: 标记推荐用于当前任务的模型

4. **最近使用**:
   - 建议: 显示最近使用的模型

5. **搜索过滤**:
   - 建议: 支持按名称或描述搜索模型
