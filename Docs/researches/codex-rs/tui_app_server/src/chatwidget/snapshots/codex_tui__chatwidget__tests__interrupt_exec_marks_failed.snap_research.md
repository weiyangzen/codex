# Snapshot Research: interrupt_exec_marks_failed

## 场景与职责

此快照测试验证当用户中断正在执行的命令时，系统如何正确标记该命令为失败状态。这是确保用户能够清楚了解哪些命令被中断、哪些成功完成的重要功能。

测试场景：
- Codex 开始执行一个长时间运行的命令（如 `sleep 1`）
- 命令执行期间显示旋转器（spinner）表示进行中
- 用户按下中断键（Esc）中断当前回合
- 系统将该命令标记为失败并刷新到历史记录
- 历史记录中显示命令执行结果，带有失败标记

## 功能点目的

1. **中断状态可视化**：清晰标记被中断的命令为失败
2. **执行结果展示**：显示命令执行状态（即使被中断）
3. **历史记录完整性**：确保所有命令（包括被中断的）都记录在案
4. **用户体验一致性**：保持与其他失败命令的显示风格一致

## 具体技术实现

### 关键流程

```
ExecCommandBegin → 显示旋转器 → TurnAborted(Interrupted) → 标记失败 → 刷新历史记录
```

### 执行命令事件数据结构

```rust
// 命令开始事件
ExecCommandBeginEvent {
    call_id: String,           // 调用 ID
    process_id: Option<String>, // 进程 ID
    turn_id: String,           // 关联的回合 ID
    command: Vec<String>,      // 命令及参数
    parsed_cmd: Vec<ParsedCommand>, // 解析后的命令
    source: ExecCommandSource, // 命令来源
    cwd: Option<String>,       // 工作目录
}

// 回合中止事件
TurnAbortedEvent {
    turn_id: Option<String>,   // 中止的回合 ID
    reason: TurnAbortReason,   // 中止原因
}

enum TurnAbortReason {
    Interrupted,    // 用户中断
    Error,          // 错误
    Timeout,        // 超时
    // ...
}
```

### 中断处理逻辑

```rust
fn handle_turn_aborted(&mut self, event: TurnAbortedEvent) {
    if event.reason == TurnAbortReason::Interrupted {
        // 中断所有正在运行的命令
        for (call_id, running_cmd) in &self.running_commands {
            // 将活动单元格标记为失败
            if let Some(active_cell) = &mut self.active_cell {
                active_cell.mark_failed();
            }
        }
        
        // 刷新活动单元格到历史记录
        self.flush_active_cell();
        
        // 重置运行状态
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
| `codex-rs/tui/src/chatwidget.rs` | ChatWidget 主逻辑，处理中断事件 |
| `codex-rs/tui/src/exec_cell/mod.rs` | 执行单元格定义和状态管理 |
| `codex-rs/tui/src/exec_cell/render.rs` | 执行单元格渲染 |

### 关键函数

- `ChatWidget::handle_codex_event()` - 处理 TurnAborted 事件
- `ExecCell::mark_failed()` - 标记执行单元格为失败
- `begin_exec()` - 测试辅助函数，开始执行命令
- `lines_to_single_string()` - 测试辅助函数，将行转换为字符串

### 测试代码位置

```rust
// codex-rs/tui/src/chatwidget/tests.rs
async fn interrupt_exec_marks_failed_snapshot() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;

    // 开始一个长时间运行的命令
    begin_exec(&mut chat, "call-int", "sleep 1");

    // 模拟中断
    chat.handle_codex_event(Event {
        id: "call-int".into(),
        msg: EventMsg::TurnAborted(codex_protocol::protocol::TurnAbortedEvent {
            turn_id: Some("turn-1".to_string()),
            reason: TurnAbortReason::Interrupted,
        }),
    });

    let cells = drain_insert_history(&mut rx);
    assert!(
        !cells.is_empty(),
        "expected finalized exec cell to be inserted into history"
    );

    // 验证第一个插入的单元格是失败标记的执行
    let exec_blob = lines_to_single_string(&cells[0]);
    assert_snapshot!("interrupt_exec_marks_failed", exec_blob);
}
```

## 依赖与外部交互

### 内部依赖

- `codex_protocol::protocol::ExecCommandBeginEvent` - 命令开始事件
- `codex_protocol::protocol::TurnAbortedEvent` - 回合中止事件
- `codex_protocol::protocol::TurnAbortReason` - 中止原因枚举
- `ExecCell` - 执行单元格

### 外部交互

- **codex-core**：接收命令执行事件和中止事件
- **操作系统**：实际执行命令的进程

## 风险、边界与改进建议

### 潜在风险

1. **状态同步问题**：中断信号可能在中途到达，导致状态不一致
2. **输出丢失**：中断时命令可能已有部分输出，需要正确处理
3. **资源泄漏**：被中断的命令可能留下僵尸进程

### 边界情况

- 命令刚刚开始执行时中断
- 命令即将完成时中断
- 多个命令同时执行时的中断
- 嵌套命令执行时的中断

### 改进建议

1. **显示优化**：
   - 使用红色 ✗ 符号明确标记失败
   - 显示命令执行时长（即使被中断）
   - 保留中断时已产生的输出

2. **交互改进**：
   - 提供重新执行被中断命令的快捷方式
   - 允许用户查看中断时的部分输出
   - 添加中断确认提示（对于长时间运行的命令）

3. **资源管理**：
   - 确保被中断的命令进程被正确清理
   - 添加进程监控防止资源泄漏
   - 实现命令执行超时机制

4. **可观测性**：
   - 记录中断事件和命令状态
   - 提供命令执行历史查看
   - 添加性能分析

---

**快照内容**：
```
• Ran sleep 1
  └ (no output)
```

**说明**：
- `• Ran sleep 1` 表示执行的命令
- `└ (no output)` 表示命令没有输出（因为被中断）
- 虽然快照中没有明确显示失败标记，但在实际 UI 中：
  - 命令前的符号会从旋转器变为红色 ✗
  - 状态栏会显示中断提示
- 用户可以从历史记录中清楚看到该命令被中断执行
