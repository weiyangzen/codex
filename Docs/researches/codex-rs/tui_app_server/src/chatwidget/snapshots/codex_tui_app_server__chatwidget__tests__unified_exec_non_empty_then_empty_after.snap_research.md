# Research: unified_exec_non_empty_then_empty_after Snapshot Test

## 场景与职责

该 snapshot 测试验证 `tui_app_server` 中 `ChatWidget` 组件在**统一执行（Unified Exec）终端交互完成后**的历史记录渲染行为。这是 `unified_exec_non_empty_then_empty_active` 测试的延续，验证：

1. 非空输入后空输入的活动状态（已在 `active` snapshot 中验证）
2. Turn 完成后，活动状态被刷新到历史记录
3. 验证最终的历史记录包含完整的交互信息

此测试确保活动单元格到历史记录的转换正确无误。

## 功能点目的

### 核心功能
- **活动到历史的转换**：将活动单元格的内容转换为历史记录
- **Turn 完成处理**：在 Turn 完成时正确刷新和归档活动状态
- **历史记录累积**：确保所有交互记录都被正确保存

### 业务价值
- 提供完整的交互审计日志
- 确保用户可以在历史记录中回顾所有终端交互
- 维护活动状态和历史记录的一致性

## 具体技术实现

### 测试设置（延续 active 测试）
```rust
// 前面的步骤与 unified_exec_non_empty_then_empty_active 相同
begin_unified_exec_startup(&mut chat, "call-wait-3", "proc-3", "just fix");
terminal_interaction(&mut chat, "call-wait-3a", "proc-3", "pwd\n");
terminal_interaction(&mut chat, "call-wait-3b", "proc-3", "");

// 获取活动状态（用于 active snapshot）
let pre_cells = drain_insert_history(&mut rx);
let active_combined = ...;
assert_snapshot!("unified_exec_non_empty_then_empty_active", active_combined);

// 4. 触发 Turn 完成
chat.handle_codex_event(Event {
    id: "turn-wait-3".into(),
    msg: EventMsg::TurnComplete(TurnCompleteEvent {
        turn_id: "turn-1".to_string(),
        last_agent_message: None,
    }),
});
```

### 历史记录收集
```rust
let post_cells = drain_insert_history(&mut rx);
let mut combined = pre_cells
    .iter()
    .map(|lines| lines_to_single_string(lines))
    .collect::<String>();
let post = post_cells
    .iter()
    .map(|lines| lines_to_single_string(lines))
    .collect::<String>();
if !combined.is_empty() && !post.is_empty() {
    combined.push('\n');
}
combined.push_str(&post);
assert_snapshot!("unified_exec_non_empty_then_empty_after", combined);
```

### Snapshot 输出分析
生成的 snapshot 显示完整历史记录：
```
↳ Interacted with background terminal · just fix
  └ pwd

• Waited for background terminal · just fix
```

关键元素：
- `↳ Interacted with background terminal · just fix`：交互记录
- `└ pwd`：输入的命令
- `• Waited for background terminal · just fix`：等待状态记录

注意：历史记录的顺序是：交互记录在前，等待记录在后。这与 `empty_then_non_empty` 的顺序相反，反映了不同的状态转换路径。

## 关键代码路径与文件引用

### 主要文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs` | `ChatWidget` 主实现，包含 `handle_turn_complete` 处理 |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试实现，包含 `unified_exec_non_empty_then_empty_snapshots` 测试函数 |
| `codex-rs/tui_app_server/src/history_cell.rs` | 历史记录单元格实现 |

### 关键代码路径
```rust
// chatwidget.rs: handle_turn_complete
fn handle_turn_complete(&mut self, ev: TurnCompleteEvent) {
    // 刷新活动单元格到历史记录
    if let Some(active_cell) = self.active_cell.take() {
        // 将活动单元格转换为历史记录
        self.flush_active_cell_to_history(active_cell);
    }
    
    // 重置状态
    self.agent_turn_running = false;
    self.current_status = StatusIndicatorState::idle();
    
    // 清理统一执行进程
    self.unified_exec_processes.clear();
    
    // 发送历史记录插入事件
    self.sync_unified_exec_footer();
}

// 刷新活动单元格
fn flush_active_cell_to_history(&mut self, cell: Box<dyn HistoryCell>) {
    self.app_event_tx.send(AppEvent::InsertHistoryCell(cell));
}
```

### 数据结构
```rust
// TurnCompleteEvent
pub struct TurnCompleteEvent {
    pub turn_id: String,
    pub last_agent_message: Option<String>,
}

// 历史记录单元格
pub trait HistoryCell: Send + Sync {
    fn as_any(&self) -> &dyn std::any::Any;
    fn display_lines(&self, width: usize) -> Vec<Line>;
    fn into_transcript_lines(self: Box<Self>) -> Vec<TranscriptLine>;
}
```

## 依赖与外部交互

### 内部依赖
- `codex_protocol::protocol::TurnCompleteEvent`：Turn 完成事件
- `codex_protocol::protocol::EventMsg::TurnComplete`：事件消息类型

### 外部交互
- `AppEvent::InsertHistoryCell`：插入历史记录单元格事件
- `app_event_tx`：应用事件发送器

### 生命周期
```
ExecCommandBegin → 创建活动单元格
    ↓
TerminalInteraction (非空) → 更新活动单元格
    ↓
TerminalInteraction (空) → 更新等待状态
    ↓
TurnComplete → 刷新活动单元格到历史记录
    ↓
发送 InsertHistoryCell 事件
    ↓
历史记录渲染
```

## 风险、边界与改进建议

### 潜在风险
1. **活动单元格丢失**：如果 TurnComplete 事件丢失，活动单元格可能永远不会被刷新
2. **重复刷新**：如果多个 TurnComplete 事件到达，可能导致重复历史记录
3. **状态不一致**：活动单元格刷新和统一执行进程清理之间可能存在竞态条件

### 边界条件
- Turn 完成时没有活动单元格
- 活动单元格为空（无交互记录）
- 多个 Turn 连续完成
- Turn 完成时仍有进行中的统一执行进程

### 改进建议
1. **增加刷新确认机制**：确保活动单元格被正确刷新后才清理状态
2. **增加重复检测**：防止重复的历史记录插入
3. **增加边界测试**：
   - Turn 完成时没有活动单元格
   - 活动单元格为空
   - 快速连续的 Turn 完成
4. **增加持久化测试**：验证历史记录在应用重启后的恢复

### 相关测试
- `codex_tui_app_server__chatwidget__tests__unified_exec_non_empty_then_empty_active.snap`：活动状态测试
- `codex_tui_app_server__chatwidget__tests__unified_exec_empty_then_non_empty_after.snap`：相反顺序测试
- `codex_tui_app_server__chatwidget__tests__turn_complete_keeps_unified_exec_processes.snap`：Turn 完成后进程保留测试
