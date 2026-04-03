# Research: unified_exec_wait_before_streamed_agent_message Snapshot Test

## 场景与职责

该 snapshot 测试验证 `tui_app_server` 中 `ChatWidget` 组件在**流式代理消息之前统一执行等待状态**的历史记录渲染行为。与 `unified_exec_wait_after_final_agent_message` 不同，此测试验证：

1. Turn 开始
2. 启动统一执行进程并进入等待状态
3. 接收流式代理消息（`AgentMessageDelta`）
4. Turn 完成（但没有 `last_agent_message`）
5. 验证历史记录正确显示等待状态和流式响应

此测试确保在流式输出场景下，等待状态和流式消息的历史记录正确处理。

## 功能点目的

### 核心功能
- **流式消息处理**：处理 `AgentMessageDelta` 事件，累积流式输出
- **等待状态与流式消息共存**：确保等待状态和流式消息都能正确显示
- **Turn 完成时的刷新**：在没有最终消息的情况下正确刷新状态

### 业务价值
- 支持实时的流式响应显示
- 确保后台终端等待状态不影响流式消息显示
- 提供完整的流式对话历史

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
begin_unified_exec_startup(&mut chat, "call-wait-stream", "proc-1", "cargo test -p codex-core");
terminal_interaction(&mut chat, "call-wait-stream-stdin", "proc-1", "");

// 3. 接收流式代理消息
chat.handle_codex_event(Event {
    id: "turn-1".into(),
    msg: EventMsg::AgentMessageDelta(AgentMessageDeltaEvent {
        delta: "Streaming response.".into(),
    }),
});

// 4. Turn 完成（无最终消息）
chat.handle_codex_event(Event {
    id: "turn-1".into(),
    msg: EventMsg::TurnComplete(TurnCompleteEvent {
        turn_id: "turn-1".to_string(),
        last_agent_message: None,  // 无最终消息
    }),
});
```

### 渲染验证
```rust
let cells = drain_insert_history(&mut rx);
let combined = cells
    .iter()
    .map(|lines| lines_to_single_string(lines))
    .collect::<String>();
assert_snapshot!("unified_exec_wait_before_streamed_agent_message", combined);
```

### Snapshot 输出分析
生成的 snapshot 显示历史记录：
```
• Waited for background terminal · cargo test -p codex-core

• Streaming response.
```

关键元素：
- `• Waited for background terminal · cargo test -p codex-core`：等待状态记录
- `• Streaming response.`：流式响应内容

注意：与 `after_final_agent_message` 的区别在于，这里的响应是通过 `AgentMessageDelta` 累积的流式内容，而不是完整的 `AgentMessage`。

## 关键代码路径与文件引用

### 主要文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs` | `ChatWidget` 主实现，包含流式消息处理 |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试实现，包含 `unified_exec_wait_before_streamed_agent_message_snapshot` |
| `codex-rs/tui_app_server/src/streaming/` | 流式处理模块 |

### 关键代码路径
```rust
// chatwidget.rs: handle_agent_message_delta
fn handle_agent_message_delta(&mut self, ev: AgentMessageDeltaEvent) {
    // 累积流式增量到缓冲区
    self.streaming_buffer.push_str(&ev.delta);
    
    // 更新活动单元格
    if let Some(active_cell) = &mut self.active_cell {
        active_cell.append_content(&ev.delta);
    } else {
        // 创建新的活动单元格
        self.active_cell = Some(Box::new(AgentMessageCell::new(&ev.delta)));
    }
    
    // 请求重绘
    self.frame_requester.request_frame();
}

// chatwidget.rs: handle_turn_complete (流式场景)
fn handle_turn_complete(&mut self, ev: TurnCompleteEvent) {
    // 刷新等待状态
    self.flush_unified_exec_wait_state();
    
    // 处理流式缓冲区
    if !self.streaming_buffer.is_empty() {
        // 创建流式消息历史记录
        let history_cell = Box::new(AgentMessageCell::from_buffer(
            std::mem::take(&mut self.streaming_buffer)
        ));
        self.app_event_tx.send(AppEvent::InsertHistoryCell(history_cell));
    }
    
    // 刷新活动单元格
    if let Some(active_cell) = self.active_cell.take() {
        self.flush_active_cell_to_history(active_cell);
    }
    
    self.agent_turn_running = false;
}
```

### 数据结构
```rust
// AgentMessageDeltaEvent
pub struct AgentMessageDeltaEvent {
    pub delta: String,  // 流式增量内容
}

// ChatWidget 流式相关字段
pub struct ChatWidget {
    streaming_buffer: String,  // 流式内容累积缓冲区
    // ...
}
```

## 依赖与外部交互

### 内部依赖
- `codex_protocol::protocol::AgentMessageDeltaEvent`：流式消息增量事件
- `codex_protocol::protocol::TurnCompleteEvent`：Turn 完成事件
- `crate::streaming::commit_tick`：流式提交机制

### 外部交互
- `FrameRequester::request_frame()`：请求 UI 重绘
- `AppEvent::InsertHistoryCell`：插入历史记录

### 流式处理生命周期
```
TurnStarted
    ↓
ExecCommandBegin → 创建统一执行进程
    ↓
TerminalInteraction (空) → 进入等待状态
    ↓
AgentMessageDelta ("Streaming") → 累积到 streaming_buffer
    ↓
AgentMessageDelta (" response.") → 继续累积
    ↓
TurnComplete (last_agent_message=None) →
    ├── 刷新等待状态
    ├── 刷新 streaming_buffer 到历史记录
    └── 重置状态
```

## 风险、边界与改进建议

### 潜在风险
1. **流式缓冲区溢出**：长时间流式输出可能导致缓冲区过大
2. **乱序事件**：`AgentMessageDelta` 和 `TurnComplete` 乱序到达可能导致数据丢失
3. **编码问题**：流式内容中的特殊字符可能导致渲染问题

### 边界条件
- 空流式缓冲区（无 `AgentMessageDelta` 到达）
- 极长的流式输出
- 包含特殊字符（如 ANSI 转义序列）的流式内容
- 快速连续的 `AgentMessageDelta` 事件

### 改进建议
1. **增加缓冲区大小限制**：防止内存溢出
2. **增加流式内容验证**：确保特殊字符正确处理
3. **增加增量提交**：对于长流式输出，定期提交到历史记录
4. **增加边界测试**：
   - 空流式内容
   - 超长流式内容
   - 包含特殊字符的内容

### 相关测试
- `codex_tui_app_server__chatwidget__tests__unified_exec_wait_after_final_agent_message.snap`：最终消息后等待测试
- `codex_tui_app_server__chatwidget__tests__deltas_then_same_final_message_are_rendered_snapshot.snap`：增量后最终消息测试
- `codex_tui_app_server__chatwidget__tests__final_reasoning_then_message_without_deltas_are_rendered.snap`：推理后消息测试
