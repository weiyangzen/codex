# 研究报告: unified_exec_waiting_multiple_empty_after.snap

## 场景与职责

该快照文件验证 **Unified Exec** 在多次空交互后的历史记录渲染。当用户多次查看后台终端状态（发送空交互）时，系统应正确记录这些等待状态。

测试场景：
- 启动 Unified Exec
- 连续发送两次空交互
- 回合完成
- 验证历史记录

## 功能点目的

**重复等待状态处理**：

1. **去重或保留** - 决定是否合并连续的等待记录
2. **状态追踪** - 记录用户的查看行为
3. **历史简洁** - 避免历史记录过度膨胀
4. **时间感知** - 可能记录每次查看的时间

## 具体技术实现

### 测试实现

```rust
// tests.rs:5302-5335
#[tokio::test]
async fn unified_exec_waiting_multiple_empty_snapshots() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
    chat.on_task_started();
    begin_unified_exec_startup(&mut chat, "call-wait-1", "proc-1", "just fix");

    // 两次空交互
    terminal_interaction(&mut chat, "call-wait-1a", "proc-1", "");
    terminal_interaction(&mut chat, "call-wait-1b", "proc-1", "");
    
    assert_eq!(
        chat.current_status.header,
        "Waiting for background terminal"
    );
    let status = chat.bottom_pane.status_widget()
        .expect("status indicator should be visible");
    assert_eq!(status.header(), "Waiting for background terminal");
    assert_eq!(status.details(), Some("just fix"));

    // 回合完成
    chat.handle_codex_event(Event {
        id: "turn-wait-1".into(),
        msg: EventMsg::TurnComplete(TurnCompleteEvent {
            turn_id: "turn-1".to_string(),
            last_agent_message: None,
        }),
    });

    let cells = drain_insert_history(&mut rx);
    let combined = cells
        .iter()
        .map(|lines| lines_to_single_string(lines))
        .collect::<String>();
    assert_snapshot!("unified_exec_waiting_multiple_empty_after", combined);
}
```

### 渲染输出

```
• Waited for background terminal · just fix
```

**解析**：
- 仅显示一条等待记录
- 多次空交互被合并为单条记录

**注意**：这验证了系统的去重行为，避免重复记录相同的等待状态。

## 关键代码路径与文件引用

| 文件 | 行号范围 | 描述 |
|------|----------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 5302-5335 | 多次空交互测试 |

## 去重逻辑

```rust
fn on_terminal_interaction(&mut self, event: TerminalInteractionEvent) {
    if event.stdin.is_empty() {
        // 检查是否已有相同的等待记录
        if !self.has_recent_wait_record(&event.process_id) {
            self.add_wait_record(&event);
        }
        // 否则忽略重复的空交互
    }
}
```

## 风险、边界与改进建议

### 特定风险

1. **信息丢失** - 去重可能丢失用户查看的频率信息
2. **时间模糊** - 无法知道用户何时查看过
3. **调试困难** - 缺少详细的交互日志

### 改进建议

1. **查看计数** - 显示 "Viewed 3 times"
2. **时间范围** - 显示 "Waited from 10:00 to 10:05"
3. **详细日志** - 提供详细的交互日志（可折叠）
4. **查看标记** - 在输出中标记用户查看的时间点

### 相关测试

- `unified_exec_empty_then_non_empty_after` - 空/非空组合
