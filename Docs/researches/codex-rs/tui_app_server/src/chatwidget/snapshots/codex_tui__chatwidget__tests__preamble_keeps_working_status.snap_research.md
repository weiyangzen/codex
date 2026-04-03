# Snapshot Research: preamble_keeps_working_status

## 场景与职责

此快照测试验证在序言（preamble）消息处理期间，工作状态指示器的正确保持。当 Codex 开始处理任务时，可能会先输出序言文本，随后才进入实际的执行阶段。此测试确保在序言提交到历史记录后，状态行能够正确恢复显示工作状态。

测试场景：
- 任务开始（`on_task_started()`）
- 接收序言消息增量（`on_agent_message_delta("Preamble line\n")`）
- 提交刻度触发历史记录插入（`on_commit_tick()`）
- 完成助手消息（`complete_assistant_message`，阶段为 Commentary）
- 验证状态行在序言完成后仍然显示工作状态

## 功能点目的

1. **状态连续性**：确保序言处理不会中断工作状态的显示
2. **用户反馈**：让用户清楚地知道 Codex 仍在处理中，即使主要输出尚未开始
3. **回归防护**：防止在序言提交后状态指示器被意外隐藏
4. **视觉一致性**：保持 UI 在不同处理阶段的一致性

## 具体技术实现

### 关键流程

1. **序言处理流程**：
   ```
   TurnStarted → on_task_started() → 显示 Working 状态
   ↓
   AgentMessageDelta (preamble) → 累积文本
   ↓
   on_commit_tick() → 提交到历史记录
   ↓
   complete_assistant_message (Commentary) → 完成消息
   ↓
   状态行仍然显示 Working
   ```

2. **状态行渲染**：
   - 使用 `TestBackend` 创建虚拟终端
   - 调用 `chat.render()` 渲染整个 ChatWidget
   - 通过 `terminal.backend()` 获取渲染输出
   - 验证 `"• Working (0s • esc to interrupt)"` 仍然可见

### 数据结构

```rust
pub enum MessagePhase {
    Commentary,  // 评论/序言阶段
    Planning,
    Coding,
    // ...
}

// 测试中的关键调用
chat.on_task_started();
chat.on_agent_message_delta("Preamble line\n".to_string());
chat.on_commit_tick();
complete_assistant_message(
    &mut chat,
    "msg-commentary-snapshot",
    "Preamble line\n",
    Some(MessagePhase::Commentary),
);
```

### 状态管理

```rust
// ChatWidget 中的状态管理
fn on_task_started(&mut self) {
    self.bottom_pane.show_status_indicator();
    self.agent_turn_running = true;
    // ...
}

// BottomPane 中的状态指示器控制
fn hide_status_indicator(&mut self);  // 隐藏状态行
fn status_indicator_visible(&self) -> bool;  // 检查可见性
```

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 测试定义（tui，line ~3955） |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试定义（tui_app_server，line ~3968） |
| `codex-rs/tui/src/chatwidget.rs` | ChatWidget 事件处理实现 |
| `codex-rs/tui/src/bottom_pane/mod.rs` | 底部面板和状态指示器实现 |

### 关键函数

- `ChatWidget::on_task_started()` - 任务开始处理
- `ChatWidget::on_agent_message_delta()` - 处理消息增量
- `ChatWidget::on_commit_tick()` - 提交累积内容到历史记录
- `complete_assistant_message()` - 测试辅助函数，完成助手消息
- `BottomPane::hide_status_indicator()` - 隐藏状态指示器
- `BottomPane::status_indicator_visible()` - 检查状态指示器可见性

### 相关测试

```rust
// codex-rs/tui/src/chatwidget/tests.rs
#[tokio::test]
async fn preamble_keeps_working_status_snapshot() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
    chat.thread_id = Some(ThreadId::new());

    // Regression sequence: a preamble line is committed to history before any exec/tool event.
    // After commentary completes, the status row should be restored before subsequent work.
    chat.on_task_started();
    chat.on_agent_message_delta("Preamble line\n".to_string());
    chat.on_commit_tick();
    drain_insert_history(&mut rx);
    complete_assistant_message(
        &mut chat,
        "msg-commentary-snapshot",
        "Preamble line\n",
        Some(MessagePhase::Commentary),
    );

    let height = chat.desired_height(80);
    let mut terminal = ratatui::Terminal::new(ratatui::backend::TestBackend::new(80, height))
        .expect("create terminal");
    terminal
        .draw(|f| chat.render(f.area(), f.buffer_mut()))
        .expect("render chatwidget");
    assert_snapshot!("preamble_keeps_working_status", terminal.backend());
}
```

## 依赖与外部交互

### 内部依赖

- `ratatui::backend::TestBackend` - 测试用的终端后端
- `MessagePhase::Commentary` - 消息阶段标识
- `ThreadId` - 线程标识

### 外部交互

- **事件系统**：处理 `TurnStarted`、`AgentMessageDelta` 等事件
- **历史记录**：通过 `drain_insert_history` 管理历史记录插入
- **渲染系统**：通过 `ratatui` 进行终端 UI 渲染

## 风险、边界与改进建议

### 潜在风险

1. **状态竞争**：在序言处理和实际执行开始之间可能存在状态竞争条件
2. **隐藏逻辑错误**：`hide_status_indicator` 可能在不当的时候被调用
3. **测试覆盖不足**：需要确保所有消息阶段都能正确处理状态保持

### 边界情况

- 序言消息为空或极长
- 序言后立即跟随执行事件
- 多个序言消息连续出现
- 用户在序言阶段中断任务

### 改进建议

1. **增强测试覆盖**：
   - 添加测试验证 `unified_exec_begin_restores_status_indicator_after_preamble`
   - 测试序言与执行事件交错的情况
   - 测试多个序言消息的累积效果

2. **代码重构**：
   - 考虑将状态管理逻辑提取到单独的模块
   - 添加更明确的状态转换断言

3. **性能优化**：
   - 减少不必要的重绘调用
   - 优化状态检查的频率

---

**快照内容**：
```
"                                                                                "
"• Working (0s • esc to interrupt)                                               "
"                                                                                "
"                                                                                "
"› Ask Codex to do anything                                                      "
"                                                                                "
"  ? for shortcuts                                            100% context left  "
```

**说明**：显示 ChatWidget 在序言消息处理完成后的渲染输出。关键点是 `"• Working (0s • esc to interrupt)"` 行仍然可见，表明工作状态指示器在序言提交后正确保持。底部显示输入提示符和快捷帮助信息。
