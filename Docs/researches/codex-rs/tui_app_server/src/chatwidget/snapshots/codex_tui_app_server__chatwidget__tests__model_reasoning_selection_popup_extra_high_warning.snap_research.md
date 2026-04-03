# 模型推理选择 Extra High 警告测试研究文档

## 场景与职责

该 snapshot 测试验证当用户选择 "Extra High" 推理级别时，tui_app_server 的 ChatWidget 能够正确显示警告信息。测试场景包括：

1. 用户当前使用 gpt-5.1-codex-max 模型
2. 用户已设置推理级别为 Extra High (XHigh)
3. 打开推理级别选择弹出框时，应显示关于 Plus 计划速率限制消耗的警告

**职责**：确保用户在选择高资源消耗的推理级别时得到适当的警告提示，避免意外消耗大量 API 配额。

## 功能点目的

- **推理级别选择**：允许用户为不同的模型选择不同的推理深度（Low、Medium、High、Extra High）
- **资源警告**：当选择 Extra High 时，提醒用户该选项可能快速消耗 Plus 计划的速率限制
- **用户体验**：在确认选择前提供充分的信息，帮助用户做出明智的决定

## 具体技术实现

### 测试代码位置
`codex-rs/tui_app_server/src/chatwidget/tests.rs` 第 8642-8653 行

```rust
#[tokio::test]
async fn model_reasoning_selection_popup_extra_high_warning_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(Some("gpt-5.1-codex-max")).await;

    set_chatgpt_auth(&mut chat);
    chat.set_reasoning_effort(Some(ReasoningEffortConfig::XHigh));

    let preset = get_available_model(&chat, "gpt-5.1-codex-max");
    chat.open_reasoning_popup(preset);

    let popup = render_bottom_popup(&chat, 80);
    assert_snapshot!("model_reasoning_selection_popup_extra_high_warning", popup);
}
```

### 关键实现细节

1. **模型预设获取**：通过 `get_available_model` 获取指定模型的配置预设
2. **推理级别设置**：使用 `set_reasoning_effort` 设置当前推理级别为 XHigh
3. **弹出框渲染**：调用 `open_reasoning_popup` 打开推理级别选择界面
4. **Snapshot 捕获**：使用 `render_bottom_popup` 渲染底部弹出框并捕获输出

### Snapshot 输出内容

```
Select Reasoning Level for gpt-5.1-codex-max

1. Low                   Fast responses with lighter reasoning
2. Medium (default)      Balances speed and reasoning depth for everyday tasks
3. High                  Greater reasoning depth for complex problems
› 4. Extra high (current)  Extra high reasoning depth for complex problems
                           ⚠ Extra high reasoning effort can quickly consume Plus plan rate limits.

Press enter to confirm or esc to go back
```

## 关键代码路径与文件引用

### 主要代码文件

1. **测试文件**：`codex-rs/tui_app_server/src/chatwidget/tests.rs`
   - 测试函数：`model_reasoning_selection_popup_extra_high_warning_snapshot`
   - 辅助函数：`make_chatwidget_manual`, `set_chatgpt_auth`, `get_available_model`, `render_bottom_popup`

2. **ChatWidget 实现**：`codex-rs/tui_app_server/src/chatwidget/mod.rs`（假设位置）
   - 方法：`open_reasoning_popup`, `set_reasoning_effort`

3. **底部面板**：`codex-rs/tui_app_server/src/bottom_pane/mod.rs`
   - 负责渲染选择弹出框 UI

4. **模型目录**：`codex-rs/tui_app_server/src/model_catalog.rs`
   - 提供可用模型列表和推理级别配置

### 相关协议类型

- `ReasoningEffortConfig`：定义推理级别枚举（Low、Medium、High、XHigh）
- `ModelPreset`：包含模型支持的推理级别列表

## 依赖与外部交互

### 内部依赖

| 组件 | 用途 |
|------|------|
| `ChatWidget` | 主聊天组件，管理推理级别选择状态 |
| `BottomPane` | 渲染底部弹出框 UI |
| `ModelCatalog` | 提供模型配置和推理级别信息 |
| `AppEventSender` | 发送应用事件（如更新推理级别） |

### 外部依赖

- `ratatui`：终端 UI 渲染库
- `insta`：snapshot 测试框架
- `tokio`：异步运行时

### 配置依赖

- 需要 `ChatGPT` 认证（`set_chatgpt_auth`）才能访问某些模型功能
- 模型配置中的 `supported_reasoning_efforts` 定义了可用的推理级别

## 风险、边界与改进建议

### 潜在风险

1. **警告信息过时**：如果 Plus 计划的速率限制策略改变，警告信息可能需要更新
2. **平台差异**：不同平台或模型可能对 Extra High 的定义不同，警告的适用性可能有差异
3. **用户体验**：频繁显示警告可能导致用户疲劳，需要考虑警告频率控制

### 边界情况

1. **单推理级别模型**：某些模型可能只支持单一推理级别，此时应跳过选择（见 `single_reasoning_option_skips_selection` 测试）
2. **Plan 模式特殊处理**：在 Plan 模式下选择推理级别可能触发额外的范围确认提示
3. **模型切换**：切换模型时，如果新模型不支持当前推理级别，需要降级处理

### 改进建议

1. **动态警告**：根据用户实际的速率限制使用情况动态调整警告的严重程度
2. **个性化设置**：允许用户在配置中禁用特定警告（不推荐但某些高级用户可能需要）
3. **更详细的说明**：在警告中提供链接或快捷键查看更详细的资源消耗说明
4. **批量操作警告**：如果用户连续多次使用 Extra High，可以显示累计消耗提示

### 相关测试

- `model_reasoning_selection_popup_snapshot`：标准推理选择界面测试
- `reasoning_popup_shows_extra_high_with_space`：验证 "Extra high" 显示格式
- `single_reasoning_option_skips_selection`：单选项跳过测试
- `reasoning_selection_in_plan_mode_opens_scope_prompt_event`：Plan 模式特殊处理测试
