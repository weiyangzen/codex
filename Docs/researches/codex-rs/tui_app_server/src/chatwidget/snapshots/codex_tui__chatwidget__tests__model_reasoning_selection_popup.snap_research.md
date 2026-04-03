# Model Reasoning Selection Popup Snapshot Research

## 场景与职责

该 snapshot 测试验证模型推理级别（Reasoning Level）选择弹出框的渲染效果。当用户选择特定模型后，系统展示该模型支持的推理级别选项（Low/Medium/High/Extra high），允许用户根据任务复杂度调整 AI 的推理深度。

**测试场景**：
- 用户从模型选择器中选择了一个支持多推理级别的模型（如 `gpt-5.1-codex-max`）
- 系统展示推理级别选择弹出框
- 当前选中的推理级别（High）被高亮显示

## 功能点目的

1. **推理能力分级**：让用户根据任务复杂度选择适当的推理深度
2. **成本与质量权衡**：高级别推理提供更好的结果但消耗更多资源
3. **模型能力展示**：清晰展示每个模型支持的推理选项及其描述

## 具体技术实现

### 测试代码路径
**文件**：`codex-rs/tui_app_server/src/chatwidget/tests.rs` (约第 8627-8639 行)

```rust
#[tokio::test]
async fn model_reasoning_selection_popup_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(Some("gpt-5.1-codex-max")).await;

    set_chatgpt_auth(&mut chat);
    chat.set_reasoning_effort(Some(ReasoningEffortConfig::High));  // 设置当前为 High

    let preset = get_available_model(&chat, "gpt-5.1-codex-max");
    chat.open_reasoning_popup(preset);  // 打开推理级别选择

    let popup = render_bottom_popup(&chat, 80);
    assert_snapshot!("model_reasoning_selection_popup", popup);
}
```

### 核心实现代码
**文件**：`codex-rs/tui_app_server/src/chatwidget.rs` (约第 7928-8077 行)

```rust
pub(crate) fn open_reasoning_popup(&mut self, preset: ModelPreset) {
    let default_effort: ReasoningEffortConfig = preset.default_reasoning_effort;
    let supported = preset.supported_reasoning_efforts;
    let in_plan_mode = self.collaboration_modes_enabled() 
        && self.active_mode_kind() == ModeKind::Plan;

    // 构建推理选项列表
    let mut choices: Vec<EffortChoice> = Vec::new();
    for effort in ReasoningEffortConfig::iter() {
        if supported.iter().any(|option| option.effort == effort) {
            choices.push(EffortChoice {
                stored: Some(effort),
                display: effort,
            });
        }
    }

    // 确定当前高亮选项
    let highlight_choice = if is_current_model {
        if in_plan_mode {
            self.config.plan_mode_reasoning_effort
                .or(self.effective_reasoning_effort())
        } else {
            self.effective_reasoning_effort()
        }
    } else {
        default_choice
    };

    // 构建 SelectionItem 列表
    let mut items: Vec<SelectionItem> = Vec::new();
    for choice in choices.iter() {
        let effort = choice.display;
        let mut effort_label = Self::reasoning_effort_label(effort).to_string();
        if choice.stored == default_choice {
            effort_label.push_str(" (default)");
        }
        
        let description = choice.stored.and_then(|effort| {
            supported.iter()
                .find(|option| option.effort == effort)
                .map(|option| option.description.to_string())
        });
        // ... 构建 SelectionItem
    }
}
```

### Snapshot 内容
```
  Select Reasoning Level for gpt-5.1-codex-max

  1. Low               Fast responses with lighter reasoning
  2. Medium (default)  Balances speed and reasoning depth for everyday tasks
› 3. High (current)    Greater reasoning depth for complex problems
  4. Extra high        Extra high reasoning depth for complex problems

  Press enter to confirm or esc to go back
```

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs:7928-8077` | `open_reasoning_popup()` - 推理级别选择主逻辑 |
| `codex-rs/tui_app_server/src/chatwidget.rs:7990-8015` | 默认选项和当前选项高亮逻辑 |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs:8627-8639` | 测试用例实现 |
| `codex-rs/core/src/config.rs` | `ReasoningEffortConfig` 枚举定义 |

### ReasoningEffortConfig 枚举
```rust
pub enum ReasoningEffortConfig {
    Low,      // 快速响应，轻量推理
    Medium,   // 平衡速度和质量（默认）
    High,     // 深度推理，适合复杂问题
    XHigh,    // 极高推理深度（Extra high）
}
```

## 依赖与外部交互

### 依赖模块
1. **ModelPreset**：包含模型支持的推理级别列表 (`supported_reasoning_efforts`)
2. **SelectionView**：通用选择界面组件
3. **Plan Mode 集成**：在 Plan 模式下使用独立的推理级别配置

### 事件流
```
用户选择模型
    ↓
检查模型支持的推理级别数量
    ↓
如果只有一个选项 → 直接应用
如果多个选项 → 显示推理级别选择弹出框
    ↓
用户选择推理级别
    ↓
触发 AppEvent::UpdateReasoningEffort
    ↓
触发 AppEvent::PersistModelSelection（持久化选择）
```

### 与 Plan Mode 的交互
- 当处于 Plan 模式时，使用 `plan_mode_reasoning_effort` 配置
- 允许 Plan 模式和执行模式使用不同的推理级别

## 风险、边界与改进建议

### 潜在风险
1. **费率限制**：Extra high 级别可能快速消耗 Plus 计划配额（见 `extra_high_warning` snapshot）
2. **选项过多**：某些模型可能支持大量推理级别，导致界面拥挤
3. **配置混淆**：Plan 模式和普通模式的推理级别配置独立，用户可能混淆

### 边界情况
1. **单选项模型**：当模型只支持一个推理级别时，跳过选择直接应用
2. **不支持推理的模型**：某些旧版模型可能不支持推理级别调整
3. **当前模型切换**：切换模型时保持或重置推理级别的逻辑

### 改进建议
1. **智能推荐**：根据任务类型（代码生成、重构、解释）推荐合适的推理级别
2. **使用统计**：显示各推理级别的使用频率和平均 token 消耗
3. **快捷切换**：在状态栏添加快捷切换推理级别的按钮
4. **模型特定提示**：针对不同模型显示特定的推理级别建议
5. **批量设置**：允许为所有模型设置默认推理级别偏好

### 相关测试
- `model_reasoning_selection_popup_extra_high_warning`：测试 Extra high 警告
- `reasoning_popup_shows_extra_high_with_space`：测试宽屏布局
- `single_reasoning_option_skips_selection`：测试单选项自动跳过
