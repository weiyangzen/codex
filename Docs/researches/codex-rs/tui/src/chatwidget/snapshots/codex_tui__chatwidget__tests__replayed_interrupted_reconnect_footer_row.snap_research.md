# 研究报告: replayed_interrupted_reconnect_footer_row.snap

## 场景与职责

该快照文件验证在**会话重放场景**中，当遇到中断重连事件时，底部状态行的渲染行为。具体来说，它确保在重放历史消息时，"Reconnecting..." 状态不会错误地显示为活动状态。

测试场景：
- 会话开始 (`TurnStarted`)
- 发生流错误，显示 "Reconnecting... 2/5"
- 验证底部状态行**不**显示重连状态（因为是重放，不是实时）

## 功能点目的

**会话重放**是 Codex 恢复历史会话时的关键功能：

1. **状态区分** - 区分实时事件和重放事件的处理
2. **避免误导** - 重放时的重连状态不应显示为当前活动状态
3. **用户体验** - 用户不应看到已解决的历史连接问题

## 具体技术实现

### 测试实现

```rust
// tests.rs:10425-10448
#[tokio::test]
async fn replayed_interrupted_reconnect_footer_row_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;

    // 使用 replay_initial_messages 重放历史事件
    chat.replay_initial_messages(vec![
        EventMsg::TurnStarted(TurnStartedEvent {
            turn_id: "turn-1".to_string(),
            model_context_window: None,
            collaboration_mode_kind: ModeKind::Default,
        }),
        EventMsg::StreamError(StreamErrorEvent {
            message: "Reconnecting... 2/5".to_string(),
            codex_error_info: Some(CodexErrorInfo::Other),
            additional_details: Some("Idle timeout waiting for SSE".to_string()),
        }),
    ]);

    let header = render_bottom_first_row(&chat, 80);
    // 验证不显示重连或工作状态
    assert!(
        !header.contains("Reconnecting") && !header.contains("Working"),
        "expected replayed interrupted reconnect to avoid active status row"
    );
    assert_snapshot!("replayed_interrupted_reconnect_footer_row", header);
}
```

### 关键区分逻辑

```rust
// 重放事件处理（与实时事件区分）
fn handle_codex_event_replay(&mut self, event: Event) {
    // 重放时某些状态更新被抑制
    match &event.msg {
        EventMsg::StreamError { .. } => {
            // 不更新底部状态指示器
        }
        _ => { /* 正常处理 */ }
    }
}
```

### 渲染输出

```
› Ask Codex to do anything
```

**关键点**：
- 仅显示输入提示 `› Ask Codex to do anything`
- 没有 `• Working` 或 `• Reconnecting` 状态指示
- 表明重放的中断事件被正确处理，不影响当前 UI 状态

## 关键代码路径与文件引用

| 文件 | 行号范围 | 描述 |
|------|----------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 10425-10448 | 重放中断重连测试 |
| `codex-rs/tui/src/chatwidget/mod.rs` | - | `replay_initial_messages` 方法 |
| `codex-rs/tui/src/chatwidget/mod.rs` | - | `handle_codex_event` vs `handle_codex_event_replay` |

## 依赖与外部交互

### 事件类型

```rust
// 关键事件类型
codex_protocol::protocol::StreamErrorEvent {
    message: String,                    // "Reconnecting... 2/5"
    codex_error_info: Option<CodexErrorInfo>,  // Other
    additional_details: Option<String>, // "Idle timeout waiting for SSE"
}
```

### 状态管理

- `chat.current_status.header` - 当前状态标题
- `chat.bottom_pane.status_widget()` - 底部状态组件
- `chat.retry_status_header` - 重试状态（重放时应为 None）

## 风险、边界与改进建议

### 特定风险

1. **状态泄漏** - 重放事件意外更新实时状态
2. **竞态条件** - 重放过程中用户发起新操作
3. **错误分类** - 某些错误在重放时可能需要特殊处理

### 边界情况

1. **重放中断** - 重放过程中发生新的连接错误
2. **混合事件** - 部分历史事件 + 部分实时事件
3. **多次重连** - 历史中有多次重连记录

### 改进建议

1. **视觉区分** - 重放历史时添加视觉标记（如灰色时间戳）
2. **进度指示** - 显示重放进度 "恢复会话中 (3/15)..."
3. **错误汇总** - 重放完成后汇总显示历史错误
4. **测试扩展** - 添加更多重放场景测试（如多次中断、不同错误类型）

### 相关测试

- `stream_error_restores_hidden_status_indicator` - 实时流错误恢复测试
- `stream_error_updates_status_indicator` - 实时流错误状态更新测试
- `resumed_initial_messages_render_history` - 会话恢复历史渲染测试
