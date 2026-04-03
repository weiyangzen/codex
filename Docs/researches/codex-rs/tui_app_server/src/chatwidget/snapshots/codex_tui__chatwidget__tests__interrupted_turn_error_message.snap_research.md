# Snapshot Research: interrupted_turn_error_message

## 场景与职责

此快照测试验证当回合被用户中断时，系统如何显示友好的错误提示信息。这是提升用户体验的重要功能，确保用户在中断操作后知道如何继续与 Codex 交互。

测试场景：
- Codex 正在执行一个回合（如生成代码、执行命令等）
- 用户按下中断键（Esc）中断当前回合
- 系统显示一个友好的错误消息，提示用户如何继续
- 错误消息包含建议操作和反馈入口

## 功能点目的

1. **中断反馈**：向用户明确告知回合已被中断
2. **操作指导**：提示用户如何继续（告诉模型需要做什么不同）
3. **问题反馈入口**：提供 `/feedback` 命令入口，方便用户报告问题
4. **用户体验优化**：使用友好的语言而非技术性错误描述

## 具体技术实现

### 关键流程

```
TurnStarted → 回合执行中 → TurnAborted(Interrupted) → 插入错误消息到历史记录
```

### 回合中止事件数据结构

```rust
TurnAbortedEvent {
    turn_id: Option<String>,   // 中止的回合 ID
    reason: TurnAbortReason,   // 中止原因
}

enum TurnAbortReason {
    Interrupted,    // 用户中断
    Error,          // 错误
    Timeout,        // 超时
    Cancelled,      // 被取消
    // ...
}
```

### 错误消息生成逻辑

```rust
fn handle_turn_aborted(&mut self, event: TurnAbortedEvent) {
    match event.reason {
        TurnAbortReason::Interrupted => {
            // 插入中断错误消息
            let error_message = format!(
                "■ Conversation interrupted - tell the model what to do differently. \
                 Something went wrong? Hit `/feedback` to report the issue."
            );
            
            self.insert_history_cell(PlainHistoryCell::new(error_message));
            
            // 重置状态
            self.agent_turn_running = false;
            self.update_task_running_state();
            
            // 恢复队列中的消息到输入框
            self.restore_queued_messages();
        }
        // 其他中止原因处理...
    }
}
```

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 测试定义和快照断言 |
| `codex-rs/tui/src/chatwidget.rs` | ChatWidget 主逻辑，处理中断事件 |
| `codex-rs/tui/src/history_cell.rs` | 历史记录单元格定义 |

### 关键函数

- `ChatWidget::handle_codex_event()` - 处理 TurnAborted 事件
- `ChatWidget::insert_history_cell()` - 插入历史记录单元格
- `lines_to_single_string()` - 测试辅助函数，将行转换为字符串
- `drain_insert_history()` - 测试辅助函数，获取插入的历史记录

### 测试代码位置

```rust
// codex-rs/tui/src/chatwidget/tests.rs
async fn interrupted_turn_error_message_snapshot() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;

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
    assert!(
        !cells.is_empty(),
        "expected error message to be inserted after interruption"
    );
    let last = lines_to_single_string(cells.last().unwrap());
    assert_snapshot!("interrupted_turn_error_message", last);
}
```

## 依赖与外部交互

### 内部依赖

- `codex_protocol::protocol::TurnAbortedEvent` - 回合中止事件
- `codex_protocol::protocol::TurnAbortReason` - 中止原因枚举
- `PlainHistoryCell` - 普通历史记录单元格

### 外部交互

- **codex-core**：接收回合中止事件
- **用户输入**：用户通过按键触发中断

## 风险、边界与改进建议

### 潜在风险

1. **消息过于频繁**：频繁中断可能导致错误消息堆积
2. **信息不足**：当前消息可能不够具体，用户不知道具体发生了什么
3. **语言单一**：当前消息为英文，非英语用户可能理解困难

### 边界情况

- 回合刚开始就中断
- 回合即将完成时中断
- 连续快速多次中断
- 中断时有待处理的 steer 指令

### 改进建议

1. **消息优化**：
   - 根据中断时机的不同显示不同的提示
   - 添加中断原因说明（如 "响应生成已中断"）
   - 提供具体的操作建议（如 "您可以重新描述需求"）

2. **国际化**：
   - 支持多语言错误消息
   - 根据系统语言自动选择

3. **交互改进**：
   - 添加快速重试按钮/快捷方式
   - 提供中断前状态的摘要
   - 支持撤销中断（如果技术上可行）

4. **可访问性**：
   - 使用图标增强消息识别度
   - 支持屏幕阅读器朗读
   - 考虑色盲用户的视觉体验

---

**快照内容**：
```
■ Conversation interrupted - tell the model what to do differently. Something went wrong? Hit `/feedback` to report the issue.
```

**说明**：
- `■` 符号表示这是一条信息/警告消息（区别于普通对话）
- "Conversation interrupted" 明确告知用户对话已被中断
- "tell the model what to do differently" 提示用户可以继续操作，告诉模型需要做什么不同
- "Something went wrong? Hit `/feedback` to report the issue" 提供问题反馈入口
- 整体语气友好，避免使用技术性错误描述，适合普通用户理解
