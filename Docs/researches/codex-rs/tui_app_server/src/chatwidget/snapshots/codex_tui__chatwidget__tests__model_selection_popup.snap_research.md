# Model Selection Popup Snapshot Research

## 场景与职责

该 snapshot 测试验证完整模型选择弹出框的渲染效果。当用户通过 `/model` 命令打开模型选择器时，系统展示所有可用的模型列表，包括默认模型、其他可用模型以及访问完整模型列表的入口。

**测试场景**：
- 用户执行 `/model` 命令
- 系统展示模型选择弹出框
- 显示多个可用模型及其描述
- 当前选中的模型被高亮标记

## 功能点目的

1. **模型发现**：让用户了解所有可用的 AI 模型选项
2. **能力对比**：通过描述帮助用户理解不同模型的特点
3. **快速切换**：提供便捷的模型切换入口
4. **默认推荐**：突出显示推荐的默认模型

## 具体技术实现

### 测试代码路径
**文件**：`codex-rs/tui_app_server/src/chatwidget/tests.rs` (约第 8332-8339 行)

```rust
#[tokio::test]
async fn model_selection_popup_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(Some("gpt-5-codex")).await;
    chat.thread_id = Some(ThreadId::new());
    chat.open_model_popup();  // 打开模型选择弹出框

    let popup = render_bottom_popup(&chat, 80);
    assert_snapshot!("model_selection_popup", popup);
}
```

### 核心实现代码
**文件**：`codex-rs/tui_app_server/src/chatwidget.rs` (约第 7320-7693 行)

```rust
pub(crate) fn open_model_popup(&mut self) {
    if !self.is_session_configured() {
        self.add_info_message(
            "Model selection is disabled until startup completes.".to_string(),
            /*hint*/ None,
        );
        return;
    }

    let presets: Vec<ModelPreset> = match self.model_catalog.try_list_models() {
        Ok(models) => models,
        Err(_) => {
            self.add_info_message(
                "Models are being updated; please try /model again in a moment.".to_string(),
                /*hint*/ None,
            );
            return;
        }
    };
    self.open_model_popup_with_presets(presets);
}

pub(crate) fn open_model_popup_with_presets(&mut self, presets: Vec<ModelPreset>) {
    // 过滤只显示 show_in_picker = true 的模型
    let presets: Vec<ModelPreset> = presets
        .into_iter()
        .filter(|preset| preset.show_in_picker)
        .collect();

    let current_model = self.current_model();
    
    // 分离自动模式模型和其他模型
    let (mut auto_presets, other_presets): (Vec<ModelPreset>, Vec<ModelPreset>) = presets
        .into_iter()
        .partition(|preset| Self::is_auto_model(&preset.model));

    auto_presets.sort_by_key(|preset| Self::auto_model_order(&preset.model));
    
    // 构建选择项列表
    let mut items: Vec<SelectionItem> = auto_presets
        .into_iter()
        .map(|preset| {
            let description =
                (!preset.description.is_empty()).then_some(preset.description.clone());
            let model = preset.model.clone();
            let actions = Self::model_selection_actions(
                model.clone(),
                Some(preset.default_reasoning_effort),
                should_prompt_plan_mode_scope,
            );
            SelectionItem {
                name: model.clone(),
                description,
                is_current: model.as_str() == current_model,
                is_default: preset.is_default,
                actions,
                dismiss_on_select: true,
                ..Default::default()
            }
        })
        .collect();

    // 添加 "All models" 入口（如果有其他模型）
    if !other_presets.is_empty() {
        items.push(SelectionItem {
            name: "All models".to_string(),
            description: Some(format!(
                "Choose a specific model and reasoning level (current: {current_label})"
            )),
            // ...
        });
    }

    self.bottom_pane.show_selection_view(SelectionViewParams {
        footer_hint: Some(standard_popup_hint_line()),
        items,
        header,
        ..Default::default()
    });
}
```

### Snapshot 内容
```
  Select Model and Effort
  Access legacy models by running codex -m <model_name> or in your config.toml

› 1. gpt-5.3-codex (default)  Latest frontier agentic coding model.
  2. gpt-5.4                  Latest frontier agentic coding model.
  3. gpt-5.2-codex            Frontier agentic coding model.
  4. gpt-5.1-codex-max        Codex-optimized flagship for deep and fast
                              reasoning.
  5. gpt-5.2                  Latest frontier model with improvements across
                              knowledge, reasoning and coding
  6. gpt-5.1-codex-mini       Optimized for codex. Cheaper, faster, but less
                              capable.

  Press enter to select reasoning effort, or esc to dismiss.
```

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs:7320-7342` | `open_model_popup()` - 模型选择入口 |
| `codex-rs/tui_app_server/src/chatwidget.rs:7610-7693` | `open_model_popup_with_presets()` - 主逻辑 |
| `codex-rs/tui_app_server/src/chatwidget.rs:7695-7706` | `is_auto_model()` 和 `auto_model_order()` - 模型分类和排序 |
| `codex-rs/tui_app_server/src/chatwidget.rs:7708-7751` | `open_all_models_popup()` - 完整模型列表 |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs:8332-8339` | 测试用例实现 |

### 自动模型排序
```rust
fn auto_model_order(model: &str) -> usize {
    match model {
        "codex-auto-fast" => 0,      // 最快
        "codex-auto-balanced" => 1,  // 平衡
        "codex-auto-thorough" => 2,  // 最全面
        _ => 3,
    }
}
```

## 依赖与外部交互

### 依赖模块
1. **ModelCatalog**：提供可用模型列表
2. **ModelPreset**：包含模型元数据（名称、描述、是否默认等）
3. **SelectionView**：通用选择界面组件
4. **ThreadId**：验证会话状态

### 事件流
```
用户执行 /model 命令
    ↓
检查会话是否已配置
    ↓
从 ModelCatalog 获取模型列表
    ↓
过滤并分类模型（auto / other）
    ↓
构建 SelectionItem 列表
    ↓
渲染 SelectionView
    ↓
用户选择模型
    ↓
触发模型切换流程（可能进入推理级别选择）
```

### 与推理级别选择的集成
- 选择模型后，如果模型支持多个推理级别，进入推理级别选择
- 如果只有一个推理级别，直接应用并关闭弹出框

## 风险、边界与改进建议

### 潜在风险
1. **模型列表过长**：随着模型增多，列表可能变得难以浏览
2. **描述截断**：长描述在窄屏下可能显示不完整
3. **模型可用性变化**：模型可能在运行时变得不可用

### 边界情况
1. **无可用模型**：当模型目录为空时显示友好提示
2. **启动中状态**：会话未完全配置时禁用模型选择
3. **当前模型不在列表中**：正确处理当前使用非标准模型的情况

### 改进建议
1. **搜索功能**：添加实时搜索过滤模型列表
2. **收藏功能**：允许用户收藏常用模型快速访问
3. **最近使用**：显示最近使用的模型列表
4. **性能指标**：显示各模型的典型响应时间和质量评分
5. **分组显示**：按模型系列（gpt-5.x、codex 等）分组
6. **对比模式**：允许用户并排对比多个模型的特性
7. **推荐引擎**：根据用户历史使用模式推荐模型

### 相关测试
- `model_picker_filters_hidden_models`：测试隐藏模型过滤
- `model_reasoning_selection_popup`：测试推理级别选择
- `personality_selection_popup`：测试个性选择（类似 UI 模式）

### UI 设计考虑
1. **视觉层次**：默认模型使用特殊标记（`(default)`）
2. **当前状态**：当前使用的模型使用 `›` 符号高亮
3. **描述对齐**：多行描述保持缩进对齐
4. **底部提示**：统一的操作提示（Enter 选择，Esc 关闭）
