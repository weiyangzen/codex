# Multi Agent Enable Prompt Snapshot Research

## 场景与职责

该 snapshot 测试验证多代理（子代理/Subagents）功能启用提示弹出框的渲染效果。当用户尝试使用多代理功能但该功能在配置中禁用时，系统显示确认对话框，询问用户是否要启用该功能。

**测试场景**：
- 用户尝试访问多代理功能（如 `/agent` 命令）
- 系统检测到 `Collab` 功能未启用
- 显示确认对话框询问是否启用子代理

## 功能点目的

1. **功能发现**：让用户了解子代理功能的存在
2. **显式启用**：确保用户明确同意启用该功能
3. **配置指导**：告知用户需要新会话才能使用
4. **安全考虑**：子代理功能涉及额外的权限和沙箱考虑

## 具体技术实现

### 测试代码路径
**文件**：`codex-rs/tui_app_server/src/chatwidget/tests.rs` (约第 8303-8309 行)

```rust
#[tokio::test]
async fn multi_agent_enable_prompt_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;

    chat.open_multi_agent_enable_prompt();  // 打开启用提示

    let popup = render_bottom_popup(&chat, 80);
    assert_snapshot!("multi_agent_enable_prompt", popup);
}
```

### 核心实现代码
**文件**：`codex-rs/tui_app_server/src/chatwidget.rs` (约第 2247-2277 行)

```rust
pub(crate) fn open_multi_agent_enable_prompt(&mut self) {
    let items = vec![
        SelectionItem {
            name: MULTI_AGENT_ENABLE_YES.to_string(),  // "Yes, enable"
            description: Some(
                "Save the setting now. You will need a new session to use it.".to_string(),
            ),
            actions: vec![Box::new(|tx| {
                // 启用 Collab 功能
                tx.send(AppEvent::UpdateFeatureFlags {
                    updates: vec![(Feature::Collab, true)],
                });
                // 在历史记录中插入警告通知
                tx.send(AppEvent::InsertHistoryCell(Box::new(
                    history_cell::new_warning_event(MULTI_AGENT_ENABLE_NOTICE.to_string()),
                )));
            })],
            dismiss_on_select: true,
            ..Default::default()
        },
        SelectionItem {
            name: MULTI_AGENT_ENABLE_NO.to_string(),  // "Not now"
            description: Some("Keep subagents disabled.".to_string()),
            dismiss_on_select: true,
            ..Default::default()
        },
    ];

    self.bottom_pane.show_selection_view(SelectionViewParams {
        title: Some(MULTI_AGENT_ENABLE_TITLE.to_string()),  // "Enable subagents?"
        subtitle: Some("Subagents are currently disabled in your config.".to_string()),
        footer_hint: Some(standard_popup_hint_line()),
        items,
        ..Default::default()
    });
}
```

### 常量定义
```rust
const MULTI_AGENT_ENABLE_TITLE: &str = "Enable subagents?";
const MULTI_AGENT_ENABLE_YES: &str = "Yes, enable";
const MULTI_AGENT_ENABLE_NO: &str = "Not now";
const MULTI_AGENT_ENABLE_NOTICE: &str = "Subagents will be enabled in the next session.";
```

### Snapshot 内容
```
  Enable subagents?
  Subagents are currently disabled in your config.

› 1. Yes, enable  Save the setting now. You will need a new session to use it.
  2. Not now      Keep subagents disabled.

  Press enter to confirm or esc to go back
```

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs:2247-2277` | `open_multi_agent_enable_prompt()` - 启用提示主逻辑 |
| `codex-rs/tui_app_server/src/app.rs:2553` | 触发启用提示的调用点 |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs:8303-8329` | 测试用例实现 |
| `codex-rs/core/src/feature_flags.rs` | `Feature::Collab` 定义 |

### 触发条件
**文件**：`codex-rs/tui_app_server/src/app.rs` (约第 2550-2555 行)

```rust
fn open_agent_picker(&mut self) {
    if !self.feature_enabled(Feature::Collab) {
        self.chat_widget.open_multi_agent_enable_prompt();
        return;
    }
    // ... 正常处理代理选择
}
```

## 依赖与外部交互

### 依赖模块
1. **Feature Flags**：`Feature::Collab` 控制子代理功能可用性
2. **SelectionView**：通用选择界面组件
3. **AppEvent 系统**：处理功能启用和历史记录插入
4. **Config 系统**：持久化功能标志设置

### 事件流
```
用户尝试访问多代理功能
    ↓
检查 Feature::Collab 是否启用
    ↓
如果未启用 → 显示启用提示
    ↓
用户选择 "Yes, enable"
    ↓
发送 AppEvent::UpdateFeatureFlags { Collab: true }
    ↓
在历史记录中插入警告通知
    ↓
提示用户需要新会话才能使用
```

### 与配置系统的交互
- 功能标志更新通过 `AppEvent::UpdateFeatureFlags` 传播
- 配置持久化到 `config.toml`
- 新会话才能生效是因为功能标志在启动时读取

## 风险、边界与改进建议

### 潜在风险
1. **会话中断**：启用功能后需要重启会话，可能中断用户工作流
2. **权限提升**：子代理功能可能涉及额外的权限，需要用户理解安全风险
3. **功能依赖**：子代理功能可能依赖其他功能（如特定沙箱级别）

### 边界情况
1. **配置只读**：如果配置文件只读，无法保存设置
2. **并发修改**：多个会话同时修改配置可能导致冲突
3. **功能已启用**：重复调用应优雅处理（不显示提示）

### 改进建议
1. **即时生效**：探索无需重启即可启用功能的技术方案
2. **功能预览**：提供子代理功能的演示或文档链接
3. **批量启用**：允许用户一次启用多个相关功能
4. **撤销选项**：提供撤销启用操作的选项
5. **配置验证**：启用前验证系统环境是否满足要求
6. **渐进式启用**：允许在特定项目中试用功能

### 相关测试
- `multi_agent_enable_prompt_updates_feature_and_emits_notice`：测试功能更新和通知

### 代码示例：功能启用后的历史记录
```rust
tx.send(AppEvent::InsertHistoryCell(Box::new(
    history_cell::new_warning_event(
        "Subagents will be enabled in the next session.".to_string()
    ),
)));
```

这会在聊天历史中添加一条警告样式的消息，提醒用户需要新会话。
