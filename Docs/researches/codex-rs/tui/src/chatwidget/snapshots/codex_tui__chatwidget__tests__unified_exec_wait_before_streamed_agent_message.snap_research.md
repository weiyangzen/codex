# 研究报告: unified_exec_wait_before_streamed_agent_message.snap

## 场景与职责

该快照文件验证 **Unified Exec** 在 Agent 流式消息之前进入等待状态时的渲染效果。与 `unified_exec_wait_after_final_agent_message` 相反，此测试关注后台操作在 Agent 开始回复前就已等待的场景。

测试场景：
- 回合开始
- 启动 Unified Exec
- 发送空交互进入等待
- Agent 开始流式回复 "Streaming response."
- 回合完成（无最终消息）
- 验证历史记录

## 功能点目的

**流式回复与后台操作协调**：

1. **时序处理** - 正确处理操作和回复的交错
2. **流式显示** - Agent 回复流式显示，后台状态独立
3. **状态一致性** - 确保所有状态正确归档
4. **用户体验** - 清晰的时序展示

## 具体技术实现

### 测试实现

```rust
// tests.rs:5230-5270
#[tokio::test]
async fn unified_exec_wait_before_streamed_agent_message_snapshot() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
    chat.handle_codex_event(Event {
        id: "turn-1".into(),
        msg: EventMsg::TurnStarted(TurnStartedEvent {
            turn_id: "turn-1".to_string(),
            model_context_window: None,
            collaboration_mode_kind: ModeKind::Default,
        }),
    });

    // 启动并进入等待
    begin_unified_exec_startup(&mut chat, "call-wait-stream", "proc-1", "cargo test -p codex-core");
    terminal_interaction(&mut chat, "call-wait-stream-stdin", "proc-1", "");

    // Agent 流式回复
    chat.handle_codex_event(Event {
        id: "turn-1".into(),
        msg: EventMsg::AgentMessageDelta(AgentMessageDeltaEvent {
            delta: "Streaming response.".into(),
        }),
    });
    chat.handle_codex_event(Event {
        id: "turn-1".into(),
        msg: EventMsg::TurnComplete(TurnCompleteEvent {
            turn_id: "turn-1".to_string(),
            last_agent_message: None, // 无最终消息
        }),
    });

    let cells = drain_insert_history(&mut rx);
    let combined = cells
        .iter()
        .map(|lines| lines_to_single_string(lines))
        .collect::<String>();
    assert_snapshot!("unified_exec_wait_before_streamed_agent_message", combined);
}
```

### 渲染输出

```
• Waited for background terminal · cargo test -p codex-core

• Streaming response.
```

**解析**：
- 第一行：`Waited for background terminal` - 等待记录
- 空行分隔
- 第二行：`Streaming response.` - 流式回复内容

## 关键代码路径与文件引用

| 文件 | 行号范围 | 描述 |
|------|----------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 5230-5270 | 流式消息前等待测试 |

## 与 after_final 的区别

| 场景 | 消息来源 | 回合完成方式 |
|------|----------|--------------|
| `after_final` | `last_agent_message` | 有最终消息 |
| `before_streamed` | `AgentMessageDelta` | 无最终消息 |

## 风险、边界与改进建议

### 特定风险

1. **流式中断** - 流式回复中断时的状态处理
2. **增量合并** - 多个增量如何合并为最终历史记录
3. **时序错乱** - 网络和渲染导致的显示顺序问题

### 改进建议

1. **时间戳** - 添加事件时间戳用于调试
2. **流式指示** - 显示流式回复进行中
3. **断点恢复** - 支持流式回复的断点续传

### 相关测试

- `unified_exec_wait_after_final_agent_message` - 最终消息后等待
