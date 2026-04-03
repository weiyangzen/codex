# Snapshot Research: interrupt_clears_unified_exec_wait_streak

## 场景与职责

此快照测试验证中断操作如何清除统一执行等待序列（Unified Exec Wait Streak）。当用户在 Codex 执行任务时按下中断键（如 Esc），系统需要正确处理正在等待执行的命令序列的状态。

**注意**：根据代码库分析，实际测试名称为 `interrupt_preserves_unified_exec_wait_streak`，验证中断操作保留（而非清除）等待序列的状态。这可能是文档需求中的笔误。

测试场景：
- Codex 正在执行一个回合，包含 Unified Exec 命令
- 用户按下中断键（Esc）中断当前回合
- 系统需要正确处理 Unified Exec 的等待状态
- 验证中断后等待序列的状态是否正确保留或清除

## 功能点目的

1. **中断状态处理**：确保中断操作正确处理 Unified Exec 等待状态
2. **状态一致性**：保持等待序列在中断后的状态一致性
3. **用户体验**：确保用户中断后系统状态可预期
4. **数据完整性**：防止中断导致的状态丢失或损坏

## 具体技术实现

### 关键流程

```
TurnStarted → UnifiedExecStartup → TerminalInteraction → TurnAborted(Interrupted) → 状态处理
```

### Unified Exec 等待状态数据结构

```rust
// 统一执行等待状态
struct UnifiedExecWaitState {
    command_display: String,
}

// 统一执行等待序列
#[derive(Clone, Debug)]
struct UnifiedExecWaitStreak {
    process_id: String,
    command_display: Option<String>,
}

// 统一执行进程摘要
struct UnifiedExecProcessSummary {
    key: String,
    call_id: String,
    command_display: String,
    recent_chunks: Vec<String>,
}
```

### 中断处理逻辑

```rust
// 当接收到 TurnAborted 事件时
fn handle_turn_aborted(&mut self, event: TurnAbortedEvent) {
    match event.reason {
        TurnAbortReason::Interrupted => {
            // 处理中断逻辑
            // 根据 submit_pending_steers_after_interrupt 标志决定如何处理
            if self.submit_pending_steers_after_interrupt {
                // 提交待处理的 steer 指令
            } else {
                // 恢复等待序列到输入框
            }
        }
        // 其他中止原因...
    }
}
```

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 测试定义和快照断言 |
| `codex-rs/tui/src/chatwidget.rs` | ChatWidget 主逻辑，处理中断事件 |
| `codex-rs/tui/src/chatwidget/interrupts.rs` | 中断管理逻辑 |

### 关键函数

- `ChatWidget::handle_codex_event()` - 处理 TurnAborted 事件
- `begin_unified_exec_startup()` - 测试辅助函数，开始 Unified Exec
- `terminal_interaction()` - 测试辅助函数，模拟终端交互
- `end_exec()` - 测试辅助函数，结束执行

### 测试代码位置

```rust
// codex-rs/tui/src/chatwidget/tests.rs
async fn interrupt_preserves_unified_exec_wait_streak_snapshot() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;

    chat.handle_codex_event(Event {
        id: "turn-1".into(),
        msg: EventMsg::TurnStarted(TurnStartedEvent {
            turn_id: "turn-1".to_string(),
            model_context_window: None,
            collaboration_mode_kind: ModeKind::Default,
        }),
    });

    let begin = begin_unified_exec_startup(&mut chat, "call-1", "process-1", "just fix");
    terminal_interaction(&mut chat, "call-1a", "process-1", "");

    // 模拟中断
    chat.handle_codex_event(Event {
        id: "turn-1".into(),
        msg: EventMsg::TurnAborted(codex_protocol::protocol::TurnAbortedEvent {
            turn_id: Some("turn-1".to_string()),
            reason: TurnAbortReason::Interrupted,
        }),
    });

    end_exec(&mut chat, begin, "", "", 0);
    let cells = drain_insert_history(&mut rx);
    let combined = cells
        .iter()
        .map(|lines| lines_to_single_string(lines))
        .collect::<Vec<_>>()
        .join("\n");
    let snapshot = format!("cells={}\n{combined}", cells.len());
    assert_snapshot!("interrupt_preserves_unified_exec_wait_streak", snapshot);
}
```

## 依赖与外部交互

### 内部依赖

- `UnifiedExecWaitState` - 统一执行等待状态
- `UnifiedExecWaitStreak` - 统一执行等待序列
- `TurnAbortedEvent` - 回合中止事件
- `TurnAbortReason::Interrupted` - 中断原因

### 外部交互

- **codex-core**：接收回合中止事件
- **终端模拟器**：Unified Exec 与终端的交互

## 风险、边界与改进建议

### 潜在风险

1. **状态竞争**：中断信号和执行完成信号可能同时到达
2. **状态丢失**：中断处理不当可能导致等待序列状态丢失
3. **死锁**：中断处理逻辑可能与其他状态机产生死锁

### 边界情况

- 中断时 Unified Exec 正处于不同阶段（启动、执行、等待输入）
- 多个 Unified Exec 进程同时运行时的中断
- 快速连续多次中断
- 中断后重新提交相同命令

### 改进建议

1. **状态机优化**：
   - 使用更明确的状态机管理 Unified Exec 生命周期
   - 添加状态转换日志便于调试
   - 实现状态恢复机制

2. **用户体验**：
   - 中断后显示清晰的恢复选项
   - 提供撤销中断的功能
   - 添加中断原因说明

3. **可观测性**：
   - 记录中断事件和状态变化
   - 提供调试命令查看 Unified Exec 状态
   - 添加性能指标监控

4. **测试覆盖**：
   - 添加更多中断场景测试
   - 测试中断后的状态恢复
   - 并发中断测试

---

**快照内容**：
```
cells=1
• Ran just fix
  └ (no output)
```

**说明**：
- 测试验证中断后历史记录中保留了执行记录
- `cells=1` 表示插入了 1 个历史记录单元格
- `• Ran just fix` 显示执行的命令
- `└ (no output)` 表示命令没有输出
- 这表明中断操作保留了执行历史，用户可以查看中断前执行的命令
