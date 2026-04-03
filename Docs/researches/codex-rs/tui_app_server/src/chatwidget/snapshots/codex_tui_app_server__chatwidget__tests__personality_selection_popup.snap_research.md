# 个性选择弹出框测试研究文档

## 场景与职责

该 snapshot 测试验证 tui_app_server 的 ChatWidget 能够正确显示个性选择弹出框，允许用户选择 AI 助手的沟通风格。

**测试场景**：
1. 用户当前使用 gpt-5.2-codex 模型
2. 用户已建立线程（thread_id 已设置）
3. 用户打开个性选择弹出框
4. 系统显示可用的个性选项，当前选中 "Pragmatic"

**职责**：确保用户可以选择与 AI 助手的沟通风格，提供个性化的交互体验。

## 功能点目的

- **个性化体验**：允许用户选择适合自己工作风格的 AI 沟通方式
- **风格多样性**：提供不同的沟通风格选项（如友好、务实等）
- **即时反馈**：显示当前选中的个性风格
- **简单切换**：提供直观的界面在不同风格间切换

## 具体技术实现

### 测试代码位置
`codex-rs/tui_app_server/src/chatwidget/tests.rs` 第 8342-8349 行

```rust
#[tokio::test]
async fn personality_selection_popup_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(Some("gpt-5.2-codex")).await;
    chat.thread_id = Some(ThreadId::new());
    chat.open_personality_popup();

    let popup = render_bottom_popup(&chat, 80);
    assert_snapshot!("personality_selection_popup", popup);
}
```

### 关键实现细节

1. **初始化 ChatWidget**：
   - 使用 `make_chatwidget_manual` 创建测试实例
   - 指定当前模型为 gpt-5.2-codex（支持个性功能的模型）

2. **设置线程 ID**：
   - 模拟已建立会话的状态
   - 某些个性功能可能需要活跃会话

3. **打开个性弹出框**：
   - 调用 `open_personality_popup()` 触发个性选择界面
   - 从当前配置中读取可用的个性选项

4. **渲染捕获**：
   - 使用 `render_bottom_popup` 在 80 列宽度下渲染弹出框内容
   - 捕获并验证 UI 输出

### Snapshot 输出内容

```
Select Personality
Choose a communication style for Codex.

  1. Friendly             Warm, collaborative, and helpful.
› 2. Pragmatic (current)  Concise, task-focused, and direct.

Press enter to confirm or esc to go back
```

## 关键代码路径与文件引用

### 主要代码文件

1. **测试文件**：`codex-rs/tui_app_server/src/chatwidget/tests.rs`
   - 测试函数：`personality_selection_popup_snapshot` (第 8342 行)

2. **ChatWidget 实现**：`codex-rs/tui_app_server/src/chatwidget/mod.rs`
   - 方法：`open_personality_popup`
   - 个性配置管理

3. **底部面板**：`codex-rs/tui_app_server/src/bottom_pane/mod.rs`
   - 负责渲染个性选择列表 UI

4. **协议类型**：`codex-protocol/src/config_types.rs`
   - `Personality`：个性类型定义

### 相关协议类型

- `Personality`：个性枚举，可能包含：
  - `Friendly`：友好型，温暖、协作、乐于助人
  - `Pragmatic`：务实型，简洁、任务导向、直接
  - 其他可能的个性选项

## 依赖与外部交互

### 内部依赖

| 组件 | 用途 |
|------|------|
| `ChatWidget` | 主聊天组件，管理个性选择状态 |
| `BottomPane` | 渲染底部弹出框 UI |
| `Personality` | 个性类型定义和描述 |
| `ThreadId` | 会话标识 |

### 外部依赖

- `ratatui`：终端 UI 渲染库
- `insta`：snapshot 测试框架
- `tokio`：异步运行时

### 模型支持

不是所有模型都支持个性功能。测试中使用 gpt-5.2-codex，这是一个支持个性配置的模型。模型预设中的 `supports_personality` 字段指示模型是否支持个性功能。

## 风险、边界与改进建议

### 潜在风险

1. **模型兼容性**：不是所有模型都支持个性功能，需要正确处理不支持的模型
2. **个性定义模糊**：用户可能不理解不同个性风格的具体差异
3. **期望落差**：个性设置可能不会显著改变 AI 的响应风格，导致用户失望

### 边界情况

1. **不支持个性的模型**：对于不支持个性的模型，不应显示个性选择选项
2. **会话中切换**：在活跃会话中切换个性可能需要重新初始化或特定处理
3. **个性与推理级别交互**：个性设置可能与推理级别设置相互影响

### 改进建议

1. **预览功能**：提供个性预览功能，展示每种风格的示例响应
2. **自定义个性**：允许用户定义自己的个性配置
3. **上下文感知个性**：根据任务类型自动调整个性（如编码时使用务实型，头脑风暴时使用友好型）
4. **个性影响说明**：清晰说明个性设置如何影响 AI 的响应
5. **快速切换**：提供快捷键快速切换常用个性

### 相关测试

- `model_selection_popup_snapshot`：模型选择测试（某些模型支持个性）
- `submit_user_message_with_mode_sets_coding_collaboration_mode`：协作模式与个性交互测试

### 用户体验考虑

1. **默认个性选择**：新用户的默认个性应该是什么？
2. **个性持久化**：个性设置是否应该跨会话持久化？
3. **团队一致性**：在团队环境中，是否应该统一个性设置？
4. **反馈机制**：用户应该能够评价个性设置的效果
