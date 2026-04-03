# Model Picker Filters Hidden Models Snapshot Research

## 场景与职责

该 snapshot 测试验证模型选择器（Model Picker）的过滤功能，确保只有标记为可见（`show_in_picker = true`）的模型才会显示在快速选择列表中，而隐藏的模型（如旧版或已弃用的模型）被正确过滤掉。

**测试场景**：
- 用户通过 `/model` 命令或快捷键打开模型选择弹出框
- 系统展示可用的自动模式模型列表
- 验证模型列表过滤逻辑正确工作

## 功能点目的

1. **模型可见性控制**：允许系统维护一个完整的模型目录，同时只向用户展示推荐的模型
2. **用户体验优化**：避免用户被过多不推荐的模型选项淹没
3. **向后兼容性**：隐藏旧版模型但保留通过命令行直接访问的能力

## 具体技术实现

### 测试代码路径
**文件**：`codex-rs/tui_app_server/src/chatwidget/tests.rs` (约第 8400-8444 行)

```rust
#[tokio::test]
async fn model_picker_filters_hidden_models() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;

    let preset = |slug: &str, show_in_picker: bool| ModelPreset {
        id: slug.to_string(),
        model: slug.to_string(),
        display_name: slug.to_string(),
        description: format!("{slug} description"),
        default_reasoning_effort: ReasoningEffortConfig::Medium,
        supported_reasoning_efforts: vec![ReasoningEffortPreset {
            effort: ReasoningEffortConfig::Medium,
            description: "medium".to_string(),
        }],
        supports_personality: false,
        is_default: false,
        upgrade: None,
        show_in_picker,  // 关键字段：控制模型是否显示
        availability_nux: None,
        supported_in_api: true,
        input_modalities: default_input_modalities(),
    };

    chat.open_model_popup_with_presets(vec![
        preset("test-visible-model", true),   // 可见模型
        preset("test-hidden-model", false),   // 隐藏模型
    ]);
    let popup = render_bottom_popup(&chat, 80);
    assert_snapshot!("model_picker_filters_hidden_models", popup);
    assert!(popup.contains("test-visible-model"));
    assert!(!popup.contains("test-hidden-model"));  // 验证隐藏模型被过滤
}
```

### 核心实现代码
**文件**：`codex-rs/tui_app_server/src/chatwidget.rs` (约第 7610-7614 行)

```rust
pub(crate) fn open_model_popup_with_presets(&mut self, presets: Vec<ModelPreset>) {
    let presets: Vec<ModelPreset> = presets
        .into_iter()
        .filter(|preset| preset.show_in_picker)  // 过滤逻辑
        .collect();
    // ... 后续处理
}
```

### Snapshot 内容
```
  Select Model and Effort
  Access legacy models by running codex -m <model_name> or in your config.toml

› 1. test-visible-model (current)  test-visible-model description

  Press enter to select reasoning effort, or esc to dismiss.
```

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs:7610-7693` | `open_model_popup_with_presets()` - 模型弹出框主逻辑 |
| `codex-rs/tui_app_server/src/chatwidget.rs:7708-7751` | `open_all_models_popup()` - 完整模型列表弹出框 |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs:8400-8444` | 测试用例实现 |
| `codex-rs/core/src/model_catalog.rs` | `ModelPreset` 结构体定义 |

### ModelPreset 关键字段
```rust
pub struct ModelPreset {
    pub id: String,
    pub model: String,
    pub show_in_picker: bool,  // 控制是否在快速选择器中显示
    pub description: String,
    pub default_reasoning_effort: ReasoningEffortConfig,
    pub supported_reasoning_efforts: Vec<ReasoningEffortPreset>,
    // ...
}
```

## 依赖与外部交互

### 依赖模块
1. **Model Catalog**：提供模型元数据，包括 `show_in_picker` 标志
2. **SelectionView**：底部弹出框的通用选择界面组件
3. **AppEvent 系统**：处理模型选择后的配置更新事件

### 事件流
```
用户打开模型选择器
    ↓
过滤 presets (show_in_picker = true)
    ↓
渲染 SelectionView
    ↓
用户选择模型
    ↓
触发 AppEvent::OpenReasoningPopup 或 AppEvent::UpdateModel
```

## 风险、边界与改进建议

### 潜在风险
1. **过滤过度**：如果所有模型都被标记为隐藏，用户将无法通过 UI 选择任何模型
2. **命令行与 UI 不一致**：用户可以通过 `codex -m <hidden_model>` 使用隐藏模型，但 UI 中不可见，可能导致困惑

### 边界情况
1. **空列表处理**：当过滤后没有可见模型时，系统应优雅降级到完整模型列表
2. **当前模型被隐藏**：如果用户当前使用的是已隐藏的模型，UI 应正确显示当前状态

### 改进建议
1. **添加调试信息**：在开发模式下显示被隐藏的模型数量，帮助开发者调试
2. **搜索功能**：当隐藏模型较多时，提供搜索功能让用户能找到特定模型
3. **分类显示**：将模型分组为"推荐"、"旧版"、"实验性"等类别，而非简单隐藏
4. **配置覆盖**：允许用户配置始终显示某些隐藏模型

### 相关测试
- `model_selection_popup`：测试正常模型选择界面
- `model_reasoning_selection_popup`：测试推理级别选择
- `server_overloaded_error_does_not_switch_models`：测试错误处理时的模型保持
