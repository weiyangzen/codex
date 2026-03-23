# 研究报告: unified_exec_wait_after_final_agent_message.snap

## 场景与职责

该快照文件验证 **Unified Exec** 在 Agent 最终消息之后进入等待状态时的渲染效果。这模拟了 Codex 完成回复但后台终端仍在运行的场景。

测试场景：
- 回合开始
- 启动 Unified Exec（`cargo test -p codex-core`）
- 发送空交互（进入等待）
- Agent 发送最终消息 "Final response."
- 回合完成
- 验证历史记录正确显示等待状态和最终消息

## 功能点目的

**异步操作完成处理**：

1. **消息分离** - Agent 回复与后台操作独立
2. **状态延续** - 回合完成后后台操作状态保留
3. **历史完整** - 记录完整的操作和回复序列
4. **用户体验** - 用户知道后台仍在运行尽管回复已完成

## 具体技术实现

### 测试实现

```rust
// tests.rs:5198-5228
#[tokio::test]
async fn unified_exec_wait_after_final_agent_message_snapshot() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
    chat.handle_codex_event(Event {
        id: "turn-1".into(),
        msg: EventMsg::TurnStarted(TurnStartedEvent {
            turn_id: "turn-1".to_string(),
            model_context_window: None,
            collaboration_mode_kind: ModeKind::Default,
        }),
    });

    // 启动 Unified Exec
    begin_unified_exec_startup(&mut chat, "call-wait", "proc-1", "cargo test -p codex-core");
    // 空交互进入等待
    terminal_interaction(&mut chat, "call-wait-stdin", "proc-1", "");

    // Agent 发送最终消息
    complete_assistant_message(&mut chat, "msg-1", "Final response.", None);
    chat.handle_codex_event(Event {
        id: "turn-1".into(),
        msg: EventMsg::TurnComplete(TurnCompleteEvent {
            turn_id: "turn-1".to_string(),
            last_agent_message: Some("Final response.".into()),
        }),
    });

    let cells = drain_insert_history(&mut rx);
    let combined = cells
        .iter()
        .map(|lines| lines_to_single_string(lines))
        .collect::<String>();
    assert_snapshot!("unified_exec_wait_after_final_agent_message", combined);
}
```

### 渲染输出

```
• Waited for background terminal · cargo test -p codex-core

• Final response.
```

**解析**：
- 第一行：`Waited for background terminal` - 后台终端等待记录
- `· cargo test -p codex-core` - 关联的命令
- 空行：分隔
- 第二行：`Final response.` - Agent 的最终回复

**注意**：等待记录在前，最终回复在后，反映了事件发生的顺序。

## 关键代码路径与文件引用

| 文件 | 行号范围 | 描述 |
|------|----------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 5198-5228 | 最终消息后等待测试 |
| `codex-rs/tui/src/chatwidget/tests.rs` | 3450-3470 | `complete_assistant_message` 辅助函数 |

## 依赖与外部交互

### 回合完成与后台操作

```rust
fn on_turn_complete(&mut self, event: TurnCompleteEvent) {
    // 保存 Agent 消息
    if let Some(msg) = event.last_agent_message {
        self.add_agent_message_to_history(msg);
    }
    
    // 注意：Unified Exec 进程不在这里清理
    // 它们在单独的事件中管理
}
```

## 风险、边界与改进建议

### 特定风险

1. **状态不一致** - 用户可能误以为后台已完成
2. **消息顺序** - 后台输出可能在最终消息之后到达
3. **上下文丢失** - 回合完成后上下文可能重置

### 改进建议

1. **后台提示** - 最终消息中提示后台仍在运行
2. **完成通知** - 后台完成时发送通知
3. **状态持久** - 跨回合保持后台状态显示

### 相关测试

- `unified_exec_wait_before_streamed_agent_message` - 流式消息前等待
