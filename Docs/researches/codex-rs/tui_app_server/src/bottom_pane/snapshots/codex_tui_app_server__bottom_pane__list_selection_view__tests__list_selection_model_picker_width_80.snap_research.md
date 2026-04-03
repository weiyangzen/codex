# list_selection_model_picker_width_80 快照研究

## 场景与职责

本快照测试验证了 `ListSelectionView` 在宽度 80 的终端上显示模型选择器的效果。这是实际使用中的常见场景，用户通过此界面选择 AI 模型（如 gpt-5.1-codex、gpt-5.1-codex-mini、gpt-4.1-codex）。

此测试确保模型选择器在中等宽度终端上能够正确显示模型名称和描述信息，提供良好的用户体验。

## 功能点目的

模型选择器界面的核心目标是：

1. **清晰展示选项**：显示模型名称、当前选中标记和详细描述
2. **信息完整性**：在有限宽度内尽可能展示完整的描述信息
3. **视觉区分**：通过缩进和对齐区分不同信息层级

测试验证了在 80 宽度下，三个模型选项及其描述能够正确渲染和换行。

## 具体技术实现

### 测试数据

```rust
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
```

### 渲染效果

在宽度 80 的终端上：

```
  Select Model and Effort

› 1. gpt-5.1-codex (current)  Optimized for Codex. Balance of reasoning
                              quality and coding ability.
  2. gpt-5.1-codex-mini       Optimized for Codex. Cheaper, faster, but less
                              capable.
  3. gpt-4.1-codex            Legacy model. Use when you need compatibility
                              with older automations.
```

### 关键渲染特性

1. **当前选中标记**：`is_current: true` 的项目显示 "(current)" 标记
2. **选择指示器**：`›` 表示当前选中的行
3. **自动换行**：描述文字超出宽度时自动换行，并保持对齐
4. **描述缩进**：换行后的描述与第一行描述列对齐

### 行构建逻辑

在 `list_selection_view.rs` 的 `build_rows` 方法中：

```rust
let marker = if item.is_current {
    " (current)"
} else if item.is_default {
    " (default)"
} else {
    ""
};
let name_with_marker = format!("{name}{marker}");
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui_app_server/src/bottom_pane/list_selection_view.rs` | `ListSelectionView` 组件 |
| `codex-rs/tui_app_server/src/bottom_pane/list_selection_view.rs:357-406` | `build_rows` 方法，构建渲染行数据 |
| `codex-rs/tui_app_server/src/bottom_pane/selection_popup_common.rs` | 行渲染和换行实现 |

### 测试函数

```rust
#[test]
fn snapshot_model_picker_width_80() {
    let (tx_raw, _rx) = unbounded_channel::<AppEvent>();
    let tx = AppEventSender::new(tx_raw);
    let items = vec![
        SelectionItem {
            name: "gpt-5.1-codex".to_string(),
            description: Some(
                "Optimized for Codex. Balance of reasoning quality and coding ability."
                    .to_string(),
            ),
            is_current: true,
            dismiss_on_select: true,
            ..Default::default()
        },
        // ... 其他模型
    ];
    let view = ListSelectionView::new(
        SelectionViewParams {
            title: Some("Select Model and Effort".to_string()),
            items,
            ..Default::default()
        },
        tx,
    );
    assert_snapshot!(
        "list_selection_model_picker_width_80",
        render_lines_with_width(&view, 80)
    );
}
```

## 依赖与外部交互

- **ratatui**: 提供渲染基础类型
- **model_picker 模块**: 实际应用中通过 `build_model_picker_params` 构建模型选择器参数

## 风险、边界与改进建议

### 潜在风险

1. **描述截断**：在更窄的宽度下，描述可能被过度截断
2. **模型名称长度**：未来可能有更长的模型名称，需要确保布局适应

### 边界情况

- 当宽度小于模型名称长度时，描述将被推到下一行
- `is_current` 和 `is_default` 标记同时存在时，两者都会显示

### 改进建议

1. **响应式布局**：在更窄宽度下考虑隐藏部分描述或调整布局
2. **模型分组**：如果模型数量增加，考虑按类别分组显示
3. **搜索功能**：模型数量多时，添加搜索过滤功能
4. **性能信息**：显示模型的响应速度或成本信息

### 相关测试

```rust
#[test]
fn width_changes_do_not_hide_rows() {
    // 验证在 60-90 宽度范围内，所有选项都能正确显示
    for width in 60..=90 {
        let rendered = render_lines_with_width(&view, width);
        assert!(rendered.contains("3."), "third option missing at width {width}");
    }
}
```
