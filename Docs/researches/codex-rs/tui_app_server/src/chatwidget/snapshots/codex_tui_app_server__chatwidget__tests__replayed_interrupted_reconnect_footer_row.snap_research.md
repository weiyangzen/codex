# Replayed Interrupted Reconnect Footer Row 研究文档

## 场景与职责

该 snapshot 测试验证在会话恢复（replay）场景下，当遇到流错误（如重新连接）时，页脚行的正确渲染行为。确保在重放中断的重新连接事件时，状态指示器不会错误地显示"Working"或"Reconnecting"状态。

**测试文件**: `codex-rs/tui_app_server/src/chatwidget/tests.rs`  
**Snapshot 文件**: `codex_tui_app_server__chatwidget__tests__replayed_interrupted_reconnect_footer_row.snap`

## 功能点目的

1. **会话恢复状态处理**: 在从会话日志重放事件时正确处理流错误事件
2. **避免状态混淆**: 确保重放的历史重新连接事件不会触发活跃状态指示器
3. **页脚一致性**: 保证在重放场景下页脚显示与正常操作场景一致
4. **用户体验**: 防止用户在恢复会话时看到令人困惑的"Reconnecting"状态

## 具体技术实现

### 测试场景构建
```rust
#[tokio::test]
async fn replayed_interrupted_reconnect_footer_row_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;
    
    // 重放初始消息序列：TurnStarted 后紧跟 StreamError
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
    
    // 断言：不应包含 "Reconnecting" 或 "Working"
    assert!(
        !header.contains("Reconnecting") && !header.contains("Working"),
        "expected replayed interrupted reconnect to avoid active status row, got {header:?}"
    );
    assert_snapshot!("replayed_interrupted_reconnect_footer_row", header);
}
```

### 重放逻辑处理
```rust
fn replay_initial_messages(&mut self, messages: Vec<EventMsg>) {
    for msg in messages {
        self.handle_codex_event_replay(Event { id: "replay".into(), msg });
    }
}

fn handle_codex_event_replay(&mut self, event: Event) {
    // 重放模式下的特殊处理：
    // - 不触发状态指示器
    // - 不启动计时器
    // - 仅更新历史记录
    match event.msg {
        EventMsg::TurnStarted(_) => {
            // 重放时不设置 agent_turn_running = true
        }
        EventMsg::StreamError(_) => {
            // 重放时不显示重新连接状态
        }
        // ...
    }
}
```

### 页脚第一行渲染
```rust
fn render_bottom_first_row(chat: &ChatWidget, width: u16) -> String {
    let height = chat.desired_height(width);
    let area = Rect::new(0, 0, width, height);
    let mut buf = Buffer::empty(area);
    chat.render(area, &mut buf);
    
    // 找到第一个非空行
    for y in 0..area.height {
        let mut row = String::new();
        for x in 0..area.width {
            let s = buf[(x, y)].symbol();
            row.push_str(if s.is_empty() { " " } else { s });
        }
        if !row.trim().is_empty() {
            return row;
        }
    }
    String::new()
}
```

## 关键代码路径与文件引用

| 文件路径 | 相关代码/函数 | 说明 |
|---------|-------------|------|
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | `replayed_interrupted_reconnect_footer_row_snapshot()` (L11158) | 测试函数 |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | `render_bottom_first_row()` (L7281) | 页脚首行渲染辅助函数 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | `replay_initial_messages()` | 消息重放函数 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | `handle_codex_event_replay()` | 重放事件处理 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | `on_stream_error()` | 流错误处理 |
| `codex-rs/tui_app_server/src/status_indicator_widget.rs` | `StatusIndicatorWidget` | 状态指示器组件 |

## 依赖与外部交互

### 依赖模块
- `codex_protocol::protocol::StreamErrorEvent`: 流错误事件
- `codex_protocol::protocol::TurnStartedEvent`: 回合开始事件
- `codex_protocol::protocol::CodexErrorInfo`: 错误信息类型
- `crate::status_indicator_widget::StatusIndicatorWidget`: 状态指示器

### 事件类型
```rust
pub struct StreamErrorEvent {
    pub message: String,                    // "Reconnecting... 2/5"
    pub codex_error_info: Option<CodexErrorInfo>,  // Other
    pub additional_details: Option<String>, // "Idle timeout waiting for SSE"
}
```

### 重放与正常处理的差异
| 场景 | TurnStarted | StreamError |
|------|-------------|-------------|
| 正常处理 | 设置 agent_turn_running = true，显示状态指示器 | 更新状态指示器显示重新连接 |
| 重放处理 | 仅记录历史，不激活状态 | 仅记录历史，不更新状态指示器 |

## 风险、边界与改进建议

### 潜在风险
1. **状态泄漏**: 重放事件可能意外触发正常的状态更新逻辑
2. **竞态条件**: 重放过程中如果收到新事件，可能导致状态混乱
3. **时序问题**: 重放事件的顺序可能与实际发生时不完全一致

### 边界情况
1. **空重放列表**: 没有事件需要重放时的处理
2. **不完整序列**: TurnStarted 但没有对应的 TurnComplete
3. **多次重连**: 序列中包含多个 StreamError 事件
4. **混合事件**: 重放列表中包含非历史事件类型

### 改进建议
1. **重放标记**: 为重放的事件添加标记，确保下游组件能区分重放和实时事件
2. **状态隔离**: 完全隔离重放状态和实时状态，使用独立的状态机
3. **重放进度**: 显示重放进度指示，让用户知道正在恢复会话
4. **错误聚合**: 重放时合并连续的 StreamError 事件，减少噪音
5. **验证机制**: 重放完成后验证状态一致性

### 相关测试覆盖
- 重放中断重新连接场景（本测试）
- 正常流错误处理测试
- 会话恢复完整性测试
- 状态指示器激活/停用测试

### Snapshot 内容分析
```
› Ask Codex to do anything
```

**关键观察点**:
1. 页脚显示正常的输入提示符（›）
2. 没有 "Working" 或 "Reconnecting" 状态文本
3. 没有状态指示器（spinner）
4. 显示默认占位符文本 "Ask Codex to do anything"

这表明重放逻辑正确地抑制了状态指示器的激活，保持了页脚的干净和一致性。
