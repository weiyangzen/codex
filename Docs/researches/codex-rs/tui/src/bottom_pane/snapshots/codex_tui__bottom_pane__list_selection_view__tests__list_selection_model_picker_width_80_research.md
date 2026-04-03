# 快照研究文档: list_selection_model_picker_width_80

## 场景与职责

此快照测试验证 `ListSelectionView` 在 **80 列标准终端宽度** 下渲染**模型选择器**的视觉效果。这是 Codex TUI 的核心功能之一，用户通过此界面选择 AI 模型（如 gpt-5.1-codex、gpt-5.1-codex-mini 等）。

测试场景：
- 模拟真实的模型选择器数据（3 个模型选项）
- 在 80 列宽度下渲染
- 验证模型名称、当前状态标记、描述的布局和换行表现

## 功能点目的

**模型选择器** 是 Codex TUI 的关键交互组件，其设计目的：

1. **模型对比**: 清晰展示不同模型的特点和差异
2. **状态指示**: 通过 `(current)` 标记显示当前选中的模型
3. **描述展示**: 提供模型的详细说明，帮助用户做出选择
4. **响应式布局**: 在中等宽度终端（80 列）下保持良好的可读性

## 具体技术实现

### 测试数据构造

```rust
// list_selection_view.rs:1480-1524
#[test]
fn snapshot_model_picker_width_80() {
    let items = vec![
        SelectionItem {
            name: "gpt-5.1-codex".to_string(),
            description: Some(
                "Optimized for Codex. Balance of reasoning quality and coding ability."
                    .to_string(),
            ),
            is_current: true,  // 标记为当前选中
            dismiss_on_select: true,
            ..Default::default()
        },
        SelectionItem {
            name: "gpt-5.1-codex-mini".to_string(),
            description: Some(
                "Optimized for Codex. Cheaper, faster, but less capable.".to_string(),
            ),
            dismiss_on_select: true,
            ..Default::default()
        },
        SelectionItem {
            name: "gpt-4.1-codex".to_string(),
            description: Some(
                "Legacy model. Use when you need compatibility with older automations."
                    .to_string(),
            ),
            dismiss_on_select: true,
            ..Default::default()
        },
    ];
    let view = ListSelectionView::new(
        SelectionViewParams {
            title: Some("Select Model and Effort".to_string()),
            items,
            ..Default::default()  // 使用默认 AutoVisible 模式
        },
        tx,
    );
    assert_snapshot!(
        "list_selection_model_picker_width_80",
        render_lines_with_width(&view, 80)
    );
}
```

### 行构建逻辑

```rust
// list_selection_view.rs:357-406
fn build_rows(&self) -> Vec<GenericDisplayRow> {
    self.filtered_indices
        .iter()
        .enumerate()
        .filter_map(|(visible_idx, actual_idx)| {
            self.items.get(*actual_idx).map(|item| {
                // 构建显示名称，添加状态标记
                let marker = if item.is_current {
                    " (current)"
                } else if item.is_default {
                    " (default)"
                } else {
                    ""
                };
                let name_with_marker = format!("{name}{marker}");
                
                // 构建前缀（选择指示器 + 序号）
                let prefix = if is_selected { '›' } else { ' ' };
                let n = visible_idx + 1;
                let wrap_prefix = format!("{prefix} {n}. ");
                
                GenericDisplayRow {
                    name: name_with_marker,
                    description: item.description.clone(),
                    // ...
                }
            })
        })
        .collect()
}
```

### 描述换行处理

```rust
// selection_popup_common.rs:270-283
fn wrap_standard_row(row: &GenericDisplayRow, desc_col: usize, width: u16) -> Vec<Line<'static>> {
    let full_line = build_full_line(row, desc_col);
    let continuation_indent = wrap_indent(row, desc_col, width);
    let options = RtOptions::new(width.max(1) as usize)
        .initial_indent(Line::from(""))
        .subsequent_indent(Line::from(" ".repeat(continuation_indent)));
    word_wrap_line(&full_line, options)
}
```

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/bottom_pane/list_selection_view.rs` | 模型选择器测试用例（第 1480-1524 行） |
| `codex-rs/tui/src/bottom_pane/selection_popup_common.rs` | 行渲染和换行逻辑 |

### 关键函数路径

1. **测试入口**: `list_selection_view.rs:1480`
   ```rust
   #[test]
   fn snapshot_model_picker_width_80()
   ```

2. **行构建**: `list_selection_view.rs:357-406`
   ```rust
   fn build_rows(&self) -> Vec<GenericDisplayRow>
   ```

3. **渲染**: `selection_popup_common.rs:591-608`
   ```rust
   pub(crate) fn render_rows(...)
   ```

4. **换行**: `selection_popup_common.rs:270-283`
   ```rust
   fn wrap_standard_row(...)
   ```

### 相关实际代码

```rust
// codex-rs/tui/src/model_picker.rs
pub fn build_model_picker_params(...) -> SelectionViewParams {
    // 实际模型选择器的参数构建
}
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `selection_popup_common::render_rows` | 实际渲染行内容 |
| `selection_popup_common::build_full_line` | 构建完整显示行 |
| `wrapping::word_wrap_line` | 描述文本换行 |

### 外部 Crate

| Crate | 用途 |
|-------|------|
| `ratatui` | 终端 UI 渲染 |
| `insta` | 快照测试 |

### 样式应用

```rust
// 选中项样式（青色加粗）
span.style = Style::default().fg(Color::Cyan).bold();

// 描述样式（暗淡）
full_spans.push(desc.clone().dim());
```

## 风险边界与改进建议

### 当前风险边界

1. **描述截断**: 在 80 列宽度下，长描述需要换行，可能占用较多垂直空间
   - 从快照可见：每个模型描述占用 2 行

2. **名称长度差异**: `gpt-5.1-codex-mini` 比 `gpt-5.1-codex` 长，导致描述列位置不一致
   - 这是 `AutoVisible` 模式的特性，但可能影响视觉对齐

3. **当前状态标记**: `(current)` 标记直接附加在名称后，可能被误认为名称的一部分

4. **模型数量扩展**: 当前测试只有 3 个模型，实际可能更多，需要滚动

### 快照观察

```
  Select Model and Effort                                                        
                                                                                
› 1. gpt-5.1-codex (current)  Optimized for Codex. Balance of reasoning         
                              quality and coding ability.                       
  2. gpt-5.1-codex-mini       Optimized for Codex. Cheaper, faster, but less   
                              capable.                                          
  3. gpt-4.1-codex            Legacy model. Use when you need compatibility    
                              with older automations.
```

**关键观察**:
- 标题 "Select Model and Effort" 居中显示
- 选中项（gpt-5.1-codex）有 `›` 指示器和 `(current)` 标记
- 描述正确换行，且换行后与描述列对齐
- 模型名称长度差异导致描述列起始位置略有不同

### 改进建议

1. **统一描述列位置**: 考虑对模型选择器使用 `AutoAllRows` 或 `Fixed` 模式
   ```rust
   col_width_mode: ColumnWidthMode::AutoAllRows,
   ```

2. **当前状态视觉区分**: 将 `(current)` 标记独立显示，如使用不同颜色或图标
   ```rust
   // 当前
   "gpt-5.1-codex (current)"
   // 建议
   "gpt-5.1-codex ✓"  // 或使用青色高亮
   ```

3. **描述摘要**: 在列表中显示简短描述，完整描述在侧边面板显示

4. **分组显示**: 如果模型数量增多，按类别分组（如 "最新", "旧版", "实验性"）

5. **搜索过滤**: 添加搜索功能，方便在大量模型中快速定位
   ```rust
   is_searchable: true,
   search_placeholder: Some("Search models...".to_string()),
   ```

6. **性能指标**: 在描述中显示关键指标（速度、成本、上下文长度）

### 测试增强建议

1. 添加 120 列宽度的快照，对比宽终端表现
2. 添加 60 列宽度的快照，测试窄终端适应性
3. 添加 10+ 模型的测试，验证滚动行为
4. 添加模型切换的交互测试

### 相关测试

| 测试 | 描述 |
|------|------|
| `width_changes_do_not_hide_rows` | 验证 60-90 列宽度下所有模型可见 |
| `snapshot_narrow_width_preserves_rows` | 验证窄宽度下保留所有行 |
| `theme_picker_subtitle_uses_fallback_text` | 主题选择器的类似测试 |
