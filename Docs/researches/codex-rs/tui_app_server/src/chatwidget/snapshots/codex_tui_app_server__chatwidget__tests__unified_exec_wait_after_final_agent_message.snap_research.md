# Research: unified_exec_wait_after_final_agent_message Snapshot Test

## 场景与职责

该 snapshot 测试验证 `tui_app_server` 中 `ChatWidget` 组件在**最终代理消息之后统一执行等待状态**的历史记录渲染行为。具体场景包括：

1. Turn 开始
2. 启动统一执行进程并发送空输入（进入等待状态）
3. 完成代理消息（最终响应）
4. Turn 完成
5. 验证历史记录正确显示等待状态和最终响应

此测试确保在 Turn 完成前后，统一执行等待状态和代理消息的历史记录正确归档。

## 功能点目的

### 核心功能
- **等待状态历史化**：将统一执行等待状态转换为历史记录
- **代理消息归档**：在 Turn 完成时正确归档最终代理消息
- **历史记录顺序**：确保等待状态和代理消息的顺序正确

### 业务价值
- 提供完整的对话历史，包括等待后台终端的状态
- 帮助用户理解对话的完整流程
- 确保最终响应和等待状态的关联性

## 具体技术实现

### 测试设置
```rust
let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;

// 1. Turn 开始
chat.handle_codex_event(Event {
    id: "turn-1".into(),
    msg: EventMsg::TurnStarted(TurnStartedEvent {
        turn_id: "turn-1".to_string(),
        model_context_window: None,
        collaboration_mode_kind: ModeKind::Default,
    }),
});

// 2. 启动统一执行并进入等待状态
begin_unified_exec_startup(&mut chat, "call-wait", "proc-1", "cargo test -p codex-core");
terminal_interaction(&mut chat, "call-wait-stdin", "proc-1", "");

// 3. 完成代理消息（最终响应）
complete_assistant_message(&mut chat, "msg-1", "Final response.", None);

// 4. Turn 完成
chat.handle_codex_event(Event {
    id: "turn-1".into(),
    msg: EventMsg::TurnComplete(TurnCompleteEvent {
        turn_id: "turn-1".to_string(),
        last_agent_message: Some("Final response.".into()),
    }),
});
```

### `complete_assistant_message` 辅助函数
```rust
fn complete_assistant_message(
    chat: &mut ChatWidget,
    message_id: &str,
    content: &str,
    phase: Option<MessagePhase>,
) {
    // 发送代理消息事件
    chat.handle_codex_event(Event {
        id: message_id.into(),
        msg: EventMsg::AgentMessage(AgentMessageEvent {
            message: content.to_string(),
            phase,
            memory_citation: None,
        }),
    });
    // 发送完成事件
    chat.handle_codex_event(Event {
        id: message_id.into(),
        msg: EventMsg::ItemCompleted(ItemCompletedEvent {
            thread_id: ThreadId::new(),
            turn_id: "turn-1".to_string(),
            item: TurnItem::AgentMessage(AgentMessageItem {
                id: message_id.to_string(),
                content: vec![AgentMessageContent::Text { text: content.to_string() }],
                phase,
                memory_citation: None,
            }),
        }),
    });
}
```

### 渲染验证
```rust
let cells = drain_insert_history(&mut rx);
let combined = cells
    .iter()
    .map(|lines| lines_to_single_string(lines))
    .collect::<String>();
assert_snapshot!("unified_exec_wait_after_final_agent_message", combined);
```

### Snapshot 输出分析
生成的 snapshot 显示历史记录：
```
• Waited for background terminal · cargo test -p codex-core

• Final response.
```

关键元素：
- `• Waited for background terminal · cargo test -p codex-core`：等待状态记录
- `• Final response.`：最终代理消息

注意：等待状态记录在最终响应之前，反映了事件发生的实际顺序。

## 关键代码路径与文件引用

### 主要文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs` | `ChatWidget` 主实现，包含 Turn 完成处理 |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试实现，包含 `unified_exec_wait_after_final_agent_message_snapshot` |
| `codex-rs/tui_app_server/src/history_cell.rs` | 历史记录单元格实现 |

### 关键代码路径
```rust
// chatwidget.rs: handle_turn_complete
fn handle_turn_complete(&mut self, ev: TurnCompleteEvent) {
    // 刷新所有待处理的状态到历史记录
    self.flush_unified_exec_wait_state();
    
    // 刷新活动单元格
    if let Some(active_cell) = self.active_cell.take() {
        self.flush_active_cell_to_history(active_cell);
    }
    
    // 重置 Turn 状态
    self.agent_turn_running = false;
    self.current_status = StatusIndicatorState::idle();
}

// 刷新统一执行等待状态
fn flush_unified_exec_wait_state(&mut self) {
    if let Some(wait_state) = self.last_unified_wait.take() {
        // 创建等待状态历史记录
        let history_cell = Box::new(PlainHistoryCell::new(vec![
            format!("• Waited for background terminal · {}", wait_state.command_display)
        ]));
        self.app_event_tx.send(AppEvent::InsertHistoryCell(history_cell));
    }
}
```

### 数据结构
```rust
// UnifiedExecWaitState
struct UnifiedExecWaitState {
    command_display: String,
}

// TurnCompleteEvent
pub struct TurnCompleteEvent {
    pub turn_id: String,
    pub last_agent_message: Option<String>,
}
```

## 依赖与外部交互

### 内部依赖
- `codex_protocol::protocol::TurnCompleteEvent`：Turn 完成事件
- `codex_protocol::protocol::AgentMessageEvent`：代理消息事件
- `codex_protocol::protocol::ItemCompletedEvent`：项目完成事件

### 外部交互
- `AppEvent::InsertHistoryCell`：插入历史记录单元格
- `last_unified_wait`：存储最后的统一执行等待状态

### 生命周期
```
TurnStarted
    ↓
ExecCommandBegin (UnifiedExec) → 创建统一执行进程
    ↓
TerminalInteraction (空输入) → 进入等待状态，更新 last_unified_wait
    ↓
AgentMessage → 创建代理消息活动单元格
    ↓
ItemCompleted → 归档代理消息
    ↓
TurnComplete → 
    ├── 刷新等待状态到历史记录
    ├── 刷新代理消息到历史记录
    └── 重置 Turn 状态
```

## 风险、边界与改进建议

### 潜在风险
1. **状态丢失**：如果 TurnComplete 事件丢失，等待状态可能不会被历史化
2. **顺序错误**：如果事件乱序到达，历史记录的顺序可能不正确
3. **重复记录**：如果多个 TurnComplete 事件到达，可能产生重复记录

### 边界条件
- Turn 完成时没有等待状态
- 多个等待状态累积
- Turn 完成前没有代理消息
- 快速连续的 Turn 开始和完成

### 改进建议
1. **增加状态持久化**：在等待状态创建时就持久化，避免丢失
2. **增加顺序验证**：添加序列号确保事件顺序
3. **增加去重机制**：防止重复的历史记录
4. **增加边界测试**：
   - Turn 完成时没有等待状态
   - 多个等待状态
   - 没有代理消息的 Turn

### 相关测试
- `codex_tui_app_server__chatwidget__tests__unified_exec_wait_before_streamed_agent_message.snap`：流式消息前等待测试
- `codex_tui_app_server__chatwidget__tests__unified_exec_waiting_multiple_empty_after.snap`：多等待状态测试
- `codex_tui_app_server__chatwidget__tests__final_reasoning_then_message_without_deltas_are_rendered.snap`：最终消息渲染测试
