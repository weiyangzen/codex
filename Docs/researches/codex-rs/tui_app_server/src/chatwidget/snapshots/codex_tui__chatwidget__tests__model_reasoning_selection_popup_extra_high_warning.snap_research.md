# Model Reasoning Selection Popup Extra High Warning Snapshot Research

## 场景与职责

该 snapshot 测试验证当用户选择 "Extra high" 推理级别时的警告提示功能。由于 Extra high 级别会显著增加 token 消耗并可能快速耗尽 Plus 计划的速率限制，系统需要在用户选择时显示明确的警告信息。

**测试场景**：
- 用户选择 `gpt-5.1-codex-max` 模型
- 当前推理级别设置为 `XHigh`（Extra high）
- 系统在选择界面中显示费率限制警告

## 功能点目的

1. **成本意识提醒**：提醒用户 Extra high 级别的高消耗特性
2. **速率限制保护**：防止用户意外耗尽 Plus 计划配额
3. **知情选择**：确保用户在了解潜在成本的情况下做出选择

## 具体技术实现

### 测试代码路径
**文件**：`codex-rs/tui_app_server/src/chatwidget/tests.rs` (约第 8641-8653 行)

```rust
#[tokio::test]
async fn model_reasoning_selection_popup_extra_high_warning_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(Some("gpt-5.1-codex-max")).await;

    set_chatgpt_auth(&mut chat);
    chat.set_reasoning_effort(Some(ReasoningEffortConfig::XHigh));  // 设置为 Extra high

    let preset = get_available_model(&chat, "gpt-5.1-codex-max");
    chat.open_reasoning_popup(preset);

    let popup = render_bottom_popup(&chat, 80);
    assert_snapshot!("model_reasoning_selection_popup_extra_high_warning", popup);
}
```

### 核心实现代码
**文件**：`codex-rs/tui_app_server/src/chatwidget.rs` (约第 7934-8050 行)

```rust
pub(crate) fn open_reasoning_popup(&mut self, preset: ModelPreset) {
    // 确定需要警告的推理级别
    let warn_effort = if supported.iter().any(|o| o.effort == ReasoningEffortConfig::XHigh) {
        Some(ReasoningEffortConfig::XHigh)
    } else if supported.iter().any(|o| o.effort == ReasoningEffortConfig::High) {
        Some(ReasoningEffortConfig::High)
    } else {
        None
    };

    // 生成警告文本
    let warning_text = warn_effort.map(|effort| {
        let effort_label = Self::reasoning_effort_label(effort);
        format!("⚠ {effort_label} reasoning effort can quickly consume Plus plan rate limits.")
    });

    // 对特定模型启用警告
    let warn_for_model = preset.model.starts_with("gpt-5.1-codex")
        || preset.model.starts_with("gpt-5.1-codex-max")
        || preset.model.starts_with("gpt-5.2");

    // 为每个选项构建 SelectionItem
    for choice in choices.iter() {
        let effort = choice.display;
        let show_warning = warn_for_model && warn_effort == Some(effort);
        
        // 当选项被选中时显示警告
        let selected_description = if show_warning {
            warning_text.as_ref().map(|warning_message| {
                description.as_ref().map_or_else(
                    || warning_message.clone(),
                    |d| format!("{d}\n{warning_message}"),
                )
            })
        } else {
            None
        };
        
        items.push(SelectionItem {
            // ...
            selected_description,  // 选中时显示的描述（包含警告）
            // ...
        });
    }
}
```

### Snapshot 内容
```
  Select Reasoning Level for gpt-5.1-codex-max

  1. Low                   Fast responses with lighter reasoning
  2. Medium (default)      Balances speed and reasoning depth for everyday
                           tasks
  3. High                  Greater reasoning depth for complex problems
› 4. Extra high (current)  Extra high reasoning depth for complex problems
                           ⚠ Extra high reasoning effort can quickly consume
                           Plus plan rate limits.

  Press enter to confirm or esc to go back
```

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs:7934-7946` | 警告级别检测逻辑 |
| `codex-rs/tui_app_server/src/chatwidget.rs:7947-7950` | 警告文本生成 |
| `codex-rs/tui_app_server/src/chatwidget.rs:7951-7953` | 模型特定警告启用条件 |
| `codex-rs/tui_app_server/src/chatwidget.rs:8037-8047` | `selected_description` 警告绑定 |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs:8641-8653` | 测试用例实现 |

### 警告触发条件
```rust
let show_warning = warn_for_model && warn_effort == Some(effort);
```

条件分解：
1. `warn_for_model`：模型属于需要警告的系列（gpt-5.1-codex, gpt-5.1-codex-max, gpt-5.2）
2. `warn_effort == Some(effort)`：当前选项是需要警告的级别（XHigh 或 High）

## 依赖与外部交互

### 依赖模块
1. **ModelPreset**：提供模型标识和推理级别支持信息
2. **SelectionItem.selected_description**：选中时显示的额外描述字段
3. **ReasoningEffortConfig**：推理级别枚举定义

### 警告显示机制
```
用户高亮选择 Extra high 选项
    ↓
SelectionView 检测到 selected_description 存在
    ↓
在选项描述下方渲染警告文本
    ↓
警告文本包含 ⚠ 符号和费率限制提示
```

### 与 SelectionView 的集成
- `selected_description` 是 `SelectionItem` 的可选字段
- 仅在选项被高亮/选中时显示
- 支持多行文本（通过 `\n` 分隔）

## 风险、边界与改进建议

### 潜在风险
1. **警告疲劳**：频繁显示警告可能导致用户忽视
2. **模型覆盖不全**：新模型可能未包含在 `warn_for_model` 检查中
3. **费率变化**：OpenAI 费率调整可能使警告信息过时

### 边界情况
1. **非 Plus 用户**：免费层用户不应看到 Plus 相关的警告
2. **企业用户**：企业计划可能有不同的速率限制
3. **宽屏显示**：警告文本在窄屏下可能换行不美观

### 改进建议
1. **动态警告**：根据用户实际使用情况和剩余配额显示个性化警告
2. **使用统计**：显示 Extra high 相对于其他级别的平均消耗倍数
3. **确认对话框**：首次选择 Extra high 时显示确认对话框
4. **配置选项**：允许高级用户禁用此类警告
5. **模型自动检测**：基于模型的实际能力而非硬编码前缀匹配
6. **多语言支持**：警告信息应支持本地化

### 相关测试
- `model_reasoning_selection_popup`：基础推理级别选择测试
- `reasoning_popup_shows_extra_high_with_space`：宽屏布局测试

### 代码维护注意
当添加新模型支持时，需要更新 `warn_for_model` 的判断逻辑：
```rust
let warn_for_model = preset.model.starts_with("gpt-5.1-codex")
    || preset.model.starts_with("gpt-5.1-codex-max")
    || preset.model.starts_with("gpt-5.2")
    || preset.model.starts_with("new-model-prefix");  // 新增
```
