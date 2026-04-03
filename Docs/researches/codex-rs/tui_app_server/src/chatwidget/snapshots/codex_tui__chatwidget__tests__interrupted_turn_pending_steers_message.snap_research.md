# Snapshot Research: interrupted_turn_pending_steers_message

## 场景与职责

此快照测试验证当回合被中断且有待处理的 steer 指令时，系统如何显示特定的信息提示。Steer 指令是用户在中途对 Codex 的引导或纠正，此功能确保用户了解这些指令将被提交。

测试场景：
- 用户已向 Codex 发送消息并开始执行
- 在等待响应过程中，用户发送了 steer 指令（中途引导）
- 用户按下中断键（Esc）中断当前回合
- 系统检测到有待处理的 steer 指令需要提交
- 显示特定信息告知用户 steer 指令将被提交

## 功能点目的

1. **Steer 指令状态通知**：告知用户 steer 指令将被提交
2. **中断原因说明**：解释中断是为了提交待处理的引导指令
3. **预期管理**：让用户知道接下来会发生什么
4. **区分场景**：与普通的回合中断消息区分开来

## 具体技术实现

### 关键流程

```
TurnStarted → pending_steers 入队 → submit_pending_steers_after_interrupt 标记 → 
TurnAborted(Interrupted) → 检查标记 → 显示 steer 提交消息
```

### Steer 指令数据结构

```rust
// 待处理的 Steer
struct PendingSteer {
    user_message: UserMessage,
    compare_key: PendingSteerCompareKey,
}

// ChatWidget 中的 steer 相关状态
struct ChatWidget {
    pending_steers: VecDeque<PendingSteer>,  // 待处理的 steer 队列
    submit_pending_steers_after_interrupt: bool, // 中断后提交 steer 的标志
    // ...
}
```

### 中断处理逻辑（带 steer）

```rust
fn handle_turn_aborted(&mut self, event: TurnAbortedEvent) {
    if event.reason == TurnAbortReason::Interrupted {
        // 检查是否有待提交的 steer 指令
        if self.submit_pending_steers_after_interrupt && !self.pending_steers.is_empty() {
            // 显示 steer 提交信息
            let info_message = "• Model interrupted to submit steer instructions.";
            self.insert_history_cell(PlainHistoryCell::new(info_message));
            
            // 提交 steer 指令
            self.submit_pending_steers();
        } else {
            // 显示普通中断消息
            let error_message = "■ Conversation interrupted - tell the model what to do differently...";
            self.insert_history_cell(PlainHistoryCell::new(error_message));
            
            // 恢复队列中的消息到输入框
            self.restore_queued_messages();
        }
        
        self.agent_turn_running = false;
        self.update_task_running_state();
    }
}
```

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 测试定义和快照断言 |
| `codex-rs/tui/src/chatwidget.rs` | ChatWidget 主逻辑，处理 steer 和中断 |
| `codex-rs/tui/src/chatwidget/realtime.rs` | 实时对话状态管理，包括 steer 处理 |
| `codex-rs/tui/src/history_cell.rs` | 历史记录单元格定义 |

### 关键函数

- `ChatWidget::handle_codex_event()` - 处理 TurnAborted 事件
- `ChatWidget::submit_pending_steers()` - 提交待处理的 steer 指令
- `pending_steer()` - 测试辅助函数，创建待处理的 steer
- `lines_to_single_string()` - 测试辅助函数，将行转换为字符串

### 测试代码位置

```rust
// codex-rs/tui/src/chatwidget/tests.rs
async fn interrupted_turn_pending_steers_message_snapshot() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
    chat.thread_id = Some(ThreadId::new());
    
    // 添加待处理的 steer 指令
    chat.pending_steers.push_back(pending_steer("steer 1"));
    chat.submit_pending_steers_after_interrupt = true;

    // 模拟回合开始
    chat.handle_codex_event(Event {
        id: "task-1".into(),
        msg: EventMsg::TurnStarted(TurnStartedEvent {
            turn_id: "turn-1".to_string(),
            model_context_window: None,
            collaboration_mode_kind: ModeKind::Default,
        }),
    });

    // 模拟中断
    chat.handle_codex_event(Event {
        id: "task-1".into(),
        msg: EventMsg::TurnAborted(codex_protocol::protocol::TurnAbortedEvent {
            turn_id: Some("turn-1".to_string()),
            reason: TurnAbortReason::Interrupted,
        }),
    });

    let cells = drain_insert_history(&mut rx);
    let info = cells
        .iter()
        .map(|cell| lines_to_single_string(cell))
        .find(|line| line.contains("Model interrupted to submit steer instructions."))
        .expect("expected steer interrupt info message to be inserted");
    assert_snapshot!("interrupted_turn_pending_steers_message", info);
}
```

## 依赖与外部交互

### 内部依赖

- `PendingSteer` - 待处理的 steer 指令
- `PendingSteerCompareKey` - steer 比较键（用于去重）
- `TurnAbortedEvent` - 回合中止事件
- `UserMessage` - 用户消息

### 外部交互

- **codex-core**：接收回合中止事件，提交 steer 指令
- **用户输入**：用户发送 steer 指令并触发中断

## 风险、边界与改进建议

### 潜在风险

1. ** steer 丢失**：中断处理不当可能导致 steer 指令丢失
2. **重复提交**：状态管理不当可能导致 steer 重复提交
3. **顺序问题**：多个 steer 指令的顺序可能在中断后混乱

### 边界情况

- 多个 steer 指令同时待处理
- steer 指令在中断瞬间到达
- 中断后 steer 提交失败
- 快速连续中断多次

### 改进建议

1. **显示优化**：
   - 显示待提交 steer 指令的数量
   - 列出 steer 指令的内容摘要
   - 添加 steer 提交进度指示

2. **交互改进**：
   - 允许用户选择是否提交 steer 指令
   - 提供取消 steer 提交的选项
   - 添加 steer 指令编辑功能

3. **可靠性**：
   - 添加 steer 提交确认机制
   - 实现 steer 指令持久化
   - 添加 steer 提交失败重试

4. **可观测性**：
   - 记录 steer 指令生命周期
   - 提供 steer 历史查看
   - 添加 steer 效果分析

---

**快照内容**：
```
• Model interrupted to submit steer instructions.
```

**说明**：
- `•` 符号表示这是一条信息消息
- "Model interrupted to submit steer instructions" 明确告知用户：
  - 模型已被中断
  - 中断的目的是提交 steer 指令
- 与普通中断消息不同，此消息更加简洁，因为用户已经知道要做什么（发送了 steer 指令）
- 让用户知道他们的 steer 指令将被处理，而不是丢失
