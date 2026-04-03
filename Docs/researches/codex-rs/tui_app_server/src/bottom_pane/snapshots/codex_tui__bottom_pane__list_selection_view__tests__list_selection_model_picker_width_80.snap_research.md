# List Selection View Model Picker Width 80 Snapshot 研究文档

## 场景与职责

该快照文件是 `codex_tui_app_server` crate 中 `list_selection_view.rs` 模块的测试快照，用于验证**模型选择器在 80 列宽度下的渲染**。当用户执行 `/model` 命令时，显示此界面选择 AI 模型。

### 业务场景
- 用户想要切换使用的 AI 模型
- 用户执行 `/model` 命令
- 系统显示可用模型列表及其描述

### 模型选择器特性
- 显示模型名称和描述
- 标记当前使用的模型
- 支持搜索过滤
- 显示模型特性（如推理能力、成本）

## 功能点目的

### 核心功能
1. **模型展示**：列出所有可用模型
2. **当前标识**：标记当前使用的模型
3. **描述说明**：显示每个模型的特性和适用场景
4. **快速选择**：支持数字键快速选择

### 用户体验目标
- **信息丰富**：帮助用户选择最适合的模型
- **决策支持**：描述帮助用户理解模型差异
- **快速操作**：支持键盘快速选择

## 具体技术实现

### 关键数据结构
```rust
pub(crate) struct SelectionItem {
    pub name: String,
    pub description: Option<String>,
    pub is_current: bool,  // 是否为当前模型
    pub is_default: bool,  // 是否为默认模型
    // ...
}

pub(crate) struct ListSelectionView {
    items: Vec<SelectionItem>,
    state: ScrollState,
    col_width_mode: ColumnWidthMode,  // 列宽模式
    // ...
}

pub(crate) enum ColumnWidthMode {
    AutoVisible,   // 根据可见行自动调整
    AutoAllRows,   // 根据所有行自动调整
    Fixed,         // 固定 30/70 分割
}
```

### 模型选择器构建
```rust
fn build_model_picker() -> ListSelectionView {
    let items = vec![
        SelectionItem {
            name: "gpt-5.1-codex".to_string(),
            description: Some("Optimized for Codex. Balance of reasoning quality and coding ability.".to_string()),
            is_current: true,
            is_default: false,
            // ...
        },
        SelectionItem {
            name: "gpt-5.1-codex-mini".to_string(),
            description: Some("Optimized for Codex. Cheaper, faster, but less capable.".to_string()),
            is_current: false,
            is_default: false,
            // ...
        },
        SelectionItem {
            name: "gpt-4.1-codex".to_string(),
            description: Some("Legacy model. Use when you need compatibility with older automations.".to_string()),
            is_current: false,
            is_default: false,
            // ...
        },
    ];
    
    ListSelectionView::new(
        SelectionViewParams {
            title: Some("Select Model and Effort".to_string()),
            items,
            col_width_mode: ColumnWidthMode::AutoVisible,
            // ...
        },
        app_event_tx,
    )
}
```

### 行构建
```rust
fn build_rows(&self) -> Vec<GenericDisplayRow> {
    self.filtered_indices
        .iter()
        .enumerate()
        .filter_map(|(visible_idx, actual_idx)| {
            self.items.get(*actual_idx).map(|item| {
                let is_selected = self.state.selected_idx == Some(visible_idx);
                let prefix = if is_selected { '›' } else { ' ' };
                let marker = if item.is_current {
                    " (current)"
                } else if item.is_default {
                    " (default)"
                } else {
                    ""
                };
                
                GenericDisplayRow {
                    name: format!("{}{}. {}{}", prefix, visible_idx + 1, item.name, marker),
                    description: item.description.clone(),
                    // ...
                }
            })
        })
        .collect()
}
```

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/list_selection_view.rs`
- **测试函数**: `list_selection_model_picker_width_80` (在 tests 模块中)
- **行构建**: `build_rows` 方法

### 渲染输出分析
```
                                                                                
  Select Model and Effort                                                        
                                                                                
› 1. gpt-5.1-codex (current)  Optimized for Codex. Balance of reasoning         
                              quality and coding ability.                        
  2. gpt-5.1-codex-mini       Optimized for Codex. Cheaper, faster, but less    
                              capable.                                           
  3. gpt-4.1-codex            Legacy model. Use when you need compatibility     
                              with older automations.
```

- 标题居中显示
- 当前模型标记为 `(current)`
- 描述换行对齐到名称列之后
- 选中项使用 `›` 指示

## 依赖与外部交互

### 内部依赖
- `ListSelectionView` - 列表选择视图
- `SelectionItem` - 选择项定义
- `ColumnWidthMode` - 列宽模式
- `GenericDisplayRow` - 通用显示行

### 外部交互
- **模型注册表**：获取可用模型列表
- **配置系统**：获取当前模型设置
- **模型 API**：切换模型时通知后端

## 风险、边界与改进建议

### 潜在风险
1. **模型列表变化**：后端模型列表变化时前端可能不同步
2. **描述长度**：过长的描述可能导致界面混乱
3. **选择延迟**：模型切换可能需要时间，需要反馈

### 边界情况
1. **无可用模型**：模型列表为空时的处理
2. **当前模型不可用**：当前模型不在列表中时的处理
3. **网络中断**：获取模型列表失败时的处理

### 改进建议
1. **模型图标**：为不同模型添加图标
2. **性能指标**：显示模型的延迟、成本等实时指标
3. **推荐系统**：根据任务类型推荐合适的模型
4. **模型对比**：允许并排比较多个模型
5. **快捷键**：添加数字键快速选择

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/list_selection_view.rs`
- 选择项通用: `codex-rs/tui_app_server/src/bottom_pane/selection_popup_common.rs`
