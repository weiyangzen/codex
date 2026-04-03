# 多代理启用提示测试研究文档

## 场景与职责

该 snapshot 测试验证当用户尝试启用多代理（子代理）功能时，tui_app_server 的 ChatWidget 能够正确显示启用确认提示。

**测试场景**：
1. 用户当前配置中禁用了子代理功能
2. 用户触发启用多代理的操作
3. 系统显示确认提示，说明启用子代理的后果

**职责**：确保用户在启用实验性子代理功能前得到明确的确认提示，了解该设置需要新会话才能生效。

## 功能点目的

- **功能发现**：提示用户子代理功能当前被禁用
- **明确后果**：告知用户启用后需要新会话才能使用
- **即时保存**：说明设置会立即保存
- **用户控制**：提供明确的"是"和"否"选项，尊重用户选择

## 具体技术实现

### 测试代码位置
`codex-rs/tui_app_server/src/chatwidget/tests.rs` 第 8302-8310 行

```rust
#[tokio::test]
async fn multi_agent_enable_prompt_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;

    chat.open_multi_agent_enable_prompt();

    let popup = render_bottom_popup(&chat, 80);
    assert_snapshot!("multi_agent_enable_prompt", popup);
}
```

### 相关功能测试

同一文件的第 8313-8329 行测试了启用后的行为：

```rust
#[tokio::test]
async fn multi_agent_enable_prompt_updates_feature_and_emits_notice() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;

    chat.open_multi_agent_enable_prompt();
    chat.handle_key_event(KeyEvent::from(KeyCode::Enter));

    assert_matches!(
        rx.try_recv(),
        Ok(AppEvent::UpdateFeatureFlags { updates }) if updates == vec![(Feature::Collab, true)]
    );
    // ... 验证历史记录显示
}
```

### 关键实现细节

1. **打开提示**：调用 `open_multi_agent_enable_prompt()` 显示启用确认对话框
2. **配置检查**：检查当前配置中子代理功能是否已启用
3. **用户确认**：通过键盘事件（Enter）确认启用
4. **事件发送**：确认后发送 `UpdateFeatureFlags` 事件更新功能标志
5. **历史记录**：在历史中显示启用通知

### Snapshot 输出内容

```
Enable subagents?
Subagents are currently disabled in your config.

› 1. Yes, enable  Save the setting now. You will need a new session to use it.
  2. Not now      Keep subagents disabled.

Press enter to confirm or esc to go back
```

## 关键代码路径与文件引用

### 主要代码文件

1. **测试文件**：`codex-rs/tui_app_server/src/chatwidget/tests.rs`
   - 测试函数：`multi_agent_enable_prompt_snapshot` (第 8302 行)
   - 功能测试：`multi_agent_enable_prompt_updates_feature_and_emits_notice` (第 8313 行)

2. **ChatWidget 实现**：`codex-rs/tui_app_server/src/chatwidget/mod.rs`
   - 方法：`open_multi_agent_enable_prompt`

3. **底部面板**：`codex-rs/tui_app_server/src/bottom_pane/mod.rs`
   - 负责渲染确认对话框 UI

4. **功能标志管理**：`codex-rs/tui_app_server/src/features.rs`（假设位置）
   - 管理 `Feature::Collab` 功能标志

### 相关协议类型

- `Feature`：功能标志枚举，包含 `Collab`（协作/子代理）
- `AppEvent::UpdateFeatureFlags`：更新功能标志的事件

## 依赖与外部交互

### 内部依赖

| 组件 | 用途 |
|------|------|
| `ChatWidget` | 主聊天组件，管理多代理启用流程 |
| `BottomPane` | 渲染确认对话框 UI |
| `Feature` | 功能标志定义 |
| `AppEventSender` | 发送功能标志更新事件 |

### 外部依赖

- `ratatui`：终端 UI 渲染库
- `insta`：snapshot 测试框架
- `tokio`：异步运行时

### 配置依赖

- 子代理功能状态存储在用户配置中
- 需要 `Feature::Collab` 功能标志控制

## 风险、边界与改进建议

### 潜在风险

1. **实验性功能**：子代理功能可能不稳定，用户启用后可能遇到意外问题
2. **会话中断**：启用后需要新会话，可能导致用户工作流中断
3. **配置持久化**：如果配置保存失败，用户可能需要重复启用过程

### 边界情况

1. **已启用状态**：如果子代理已启用，不应再次显示启用提示
2. **网络依赖**：某些子代理功能可能需要网络连接，离线时的行为
3. **权限限制**：某些环境可能不允许启用子代理功能

### 改进建议

1. **功能说明**：在提示中提供更多关于子代理功能的具体说明和用例
2. **快速重启**：提供快捷方式直接重启会话以应用更改
3. **回滚选项**：允许用户轻松禁用子代理功能
4. **渐进启用**：考虑支持在不重启的情况下启用某些子代理功能
5. **状态指示**：在主界面显示子代理功能的当前状态

### 相关测试

- `multi_agent_enable_prompt_updates_feature_and_emits_notice`：验证启用后的功能更新和历史记录
- 其他功能标志相关测试
